local config = require("nvim-feedback.config")

local tests = MiniTest.new_set()

tests["parse()"] = MiniTest.new_set()

tests["parse()"]["returns defaults when opts is nil"] = function()
  local parsed, problems = config.parse(nil)

  MiniTest.expect.equality(parsed, { window = { width = 1, height = 0.3 }, icon = "󰆉" })
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["applies a valid window width"] = function()
  local parsed, problems = config.parse({ window = { width = 0.8 } })

  MiniTest.expect.equality(parsed.window, { width = 0.8, height = 0.3 })
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["reports an out of range window height and keeps the default"] = function()
  local parsed, problems = config.parse({ window = { height = 2 } })

  MiniTest.expect.equality(parsed.window.height, 0.3)
  MiniTest.expect.equality(problems, { "window.height must be a number between 0 and 1" })
end

tests["parse()"]["reports opts that are not a table and keeps the defaults"] = function()
  local parsed, problems = config.parse("wide")

  MiniTest.expect.equality(parsed, { window = { width = 1, height = 0.3 }, icon = "󰆉" })
  MiniTest.expect.equality(problems, { "opts must be a table" })
end

tests["parse()"]["reports a window that is not a table and keeps the defaults"] = function()
  local parsed, problems = config.parse({ window = 0.8 })

  MiniTest.expect.equality(parsed.window, { width = 1, height = 0.3 })
  MiniTest.expect.equality(problems, { "window must be a table" })
end

tests["parse()"]["reports a window width that is not a number and keeps the default"] = function()
  local parsed, problems = config.parse({ window = { width = "80%", height = 0.25 } })

  MiniTest.expect.equality(parsed.window, { width = 1, height = 0.25 })
  MiniTest.expect.equality(problems, { "window.width must be a number between 0 and 1" })
end

tests["parse()"]["accepts window fractions of 1"] = function()
  local parsed, problems = config.parse({ window = { width = 1, height = 1 } })

  MiniTest.expect.equality(parsed.window, { width = 1, height = 1 })
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["reports window fractions of 0 and above 1 and keeps the defaults"] = function()
  local parsed, problems = config.parse({ window = { width = 0, height = 1.5 } })

  MiniTest.expect.equality(parsed.window, { width = 1, height = 0.3 })
  MiniTest.expect.equality(problems, {
    "window.width must be a number between 0 and 1",
    "window.height must be a number between 0 and 1",
  })
end

tests["parse()"]["applies a plain-text icon"] = function()
  local parsed, problems = config.parse({ icon = ">" })

  MiniTest.expect.equality(parsed.icon, ">")
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["accepts an empty icon"] = function()
  local parsed, problems = config.parse({ icon = "" })

  MiniTest.expect.equality(parsed.icon, "")
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["reports an icon that is not a string and keeps the default"] = function()
  local parsed, problems = config.parse({ icon = false })

  MiniTest.expect.equality(parsed.icon, "󰆉")
  MiniTest.expect.equality(problems, { "icon must be a string" })
end

return tests
