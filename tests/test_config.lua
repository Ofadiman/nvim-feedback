local config = require("nvim-feedback.config")

local tests = MiniTest.new_set()

tests["parse()"] = MiniTest.new_set()

tests["parse()"]["returns defaults when opts is nil"] = function()
  local parsed, problems = config.parse(nil)

  MiniTest.expect.equality(parsed, { window = { width = 0.5, height = 0.5 } })
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["applies a valid window width"] = function()
  local parsed, problems = config.parse({ window = { width = 0.8 } })

  MiniTest.expect.equality(parsed.window, { width = 0.8, height = 0.5 })
  MiniTest.expect.equality(problems, {})
end

tests["parse()"]["reports an out of range window height and keeps the default"] = function()
  local parsed, problems = config.parse({ window = { height = 2 } })

  MiniTest.expect.equality(parsed.window.height, 0.5)
  MiniTest.expect.equality(problems, { "window.height must be a number between 0 and 1" })
end

return tests
