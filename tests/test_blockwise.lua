local store = require("nvim-feedback.store")

local FILE_LINES = { "alpha = 1", "b", "gamma = 3" }

local child = MiniTest.new_child_neovim()
local repository = nil
local file_path = nil

local function create_repository()
  repository = vim.fn.tempname()
  vim.fn.mkdir(repository, "p")
  vim.system({ "git", "init", "--quiet", "--initial-branch=main", repository }):wait()
  file_path = vim.fs.joinpath(repository, "values.txt")
  vim.fn.writefile(FILE_LINES, file_path)
end

local function remove_repository()
  vim.fn.delete(repository, "rf")
end

local function read_feedback()
  local raw = table.concat(vim.fn.readfile(vim.fs.joinpath(repository, "feedback.json")), "\n")
  return vim.json.decode(raw).feedback
end

local function comment_on_block(cursor, keys)
  child.api.nvim_win_set_cursor(0, cursor)
  child.type_keys("<C-v>", keys, "Q")
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Align these values" })
    vim.cmd.write()
  ]])
end

local function highlighted_ranges()
  return child.lua(
    [[
    local buffer = vim.fn.bufnr(...)
    local namespace = vim.api.nvim_create_namespace("nvim-feedback")
    local ranges = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })) do
      local details = mark[4]
      if details.hl_group or details.line_hl_group then
        table.insert(ranges, {
          start_row = mark[2],
          start_col = mark[3],
          end_row = details.end_row,
          end_col = details.end_col,
          line_hl_group = details.line_hl_group,
        })
      end
    end
    return ranges
  ]],
    { file_path }
  )
end

local tests = MiniTest.new_set()

tests["add()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      create_repository()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        local feedback = require("nvim-feedback")
        feedback.setup()
        vim.keymap.set("x", "Q", feedback.add)
      ]])
      child.cmd("edit " .. vim.fn.fnameescape(file_path))
    end,
    post_case = remove_repository,
    post_once = child.stop,
  },
})

tests["add()"]["records the columns and text that a blockwise selection covers on each line"] = function()
  comment_on_block({ 1, 1 }, "2jll")

  local feedback = read_feedback()
  MiniTest.expect.equality(#feedback, 1)
  MiniTest.expect.equality(feedback[1].range, {
    start_line = 1,
    end_line = 3,
    columns = {
      { start_col = 1, end_col = 4 },
      { start_col = 1, end_col = 1 },
      { start_col = 1, end_col = 4 },
    },
  })
  MiniTest.expect.equality(feedback[1].anchor.selected_block, { "lph", "", "amm" })
  MiniTest.expect.equality(feedback[1].anchor.selected_lines, FILE_LINES)
  MiniTest.expect.equality(feedback[1].anchor.selected_text, nil)
end

tests["add()"]["extends every line of a blockwise selection to its end after $"] = function()
  comment_on_block({ 1, 6 }, "2j$")

  local feedback = read_feedback()
  MiniTest.expect.equality(feedback[1].range.columns, {
    { start_col = 6, end_col = 9 },
    { start_col = 1, end_col = 1 },
    { start_col = 6, end_col = 9 },
  })
  MiniTest.expect.equality(feedback[1].anchor.selected_block, { "= 1", "", "= 3" })
end

tests["add()"]["highlights only the covered text of each line of a blockwise comment"] = function()
  comment_on_block({ 1, 1 }, "2jll")

  MiniTest.expect.equality(highlighted_ranges(), {
    { start_row = 0, start_col = 1, end_row = 0, end_col = 4 },
    { start_row = 2, start_col = 1, end_row = 2, end_col = 4 },
  })
end

tests["write()"] = MiniTest.new_set({
  hooks = {
    pre_case = create_repository,
    post_case = remove_repository,
  },
})

local function block_feedback(columns)
  return {
    feedback = {
      {
        id = "block",
        branch = "main",
        file = "values.txt",
        comment = "Align these values",
        created_at = "2026-11-10T00:00:00Z",
        range = { start_line = 1, end_line = 2, columns = columns },
        anchor = {
          head = vim.NIL,
          selected_lines = { "alpha = 1", "b" },
          selected_block = { "lph", "" },
          context_before = {},
          context_after = { "gamma = 3" },
          diff_hunk = vim.NIL,
        },
      },
    },
  }
end

tests["write()"]["accepts a blockwise comment with columns for each line"] = function()
  local ok = store.write(repository, block_feedback({ { start_col = 1, end_col = 4 }, { start_col = 1, end_col = 1 } }))

  MiniTest.expect.equality(ok, true)
end

tests["write()"]["rejects a blockwise comment whose columns do not match its lines"] = function()
  local ok = store.write(repository, block_feedback({ { start_col = 1, end_col = 4 } }))

  MiniTest.expect.equality(ok, nil)
end

return tests
