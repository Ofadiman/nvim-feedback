vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/deps/mini.test")

require("mini.test").setup()
