vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  defaults = { lazy = true },
  install = { colorscheme = { "everforest" } },
  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin", "tohtml", "getscript", "getscriptPlugin",
        "gzip", "logipat", "matchit", "tar", "tarPlugin",
        "rrhelper", "spellfile_plugin", "vimball", "vimballPlugin",
        "zip", "zipPlugin", "tutor", "rplugin", "synmenu",
        "optwin", "compiler", "bugreport",
      },
    },
  },
})

require("options")
require("keymaps")
require("autocmds")
