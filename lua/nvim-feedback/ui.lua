local M = {}

local NOTIFICATION_TITLE = "nvim-feedback"

local active_window = nil
local settings = require("nvim-feedback.config").parse(nil)

function M.configure(config)
  settings = config
end

function M.notify(message, level)
  vim.notify(message, level, { title = NOTIFICATION_TITLE })
end

function M.comment_lines(comment)
  return vim.tbl_filter(function(line)
    return line:match("%S") ~= nil
  end, vim.split(comment, "\n", { plain = true }))
end

function M.summary(comment, stale, index)
  local lines = M.comment_lines(comment)
  local text = lines[index or 1] or ""
  local hidden = #lines - 1
  if hidden > 0 then
    text = string.format("%s … (+%d %s)", text, hidden, hidden == 1 and "line" or "lines")
  end
  return (stale and "[stale] " or "") .. text
end

function M.labeled(text)
  if settings.icon == "" then
    return text
  end
  return settings.icon .. " " .. text
end

local function close_active_window()
  local window = active_window
  active_window = nil
  if window and vim.api.nvim_win_is_valid(window) then
    vim.api.nvim_win_close(window, true)
  end
end

local function initial_lines(value)
  if value == "" then
    return { "" }
  end
  return vim.split(value, "\n", { plain = true })
end

local function feedback_text(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  while #lines > 1 and lines[1] == "" do
    table.remove(lines, 1)
  end
  while #lines > 1 and lines[#lines] == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

function M.open(value, on_save, options)
  options = options or {}
  if active_window and vim.api.nvim_win_is_valid(active_window) then
    vim.api.nvim_set_current_win(active_window)
    return
  end

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, "nvim-feedback://" .. tostring(vim.uv.hrtime()))
  vim.bo[buffer].buftype = "acwrite"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, initial_lines(value))
  vim.bo[buffer].modified = false

  local window = settings.window
  local max_width = math.max(1, vim.o.columns - 4)
  local max_height = math.max(1, vim.o.lines - 4)
  local width = math.min(max_width, math.max(1, math.floor(vim.o.columns * window.width)))
  local height = math.min(max_height, math.max(1, math.floor(vim.o.lines * window.height)))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local column = math.max(0, math.floor((vim.o.columns - width) / 2))

  active_window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "double",
    title = " " .. M.labeled("AI feedback") .. " ",
    title_pos = "center",
    footer = " :w save · :wq save and close · :q! discard ",
    footer_pos = "center",
    width = width,
    height = height,
    row = row,
    col = column,
  })
  vim.wo[active_window].wrap = true
  vim.wo[active_window].linebreak = true
  vim.wo[active_window].cursorline = true
  vim.wo[active_window].winhl =
    "Normal:NormalFloat,FloatBorder:DiagnosticWarn,FloatTitle:DiagnosticWarn,FloatFooter:Comment"

  vim.keymap.set("n", "<Esc>", function()
    if not vim.bo[buffer].modified then
      close_active_window()
    end
  end, {
    buffer = buffer,
    desc = "Close saved AI feedback",
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buffer,
    callback = function()
      local text = feedback_text(buffer)
      if text:match("^%s*$") then
        M.notify("AI feedback cannot be empty", vim.log.levels.ERROR)
        return
      end

      local ok, save_error = on_save(text)
      if not ok then
        M.notify(save_error, vim.log.levels.ERROR)
        return
      end

      vim.bo[buffer].modified = false
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      active_window = nil
    end,
  })

  vim.api.nvim_win_set_cursor(active_window, { 1, 0 })
  if options.start_insert then
    local window = active_window
    vim.schedule(function()
      if active_window == window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_set_current_win(window)
        vim.cmd.startinsert()
      end
    end)
  end
end

return M
