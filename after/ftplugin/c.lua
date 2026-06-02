-- Runtime $VIMRUNTIME/ftplugin/c.vim can run after FileType autocmds and leave noexpandtab / tabstop=8.
vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = -1

-- CompetiTest (buffer-local; shadows global <leader>a/<leader>e in c/cpp only)
vim.keymap.set("n", "<leader>r", "<cmd>CompetiTest run<cr>", { buffer = true, desc = "CompetiTest: run" })
vim.keymap.set("n", "<leader>a", "<cmd>CompetiTest add_testcase<cr>", { buffer = true, desc = "CompetiTest: add testcase" })
vim.keymap.set("n", "<leader>e", "<cmd>CompetiTest edit_testcase<cr>", { buffer = true, desc = "CompetiTest: edit testcase" })
