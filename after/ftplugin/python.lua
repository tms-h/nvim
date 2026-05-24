local python = vim.fn.trim(vim.fn.system({ vim.o.shell, "-lc", "which python3" }))
if python == "" then python = "python3" end

local function run_python()
  vim.cmd("w")
  local file = vim.fn.expand("%:p")
  vim.cmd("split | term " .. python .. " " .. vim.fn.shellescape(file))
end

local key = vim.g.neovide and "<D-r>" or "<F5>"
vim.keymap.set("n", key, run_python, { buffer = true, desc = "Python: run" })
vim.keymap.set("n", "<F5>", run_python, { buffer = true, desc = "Python: run" })

vim.api.nvim_create_autocmd("TermOpen", {
  buffer = 0,
  callback = function()
    vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true })
  end,
})
