local picker = require("nvim-feedback.picker")

local TELESCOPE_MODULES = {
  "telescope.actions",
  "telescope.actions.state",
  "telescope.config",
  "telescope.finders",
  "telescope.pickers",
  "telescope.previewers",
}

local telescope = {}

local function install_telescope()
  telescope = {}
  telescope.closed = {}
  package.loaded["telescope.actions"] = {
    select_default = {
      replace = function(_, callback)
        telescope.select_default = callback
      end,
    },
    close = function(prompt_buffer)
      table.insert(telescope.closed, prompt_buffer)
    end,
  }
  package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
      return telescope.selection
    end,
  }
  package.loaded["telescope.config"] = {
    values = {
      generic_sorter = function()
        return { highlighter = "fuzzy" }
      end,
    },
  }
  package.loaded["telescope.finders"] = {
    new_table = function(finder)
      return finder
    end,
  }
  package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(previewer)
      return previewer
    end,
  }
  package.loaded["telescope.pickers"] = {
    new = function(picker_options, picker)
      telescope.picker_options = picker_options
      telescope.picker = picker
      return {
        find = function()
          telescope.found = true
        end,
      }
    end,
  }
end

local function remove_telescope()
  for _, name in ipairs(TELESCOPE_MODULES) do
    package.loaded[name] = nil
  end
end

local function line_comment(file, start_line, selected_lines)
  return {
    file = file,
    comment = "Comment on " .. file,
    range = { start_line = start_line, end_line = start_line + #selected_lines - 1 },
    anchor = { selected_lines = selected_lines },
  }
end

local function entries()
  local finder = telescope.picker.finder
  return vim.tbl_map(finder.entry_maker, finder.results)
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = install_telescope,
    post_case = remove_telescope,
  },
})

tests["open()"] = MiniTest.new_set()

tests["open()"]["opens a picker over the comments in the repository"] = function()
  picker.open("/repository", { line_comment("a.lua", 1, { "local a = 1" }) }, function() end)

  MiniTest.expect.equality(telescope.found, true)
  MiniTest.expect.equality(telescope.picker_options, { cwd = "/repository" })
  MiniTest.expect.equality(telescope.picker.prompt_title, "Search AI feedback")
  MiniTest.expect.equality(telescope.picker.sorter, {})
end

tests["open()"]["matches each comment by its text and points it at its file and range"] = function()
  local comment = line_comment("lua/a.lua", 3, { "local a = 1", "local b = 2" })
  comment.range.start_col = 4
  comment.range.end_col = 7
  comment.anchor.selected_text = "a = 1\nloc"

  picker.open("/repository", { comment }, function() end)

  local entry = entries()[1]
  MiniTest.expect.equality(entry.value, comment)
  MiniTest.expect.equality(entry.ordinal, "Comment on lua/a.lua")
  MiniTest.expect.equality(entry.filename, "/repository/lua/a.lua")
  MiniTest.expect.equality({ entry.lnum, entry.lnend, entry.col }, { 3, 4, 5 })
end

tests["open()"]["lists the location and the commented code of each comment"] = function()
  local characterwise = line_comment("b.lua", 2, { "return value + 1" })
  characterwise.range.start_col = 7
  characterwise.range.end_col = 12
  characterwise.anchor.selected_text = "value"
  local blockwise = line_comment("c.lua", 5, { "alpha = 1", "b" })
  blockwise.range.columns = { { start_col = 1, end_col = 4 }, { start_col = 1, end_col = 1 } }
  blockwise.anchor.selected_block = { "lph", "" }

  picker.open("/repository", {
    line_comment("a.lua", 1, { "local a = 1" }),
    line_comment("a.lua", 3, { "  if a then", "    return a", "  end" }),
    characterwise,
    blockwise,
  }, function() end)

  MiniTest.expect.equality(
    vim.tbl_map(function(entry)
      return entry.display
    end, entries()),
    {
      "a.lua:1 local a = 1",
      "a.lua:3-5 if a then return a end",
      "b.lua:2 value",
      "c.lua:5-6 lph",
    }
  )
  MiniTest.expect.equality(entries()[1].col, 1)
end

tests["open()"]["previews the whole comment as wrapped markdown"] = function()
  picker.open("/repository", { line_comment("a.lua", 1, { "local a = 1" }) }, function() end)
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, false, { relative = "editor", row = 0, col = 0, width = 20, height = 5 })

  telescope.picker.previewer.define_preview(
    { state = { bufnr = buffer, winid = window } },
    { value = { comment = "First line\nSecond line" } }
  )

  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { "First line", "Second line" })
  MiniTest.expect.equality(vim.bo[buffer].filetype, "markdown")
  MiniTest.expect.equality({ vim.wo[window].wrap, vim.wo[window].linebreak }, { true, true })

  vim.api.nvim_win_close(window, true)
  vim.api.nvim_buf_delete(buffer, { force = true })
end

tests["open()"]["closes the picker and passes the selected comment on"] = function()
  local comment = line_comment("a.lua", 1, { "local a = 1" })
  local selected = {}
  picker.open("/repository", { comment }, function(item)
    table.insert(selected, item)
  end)

  MiniTest.expect.equality(telescope.picker.attach_mappings(7), true)
  telescope.selection = entries()[1]
  telescope.select_default()

  MiniTest.expect.equality(telescope.closed, { 7 })
  MiniTest.expect.equality(selected, { comment })
end

tests["open()"]["closes the picker without a selection when nothing matches"] = function()
  local selected = {}
  picker.open("/repository", { line_comment("a.lua", 1, { "local a = 1" }) }, function(item)
    table.insert(selected, item)
  end)

  telescope.picker.attach_mappings(7)
  telescope.select_default()

  MiniTest.expect.equality(telescope.closed, { 7 })
  MiniTest.expect.equality(selected, {})
end

return tests
