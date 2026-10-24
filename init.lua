-- One file per concern; this file only decides the order.
--
--   usage       counts mapped keys; :UsageReport and :FrictionNote
--   options     plain Vim options (tools puts language tools on PATH)
--   gui         Neovide: font, motion, see-through surface
--   theme       every colour, built from the desktop palette; :Look
--   plugins     the few plugins and their setup (explorer, statusline)
--   keys        every global key (Alt on Linux/Windows, Cmd on macOS; util)
--   panes       what the pane keys do: focus, swap, zoom, flip, resize, close
--   words       double-click marks the word's other occurrences
--   focus       the focused pane at full strength, the others dimmed
--   dividers    the divider under the pointer lights up
--   projects    open folder, per-folder sessions, one project per window
--   lsp         language servers, diagnostics, format on save
--   library     installed code is read-only, without diagnostics
--   sync        pulls this config from GitHub after startup (clean checkout only)
--
-- Loaded on demand: ocaml (ocp-indent, ocamlformat, dune; from
-- after/ftplugin), run (F5, lazygit), explorer, statusline, tools, util.

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
