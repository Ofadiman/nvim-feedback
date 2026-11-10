local helpers = dofile("tests/helpers.lua")

local FILE_LINES = { "local alpha = 1", "local beta = 2", "return alpha + beta" }
local COLORSCHEME_LINES = {
  "vim.cmd(\"highlight clear\")",
  "vim.g.colors_name = \"feedback-test\"",
  "vim.api.nvim_set_hl(0, 'Normal', { bg = 0x102030 })",
  "vim.api.nvim_set_hl(0, 'DiagnosticWarn', { fg = 0xf0d0b0 })",
  "vim.api.nvim_set_hl(0, 'NvimFeedbackStaleText', { fg = 0x123456 })",
}

local child = MiniTest.new_child_neovim()

local function highlight(name)
  return child.api.nvim_get_hl(0, { name = name })
end

local function setup()
  child.lua([[require("nvim-feedback").setup()]])
end

local tests = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

tests["setup()"] = MiniTest.new_set()

tests["setup()"]["links the comment text to the warning virtual text and stale text to Comment"] = function()
  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackText"), { link = "DiagnosticVirtualTextWarn", default = true })
  MiniTest.expect.equality(highlight("NvimFeedbackStaleText"), { link = "Comment", default = true })
end

tests["setup()"]["tints the background of the range group with the warning color"] = function()
  child.cmd("highlight Normal guibg=#102030")
  child.cmd("highlight DiagnosticWarn guifg=#f0d0b0")

  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { bg = 0x323a43, default = true })
end

tests["setup()"]["tints against black when Normal has no background on a dark background"] = function()
  child.o.background = "dark"
  child.cmd("highlight Normal guibg=NONE")
  child.cmd("highlight DiagnosticWarn guifg=#f0d0b0")

  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { bg = 0x241f1a, default = true })
end

tests["setup()"]["tints against white when Normal has no background on a light background"] = function()
  child.o.background = "light"
  child.cmd("highlight Normal guibg=NONE")
  child.cmd("highlight DiagnosticWarn guifg=#f0d0b0")

  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { bg = 0xfdf8f3, default = true })
end

tests["setup()"]["links the range group to CursorLine when there is no warning color"] = function()
  child.cmd("highlight clear DiagnosticWarn")

  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { link = "CursorLine", default = true })
end

tests["setup()"]["keeps the groups that were defined before it was called"] = function()
  child.cmd("highlight NvimFeedbackRange guibg=#abcdef")
  child.cmd("highlight link NvimFeedbackText Title")

  setup()

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { bg = 0xabcdef })
  MiniTest.expect.equality(highlight("NvimFeedbackText"), { link = "Title" })
end

tests["colorscheme"] = MiniTest.new_set()

tests["colorscheme"]["defines the groups again from the colors of the new colorscheme"] = function()
  local directory = helpers.temporary_directory()
  helpers.write_file(directory, "colors/feedback-test.lua", COLORSCHEME_LINES)
  setup()

  child.lua("vim.opt.runtimepath:prepend(...)", { directory })
  child.cmd("colorscheme feedback-test")

  MiniTest.expect.equality(highlight("NvimFeedbackRange"), { bg = 0x323a43, default = true })
  MiniTest.expect.equality(highlight("NvimFeedbackText"), { link = "DiagnosticVirtualTextWarn", default = true })
  MiniTest.expect.equality(highlight("NvimFeedbackStaleText"), { fg = 0x123456 })

  helpers.remove(directory)
end

tests["rendering"] = MiniTest.new_set()

tests["rendering"]["highlights every kind of commented range with the range group"] = function()
  local repository = helpers.create_repository({ ["values.lua"] = FILE_LINES })
  local columns = { { start_col = 6, end_col = 10 }, { start_col = 6, end_col = 10 } }
  helpers.write_feedback(repository, {
    helpers.comment(repository, { file = "values.lua", comment = "Lines", range = { start_line = 1, end_line = 2 } }),
    helpers.comment(repository, {
      file = "values.lua",
      comment = "Characters",
      range = { start_line = 3, end_line = 3, start_col = 7, end_col = 12 },
    }),
    helpers.comment(repository, {
      file = "values.lua",
      comment = "Block",
      range = { start_line = 1, end_line = 2, columns = columns },
    }),
  })
  setup()

  child.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(repository, "values.lua")))

  local groups = child.lua([[
    local namespace = vim.api.nvim_create_namespace("nvim-feedback")
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
      local details = mark[4]
      local group = details.hl_group or details.line_hl_group
      if group then
        table.insert(groups, {
          start_line = mark[2] + 1,
          end_line = details.end_row + 1,
          kind = details.hl_group and "text" or "line",
          group = group,
        })
      end
    end
    return groups
  ]])
  MiniTest.expect.equality(groups, {
    { start_line = 1, end_line = 2, kind = "line", group = "NvimFeedbackRange" },
    { start_line = 1, end_line = 1, kind = "text", group = "NvimFeedbackRange" },
    { start_line = 2, end_line = 2, kind = "text", group = "NvimFeedbackRange" },
    { start_line = 3, end_line = 3, kind = "text", group = "NvimFeedbackRange" },
  })

  helpers.remove(repository)
end

return tests
