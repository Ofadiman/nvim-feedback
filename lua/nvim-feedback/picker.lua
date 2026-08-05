local M = {}

local function display_text(item)
  local location = string.format("%s:%d", item.file, item.range.start_line)
  if item.range.end_line ~= item.range.start_line then
    location = location .. "-" .. item.range.end_line
  end

  return location .. " " .. item.comment:gsub("%s+", " ")
end

function M.open(root, feedback, on_select)
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  local finders = require("telescope.finders")
  local pickers = require("telescope.pickers")

  pickers
    .new({ cwd = root }, {
      prompt_title = "Search AI feedback",
      results_title = "Results",
      preview_title = "Preview",
      finder = finders.new_table({
        results = feedback,
        entry_maker = function(item)
          return {
            value = item,
            display = display_text(item),
            ordinal = item.file .. " " .. item.comment,
            filename = vim.fs.joinpath(root, item.file),
            lnum = item.range.start_line,
            lnend = item.range.end_line,
            col = (item.range.start_col or 0) + 1,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.grep_previewer({}),
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
