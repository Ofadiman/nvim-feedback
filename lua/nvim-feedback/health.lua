local config = require("nvim-feedback.config")
local git = require("nvim-feedback.git")
local store = require("nvim-feedback.store")

local M = {}

local skill_name = "nvim-feedback-resolve"

local agents = {
  { name = "Claude Code", variable = "CLAUDE_CONFIG_DIR", directory = "~/.claude" },
  { name = "Codex", variable = "CODEX_HOME", directory = "~/.codex" },
}

local function version_string()
  local version = vim.version()
  return string.format("%d.%d.%d", version.major, version.minor, version.patch)
end

local function check_environment()
  vim.health.start("Environment")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim " .. version_string())
  else
    vim.health.error("Neovim 0.12 or newer is required, found " .. version_string())
  end

  local git_available = vim.fn.executable("git") == 1
  if git_available then
    vim.health.ok("git found in $PATH")
  else
    vim.health.error("git not found in $PATH")
  end

  if pcall(require, "telescope") then
    vim.health.ok("telescope.nvim is loadable")
  else
    vim.health.warn("telescope.nvim is not loadable, find() will not work")
  end

  return git_available
end

local function check_configuration()
  vim.health.start("Configuration")

  if config.is_initialized() then
    vim.health.ok("setup() was called")
  else
    vim.health.error("setup() was not called, no autocommands are registered and no comments are rendered")
  end

  local rejected = config.rejected()
  if #rejected == 0 then
    local window = config.window()
    vim.health.ok(string.format("window width %s, height %s", window.width, window.height))
    return
  end

  for _, entry in ipairs(rejected) do
    vim.health.warn(
      string.format(
        "%s must be a number between 0 and 1, got %s, using %s",
        entry.name,
        vim.inspect(entry.value),
        entry.substitute
      )
    )
  end
end

local function check_gitignore(root)
  local command = { "git", "-C", root, "check-ignore", "--quiet", "--", "feedback.json" }
  local result = vim.system(command, { text = true }):wait()

  if result.code == 0 then
    vim.health.ok("feedback.json is ignored by Git")
  elseif result.code == 1 then
    vim.health.warn("feedback.json is not ignored by Git, add it to .gitignore to keep comments out of commits")
  else
    local message = (result.stderr or ""):gsub("%s+$", "")
    vim.health.warn("git check-ignore failed: " .. message)
  end
end

local function check_feedback(git_available)
  vim.health.start("Feedback")

  if not git_available then
    vim.health.info("skipped, git is not available")
    return
  end

  local directory = vim.fs.normalize(vim.fn.getcwd())
  local root = git.root_from_directory(directory)
  if not root then
    vim.health.error(directory .. " is not inside a Git repository")
    return
  end
  vim.health.ok("repository " .. root)

  local branch = git.branch(root)
  if branch then
    vim.health.ok("branch " .. branch)
  else
    vim.health.error("HEAD is detached, comments are scoped to a branch")
  end

  local target = store.path(root)
  local data, read_error = store.read(root)
  if not data then
    vim.health.error(read_error)
  elseif vim.uv.fs_stat(target) then
    vim.health.ok(target .. " is valid")
  else
    vim.health.ok(target .. " does not exist yet, it is created with the first comment")
  end

  check_gitignore(root)
end

local function skills_directory(agent)
  return vim.fs.joinpath(vim.fs.normalize(vim.env[agent.variable] or agent.directory), "skills")
end

local function check_skill()
  vim.health.start("Agent skill")

  local locations = {}
  local installed = false
  for _, agent in ipairs(agents) do
    local directory = skills_directory(agent)
    table.insert(locations, directory)
    local path = vim.fs.joinpath(directory, skill_name, "SKILL.md")
    if vim.uv.fs_stat(path) then
      installed = true
      vim.health.ok(agent.name .. " skill installed at " .. path)
    end
  end

  if not installed then
    vim.health.warn(string.format("%s is not installed, install it in %s", skill_name, table.concat(locations, " or ")))
  end
end

function M.check()
  local git_available = check_environment()
  check_configuration()
  check_feedback(git_available)
  check_skill()
end

return M
