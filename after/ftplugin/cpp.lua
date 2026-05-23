vim.opt_local.expandtab = true
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = -1

-- Compile and run current file: F5 (or Cmd+R in Neovide)
local function run_cpp()
  vim.cmd("w")
  local out = "/tmp/cpp_out"
  local file = vim.fn.expand("%:p")
  vim.cmd("split | term g++ -std=c++20 -Wall -o " .. out .. " " .. file .. " && " .. out)
end

local key = vim.g.neovide and "<D-r>" or "<F5>"
vim.keymap.set("n", key, run_cpp, { buffer = true, desc = "C++: compile and run" })
vim.keymap.set("n", "<F5>", run_cpp, { buffer = true, desc = "C++: compile and run" })

-- Close terminal pane with q
vim.api.nvim_create_autocmd("TermOpen", {
  buffer = 0,
  callback = function()
    vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true })
  end,
})
