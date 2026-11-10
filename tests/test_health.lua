local helpers = dofile("tests/helpers.lua")

local child = MiniTest.new_child_neovim()
local repository = nil
local agents_home = nil

local function neovim_version()
  local version = vim.version()
  return string.format("ok: Neovim %d.%d.%d", version.major, version.minor, version.patch)
end

local function claude_skills()
  return vim.fs.joinpath(agents_home, "claude", "skills")
end

local function codex_skills()
  return vim.fs.joinpath(agents_home, "codex", "skills")
end

local function install_skill(skills_directory)
  return helpers.write_file(skills_directory, "nvim-feedback-resolve/SKILL.md", { "# Skill" })
end

local function check_health(directory)
  return child.lua(
    [[
    local directory = ...
    local health = require("nvim-feedback.health")
    local project = vim.fn.getcwd()
    vim.cmd.cd(directory)
    local ok, check_error = pcall(health.check)
    vim.cmd.cd(project)
    assert(ok, check_error)
    return _G.report
  ]],
    { directory }
  )
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      repository = helpers.create_repository()
      agents_home = helpers.temporary_directory()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua(
        [[
        local claude, codex = ...
        vim.env.CLAUDE_CONFIG_DIR = claude
        vim.env.CODEX_HOME = codex
        _G.report = {}
        for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
          vim.health[level] = function(message)
            table.insert(_G.report, level .. ": " .. message)
          end
        end
      ]],
        { vim.fs.joinpath(agents_home, "claude"), vim.fs.joinpath(agents_home, "codex") }
      )
    end,
    post_case = function()
      helpers.remove(repository)
      helpers.remove(agents_home)
    end,
    post_once = child.stop,
  },
})

tests["check()"] = MiniTest.new_set()

tests["check()"]["reports a repository that is ready for feedback"] = function()
  child.lua([[package.preload.telescope = function() return {} end]])
  helpers.write_file(repository, ".gitignore", { "feedback.json" })
  helpers.write_feedback(repository, {})
  local skill = install_skill(claude_skills())

  MiniTest.expect.equality(check_health(repository), {
    "start: Environment",
    neovim_version(),
    "ok: git found in $PATH",
    "ok: telescope.nvim is loadable",
    "start: Feedback",
    "ok: repository " .. repository,
    "ok: branch main",
    "ok: " .. repository .. "/feedback.json is valid",
    "ok: feedback.json is ignored by Git",
    "start: Agent skill",
    "ok: Claude Code skill installed at " .. skill,
  })
end

tests["check()"]["warns about a missing picker, an unignored feedback file, and a missing skill"] = function()
  MiniTest.expect.equality(check_health(repository), {
    "start: Environment",
    neovim_version(),
    "ok: git found in $PATH",
    "warn: telescope.nvim is not loadable, find() will not work",
    "start: Feedback",
    "ok: repository " .. repository,
    "ok: branch main",
    "ok: " .. repository .. "/feedback.json does not exist yet, it is created with the first comment",
    "warn: feedback.json is not ignored by Git, add it to .gitignore to keep comments out of commits",
    "start: Agent skill",
    string.format(
      "warn: nvim-feedback-resolve is not installed, install it in %s or %s",
      claude_skills(),
      codex_skills()
    ),
  })
end

tests["check()"]["reports the skill installed for Codex"] = function()
  local skill = install_skill(codex_skills())

  local report = check_health(repository)

  MiniTest.expect.equality(report[#report], "ok: Codex skill installed at " .. skill)
end

tests["check()"]["reports an invalid feedback file and a detached HEAD"] = function()
  helpers.write_file(repository, "file.txt", { "content" })
  helpers.commit(repository)
  helpers.git(repository, { "checkout", "--quiet", "--detach" })
  helpers.write_file(repository, "feedback.json", { "{" })

  local report = check_health(repository)

  MiniTest.expect.equality(vim.list_slice(report, 5, 8), {
    "start: Feedback",
    "ok: repository " .. repository,
    "error: HEAD is detached, comments are scoped to a branch",
    "error: Invalid AI feedback file: " .. repository .. "/feedback.json",
  })
end

tests["check()"]["reports a working directory outside a Git repository"] = function()
  local directory = helpers.temporary_directory()

  local report = check_health(directory)

  MiniTest.expect.equality(vim.list_slice(report, 5, 7), {
    "start: Feedback",
    "error: " .. directory .. " is not inside a Git repository",
    "start: Agent skill",
  })

  helpers.remove(directory)
end

tests["check()"]["skips the feedback checks when git is missing"] = function()
  child.lua([[
    local executable = vim.fn.executable
    vim.fn.executable = function(name)
      return name == "git" and 0 or executable(name)
    end
  ]])

  local report = check_health(repository)

  MiniTest.expect.equality(vim.list_slice(report, 3, 7), {
    "error: git not found in $PATH",
    "warn: telescope.nvim is not loadable, find() will not work",
    "start: Feedback",
    "info: skipped, git is not available",
    "start: Agent skill",
  })
end

return tests
