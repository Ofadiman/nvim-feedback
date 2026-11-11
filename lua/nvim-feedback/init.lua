local anchor = require("nvim-feedback.git")
local highlights = require("nvim-feedback.highlights")
local picker = require("nvim-feedback.picker")
local store = require("nvim-feedback.store")
local ui = require("nvim-feedback.ui")

local M = {}

local namespace = vim.api.nvim_create_namespace("nvim-feedback")
local buffers = {}
local feedback_counts = {}
local mtimes = {}
local errors = {}

local function notify_error(message)
  ui.notify(message or "Unknown AI feedback error", vim.log.levels.ERROR)
end

local function report_error(root, message)
  if errors[root] == message then
    return
  end
  errors[root] = message
  ui.notify(message, vim.log.levels.ERROR)
end

local function clear_error(root)
  errors[root] = nil
end

local function feedback_for_branch(data, branch)
  local feedback = {}
  for _, item in ipairs(data.feedback) do
    if item.branch == branch then
      table.insert(feedback, item)
    end
  end
  return feedback
end

local function read_feedback(root, branch)
  local data, read_error = store.read(root)
  feedback_counts[root] = feedback_counts[root] or {}
  feedback_counts[root][branch] = data and #feedback_for_branch(data, branch) or nil
  return data, read_error
end

local function buffer_context(buffer, require_saved)
  if not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].buftype ~= "" then
    return nil, "AI feedback requires a file buffer"
  end

  local file_path = vim.api.nvim_buf_get_name(buffer)
  if file_path == "" then
    return nil, "AI feedback requires a named file"
  end

  if require_saved and vim.bo[buffer].modified then
    return nil, "Save buffer before adding AI feedback"
  end

  file_path = vim.fs.normalize(file_path)
  if not vim.uv.fs_stat(file_path) then
    return nil, "AI feedback requires a saved file"
  end

  local root = anchor.root(file_path)
  if not root then
    return nil, "AI feedback requires a Git repository"
  end

  local branch = anchor.branch(root)
  if not branch then
    return nil, "AI feedback requires a Git branch"
  end

  local relative_path = anchor.relative(root, file_path)
  if not relative_path then
    return nil, "File is outside Git repository"
  end

  return {
    buffer = buffer,
    file_path = file_path,
    root = root,
    branch = branch,
    relative_path = relative_path,
  }
end

local function next_character_column(line, column)
  if column >= #line then
    return #line
  end

  local character = vim.fn.charidx(line, column)
  local next_column = vim.fn.byteidx(line, character + 1)
  return next_column == -1 and #line or next_column
end

local function block_range()
  local region = vim.fn.getregionpos(vim.fn.getpos("v"), vim.fn.getpos("."), {
    type = "\22",
    exclusive = vim.o.selection == "exclusive",
    eol = true,
  })
  local to_line_end = vim.fn.winsaveview().curswant == vim.v.maxcol
  local columns = {}
  local covered = false
  for _, segment in ipairs(region) do
    local first = segment[1]
    local last = segment[2]
    local text = vim.api.nvim_buf_get_lines(0, first[2] - 1, first[2], false)[1] or ""
    local start_col = math.min(math.max(first[3] - 1, 0), #text)
    local end_col = #text
    if not to_line_end and last[3] <= #text then
      end_col = next_character_column(text, math.max(last[3] - 1, 0))
    end
    end_col = math.max(end_col, start_col)
    covered = covered or end_col > start_col
    table.insert(columns, { start_col = start_col, end_col = end_col })
  end

  if not covered then
    return nil, nil, "AI feedback requires a non-empty selection"
  end
  return region[1][1][2], region[#region][1][2], nil, nil, nil, columns
end

local function target_range()
  local mode = vim.fn.mode()
  if mode == "\22" then
    return block_range()
  end

  if mode == "v" then
    local region = vim.fn.getregionpos(vim.fn.getpos("v"), vim.fn.getpos("."), {
      type = "v",
      exclusive = vim.o.selection == "exclusive",
      eol = true,
    })
    if #region == 0 then
      return nil, nil, "AI feedback requires a non-empty selection"
    end

    local first = region[1][1]
    local last = region[#region][2]
    local start_line = first[2]
    local end_line = last[2]
    local start_col = math.max(first[3] - 1, 0)
    local end_text = vim.api.nvim_buf_get_lines(0, end_line - 1, end_line, false)[1] or ""
    local end_col = last[3] > #end_text and #end_text or next_character_column(end_text, math.max(last[3] - 1, 0))
    if start_line == end_line and end_col <= start_col then
      return nil, nil, "AI feedback requires a non-empty selection"
    end
    return start_line, end_line, nil, start_col, end_col
  end

  if mode == "V" then
    local first = vim.fn.line("v")
    local last = vim.fn.line(".")
    return math.min(first, last), math.max(first, last)
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

local function comment_virtual_line(comment, stale, highlight, indent)
  return { { string.rep(" ", indent) }, { ui.labeled(ui.summary(comment, stale)), highlight } }
end

local function mark_range(buffer, mark)
  local position = vim.api.nvim_buf_get_extmark_by_id(buffer, namespace, mark.extmark_id, { details = true })
  if #position == 0 then
    return nil
  end

  local details = position[3] or {}
  return position[1] + 1, (details.end_row or position[1]) + 1, position[2], details.end_col or position[2]
end

local refresh_buffer

local function update_relocated(root, branch, relative_path, relocated)
  if not next(relocated) then
    return
  end

  local ok, update_error = store.mutate(root, function(data)
    local changed = false
    for _, item in ipairs(data.feedback) do
      local range = relocated[item.id]
      if range and item.branch == branch and item.file == relative_path then
        item.range.start_line = range.start_line
        item.range.end_line = range.end_line
        if range.start_col then
          item.range.start_col = range.start_col
          item.range.end_col = range.end_col
        end
        changed = true
      end
    end
    return changed, true
  end)

  if not ok then
    report_error(root, update_error)
  else
    mtimes[root] = store.mtime(root)
  end
end

refresh_buffer = function(buffer)
  local context = buffer_context(buffer, false)
  if not context then
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    end
    buffers[buffer] = nil
    return
  end

  local data, read_error = read_feedback(context.root, context.branch)
  if not data then
    buffers[buffer] = buffers[buffer]
      or {
        root = context.root,
        branch = context.branch,
        relative_path = context.relative_path,
        marks = {},
      }
    mtimes[context.root] = store.mtime(context.root)
    report_error(context.root, read_error)
    return
  end
  clear_error(context.root)

  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local line_count = math.max(#lines, 1)
  local marks = {}
  local relocated = {}
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

  for _, item in ipairs(data.feedback) do
    if item.branch == context.branch and item.file == context.relative_path then
      local characterwise = item.range.start_col ~= nil
      local columns = item.range.columns
      local start_line, end_line, start_col, end_col = anchor.locate(lines, item)
      local stale = not start_line
      if stale then
        start_line = math.min(math.max(item.range.start_line, 1), line_count)
        end_line = start_line
        if characterwise then
          local line = lines[start_line] or ""
          start_col = math.min(item.range.start_col, #line)
          end_col = item.range.start_line == item.range.end_line and math.min(item.range.end_col, #line) or #line
        end
      elseif
        start_line ~= item.range.start_line
        or end_line ~= item.range.end_line
        or start_col ~= item.range.start_col
        or end_col ~= item.range.end_col
      then
        relocated[item.id] = {
          start_line = start_line,
          end_line = end_line,
          start_col = start_col,
          end_col = end_col,
        }
      end

      local end_text = lines[end_line] or ""
      local virtual_highlight = stale and "NvimFeedbackStaleText" or "NvimFeedbackText"
      local mark_col = characterwise and start_col or 0
      local extmark_options = {
        end_row = end_line - 1,
        end_col = characterwise and end_col or #end_text,
        priority = 200,
        right_gravity = false,
        end_right_gravity = true,
        strict = false,
      }
      if characterwise then
        extmark_options.hl_group = "NvimFeedbackRange"
      elseif not columns then
        extmark_options.line_hl_group = "NvimFeedbackRange"
      end

      local extmark_id = vim.api.nvim_buf_set_extmark(buffer, namespace, start_line - 1, mark_col, extmark_options)
      if columns then
        for line = start_line, end_line do
          local column = columns[line - start_line + 1]
          local block_end = math.min(column.end_col, #(lines[line] or ""))
          if block_end > column.start_col then
            vim.api.nvim_buf_set_extmark(buffer, namespace, line - 1, column.start_col, {
              end_col = block_end,
              hl_group = "NvimFeedbackRange",
              priority = 200,
              strict = false,
            })
          end
        end
      end
      local indent = vim.api.nvim_buf_call(buffer, function()
        return vim.fn.indent(start_line)
      end)
      vim.api.nvim_buf_set_extmark(buffer, namespace, end_line - 1, 0, {
        virt_lines = { comment_virtual_line(item.comment, stale, virtual_highlight, indent) },
        priority = 200,
        strict = false,
      })
      marks[item.id] = {
        extmark_id = extmark_id,
        stale = stale,
        characterwise = characterwise,
      }
    end
  end

  buffers[buffer] = {
    root = context.root,
    branch = context.branch,
    relative_path = context.relative_path,
    marks = marks,
  }
  mtimes[context.root] = store.mtime(context.root)

  if not vim.bo[buffer].modified then
    update_relocated(context.root, context.branch, context.relative_path, relocated)
  end
end

local function refresh_root(root)
  local refreshed = false
  for buffer, info in pairs(buffers) do
    if info.root == root and vim.api.nvim_buf_is_valid(buffer) then
      refreshed = true
      refresh_buffer(buffer)
    end
  end
  if not refreshed then
    local branch = anchor.branch(root)
    if branch then
      read_feedback(root, branch)
    end
  end
end

local function sync_buffer(buffer)
  local info = buffers[buffer]
  if not info or not next(info.marks) then
    refresh_buffer(buffer)
    return
  end

  local context = buffer_context(buffer, false)
  if not context then
    return
  end

  local ok, sync_error = store.mutate(context.root, function(data)
    local changed = false
    for _, item in ipairs(data.feedback) do
      local mark = info.marks[item.id]
      if item.branch == context.branch and item.file == context.relative_path and mark and not mark.stale then
        local start_line, end_line, start_col, end_col = mark_range(buffer, mark)
        if start_line and end_line then
          item.range.start_line = start_line
          item.range.end_line = end_line
          if mark.characterwise then
            item.range.start_col = start_col
            item.range.end_col = end_col
          end
          changed = true
        end
      end
    end
    return changed, true
  end)

  if not ok then
    report_error(context.root, sync_error)
    return
  end

  mtimes[context.root] = store.mtime(context.root)
  refresh_buffer(buffer)
end

local function position_before(left_line, left_col, right_line, right_col)
  return left_line < right_line or (left_line == right_line and left_col < right_col)
end

local function ranges_overlap(
  start_line,
  end_line,
  start_col,
  end_col,
  item_start,
  item_end,
  item_start_col,
  item_end_col
)
  if start_col == nil or item_start_col == nil then
    return start_line <= item_end and end_line >= item_start
  end

  return position_before(start_line, start_col, item_end, item_end_col)
    and position_before(item_start, item_start_col, end_line, end_col)
end

local function current_entries()
  local buffer = vim.api.nvim_get_current_buf()
  local context, context_error = buffer_context(buffer, false)
  if not context then
    return nil, context_error
  end

  local start_line, end_line, range_error, start_col, end_col, columns = target_range()
  if not start_line then
    return nil, range_error
  end

  refresh_buffer(buffer)
  local data, read_error = read_feedback(context.root, context.branch)
  if not data then
    return nil, read_error
  end

  local matches = {}
  local info = buffers[buffer]
  for _, item in ipairs(data.feedback) do
    if item.branch == context.branch and item.file == context.relative_path then
      local item_start = item.range.start_line
      local item_end = item.range.end_line
      local item_start_col = item.range.start_col
      local item_end_col = item.range.end_col
      local mark = info and info.marks[item.id]
      if mark then
        item_start, item_end, item_start_col, item_end_col = mark_range(buffer, mark)
        if not mark.characterwise then
          item_start_col = nil
          item_end_col = nil
        end
      end
      if
        item_start
        and ranges_overlap(start_line, end_line, start_col, end_col, item_start, item_end, item_start_col, item_end_col)
      then
        table.insert(matches, item)
      end
    end
  end

  return {
    buffer = buffer,
    context = context,
    feedback = matches,
    range = {
      start_line = start_line,
      end_line = end_line,
      start_col = start_col,
      end_col = end_col,
      columns = columns,
    },
  }
end

local function choose_feedback(entries, prompt, callback)
  if #entries == 0 then
    ui.notify("No AI feedback at selection", vim.log.levels.INFO)
    return
  end

  if #entries == 1 then
    callback(entries[1])
    return
  end

  vim.ui.select(entries, {
    prompt = prompt,
    format_item = function(item)
      local text = item.comment:match("[^\n]+") or ""
      return string.format("L%d-L%d %s", item.range.start_line, item.range.end_line, text)
    end,
  }, callback)
end

local function save_comment(root, branch, id, text)
  local ok, save_error = store.mutate(root, function(data)
    for _, existing in ipairs(data.feedback) do
      if existing.id == id and existing.branch == branch then
        existing.comment = text
        return true, true
      end
    end
    return false, nil, "AI feedback no longer exists"
  end)
  if not ok then
    return nil, save_error
  end

  mtimes[root] = store.mtime(root)
  refresh_root(root)
  return true
end

local function create_feedback(buffer, context, start_line, end_line, start_col, end_col, columns)
  if vim.bo[buffer].modified then
    notify_error("Save buffer before adding AI feedback")
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local created_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local id = vim.fn.sha256(
    table.concat(
      { context.root, context.branch, context.relative_path, start_line, end_line, created_at, vim.uv.hrtime() },
      "\0"
    )
  )
  local entry = {
    id = id,
    branch = context.branch,
    file = context.relative_path,
    range = {
      start_line = start_line,
      end_line = end_line,
    },
    comment = "",
    created_at = created_at,
    anchor = anchor.snapshot(
      context.root,
      context.relative_path,
      lines,
      start_line,
      end_line,
      start_col,
      end_col,
      columns
    ),
  }
  if start_col then
    entry.range.start_col = start_col
    entry.range.end_col = end_col
  end
  if columns then
    entry.range.columns = columns
  end

  local saved = false
  ui.open("", function(text)
    if saved then
      return save_comment(context.root, context.branch, id, text)
    end

    entry.comment = text
    local ok, save_error = store.mutate(context.root, function(data)
      table.insert(data.feedback, entry)
      return true, true
    end)
    if not ok then
      return nil, save_error
    end

    saved = true
    mtimes[context.root] = store.mtime(context.root)
    refresh_root(context.root)
    return true
  end, {
    start_insert = true,
    title = "New comment",
    location = { file = context.relative_path, start_line = start_line, end_line = end_line },
  })
end

local function edit_feedback(current, item)
  local start_line, end_line = item.range.start_line, item.range.end_line
  local info = buffers[current.buffer]
  local mark = info and info.marks[item.id]
  if mark then
    local mark_start, mark_end = mark_range(current.buffer, mark)
    start_line, end_line = mark_start or start_line, mark_end or end_line
  end

  ui.open(item.comment, function(text)
    return save_comment(current.context.root, current.context.branch, item.id, text)
  end, {
    title = "Edit comment",
    location = { file = item.file, start_line = start_line, end_line = end_line },
  })
end

function M.add()
  local current, current_error = current_entries()
  if not current then
    notify_error(current_error)
    return
  end

  local range = current.range
  create_feedback(
    current.buffer,
    current.context,
    range.start_line,
    range.end_line,
    range.start_col,
    range.end_col,
    range.columns
  )
end

function M.edit()
  local current, current_error = current_entries()
  if not current then
    notify_error(current_error)
    return
  end

  choose_feedback(current.feedback, "Edit AI feedback", function(item)
    if not item then
      return
    end
    edit_feedback(current, item)
  end)
end

function M.delete()
  local current, current_error = current_entries()
  if not current then
    notify_error(current_error)
    return
  end

  choose_feedback(current.feedback, "Delete AI feedback", function(item)
    if not item or vim.fn.confirm("Delete selected AI feedback?", "&Delete\n&Cancel", 2) ~= 1 then
      return
    end

    local ok, delete_error = store.mutate(current.context.root, function(data)
      for index, existing in ipairs(data.feedback) do
        if existing.id == item.id and existing.branch == current.context.branch then
          table.remove(data.feedback, index)
          return true, true
        end
      end
      return false, nil, "AI feedback no longer exists"
    end)
    if not ok then
      notify_error(delete_error)
      return
    end

    mtimes[current.context.root] = store.mtime(current.context.root)
    refresh_root(current.context.root)
  end)
end

local function find_feedback_location()
  local buffer = vim.api.nvim_get_current_buf()
  local root = nil
  if vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buftype == "" then
    local file_path = vim.api.nvim_buf_get_name(buffer)
    if file_path ~= "" then
      root = anchor.root(file_path)
    end
  end

  root = root or anchor.root_from_directory(vim.fn.getcwd())
  if not root then
    return nil, "AI feedback requires a Git repository"
  end

  local branch = anchor.branch(root)
  if not branch then
    return nil, "AI feedback requires a Git branch"
  end

  return {
    root = root,
    branch = branch,
  }
end

function M.delete_all()
  local location, location_error = find_feedback_location()
  if not location then
    notify_error(location_error)
    return
  end

  local data, read_error = read_feedback(location.root, location.branch)
  if not data then
    notify_error(read_error)
    return
  end

  local count = #feedback_for_branch(data, location.branch)
  if count == 0 then
    ui.notify("No AI feedback on branch " .. location.branch, vim.log.levels.INFO)
    return
  end

  local suffix = count == 1 and "" or "s"
  local prompt = string.format("Delete all %d AI feedback comment%s on branch %s?", count, suffix, location.branch)
  if vim.fn.confirm(prompt, "&Delete all\n&Cancel", 2) ~= 1 then
    return
  end

  local deleted, delete_error = store.mutate(location.root, function(current)
    local remaining = {}
    local deleted_count = 0
    for _, item in ipairs(current.feedback) do
      if item.branch == location.branch then
        deleted_count = deleted_count + 1
      else
        table.insert(remaining, item)
      end
    end
    if deleted_count == 0 then
      return false, 0
    end
    current.feedback = remaining
    return true, deleted_count
  end)
  if not deleted then
    notify_error(delete_error)
    return
  end

  mtimes[location.root] = store.mtime(location.root)
  refresh_root(location.root)
  local deleted_suffix = deleted == 1 and "" or "s"
  ui.notify(
    string.format("Deleted %d AI feedback comment%s from branch %s", deleted, deleted_suffix, location.branch),
    vim.log.levels.INFO
  )
end

local function file_lines(file_path)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) and vim.fs.normalize(vim.api.nvim_buf_get_name(buffer)) == file_path then
      return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    end
  end
  if vim.uv.fs_stat(file_path) then
    return vim.fn.readfile(file_path)
  end
end

local function picker_entries(root, feedback)
  local files = {}
  local entries = {}
  for _, item in ipairs(feedback) do
    if files[item.file] == nil then
      files[item.file] = file_lines(vim.fs.normalize(vim.fs.joinpath(root, item.file))) or false
    end
    local lines = files[item.file] or nil
    local start_line, end_line, start_col, end_col
    if lines then
      start_line, end_line, start_col, end_col = anchor.locate(lines, item)
    end
    local range = item.range
    if start_line then
      range = {
        start_line = start_line,
        end_line = end_line,
        start_col = start_col,
        end_col = end_col,
        columns = item.range.columns,
      }
    end
    table.insert(entries, { item = item, lines = lines, range = range, stale = start_line == nil })
  end
  return entries
end

function M.find()
  local location, location_error = find_feedback_location()
  if not location then
    notify_error(location_error)
    return
  end

  local data, read_error = read_feedback(location.root, location.branch)
  if not data then
    notify_error(read_error)
    return
  end

  local feedback = feedback_for_branch(data, location.branch)
  if #feedback == 0 then
    ui.notify("No AI feedback on branch " .. location.branch, vim.log.levels.INFO)
    return
  end

  picker.open(location.root, picker_entries(location.root, feedback), function(item)
    local file_path = vim.fs.joinpath(location.root, item.file)
    if not vim.uv.fs_stat(file_path) then
      ui.notify("AI feedback file does not exist: " .. item.file, vim.log.levels.ERROR)
      return
    end

    vim.cmd.edit(vim.fn.fnameescape(file_path))
    local target_buffer = vim.api.nvim_get_current_buf()
    refresh_buffer(target_buffer)

    local start_line = item.range.start_line
    local block_col = item.range.columns and item.range.columns[1].start_col or 0
    local start_col = item.range.start_col or block_col
    local info = buffers[target_buffer]
    local mark = info and info.marks[item.id]
    if mark then
      local mark_line, _, mark_col = mark_range(target_buffer, mark)
      start_line = mark_line or start_line
      start_col = mark.characterwise and mark_col or block_col
    end

    local line_count = vim.api.nvim_buf_line_count(target_buffer)
    start_line = math.min(math.max(start_line, 1), line_count)
    local line = vim.api.nvim_buf_get_lines(target_buffer, start_line - 1, start_line, false)[1] or ""
    start_col = math.min(start_col, #line)
    vim.api.nvim_win_set_cursor(0, { start_line, start_col })
    vim.cmd.normal({ args = { "zz" }, bang = true })
  end)
end

local function refresh_changed_roots()
  local roots = {}
  for _, info in pairs(buffers) do
    if not roots[info.root] then
      roots[info.root] = anchor.branch(info.root) or false
    end
  end
  for root, branch in pairs(roots) do
    local branch_changed = false
    for _, info in pairs(buffers) do
      if info.root == root and info.branch ~= branch then
        branch_changed = true
        break
      end
    end
    if branch_changed or mtimes[root] ~= store.mtime(root) then
      refresh_root(root)
    end
  end
end

local function refresh_visible_buffers()
  for buffer in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.fn.bufwinid(buffer) ~= -1 then
      refresh_buffer(buffer)
    end
  end
end

function M.statusline()
  local info = buffers[vim.api.nvim_get_current_buf()]
  local count = info and feedback_counts[info.root] and feedback_counts[info.root][info.branch]
  if not count or count == 0 then
    return ""
  end
  return ui.labeled(tostring(count))
end

local initialized = false

function M.setup(opts)
  if initialized then
    ui.notify("nvim-feedback setup() cannot be called more than once", vim.log.levels.ERROR)
    return
  end
  initialized = true

  local config = require("nvim-feedback.config").parse(opts)
  ui.configure(config)

  highlights.define()

  local group = vim.api.nvim_create_augroup("nvim-feedback", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = highlights.define,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      if vim.g.SessionLoad then
        return
      end
      refresh_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = group,
    callback = function(args)
      if vim.fn.bufwinid(args.buf) ~= -1 then
        refresh_buffer(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      sync_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "FileChangedShellPost" }, {
    group = group,
    callback = function(args)
      refresh_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      buffers[args.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      vim.o.autoread = true
      vim.schedule(function()
        vim.cmd.checktime()
        refresh_changed_roots()
        refresh_visible_buffers()
      end)
    end,
  })
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = refresh_changed_roots,
  })

  refresh_buffer(vim.api.nvim_get_current_buf())
end

return M
