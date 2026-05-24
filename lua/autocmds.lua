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

vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.fn.argc() == 0 then
      require("persistence").load({ last = true })
    end
  end,
})

vim.api.nvim_create_autocmd("SessionLoadPost", {
  callback = function()
    vim.schedule(function()
      pcall(function() require("lazy").load({ plugins = { "nvim-treesitter" } }) end)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
          vim.api.nvim_buf_call(buf, function()
            if vim.bo.filetype == "" then vim.cmd("filetype detect") end
            pcall(vim.treesitter.start)
          end)
        end
      end
    end)
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
      vim.cmd("setlocal winhighlight=Normal:TermNormal")
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
    pcall(vim.treesitter.start)
  end,
})
