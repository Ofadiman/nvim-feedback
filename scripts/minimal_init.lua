local COVERAGE_DIRECTORY = vim.fs.joinpath(vim.fn.getcwd(), "coverage")

vim.opt.runtimepath:prepend(".")
vim.opt.runtimepath:append("deps/mini.test")
package.path = "deps/luacov/src/?.lua;" .. package.path
package.preload.lfs = function()
  return {
    dir = vim.fs.dir,
    attributes = function(path)
      local stat = vim.uv.fs_stat(path)
      return stat and { mode = stat.type }
    end,
  }
end

vim.fn.mkdir(COVERAGE_DIRECTORY, "p")
jit.off()

local luacov = require("luacov.runner")
luacov.init({
  include = { "^lua/nvim%-feedback/" },
  includeuntestedfiles = { "lua/nvim-feedback" },
  statsfile = vim.fs.joinpath(COVERAGE_DIRECTORY, "luacov.stats.out"),
  reportfile = vim.fs.joinpath(COVERAGE_DIRECTORY, "luacov.report.out"),
})

require("mini.test").setup()

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    luacov.shutdown()
    if not MiniTest.current.all_cases then
      return
    end

    luacov.run_report()
    local report = vim.fn.readfile(luacov.configuration.reportfile)
    local summary_start = vim.fn.index(report, "Summary") + 3
    io.stdout:write(table.concat(vim.list_slice(report, summary_start), "\n"), "\n")
    io.stdout:write("Full report: ", vim.fn.fnamemodify(luacov.configuration.reportfile, ":."), "\n")
  end,
})
