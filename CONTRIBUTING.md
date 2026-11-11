# Contributing

## Clone the repository

The rest of this guide assumes the clone lives at `~/projects/nvim-feedback`. Any directory works, but every command and snippet below uses that path.

```sh
git clone https://github.com/Ofadiman/nvim-feedback.git ~/projects/nvim-feedback
cd ~/projects/nvim-feedback
```

## Install the tools

This project uses [mise](https://mise.jdx.dev) to manage tool versions. Follow the [installation guide](https://mise.jdx.dev/installing-mise.html) to set it up. Then run the following command from the clone to get every tool pinned in `mise.toml`:

```sh
mise install
```

## Install the dependencies

The plugin needs [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), and telescope.nvim needs [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). In your `init.lua`:

```lua
vim.pack.add({
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
})
```

## Load the plugin from your clone

Put the clone on the Neovim `runtimepath` instead of installing the plugin, so `require("nvim-feedback")` reads your working tree:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand("~/projects/nvim-feedback"))
```

The plugin registers no autocommands until you call `setup()`, so call it after the `runtimepath` line:

```lua
require("nvim-feedback").setup()
```

If your configuration already installs `nvim-feedback` with `vim.pack.add`, delete that entry first. Two copies on the `runtimepath` make it unclear which one loads. Then remove the installed copy from disk:

```vim
:lua vim.pack.del({ "nvim-feedback" })
```

Restart Neovim and run `:checkhealth nvim-feedback`. To confirm which copy is active, run:

```vim
:lua vim.print(vim.api.nvim_get_runtime_file("lua/nvim-feedback/init.lua", true))
```

The first path in the output must be inside `~/projects/nvim-feedback`.

## Restart Neovim after every edit

Neovim caches every loaded Lua module, so an edit in your clone does not reach a running session. Restart Neovim after you change any file under `lua/`.

## Run the tests

The tests use [mini.test](https://github.com/nvim-mini/mini.test) and live in `tests/`. Every file named `test_*.lua` there is collected automatically. Run them from the clone:

```sh
mise run test
```

The first run clones mini.test, [LuaCov](https://github.com/lunarmodules/luacov), telescope.nvim, and plenary.nvim into `deps/`, which git ignores. The picker tests run against those copies of telescope.nvim and plenary.nvim, not against the ones your Neovim configuration installs. To pick up a new version after a pinned tag in `mise.toml` changes, delete `deps/` and run the tests again.

The tests run Git with `tests/gitconfig` in place of your global and system Git configuration, so your own Git settings do not change the results. Shared test utilities live in `tests/helpers.lua`, which test files load with `dofile("tests/helpers.lua")`.

Every run also measures line coverage of `lua/nvim-feedback/` and prints a summary per file after the test results. Files that no test loads show 0%. The annotated source, with `*0` marking each line that never ran, is in `coverage/luacov.report.out`, which git ignores.

## Link the agent skill

When working on the skill itself, symlink it from your clone instead of installing it, so edits take effect without reinstalling:

```sh
./scripts/link.sh
```

The script links `skills/nvim-feedback-resolve` into `~/.claude/skills` for Claude Code and into `~/.codex/skills` for Codex. If a directory does not exist, the script creates it. Re-running the script is safe. It refuses to replace an existing directory that is not a symlink, so remove any copy installed by `skills add` first.
