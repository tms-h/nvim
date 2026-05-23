vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local cwd = vim.fn.getcwd()
    if cwd == vim.env.HOME or cwd == "/" then
      local projects = vim.env.HOME .. "/Desktop/Projects"
      if vim.fn.isdirectory(projects) == 1 then
        vim.cmd("cd " .. vim.fn.fnameescape(projects))
      end
    end
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
})

vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
  pattern = "term://*",
  callback = function()
    if vim.bo.buftype == "terminal" then
      vim.cmd("startinsert")
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp", "python" },
  callback = function(ev)
    pcall(function()
      require("lazy").load({ plugins = { "nvim-treesitter" } })
    end)
    if ev.match == "c" or ev.match == "cpp" then
      vim.opt_local.cindent = false
      vim.opt_local.smartindent = false
      vim.opt_local.expandtab = true
      vim.opt_local.shiftwidth = 2
      vim.opt_local.tabstop = 2
      vim.opt_local.softtabstop = -1
    end
    vim.opt_local.indentexpr = "nvim_treesitter#indent()"
  end,
})
