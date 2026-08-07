local M = {}

local function run(root, args)
  local command = { "git", "-C", root }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  return result.stdout:gsub("%s+$", "")
end

local function copy_lines(lines, first, last)
  local result = {}
  for index = math.max(first, 1), math.min(last, #lines) do
    table.insert(result, lines[index])
  end
  return result
end

local function hunk_range(header)
  local start, count = header:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
  if not start then
    return nil
  end

  local start_line = tonumber(start)
  if not start_line then
    return nil
  end
  local line_count = tonumber(count) or 1
  return start_line, start_line + math.max(line_count, 1) - 1
end

local function matching_hunks(diff, start_line, end_line)
  if not diff or diff == "" then
    return vim.NIL
  end

  local hunks = {}
  local current = nil
  for line in (diff .. "\n"):gmatch("(.-)\n") do
    if line:match("^@@ ") then
      if current then
        table.insert(hunks, current)
      end
      current = { line }
    elseif current then
      table.insert(current, line)
    end
  end
  if current then
    table.insert(hunks, current)
  end

  local matches = {}
  for _, hunk in ipairs(hunks) do
    local hunk_start, hunk_end = hunk_range(hunk[1])
    if hunk_start and start_line <= hunk_end and end_line >= hunk_start then
      table.insert(matches, table.concat(hunk, "\n"))
    end
  end

  if #matches == 0 then
    return vim.NIL
  end

  return table.concat(matches, "\n")
end

local function sequence_matches(lines, selected, start_line)
  if start_line < 1 or start_line + #selected - 1 > #lines then
    return false
  end

  for offset, selected_line in ipairs(selected) do
    if lines[start_line + offset - 1] ~= selected_line then
      return false
    end
  end

  return true
end

local function context_score(lines, anchor, start_line, end_line)
  local score = 0
  for index, context_line in ipairs(anchor.context_before) do
    local line = start_line - #anchor.context_before + index - 1
    if line >= 1 and lines[line] == context_line then
      score = score + 1
    end
  end

  for index, context_line in ipairs(anchor.context_after) do
    local line = end_line + index
    if line <= #lines and lines[line] == context_line then
      score = score + 1
    end
  end

  return score
end

local function selected_text(lines, start_line, end_line, start_col, end_col)
  if start_line < 1 or end_line > #lines or start_line > end_line then
    return nil
  end

  local selected = copy_lines(lines, start_line, end_line)
  if start_col > #selected[1] or end_col > #selected[#selected] then
    return nil
  end

  if #selected == 1 then
    if end_col <= start_col then
      return nil
    end
    return selected[1]:sub(start_col + 1, end_col)
  end

  selected[1] = selected[1]:sub(start_col + 1)
  selected[#selected] = selected[#selected]:sub(1, end_col)
  return table.concat(selected, "\n")
end

local function line_starts(lines)
  local starts = {}
  local offset = 1
  for index, line in ipairs(lines) do
    starts[index] = offset
    offset = offset + #line + 1
  end
  return starts
end

local function position_at(lines, starts, offset)
  for line = #starts, 1, -1 do
    if offset >= starts[line] then
      return line, math.min(offset - starts[line], #lines[line])
    end
  end
  return 1, 0
end

local function locate_text(lines, item)
  local range = item.range
  local text = item.anchor.selected_text
  if selected_text(lines, range.start_line, range.end_line, range.start_col, range.end_col) == text then
    return range.start_line, range.end_line, range.start_col, range.end_col
  end

  local content = table.concat(lines, "\n")
  local starts = line_starts(lines)
  local candidates = {}
  local offset = 1
  while true do
    local match_start, match_end = content:find(text, offset, true)
    if not match_start then
      break
    end

    local start_line, start_col = position_at(lines, starts, match_start)
    local end_line, end_col = position_at(lines, starts, match_end + 1)
    table.insert(candidates, {
      start_line = start_line,
      end_line = end_line,
      start_col = start_col,
      end_col = end_col,
      score = context_score(lines, item.anchor, start_line, end_line),
      distance = math.abs(start_line - range.start_line),
      column_distance = math.abs(start_col - range.start_col),
    })
    offset = match_start + 1
  end

  if #candidates == 0 then
    return nil
  end

  table.sort(candidates, function(left, right)
    if left.score ~= right.score then
      return left.score > right.score
    end
    if left.distance ~= right.distance then
      return left.distance < right.distance
    end
    return left.column_distance < right.column_distance
  end)

  if
    #candidates > 1
    and candidates[1].score == candidates[2].score
    and candidates[1].distance == candidates[2].distance
    and candidates[1].column_distance == candidates[2].column_distance
  then
    return nil
  end

  local match = candidates[1]
  return match.start_line, match.end_line, match.start_col, match.end_col
end

function M.root_from_directory(directory)
  directory = vim.fs.normalize(directory)
  local result = vim.system({ "git", "-C", directory, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local root = result.stdout:gsub("%s+$", "")
  return vim.fs.normalize(root)
end

function M.root(file_path)
  local directory = vim.fs.dirname(vim.fs.normalize(file_path))
  if not directory then
    return nil
  end

  return M.root_from_directory(directory)
end

function M.branch(root)
  local branch = run(root, { "symbolic-ref", "--quiet", "--short", "HEAD" })
  if not branch or branch == "" then
    return nil
  end
  return branch
end

function M.relative(root, file_path)
  root = vim.fs.normalize(root)
  file_path = vim.fs.normalize(file_path)
  local prefix = root .. "/"
  if file_path:sub(1, #prefix) ~= prefix then
    return nil
  end

  return file_path:sub(#prefix + 1)
end

function M.snapshot(root, relative_path, lines, start_line, end_line, start_col, end_col)
  local head = run(root, { "rev-parse", "--verify", "HEAD" }) or vim.NIL
  local diff = nil
  if head ~= vim.NIL then
    diff = run(root, { "diff", "--no-ext-diff", "--no-color", "--unified=3", "HEAD", "--", relative_path })
  end

  local result = {
    head = head,
    selected_lines = copy_lines(lines, start_line, end_line),
    context_before = copy_lines(lines, start_line - 3, start_line - 1),
    context_after = copy_lines(lines, end_line + 1, end_line + 3),
    diff_hunk = matching_hunks(diff, start_line, end_line),
  }
  if start_col then
    result.selected_text = selected_text(lines, start_line, end_line, start_col, end_col)
  end
  return result
end

function M.locate(lines, item)
  if item.range.start_col then
    return locate_text(lines, item)
  end

  local selected = item.anchor.selected_lines
  if sequence_matches(lines, selected, item.range.start_line) then
    return item.range.start_line, item.range.start_line + #selected - 1
  end

  local candidates = {}
  for start_line = 1, #lines - #selected + 1 do
    if sequence_matches(lines, selected, start_line) then
      table.insert(candidates, {
        start_line = start_line,
        score = context_score(lines, item.anchor, start_line, start_line + #selected - 1),
        distance = math.abs(start_line - item.range.start_line),
      })
    end
  end

  if #candidates == 0 then
    return nil
  end

  table.sort(candidates, function(left, right)
    if left.score ~= right.score then
      return left.score > right.score
    end
    return left.distance < right.distance
  end)

  if
    #candidates > 1
    and candidates[1].score == candidates[2].score
    and candidates[1].distance == candidates[2].distance
  then
    return nil
  end

  return candidates[1].start_line, candidates[1].start_line + #selected - 1
end

return M
