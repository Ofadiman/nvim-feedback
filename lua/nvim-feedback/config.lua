local M = {}

local opts = {
  window = {
    width = 0.5,
    height = 0.5,
  },
}

function M.parse(user_opts)
  local problems = {}

  if user_opts == nil then
    return opts, problems
  end

  if type(user_opts) ~= "table" then
    table.insert(problems, "opts must be a table")
    return opts, problems
  end

  if user_opts.window ~= nil then
    if type(user_opts.window) ~= "table" then
      table.insert(problems, "window must be a table")
    else
      if user_opts.window.width ~= nil then
        if type(user_opts.window.width) == "number" and user_opts.window.width > 0 and user_opts.window.width < 1 then
          opts.window.width = user_opts.window.width
        else
          table.insert(problems, "window.width must be a number between 0 and 1")
        end
      end

      if user_opts.window.height ~= nil then
        if
          type(user_opts.window.height) == "number"
          and user_opts.window.height > 0
          and user_opts.window.height < 1
        then
          opts.window.height = user_opts.window.height
        else
          table.insert(problems, "window.height must be a number between 0 and 1")
        end
      end
    end
  end

  return opts, problems
end

function M.window()
  return opts.window
end

return M
