local helpers = dofile("tests/helpers.lua")

local child = MiniTest.new_child_neovim()

local function open_editor(value, options)
  options = options or {}
  child.lua(
    [[
    local value, options = ...
    _G.saved = {}
    require("nvim-feedback.ui").open(value, function(text)
      table.insert(_G.saved, text)
      if options.failure then
        return nil, options.failure
      end
      return true
    end, { start_insert = options.start_insert })
  ]],
    { value, options }
  )
end

local function window_layout()
  return child.lua([[
    local config = vim.api.nvim_win_get_config(0)
    return { relative = config.relative, width = config.width, height = config.height, row = config.row, col = config.col }
  ]])
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

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        _G.notifications = {}
        vim.notify = function(message, level)
          table.insert(_G.notifications, { message = message, level = level })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

tests["open()"] = MiniTest.new_set()

tests["open()"]["opens a centered floating window that fills half of the editor by default"] = function()
  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "editor", width = 40, height = 12, row = 5, col = 20 })
end

tests["open()"]["sizes the window with the configured fractions of the editor"] = function()
  child.lua([[require("nvim-feedback.ui").configure({ window = { width = 0.8, height = 0.25 }, icon = "󰆉" })]])

  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "editor", width = 64, height = 6, row = 8, col = 8 })
end

tests["open()"]["keeps the window inside the editor"] = function()
  child.lua([[require("nvim-feedback.ui").configure({ window = { width = 0.99, height = 0.99 }, icon = "󰆉" })]])

  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "editor", width = 76, height = 20, row = 1, col = 2 })
end

tests["open()"]["shows the icon in the title"] = function()
  open_editor("")

  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
end

tests["open()"]["shows the configured icon in the title"] = function()
  child.lua([[require("nvim-feedback.ui").configure({ window = { width = 0.5, height = 0.5 }, icon = ">" })]])

  open_editor("")

  MiniTest.expect.equality(window_title(), " > AI feedback ")
end

tests["open()"]["leaves the icon out of the title when it is empty"] = function()
  child.lua([[require("nvim-feedback.ui").configure({ window = { width = 0.5, height = 0.5 }, icon = "" })]])

  open_editor("")

  MiniTest.expect.equality(window_title(), " AI feedback ")
end

tests["open()"]["shows the existing comment in an unmodified markdown buffer"] = function()
  open_editor("First line\nSecond line")

  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "First line", "Second line" })
  MiniTest.expect.equality(child.bo.filetype, "markdown")
  MiniTest.expect.equality(child.bo.modified, false)
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

tests["open()"]["starts in insert mode when asked to"] = function()
  open_editor("", { start_insert = true })

  MiniTest.expect.equality(child.fn.mode(), "i")
end

tests["open()"]["stays in normal mode by default"] = function()
  open_editor("")

  MiniTest.expect.equality(child.fn.mode(), "n")
end

tests["open()"]["focuses the open window instead of opening a second one"] = function()
  open_editor("First")
  local window = child.api.nvim_get_current_win()
  child.cmd("wincmd p")

  open_editor("Second")

  MiniTest.expect.equality(child.api.nvim_get_current_win(), window)
  MiniTest.expect.equality(helpers.floating_windows(child), { window })
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "First" })
end

tests["open()"]["opens a new window after the previous one was closed"] = function()
  open_editor("First")
  local window = child.api.nvim_get_current_win()
  child.cmd("quit!")

  open_editor("Second")

  MiniTest.expect.no_equality(child.api.nvim_get_current_win(), window)
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Second" })
end

tests[":write"] = MiniTest.new_set()

tests[":write"]["saves the comment without its surrounding blank lines and keeps the window open"] = function()
  open_editor("")

  helpers.save_comment(child, { "", "", "First line", "", "Second line", "", "" }, "write")

  MiniTest.expect.equality(child.lua_get("_G.saved"), { "First line\n\nSecond line" })
  MiniTest.expect.equality(child.bo.modified, false)
  MiniTest.expect.equality(#helpers.floating_windows(child), 1)
end

tests[":write"]["refuses to save an empty comment"] = function()
  open_editor("")

  helpers.save_comment(child, { "", "  " }, "write")

  MiniTest.expect.equality(child.lua_get("_G.saved"), {})
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "AI feedback cannot be empty", level = vim.log.levels.ERROR },
  })
  MiniTest.expect.equality(child.bo.modified, true)
end

tests[":write"]["reports a failed save and keeps the changes"] = function()
  open_editor("", { failure = "Disk is full" })

  helpers.save_comment(child, { "Comment" }, "write")

  MiniTest.expect.equality(child.lua_get("_G.saved"), { "Comment" })
  MiniTest.expect.equality(helpers.notifications(child), {
    { message = "Disk is full", level = vim.log.levels.ERROR },
  })
  MiniTest.expect.equality(child.bo.modified, true)
end

tests["<Esc>"] = MiniTest.new_set()

tests["<Esc>"]["keeps the window open while the comment has unsaved changes"] = function()
  open_editor("Comment")
  local window = child.api.nvim_get_current_win()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Changed" })

  child.type_keys("<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), { window })
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Changed" })
  MiniTest.expect.equality(child.bo.modified, true)
  MiniTest.expect.equality(helpers.notifications(child), {})
end

tests["<Esc>"]["closes the window once the comment is saved"] = function()
  open_editor("")
  helpers.save_comment(child, { "Comment" }, "write")

  child.type_keys("<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
  MiniTest.expect.equality(child.lua_get("_G.saved"), { "Comment" })
end

tests["<Esc>"]["closes the window of a comment that was not changed"] = function()
  open_editor("Comment")

  child.type_keys("<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
  MiniTest.expect.equality(helpers.notifications(child), {})
end

tests[":quit!"] = MiniTest.new_set()

tests[":quit!"]["closes the window and discards the changes"] = function()
  open_editor("Comment")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Changed" })

  child.cmd("quit!")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
  MiniTest.expect.equality(child.lua_get("_G.saved"), {})
end

return tests
