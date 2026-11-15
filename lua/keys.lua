-- Every global key, in one place, except the Claude helpers' own keys: Alt+K
-- (goose.lua), Alt+L (goose_ask.lua) and Space r, ]r, [r, Alt+. (seconder.lua);
-- Space i (iron.lua, mini-iron's fe); Up/Down on the command line
-- (cmdline.lua); and the pointer's moves in Neovide (dividers.lua). Buffer-local
-- keys live with their feature: OCaml (ocaml.lua, and K in lsp.lua), the tree
-- (explorer.lua), a terminal's click (panes.lua).
--
-- Rules:
-- * Alt/Cmd chords (`super`) are the VS Code / Chrome shortcuts: Alt on
--   Linux and Windows, Cmd on macOS (util.lua).
-- * Pane, tab, find and file chords do the same thing from Normal, Insert, a
--   selection or a terminal: they first leave that mode (`call`); a
--   terminal you land in goes back to typing. Edit chords work where you edit.
-- * Stock Vim and Neovim keys keep their meaning (;, -, H, L, gi, ga,
--   grr, grn, gra, gri, grt, gO, K, gc, [d, ]d). Exceptions, with reasons:
--   s (flash.nvim's jump, its own default key, in every file: stock s is
--   cl, and in a selection c); Visual S (vim-surround's wrap; stock it is
--   linewise c); ds, cs, ys (vim-surround: they take over d, c and y
--   followed by flash's s); c, C, normal S and Visual p edit as usual but
--   leave the clipboard alone (below);
--   gd (go to definition: the stock heuristic aims at the same thing and
--   misses across files); <C-h/j/k/l> (pane focus; most used keys);
--   <C-Arrows> (move the divider: brief); <C-PageUp/Down> (file tabs, as in
--   Chrome); Visual < > (keep the selection); Space (leader only); K in OCaml
--   (the full type, lsp.lua); gt in OCaml (wrap in a thunk, bcc32's key;
--   tab pages here only hold an Alt+F zoom, ocaml.lua).
-- VS Code keys not taken, with what they would have stolen: Ctrl+T (symbol
-- in workspace: Vim's tag-back) and Alt+T (new tab) -> Space f s; Ctrl+K
-- Ctrl+Alt+S / Ctrl+K Ctrl+R (stage / revert change: Ctrl+K is focus up) ->
-- Space g s / Space g r. Cmd+= / Cmd+- / Cmd+0 (Mac zoom) -> Ctrl, as on
-- Linux: Alt/Cmd+= / - resize panes, Omarchy's Super+= / Super+-.
local map = vim.keymap.set
local util = require "util"
local super = util.chord
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
-- Alt+= / Alt+- (Cmd on the Mac) widen / narrow the pane, Alt+Shift+= /
-- Alt+Shift+- make it taller / shorter: Omarchy's Super+= / Super+- for
-- windows. Without leaving the mode. Through herdr Alt+Shift+= arrives as
-- <M-S-=>; Neovide sends <M-+>.
for how, keys in pairs {
  wider = { "=" },
  narrower = { "-" },
  taller = { "S-=", "+" },
  shorter = { "S--", "_" },
} do
  for _, k in ipairs(keys) do
    map(ALL, super(k), function()
      panes.resize(how)
    end, { desc = "Pane " .. how })
  end
end
-- Inside tmux or herdr, terminals and tabs are the multiplexer's
-- (util.in_mux): Alt+Return splits its pane, Alt+T / Alt+Shift+T / Alt+1..9
-- and Ctrl+Shift+Left/Right act on its tabs, and Neovim maps none of them.
-- Ctrl+Tab stays Neovim's: it cycles the open files (panes.cycle).
local in_mux = util.in_mux
if not in_mux then
  map(ALL, super "CR", pane "new_terminal", { expr = true, desc = "New terminal on the longer side" })
  -- Ctrl+` (Ctrl on the Mac too, as in VS Code): the terminal panel at the bottom.
  map(ALL, "<C-`>", pane "toggle_panel", { expr = true, desc = "Toggle the bottom terminal panel" })
end
map(ALL, super "f", pane "zoom", { expr = true, desc = "Zoom pane (toggle)" })
map(ALL, super "j", pane "flip", { expr = true, desc = "Flip split direction" })
map(ALL, super "w", call "require('panes').close()", { expr = true, desc = "Close what has focus" })
-- Quit the editor, like Cmd+Q quits an app (asks about unsaved files). In tmux
-- the pane then closes or drops to its shell; tmux leaves Alt+Q to Neovim.
map(ALL, super "q", "<Cmd>confirm qa<CR>", { desc = "Quit Neovim" })
-- Option+W on the Mac is Super+W (Hyprland's killactive): quit this Neovide
-- window, like its red close button (asks only about unsaved files).
-- Karabiner passes Option+W through to Neovide unchanged for this. Neovide
-- only: in Ghostty, Karabiner turns the physical Cmd into Alt, so Cmd+W
-- arrives as Alt+W (via herdr-keys close-pane) and must close the tab, not
-- quit; the Cmd-to-Alt mirror below gives it panes.close().
if util.is_macos and vim.g.neovide then
  map(ALL, "<M-w>", "<Cmd>confirm qa<CR>", { desc = "Quit Neovide (Super+W)" })
end

-- ── Tabs (Chrome; the multiplexer's inside tmux or herdr) ──────────────────
local function step(n)
  return call(("require('panes').cycle(%d)"):format(n))
end
-- Ctrl+Tab is the innermost tab key: files here, and the multiplexer's tabs
-- only when there is one file (panes.cycle).
map(ALL, "<C-Tab>", step(1), { expr = true, desc = "Next tab" })
map(ALL, "<C-S-Tab>", step(-1), { expr = true, desc = "Previous tab" })
if not in_mux then
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
map("n", "<leader>ht", "<Cmd>Hardtime toggle<CR>", { desc = "Hardtime toggle" })
map("n", "<leader>hr", "<Cmd>Hardtime report<CR>", { desc = "Hardtime report" })
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })

-- Double-click selects the word and marks its other occurrences (words.lua).
map("n", "<2-LeftMouse>", "<LeftMouse><Cmd>lua require('words').select_word()<CR>", { desc = "Select word" })
map("i", "<2-LeftMouse>", "<Esc><LeftMouse><Cmd>lua require('words').select_word()<CR>", { desc = "Select word" })
-- Alt/Cmd+click is a plain click everywhere (stock Alt+click starts a block
-- selection, which nobody meant).
map({ "n", "i", "x", "t" }, super "LeftMouse", "<LeftMouse>", { desc = "Plain click (no block selection)" })

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
-- in VS Code. Retyping text (c, S) or pasting over a selection does not
-- replace it, so the same text pastes again and again. A named register
-- ("ac) still gets the old text. (s is flash's jump and Visual S
-- vim-surround's wrap, below.)
for _, key in ipairs { "c", "C", "S" } do
  map(key == "S" and "n" or { "n", "x" }, key, function()
    return (vim.v.register == "+" or vim.v.register == '"') and '"_' .. key or key
  end, { expr = true, desc = "Change, keep the clipboard" })
end
-- Visual P is the stock put that keeps the register.
map("x", "p", "P", { desc = "Paste over the selection, keep the clipboard" })
-- s jumps (flash.nvim, plugins.lua): type a couple of letters, then press the
-- label on the match you want. After an operator too (ds<label> deletes to
-- it). Stock s is cl, still there.
map({ "n", "x", "o" }, "s", function()
  require("flash").jump()
end, { desc = "Jump: type letters, press the label (flash)" })
-- vim-surround's own keys (plugins.lua turns its unnamed ones off), named
-- for the key hints; vim-repeat makes . repeat them. Its insert-mode Ctrl+S
-- is left out: Neovim's signature help has it. ds and cs win over d or c
-- followed by flash's s; dS, cS... nothing else here uses them.
for _, m in ipairs {
  { "n", "ds", "<Plug>Dsurround", "Surround: delete ds{char}, e.g. ds( or dst" },
  { "n", "cs", "<Plug>Csurround", "Surround: change cs{old}{new}, e.g. cs([" },
  { "n", "cS", "<Plug>CSurround", "Surround: change, new pair on its own lines" },
  { "n", "ys", "<Plug>Ysurround", "Surround: add ys{motion}{char}, e.g. ysiw)" },
  { "n", "yS", "<Plug>YSurround", "Surround: add, on their own lines" },
  { "n", "yss", "<Plug>Yssurround", "Surround: add around the line, yss{char}" },
  { "n", "ySs", "<Plug>YSsurround", "Surround: add around the line, on their own lines" },
  { "n", "ySS", "<Plug>YSsurround", "Surround: add around the line, on their own lines" },
  { "x", "S", "<Plug>VSurround", "Surround: wrap the selection, S{char}" },
  { "x", "gS", "<Plug>VgSurround", "Surround: wrap the selection, indented" },
  { "i", "<C-g>s", "<Plug>Isurround", "Surround: type a pair around the cursor" },
  { "i", "<C-g>S", "<Plug>ISurround", "Surround: type a pair on lines of their own" },
} do
  map(m[1], m[2], m[3], { remap = true, desc = m[4] })
end
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
  -- Ctrl+= / Ctrl+- / Ctrl+0, on the Mac too: Chrome's and VS Code's zoom on
  -- Linux, and kitty's text size here. Alt/Cmd+= / - resize panes (above).
  -- Zoom works while typing a command too.
  local modes = { "n", "i", "x", "s", "c", "t" }
  map(modes, "<C-=>", zoom(1.25), { desc = "Zoom in" })
  map(modes, "<C-->", zoom(1 / 1.25), { desc = "Zoom out" })
  map(modes, "<C-0>", zoom(), { desc = "Reset zoom" })
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
local system_keys = util.is_macos and { q = true, h = true, m = true, n = true, ["`"] = true } or {}
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
if util.is_macos then
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
