local M = {}

local function path(root)
  return root .. "/feedback.json"
end

local function empty()
  return {
    feedback = {},
  }
end

local function is_null(value)
  return value == vim.NIL
end

local function validate_lines(value)
  if type(value) ~= "table" or not vim.islist(value) then
    return false
  end

  for _, line in ipairs(value) do
    if type(line) ~= "string" then
      return false
    end
  end

  return true
end

local function validate_columns(item)
  local range = item.range
  local has_start = range.start_col ~= nil
  local has_end = range.end_col ~= nil
  if has_start ~= has_end then
    return false
  end
  if not has_start then
    return item.anchor.selected_text == nil
  end

  if type(range.start_col) ~= "number" or type(range.end_col) ~= "number" then
    return false
  end
  if range.start_col % 1 ~= 0 or range.end_col % 1 ~= 0 or range.start_col < 0 or range.end_col < 0 then
    return false
  end

  if range.start_line == range.end_line and range.end_col <= range.start_col then
    return false
  end

  return type(item.anchor.selected_text) == "string" and item.anchor.selected_text ~= ""
end

local function validate_item(item)
  if type(item) ~= "table" then
    return false
  end

  if type(item.branch) ~= "string" or item.branch == "" then
    return false
  end

  if type(item.id) ~= "string" or item.id == "" then
    return false
  end

  if type(item.file) ~= "string" or item.file == "" then
    return false
  end

  local normalized_file = vim.fs.normalize(item.file)
  if normalized_file:sub(1, 1) == "/" or normalized_file == ".." or normalized_file:sub(1, 3) == "../" then
    return false
  end

  if type(item.comment) ~= "string" or item.comment:match("^%s*$") then
    return false
  end

  if type(item.created_at) ~= "string" or item.created_at == "" then
    return false
  end

  if type(item.range) ~= "table" or type(item.range.start_line) ~= "number" or type(item.range.end_line) ~= "number" then
    return false
  end

  if item.range.start_line % 1 ~= 0 or item.range.end_line % 1 ~= 0 or item.range.start_line < 1 or item.range.end_line < item.range.start_line then
    return false
  end

  if type(item.anchor) ~= "table" then
    return false
  end

  if not (type(item.anchor.head) == "string" or is_null(item.anchor.head)) then
    return false
  end

  if not validate_lines(item.anchor.selected_lines) or #item.anchor.selected_lines ~= item.range.end_line - item.range.start_line + 1 then
    return false
  end

  if not validate_lines(item.anchor.context_before) or not validate_lines(item.anchor.context_after) then
    return false
  end

  if not validate_columns(item) then
    return false
  end

  if not (type(item.anchor.diff_hunk) == "string" or is_null(item.anchor.diff_hunk)) then
    return false
  end

  return true
end

local function validate(data)
  if type(data) ~= "table" or type(data.feedback) ~= "table" or not vim.islist(data.feedback) then
    return false
  end

  local ids = {}
  for _, item in ipairs(data.feedback) do
    if not validate_item(item) or ids[item.id] then
      return false
    end
    ids[item.id] = true
  end

  return true
end

function M.path(root)
  return path(root)
end

function M.read(root)
  local target = path(root)
  local file, open_error = io.open(target, "rb")
  if not file then
    if vim.uv.fs_stat(target) then
      return nil, open_error
    end
    return empty()
  end

  local raw = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or not validate(data) then
    return nil, "Invalid AI feedback file: " .. target
  end

  return data
end

function M.write(root, data)
  if not validate(data) then
    return nil, "Refusing to write invalid AI feedback data"
  end

  local target = path(root)
  local temporary = target .. ".tmp." .. vim.fn.getpid() .. "." .. tostring(vim.uv.hrtime())
  local file, open_error = io.open(temporary, "wb")
  if not file then
    return nil, open_error
  end

  local write_ok, write_error = file:write(vim.json.encode(data), "\n")
  file:close()
  if not write_ok then
    os.remove(temporary)
    return nil, write_error
  end

  local rename_ok, rename_error = os.rename(temporary, target)
  if not rename_ok then
    os.remove(temporary)
    return nil, rename_error
  end

  return true
end

function M.mutate(root, callback)
  local data, read_error = M.read(root)
  if not data then
    return nil, read_error
  end

  local changed, result, mutation_error = callback(data)
  if mutation_error then
    return nil, mutation_error
  end

  if changed then
    local write_ok, write_error = M.write(root, data)
    if not write_ok then
      return nil, write_error
    end
  end

  return result == nil and true or result
end

function M.mtime(root)
  local stat = vim.uv.fs_stat(path(root))
  if not stat then
    return "missing"
  end

  return table.concat({ stat.mtime.sec, stat.mtime.nsec, stat.size }, ":")
end

return M
