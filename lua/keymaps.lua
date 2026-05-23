local map = vim.keymap.set

map("n", ";", ":", { desc = "Command mode" })
map("i", "jk", "<ESC>")
map("n", "<Esc>", "<cmd>nohlsearch<cr>")

-- ── Undo/Redo (Cmd+Z / Cmd+Shift+Z) ──
map("n", "<D-z>", "u", { desc = "Undo" })
map("n", "<D-S-z>", "<C-r>", { desc = "Redo" })
map("i", "<D-z>", "<C-o>u", { desc = "Undo" })
map("i", "<D-S-z>", "<C-o><C-r>", { desc = "Redo" })

-- ── Find (VSCode-style) ──
map("n", "<D-p>", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<D-S-p>", "<cmd>Telescope commands<cr>", { desc = "Command palette" })
map("n", "<D-S-f>", "<cmd>Telescope live_grep<cr>", { desc = "Search in project" })

-- ── Tabs (Cmd+W close, Cmd+N new, Cmd+Shift+[/] cycle) ──
map("n", "<D-w>", function() require("mini.bufremove").delete(0, false) end, { desc = "Close tab" })
map("n", "<D-t>", "<cmd>enew<cr>", { desc = "New tab" })
map("n", "<D-S-]>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next tab" })
map("n", "<D-S-[>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous tab" })
for i = 1, 9 do
  map("n", "<D-" .. i .. ">", "<cmd>BufferLineGoToBuffer " .. i .. "<cr>", { desc = "Tab " .. i })
end

-- ── Sidebar (Cmd+B) ──
map("n", "<D-b>", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle sidebar" })

-- ── Leader: Find ──
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help" })
map("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { desc = "Todos" })

-- ── Leader: Files & buffers ──
map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "File explorer" })
map("n", "<leader>n", "<cmd>enew<cr>", { desc = "New file" })
map("n", "<leader>c", function() require("mini.bufremove").delete(0, false) end, { desc = "Close buffer" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit window" })

-- ── Buffer cycling (Shift+H/L) ──
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous tab" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next tab" })

-- ── Window navigation ──
map("n", "<C-h>", "<C-w>h", { desc = "Left window" })
map("n", "<C-l>", "<C-w>l", { desc = "Right window" })
map("n", "<C-j>", "<C-w>j", { desc = "Lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Upper window" })
map("t", "<C-h>", "<C-\\><C-n><C-w>h")
map("t", "<C-l>", "<C-\\><C-n><C-w>l")
map("t", "<C-j>", "<C-\\><C-n><C-w>j")
map("t", "<C-k>", "<C-\\><C-n><C-w>k")
map("t", "<Esc>", "<C-\\><C-n>", { desc = "Terminal: normal mode" })

-- ── Terminal splits ──
map("n", "<leader>th", "<cmd>belowright split | resize 15 | term<cr>", { desc = "Terminal (bottom)" })
map("n", "<leader>tv", "<cmd>vsplit | term<cr>", { desc = "Terminal (side)" })

-- ── Visual ──
map("v", "<", "<gv")
map("v", ">", ">gv")
map("x", ":", ":<C-u>'<,'>s/\\%V/g<Left><Left>", { desc = "Substitute in selection" })

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
map("n", "<leader>ll", function() require("lint").try_lint() end, { desc = "Run linter" })
map("n", "<leader>ls", function() require("configs.leetcode_stats").open() end, { desc = "LeetCode stats" })

-- ── Sessions ──
map("n", "<leader>qs", function() require("persistence").load() end, { desc = "Restore session" })
map("n", "<leader>ql", function() require("persistence").load({ last = true }) end, { desc = "Last session" })
map("n", "<leader>qd", function() require("persistence").stop() end, { desc = "Stop session" })

-- ── Neovide ──
if vim.g.neovide then
  vim.g.neovide_scale_factor = vim.g.neovide_scale_factor or 1.0
  local function paste() vim.api.nvim_paste(vim.fn.getreg("+"), true, -1) end
  map({ "n", "i", "v", "c", "t" }, "<D-v>", paste, { silent = true })
  map({ "n", "i", "v", "c", "t" }, "<D-=>", function()
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * 1.25
  end, { silent = true })
  map({ "n", "i", "v", "c", "t" }, "<D-->", function()
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor / 1.25
  end, { silent = true })
end
