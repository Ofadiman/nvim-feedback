local M = {}

local NOTIFICATION_TITLE = "nvim-feedback"
local FALLBACK_BORDER = "double"
local FOOTERS = {
  " :w save · :wq save and close · :q! discard ",
  " :w · :wq · :q! ",
}

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
    text = string.format("%s (+%d %s)", text, hidden, hidden == 1 and "line" or "lines")
  end
  return (stale and "[stale] " or "") .. text
end

local function line_numbers(start_line, end_line)
  if end_line ~= start_line then
    return string.format(":%d-%d", start_line, end_line)
  end
  return string.format(":%d", start_line)
end

function M.location(file, start_line, end_line)
  return file .. line_numbers(start_line, end_line)
end

function M.highlight_range(buffer, namespace, range, first, lines)
  local function row(line)
    return line - first
  end

  if range.columns then
    for index, column in ipairs(range.columns) do
      local line = range.start_line + index - 1
      local end_col = math.min(column.end_col, #(lines[line - first + 1] or ""))
      if end_col > column.start_col then
        vim.api.nvim_buf_set_extmark(buffer, namespace, row(line), column.start_col, {
          end_col = end_col,
          hl_group = "NvimFeedbackRange",
          strict = false,
        })
      end
    end
  elseif range.start_col then
    vim.api.nvim_buf_set_extmark(buffer, namespace, row(range.start_line), range.start_col, {
      end_row = row(range.end_line),
      end_col = range.end_col,
      hl_group = "NvimFeedbackRange",
      strict = false,
    })
  else
    vim.api.nvim_buf_set_extmark(buffer, namespace, row(range.start_line), 0, {
      end_row = row(range.end_line),
      line_hl_group = "NvimFeedbackRange",
      strict = false,
    })
  end
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

local function window_title(label, modified)
  return " " .. M.labeled(label) .. (modified and " [+]" or "") .. " "
end

local function fitted_label(label, location, width)
  if not location then
    return label
  end

  local function fits(path)
    return vim.fn.strdisplaywidth(window_title(label .. " · " .. path, true)) <= width
  end

  local lines = line_numbers(location.start_line, location.end_line)
  local parts = vim.split(location.file, "/", { plain = true })
  for first = 1, #parts do
    local path = (first == 1 and "" or ".../") .. table.concat(parts, "/", first) .. lines
    if fits(path) then
      return label .. " · " .. path
    end
  end

  local name = parts[#parts]
  for count = vim.fn.strchars(name) - 1, 1, -1 do
    local path = vim.fn.strcharpart(name, 0, count) .. "..." .. lines
    if fits(path) then
      return label .. " · " .. path
    end
  end
  return label
end

local function window_footer(width)
  for _, footer in ipairs(FOOTERS) do
    if vim.fn.strdisplaywidth(footer) <= width then
      return footer
    end
  end
  return FOOTERS[#FOOTERS]
end

local function screen_row(window, info, line, last)
  if line < 1 or line > vim.api.nvim_buf_line_count(info.bufnr) then
    return nil
  end
  local column = last and math.max(1, #(vim.api.nvim_buf_get_lines(info.bufnr, line - 1, line, false)[1] or "")) or 1
  local position = vim.fn.screenpos(window, line, column)
  if position.row == 0 then
    return nil
  end
  return position.row - info.winrow
end

local function placement(source, location, border)
  local info = vim.fn.getwininfo(source)[1]
  local text_width = info.width - info.textoff
  local width = math.max(1, math.floor(text_width * settings.window.width) - border)
  local height = math.max(1, math.floor(info.height * settings.window.height) - border)
  local config = { relative = "win", win = source, col = info.textoff, width = width }

  local below = location and screen_row(source, info, location.end_line, true)
  local above = location and screen_row(source, info, location.start_line, false)
  local space_below = below and info.height - below - 1 - border or -1
  local space_above = above and above - border or -1

  if space_below >= height then
    return vim.tbl_extend("force", config, { row = below + 1, height = height })
  end
  if space_above >= height then
    return vim.tbl_extend("force", config, { row = above - height - border, height = height })
  end
  if math.max(space_below, space_above) >= 1 then
    if space_below >= space_above then
      return vim.tbl_extend("force", config, { row = below + 1, height = space_below })
    end
    return vim.tbl_extend("force", config, { row = 0, height = space_above })
  end

  local outer_width = width + border
  return vim.tbl_extend("force", config, {
    row = math.max(0, math.floor((info.height - height - border) / 2)),
    col = info.textoff + math.max(0, math.floor((text_width - outer_width) / 2)),
    height = height,
  })
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

local function significant_text(text)
  return text:match("^%s*$") and "" or text
end

function M.open(value, on_save, options)
  options = options or {}
  if active_window and vim.api.nvim_win_is_valid(active_window) then
    vim.api.nvim_set_current_win(active_window)
    return false
  end

  local source = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, "nvim-feedback://" .. tostring(vim.uv.hrtime()))
  vim.bo[buffer].buftype = "acwrite"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, initial_lines(value))
  vim.bo[buffer].modified = false

  local position = placement(source, options.location, vim.o.winborder == "none" and 0 or 2)
  local title_label = fitted_label(options.title or "AI feedback", options.location, position.width)

  active_window = vim.api.nvim_open_win(
    buffer,
    true,
    vim.tbl_extend("force", position, {
      style = "minimal",
      border = vim.o.winborder == "" and FALLBACK_BORDER or nil,
      title = window_title(title_label, false),
      title_pos = "center",
      footer = window_footer(position.width),
      footer_pos = "center",
    })
  )
  vim.wo[active_window].wrap = true
  vim.wo[active_window].linebreak = true
  vim.wo[active_window].cursorline = true
  vim.wo[active_window].winhl =
    "Normal:NormalFloat,FloatBorder:DiagnosticWarn,FloatTitle:DiagnosticWarn,FloatFooter:Comment"

  local opened_window = active_window
  local saved_text = significant_text(value)
  local function has_unsaved_changes()
    return significant_text(feedback_text(buffer)) ~= saved_text
  end

  local function update_title()
    if vim.api.nvim_win_is_valid(opened_window) then
      vim.api.nvim_win_set_config(opened_window, {
        title = window_title(title_label, vim.bo[buffer].modified),
        title_pos = "center",
      })
    end
  end

  vim.keymap.set("n", "<Esc>", function()
    if not has_unsaved_changes() then
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

      saved_text = text
      vim.bo[buffer].modified = false
      update_title()
    end,
  })

  vim.api.nvim_create_autocmd("BufModifiedSet", {
    buffer = buffer,
    callback = update_title,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    buffer = buffer,
    callback = function()
      vim.bo[buffer].modified = has_unsaved_changes()
      update_title()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      active_window = nil
      if options.on_close then
        options.on_close()
      end
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
  return true
end

return M
