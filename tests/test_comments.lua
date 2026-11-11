local helpers = dofile("tests/helpers.lua")

local FILE_LINES = { "local alpha = 1", "  local beta = 2", "", "return alpha + beta" }
local ERROR = vim.log.levels.ERROR
local INFO = vim.log.levels.INFO

local child = MiniTest.new_child_neovim()
local repository = nil

local function open_file(name)
  child.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(repository, name or "values.lua")))
end

local function write_feedback(items)
  helpers.write_feedback(repository, items)
end

local function comment(fields)
  fields.file = fields.file or "values.lua"
  return helpers.comment(repository, fields)
end

local function call_in_directory(directory, name)
  child.lua(
    [[
    local directory, name = ...
    local project = vim.fn.getcwd()
    vim.cmd.cd(directory)
    require("nvim-feedback")[name]()
    vim.cmd.cd(project)
  ]],
    { directory, name }
  )
end

local function open_scratch_buffer()
  child.cmd("enew")
  child.bo.buftype = "nofile"
end

local function answer_confirm(choice)
  child.lua(
    [[
    local choice = ...
    _G.prompts = {}
    vim.fn.confirm = function(message, choices, default)
      table.insert(_G.prompts, { message = message, choices = choices, default = default })
      return choice
    end
  ]],
    { choice }
  )
end

local function answer_select(choice)
  child.lua(
    [[
    local choice = ...
    vim.ui.select = function(items, opts, on_choice)
      _G.selection = { prompt = opts.prompt, items = vim.tbl_map(opts.format_item, items) }
      on_choice(items[choice])
    end
  ]],
    { choice or 0 }
  )
end

local function stub_picker()
  child.lua([[
    require("nvim-feedback.picker").open = function(root, entries, on_select)
      _G.picker = {
        root = root,
        comments = vim.tbl_map(function(entry)
          return entry.item.comment
        end, entries),
        entries = vim.tbl_map(function(entry)
          return { range = entry.range, stale = entry.stale, lines = entry.lines or vim.NIL }
        end, entries),
      }
      _G.select_comment = function(index)
        on_select(entries[index].item)
      end
    end
  ]])
end

local function select_comment(index)
  child.lua("_G.select_comment(...)", { index })
end

local function statusline()
  return child.lua_get([[require("nvim-feedback").statusline()]])
end

local function window_title()
  return child.lua([[
    local text = {}
    for _, chunk in ipairs(vim.api.nvim_win_get_config(0).title) do
      table.insert(text, chunk[1])
    end
    return table.concat(text)
  ]])
end

local function current_file()
  return child.api.nvim_buf_get_name(0)
end

local function comments()
  return vim.tbl_map(function(item)
    return item.comment
  end, helpers.read_feedback(repository))
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      repository = helpers.create_repository({ ["values.lua"] = FILE_LINES })
      helpers.start_editor(child)
    end,
    post_case = function()
      helpers.remove(repository)
    end,
    post_once = child.stop,
  },
})

tests["add()"] = MiniTest.new_set()

tests["add()"]["comments on the cursor line in normal mode"] = function()
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 4 })

  child.type_keys("<F2>")
  helpers.save_comment(child, { "Explain beta" })

  local feedback = helpers.read_feedback(repository)
  MiniTest.expect.equality(#feedback, 1)
  MiniTest.expect.equality(#feedback[1].id, 64)
  MiniTest.expect.equality(feedback[1].created_at:match("^%d+%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil, true)
  MiniTest.expect.equality(
    { feedback[1].branch, feedback[1].file, feedback[1].comment },
    { "main", "values.lua", "Explain beta" }
  )
  MiniTest.expect.equality(feedback[1].range, { start_line = 2, end_line = 2 })
  MiniTest.expect.equality(feedback[1].anchor, {
    head = vim.NIL,
    selected_lines = { "  local beta = 2" },
    context_before = { "local alpha = 1" },
    context_after = { "", "return alpha + beta" },
    diff_hunk = vim.NIL,
  })
  MiniTest.expect.equality(helpers.virtual_lines(child), {
    { line = 2, text = "  󰆉 Explain beta", highlight = "NvimFeedbackText" },
  })
  MiniTest.expect.equality(helpers.highlights(child), { { start_line = 2, end_line = 2 } })
  MiniTest.expect.equality(helpers.signs(child), {})
  MiniTest.expect.equality(statusline(), "󰆉 1")
end

tests["add()"]["opens the comment window in insert mode"] = function()
  open_file()

  child.type_keys("<F2>")

  MiniTest.expect.equality(#helpers.floating_windows(child), 1)
  MiniTest.expect.equality(child.fn.mode(), "i")
end

tests["add()"]["titles the comment window with the location of the new comment"] = function()
  open_file()

  child.type_keys("Vj", "<F2>")

  MiniTest.expect.equality(window_title(), " 󰆉 New comment · values.lua:1-2 ")
end

tests["add()"]["comments on the whole lines selected with V"] = function()
  open_file()
  child.api.nvim_win_set_cursor(0, { 1, 3 })

  child.type_keys("Vj", "<F2>")
  helpers.save_comment(child, { "Merge these" })

  local feedback = helpers.read_feedback(repository)
  MiniTest.expect.equality(feedback[1].range, { start_line = 1, end_line = 2 })
  MiniTest.expect.equality(feedback[1].anchor.selected_lines, { "local alpha = 1", "  local beta = 2" })
  MiniTest.expect.equality(helpers.highlights(child), { { start_line = 1, end_line = 2 } })
  MiniTest.expect.equality(helpers.signs(child), {})
  MiniTest.expect.equality(helpers.virtual_lines(child), {
    { line = 2, text = "󰆉 Merge these", highlight = "NvimFeedbackText" },
  })
end

tests["add()"]["comments on the characters selected with v"] = function()
  open_file()
  child.api.nvim_win_set_cursor(0, { 4, 7 })

  child.type_keys("v4l", "<F2>")
  helpers.save_comment(child, { "Rename alpha" })

  local feedback = helpers.read_feedback(repository)
  MiniTest.expect.equality(feedback[1].range, { start_line = 4, end_line = 4, start_col = 7, end_col = 12 })
  MiniTest.expect.equality(feedback[1].anchor.selected_text, "alpha")
  MiniTest.expect.equality(helpers.highlights(child), {
    { start_line = 4, start_col = 7, end_line = 4, end_col = 12 },
  })
end

tests["add()"]["comments on characters selected with v across lines"] = function()
  open_file()
  child.api.nvim_win_set_cursor(0, { 1, 6 })

  child.type_keys("vj", "<F2>")
  helpers.save_comment(child, { "Split this" })

  local feedback = helpers.read_feedback(repository)
  MiniTest.expect.equality(feedback[1].range, { start_line = 1, end_line = 2, start_col = 6, end_col = 7 })
  MiniTest.expect.equality(feedback[1].anchor.selected_text, "alpha = 1\n  local")
end

tests["add()"]["covers every byte of a selected multibyte character"] = function()
  helpers.write_file(repository, "words.txt", { "naïve" })
  open_file("words.txt")
  child.api.nvim_win_set_cursor(0, { 1, 2 })

  child.type_keys("v", "<F2>")
  helpers.save_comment(child, { "Drop the diaeresis" })

  local feedback = helpers.read_feedback(repository)
  MiniTest.expect.equality(feedback[1].range, { start_line = 1, end_line = 1, start_col = 2, end_col = 4 })
  MiniTest.expect.equality(feedback[1].anchor.selected_text, "ï")
end

tests["add()"]["shows the first line of a longer comment and counts the other lines that have text"] = function()
  open_file()

  child.type_keys("<F2>")
  helpers.save_comment(child, { "Summary", "", "Details", "  ", "More details" })

  MiniTest.expect.equality(comments(), { "Summary\n\nDetails\n  \nMore details" })
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 Summary (+2 lines)")
end

tests["add()"]["counts a single other line of a comment in the singular"] = function()
  open_file()

  child.type_keys("<F2>")
  helpers.save_comment(child, { "Summary", "Details" })

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 Summary (+1 line)")
end

tests["add()"]["updates the new comment when its window is saved again"] = function()
  open_file()

  child.type_keys("<F2>")
  helpers.save_comment(child, { "Draft" }, "write")
  helpers.save_comment(child, { "Final" }, "write")

  MiniTest.expect.equality(comments(), { "Final" })
end

tests["add()"]["reports a feedback file that became invalid before the comment was saved"] = function()
  open_file()
  child.type_keys("<F2>")

  helpers.write_file(repository, "feedback.json", { "{" })
  helpers.save_comment(child, { "Explain alpha" }, "write")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json"), level = ERROR },
  })
  MiniTest.expect.equality(child.bo.modified, true)
end

tests["add()"]["refuses to comment on a buffer with unsaved changes"] = function()
  open_file()
  child.api.nvim_buf_set_lines(0, 0, 0, false, { "-- header" })

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Save buffer before adding AI feedback", level = ERROR },
  })
  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["add()"]["refuses an empty selection"] = function()
  open_file()
  child.api.nvim_win_set_cursor(0, { 3, 0 })

  child.type_keys("v", "<F2>", "<Esc>", "<C-v>", "<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a non-empty selection", level = ERROR },
    { message = "AI feedback requires a non-empty selection", level = ERROR },
  })
  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["add()"]["refuses a buffer that is not a file"] = function()
  open_scratch_buffer()

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a file buffer", level = ERROR },
  })
end

tests["add()"]["refuses a buffer without a name"] = function()
  child.cmd("enew")

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a named file", level = ERROR },
  })
end

tests["add()"]["refuses a file that was never saved"] = function()
  open_file("new.lua")

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a saved file", level = ERROR },
  })
end

tests["add()"]["refuses a file outside a Git repository"] = function()
  local directory = helpers.temporary_directory()
  helpers.write_file(directory, "values.lua", FILE_LINES)
  child.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(directory, "values.lua")))

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a Git repository", level = ERROR },
  })

  helpers.remove(directory)
end

tests["add()"]["refuses a repository with a detached HEAD"] = function()
  helpers.commit(repository)
  helpers.git(repository, { "checkout", "--quiet", "--detach" })
  open_file()

  child.type_keys("<F2>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a Git branch", level = ERROR },
  })
end

tests["edit()"] = MiniTest.new_set()

tests["edit()"]["saves the edited text of the comment under the cursor"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.type_keys("<F3>")
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Explain beta" })
  MiniTest.expect.equality(child.fn.mode(), "n")
  helpers.save_comment(child, { "Explain beta in detail" })

  MiniTest.expect.equality(comments(), { "Explain beta in detail" })
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "  󰆉 Explain beta in detail")
end

tests["edit()"]["titles the comment window with where the comment is now"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.type_keys("ggO", "local zero = 0", "<Esc>")

  child.type_keys("3G", "<F3>")

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · values.lua:3 ")
end

tests["edit()"]["asks which comment to edit when several overlap the cursor line"] = function()
  write_feedback({
    comment({ comment = "First\nwith details", range = { start_line = 1, end_line = 2 } }),
    comment({ comment = "Second", range = { start_line = 2, end_line = 4 } }),
  })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  answer_select(2)

  child.type_keys("<F3>")

  MiniTest.expect.equality(child.lua_get("_G.selection"), {
    prompt = "Edit AI feedback",
    items = { "L1-L2 First", "L2-L4 Second" },
  })
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Second" })
end

tests["edit()"]["does nothing when the choice of comment is cancelled"] = function()
  write_feedback({
    comment({ comment = "First", range = { start_line = 1, end_line = 2 } }),
    comment({ comment = "Second", range = { start_line = 2, end_line = 4 } }),
  })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  answer_select(nil)

  child.type_keys("<F3>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["edit()"]["reports when no comment overlaps the cursor line"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 4, 0 })

  child.type_keys("<F3>")

  MiniTest.expect.equality(helpers.notifications(child), { { message = "No AI feedback at selection", level = INFO } })
  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["edit()"]["finds a characterwise comment from anywhere on its line in normal mode"] = function()
  write_feedback({
    comment({ comment = "Rename alpha", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 12 } }),
  })
  open_file()
  child.api.nvim_win_set_cursor(0, { 4, 16 })

  child.type_keys("<F3>")

  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Rename alpha" })
end

tests["edit()"]["finds a characterwise comment only where the selected characters overlap it"] = function()
  write_feedback({
    comment({ comment = "Rename alpha", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 12 } }),
  })
  open_file()
  child.api.nvim_win_set_cursor(0, { 4, 15 })
  child.type_keys("v3l", "<F3>", "<Esc>")
  MiniTest.expect.equality(helpers.notifications(child), { { message = "No AI feedback at selection", level = INFO } })

  child.api.nvim_win_set_cursor(0, { 4, 11 })
  child.type_keys("v4l", "<F3>")

  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Rename alpha" })
end

tests["edit()"]["refuses a buffer that is not a file"] = function()
  open_scratch_buffer()

  child.type_keys("<F3>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a file buffer", level = ERROR },
  })
end

tests["edit()"]["reports a comment that was deleted while it was being edited"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.type_keys("<F3>")

  write_feedback({})
  helpers.save_comment(child, { "Explain beta in detail" }, "write")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback no longer exists", level = ERROR },
  })
end

tests["delete()"] = MiniTest.new_set()

tests["delete()"]["deletes the comment under the cursor after confirmation"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  answer_confirm(1)

  child.type_keys("<F4>")

  MiniTest.expect.equality(child.lua_get("_G.prompts"), {
    { message = "Delete selected AI feedback?", choices = "&Delete\n&Cancel", default = 2 },
  })
  MiniTest.expect.equality(comments(), {})
  MiniTest.expect.equality(helpers.virtual_lines(child), {})
  MiniTest.expect.equality(statusline(), "")
end

tests["delete()"]["keeps the comment when deletion is cancelled"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  answer_confirm(2)

  child.type_keys("<F4>")

  MiniTest.expect.equality(comments(), { "Explain beta" })
end

tests["delete()"]["asks which comment to delete when several overlap the selection"] = function()
  write_feedback({
    comment({ comment = "First", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Second", range = { start_line = 2, end_line = 2 } }),
    comment({ comment = "Third", range = { start_line = 4, end_line = 4 } }),
  })
  open_file()
  answer_select(1)
  answer_confirm(1)

  child.type_keys("Vj", "<F4>")

  MiniTest.expect.equality(child.lua_get("_G.selection"), {
    prompt = "Delete AI feedback",
    items = { "L1-L1 First", "L2-L2 Second" },
  })
  MiniTest.expect.equality(comments(), { "Second", "Third" })
end

tests["delete()"]["reports a comment that was deleted before the confirmation"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua(
    [[
    local path = ...
    vim.fn.confirm = function()
      vim.fn.writefile({ vim.json.encode({ feedback = {} }) }, path)
      return 1
    end
  ]],
    { vim.fs.joinpath(repository, "feedback.json") }
  )

  child.type_keys("<F4>")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback no longer exists", level = ERROR },
  })
end

tests["delete()"]["reports when no comment overlaps the cursor line"] = function()
  open_file()

  child.type_keys("<F4>")

  MiniTest.expect.equality(helpers.notifications(child), { { message = "No AI feedback at selection", level = INFO } })
end

tests["delete()"]["reports an invalid feedback file"] = function()
  helpers.write_file(repository, "feedback.json", { "{" })
  open_file()

  child.type_keys("<F4>")

  local message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json")
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = message, level = ERROR },
    { message = message, level = ERROR },
  })
end

tests["delete_all()"] = MiniTest.new_set()

tests["delete_all()"]["deletes every comment on the current branch after confirmation"] = function()
  write_feedback({
    comment({ comment = "First", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Other branch", branch = "feature", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Second", range = { start_line = 4, end_line = 4 } }),
  })
  open_file()
  answer_confirm(1)

  child.lua([[require("nvim-feedback").delete_all()]])

  MiniTest.expect.equality(child.lua_get("_G.prompts"), {
    {
      message = "Delete all 2 AI feedback comments on branch main?",
      choices = "&Delete all\n&Cancel",
      default = 2,
    },
  })
  MiniTest.expect.equality(comments(), { "Other branch" })
  MiniTest.expect.equality(helpers.virtual_lines(child), {})
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Deleted 2 AI feedback comments from branch main", level = INFO },
  })
end

tests["delete_all()"]["reports a feedback file that became invalid before the confirmation"] = function()
  write_feedback({ comment({ comment = "First", range = { start_line = 1, end_line = 1 } }) })
  open_file()
  child.lua(
    [[
    local path = ...
    vim.fn.confirm = function()
      vim.fn.writefile({ "{" }, path)
      return 1
    end
  ]],
    { vim.fs.joinpath(repository, "feedback.json") }
  )

  child.lua([[require("nvim-feedback").delete_all()]])

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json"), level = ERROR },
  })
end

tests["delete_all()"]["counts a single comment in the singular"] = function()
  write_feedback({ comment({ comment = "First", range = { start_line = 1, end_line = 1 } }) })
  open_file()
  answer_confirm(1)

  child.lua([[require("nvim-feedback").delete_all()]])

  MiniTest.expect.equality(child.lua_get("_G.prompts")[1].message, "Delete all 1 AI feedback comment on branch main?")
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Deleted 1 AI feedback comment from branch main", level = INFO },
  })
end

tests["delete_all()"]["keeps the comments when deletion is cancelled"] = function()
  write_feedback({ comment({ comment = "First", range = { start_line = 1, end_line = 1 } }) })
  open_file()
  answer_confirm(2)

  child.lua([[require("nvim-feedback").delete_all()]])

  MiniTest.expect.equality(comments(), { "First" })
  MiniTest.expect.equality(helpers.notifications(child), {})
end

tests["delete_all()"]["reports a branch without comments"] = function()
  write_feedback({
    comment({ comment = "Other branch", branch = "feature", range = { start_line = 1, end_line = 1 } }),
  })
  open_file()
  answer_confirm(1)

  child.lua([[require("nvim-feedback").delete_all()]])

  MiniTest.expect.equality(child.lua_get("_G.prompts"), {})
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "No AI feedback on branch main", level = INFO },
  })
end

tests["delete_all()"]["uses the repository of the working directory when the buffer is not a file"] = function()
  write_feedback({ comment({ comment = "First", range = { start_line = 1, end_line = 1 } }) })
  open_scratch_buffer()
  answer_confirm(1)

  call_in_directory(repository, "delete_all")

  MiniTest.expect.equality(comments(), {})
end

tests["delete_all()"]["reports an invalid feedback file"] = function()
  helpers.write_file(repository, "feedback.json", { "{" })
  open_scratch_buffer()

  call_in_directory(repository, "delete_all")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json"), level = ERROR },
  })
end

tests["delete_all()"]["reports a working directory outside a Git repository"] = function()
  local directory = helpers.temporary_directory()
  open_scratch_buffer()

  call_in_directory(directory, "delete_all")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a Git repository", level = ERROR },
  })

  helpers.remove(directory)
end

tests["delete_all()"]["reports a repository with a detached HEAD"] = function()
  helpers.commit(repository)
  helpers.git(repository, { "checkout", "--quiet", "--detach" })
  open_scratch_buffer()

  call_in_directory(repository, "delete_all")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a Git branch", level = ERROR },
  })
end

tests["find()"] = MiniTest.new_set({
  hooks = {
    pre_case = stub_picker,
  },
})

tests["find()"]["lists the comments on the current branch"] = function()
  helpers.write_file(repository, "other.lua", { "return {}" })
  write_feedback({
    comment({ comment = "First", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Other branch", branch = "feature", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Second", file = "other.lua", range = { start_line = 1, end_line = 1 } }),
  })
  open_file()

  child.lua([[require("nvim-feedback").find()]])

  MiniTest.expect.equality(child.lua_get("_G.picker.root"), repository)
  MiniTest.expect.equality(child.lua_get("_G.picker.comments"), { "First", "Second" })
end

tests["find()"]["passes where each comment is now and which comments are stale"] = function()
  helpers.write_file(repository, "gone.lua", { "return {}" })
  write_feedback({
    comment({ comment = "Moved", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Edited away", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 19 } }),
    comment({ comment = "Deleted file", file = "gone.lua", range = { start_line = 1, end_line = 1 } }),
  })
  helpers.remove(vim.fs.joinpath(repository, "gone.lua"))
  helpers.write_file(repository, "values.lua", { "-- header", unpack(FILE_LINES) })
  open_file()
  child.api.nvim_buf_set_lines(0, 4, 5, false, { "return 0" })

  child.lua([[require("nvim-feedback").find()]])

  local lines = { "-- header", "local alpha = 1", "  local beta = 2", "", "return 0" }
  MiniTest.expect.equality(child.lua_get("_G.picker.entries"), {
    { range = { start_line = 2, end_line = 2 }, stale = false, lines = lines },
    { range = { start_line = 5, end_line = 5, start_col = 7, end_col = 19 }, stale = true, lines = lines },
    { range = { start_line = 1, end_line = 1 }, stale = true, lines = vim.NIL },
  })
end

tests["find()"]["opens the file of the selected comment at its first line"] = function()
  helpers.write_file(repository, "other.lua", { "local other = {}", "  other.value = 1", "return other" })
  write_feedback({
    comment({ comment = "Explain value", file = "other.lua", range = { start_line = 2, end_line = 3 } }),
  })
  open_file()

  child.lua([[require("nvim-feedback").find()]])
  select_comment(1)

  MiniTest.expect.equality(current_file(), vim.fs.joinpath(repository, "other.lua"))
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 2, 0 })
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "  󰆉 Explain value")
end

tests["find()"]["places the cursor on the first character of a characterwise comment"] = function()
  write_feedback({
    comment({ comment = "Rename alpha", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 12 } }),
  })
  open_scratch_buffer()

  call_in_directory(repository, "find")
  select_comment(1)

  MiniTest.expect.equality(current_file(), vim.fs.joinpath(repository, "values.lua"))
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 4, 7 })
end

tests["find()"]["places the cursor on the first column of a blockwise comment"] = function()
  local columns = { { start_col = 6, end_col = 11 }, { start_col = 6, end_col = 11 } }
  write_feedback({
    comment({ comment = "Align", range = { start_line = 1, end_line = 2, columns = columns } }),
  })
  open_file()

  child.lua([[require("nvim-feedback").find()]])
  select_comment(1)

  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 1, 6 })
end

tests["find()"]["jumps to where the code of the comment moved"] = function()
  write_feedback({
    comment({ comment = "Rename alpha", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 12 } }),
  })
  helpers.write_file(repository, "values.lua", { "-- header", "-- more", unpack(FILE_LINES) })
  open_scratch_buffer()

  call_in_directory(repository, "find")
  select_comment(1)

  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 6, 7 })
end

tests["find()"]["jumps to the closest line of a comment whose code is gone"] = function()
  write_feedback({
    comment({ comment = "Rename alpha", range = { start_line = 4, end_line = 4, start_col = 7, end_col = 12 } }),
  })
  helpers.write_file(repository, "values.lua", { "local a = 1" })
  open_scratch_buffer()

  call_in_directory(repository, "find")
  select_comment(1)

  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 1, 7 })
end

tests["find()"]["reports a comment on a file that no longer exists"] = function()
  helpers.write_file(repository, "other.lua", { "return {}" })
  write_feedback({
    comment({ comment = "Explain", file = "other.lua", range = { start_line = 1, end_line = 1 } }),
  })
  helpers.remove(vim.fs.joinpath(repository, "other.lua"))
  open_file()

  child.lua([[require("nvim-feedback").find()]])
  select_comment(1)

  MiniTest.expect.equality(current_file(), vim.fs.joinpath(repository, "values.lua"))
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback file does not exist: other.lua", level = ERROR },
  })
end

tests["find()"]["reports a branch without comments"] = function()
  open_file()

  child.lua([[require("nvim-feedback").find()]])

  MiniTest.expect.equality(child.lua_get("_G.picker"), vim.NIL)
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "No AI feedback on branch main", level = INFO },
  })
end

tests["find()"]["reports an invalid feedback file"] = function()
  helpers.write_file(repository, "feedback.json", { "{" })
  open_scratch_buffer()

  call_in_directory(repository, "find")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json"), level = ERROR },
  })
end

tests["find()"]["reports a working directory outside a Git repository"] = function()
  local directory = helpers.temporary_directory()
  open_scratch_buffer()

  call_in_directory(directory, "find")

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback requires a Git repository", level = ERROR },
  })

  helpers.remove(directory)
end

tests["statusline()"] = MiniTest.new_set()

tests["statusline()"]["counts the comments on the branch of the current buffer"] = function()
  write_feedback({
    comment({ comment = "First", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Other branch", branch = "feature", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "Second", range = { start_line = 4, end_line = 4 } }),
  })
  open_file()

  MiniTest.expect.equality(statusline(), "󰆉 2")
end

tests["statusline()"]["is empty when the branch of the current buffer has no comments"] = function()
  write_feedback({
    comment({ comment = "Other branch", branch = "feature", range = { start_line = 1, end_line = 1 } }),
  })
  open_file()

  MiniTest.expect.equality(statusline(), "")
end

tests["statusline()"]["is empty for a buffer that is not a file in a Git repository"] = function()
  open_scratch_buffer()

  MiniTest.expect.equality(statusline(), "")
end

tests["statusline()"]["is empty when the feedback file is invalid"] = function()
  helpers.write_file(repository, "feedback.json", { "{" })
  open_file()

  MiniTest.expect.equality(statusline(), "")
end

tests["setup()"] = MiniTest.new_set()

tests["setup()"]["titles every message with the plugin name"] = function()
  open_file()
  child.type_keys("<F3>")
  open_scratch_buffer()
  child.type_keys("<F2>")
  child.lua([[require("nvim-feedback").setup()]])

  MiniTest.expect.equality(helpers.notification_titles(child), { "nvim-feedback", "nvim-feedback", "nvim-feedback" })
end

tests["setup()"]["reports a second call"] = function()
  child.lua([[require("nvim-feedback").setup()]])

  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "nvim-feedback setup() cannot be called more than once", level = ERROR },
  })
end

tests["setup()"]["sizes the comment window with the configured fractions of the editor"] = function()
  helpers.start_editor(child, { window = { width = 0.8, height = 0.25 } })
  open_file()

  child.type_keys("<F2>")

  MiniTest.expect.equality(
    child.lua_get([[{ vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0) }]]),
    { 64, 6 }
  )
end

tests["setup()"]["marks comments and the statusline count with the configured icon"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  helpers.start_editor(child, { icon = ">" })

  open_file()

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "  > Explain beta")
  MiniTest.expect.equality(statusline(), "> 1")
end

tests["setup()"]["leaves the icon out of comments and the statusline count when it is empty"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  helpers.start_editor(child, { icon = "" })

  open_file()

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "  Explain beta")
  MiniTest.expect.equality(statusline(), "1")
end

tests["setup()"]["shows the comments of the buffer that was open before it was called"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  child.restart({ "-u", "scripts/minimal_init.lua" })
  open_file()

  child.lua([[require("nvim-feedback").setup()]])

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "  󰆉 Explain beta")
end

return tests
