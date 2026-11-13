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
-- Paste asks the Wayland clipboard for text only. Neovim's own provider runs
-- `wl-paste` with no type, which hands over whatever was copied: with only a
-- screenshot on the clipboard, `p` pasted the PNG's bytes (2026-11-13, 174
-- lines of binary into a .ml, and the NULs desynced ocamllsp). With no text
-- copied, `p` now pastes nothing and says only "E353: Nothing in register".
-- Copying, the cache and every other system (Mac, tmux) stay Neovim's own;
-- tests set g:clipboard first.
if
  vim.g.clipboard == nil
  and (vim.env.WAYLAND_DISPLAY or "") ~= ""
  and vim.fn.executable "wl-copy" == 1
  and vim.fn.executable "wl-paste" == 1
then
  local function text_paste(...)
    local cmd = { "wl-paste", "--no-newline", "--type", "text", ... }
    return function()
      local r = vim.system(cmd):wait()
      return r.code == 0 and vim.split(r.stdout, "\n", { plain = true }) or {}
    end
  end
  vim.g.clipboard = {
    name = "wl-copy, text-only paste",
    copy = {
      ["+"] = { "wl-copy", "--type", "text/plain" },
      ["*"] = { "wl-copy", "--primary", "--type", "text/plain" },
    },
    paste = { ["+"] = text_paste(), ["*"] = text_paste "--primary" },
    cache_enabled = 1,
  }
end
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
