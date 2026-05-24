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

map("n", "<leader>a", "<cmd>Alpha<cr>", { desc = "Dashboard" })

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

-- ── Todo ──
local todo_buf, todo_win = nil, nil
local widget_buf, widget_win = nil, nil
local widget_grp = vim.api.nvim_create_augroup("TodoWidget", { clear = true })
local widget_ns = vim.api.nvim_create_namespace("todo_widget")
local todo_ns = vim.api.nvim_create_namespace("todo_hl")
local widget_visible = true

vim.api.nvim_set_hl(0, "TodoWidgetNormal", { bg = "NONE" })
vim.api.nvim_set_hl(0, "TodoWidgetBorder", { fg = "#374145", bg = "NONE" })
vim.api.nvim_set_hl(0, "TodoWidgetHeading", { fg = "#a7c080", bold = true })
vim.api.nvim_set_hl(0, "TodoWidgetOpen", { fg = "#d3c6aa" })
vim.api.nvim_set_hl(0, "TodoWidgetDone", { fg = "#5c6a72", strikethrough = true })
vim.api.nvim_set_hl(0, "TodoFloatNormal", { bg = "#181e21" })
vim.api.nvim_set_hl(0, "TodoFloatBorder", { fg = "#4a555b", bg = "#181e21" })
vim.api.nvim_set_hl(0, "TodoDesc", { fg = "#7a8478", italic = true })
vim.api.nvim_set_hl(0, "TodoDone", { fg = "#5c6a72", strikethrough = true })

local function todo_path()
  return vim.fn.getcwd() .. "/todo.md"
end

local function parse_headings(path)
  local lines, types = {}, {}
  local f = io.open(path, "r")
  if not f then return { "  no todo.md" }, { "open" } end
  for line in f:lines() do
    local cb, text = line:match("^%s*- %[([ x])%] (.+)")
    if cb then
      text = text:gsub(" %- .+$", ""):gsub(" — .+$", "")
      lines[#lines + 1] = (cb == "x" and " ✓ " or " ○ ") .. text
      types[#types + 1] = cb == "x" and "done" or "open"
    elseif line:match("^#+ ") then
      if #lines > 0 then
        lines[#lines + 1] = ""
        types[#types + 1] = "blank"
      end
      lines[#lines + 1] = " " .. line:gsub("^#+ ", "")
      types[#types + 1] = "heading"
    end
  end
  f:close()
  if #lines == 0 then return { "  no tasks" }, { "open" } end
  return lines, types
end

local function refresh_widget()
  if not widget_visible then return end
  if todo_win and vim.api.nvim_win_is_valid(todo_win) then return end
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then return end
  local lines, types = parse_headings(todo_path())
  local w = 28
  local h = math.min(#lines, 15)
  if not widget_buf or not vim.api.nvim_buf_is_valid(widget_buf) then
    widget_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[widget_buf].bufhidden = "hide"
  end
  vim.bo[widget_buf].modifiable = true
  vim.api.nvim_buf_set_lines(widget_buf, 0, -1, false, lines)
  vim.bo[widget_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(widget_buf, widget_ns, 0, -1)
  for i, t in ipairs(types) do
    local hl = t == "heading" and "TodoWidgetHeading"
      or t == "done" and "TodoWidgetDone"
      or t == "open" and "TodoWidgetOpen"
      or nil
    if hl then
      vim.api.nvim_buf_add_highlight(widget_buf, widget_ns, hl, i - 1, 0, -1)
    end
  end
  if widget_win and vim.api.nvim_win_is_valid(widget_win) then
    vim.api.nvim_win_set_config(widget_win, {
      relative = "editor",
      row = 1, col = ui.width - w - 2,
      width = w, height = h,
    })
  else
    widget_win = vim.api.nvim_open_win(widget_buf, false, {
      relative = "editor",
      row = 1, col = ui.width - w - 2,
      width = w, height = h,
      style = "minimal",
      border = "rounded",
      title = " todo ", title_pos = "center",
      focusable = false,
      zindex = 1,
    })
    vim.wo[widget_win].winblend = 25
    vim.wo[widget_win].winhighlight = "Normal:TodoWidgetNormal,FloatBorder:TodoWidgetBorder"
  end
end

local function close_widget()
  if widget_win and vim.api.nvim_win_is_valid(widget_win) then
    vim.api.nvim_win_close(widget_win, true)
    widget_win = nil
  end
end

local function toggle_widget()
  widget_visible = not widget_visible
  if widget_visible then refresh_widget() else close_widget() end
end

local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()
  local new = line:gsub("- %[ %]", "- [x]")
  if new == line then new = line:gsub("- %[x%]", "- [ ]") end
  if new ~= line then
    vim.api.nvim_set_current_line(new)
    vim.cmd("silent write!")
  end
end

local function toggle_todo()
  if todo_win and vim.api.nvim_win_is_valid(todo_win) then
    vim.api.nvim_win_close(todo_win, true)
    todo_win = nil
    refresh_widget()
    return
  end
  close_widget()
  local path = todo_path()
  if todo_buf and vim.api.nvim_buf_is_valid(todo_buf) then
    vim.api.nvim_buf_set_name(todo_buf, path)
  else
    todo_buf = vim.fn.bufnr(path, true)
    vim.bo[todo_buf].buflisted = false
  end
  vim.fn.bufload(todo_buf)
  vim.bo[todo_buf].filetype = "markdown"
  local ui = vim.api.nvim_list_uis()[1]
  local w = math.floor(ui.width * 0.6)
  local h = math.floor(ui.height * 0.6)
  todo_win = vim.api.nvim_open_win(todo_buf, true, {
    relative = "editor",
    row = math.floor((ui.height - h) / 2),
    col = math.floor((ui.width - w) / 2),
    width = w, height = h,
    style = "minimal",
    border = "rounded",
    title = " todo ", title_pos = "center",
  })
  vim.wo[todo_win].winblend = 10
  vim.wo[todo_win].wrap = true
  vim.wo[todo_win].linebreak = true
  vim.wo[todo_win].breakindent = true
  vim.wo[todo_win].breakindentopt = "shift:6"
  vim.wo[todo_win].winhighlight = "Normal:TodoFloatNormal,FloatBorder:TodoFloatBorder"
  vim.schedule(function()
    pcall(function() vim.cmd("RenderMarkdown buf_disable") end)
  end)
  local function apply_todo_hl()
    if not todo_buf or not vim.api.nvim_buf_is_valid(todo_buf) then return end
    vim.api.nvim_buf_clear_namespace(todo_buf, todo_ns, 0, -1)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(todo_buf, 0, -1, false)) do
      if line:match("^%s*- %[x%]") then
        vim.api.nvim_buf_add_highlight(todo_buf, todo_ns, "TodoDone", i - 1, 0, -1)
      else
        local pos = line:find(" — ", 7) or line:find(" %- ", 7)
        if pos then
          vim.api.nvim_buf_add_highlight(todo_buf, todo_ns, "TodoDesc", i - 1, pos - 1, -1)
        end
      end
    end
  end
  apply_todo_hl()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = widget_grp, buffer = todo_buf,
    callback = function() vim.schedule(apply_todo_hl) end,
  })
  vim.keymap.set("n", "q", toggle_todo, { buffer = todo_buf })
  vim.keymap.set("n", "<CR>", toggle_checkbox, { buffer = todo_buf })
  vim.keymap.set("n", "o", function()
    local line = vim.api.nvim_get_current_line()
    local prefix = line:match("^(%s*- %[[ x]%] )") or ""
    if prefix ~= "" then prefix = prefix:gsub("%[x%]", "[ ]") end
    vim.cmd("normal! o")
    if prefix ~= "" then
      vim.api.nvim_set_current_line(prefix)
      vim.cmd("startinsert!")
    else
      vim.cmd("startinsert")
    end
  end, { buffer = todo_buf })
  vim.keymap.set("i", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    local prefix = line:match("^(%s*- %[[ x]%] )")
    if prefix then
      prefix = prefix:gsub("%[x%]", "[ ]")
      return "<CR>" .. prefix
    end
    return "<CR>"
  end, { buffer = todo_buf, expr = true })
end

vim.api.nvim_create_autocmd("BufWritePost", {
  group = widget_grp,
  pattern = "todo.md",
  callback = function() vim.schedule(refresh_widget) end,
})
vim.api.nvim_create_autocmd("VimResized", {
  group = widget_grp,
  callback = function() if widget_visible then vim.schedule(refresh_widget) end end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  group = widget_grp,
  once = true,
  callback = function() vim.defer_fn(refresh_widget, 100) end,
})

map("n", "<leader>td", toggle_todo, { desc = "Todo list" })
map("n", "<leader>tw", toggle_widget, { desc = "Toggle todo widget" })

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
