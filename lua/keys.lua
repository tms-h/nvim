-- Every global key, in one place. Buffer-local keys live with their feature:
-- OCaml (ocaml.lua), the tree (explorer.lua), completion (below).
--
-- Rules:
-- * Alt/Cmd chords (`super`) are the VS Code / Chrome shortcuts: Alt on
--   Linux and Windows, Cmd on macOS (util.lua).
-- * Pane, tab, find and file chords do the same thing from Normal, Insert, a
--   selection or a terminal: they first leave that mode (`call`); a
--   terminal you land in goes back to typing. Edit chords work where you edit.
-- * Stock Vim and Neovim keys keep their meaning (s, ;, -, H, L, gi, ga,
--   grr, grn, gra, gri, grt, gO, K, gc, [d, ]d). Exceptions, with reasons:
--   c, C, s, S and Visual p edit as usual but leave the clipboard alone
--   (below);
--   gd (go to definition: the stock heuristic aims at the same thing and
--   misses across files); <C-h/j/k/l> (pane focus; most used keys);
--   <C-Arrows> (move the divider: brief); <C-PageUp/Down> (file tabs, as in
--   Chrome); Visual < > (keep the selection); Space (leader only); K in OCaml
--   (the full type, lsp.lua); gt in OCaml (wrap in a thunk, bcc32's key;
--   tab pages here only hold an Alt+F zoom, ocaml.lua).
-- VS Code keys not taken, with what they would have stolen: Ctrl+T (symbol
-- in workspace: Vim's tag-back) and Alt+T (new tab) -> Space f s; Ctrl+K
-- Ctrl+Alt+S / Ctrl+K Ctrl+R (stage / revert change: Ctrl+K is focus up) ->
-- Space g s / Space g r.
local map = vim.keymap.set
local super = require("util").chord
local panes = require "panes"

local ALL = { "n", "i", "x", "s", "t" }

-- A key that leaves the current mode, then runs a Lua call (an expr map).
-- A terminal leaves with :stopinsert, not <C-\><C-n>: a stray Ctrl+\ typed
-- just before would pair with that one and reach the shell as a quit signal.
local function call(lua)
  local run = "<Cmd>lua " .. lua .. "<CR>"
  return function()
    return (vim.api.nvim_get_mode().mode == "t" and "<Cmd>stopinsert<CR>" or "<C-\\><C-n>") .. run
  end
end
local function pane(name, arg)
  return call(("require('panes').run(%q%s)"):format(name, arg and (", %q"):format(arg) or ""))
end
-- The same, run from the editor pane (from the tree or a terminal, it acts
-- on the files).
local function in_editor(lua)
  return call(("require('panes').in_editor(function() %s end)"):format(lua))
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
-- Inside tmux, terminals and tabs are tmux's (util.in_tmux): Alt+Return
-- splits a tmux pane, Alt+T / Alt+Shift+T / Alt+1..9 / Ctrl+Tab act on tmux
-- tabs (tmux.conf binds them outright), and Neovim maps none of them.
local in_tmux = require("util").in_tmux
if not in_tmux then
  map(ALL, super "CR", pane "new_terminal", { expr = true, desc = "New terminal on the longer side" })
  -- Ctrl+` (Ctrl on the Mac too, as in VS Code): the terminal panel at the bottom.
  map(ALL, "<C-`>", pane "toggle_panel", { expr = true, desc = "Toggle the bottom terminal panel" })
end
map(ALL, super "f", pane "zoom", { expr = true, desc = "Zoom pane (toggle)" })
map(ALL, super "j", pane "flip", { expr = true, desc = "Flip split direction" })
map(ALL, super "w", call "require('panes').close()", { expr = true, desc = "Close what has focus" })
-- Option+W on the Mac is Super+W (Hyprland's killactive): quit this Neovide
-- window, like its red close button (asks only about unsaved files).
-- Karabiner passes Option+W through to Neovide unchanged for this.
if require("util").is_macos then
  map(ALL, "<M-w>", "<Cmd>confirm qa<CR>", { desc = "Quit Neovide (Super+W)" })
end

-- ── Tabs (Chrome; tmux's inside tmux) ──────────────────────────────────────
local function step(n)
  return in_editor(("require('tabs').next(%d)"):format(n))
end
if not in_tmux then
  map(ALL, "<C-Tab>", step(1), { expr = true, desc = "Next tab" })
  map(ALL, "<C-S-Tab>", step(-1), { expr = true, desc = "Previous tab" })
  map(ALL, "<C-PageDown>", step(1), { expr = true, desc = "Next tab" })
  map(ALL, "<C-PageUp>", step(-1), { expr = true, desc = "Previous tab" })
  map(ALL, super "t", in_editor 'vim.cmd("enew")', { expr = true, desc = "New tab" })
  map(ALL, super "S-t", call "require('panes').reopen()", { expr = true, desc = "Reopen closed tab" })
  for i = 1, 9 do
    -- 1-8 go to that tab, 9 to the last one (Chrome).
    local go = in_editor(("require('tabs').go_to(%d)"):format(i == 9 and -1 or i))
    map(ALL, super(tostring(i)), go, { expr = true, desc = i == 9 and "Last tab" or "Tab " .. i })
  end
end

-- ── Find, files, folders (VS Code) ─────────────────────────────────────────
map(ALL, super "p", call "require('finder').files()", { expr = true, desc = "Find file" })
map(ALL, super "S-p", call "require('finder').commands()", { expr = true, desc = "Command palette" })
map(ALL, super "S-f", call "require('finder').grep()", { expr = true, desc = "Search in project" })
map(ALL, super "b", call "require('explorer').toggle()", { expr = true, desc = "Toggle file tree" })
map(ALL, super "o", call "require('projects').pick_folder()", { expr = true, desc = "Open folder" })
map(ALL, super "s", "<Cmd>silent! update<CR>", { desc = "Save" })
for _, f in ipairs {
  { "f", "files", "Find file" },
  { "g", "grep_live", "Search in project" },
  { "b", "buffers", "Find open tab" },
  { "r", "oldfiles", "Recent files" },
  { "h", "help", "Find help" },
  { "k", "keymaps", "Find key" },
  { "d", "diagnostic scope='current'", "Find diagnostic" },
} do
  map("n", "<leader>f" .. f[1], function()
    require("finder").pick(f[2])
  end, { desc = f[3] })
end
map("n", "<leader>fs", function()
  require("finder").symbols()
end, { desc = "Find symbol in project" })

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

-- ── Clipboard ──────────────────────────────────────────────────────────────
-- The clipboard holds what was last copied or cut (y, d, x, Alt+C, Alt+X), as
-- in VS Code. Retyping text (c, s) or pasting over a selection does not
-- replace it, so the same text pastes again and again. A named register
-- ("ac) still gets the old text.
for _, key in ipairs { "c", "C", "s", "S" } do
  map({ "n", "x" }, key, function()
    return (vim.v.register == "+" or vim.v.register == '"') and '"_' .. key or key
  end, { expr = true, desc = "Change, keep the clipboard" })
end
-- Visual P is the stock put that keeps the register.
map("x", "p", "P", { desc = "Paste over the selection, keep the clipboard" })
-- Typing over a Select mode selection (a snippet field) sends the old text
-- nowhere: Select mode's CTRL-R _. Fed in front of any keys already typed; if
-- a key beats it, it lands in Insert mode, where it inserts nothing.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = vim.api.nvim_create_augroup("KeepClipboard", { clear = true }),
  pattern = "*:[sS\19]",
  callback = function()
    vim.api.nvim_feedkeys(vim.keycode "<C-r>_", "ni", false)
  end,
})

-- ── Clipboard and zoom keys (Neovide: the terminal app does these elsewhere)
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
  map({ "n", "i", "c", "t" }, super "v", paste, { desc = "Paste" })
  -- Over a selection, P: nvim_paste would put the replaced text on the
  -- clipboard.
  map("x", super "v", '"+P', { desc = "Paste over the selection" })
  map("s", super "v", '<C-g>"+P', { desc = "Paste over the selection" })
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
-- Changes since the last stage (hunks.lua). Alt+F5 is VS Code's key on every
-- system (Option+F5 on the Mac; Cmd+F5 is VoiceOver there).
local function hunk_jump(dir)
  return in_editor(("require('hunks').go(%q)"):format(dir))
end
map(ALL, "<M-F5>", hunk_jump "next", { expr = true, desc = "Next change" })
map(ALL, "<M-S-F5>", hunk_jump "prev", { expr = true, desc = "Previous change" })
map({ "n", "x" }, "<leader>gs", function()
  require("hunks").stage()
end, { desc = "Stage this change" })
map({ "n", "x" }, "<leader>gr", function()
  require("hunks").reset()
end, { desc = "Undo this change" })
map({ "n", "x" }, "<leader>gp", function()
  require("hunks").preview()
end, { desc = "Show old lines (toggle)" })

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
-- ── Alt on the Mac too ─────────────────────────────────────────────────────
-- Every Cmd chord also answers to (left) Option, so the Linux Alt keys work
-- unchanged on the Mac. An Alt key that already has an action keeps it.
if require("util").is_macos then
  for _, m in ipairs { "n", "i", "x", "s", "o", "t" } do
    for _, km in ipairs(vim.api.nvim_get_keymap(m)) do
      -- (Neovim stores Cmd+Shift+Left as <S-D-Left>.)
      local mods, rest = km.lhs:match "^<([%u%-]-)D%-(.+)>$"
      local alt = mods and "<" .. mods .. "M-" .. rest .. ">"
      if alt and vim.fn.maparg(alt, m) == "" then
        map(m, alt, km.lhs, { remap = true, desc = km.desc })
      end
    end
  end
end

-- Space is the leader; on its own it does not move the cursor.
map({ "n", "x" }, "<Space>", "<Nop>")

-- :W is a common typo of :w (11 uses in the usage log).
vim.api.nvim_create_user_command("W", "write", { bang = true, desc = "Write (typo of :w)" })
