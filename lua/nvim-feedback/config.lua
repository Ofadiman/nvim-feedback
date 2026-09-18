local M = {}

function M.parse(opts)
  local config = {
    window = {
      width = 0.5,
      height = 0.5,
    },
  }
  local problems = {}

  if opts == nil then
    return config, problems
  end

  if type(opts) ~= "table" then
    table.insert(problems, "opts must be a table")
    return config, problems
  end

  if opts.window ~= nil then
    if type(opts.window) ~= "table" then
      table.insert(problems, "window must be a table")
    else
      if opts.window.width ~= nil then
        if type(opts.window.width) == "number" and opts.window.width > 0 and opts.window.width < 1 then
          config.window.width = opts.window.width
        else
          table.insert(problems, "window.width must be a number between 0 and 1")
        end
      end

      if opts.window.height ~= nil then
        if type(opts.window.height) == "number" and opts.window.height > 0 and opts.window.height < 1 then
          config.window.height = opts.window.height
        else
          table.insert(problems, "window.height must be a number between 0 and 1")
        end
      end
    end
  end

  return config, problems
end

return M
