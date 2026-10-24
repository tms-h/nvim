-- Every global key, in one place. Buffer-local keys live with their feature:
-- OCaml (ocaml.lua), the tree (explorer.lua), completion (below).
--
-- Rules:
-- * Alt/Cmd chords (`super`) are the VS Code / Chrome shortcuts: Alt on
--   Linux and Windows, Cmd on macOS (util.lua).
-- * Pane, tab, find and file chords do the same thing from Normal, Insert, a
--   selection or a terminal: they first leave that mode (from_any_mode); a
--   terminal you land in goes back to typing. Edit chords work where you edit.
-- * Stock Vim and Neovim keys keep their meaning (s, ;, -, H, L, gi, ga,
--   grr, grn, gra, gri, grt, gO, K, gc, [d, ]d). Exceptions, with reasons:
--   gd (go to definition: the stock heuristic aims at the same thing and
--   misses across files); <C-h/j/k/l> (pane focus; most used keys);
--   <C-Arrows> (move the divider: brief); <C-PageUp/Down> (file tabs, as in
--   Chrome); Visual < > (keep the selection); Space (leader only); K in OCaml
--   (the full type, lsp.lua).
local map = vim.keymap.set
local super = require("util").chord
local panes = require "panes"

local ALL = { "n", "i", "x", "s", "t" }

-- A key that leaves the current mode, then runs a Lua call (an expr map).
-- A terminal leaves with :stopinsert, not <C-\><C-n>: a stray Ctrl+\ typed
-- just before would pair with that one and reach the shell as a quit signal.
local function from_any_mode(lua)
  local run = "<Cmd>lua " .. lua .. "<CR>"
  return function()
    return (vim.api.nvim_get_mode().mode == "t" and "<Cmd>stopinsert<CR>" or "<C-\\><C-n>") .. run
  end
end
local function pane(name, arg)
  return from_any_mode(("require('panes').run(%q%s)"):format(name, arg and (", %q"):format(arg) or ""))
end
local function call(lua)
  return from_any_mode(lua)
end

-- ── Panes (the Omarchy keys) ───────────────────────────────────────────────
for arrow, dir in pairs { Left = "h", Down = "j", Up = "k", Right = "l" } do
  map(ALL, super(arrow), pane("focus", dir), { expr = true, desc = "Focus pane " .. arrow:lower() })
  map(ALL, "<C-" .. dir .. ">", pane("focus", dir), { expr = true, desc = "Focus pane " .. arrow:lower() })
  map(ALL, super("S-" .. arrow), pane("swap", dir), { expr = true, desc = "Swap pane " .. arrow:lower() })
  -- The divider moves toward the arrow, without leaving the mode.
  map(ALL, "<C-" .. arrow .. ">", function()
    panes.move_divider(arrow)
  end, { desc = "Move divider " .. arrow:lower() })
end
map(ALL, super "CR", pane "new_terminal", { expr = true, desc = "New terminal on the longer side" })
-- Ctrl+` (Ctrl on the Mac too, as in VS Code): the terminal panel at the bottom.
map(ALL, "<C-`>", pane "toggle_panel", { expr = true, desc = "Toggle the bottom terminal panel" })
map(ALL, super "f", pane "zoom", { expr = true, desc = "Zoom pane (toggle)" })
map(ALL, super "j", pane "flip", { expr = true, desc = "Flip split direction" })
map(ALL, super "w", call "require('panes').close()", { expr = true, desc = "Close what has focus" })

-- ── Tabs (Chrome) ──────────────────────────────────────────────────────────
local function tab(cmd)
  return call(("require('panes').in_editor(function() vim.cmd(%q) end)"):format(cmd))
end
local function step(n)
  return call(("require('panes').in_editor(function() require('tabs').next(%d) end)"):format(n))
end
map(ALL, "<C-Tab>", step(1), { expr = true, desc = "Next tab" })
map(ALL, "<C-S-Tab>", step(-1), { expr = true, desc = "Previous tab" })
map(ALL, "<C-PageDown>", step(1), { expr = true, desc = "Next tab" })
map(ALL, "<C-PageUp>", step(-1), { expr = true, desc = "Previous tab" })
map(ALL, super "t", tab "enew", { expr = true, desc = "New tab" })
map(ALL, super "S-t", call "require('panes').reopen()", { expr = true, desc = "Reopen closed tab" })
for i = 1, 9 do
  -- 1-8 go to that tab, 9 to the last one (Chrome).
  local go = ("require('panes').in_editor(function() require('tabs').go_to(%d) end)"):format(i == 9 and -1 or i)
  map(ALL, super(tostring(i)), call(go), { expr = true, desc = i == 9 and "Last tab" or "Tab " .. i })
end

-- ── Find, files, folders (VS Code) ─────────────────────────────────────────
map(ALL, super "p", call "require('finder').files()", { expr = true, desc = "Find file" })
map(ALL, super "S-p", call "require('finder').commands()", { expr = true, desc = "Command palette" })
map(ALL, super "S-f", call "require('finder').grep()", { expr = true, desc = "Search in project" })
map(ALL, super "b", call "require('explorer').toggle()", { expr = true, desc = "Toggle file tree" })
map(ALL, super "o", call "require('projects').pick_folder()", { expr = true, desc = "Open folder" })
map(ALL, super "s", "<Cmd>silent! update<CR>", { desc = "Save" })
map("n", "<leader>ff", function()
  require("finder").pick "files"
end, { desc = "Find file" })
map("n", "<leader>fg", function()
  require("finder").pick "grep_live"
end, { desc = "Search in project" })
map("n", "<leader>fb", function()
  require("finder").pick "buffers"
end, { desc = "Find open tab" })
map("n", "<leader>fr", function()
  require("finder").pick "oldfiles"
end, { desc = "Recent files" })
map("n", "<leader>fh", function()
  require("finder").pick "help"
end, { desc = "Find help" })
map("n", "<leader>fk", function()
  require("finder").pick "keymaps"
end, { desc = "Find key" })
map("n", "<leader>fd", function()
  require("finder").pick "diagnostic scope='current'"
end, { desc = "Find diagnostic" })

-- ── Edit ───────────────────────────────────────────────────────────────────
map("n", "<Esc>", "<Cmd>nohlsearch<CR><Esc>", { desc = "Clear search highlight" })
map("n", super "/", "gcc", { remap = true, desc = "Toggle comment" })
map("x", super "/", "gc", { remap = true, desc = "Toggle comment" })
map("i", super "/", "<C-o>gcc", { remap = true, desc = "Toggle comment" })
map("x", "<", "<gv", { desc = "Indent left, keep selection" })
map("x", ">", ">gv", { desc = "Indent right, keep selection" })
map("n", super "S-j", "<Cmd>move .+1<CR>==", { desc = "Move line down" })
map("n", super "S-k", "<Cmd>move .-2<CR>==", { desc = "Move line up" })
map("i", super "S-j", "<Esc><Cmd>move .+1<CR>==gi", { desc = "Move line down" })
map("i", super "S-k", "<Esc><Cmd>move .-2<CR>==gi", { desc = "Move line up" })
map("x", super "S-j", ":move '>+1<CR>gv=gv", { silent = true, desc = "Move lines down" })
map("x", super "S-k", ":move '<-2<CR>gv=gv", { silent = true, desc = "Move lines up" })
map("n", "<leader>d", function()
  vim.diagnostic.open_float { scope = "line" }
end, { desc = "Line diagnostics" })
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })

-- Double-click selects the word and marks its other occurrences (words.lua).
map("n", "<2-LeftMouse>", "<LeftMouse><Cmd>lua require('words').select_word()<CR>", { desc = "Select word" })
map("i", "<2-LeftMouse>", "<Esc><LeftMouse><Cmd>lua require('words').select_word()<CR>", { desc = "Select word" })
-- Alt/Cmd+click is a plain click everywhere (stock Alt+click starts a block
-- selection, which nobody meant).
map({ "n", "i", "x", "t" }, super "LeftMouse", "<LeftMouse>")

-- Completion menu: Tab / Shift+Tab move, Enter takes the chosen item (else a
-- new line), like VS Code. Inside a snippet, Tab jumps to the next field.
map("i", "<Tab>", function()
  if vim.fn.pumvisible() == 1 then
    return "<C-n>"
  elseif vim.snippet.active { direction = 1 } then
    return "<Cmd>lua vim.snippet.jump(1)<CR>"
  end
  return "<Tab>"
end, { expr = true, desc = "Next completion" })
map("i", "<S-Tab>", function()
  if vim.fn.pumvisible() == 1 then
    return "<C-p>"
  elseif vim.snippet.active { direction = -1 } then
    return "<Cmd>lua vim.snippet.jump(-1)<CR>"
  end
  return "<S-Tab>"
end, { expr = true, desc = "Previous completion" })
-- MiniPairs.cr() returns raw keys, so this map returns raw keys too.
local accept = vim.keycode "<C-y>"
map("i", "<CR>", function()
  if vim.fn.pumvisible() == 1 and vim.fn.complete_info({ "selected" }).selected ~= -1 then
    return accept
  end
  return MiniPairs.cr()
end, { expr = true, replace_keycodes = false, desc = "Accept completion or new line" })

-- ── Clipboard and zoom (Neovide: the terminal app does these elsewhere) ────
if vim.g.neovide then
  local function paste()
    -- A whole copied line (Alt+C with no selection) goes in above the
    -- cursor's line, as in VS Code; anything else goes in at the cursor.
    if vim.api.nvim_get_mode().mode == "n" and vim.fn.getregtype "+" == "V" then
      vim.cmd 'normal! "+P'
      return
    end
    vim.api.nvim_paste(vim.fn.getreg "+", true, -1)
  end
  map("n", super "c", '"+yy', { desc = "Copy line" })
  map("x", super "c", '"+y', { desc = "Copy selection" })
  map("s", super "c", '<C-g>"+y', { desc = "Copy selection" })
  map("x", super "x", '"+d', { desc = "Cut selection" })
  map("s", super "x", '<C-g>"+d', { desc = "Cut selection" })
  map({ "n", "i", "x", "s", "c", "t" }, super "v", paste, { desc = "Paste" })
  local function zoom(factor)
    return function()
      vim.g.neovide_scale_factor = factor and vim.g.neovide_scale_factor * factor or vim.g.default_scale
    end
  end
  map({ "n", "i", "x", "s", "c", "t" }, super "=", zoom(1.25), { desc = "Zoom in" })
  map({ "n", "i", "x", "s", "c", "t" }, super "-", zoom(1 / 1.25), { desc = "Zoom out" })
  map({ "n", "i", "x", "s", "c", "t" }, super "0", zoom(), { desc = "Reset zoom" })
end

-- ── Run and git ────────────────────────────────────────────────────────────
map(ALL, "<F5>", call "require('run').current_file()", { expr = true, desc = "Run this file" })
map(ALL, "<C-S-g>", call "require('run').lazygit()", { expr = true, desc = "Lazygit" })

-- ── Stray keys do nothing ──────────────────────────────────────────────────
-- An Alt chord with no action would otherwise run the plain letter (Alt+X
-- deletes a character, Alt+U undoes). Every unused one is a no-op instead;
-- after an operator (d, c, y…) it cancels the operator, as Esc would.
-- Terminals get the unused ones (the shell's Alt+D, Alt+. …); Alt keys with
-- an action here (Alt+B tree, Alt+F zoom) win over the shell's. The usage log
-- counts these, so it shows which shortcuts get reached for.
local chars = "abcdefghijklmnopqrstuvwxyz0123456789,./;'[]\\`=-!@#$%^&*()_+{}:\"<>?~|"
-- macOS keeps Cmd+Q/H/M/N/` for the app and the system.
local system_keys = require("util").is_macos and { q = true, h = true, m = true, n = true, ["`"] = true } or {}
for i = 1, #chars do
  local c = chars:sub(i, i)
  local name = ({ ["<"] = "lt", ["|"] = "Bar" })[c] or c
  for _, k in ipairs(system_keys[c] and {} or { super(name), c:match "%a" and super("S-" .. c) or nil }) do
    for _, m in ipairs { "n", "i", "x", "s", "o" } do
      if vim.fn.maparg(k, m) == "" then
        -- (A no-op after an operator would count as an empty motion.)
        map(m, k, m == "o" and "<Esc>" or "<Nop>", { desc = "Stray Alt/Cmd key: nothing" })
      end
    end
  end
end
-- Space is the leader; on its own it does not move the cursor.
map({ "n", "x" }, "<Space>", "<Nop>")

-- :W is a common typo of :w (11 uses in the usage log).
vim.api.nvim_create_user_command("W", "write", { bang = true, desc = "Write (typo of :w)" })
