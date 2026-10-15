local map = vim.keymap.set
local buffer_close = require "configs.buffer_close"

local super = require("util.modifier").chord

-- Keyboard buffer switches should not trap us in Terminal-mode. BufEnter
-- checks this flag and leaves terminal buffers in Terminal-Normal mode.
local function keyboard_buffer_switch(command)
  vim.g.nvim_keyboard_buffer_switch = true
  local ok, err = pcall(vim.cmd, command)
  vim.g.nvim_keyboard_buffer_switch = false
  if not ok then
    error(err)
  end
end

map("n", ";", ":", { desc = "Command mode" })
map("i", "jk", "<ESC>")
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- Multicursor: Space m exposes every action, including in terminal Neovim.
local mc = require "multicursor-nvim"
map({ "n", "x" }, "<leader>mn", function()
  mc.matchAddCursor(1)
end, { desc = "Add next matching cursor" })
map({ "n", "x" }, "<leader>ms", function()
  mc.matchSkipCursor(1)
end, { desc = "Skip next match" })
map({ "n", "x" }, "<leader>ma", mc.matchAllAddCursors, { desc = "Add all matching cursors" })
map({ "n", "x" }, "<leader>mj", function()
  mc.lineAddCursor(1)
end, { desc = "Add cursor below" })
map({ "n", "x" }, "<leader>mk", function()
  mc.lineAddCursor(-1)
end, { desc = "Add cursor above" })
map({ "n", "x" }, "<leader>mx", mc.clearCursors, { desc = "Clear extra cursors" })
map({ "n", "x" }, "<leader>mr", mc.restoreCursors, { desc = "Restore previous cursors" })
if vim.g.neovide then
  map({ "n", "x" }, super "d", function()
    mc.matchAddCursor(1)
  end, { desc = "Add next matching cursor" })
  map("n", super "LeftMouse", mc.handleMouse, { desc = "Add or remove cursor at mouse" })
  map("n", super "LeftDrag", mc.handleMouseDrag)
  map("n", super "LeftRelease", mc.handleMouseRelease)
end
map("n", "<leader>fk", "<cmd>Telescope keymaps<cr>", { desc = "Find keyboard shortcuts" })

-- Double-click a word to keep it selected and highlight every exact occurrence.
map(
  { "n", "i" },
  "<2-LeftMouse>",
  "<Esc><2-LeftMouse><Esc><Cmd>if !empty(expand('<cword>')) | set hlsearch | silent! execute 'keepjumps normal! *N' | execute 'normal! viw' | endif<CR>",
  { desc = "Select word and highlight occurrences" }
)

-- ── Comments (Cmd+/ on macOS, Ctrl+/ on Windows) ──
local function comment_operator()
  return require("vim._comment").operator()
end

map("n", super "/", function()
  return comment_operator() .. "_"
end, { desc = "Toggle comment on current line", expr = true })
map("x", super "/", comment_operator, { desc = "Toggle comment on selection", expr = true })
map("i", super "/", function()
  return "<C-o>" .. comment_operator() .. "_"
end, { desc = "Toggle comment on current line", expr = true })

-- ── Undo/Redo (Cmd on macOS, Ctrl on Windows) ──
map("n", super "z", "u", { desc = "Undo" })
map("n", super "S-z", "<C-r>", { desc = "Redo" })
map("i", super "z", "<C-o>u", { desc = "Undo" })
map("i", super "S-z", "<C-o><C-r>", { desc = "Redo" })

-- ── Find (VSCode-style) ──
map("n", super "p", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", super "S-p", "<cmd>Telescope commands<cr>", { desc = "Command palette" })
map("n", super "S-f", "<cmd>Telescope live_grep<cr>", { desc = "Search in project" })

-- ── Tabs (primary modifier + VS Code-style chords) ──
map("n", super "w", buffer_close.delete_from_keyboard, { desc = "Close tab" })
map("n", super "S-w", buffer_close.close_window_and_buffer, { desc = "Close split and tab" })
map("n", super "t", "<cmd>enew<cr>", { desc = "New tab" })
map("n", super "S-t", buffer_close.reopen, { desc = "Reopen closed tab" })
map("n", super "S-]", function()
  keyboard_buffer_switch "BufferLineCycleNext"
end, { desc = "Next tab" })
map("n", super "S-[", function()
  keyboard_buffer_switch "BufferLineCyclePrev"
end, { desc = "Previous tab" })
-- Ctrl+Tab and Ctrl+PageDown are Ctrl on every OS in Chrome and VS Code alike.
for _, keys in ipairs { { "<C-Tab>", "<C-S-Tab>" }, { "<C-PageDown>", "<C-PageUp>" } } do
  map({ "n", "i", "t" }, keys[1], function()
    keyboard_buffer_switch "BufferLineCycleNext"
  end, { desc = "Next tab" })
  map({ "n", "i", "t" }, keys[2], function()
    keyboard_buffer_switch "BufferLineCyclePrev"
  end, { desc = "Previous tab" })
end
-- Like Chrome, 1-8 jump to that tab and 9 jumps to the last one.
for i = 1, 9 do
  local index = i == 9 and -1 or i
  map("n", super(tostring(i)), function()
    keyboard_buffer_switch("BufferLineGoToBuffer " .. index)
  end, { desc = i == 9 and "Last tab" or "Tab " .. i })
end

-- ── Sidebar (Cmd+B on macOS, Ctrl+B on Windows) ──
map("n", super "b", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle sidebar" })

-- ── Leader: Find ──
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help" })
map("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { desc = "Todos" })

-- ── Leader: Files & buffers ──
map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "File explorer" })
map("n", "<leader>n", "<cmd>enew<cr>", { desc = "New file" })
map("n", "<leader>c", buffer_close.delete, { desc = "Close buffer" })
map("n", "<leader>q", "<cmd>silent! close<cr>", { desc = "Close window" })
map("n", "<leader>Q", buffer_close.close_window_and_buffer, { desc = "Close window and buffer" })

-- ── Buffer cycling (Shift+H/L) ──
map("n", "<S-h>", function()
  keyboard_buffer_switch "BufferLineCyclePrev"
end, { desc = "Previous tab" })
map("n", "<S-l>", function()
  keyboard_buffer_switch "BufferLineCycleNext"
end, { desc = "Next tab" })

-- ── Window navigation ──
map("n", "<C-h>", "<C-w>h", { desc = "Left window" })
map("n", "<C-l>", "<C-w>l", { desc = "Right window" })
map("n", "<C-j>", "<C-w>j", { desc = "Lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Upper window" })
map("t", "<C-h>", "<C-\\><C-n><C-w>h")
map("t", "<C-l>", "<C-\\><C-n><C-w>l")
map("t", "<C-j>", "<C-\\><C-n><C-w>j")
map("t", "<C-k>", "<C-\\><C-n><C-w>k")
-- Double Esc so a single Esc still reaches lazygit, fzf and other TUIs.
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal: normal mode" })

-- ── Window resize (Ctrl+Arrow) ──
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase width" })

-- ── Terminal splits ──
map("n", "<leader>th", "<cmd>belowright split | resize 15 | term<cr>", { desc = "Terminal (bottom)" })
map("n", "<leader>tv", "<cmd>vsplit | term<cr>", { desc = "Terminal (side)" })

-- ── Visual ──
map("v", "<", "<gv")
map("v", ">", ">gv")

-- ── Move lines (Alt+J/K) ──
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi")
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi")
map("v", "<A-j>", ":m '>+1<cr>gv=gv")
map("v", "<A-k>", ":m '<-2<cr>gv=gv")

-- ── Diagnostics ──
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics" })
map("n", "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer diagnostics" })

-- ── Lint & LeetCode ──
map("n", "<leader>ll", function()
  require("lint").try_lint()
end, { desc = "Run linter" })
map("n", "<leader>ls", function()
  require("configs.leetcode_stats").open()
end, { desc = "LeetCode stats" })

-- ── Sessions ──
map("n", "<leader>Ss", function()
  require("persistence").load()
end, { desc = "Restore session" })
map("n", "<leader>Sl", function()
  require("persistence").load { last = true }
end, { desc = "Last session" })
map("n", "<leader>Sd", function()
  require("persistence").stop()
end, { desc = "Stop session" })

-- ── Todo ──
local todo = require "configs.todo"
map("n", "<leader>td", todo.toggle, { desc = "Todo list" })
map("n", "<leader>tw", todo.toggle_widget, { desc = "Toggle todo widget" })

-- ── Neovide ──
if vim.g.neovide then
  -- Start one zoom step (Super+-) below the base font size.
  vim.g.neovide_scale_factor = vim.g.neovide_scale_factor or 1 / 1.25

  local function change_scale_factor(multiplier)
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * multiplier
  end

  local function paste()
    vim.api.nvim_paste(vim.fn.getreg "+", true, -1)
  end
  map("n", super "c", '"+yy', { desc = "Copy line" })
  map("i", super "c", '<C-o>"+yy', { desc = "Copy line" })
  map("v", super "c", '"+y', { desc = "Copy selection" })
  map("s", super "c", '<C-g>"+y', { desc = "Copy selection" })
  map({ "n", "i", "v", "c", "t" }, super "v", paste, { silent = true })
  map({ "n", "i", "v", "c", "t" }, super "=", function()
    change_scale_factor(1.25)
  end, { silent = true })
  map({ "n", "i", "v", "c", "t" }, super "-", function()
    change_scale_factor(1 / 1.25)
  end, { silent = true })
  map({ "n", "i", "v", "c", "t" }, super "0", function()
    vim.g.neovide_scale_factor = 1 / 1.25
  end, { silent = true, desc = "Reset zoom" })
end

map("n", "<leader>gs", function()
  require("configs.config_sync").sync()
end, { desc = "Sync config to GitHub" })
