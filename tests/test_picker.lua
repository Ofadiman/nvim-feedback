local helpers = dofile("tests/helpers.lua")

local VALUES_LINES = {
  "local M = {}",
  "",
  "local alpha = 1",
  "local beta = compute(2)",
  "",
  "function M.sum()",
  "  return alpha + beta",
  "end",
  "",
  "return M",
}
local TELESCOPE_DEFAULTS = {
  layout_strategy = "vertical",
  layout_config = { vertical = { width = 100, height = 46, preview_cutoff = 0, preview_height = 0.5 } },
}
local PICKER_STATE = [[
  local function window_title(window)
    if not window or not vim.api.nvim_win_is_valid(window) then
      return nil
    end
    local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, 1, false)[1] or ""
    return vim.trim((line:gsub("─", ""):gsub("╭", ""):gsub("╮", "")))
  end

  local function geometry(window)
    local config = vim.api.nvim_win_get_config(window)
    return { row = config.row, col = config.col, width = config.width, height = config.height }
  end

  local function window_state(window, border_window)
    local buffer = vim.api.nvim_win_get_buf(window)
    local namespace = vim.api.nvim_create_namespace("nvim-feedback-preview")
    local numbers, highlights = {}, {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })) do
      local details = mark[4]
      if details.virt_text then
        table.insert(numbers, details.virt_text[1][1])
      elseif details.line_hl_group then
        table.insert(highlights, { lines = { mark[2], details.end_row }, group = details.line_hl_group })
      else
        table.insert(highlights, {
          from = { mark[2], mark[3] },
          to = { details.end_row, details.end_col },
          group = details.hl_group,
        })
      end
    end
    return {
      window = window,
      buffer = buffer,
      lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
      title = window_title(border_window),
      geometry = geometry(window),
      number = vim.wo[window].number,
      wrap = vim.wo[window].wrap,
      linebreak = vim.wo[window].linebreak,
      topline = vim.fn.getwininfo(window)[1].topline,
      treesitter = vim.treesitter.highlighter.active[buffer] ~= nil,
      syntax = vim.bo[buffer].syntax,
      numbers = numbers,
      highlights = highlights,
    }
  end

  local function result_highlights(buffer, group)
    local first_row = 0
    for index, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
      if line ~= "" then
        first_row = index - 1
        break
      end
    end
    local columns = {}
    for _, namespace in pairs(vim.api.nvim_get_namespaces()) do
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })) do
        if mark[4].hl_group == group then
          table.insert(columns, { mark[2] - first_row, mark[3], mark[4].end_col })
        end
      end
    end
    table.sort(columns, function(left, right)
      return left[1] < right[1] or (left[1] == right[1] and left[2] < right[2])
    end)
    return columns
  end

  _G.feedback_picker = function()
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].filetype == "TelescopePrompt" then
        local picker = require("telescope.actions.state").get_current_picker(buffer)
        if not picker or not picker.layout then
          return nil
        end
        local comment = picker.layout.comment
        local preview = picker.layout.preview
        return {
          rows = vim.tbl_filter(function(line)
            return line ~= ""
          end, vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false)),
          stale = result_highlights(picker.results_bufnr, "NvimFeedbackStaleText"),
          matching = result_highlights(picker.results_bufnr, "TelescopeMatching"),
          comment = comment and window_state(comment.winid, comment.border_winid) or nil,
          code = preview and window_state(preview.winid, preview.border and preview.border.winid) or nil,
        }
      end
    end
  end
]]

local child = MiniTest.new_child_neovim()
local repository = nil

local function file_path(name)
  return vim.fs.joinpath(repository, name)
end

local function comment(fields)
  fields.file = fields.file or "values.lua"
  return helpers.comment(repository, fields)
end

local function start_editor(lines, defaults)
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.o.lines = lines or 50
  child.o.columns = 120
  helpers.add_telescope(child, defaults or TELESCOPE_DEFAULTS)
  child.lua(PICKER_STATE)
  child.lua([[require("nvim-feedback").setup()]])
end

local function find(comments)
  helpers.write_feedback(repository, comments)
  child.cmd("edit " .. vim.fn.fnameescape(file_path("values.lua")))
  child.lua([[require("nvim-feedback").find()]])
end

local function wait_for(path, expected)
  child.lua(
    [[
    local path, expected = ...
    vim.wait(3000, function()
      local state = _G.feedback_picker()
      return state ~= nil and vim.deep_equal(vim.tbl_get(state, unpack(path)), expected)
    end, 20)
  ]],
    { path, expected }
  )
  local state = child.lua("return _G.feedback_picker()")
  MiniTest.expect.no_equality(state, vim.NIL)
  MiniTest.expect.equality(vim.tbl_get(state, unpack(path)), expected)
  return state
end

local function wait_until_closed()
  child.lua([[
    vim.wait(3000, function()
      return #vim.tbl_filter(function(window)
        return vim.api.nvim_win_get_config(window).relative ~= ""
      end, vim.api.nvim_list_wins()) == 0
    end, 20)
  ]])
end

local function type_prompt(text)
  child.type_keys(vim.split(text, ""))
end

local function erase_prompt(text)
  child.type_keys(vim.fn["repeat"]({ "<BS>" }, #text))
end

local function expect_stacked(state, borders)
  local comment_window, code = state.comment.geometry, state.code.geometry
  MiniTest.expect.equality(comment_window.row + comment_window.height + borders, code.row)
  MiniTest.expect.equality({ comment_window.col, comment_window.width }, { code.col, code.width })
  MiniTest.expect.equality(comment_window.height, math.floor((comment_window.height + code.height) / 3))
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      repository = helpers.create_repository({
        ["values.lua"] = VALUES_LINES,
        ["lua/long/path.lua"] = VALUES_LINES,
      })
      start_editor()
    end,
    post_case = function()
      helpers.remove(repository)
    end,
    post_once = child.stop,
  },
})

tests["results"] = MiniTest.new_set()

tests["results"]["list the location and the first line of each comment in aligned columns"] = function()
  local comments = {
    comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }),
    comment({
      file = "lua/long/path.lua",
      comment = "Inline this\n\nIt is used once",
      range = { start_line = 6, end_line = 8 },
    }),
    comment({ comment = "Old note", range = { start_line = 1, end_line = 1 } }),
  }
  helpers.write_file(repository, "values.lua", { "local N = {}", unpack(VALUES_LINES, 2) })

  find(comments)

  local state = wait_for({ "rows" }, {
    "  values.lua:1           [stale] Old note",
    "  lua/long/path.lua:6-8  Inline this … (+1 line)",
    "> values.lua:3           Rename alpha",
  })
  MiniTest.expect.equality(state.stale, { { 0, 25, 41 } })
end

tests["results"]["show the line of a comment that best matches the search and highlight the match"] = function()
  find({ comment({ comment = "shortcuts\none\ntwo\nthree", range = { start_line = 1, end_line = 1 } }) })
  wait_for({ "rows" }, { "> values.lua:1  shortcuts … (+3 lines)" })

  type_prompt("one")

  local state = wait_for({ "rows" }, { "> values.lua:1  one … (+3 lines)" })
  local columns = vim.tbl_map(function(highlight)
    return highlight[2]
  end, state.matching)
  MiniTest.expect.equality(vim.tbl_contains(columns, 16), true)
  MiniTest.expect.equality(vim.tbl_contains(columns, 17), true)
  MiniTest.expect.equality(vim.tbl_contains(columns, 18), true)
end

tests["results"]["find comments by their location and by any line of their text"] = function()
  find({
    comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }),
    comment({
      file = "lua/long/path.lua",
      comment = "Inline this\n\nIt is used once",
      range = { start_line = 6, end_line = 8 },
    }),
  })
  wait_for({ "rows", 2 }, "> values.lua:3           Rename alpha")

  type_prompt("path")
  wait_for({ "rows" }, { "> lua/long/path.lua:6-8  Inline this … (+1 line)" })
  erase_prompt("path")
  type_prompt("used once")

  wait_for({ "rows" }, { "> lua/long/path.lua:6-8  It is used once … (+1 line)" })
end

tests["preview"] = MiniTest.new_set()

tests["preview"]["shows the comment in its own window above the code of the file"] = function()
  find({
    comment({
      file = "lua/long/path.lua",
      comment = "Inline this\n\nIt is used once",
      range = { start_line = 6, end_line = 8 },
    }),
  })

  local state = wait_for({ "code", "number" }, true)
  expect_stacked(state, 2)
  MiniTest.expect.equality(state.comment.title, "Comment")
  MiniTest.expect.equality(state.comment.lines, { "Inline this", "", "It is used once" })
  MiniTest.expect.equality({ state.comment.wrap, state.comment.linebreak }, { true, true })
  MiniTest.expect.equality(state.comment.treesitter, true)
  MiniTest.expect.equality(state.code.title, "lua/long/path.lua:6-8")
  MiniTest.expect.equality(state.code.lines, VALUES_LINES)
  MiniTest.expect.equality(state.code.highlights, { { lines = { 5, 7 }, group = "NvimFeedbackRange" } })
  MiniTest.expect.equality(state.code.numbers, {})
  MiniTest.expect.equality(state.code.topline, 3)
  MiniTest.expect.equality(state.code.treesitter, true)
end

tests["preview"]["highlights the characters of a characterwise comment"] = function()
  find({ comment({ comment = "Rename", range = { start_line = 4, end_line = 4, start_col = 13, end_col = 20 } }) })

  wait_for({ "code", "highlights" }, { { from = { 3, 13 }, to = { 3, 20 }, group = "NvimFeedbackRange" } })
end

tests["preview"]["highlights the columns of a blockwise comment"] = function()
  local columns = { { start_col = 6, end_col = 11 }, { start_col = 6, end_col = 10 } }

  find({ comment({ comment = "Align", range = { start_line = 3, end_line = 4, columns = columns } }) })

  wait_for({ "code", "highlights" }, {
    { from = { 2, 6 }, to = { 2, 11 }, group = "NvimFeedbackRange" },
    { from = { 3, 6 }, to = { 3, 10 }, group = "NvimFeedbackRange" },
  })
end

tests["preview"]["shows the code of a stale comment as it was when the comment was written"] = function()
  local comments = { comment({ comment = "Rename sum", range = { start_line = 6, end_line = 6 } }) }
  local lines = vim.deepcopy(VALUES_LINES)
  lines[6] = "function M.total()"
  helpers.write_file(repository, "values.lua", lines)

  find(comments)

  local state = wait_for({ "code", "title" }, "values.lua:6 [stale]")
  MiniTest.expect.equality(state.code.lines, vim.list_slice(VALUES_LINES, 3, 9))
  MiniTest.expect.equality(state.code.numbers, { "3 │ ", "4 │ ", "5 │ ", "6 │ ", "7 │ ", "8 │ ", "9 │ " })
  MiniTest.expect.equality(state.code.highlights, { { lines = { 3, 3 }, group = "NvimFeedbackRange" } })
  MiniTest.expect.equality(state.code.number, false)
  MiniTest.expect.equality(state.comment.lines, { "Rename sum" })
end

tests["preview"]["leaves the code of a file of unknown type unhighlighted"] = function()
  helpers.write_file(repository, "notes.unknown-extension", { "plain text" })

  find({
    comment({ file = "notes.unknown-extension", comment = "Reword", range = { start_line = 1, end_line = 1 } }),
  })

  local state = wait_for({ "code", "lines" }, { "plain text" })
  MiniTest.expect.equality(state.code.treesitter, false)
  MiniTest.expect.equality(state.code.syntax, "")
end

tests["preview"]["follows the selection to another comment"] = function()
  find({
    comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }),
    comment({ comment = "Return early", range = { start_line = 7, end_line = 7 } }),
  })
  wait_for({ "comment", "lines" }, { "Rename alpha" })

  child.type_keys("<C-p>")

  local state = wait_for({ "comment", "lines" }, { "Return early" })
  wait_for({ "code", "title" }, "values.lua:7")
  MiniTest.expect.equality(state.rows[1], "> values.lua:7  Return early")
end

tests["layout"] = MiniTest.new_set()

tests["layout"]["stacks the windows without a gap when Telescope draws no borders"] = function()
  start_editor(50, vim.tbl_extend("force", TELESCOPE_DEFAULTS, { border = false }))

  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })

  expect_stacked(wait_for({ "comment", "lines" }, { "Rename alpha" }), 0)
end

tests["layout"]["shows only the comment when the preview is too small to split"] = function()
  start_editor(10)

  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })

  local state = wait_for({ "code", "lines" }, { "Rename alpha" })
  MiniTest.expect.equality(state.comment, nil)
  MiniTest.expect.equality(state.code.number, false)

  child.type_keys("<Esc>", "<Esc>")
  wait_until_closed()
  MiniTest.expect.equality(#child.api.nvim_list_wins(), 1)
end

tests["layout"]["opens no comment window when Telescope hides the preview"] = function()
  start_editor(50, { layout_strategy = "horizontal", layout_config = { horizontal = { preview_cutoff = 200 } } })

  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })

  local state = wait_for({ "rows" }, { "> values.lua:3  Rename alpha" })
  MiniTest.expect.equality({ state.comment, state.code }, {})
end

tests["layout"]["removes the comment window when a resize makes Telescope hide the preview"] = function()
  start_editor(50, { layout_strategy = "horizontal", layout_config = { horizontal = { preview_cutoff = 100 } } })
  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })
  local before = wait_for({ "comment", "lines" }, { "Rename alpha" })

  child.o.columns = 90
  child.api.nvim_exec_autocmds("VimResized", {})

  local state = wait_for({ "code" }, nil)
  MiniTest.expect.equality(state.comment, nil)
  MiniTest.expect.equality(child.api.nvim_win_is_valid(before.comment.window), false)
end

tests["layout"]["titles the code window with its location when Telescope shows dynamic preview titles"] = function()
  start_editor(50, vim.tbl_extend("force", TELESCOPE_DEFAULTS, { dynamic_preview_title = true }))

  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })

  wait_for({ "code", "title" }, "values.lua:3")
end

tests["layout"]["leaves a custom layout from the Telescope configuration alone"] = function()
  child.lua([[
    local Layout = require("telescope.pickers.layout")
    local function window(enter, row, height)
      local buffer = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(buffer, enter, {
        relative = "editor",
        row = row,
        col = 0,
        width = 100,
        height = height,
        style = "minimal",
      })
      return Layout.Window({ bufnr = buffer, winid = winid })
    end
    require("telescope").setup({
      defaults = {
        create_layout = function(picker)
          return Layout({
            picker = picker,
            mount = function(self)
              self.preview = window(false, 0, 10)
              self.results = window(false, 12, 10)
              self.prompt = window(true, 24, 1)
            end,
            unmount = function(self)
              for _, part in ipairs({ self.preview, self.results, self.prompt }) do
                pcall(vim.api.nvim_win_close, part.winid, true)
              end
            end,
            update = function() end,
          })
        end,
      },
    })
  ]])

  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })

  local state = wait_for({ "code", "lines" }, { "Rename alpha" })
  MiniTest.expect.equality(state.comment, nil)
end

tests["layout"]["splits the preview again after the editor is resized"] = function()
  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })
  local before = wait_for({ "comment", "lines" }, { "Rename alpha" })

  child.o.lines = 40
  child.api.nvim_exec_autocmds("VimResized", {})
  child.lua(
    [[
    local previous = ...
    vim.wait(3000, function()
      local state = _G.feedback_picker()
      return state ~= nil
        and state.comment ~= nil
        and state.comment.window ~= previous
        and vim.deep_equal(state.comment.lines, { "Rename alpha" })
    end, 20)
  ]],
    { before.comment.window }
  )

  local after = child.lua("return _G.feedback_picker()")
  MiniTest.expect.no_equality(after.comment.window, before.comment.window)
  MiniTest.expect.equality(after.comment.lines, { "Rename alpha" })
  MiniTest.expect.equality(after.code.geometry.height < before.code.geometry.height, true)
  expect_stacked(after, 2)
end

tests["layout"]["closes the comment window with the picker"] = function()
  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })
  local state = wait_for({ "comment", "lines" }, { "Rename alpha" })

  child.type_keys("<Esc>", "<Esc>")
  wait_until_closed()

  MiniTest.expect.equality(child.api.nvim_win_is_valid(state.comment.window), false)
  MiniTest.expect.equality(child.api.nvim_buf_is_valid(state.comment.buffer), false)
  MiniTest.expect.equality(#child.api.nvim_list_wins(), 1)
end

tests["selection"] = MiniTest.new_set()

tests["selection"]["opens the selected comment"] = function()
  find({
    comment({ file = "lua/long/path.lua", comment = "Inline this", range = { start_line = 6, end_line = 8 } }),
  })
  wait_for({ "comment", "lines" }, { "Inline this" })

  child.type_keys("<CR>")
  wait_until_closed()

  MiniTest.expect.equality(child.api.nvim_buf_get_name(0), file_path("lua/long/path.lua"))
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 6, 0 })
end

tests["selection"]["does nothing when no comment matches the search"] = function()
  find({ comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }) })
  wait_for({ "comment", "lines" }, { "Rename alpha" })
  type_prompt("zzzz")
  wait_for({ "rows" }, {})

  child.type_keys("<CR>")
  wait_until_closed()

  MiniTest.expect.equality(child.api.nvim_buf_get_name(0), file_path("values.lua"))
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

tests["selection"]["sends the comments to the quickfix list at their current location"] = function()
  local comments = {
    comment({ comment = "Rename alpha", range = { start_line = 3, end_line = 3 } }),
    comment({ comment = "Rename compute", range = { start_line = 4, end_line = 4, start_col = 13, end_col = 20 } }),
  }
  helpers.write_file(repository, "values.lua", { "-- header", unpack(VALUES_LINES) })
  find(comments)
  wait_for({ "rows", 2 }, "> values.lua:4  Rename alpha")

  child.type_keys("<C-q>")
  wait_until_closed()

  local items = child.lua([[
    return vim.tbl_map(function(item)
      return { file = vim.api.nvim_buf_get_name(item.bufnr), lnum = item.lnum, col = item.col }
    end, vim.fn.getqflist())
  ]])
  MiniTest.expect.equality(items, {
    { file = file_path("values.lua"), lnum = 4, col = 1 },
    { file = file_path("values.lua"), lnum = 5, col = 14 },
  })
end

return tests
