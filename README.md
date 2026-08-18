# nvim-feedback

Leave review comments on code in Neovim, then hand them to an AI agent to resolve.

Select a range, write a comment, and it is stored in `feedback.json` at the repository root together with an anchor describing the code it points at. Comments are scoped to the current Git branch and render inline as virtual text. The bundled `nvim-feedback-resolve` skill teaches an agent to locate each comment, apply the change, and delete only the items it actually resolved.

## Features

- Comment on a cursor line, a linewise selection, or a characterwise selection.
- Comments are scoped to the current Git branch, so switching branches switches the visible set.
- Comments follow code as it moves. Every comment stores the selected text, three lines of context on each side, the matching diff hunk, and `HEAD`, which is enough to relocate it after an edit.
- Comments that can no longer be located are marked `[stale]` instead of being silently dropped.
- Inline rendering with a sign, a highlighted range, and the comment as end-of-line virtual text.
- Telescope picker to search every comment on the branch, with a preview.
- Delete a single comment, or every comment on the current branch.
- Statusline component showing the number of comments on the branch.
- External edits to `feedback.json`, including deletions by an agent, are picked up automatically.

## Requirements

- Neovim 0.11 or newer.
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
- [skills](https://www.npmjs.com/package/skills) CLI, to install the bundled agent skill.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Ofadiman/nvim-feedback",
  dependencies = { "nvim-telescope/telescope.nvim" },
  lazy = false,
  config = function()
    require("nvim-feedback").setup()
  end,
}
```

`lazy = false` is required. The plugin registers autocommands that must be active from startup to render comments in buffers you open.

Add `feedback.json` to `.gitignore` in every repository where you use this plugin. Comments are personal scratch state and should not be committed.

### Installing the agent skill

The plugin only records comments. Resolving them is done by the bundled `nvim-feedback-resolve` skill, which you install separately with the [skills](https://www.npmjs.com/package/skills) CLI.

Install it globally for Claude Code and Codex:

```sh
skills add Ofadiman/nvim-feedback --global --agent claude-code,codex --skill nvim-feedback-resolve --yes
```

## Configuration

`setup()` must be called explicitly. The only option is the size of the comment editor window, given as fractions of the editor:

```lua
require("nvim-feedback").setup({
  window = {
    width = 0.5,
    height = 0.5,
  },
})
```

Both values must be numbers between 0 and 1. Anything else raises an error at `setup()`.

## Usage

The plugin defines no keymaps. Bind the functions you want:

```lua
local feedback = require("nvim-feedback")

vim.keymap.set({ "n", "x" }, "<leader>ac", feedback.add, { desc = "Add or edit AI feedback" })
vim.keymap.set({ "n", "x" }, "<leader>ad", feedback.delete, { desc = "Delete AI feedback" })
vim.keymap.set("n", "<leader>aD", feedback.delete_all, { desc = "Delete all AI feedback" })
vim.keymap.set("n", "<leader>af", feedback.find, { desc = "Find AI feedback" })
```

| Function       | Description                                                                                    |
| -------------- | ---------------------------------------------------------------------------------------------- |
| `setup(opts)`  | Configures the plugin and registers autocommands. Must be called once.                         |
| `add()`        | Adds a comment on the cursor line or selection. Offers to edit existing comments in the range. |
| `delete()`     | Deletes a comment in the range, after confirmation.                                            |
| `delete_all()` | Deletes every comment on the current branch, after confirmation.                               |
| `find()`       | Opens the Telescope picker over every comment on the branch.                                   |
| `statusline()` | Returns the comment count for the current buffer's branch, or an empty string.                 |

The buffer must be saved before a comment can be added. In the comment window, `<Esc>` saves and `:q!` discards.

### Statusline

With [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim):

```lua
lualine_x = {
  function()
    return require("nvim-feedback").statusline()
  end,
}
```

### Resolving feedback with an agent

Once comments exist, invoke the skill yourself: `/nvim-feedback-resolve` in Claude Code, `$nvim-feedback-resolve` in Codex. The skill is explicit-invocation only in both, so an agent never starts resolving feedback on its own. It reads `feedback.json`, filters to the current branch, locates each comment against the current working tree, applies the smallest change that satisfies it, verifies the result, and removes only the items it resolved. Comments on other branches are never touched, and a comment is never deleted merely because the code around it changed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local development setup.

## Roadmap

- Semver release tags.
- `:checkhealth` support.
- A `doc/` vignette so `:help nvim-feedback` works.
- Broader configuration with validation, if a second option turns out to be worth having.

## License

MIT
