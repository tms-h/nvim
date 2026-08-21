vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
-- No configured plugin uses Neovim's legacy embedded-Python provider. Its
-- pyenv detection can block Python buffers during the initial screen draw.
vim.g.loaded_python3_provider = 0
vim.g.loaded_python_provider = 0
vim.opt.termguicolors = true

-- GUI launches do not always inherit the interactive shell PATH. Keep the
-- toolchains used by LSP, linting, formatting, and OCaml available in Neovide.
local path_separator = vim.fn.has "win32" == 1 and ";" or ":"
local function prepend_path(path)
  if not path or path == "" then
    return
  end
  path = vim.fn.expand(path)
  if vim.fn.isdirectory(path) ~= 1 then
    return
  end

  local entries = vim.split(vim.env.PATH or "", path_separator, { plain = true })
  if not vim.tbl_contains(entries, path) then
    vim.env.PATH = path .. path_separator .. (vim.env.PATH or "")
  end
end

local project_opam = vim.fs.find("_opam", {
  path = vim.fn.getcwd(),
  upward = true,
  type = "directory",
})[1]
prepend_path(project_opam and (project_opam .. "/bin") or nil)
prepend_path(vim.env.OPAM_SWITCH_PREFIX and (vim.env.OPAM_SWITCH_PREFIX .. "/bin") or nil)
prepend_path "~/.cargo/bin"

if vim.fn.has "macunix" == 1 then
  prepend_path "/opt/homebrew/bin"
  prepend_path "~/.opam/default/bin"
  prepend_path "~/.pyenv/shims"

  -- nvm changes PATH from shell startup scripts, which Finder does not run.
  local nvm_default_file = vim.fn.expand "~/.nvm/alias/default"
  if vim.fn.filereadable(nvm_default_file) == 1 then
    local default_node = vim.trim((vim.fn.readfile(nvm_default_file)[1] or ""))
    local node_bins = vim.fn.glob(vim.fn.expand("~/.nvm/versions/node/v" .. default_node .. "*/bin"), false, true)
    table.sort(node_bins)
    prepend_path(node_bins[#node_bins] or "")
  end
elseif vim.fn.has "win32" == 1 then
  prepend_path "~/.pyenv/pyenv-win/shims"
end

local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system {
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  defaults = { lazy = true },
  install = { colorscheme = { "everforest" } },
  -- No configured plugin needs LuaRocks. Disabling it keeps :checkhealth clean
  -- and avoids creating a second Lua toolchain through hererocks.
  rocks = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "tohtml",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "tar",
        "tarPlugin",
        "rrhelper",
        "spellfile_plugin",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
        "tutor",
        "rplugin",
        "synmenu",
        "optwin",
        "bugreport",
      },
    },
  },
})

require "options"
require "keymaps"
require "autocmds"
