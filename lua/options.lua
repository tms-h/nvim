local o = vim.o

-- Tools first: a GUI launch does not inherit the login shell's PATH.
require("tools").setup_path()

-- Editing
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = -1
o.undofile = true
-- No swap files: their "ATTENTION" dialog is the biggest popup in Vim, and
-- the undo file plus frequent saves already keep the work.
o.swapfile = false
o.clipboard = "unnamedplus"
o.ignorecase = true
o.smartcase = true
o.confirm = true
o.virtualedit = "block"
o.jumpoptions = "view"
o.updatetime = 250
o.timeoutlen = 400
o.mouse = "a"
-- Files changed by agents or git reload without a keypress (projects.lua).
o.autoread = true

-- Completion menu (mini.completion fills it as you type; see plugins.lua).
o.completeopt = "menuone,noselect"
o.pumheight = 12
o.pummaxwidth = 60

-- Screen
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 8
o.sidescrolloff = 8
-- :s does not preview while you type (the old config's choice).
o.inccommand = ""
o.wrap = true
o.linebreak = true
o.breakindent = true
o.showmode = false
o.laststatus = 3
o.cmdheight = 0
o.winborder = "rounded"
o.list = true
o.listchars = "tab:» ,trail:·,nbsp:␣"
-- Markup never hides words: every character in the file is drawn.
o.conceallevel = 0
o.foldlevelstart = 99
o.shortmess = o.shortmess .. "IcC"
-- One thin line between panes, the same glyph at every joint.
o.fillchars = "vert:│,horiz:─,horizup:┴,horizdown:┬,vertleft:┤,vertright:├,verthoriz:┼,eob: ,fold: "

-- Panes: a new pane takes space only from the pane it splits; closing one
-- gives its space only to its neighbour. Nothing else moves.
o.splitright = true
o.splitbelow = true
o.equalalways = false
o.splitkeep = "topline"

-- Messages and the command line: the built-in redesign (no "Press ENTER", no
-- stacks). A message is one line at the bottom, with [+N] when there is
-- more; g< shows the rest. (ui2 reads a height below 1 as a share of the
-- screen, rounded up: 0.01 is one line.)
require("vim._core.ui2").enable { msg = { target = "cmd", cmd = { height = 0.01 } } }
-- Typed commands and searches show in a centred box where the finder opens
-- (cmdline.lua).
require("cmdline").setup()

-- A short flash on what was just copied.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("YankFlash", { clear = true }),
  callback = function()
    vim.hl.on_yank { higroup = "IncSearch", timeout = 200 }
  end,
})

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
