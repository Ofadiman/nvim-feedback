local M = {}

local function commented_text(item)
  local text = item.anchor.selected_text or table.concat(item.anchor.selected_lines, "\n")
  return (vim.trim(text):gsub("%s+", " "))
end

local function display_text(item)
  local location = string.format("%s:%d", item.file, item.range.start_line)
  if item.range.end_line ~= item.range.start_line then
    location = location .. "-" .. item.range.end_line
  end

  return location .. " " .. commented_text(item)
end

function M.open(root, feedback, on_select)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")
  local previewers = require("telescope.previewers")

  local sorter = conf.generic_sorter({})
  sorter.highlighter = nil

  pickers
    .new({ cwd = root }, {
      prompt_title = "Search AI feedback",
      results_title = "Results",
      preview_title = "Comment",
      finder = finders.new_table({
        results = feedback,
        entry_maker = function(item)
          return {
            value = item,
            display = display_text(item),
            ordinal = item.comment,
            filename = vim.fs.joinpath(root, item.file),
            lnum = item.range.start_line,
            lnend = item.range.end_line,
            col = (item.range.start_col or 0) + 1,
          }
        end,
      }),
      sorter = sorter,
      previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          local lines = vim.split(entry.value.comment, "\n", { plain = true })
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
        end,
      }),
      attach_mappings = function(prompt_buffer)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_buffer)
          if selection then
            on_select(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
