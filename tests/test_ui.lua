local helpers = dofile("tests/helpers.lua")

local LONG_PATH = "packages/agent-management/src/features/new-server-class/NewServerClass.page.tsx"

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

local function open_at(start_line, end_line)
  child.lua(
    [[
    local start_line, end_line = ...
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.tbl_map(function(index)
      return "line " .. index
    end, vim.fn.range(1, 30)))
    require("nvim-feedback.ui").open("", function()
      return true
    end, { title = "New comment", location = { file = "a.lua", start_line = start_line, end_line = end_line } })
  ]],
    { start_line, end_line }
  )
end

local function configure(width, height)
  child.lua(
    [[
    local width, height = ...
    require("nvim-feedback.ui").configure({ window = { width = width, height = height }, icon = "󰆉" })
  ]],
    { width, height }
  )
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

local function open_titled(columns, file, start_line, end_line)
  child.o.columns = columns
  child.lua(
    [[
    local location = ...
    require("nvim-feedback.ui").open("", function()
      return true
    end, { title = "Edit comment", location = location })
  ]],
    { { file = file, start_line = start_line, end_line = end_line } }
  )
end

local function window_footer()
  return child.lua([[
    local text = {}
    for _, chunk in ipairs(vim.api.nvim_win_get_config(0).footer) do
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
        _G.notification_titles = {}
        vim.notify = function(message, level, opts)
          table.insert(_G.notifications, { message = message, level = level })
          table.insert(_G.notification_titles, opts and opts.title or vim.NIL)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

tests["open()"] = MiniTest.new_set()

tests["open()"]["centers the window over the current window when it has no comment location"] = function()
  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 4, row = 8, col = 0 })
end

tests["open()"]["sizes the window with the configured fractions of the current window"] = function()
  configure(0.8, 0.25)

  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 62, height = 3, row = 8, col = 8 })
end

tests["open()"]["fills the current window when both fractions are 1"] = function()
  configure(1, 1)

  open_editor("")

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 20, row = 0, col = 0 })
end

tests["open()"]["opens right below the commented lines"] = function()
  open_at(3, 4)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 4, row = 4, col = 0 })
end

tests["open()"]["opens right above the commented lines when there is no room below them"] = function()
  open_at(19, 21)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 4, row = 12, col = 0 })
end

tests["open()"]["shrinks to the free space below the commented lines when neither side has room"] = function()
  configure(1, 1)

  open_at(8, 9)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 11, row = 9, col = 0 })
end

tests["open()"]["shrinks to the free space above the commented lines when it is the larger side"] = function()
  configure(1, 1)

  open_at(15, 16)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 12, row = 0, col = 0 })
end

tests["open()"]["opens below the last screen row of a wrapped line"] = function()
  child.lua([[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "short", string.rep("x", 100) })]])
  child.lua([[
    require("nvim-feedback.ui").open("", function()
      return true
    end, { title = "New comment", location = { file = "a.lua", start_line = 2, end_line = 2 } })
  ]])

  MiniTest.expect.equality(window_layout().row, 3)
end

tests["open()"]["lines up with the text next to the line numbers"] = function()
  child.o.number = true

  open_at(3, 4)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 74, height = 4, row = 4, col = 4 })
end

tests["open()"]["fits the width of a split window"] = function()
  child.cmd("vsplit")
  local width = child.api.nvim_win_get_width(0)

  open_at(3, 4)

  MiniTest.expect.equality(window_layout().width, width - 2)
end

tests["open()"]["centers the window when the commented lines are out of view"] = function()
  open_at(28, 29)

  MiniTest.expect.equality(window_layout(), { relative = "win", width = 78, height = 4, row = 8, col = 0 })
end

tests["open()"]["draws a double border when 'winborder' is not set"] = function()
  open_editor("")

  MiniTest.expect.equality(
    child.api.nvim_win_get_config(0).border,
    { "╔", "═", "╗", "║", "╝", "═", "╚", "║" }
  )
end

tests["open()"]["draws the border that 'winborder' sets"] = function()
  child.o.winborder = "rounded"

  open_editor("")

  MiniTest.expect.equality(
    child.api.nvim_win_get_config(0).border,
    { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
  )
end

tests["open()"]["draws no border when 'winborder' is none"] = function()
  child.o.winborder = "none"

  open_editor("")

  MiniTest.expect.equality(child.api.nvim_win_get_config(0).border, "none")
end

tests["open()"]["shows the full key hints in the footer when they fit the window"] = function()
  child.o.columns = 46

  open_editor("")

  MiniTest.expect.equality(child.api.nvim_win_get_width(0), 44)
  MiniTest.expect.equality(window_footer(), " :w save · :wq save and close · :q! discard ")
end

tests["open()"]["shows only the commands in the footer when the full key hints do not fit"] = function()
  child.o.columns = 45

  open_editor("")

  MiniTest.expect.equality(child.api.nvim_win_get_width(0), 43)
  MiniTest.expect.equality(window_footer(), " :w · :wq · :q! ")
end

tests["open()"]["keeps the shortest footer when even that does not fit the window"] = function()
  configure(0.1, 0.5)

  open_editor("")

  MiniTest.expect.equality(child.api.nvim_win_get_width(0), 6)
  MiniTest.expect.equality(window_footer(), " :w · :wq · :q! ")
end

tests["open()"]["shows the icon in the title"] = function()
  open_editor("")

  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
end

tests["open()"]["shows the given title with the location of the comment"] = function()
  open_titled(80, "a.lua", 3, 5)

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · a.lua:3-5 ")
end

tests["open()"]["shows the whole path of the comment when it fits the title"] = function()
  open_titled(122, LONG_PATH, 8, 8)

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · " .. LONG_PATH .. ":8 ")
end

tests["open()"]["drops leading directories of a path that does not fit the title"] = function()
  open_titled(72, LONG_PATH, 8, 8)

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · .../new-server-class/NewServerClass.page.tsx:8 ")
end

tests["open()"]["shortens the file name when no directory can be dropped"] = function()
  open_titled(42, LONG_PATH, 8, 8)

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · NewServerCla...:8 ")
end

tests["open()"]["leaves the location out of a title too narrow for it"] = function()
  open_titled(22, LONG_PATH, 8, 8)

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment ")
end

tests["open()"]["keeps the fitted location when the unsaved-changes mark appears"] = function()
  open_titled(72, LONG_PATH, 8, 8)

  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Changed" })

  MiniTest.expect.equality(window_title(), " 󰆉 Edit comment · .../new-server-class/NewServerClass.page.tsx:8 [+] ")
  MiniTest.expect.equality(vim.fn.strdisplaywidth(window_title()) <= child.api.nvim_win_get_width(0), true)
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

tests["open()"]["reports whether it opened a window and tells when the window closes"] = function()
  local opened = child.lua([[
    _G.closed = 0
    local options = { on_close = function() _G.closed = _G.closed + 1 end }
    local ui = require("nvim-feedback.ui")
    return { ui.open("First", function() return true end, options), ui.open("Second", function() return true end, options) }
  ]])
  MiniTest.expect.equality(opened, { true, false })
  MiniTest.expect.equality(child.lua_get("_G.closed"), 0)

  child.cmd("quit!")

  MiniTest.expect.equality(child.lua_get("_G.closed"), 1)
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
  MiniTest.expect.equality(#helpers.floating_windows(child), 1)
end

tests[":write"]["marks the title while the comment has unsaved changes"] = function()
  open_editor("Comment")
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")

  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Changed" })
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback [+] ")
  MiniTest.expect.equality(child.api.nvim_win_get_config(0).title_pos, "center")

  helpers.save_comment(child, { "Changed again" }, "write")
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
end

tests[":write"]["clears the unsaved-changes mark when the typed changes are undone"] = function()
  open_editor("Comment")

  child.type_keys("A", "!", "<Esc>")
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback [+] ")
  child.type_keys("u")

  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
end

tests[":write"]["keeps the unsaved-changes mark when the save fails"] = function()
  open_editor("", { failure = "Disk is full" })

  helpers.save_comment(child, { "Comment" }, "write")

  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback [+] ")
end

tests[":write"]["titles its messages with the plugin name"] = function()
  open_editor("", { failure = "Disk is full" })

  helpers.save_comment(child, { "" }, "write")
  helpers.save_comment(child, { "Comment" }, "write")

  MiniTest.expect.equality(helpers.notification_titles(child), { "nvim-feedback", "nvim-feedback" })
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

tests["<Esc>"]["closes a new comment after the typed text is deleted again"] = function()
  open_editor("")

  child.type_keys("i", "a", "<BS>", "<Esc>")
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
  child.type_keys("<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["<Esc>"]["closes an edited comment after its text is typed back to the saved text"] = function()
  open_editor("Comment")

  child.type_keys("A", "!", "<BS>", "<Esc>")
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback ")
  child.type_keys("<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["<Esc>"]["closes a new comment that holds only blank text"] = function()
  open_editor("")

  child.type_keys("i", "  ", "<CR>", "<Esc>", "<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests["<Esc>"]["compares the text with the last saved comment"] = function()
  open_editor("")
  helpers.save_comment(child, { "Draft" }, "write")
  local window = child.api.nvim_get_current_win()

  child.type_keys("A", "!", "<Esc>", "<Esc>")
  MiniTest.expect.equality(helpers.floating_windows(child), { window })
  MiniTest.expect.equality(window_title(), " 󰆉 AI feedback [+] ")
  child.type_keys("A", "<BS>", "<Esc>", "<Esc>")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests[":quit!"] = MiniTest.new_set()

tests[":quit!"]["is not needed with :quit after the typed text is deleted again"] = function()
  open_editor("Comment")

  child.type_keys("A", "!", "<BS>", "<Esc>")
  child.cmd("quit")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
end

tests[":quit!"]["closes the window and discards the changes"] = function()
  open_editor("Comment")
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "Changed" })

  child.cmd("quit!")

  MiniTest.expect.equality(helpers.floating_windows(child), {})
  MiniTest.expect.equality(child.lua_get("_G.saved"), {})
end

return tests
