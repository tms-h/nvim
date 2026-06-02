vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = -1

local runner = require("configs.runner")
runner.setup_ft(0, "cpp")

vim.api.nvim_create_autocmd("TermOpen", {
  buffer = 0,
  callback = function()
    vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true, desc = "Close terminal" })
  end,
})
