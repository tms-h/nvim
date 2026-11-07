-- One file per concern; this file only decides the order.
--
--   usage       counts mapped keys; :UsageReport and :FrictionNote
--   options     plain Vim options; also loads tools (language tools on PATH)
--               and cmdline (typed commands in a centred box)
--   gui         Neovide: font, motion, floats, padding
--   theme       every colour, built from the desktop palette (surface); :Look
--   plugins     the few plugins and their setup; loads explorer, statusline,
--               tabs (the tab bar), snippets and finder (mini.pick waits for
--               first use)
--   keys        every global key (Alt on Linux/Windows, Cmd on macOS; util)
--   panes       what the pane keys do: focus, swap, zoom, flip, resize, close
--   words       double-click marks the word's other occurrences
--   focus       which pane has focus: its title row stands out, others dim
--   dividers    the divider under the pointer lights up
--   projects    open folder, per-folder sessions, one project per window
--   lsp         language servers, diagnostics, format on save
--   library     installed code is read-only, without diagnostics
--   sync        pulls this config from GitHub after startup (clean checkout only)
--   goose       type pseudocode, Alt+K: the underlined typed lines become code;
--               Alt+L asks a question about the code (goose_ask)
--   seconder    Space r: a reviewer that writes CR comments; ]r / [r jump
--
-- Loaded on first use: hunks (change keys), run (F5, lazygit), ocaml
-- (ocp-indent, ocamlformat, dune; from after/ftplugin).

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Counts every key this config maps, so it must wrap vim.keymap.set first.
require("usage").setup()

require "options"
require "gui"
require("theme").setup()
require "plugins"
require "keys"
require("panes").setup()
require("words").setup()
require("focus").setup()
require("dividers").setup()
require("projects").setup()
require("lsp").setup()
require("library").setup()
require("sync").setup()
require("goose").setup()
require("goose_ask").setup()
require("seconder").setup()
