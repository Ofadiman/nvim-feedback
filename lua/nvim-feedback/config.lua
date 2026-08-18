local M = {}

local defaults = {
  window = {
    width = 0.5,
    height = 0.5,
  },
}

local current = vim.deepcopy(defaults)
local rejected = {}
local initialized = false

local function resolve_fraction(name, value, fallback)
  if type(value) ~= "number" or value <= 0 or value >= 1 then
    table.insert(rejected, { name = name, value = value, substitute = fallback })
    return fallback
  end

  return value
end

function M.resolve(opts)
  local resolved = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  rejected = {}
  resolved.window.width = resolve_fraction("window.width", resolved.window.width, defaults.window.width)
  resolved.window.height = resolve_fraction("window.height", resolved.window.height, defaults.window.height)
  current = resolved
end

function M.window()
  return current.window
end

function M.rejected()
  return rejected
end

function M.mark_initialized()
  initialized = true
end

function M.is_initialized()
  return initialized
end

return M
