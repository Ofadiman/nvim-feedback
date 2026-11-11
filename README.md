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
- Comment on part of a line, or on a span that starts or ends mid-line, by selecting it with `v` and pressing `<leader>ac`.
- Comment on a rectangular block of text by selecting it with `<C-v>` and pressing `<leader>ac`.
- Edit a comment by pressing `<leader>ae` on its range.
- Search the comments on the branch by their text by pressing `<leader>af`.
- Delete a comment by pressing `<leader>ad` on its range and confirming.
- Delete every comment by pressing `<leader>aD` and confirming.

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

`statusline()` returns an empty string when the branch of the current buffer has no comments, so the component takes no space until you add one.

### Resolving feedback with an agent

Once comments exist, invoke the skill yourself: `/nvim-feedback-resolve` in Claude Code, `$nvim-feedback-resolve` in Codex. The skill is explicit-invocation only in both, so an agent never starts resolving feedback on its own. It works through the comments on the current branch. A comment that asks for a change gets the smallest change that satisfies it, checked to work, and a comment that asks a question gets an answer. The agent's reply shows the code each resolved comment targets and quotes the comment, followed by what it changed or its answer. The skill deletes only the comments it resolved. Comments on other branches are never touched, and a comment is never deleted merely because the code around it changed.

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

`setup()` must be called explicitly. It takes the following options, shown with their defaults:

```lua
require("nvim-feedback").setup({
  window = {
    width = 1,
    height = 0.3,
  },
  icon = "󰆉",
})
```

- `window.width` and `window.height` set the size of the comment editor window, as fractions greater than 0 and up to 1 of the window you comment in: `width` of its text area next to the line numbers, `height` of its height, borders included. The comment editor opens right below the commented lines, lined up with the code, or right above them when there is not enough room below. When neither side has room, it shrinks to the larger side, and when the commented lines are out of view, it opens in the middle of the window. The window draws the border set by `'winborder'`, or a double border when `'winborder'` is empty. With `'winborder'` set to `none`, the window has no border, so its title and key hints are hidden.
- `icon` marks comment text in the code, the title of the comment editor window, and the count returned by `statusline()`. The default requires a [Nerd Font](https://www.nerdfonts.com). Without one, set a plain character such as `">"`, or `""` to show no icon.

### Highlights

Comments in the code use the following highlight groups. Define any of them, or let your colorscheme define them, to change how comments look:

| Group                   | Used for                                         | Default                                                          |
| ----------------------- | ------------------------------------------------ | ---------------------------------------------------------------- |
| `NvimFeedbackRange`     | Background of the commented code.                | The `DiagnosticWarn` color blended into the `Normal` background. |
| `NvimFeedbackText`      | Comment text below the code.                     | Linked to `DiagnosticVirtualTextWarn`.                           |
| `NvimFeedbackStaleText` | Text of a comment that can no longer be located. | Linked to `DiagnosticVirtualTextError`.                          |

```lua
vim.api.nvim_set_hl(0, "NvimFeedbackRange", { bg = "#3a3020" })
```

The plugin never overrides a group that is already defined, and it defines the groups again after every colorscheme change.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local development setup.
