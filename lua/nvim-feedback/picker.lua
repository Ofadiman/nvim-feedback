local ui = require("nvim-feedback.ui")

local M = {}

local CONTEXT_LINES = 3
local COMMENT_HEIGHT_SHARE = 1 / 3

local namespace = vim.api.nvim_create_namespace("nvim-feedback-preview")

local function location(entry)
  return ui.location(entry.item.file, entry.range.start_line, entry.range.end_line)
end

local function preview_title(entry)
  return location(entry) .. (entry.stale and " [stale]" or "")
end

local function matching_line(sorter, prompt, lines)
  if not prompt or prompt == "" then
    return 1
  end

  local best_index, best_score = 1, nil
  for index, line in ipairs(lines) do
    local score = sorter:scoring_function(prompt, line)
    if score >= 0 and (best_score == nil or score < best_score) then
      best_index, best_score = index, score
    end
  end
  return best_index
end

local function code_lines(entry)
  if not entry.stale then
    return entry.lines, 1
  end

  local anchor = entry.item.anchor
  local code = vim.list_extend(vim.list_extend({}, anchor.context_before), anchor.selected_lines)
  return vim.list_extend(code, anchor.context_after), entry.range.start_line - #anchor.context_before
end

local function number_lines(buffer, first, count)
  local width = #tostring(first + count - 1)
  for index = 1, count do
    vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, 0, {
      virt_text = { { string.format("%" .. width .. "d │ ", first + index - 1), "LineNr" } },
      virt_text_pos = "inline",
    })
  end
end

local function show_comment(buffer, window, comment)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(comment, "\n", { plain = true }))
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
end

local function show_code(buffer, window, entry, preview_utils)
  local lines, first = code_lines(entry)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  if entry.stale then
    number_lines(buffer, first, #lines)
  end
  ui.highlight_range(buffer, namespace, entry.range, first, lines)

  local filetype = vim.filetype.match({ filename = entry.item.file, contents = lines })
  if filetype then
    preview_utils.highlighter(buffer, filetype)
  end

  local start_row = entry.range.start_line - first + 1
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window) == buffer then
      vim.wo[window].number = not entry.stale
      vim.api.nvim_win_call(window, function()
        vim.fn.winrestview({ topline = math.max(start_row - CONTEXT_LINES, 1), lnum = start_row, col = 0 })
      end)
    end
  end)
end

local function close_comment_window(layout)
  local comment = layout.comment
  layout.comment = nil
  if not comment then
    return
  end

  for _, window in ipairs({ comment.winid, comment.border_winid }) do
    if window and vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
end

local function open_comment_window(picker, layout, preview_utils)
  local line_count = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus ~= 0 and 1 or 0)
  local preview = layout.preview
    and vim.api.nvim_win_is_valid(layout.preview.winid)
    and picker:get_window_options(vim.o.columns, line_count).preview
  if not preview then
    return
  end

  local borders = preview.border == false and 0 or 2
  local comment_height = math.floor((preview.height - borders) * COMMENT_HEIGHT_SHARE)
  local code_height = preview.height - borders - comment_height
  if comment_height < 1 or code_height < 1 then
    return
  end

  local popup = require("plenary.popup")
  popup.move(layout.preview.winid, {
    line = preview.line + comment_height + borders,
    col = preview.col,
    width = preview.width,
    height = code_height,
    minheight = code_height,
  })

  local winid, popup_options = popup.create(
    "",
    vim.tbl_extend("force", preview, {
      title = "Comment",
      height = comment_height,
      minheight = comment_height,
      focusable = false,
      highlight = "TelescopePreviewNormal",
      borderhighlight = "TelescopePreviewBorder",
      titlehighlight = "TelescopePreviewTitle",
    })
  )
  local bufnr = vim.api.nvim_win_get_buf(winid)
  vim.wo[winid].winblend = vim.wo[layout.preview.winid].winblend
  preview_utils.highlighter(bufnr, "markdown")
  layout.comment = {
    winid = winid,
    bufnr = bufnr,
    border_winid = popup_options and popup_options.border and popup_options.border.win_id,
  }
end

local function add_comment_window(picker, preview_utils)
  if require("telescope.config").values.create_layout then
    return
  end

  local create_layout = picker.create_layout
  picker.create_layout = function(self)
    local layout = create_layout(self)
    local mount, update, unmount = layout.mount, layout.update, layout.unmount

    layout.mount = function(this)
      mount(this)
      open_comment_window(self, this, preview_utils)
    end
    layout.update = function(this)
      close_comment_window(this)
      update(this)
      vim.defer_fn(function()
        open_comment_window(self, this, preview_utils)
        if this.comment then
          self:refresh_previewer()
        end
      end, 0)
    end
    layout.unmount = function(this)
      close_comment_window(this)
      unmount(this)
    end
    return layout
  end
end

function M.open(root, entries, on_select)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local preview_utils = require("telescope.previewers.utils")
  local previewers = require("telescope.previewers")

  local sorter = conf.generic_sorter({})
  local location_width = 0
  for _, entry in ipairs(entries) do
    location_width = math.max(location_width, vim.fn.strdisplaywidth(location(entry)))
  end

  local picker
  picker = pickers.new({ cwd = root }, {
    prompt_title = "Search AI feedback",
    results_title = "Results",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        local text = location(entry)
        local padding = string.rep(" ", location_width - vim.fn.strdisplaywidth(text) + 2)
        local summary_start = #text + #padding
        local comment_lines = ui.comment_lines(entry.item.comment)
        return {
          value = entry.item,
          feedback = entry,
          display = function()
            local index = matching_line(sorter, action_state.get_current_line(), comment_lines)
            local display = text .. padding .. ui.summary(entry.item.comment, entry.stale, index)
            if entry.stale then
              return display, { { { summary_start, #display }, "NvimFeedbackStaleText" } }
            end
            return display, {}
          end,
          ordinal = text .. " " .. entry.item.comment:gsub("%s+", " "),
          filename = vim.fs.joinpath(root, entry.item.file),
          lnum = entry.range.start_line,
          lnend = entry.range.end_line,
          col = (entry.range.start_col or 0) + 1,
        }
      end,
    }),
    sorter = sorter,
    previewer = previewers.new_buffer_previewer({
      title = "Comment",
      define_preview = function(self, entry)
        local feedback = entry.feedback
        local comment = picker.layout and picker.layout.comment
        if comment and vim.api.nvim_win_is_valid(comment.winid) then
          show_comment(comment.bufnr, comment.winid, feedback.item.comment)
          show_code(self.state.bufnr, self.state.winid, feedback, preview_utils)
          picker.layout.preview.border:change_title(preview_title(feedback))
        else
          vim.wo[self.state.winid].number = false
          show_comment(self.state.bufnr, self.state.winid, feedback.item.comment)
          preview_utils.highlighter(self.state.bufnr, "markdown")
        end
      end,
    }),
    attach_mappings = function(prompt_buffer)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_buffer)
        if selection then
          on_select(selection.value)
        end
      end)
      return true
    end,
  })
  add_comment_window(picker, preview_utils)
  picker:find()
end

return M
