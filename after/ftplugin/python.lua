require("configs.runner").setup_ft(0, "python")

vim.api.nvim_create_autocmd("TermOpen", {
  buffer = 0,
  callback = function()
    vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true, desc = "Close terminal" })
  end,
})
