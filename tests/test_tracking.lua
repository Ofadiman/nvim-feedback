local helpers = dofile("tests/helpers.lua")

local FILE_LINES = { "local alpha = 1", "local beta = compute(2)", "return alpha + beta" }
local ERROR = vim.log.levels.ERROR

local child = MiniTest.new_child_neovim()
local repository = nil

local function open_file()
  child.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(repository, "values.lua")))
end

local function write_feedback(items)
  helpers.write_feedback(repository, items)
end

local function comment(fields)
  fields.file = "values.lua"
  return helpers.comment(repository, fields)
end

local function ranges()
  return vim.tbl_map(function(item)
    return item.range
  end, helpers.read_feedback(repository))
end

local function trigger(event)
  child.api.nvim_exec_autocmds(event, {})
end

local function invalid_file_error()
  return { message = "Invalid AI feedback file: " .. vim.fs.joinpath(repository, "feedback.json"), level = ERROR }
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

tests["editing"] = MiniTest.new_set()

tests["editing"]["moves a comment with its lines without storing the move before the buffer is saved"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()

  child.type_keys("ggO", "local zero = 0", "<CR>", "local half = 0.5", "<Esc>")

  MiniTest.expect.equality(helpers.virtual_lines(child), {
    { line = 4, text = "󰆉 Explain beta", highlight = "NvimFeedbackText" },
  })
  MiniTest.expect.equality(ranges(), { { start_line = 2, end_line = 2 } })
end

tests["editing"]["marks a comment whose lines were deleted as stale"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()

  child.type_keys("2G", "dd")

  MiniTest.expect.equality(helpers.virtual_lines(child), {
    { line = 2, text = "󰆉 [stale] Explain beta", highlight = "NvimFeedbackStaleText" },
  })
  MiniTest.expect.equality(helpers.signs(child), { { line = 2, highlight = "NvimFeedbackStaleSign" } })
end

tests["saving"] = MiniTest.new_set()

tests["saving"]["stores the new lines of a comment that moved"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()

  child.type_keys("ggO", "local zero = 0", "<CR>", "local half = 0.5", "<Esc>")
  child.cmd("write")

  MiniTest.expect.equality(ranges(), { { start_line = 4, end_line = 4 } })
end

tests["saving"]["stores the new columns of a characterwise comment that moved"] = function()
  write_feedback({
    comment({ comment = "Inline compute", range = { start_line = 2, end_line = 2, start_col = 13, end_col = 20 } }),
  })
  open_file()

  child.type_keys("2G", "I", "  ", "<Esc>")
  child.cmd("write")

  MiniTest.expect.equality(ranges(), { { start_line = 2, end_line = 2, start_col = 15, end_col = 22 } })
  MiniTest.expect.equality(helpers.highlights(child), {
    { start_line = 2, start_col = 15, end_line = 2, end_col = 22 },
  })
end

tests["saving"]["keeps the stored range of a stale comment"] = function()
  write_feedback({
    comment({ comment = "Inline compute", range = { start_line = 2, end_line = 2, start_col = 13, end_col = 20 } }),
  })
  open_file()

  child.type_keys("2G", "cc", "local beta = 2", "<Esc>")
  child.cmd("write")

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 [stale] Inline compute")
  MiniTest.expect.equality(ranges(), { { start_line = 2, end_line = 2, start_col = 13, end_col = 20 } })
  MiniTest.expect.equality(helpers.notifications(child), {})
end

tests["saving"]["shows comments that were added to the feedback file for the buffer"] = function()
  open_file()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })

  child.cmd("write")

  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 Explain beta")
end

tests["saving"]["reports a feedback file that became invalid"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  helpers.write_file(repository, "feedback.json", { "{" })

  child.cmd("write")

  MiniTest.expect.equality(helpers.notifications(child), { invalid_file_error() })
end

tests["saving"]["leaves the stored ranges alone while HEAD is detached"] = function()
  helpers.commit(repository)
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  helpers.git(repository, { "checkout", "--quiet", "--detach" })
  local before = vim.fn.readfile(vim.fs.joinpath(repository, "feedback.json"))

  child.cmd("write")

  MiniTest.expect.equality(vim.fn.readfile(vim.fs.joinpath(repository, "feedback.json")), before)
  MiniTest.expect.equality(helpers.notifications(child), {})
end

tests["opening"] = MiniTest.new_set()

tests["opening"]["stores where the code of a comment moved on disk"] = function()
  write_feedback({
    comment({ comment = "Inline compute", range = { start_line = 2, end_line = 2, start_col = 13, end_col = 20 } }),
  })
  helpers.write_file(repository, "values.lua", { "-- header", "local alpha = 1", "local beta  = compute(2)" })

  open_file()

  MiniTest.expect.equality(helpers.highlights(child), {
    { start_line = 3, start_col = 14, end_line = 3, end_col = 21 },
  })
  MiniTest.expect.equality(ranges(), { { start_line = 3, end_line = 3, start_col = 14, end_col = 21 } })
end

tests["opening"]["keeps a stale characterwise comment on the columns it had"] = function()
  write_feedback({
    comment({ comment = "Inline compute", range = { start_line = 2, end_line = 2, start_col = 13, end_col = 20 } }),
  })
  helpers.write_file(repository, "values.lua", { "local alpha = 1", "local beta = 2" })

  open_file()

  MiniTest.expect.equality(helpers.highlights(child), {
    { start_line = 2, start_col = 13, end_line = 2, end_col = 14 },
  })
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 [stale] Inline compute")
end

tests["opening"]["reports an invalid feedback file once until it is fixed"] = function()
  helpers.write_file(repository, "feedback.json", { "{" })
  open_file()
  child.cmd("edit")
  MiniTest.expect.equality(helpers.notifications(child), { invalid_file_error() })

  write_feedback({})
  child.cmd("edit")
  helpers.write_file(repository, "feedback.json", { "{" })
  child.cmd("edit")

  MiniTest.expect.equality(helpers.notifications(child), { invalid_file_error(), invalid_file_error() })
end

tests["opening"]["shows the comments of a restored session once it has loaded"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  local session = vim.fs.joinpath(repository, "session.vim")
  open_file()
  child.o.sessionoptions = "buffers,curdir"
  child.cmd("mksession " .. vim.fn.fnameescape(session))
  helpers.start_editor(child)

  child.cmd("source " .. vim.fn.fnameescape(session))

  MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.fs.joinpath(repository, "values.lua"))
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 Explain beta")
end

tests["opening"]["waits for a session to finish loading before showing comments"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  child.g.SessionLoad = 1

  open_file()
  MiniTest.expect.equality(helpers.virtual_lines(child), {})

  child.lua("vim.g.SessionLoad = nil")
  trigger("SessionLoadPost")
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 Explain beta")
end

tests["focus"] = MiniTest.new_set()

tests["focus"]["reloads a file that changed on disk and follows its comments"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  helpers.write_file(repository, "values.lua", { "-- one", "-- two", unpack(FILE_LINES) })

  trigger("FocusGained")

  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, 1, false), { "-- one" })
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].line, 4)
  MiniTest.expect.equality(ranges(), { { start_line = 4, end_line = 4 } })
end

tests["focus"]["hides comments that were deleted from the feedback file"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  write_feedback({})

  trigger("FocusGained")

  MiniTest.expect.equality(helpers.virtual_lines(child), {})
end

tests["cursor hold"] = MiniTest.new_set()

tests["cursor hold"]["hides comments that were deleted from the feedback file"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  write_feedback({})

  trigger("CursorHold")

  MiniTest.expect.equality(helpers.virtual_lines(child), {})
end

tests["cursor hold"]["shows the comments of the branch that was checked out"] = function()
  helpers.commit(repository)
  write_feedback({
    comment({ comment = "On main", range = { start_line = 1, end_line = 1 } }),
    comment({ comment = "On feature", branch = "feature", range = { start_line = 2, end_line = 2 } }),
  })
  open_file()

  helpers.git(repository, { "checkout", "--quiet", "-b", "feature" })
  trigger("CursorHold")
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 On feature")

  helpers.git(repository, { "checkout", "--quiet", "main" })
  trigger("CursorHold")
  MiniTest.expect.equality(helpers.virtual_lines(child)[1].text, "󰆉 On main")
end

tests["cursor hold"]["does not redraw the comments when nothing changed"] = function()
  write_feedback({ comment({ comment = "Explain beta", range = { start_line = 2, end_line = 2 } }) })
  open_file()
  child.lua([[vim.api.nvim_buf_clear_namespace(0, vim.api.nvim_create_namespace("nvim-feedback"), 0, -1)]])

  trigger("CursorHold")

  MiniTest.expect.equality(helpers.virtual_lines(child), {})
end

return tests
