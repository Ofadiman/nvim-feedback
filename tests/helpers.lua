local git = require("nvim-feedback.git")

local CREATED_AT = "2026-11-10T00:00:00Z"

local helpers = {}

function helpers.git(repository, args)
  local command = { "git", "-C", repository }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(command, " ") .. ": " .. result.stderr, 2)
  end
  return vim.trim(result.stdout)
end

function helpers.temporary_directory()
  local directory = vim.fn.tempname()
  vim.fn.mkdir(directory, "p")
  return vim.uv.fs_realpath(directory)
end

function helpers.create_repository(files)
  local repository = helpers.temporary_directory()
  helpers.git(repository, { "init", "--quiet" })
  for name, lines in pairs(files or {}) do
    helpers.write_file(repository, name, lines)
  end
  return repository
end

function helpers.commit(repository)
  helpers.git(repository, { "add", "--all" })
  helpers.git(repository, { "commit", "--quiet", "--message", "commit" })
end

function helpers.write_file(repository, name, lines)
  local path = vim.fs.joinpath(repository, name)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end

function helpers.remove(path)
  vim.fn.delete(path, "rf")
end

function helpers.comment(repository, fields)
  local lines = vim.fn.readfile(vim.fs.joinpath(repository, fields.file))
  local range = fields.range
  return {
    id = fields.id or fields.comment,
    branch = fields.branch or "main",
    file = fields.file,
    comment = fields.comment,
    created_at = CREATED_AT,
    range = vim.deepcopy(range),
    anchor = git.snapshot(
      repository,
      fields.file,
      lines,
      range.start_line,
      range.end_line,
      range.start_col,
      range.end_col,
      range.columns
    ),
  }
end

function helpers.write_feedback(repository, items)
  vim.fn.writefile({ vim.json.encode({ feedback = items }) }, vim.fs.joinpath(repository, "feedback.json"))
end

function helpers.read_feedback(repository)
  local raw = table.concat(vim.fn.readfile(vim.fs.joinpath(repository, "feedback.json")), "\n")
  return vim.json.decode(raw).feedback
end

function helpers.start_editor(child, opts)
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.lua(
    [[
    _G.notifications = {}
    _G.notification_titles = {}
    vim.notify = function(message, level, opts)
      table.insert(_G.notifications, { message = message, level = level })
      table.insert(_G.notification_titles, opts and opts.title or vim.NIL)
    end

    local feedback = require("nvim-feedback")
    feedback.setup(...)
    vim.keymap.set({ "n", "x" }, "<F2>", feedback.add)
    vim.keymap.set({ "n", "x" }, "<F3>", feedback.edit)
    vim.keymap.set({ "n", "x" }, "<F4>", feedback.delete)
  ]],
    { opts }
  )
end

function helpers.add_telescope(child, defaults)
  child.lua(
    [[
    local root, defaults = ...
    vim.opt.runtimepath:append(vim.fs.joinpath(root, "deps", "plenary.nvim"))
    vim.opt.runtimepath:append(vim.fs.joinpath(root, "deps", "telescope.nvim"))
    require("telescope").setup({ defaults = defaults })
  ]],
    { vim.fn.getcwd(), defaults or vim.empty_dict() }
  )
end

function helpers.notifications(child)
  return child.lua_get("_G.notifications")
end

function helpers.notification_titles(child)
  return child.lua_get("_G.notification_titles")
end

function helpers.save_comment(child, lines, command)
  child.lua(
    [[
    local lines, command = ...
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd(command)
  ]],
    { lines, command or "wq" }
  )
  child.ensure_normal_mode()
end

function helpers.floating_windows(child)
  return child.lua([[
    local windows = {}
    for _, window in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(window).relative ~= "" then
        table.insert(windows, window)
      end
    end
    return windows
  ]])
end

function helpers.virtual_lines(child)
  return child.lua([[
    local namespace = vim.api.nvim_create_namespace("nvim-feedback")
    local result = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
      local virt_lines = mark[4].virt_lines
      if virt_lines then
        local chunks = virt_lines[1]
        table.insert(result, { line = mark[2] + 1, text = chunks[1][1] .. chunks[2][1], highlight = chunks[2][2] })
      end
    end
    return result
  ]])
end

function helpers.highlights(child)
  return child.lua([[
    local namespace = vim.api.nvim_create_namespace("nvim-feedback")
    local result = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
      local details = mark[4]
      if details.hl_group then
        table.insert(result, {
          start_line = mark[2] + 1,
          start_col = mark[3],
          end_line = details.end_row + 1,
          end_col = details.end_col,
        })
      elseif details.line_hl_group then
        table.insert(result, { start_line = mark[2] + 1, end_line = details.end_row + 1 })
      end
    end
    return result
  ]])
end

function helpers.signs(child)
  return child.lua([[
    local namespace = vim.api.nvim_create_namespace("nvim-feedback")
    local result = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
      if mark[4].sign_text then
        table.insert(result, { line = mark[2] + 1, text = mark[4].sign_text })
      end
    end
    return result
  ]])
end

return helpers
