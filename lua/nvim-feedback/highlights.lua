local M = {}

local RANGE_TINT = 0.15

local LINKS = {
  NvimFeedbackSign = "DiagnosticSignWarn",
  NvimFeedbackText = "DiagnosticVirtualTextWarn",
  NvimFeedbackStaleSign = "DiagnosticSignError",
  NvimFeedbackStaleText = "DiagnosticVirtualTextError",
}

local function blend(foreground, background, alpha)
  local result = 0
  for _, shift in ipairs({ 0x10000, 0x100, 1 }) do
    local front = math.floor(foreground / shift) % 0x100
    local back = math.floor(background / shift) % 0x100
    result = result + math.floor(back + (front - back) * alpha + 0.5) * shift
  end
  return result
end

local function range_highlight()
  local warning = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false }).fg
  if not warning then
    return { link = "CursorLine", default = true }
  end

  local background = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
    or (vim.o.background == "light" and 0xffffff or 0x000000)
  return { bg = blend(warning, background, RANGE_TINT), default = true }
end

function M.define()
  for name, target in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  vim.api.nvim_set_hl(0, "NvimFeedbackRange", range_highlight())
end

return M
