# nvim-feedback

Leave review comments on code in Neovim, then hand them to an AI agent to resolve.

## Usage

The plugin defines no keymaps. Bind the functions you want:

```lua
local feedback = require("nvim-feedback")

vim.keymap.set({ "n", "x" }, "<leader>ac", feedback.add, { desc = "Add AI feedback" })
vim.keymap.set({ "n", "x" }, "<leader>ae", feedback.edit, { desc = "Edit AI feedback" })
vim.keymap.set({ "n", "x" }, "<leader>ad", feedback.delete, { desc = "Delete AI feedback" })
vim.keymap.set("n", "<leader>aD", feedback.delete_all, { desc = "Delete all AI feedback" })
vim.keymap.set("n", "<leader>af", feedback.find, { desc = "Find AI feedback" })
```

With the keymaps above:

- Comment on the cursor line by pressing `<leader>ac` in normal mode.
- Comment on whole lines by selecting them with `V` and pressing `<leader>ac`.
- Comment on part of a line, or on a span that starts or ends mid-line, by selecting it with `v` and pressing `<leader>ac`. Blockwise selections made with `<C-v>` are not supported.
- Write the comment in the window that opens. `:w` saves the comment and keeps the window open, `:wq` saves it and closes the window, and `:q` closes the window once every change is saved. `:q!` or `<Esc>` in normal mode closes the window and discards unsaved changes. Save the buffer first, because a buffer with unsaved changes cannot take a comment.
- Edit a comment by pressing `<leader>ae` on its range. When several comments overlap the range, pick one first.
- Read comments inline. Each comment shows a sign, a highlighted range, and the first line of its text on a virtual line below the range.
- Keep editing the code, and comments follow it as it moves. A comment that can no longer be located is marked `[stale]` instead of being silently dropped.
- Switch Git branches to switch the visible comments. Comments are scoped to the branch they were written on.
- Search the comments on the branch by their text by pressing `<leader>af`. The Telescope picker lists the file and commented code of each match, previews the full comment, and jumps to the comment you select.
- Delete a comment by pressing `<leader>ad` on its range and confirming. When several comments overlap the range, pick one first.
- Delete every comment on the branch by pressing `<leader>aD` and confirming.
- Show the comment count for the branch in the statusline, as described in [Statusline](#statusline).
- Hand the comments to an agent, as described in [Resolving feedback with an agent](#resolving-feedback-with-an-agent). Comments the agent resolves disappear from Neovim on their own.

| Function       | Description                                                                    |
| -------------- | ------------------------------------------------------------------------------ |
| `setup(opts)`  | Configures the plugin. Must be called once.                                    |
| `add()`        | Adds a comment on the cursor line or selection.                                |
| `edit()`       | Edits a comment in the range.                                                  |
| `delete()`     | Deletes a comment in the range, after confirmation.                            |
| `delete_all()` | Deletes every comment on the current branch, after confirmation.               |
| `find()`       | Opens the Telescope picker over every comment on the branch.                   |
| `statusline()` | Returns the comment count for the current buffer's branch, or an empty string. |

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

Once comments exist, invoke the skill yourself: `/nvim-feedback-resolve` in Claude Code, `$nvim-feedback-resolve` in Codex. The skill is explicit-invocation only in both, so an agent never starts resolving feedback on its own. It works through the comments on the current branch. A comment that asks for a change gets the smallest change that satisfies it, checked to work. A comment that asks a question gets an answer in the agent's reply, quoting the question. The skill deletes only the comments it resolved. Comments on other branches are never touched, and a comment is never deleted merely because the code around it changed.

## Requirements

- Neovim 0.12 or newer.
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
- [skills](https://www.npmjs.com/package/skills) CLI, to install the bundled agent skill.

## Installation

With `vim.pack`, the plugin manager built into Neovim 0.12:

```lua
vim.pack.add({
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
  "https://github.com/Ofadiman/nvim-feedback",
})

require("nvim-feedback").setup()
```

`vim.pack.add` installs no dependencies of its own, so the list above names `plenary.nvim`, which telescope.nvim requires. Call `setup()` at startup, not on a lazy trigger, or buffers you open before it runs may not show their comments.

Add `feedback.json` to `.gitignore` in every repository where you use this plugin. Comments are personal scratch state, and you must not commit them.

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local development setup.
