-- Scripted checks, run inside a real Neovim (TUI in a private tmux, see
-- tests/check.sh) with g:neovide faked so every GUI key exists. Keys are
-- typed with nvim_input, the same path a keyboard takes. One line per check
-- goes to $TEST_OUT: "PASS name" or "FAIL name: detail".
local api = vim.api
local out_path = vim.env.TEST_OUT or "/tmp/nvnext/results.txt"
local proj = vim.env.TEST_PROJ or "/tmp/nvnext/proj"
local only = vim.env.TEST_ONLY
local super = require("util").chord

local function log(line)
  local f = io.open(out_path, "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

local co
local function wait(ms)
  vim.defer_fn(function()
    local ok, err = coroutine.resume(co)
    if not ok then
      log("FAIL runner: " .. tostring(err))
    end
  end, ms or 120)
  coroutine.yield()
end

---Type keys (key notation), then let Neovim process them.
local function press(keys, ms)
  api.nvim_input(keys)
  wait(ms or 150)
end

local function mode()
  return api.nvim_get_mode().mode
end

local function floats()
  return #vim.tbl_filter(function(w)
    return api.nvim_win_get_config(w).relative ~= ""
      and api.nvim_win_get_config(w).focusable ~= false
      and vim.bo[api.nvim_win_get_buf(w)].filetype ~= "cmd"
      and vim.bo[api.nvim_win_get_buf(w)].filetype ~= "msg"
  end, api.nvim_list_wins())
end

local function wins()
  return vim.tbl_filter(function(w)
    return api.nvim_win_get_config(w).relative == ""
  end, api.nvim_tabpage_list_wins(0))
end

local function win_of(pred)
  for _, w in ipairs(wins()) do
    if pred(w, api.nvim_win_get_buf(w)) then
      return w
    end
  end
end

local function is_term(w)
  return vim.bo[api.nvim_win_get_buf(w)].buftype == "terminal"
end

local function editor_win()
  return win_of(function(w)
    return not is_term(w)
  end)
end

local function tree_win()
  return win_of(function(_, b)
    return vim.bo[b].filetype == "NvimTree"
  end)
end

local function name_of(w)
  return vim.fn.fnamemodify(api.nvim_buf_get_name(api.nvim_win_get_buf(w)), ":t")
end

-- The command line's window (ui2's, floating, so not in wins()).
local function cmd_win()
  for _, w in ipairs(api.nvim_list_wins()) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "cmd" then
      return w
    end
  end
end

-- A window's own 'fillchars' ("" = it uses the global value).
local function lfc(w)
  return api.nvim_get_option_value("fillchars", { scope = "local", win = w })
end

local function sizes()
  local s = {}
  for _, w in ipairs(wins()) do
    s[w] = api.nvim_win_get_width(w) .. "x" .. api.nvim_win_get_height(w)
  end
  return s
end

-- Back to one editor pane showing a.ml, Normal mode, no tree, no terminals.
local function reset()
  vim.cmd "stopinsert"
  api.nvim_input "<C-\\><C-n><Esc>"
  wait(80)
  pcall(vim.cmd, "silent! tabonly")
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)
  pcall(vim.cmd, "silent! only")
  vim.cmd("cd " .. proj)
  vim.cmd "edit! a.ml"
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= api.nvim_get_current_buf() then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
  vim.cmd "messages clear"
  vim.v.errmsg = ""
  wait(80)
end

local checks = {}
local function check(name, fn)
  checks[#checks + 1] = { name = name, fn = fn }
end

local function expect(cond, detail)
  if not cond then
    error(detail or "expectation failed", 0)
  end
end

-- Editor left, terminal right (Alt+Return from a wide pane).
local function editor_and_terminal()
  press(super "CR", 400)
  local term = win_of(is_term)
  expect(term, "Alt+Return made no terminal")
  return term
end

-- Up to 10 s for a language server to attach to buf and go idle.
local function wait_for_lsp(buf)
  for _ = 1, 40 do
    wait(250)
    if #vim.lsp.get_clients { bufnr = buf } > 0 and vim.lsp.status() == "" then
      return
    end
  end
end

local function picker_active()
  return MiniPick ~= nil and MiniPick.is_picker_active()
end

-- ── Friction principles ───────────────────────────────────────────────────

-- First, while nothing has used it yet: the finder loads on first use.
check("The finder loads on first use (:Pick and vim.ui.select work before)", function()
  expect(MiniPick == nil, "mini.pick was loaded at start")
  press(" ff", 600)
  expect(picker_active(), "<leader>ff opened no picker")
  press("<Esc>", 200)
  expect(vim.ui.select ~= nil, "no vim.ui.select")
end)

check("stray keys in the tree: no popups, at most one short line each", function()
  press(super "b", 300)
  expect(vim.bo.filetype == "NvimTree", "tree not focused")
  local before = floats()
  local stray = {
    "i",
    "u",
    "J",
    "Q",
    "s",
    "S",
    "X",
    "z",
    "Z",
    "e",
    "m",
    "t",
    "w",
    "b",
    "n",
    "<Del>",
    "g",
    "F",
  }
  local bad = {}
  for _, k in ipairs(stray) do
    vim.cmd "messages clear"
    -- Key and Esc in one go: keys like m, g, z wait for one more key, and
    -- while they wait Neovim runs no timers (this runner would stall).
    press(k .. "<Esc>", 80)
    local msgs = vim.split(vim.trim(vim.fn.execute "messages"), "\n", { trimempty = true })
    if #msgs > 1 then
      bad[#bad + 1] = k .. " => " .. #msgs .. " lines: " .. table.concat(msgs, " / ")
    end
  end
  expect(floats() == before, "floats appeared: " .. floats() - before)
  expect(#bad == 0, table.concat(bad, "; "))
end)

check("stray keys in an editor: unmapped leader and Alt keys do nothing", function()
  local tick = vim.b.changedtick
  local before = floats()
  for _, k in ipairs { "<leader>z", "<leader>q", super "y", super "u", super "x", super "d", super "k", super "S-x" } do
    press(k .. "<Esc>", 150)
  end
  press("i", 50)
  for _, k in ipairs { super "u", super "x", super "d" } do
    press(k, 100)
  end
  expect(mode() == "i", "an Alt key left Insert mode")
  press("<Esc>", 50)
  expect(floats() == before, "a float opened")
  expect(vim.b.changedtick == tick, "the file changed")
end)

check("pane focus works the same from Normal, Insert, Visual and Terminal", function()
  local term = editor_and_terminal()
  local editor = editor_win()
  local failed = {}
  for _, k in ipairs { "<C-h>", super "Left" } do
    -- from Terminal mode (the terminal just opened is in it)
    api.nvim_set_current_win(term)
    vim.cmd "startinsert"
    wait(100)
    expect(mode() == "t", "terminal not in Terminal mode")
    press(k)
    if api.nvim_get_current_win() ~= editor then
      failed[#failed + 1] = k .. " from Terminal"
    end
    -- from Insert
    press "i"
    press(k == "<C-h>" and "<C-l>" or super "Right")
    if api.nvim_get_current_win() ~= term then
      failed[#failed + 1] = k .. " pair from Insert"
    end
    expect(mode() == "t", "landing in a terminal should type: mode " .. mode())
    -- from Visual
    api.nvim_set_current_win(editor)
    vim.cmd "stopinsert"
    wait(60)
    press "v"
    press(k == "<C-h>" and "<C-l>" or super "Right")
    if api.nvim_get_current_win() ~= term then
      failed[#failed + 1] = k .. " pair from Visual"
    end
  end
  expect(#failed == 0, table.concat(failed, ", "))
end)

check("every pane and tab key is mapped in Normal, Insert, Visual, Select and Terminal", function()
  local keys = {
    "<C-h>",
    "<C-j>",
    "<C-k>",
    "<C-l>",
    "<C-Left>",
    "<C-Right>",
    "<C-Up>",
    "<C-Down>",
    "<C-Tab>",
    "<C-S-Tab>",
    "<F5>",
  }
  for _, k in ipairs {
    "Left",
    "Right",
    "Up",
    "Down",
    "S-Left",
    "S-Right",
    "S-Up",
    "S-Down",
    "CR",
    "f",
    "j",
    "w",
    "t",
    "S-t",
    "p",
    "S-p",
    "S-f",
    "b",
    "o",
    "s",
    "1",
    "9",
  } do
    keys[#keys + 1] = super(k)
  end
  local missing = {}
  for _, k in ipairs(keys) do
    for _, m in ipairs { "n", "i", "x", "s", "t" } do
      if vim.fn.maparg(k, m) == "" then
        missing[#missing + 1] = m .. " " .. k
      end
    end
  end
  expect(#missing == 0, "missing: " .. table.concat(missing, ", "))
end)

check("no Esc Esc needed: a single Esc reaches the program in a terminal", function()
  editor_and_terminal()
  expect(vim.fn.maparg("<Esc>", "t") == "" and vim.fn.maparg("<Esc><Esc>", "t") == "", "Esc is mapped in Terminal mode")
end)

check("Alt/Cmd+W closes the focused thing: terminal pane", function()
  local term = editor_and_terminal()
  local buf = api.nvim_win_get_buf(term)
  local job = vim.b[buf].terminal_job_id
  api.nvim_set_current_win(term)
  press(super "w", 300)
  expect(not api.nvim_win_is_valid(term), "terminal window still open")
  expect(not api.nvim_buf_is_valid(buf), "terminal buffer still exists")
  expect(vim.fn.jobwait({ job }, 0)[1] ~= -1, "terminal job still running")
  expect(#wins() == 1, "panes left: " .. #wins())
end)

check("Alt/Cmd+W closes the focused thing: a tab in the editor", function()
  vim.cmd "edit b.ml"
  local b = api.nvim_get_current_buf()
  press(super "w", 200)
  expect(not api.nvim_buf_is_valid(b) or not vim.bo[b].buflisted, "b.ml still open")
  expect(name_of(0) == "a.ml", "shows " .. name_of(0) .. " instead of the previous tab")
  expect(#wins() == 1, "the editor pane closed")
end)

check("Alt/Cmd+W closes the focused thing: the tree, a split, a float, help", function()
  press(super "b", 300)
  expect(vim.bo.filetype == "NvimTree", "tree not focused")
  press(super "w", 200)
  expect(not require("nvim-tree.api").tree.is_visible(), "tree still visible")
  vim.cmd "vsplit b.ml"
  local split = api.nvim_get_current_win()
  press(super "w", 200)
  expect(not api.nvim_win_is_valid(split), "split still open")
  vim.cmd "help help"
  local help = api.nvim_get_current_win()
  press(super "w", 200)
  expect(not api.nvim_win_is_valid(help), "help still open")
  local float = api.nvim_open_win(
    api.nvim_create_buf(false, true),
    true,
    { relative = "editor", row = 2, col = 2, width = 20, height = 3 }
  )
  press(super "w", 200)
  expect(not api.nvim_win_is_valid(float), "float still open")
end)

check("Ctrl+Arrow moves the divider toward the arrow (editor and terminal)", function()
  local term = editor_and_terminal()
  local editor = editor_win()
  local function divider()
    return api.nvim_win_get_width(editor)
  end
  api.nvim_set_current_win(editor)
  vim.cmd "stopinsert"
  wait(60)
  local d0 = divider()
  press "<C-Right>"
  expect(divider() > d0, "editor Ctrl+Right: divider did not move right")
  press "<C-Left><C-Left>"
  expect(divider() < d0, "editor Ctrl+Left: divider did not move left")
  -- From the terminal, in Terminal mode.
  api.nvim_set_current_win(term)
  vim.cmd "startinsert"
  wait(100)
  local d1 = divider()
  press "<C-Left>"
  expect(divider() < d1, "terminal Ctrl+Left: divider did not move left")
  press "<C-Right><C-Right>"
  expect(divider() > d1, "terminal Ctrl+Right: divider did not move right")
  expect(mode() == "t", "left Terminal mode: " .. mode())
  -- Stacked: editor over a terminal.
  press(super "w", 300)
  vim.cmd "stopinsert"
  vim.cmd "belowright 10split | terminal"
  wait(200)
  local top = editor_win()
  local h0 = api.nvim_win_get_height(top)
  press "<C-Up>"
  expect(api.nvim_win_get_height(top) < h0, "terminal Ctrl+Up: divider did not move up")
  press "<C-Down><C-Down>"
  expect(api.nvim_win_get_height(top) > h0, "terminal Ctrl+Down: divider did not move down")
end)

check("opening or closing the tree never resizes the other panes", function()
  vim.cmd "vsplit b.ml"
  vim.cmd "wincmd l"
  vim.cmd "belowright split README.md"
  local before = sizes()
  local left = vim.fn.win_getid(1)
  press(super "b", 300)
  local changed = {}
  for w, s in pairs(before) do
    if w ~= left and api.nvim_win_is_valid(w) and sizes()[w] ~= s then
      changed[#changed + 1] = name_of(w) .. " " .. s .. "->" .. sizes()[w]
    end
  end
  local left_h = before[left]:match "x(%d+)"
  expect(api.nvim_win_get_height(left) == tonumber(left_h), "the pane beside the tree changed height")
  press(super "b", 300)
  for w, s in pairs(before) do
    if api.nvim_win_is_valid(w) and sizes()[w] ~= s then
      changed[#changed + 1] = "after close " .. name_of(w) .. " " .. s .. "->" .. sizes()[w]
    end
  end
  expect(#changed == 0, table.concat(changed, "; "))
end)

check("opening or closing a terminal never resizes the other panes", function()
  vim.cmd "vsplit b.ml"
  local right = api.nvim_get_current_win()
  vim.cmd "wincmd h"
  local left = api.nvim_get_current_win()
  local before = sizes()
  api.nvim_set_current_win(right)
  press(super "CR", 400)
  expect(sizes()[left] == before[left], "left pane " .. before[left] .. " -> " .. sizes()[left])
  press(super "w", 300)
  expect(sizes()[left] == before[left], "after close: left pane " .. before[left] .. " -> " .. sizes()[left])
  expect(
    sizes()[right] == before[right],
    "after close: right pane " .. before[right] .. " -> " .. tostring(sizes()[right])
  )
end)

check("the focused pane is obvious: others dimmed, cursor line only in focus", function()
  vim.cmd "vsplit b.ml"
  local right = api.nvim_get_current_win()
  vim.cmd "wincmd h"
  wait(60)
  local left = api.nvim_get_current_win()
  expect(api.nvim_get_hl_ns { winid = left } == 0, "focused pane is dimmed")
  local ns = api.nvim_get_hl_ns { winid = right }
  expect(ns ~= 0, "unfocused pane is not dimmed")
  local dim = api.nvim_get_hl(ns, { name = "Normal" }).fg
  local full = api.nvim_get_hl(0, { name = "Normal" }).fg
  expect(dim and dim ~= full, "dimmed Normal text is the same colour")
  expect(next(api.nvim_get_hl(ns, { name = "CursorLine" })) == nil, "unfocused pane shows a cursor line")
  press "<C-l>"
  expect(
    api.nvim_get_hl_ns { winid = right } == 0 and api.nvim_get_hl_ns { winid = left } ~= 0,
    "focus swap did not swap dimming"
  )
end)

-- WCAG contrast ratio of two 0xRRGGBB colours.
local function contrast(a, b)
  local function lum(c)
    local function ch(x)
      x = x / 255
      return x <= 0.03928 and x / 12.92 or ((x + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * ch(bit.rshift(c, 16) % 256) + 0.7152 * ch(bit.rshift(c, 8) % 256) + 0.0722 * ch(c % 256)
  end
  local x, y = lum(a), lum(b)
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

check("unfocused panes stay easy to read; the focused one has an accent title", function()
  press(super "b", 400)
  local tree = api.nvim_get_current_win()
  press("<C-l>", 200)
  vim.cmd "vsplit b.ml"
  local right = api.nvim_get_current_win()
  vim.cmd "wincmd h"
  wait(80)
  local left = api.nvim_get_current_win()
  local bg = api.nvim_get_hl(0, { name = "Normal" }).bg
  local ns = api.nvim_get_hl_ns { winid = right }
  local dim = api.nvim_get_hl(ns, { name = "Normal" }).fg
  local ratio = contrast(dim, bg)
  expect(ratio >= 7, ("unfocused text contrast %.1f:1, under 7:1"):format(ratio))
  -- Every pane has a title row; only the focused pane's is in the accent.
  local accent = api.nvim_get_hl(0, { name = "WinSeparatorHover", link = false }).fg
  local function title_fg(w)
    local space = api.nvim_get_hl_ns { winid = w }
    return api.nvim_get_hl(space, { name = "FocusTitle", link = false }).fg
  end
  for _, w in ipairs { left, right } do
    expect(vim.wo[w].winbar:find "focus", "pane " .. name_of(w) .. " has no title row")
  end
  expect(
    vim.wo[tree].winbar ~= "" and vim.fn.luaeval("require('explorer').winbar()"):find "FocusTitle",
    "the tree's title is not a focus title"
  )
  expect(title_fg(left) == accent, "focused title is not the accent")
  expect(title_fg(right) ~= accent and title_fg(tree) ~= accent, "an unfocused title is in the accent")
  -- The focused title is a tinted bar to the row's end, found at a glance.
  local title_bg = api.nvim_get_hl(api.nvim_get_hl_ns { winid = left }, { name = "FocusTitle", link = false }).bg
  expect(title_bg and title_bg ~= bg, "focused title row has no tint")
  expect(vim.fn.luaeval("require('focus').title()"):find "%%=$", "focused title tint stops at the name")
end)

check("markup never hides words: markdown and org show every character", function()
  for _, file in ipairs { "README.md", "README.org" } do
    vim.cmd("edit " .. file)
    wait(400)
    expect(vim.wo.conceallevel == 0, file .. ": conceallevel " .. vim.wo.conceallevel)
    local comment = api.nvim_get_hl(0, { name = "Comment", link = false })
    local bg = api.nvim_get_hl(0, { name = "Normal" }).bg
    expect(comment.fg and comment.fg ~= bg, "comments are invisible")
  end
  vim.cmd "edit README.md"
  wait(200)
  -- The HTML comment line is drawn with a visible colour.
  local row = vim.fn.search "<!--"
  local caps = vim.inspect_pos(0, row - 1, 2)
  local groups = {}
  for _, c in ipairs(caps.treesitter) do
    groups[#groups + 1] = c.hl_group_link or c.hl_group
  end
  local nonzero = true
  for _, g in ipairs(groups) do
    local hl = api.nvim_get_hl(0, { name = g, link = false })
    if hl.fg and hl.fg == api.nvim_get_hl(0, { name = "Normal" }).bg then
      nonzero = false
    end
  end
  expect(nonzero, "comment text has the background colour")
end)

-- Where projects.lua keeps a folder's session.
local function session_file(dir)
  return vim.fn.stdpath "state" .. "/sessions/" .. vim.uv.fs_realpath(dir):gsub("[/\\:]", "%%") .. ".vim"
end

-- Another Neovim (a live process) has dir open. Returns the way to end it.
local function open_in_other_window(dir)
  local job = vim.fn.jobstart { "sleep", "30" }
  local open_dir = vim.env.XDG_STATE_HOME .. "/nvim/open-projects"
  local file = open_dir .. "/" .. vim.fn.jobpid(job)
  vim.fn.mkdir(open_dir, "p")
  vim.fn.writefile({ vim.uv.fs_realpath(dir) }, file)
  return function()
    vim.fn.jobstop(job)
    os.remove(file)
  end
end

check("a new window never reopens a project another window shows", function()
  local projects = require "projects"
  local a, b = proj .. "/sub-a", proj .. "/sub-b"
  vim.fn.mkdir(a, "p")
  vim.fn.mkdir(b, "p")
  vim.fn.mkdir(vim.fn.stdpath "state" .. "/sessions", "p")
  vim.fn.writefile({ '" test' }, session_file(b))
  vim.uv.sleep(1100)
  vim.fn.writefile({ '" test' }, session_file(a)) -- a is the newest
  local close_other = open_in_other_window(a)
  local got = projects.last_project()
  close_other()
  os.remove(session_file(a))
  os.remove(session_file(b))
  expect(got and vim.uv.fs_realpath(got) == vim.uv.fs_realpath(b), "reopened " .. tostring(got))
end)

check("library files are read-only with no diagnostics", function()
  local lib = vim.fn.expand "~/.opam/default/lib/base/list.mli"
  if not vim.uv.fs_stat(lib) then
    error("SKIP: " .. lib .. " missing", 0)
  end
  vim.cmd("edit " .. lib)
  local buf = api.nvim_get_current_buf()
  wait_for_lsp(buf)
  wait(1500)
  expect(vim.bo[buf].readonly, "not read-only")
  expect(#vim.lsp.get_clients { bufnr = buf } > 0, "no language server (hover would not work)")
  expect(#vim.diagnostic.get(buf) == 0, #vim.diagnostic.get(buf) .. " diagnostics shown")
end)

check("project files still get diagnostics", function()
  vim.cmd "edit broken.ml"
  local buf = api.nvim_get_current_buf()
  for _ = 1, 60 do
    wait(250)
    if #vim.diagnostic.get(buf) > 0 then
      break
    end
  end
  expect(#vim.diagnostic.get(buf) > 0, "no diagnostics on a broken project file")
end)

check("the tree shows the folder name and opens files in the last editor, no prompt", function()
  local term = editor_and_terminal()
  local editor = editor_win()
  -- Focus the terminal last, then open a file from the tree.
  api.nvim_set_current_win(term)
  press(super "b", 400)
  expect(vim.bo.filetype == "NvimTree", "tree not focused")
  local first = api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  local folder = vim.fn.fnamemodify(proj, ":t")
  expect(vim.trim(first):find(folder, 1, true) and #vim.trim(first) <= #folder + 4, "top line is '" .. first .. "'")
  local n = #wins()
  vim.fn.search "b.ml"
  press("<CR>", 400)
  expect(#wins() == n, "a window was added or removed")
  expect(api.nvim_get_current_win() == editor, "file did not open in the editor pane")
  expect(name_of(editor) == "b.ml", "editor shows " .. name_of(editor))
  expect(is_term(term) and api.nvim_win_is_valid(term), "the terminal pane was replaced")
  expect(floats() == 0, "a prompt or picker appeared")
end)

check("Alt/Cmd+O opens a folder", function()
  vim.fn.mkdir(proj .. "/sub-b", "p")
  press(super "o", 1500)
  expect(picker_active(), "no folder picker")
  press("proj/sub-b", 300)
  press("<CR>", 800)
  expect(vim.fn.getcwd():match "sub%-b$", "cwd is " .. vim.fn.getcwd())
  expect(require("nvim-tree.api").tree.is_visible(), "tree not shown for the folder")
  vim.cmd("cd " .. proj)
end)

-- ── Keymaps ───────────────────────────────────────────────────────────────

check("Alt+Arrows and Ctrl+H/J/K/L focus in all four directions", function()
  vim.cmd "vsplit b.ml | split README.md | wincmd k"
  local tr = api.nvim_get_current_win()
  press(super "Down")
  local br = api.nvim_get_current_win()
  expect(br ~= tr, "Alt+Down did not move")
  press "<C-k>"
  expect(api.nvim_get_current_win() == tr, "Ctrl+K did not move up")
  press "<C-j>"
  press(super "Up")
  expect(api.nvim_get_current_win() == tr, "Alt+Up did not move up")
  press(super "Left")
  local left = api.nvim_get_current_win()
  expect(left ~= tr and api.nvim_win_get_position(left)[2] == 0, "Alt+Left did not move left")
  press(super "Right")
  expect(api.nvim_win_get_position(api.nvim_get_current_win())[2] > 0, "Alt+Right did not move right")
end)

check("Alt+Shift+Arrows swap panes; sizes stay", function()
  vim.cmd "vsplit b.ml | wincmd h"
  local left = api.nvim_get_current_win()
  local before = sizes()
  press(super "S-Right")
  local right = api.nvim_get_current_win()
  expect(right ~= left and name_of(right) == "a.ml" and name_of(left) == "b.ml", "contents did not swap")
  expect(vim.deep_equal(before, sizes()), "sizes changed")
end)

check("Alt+Return opens a terminal on the longer side", function()
  press(super "CR", 400)
  expect(#wins() == 2, "panes: " .. #wins())
  local t = api.nvim_get_current_win()
  expect(is_term(t), "focus not in the terminal")
  expect(api.nvim_win_get_position(t)[2] > 0, "a wide pane did not split sideways")
  expect(mode() == "t", "terminal not ready to type")
  -- A tall pane splits downward (narrow this one first).
  api.nvim_win_set_width(t, 40)
  press(super "CR", 400)
  local t2 = api.nvim_get_current_win()
  expect(api.nvim_win_get_position(t2)[1] > api.nvim_win_get_position(t)[1], "a tall pane did not split downward")
end)

check("Ctrl+` toggles a full-width terminal panel at the bottom, from every mode", function()
  for _, m in ipairs { "n", "i", "x", "t" } do
    expect(vim.fn.maparg("<C-`>", m) ~= "", "Ctrl+` not mapped in mode " .. m)
  end
  vim.cmd "vsplit b.ml"
  local editor = api.nvim_get_current_win()
  local before = sizes()
  press("i", 50)
  press("<C-`>", 400)
  local p = api.nvim_get_current_win()
  expect(is_term(p), "focus not in a terminal")
  expect(mode() == "t", "panel not ready to type")
  expect(api.nvim_win_get_width(p) == vim.o.columns, "panel not full width: " .. api.nvim_win_get_width(p))
  local row = api.nvim_win_get_position(p)[1]
  for _, w in ipairs(wins()) do
    expect(w == p or api.nvim_win_get_position(w)[1] < row, "a pane sits below the panel")
  end
  local job = vim.b.terminal_job_id
  -- Focused: Ctrl+` hides it, the shell keeps running, sizes come back.
  press("<C-`>", 300)
  expect(api.nvim_get_current_win() == editor, "focus did not go back to the editor")
  expect(#wins() == 2, "panel still shows: " .. #wins() .. " panes")
  for w, s in pairs(before) do
    expect(sizes()[w] == s, "pane " .. w .. " " .. s .. " -> " .. tostring(sizes()[w]))
  end
  -- From a selection: the same shell comes back. Not focused: Ctrl+` focuses it.
  press("v", 50)
  press("<C-`>", 300)
  expect(vim.b.terminal_job_id == job, "a new shell instead of the same one")
  local shown = api.nvim_get_current_win()
  press(super "Up", 200)
  expect(api.nvim_get_current_win() ~= shown, "Alt+Up did not leave the panel")
  press("<C-`>", 200)
  expect(api.nvim_get_current_win() == shown, "Ctrl+` with the panel shown but not focused did not focus it")
end)

check("Alt+B with the panel shown or the editor split top/bottom: tree full size, panel full width", function()
  press(super "b", 400)
  if not tree_win() then
    press(super "b", 400)
  end
  local width = api.nvim_win_get_width(tree_win())
  press("<C-`>", 400)
  press(super "b", 300)
  expect(not tree_win(), "Alt+B did not hide the tree")
  press(super "b", 400)
  local t = tree_win()
  expect(
    t and api.nvim_win_get_width(t) == width,
    "tree came back " .. (t and api.nvim_win_get_width(t) or 0) .. " wide, not " .. width
  )
  expect(t and api.nvim_get_current_win() == t, "focus not in the tree")
  local panel = win_of(is_term)
  expect(panel and api.nvim_win_get_width(panel) == vim.o.columns, "panel not full width after the tree came back")
  expect(
    t and panel and api.nvim_win_get_position(t)[1] + api.nvim_win_get_height(t) < api.nvim_win_get_position(panel)[1],
    "the tree runs down past the panel"
  )
  api.nvim_set_current_win(panel)
  press("<C-`>", 300)
  -- Two editors along the tree's edge, one above the other.
  require("panes").editor()
  vim.cmd "split b.ml"
  press(super "b", 300)
  press(super "b", 400)
  t = tree_win()
  expect(
    t and api.nvim_win_get_width(t) == width,
    "with a top/bottom split the tree came back " .. (t and api.nvim_win_get_width(t) or 0) .. " wide"
  )
end)

check("Alt+F zooms a pane and brings the layout back", function()
  vim.cmd "vsplit b.ml"
  local layout = vim.fn.winlayout()
  press(super "f", 200)
  expect(#wins() == 1, "zoom shows " .. #wins() .. " panes")
  press(super "f", 200)
  expect(vim.deep_equal(vim.fn.winlayout(), layout), "layout changed after unzoom")
end)

check("Alt+J flips the split direction", function()
  vim.cmd "vsplit b.ml"
  expect(vim.fn.winlayout()[1] == "row", "setup")
  press(super "j", 200)
  expect(vim.fn.winlayout()[1] == "col", "did not flip to stacked")
  press(super "j", 200)
  expect(vim.fn.winlayout()[1] == "row", "did not flip back")
end)

check("Alt+Shift+J/K move the line (Normal, Insert, Visual)", function()
  vim.cmd "edit! a.ml"
  local l1, l2 = vim.fn.getline(1), vim.fn.getline(2)
  vim.fn.cursor(1, 1)
  press(super "S-j")
  expect(vim.fn.getline(2) == l1, "Normal: line did not move down")
  press(super "S-k")
  expect(vim.fn.getline(1) == l1, "Normal: line did not move up")
  press "i"
  press(super "S-j")
  expect(vim.fn.getline(2) == l1 and mode() == "i", "Insert: did not move or left Insert")
  press "<Esc>"
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  press "V"
  press(super "S-j")
  expect(vim.fn.getline(2) == l1, "Visual: did not move")
  vim.cmd "edit! a.ml"
  expect(vim.fn.getline(2) == l2, "reload")
end)

check("Tabs: Ctrl+Tab, Alt+1..9, Alt+T, Alt+Shift+T, from a terminal too", function()
  vim.cmd "edit b.ml | edit README.md"
  vim.cmd "buffer a.ml"
  press "<C-Tab>"
  local after = name_of(0)
  expect(after ~= "a.ml", "Ctrl+Tab did not switch")
  press "<C-S-Tab>"
  expect(name_of(0) == "a.ml", "Ctrl+Shift+Tab did not come back")
  press(super "2")
  expect(name_of(0) == "b.ml", "Alt+2 shows " .. name_of(0))
  press(super "9")
  expect(name_of(0) == "README.md", "Alt+9 shows " .. name_of(0))
  local term = editor_and_terminal()
  api.nvim_set_current_win(term)
  vim.cmd "startinsert"
  wait(100)
  press "<C-Tab>"
  expect(not is_term(api.nvim_get_current_win()), "Ctrl+Tab in a terminal switched the terminal pane")
  local closed = name_of(0)
  press(super "w", 200)
  press(super "S-t", 200)
  expect(name_of(0) == closed, "Alt+Shift+T reopened " .. name_of(0) .. ", not " .. closed)
  local n = #vim.fn.getbufinfo { buflisted = 1 }
  press(super "t", 200)
  expect(#vim.fn.getbufinfo { buflisted = 1 } == n + 1, "Alt+T made no new tab")
end)

check("Terminals stay out of the tab bar", function()
  editor_and_terminal()
  for _, b in ipairs(vim.fn.getbufinfo { buflisted = 1 }) do
    expect(vim.bo[b.bufnr].buftype ~= "terminal", "a terminal is listed as a tab")
  end
end)

check("Find: Alt+P, Alt+Shift+P, Alt+Shift+F open one picker; Esc closes it", function()
  for _, k in ipairs { super "p", super "S-p", super "S-f" } do
    press(k, 500)
    expect(picker_active(), k .. " opened no picker")
    expect(floats() <= 1, k .. " opened " .. floats() .. " floats")
    press("<Esc>", 200)
    expect(not picker_active(), "Esc did not close the picker")
  end
  press("i", 50)
  press(super "p", 500)
  expect(picker_active(), "Alt+P from Insert opened no picker")
  press("<Esc>", 200)
end)

check("Alt+B toggles the tree from any mode", function()
  press "i"
  press(super "b", 300)
  expect(require("nvim-tree.api").tree.is_visible(), "Alt+B from Insert did not open the tree")
  press(super "b", 300)
  expect(not require("nvim-tree.api").tree.is_visible(), "Alt+B did not close the tree")
end)

check("Alt+/ toggles a comment; Esc clears the search highlight", function()
  vim.cmd "edit! a.ml"
  local l1 = vim.fn.getline(1)
  vim.fn.cursor(1, 1)
  press(super "/")
  expect(vim.fn.getline(1) ~= l1, "no comment added")
  press(super "/")
  expect(vim.fn.getline(1) == l1, "comment not removed")
  vim.cmd "edit! a.ml"
  vim.fn.setreg("/", "let")
  vim.o.hlsearch = true
  vim.v.hlsearch = 1
  press "<Esc>"
  expect(vim.v.hlsearch == 0, "highlight still on")
end)

check("Alt+S saves; :W is :w", function()
  vim.cmd "edit! c.ml"
  api.nvim_buf_set_lines(0, 0, -1, false, { "let x = 1" })
  press(super "s", 400)
  expect(not vim.bo.modified, "Alt+S did not save")
  api.nvim_buf_set_lines(0, 0, -1, false, { "let y = 2" })
  vim.cmd "W"
  wait(300)
  expect(not vim.bo.modified, ":W did not save")
end)

check("Zoom keys change the font scale; paste key pastes", function()
  local s = vim.g.neovide_scale_factor
  press(super "=")
  expect(vim.g.neovide_scale_factor > s, "Alt+= did not zoom in")
  press(super "-")
  press(super "-")
  expect(vim.g.neovide_scale_factor < s, "Alt+- did not zoom out")
  press(super "0")
  expect(math.abs(vim.g.neovide_scale_factor - vim.g.default_scale) < 1e-9, "Alt+0 did not reset")
  vim.cmd "enew"
  vim.fn.setreg("+", "pasted-text")
  press "i"
  press(super "v")
  press "<Esc>"
  expect(vim.fn.getline(1):find "pasted%-text", "Alt+V did not paste: " .. vim.fn.getline(1))
end)

check("OCaml: <leader>oi switches .ml/.mli; ocp-indent indents; format on save", function()
  vim.cmd "edit! a.ml"
  press " oi"
  expect(name_of(0) == "a.mli", "shows " .. name_of(0))
  press " oi"
  expect(name_of(0) == "a.ml", "did not switch back")
  expect(vim.bo.indentexpr:find "ocaml", "indentexpr is " .. vim.bo.indentexpr)
  vim.cmd "edit! fmt.ml"
  api.nvim_buf_set_lines(0, 0, -1, false, { "let   f x=x+1" })
  vim.cmd "write"
  wait(300)
  expect(vim.fn.getline(1) == "let f x = x + 1", "formatted to '" .. vim.fn.getline(1) .. "'")
end)

check("OCaml: :w re-indents (Jane Street) where .ocamlformat says disable", function()
  vim.cmd "edit! noformat/indent_me.ml"
  vim.cmd "write"
  wait(300)
  expect(vim.fn.getline(2) == "  item * 2) [ 1; 2; 3 ]", "line 2 is '" .. vim.fn.getline(2) .. "'")
  expect(vim.fn.getline(1) == "let prices = List.map (fun item ->", "line 1 reflowed: " .. vim.fn.getline(1))
end)

check("OCaml: the ruler sits where ocamlformat wraps, and only in OCaml files", function()
  for dir, conf in pairs { wide = { "profile = default", "margin = 110" }, plain = { "profile = default" } } do
    vim.fn.mkdir(proj .. "/" .. dir, "p")
    vim.fn.writefile(conf, proj .. "/" .. dir .. "/.ocamlformat")
    vim.fn.writefile({ "let x = 1" }, proj .. "/" .. dir .. "/x.ml")
  end
  for _, case in ipairs {
    { "noformat/indent_me.ml", "" },
    { "wide/x.ml", "110" },
    { "plain/x.ml", "80" },
    { "a.ml", "90" },
    { "README.md", "" },
  } do
    vim.cmd("edit! " .. case[1])
    expect(vim.wo.colorcolumn == case[2], case[1] .. " has the ruler at '" .. vim.wo.colorcolumn .. "'")
  end
  expect(api.nvim_get_hl(0, { name = "ColorColumn" }).bg, "ColorColumn has no fill, so the ruler is invisible")
end)

check("gd goes to a definition; K shows the type", function()
  vim.cmd "edit! b.ml"
  local buf = api.nvim_get_current_buf()
  wait_for_lsp(buf)
  wait(800)
  vim.fn.search "helper"
  press("gd", 1200)
  expect(vim.fn.line "." == 1, "gd went to line " .. vim.fn.line ".")
  vim.fn.search "helper"
  press("K", 1500)
  expect(floats() >= 1, "K showed nothing")
  press("<Esc>", 100)
end)

check("F5 runs a Python file in a terminal pane", function()
  vim.cmd "edit! hello.py"
  press("<F5>", 1200)
  local term = win_of(is_term)
  expect(term, "no terminal pane")
  local text = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(term), 0, -1, false), "\n")
  expect(text:find "hello from python", "output: " .. text:sub(1, 80))
end)

local function word_marks()
  return vim.tbl_filter(function(m)
    return m.group == "WordOccurrence"
  end, vim.fn.getmatches())
end

check("Double-click selects the word and marks its other occurrences", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 5)
  require("words").select_word()
  wait(100)
  expect(mode() == "v", "not in Visual: " .. mode())
  expect(#word_marks() == 1, "no occurrence marks")
  press "<Esc>"
  expect(#word_marks() == 0, "marks stayed after the selection ended")
end)

-- ── The other keys ────────────────────────────────────────────────────────

local function close_floats()
  for _, w in ipairs(api.nvim_list_wins()) do
    local cfg = api.nvim_win_get_config(w)
    if cfg.relative ~= "" and cfg.focusable ~= false and not cfg.hide then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

check("Leader find keys each open one picker; Esc closes it", function()
  for _, k in ipairs { "ff", "fg", "fb", "fr", "fh", "fk", "fd" } do
    press(" " .. k, 600)
    expect(picker_active(), "<leader>" .. k .. " opened no picker")
    press("<Esc>", 200)
    expect(not picker_active(), "Esc did not close <leader>" .. k)
  end
end)

check("<leader>d shows the line's problems in one float", function()
  vim.cmd "edit! a.ml"
  local ns = api.nvim_create_namespace "test-diagnostic"
  vim.diagnostic.set(
    ns,
    0,
    { { lnum = 0, col = 0, message = "test problem", severity = vim.diagnostic.severity.WARN } }
  )
  vim.fn.cursor(1, 1)
  local before = floats()
  press(" d", 300)
  local opened = floats() - before
  close_floats()
  vim.diagnostic.reset(ns)
  expect(opened == 1, "floats opened: " .. opened)
end)

check("A long problem message fits beside the code, never off screen", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  local ns = api.nvim_create_namespace "test-long-diagnostic"
  local long = ("This expression has type string but an expression was expected of type int "):rep(4)
  vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = long .. "\nsecond line" } })
  wait(150)
  local width = 0
  for _, mark in ipairs(api.nvim_buf_get_extmarks(0, -1, { 0, 0 }, { 0, -1 }, { details = true })) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      width = width + vim.fn.strdisplaywidth(chunk[1])
    end
  end
  local info = vim.fn.getwininfo(api.nvim_get_current_win())[1]
  local used = info.textoff + vim.fn.strdisplaywidth(vim.fn.getline(1)) + width
  vim.diagnostic.reset(ns)
  expect(width > 0, "no message shown")
  expect(used <= info.width, ("message needs %d columns, window has %d"):format(used, info.width))
end)

check("Visual < and > indent and keep the selection", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  press("Vj>", 150)
  expect(mode() == "V", "selection lost after >: " .. mode())
  expect(vim.fn.getline(1):match "^%s+let" and vim.fn.getline(2):match "^%s+let", "not indented")
  press("<lt>", 150)
  expect(mode() == "V", "selection lost after <: " .. mode())
  expect(vim.fn.getline(1):match "^let", "not indented back")
  press "<Esc>"
  vim.cmd "edit! a.ml"
end)

check("Completion: Tab picks, Enter takes it; Enter alone is a new line", function()
  vim.cmd "enew"
  api.nvim_buf_set_lines(0, 0, -1, false, { "foobar foobaz", "" })
  vim.fn.cursor(2, 1)
  press("ifoo<C-x><C-n>", 250)
  expect(vim.fn.pumvisible() == 1, "no menu")
  press("<Tab>", 100)
  press("<CR>", 150)
  local l = vim.fn.getline(2)
  expect(l == "foobar" or l == "foobaz", "line 2 is '" .. l .. "'")
  expect(api.nvim_buf_line_count(0) == 2, "Enter on a chosen item also made a new line")
  press("<CR>", 150)
  expect(api.nvim_buf_line_count(0) == 3, "Enter did not make a new line")
  press "<Esc>"
end)

check("Completion pops up by itself with language-server items", function()
  vim.cmd "edit! c.ml"
  local buf = api.nvim_get_current_buf()
  wait_for_lsp(buf)
  wait(500)
  vim.fn.cursor(1, 1)
  press("olet z = List.ma", 1500)
  local shown = vim.fn.pumvisible() == 1
  local words = vim.tbl_map(function(item)
    return item.word
  end, vim.fn.complete_info({ "items" }).items or {})
  press "<Esc>"
  vim.cmd "edit! c.ml"
  expect(shown, "no menu popped up")
  expect(vim.tbl_contains(words, "map"), "items: " .. table.concat(vim.list_slice(words, 1, 6), ", "))
end)

check("Ctrl+PageDown / Ctrl+PageUp switch tabs", function()
  vim.cmd "edit! a.ml"
  vim.cmd "edit! b.ml"
  press("<C-PageUp>", 150)
  expect(name_of(0) == "a.ml", "Ctrl+PageUp shows " .. name_of(0))
  press("<C-PageDown>", 150)
  expect(name_of(0) == "b.ml", "Ctrl+PageDown shows " .. name_of(0))
end)

check("Copy and cut keys fill the clipboard (a private one in tests)", function()
  expect(vim.g.clipboard and vim.g.clipboard.name == "test-memory", "test clipboard not active")
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  press(super "c", 150)
  expect(vim.fn.getreg "+" == vim.fn.getline(1) .. "\n", "Alt+C copied '" .. vim.fn.getreg "+" .. "'")
  press("viw" .. super "x", 150)
  expect(vim.fn.getreg "+" == "let", "Alt+X cut '" .. vim.fn.getreg "+" .. "'")
  expect(not vim.fn.getline(1):match "^let", "Alt+X left the text")
  vim.cmd "edit! a.ml"
end)

check("Alt/Cmd+click is a plain click, not a block selection", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  local pos = vim.fn.screenpos(0, 2, 5)
  local mod = require("util").is_macos and "D" or "A"
  api.nvim_input_mouse("left", "press", mod, 0, pos.row - 1, pos.col - 1)
  api.nvim_input_mouse("left", "release", mod, 0, pos.row - 1, pos.col - 1)
  wait(150)
  expect(mode() == "n", "mode after the click: " .. mode())
  expect(vim.fn.line "." == 2, "cursor on line " .. vim.fn.line ".")
end)

check("Tree keys: - goes up a folder, q closes the tree", function()
  press(super "b", 300)
  local explorer = require("nvim-tree.core").get_explorer()
  local root = explorer.absolute_path
  press("-", 300)
  local up = require("nvim-tree.core").get_explorer().absolute_path
  press("q", 200)
  local visible = require("nvim-tree.api").tree.is_visible()
  vim.cmd("cd " .. proj)
  require("nvim-tree.api").tree.change_root(proj)
  expect(up == vim.fs.dirname(root), "- went to " .. tostring(up))
  expect(not visible, "q left the tree open")
end)

check("A message takes one line: three lines show as one with [+2]", function()
  press(':echo "one\\ntwo\\nthree"<CR>', 300)
  local cmd = cmd_win()
  expect(
    cmd and api.nvim_win_get_height(cmd) == 1,
    "command line is " .. (cmd and api.nvim_win_get_height(cmd) or "?") .. " rows"
  )
  for _, w in ipairs(api.nvim_list_wins()) do
    local ft = vim.bo[api.nvim_win_get_buf(w)].filetype
    if ft == "pager" or ft == "msg" then
      expect(api.nvim_win_get_config(w).hide, ft .. " window showed up")
    end
  end
end)

check("Sizing panes (Neovide zoom, tree open) leaves no empty rows under the status line", function()
  vim.cmd "only"
  local win = api.nvim_get_current_win()
  -- The zoom rescale asks a pane that fills the screen for a row less.
  require("panes").restore { [win] = { api.nvim_win_get_width(win), api.nvim_win_get_height(win) - 1 } }
  expect(vim.o.cmdheight == 0, "cmdheight is " .. vim.o.cmdheight .. " after sizing the pane")
end)

check("Typed commands show in a centred box on the finder's row; long input wraps, all of it in view", function()
  local cols = vim.o.columns
  local function boxed(what)
    local w = cmd_win()
    expect(w, what .. ": no command line window")
    local cfg = api.nvim_win_get_config(w)
    local row = require("finder").window().row
    expect(row > 3, "the finder's row is " .. row)
    expect(
      cfg.relative == "editor" and cfg.row == row and not cfg.hide,
      what
        .. ": not on the finder's row: "
        .. vim.inspect {
          cfg.relative,
          cfg.row,
          cfg.hide,
        }
    )
    local mid = cfg.col + (cfg.width + 2) / 2
    expect(
      math.abs(mid - cols / 2) <= 2 and cfg.width < cols,
      what .. ": not centred, col " .. cfg.col .. " width " .. cfg.width
    )
    return w, cfg
  end
  local long = ("word "):rep(80)
  press(":echo '" .. long, 300)
  local w, cfg = boxed ":"
  local th = api.nvim_win_text_height(w, {}).all
  expect(
    th >= 3 and api.nvim_win_get_height(w) == th,
    "long input: " .. th .. " text rows in a " .. cfg.height .. "-row box"
  )
  expect(vim.o.cmdheight == 0, "the bottom line opened too")
  press("<C-u>e ", 100)
  press("<Tab>", 300)
  local info = vim.fn.cmdcomplete_info()
  expect(info.pum_visible == 1, "Tab completion opened no menu")
  w = boxed "Tab"
  expect(api.nvim_win_get_height(w) >= 1 + math.min(#info.matches, vim.o.pumheight), "the menu sits outside the box")
  press("<Esc>", 150)
  press("/greet", 200)
  boxed "/"
  press("<Esc>", 150)
  press(":echo 'seen at the bottom'<CR>", 300)
  w = cmd_win()
  cfg = api.nvim_win_get_config(w)
  expect(cfg.relative == "laststatus", "the message is not on the bottom line: " .. cfg.relative)
  expect(
    table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false)):find "seen at the bottom",
    "message not shown"
  )
  -- Every ui2 window is cut to the screen (Neovide does not cut floats).
  for _, x in ipairs(api.nvim_list_wins()) do
    local ft = vim.bo[api.nvim_win_get_buf(x)].filetype
    if ft == "cmd" or ft == "pager" or ft == "dialog" then
      expect(api.nvim_win_get_width(x) <= cols, ft .. " window is " .. api.nvim_win_get_width(x) .. " wide")
    end
  end
end)

check("Suggestions pop up as you type a command (:e shows files), inside the box, without changing the text", function()
  local function inside(what)
    local cfg, pum = api.nvim_win_get_config(cmd_win()), vim.fn.pum_getpos()
    expect(
      pum.row and pum.row > cfg.row and pum.row + pum.height <= cfg.row + 1 + cfg.height,
      what
        .. ": the menu (row "
        .. tostring(pum.row)
        .. ") is outside the box (rows "
        .. cfg.row
        .. "+"
        .. cfg.height
        .. ")"
    )
  end
  -- Typed in one burst, before the box has been drawn.
  press(":e ", 300)
  local info = vim.fn.cmdcomplete_info()
  expect(info.pum_visible == 1, ":e showed no suggestions until Tab")
  inside ":e "
  expect(vim.tbl_contains(info.matches or {}, "a.ml"), "a.ml is not suggested: " .. vim.inspect(info.matches))
  expect(vim.fn.getcmdline() == "e ", "typing changed the line to " .. vim.fn.getcmdline())
  press("a.", 300)
  info = vim.fn.cmdcomplete_info()
  expect(info.pum_visible == 1 and not vim.tbl_contains(info.matches, "b.ml"), "the list did not narrow as you type")
  inside ":e a."
  press("<Tab>", 200)
  expect(vim.fn.getcmdline():find "^e a%.ml", "Tab does not pick the first suggestion: " .. vim.fn.getcmdline())
  press("<Esc>", 150)
  -- Up still recalls the last command, as before.
  press(":echo 'from history'<CR>", 200)
  press(":<Up>", 200)
  expect(vim.fn.getcmdline() == "echo 'from history'", "Up gave " .. vim.fn.getcmdline())
  press("<Esc>", 150)
end)

-- ── Found by review (each was a real bug) ─────────────────────────────────

check("dune keys open a new pane; the .ml file stays in the editor", function()
  vim.cmd "edit! a.ml"
  local editor = api.nvim_get_current_win()
  press(" ob", 800)
  local term = win_of(is_term)
  expect(term, "no dune pane")
  expect(name_of(editor) == "a.ml", "the editor shows " .. name_of(editor))
  expect(api.nvim_win_get_buf(term) ~= api.nvim_win_get_buf(editor), "dune took over a.ml")
end)

check("Alt+B open then closed: no error", function()
  vim.v.errmsg = ""
  press(super "b", 300)
  press(super "b", 300)
  expect(vim.v.errmsg == "", vim.v.errmsg)
end)

check("F5 leaves the file in Normal mode, with focus", function()
  vim.cmd "edit! hello.py"
  local editor = api.nvim_get_current_win()
  press("<F5>", 1200)
  expect(api.nvim_get_current_win() == editor, "focus moved")
  expect(mode() == "n", "mode is " .. mode())
end)

check("A file opened where a terminal was gets numbers and signs back", function()
  local term = editor_and_terminal()
  api.nvim_set_current_win(term)
  vim.cmd "stopinsert"
  vim.cmd "edit b.ml"
  expect(
    vim.wo.number and vim.wo.signcolumn ~= "no",
    "number " .. tostring(vim.wo.number) .. ", signs " .. vim.wo.signcolumn
  )
end)

check("Alt+P from a terminal opens the file in the editor pane", function()
  local term = editor_and_terminal()
  expect(api.nvim_get_current_win() == term, "terminal not focused")
  press(super "p", 600)
  expect(picker_active(), "no picker")
  local target = MiniPick.get_picker_state().windows.target
  press("<Esc>", 200)
  expect(not is_term(target), "the picker would open the file in the terminal")
end)

check("Mouse moves and stray keys after an operator change nothing", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  local line = vim.fn.getline(1)
  -- c, a mouse move, w: changes the word, as cw does.
  api.nvim_input "c"
  api.nvim_input_mouse("move", "", "", 0, 5, 5)
  api.nvim_input "w<Esc>"
  wait(200)
  expect(vim.fn.getline(1) == line:gsub("^let", "", 1), "c + mouse move + w gave '" .. vim.fn.getline(1) .. "'")
  vim.cmd "edit! a.ml"
  local tick = vim.b.changedtick
  press("d" .. super "y", 200)
  expect(mode() == "n", "mode is " .. mode())
  expect(vim.b.changedtick == tick, "d + a stray key changed the file")
end)

check("Alt+C then Alt+V in Normal pastes the whole line above", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(2, 3)
  local second, count = vim.fn.getline(2), vim.fn.line "$"
  press(super "c", 150)
  press(super "v", 200)
  expect(vim.fn.line "$" == count + 1, "line count " .. vim.fn.line "$")
  expect(
    vim.fn.getline(2) == second and vim.fn.getline(3) == second,
    "lines: " .. vim.fn.getline(2) .. " / " .. vim.fn.getline(3)
  )
  vim.cmd "edit! a.ml"
end)

-- Friction 2026-10-27 (N1, N2): pasting over a word swapped the clipboard for
-- that word, so the second paste put back the old word.
check("Paste over a selection twice: both get the copied text (Alt+V, p)", function()
  for _, key in ipairs { super "v", "p" } do
    vim.cmd "enew!"
    api.nvim_buf_set_lines(0, 0, -1, false, { "one two three" })
    vim.fn.setreg("+", "XY", "v")
    vim.fn.cursor(1, 1)
    press("viw" .. key, 150)
    press("wviw" .. key, 150)
    local name = key == "p" and "p" or "Alt+V"
    expect(vim.fn.getline(1) == "XY XY three", name .. " twice made: " .. vim.fn.getline(1))
    expect(vim.fn.getreg "+" == "XY", name .. " left the clipboard as '" .. vim.fn.getreg "+" .. "'")
  end
  vim.cmd "enew!"
end)

check("Changing text (c, s) keeps the copied text on the clipboard", function()
  vim.cmd "enew!"
  api.nvim_buf_set_lines(0, 0, -1, false, { "keep one two three" })
  vim.fn.cursor(1, 1)
  press("viw" .. super "c", 150)
  for _, keys in ipairs { "wciwA<Esc>", "w2sB<Esc>", "wvecC<Esc>", "0CD<Esc>" } do
    press(keys, 150)
    expect(vim.fn.getreg "+" == "keep", keys .. " left the clipboard as '" .. vim.fn.getreg "+" .. "'")
  end
  expect(vim.fn.getline(1) == "D", "the changes made: " .. vim.fn.getline(1))
  -- Typing over a snippet field (Select mode).
  api.nvim_buf_set_lines(0, 0, -1, false, { "keep one" })
  press("wviw<C-g>E<Esc>", 150)
  expect(vim.fn.getline(1) == "keep E", "typing over the selection made: " .. vim.fn.getline(1))
  expect(vim.fn.getreg "+" == "keep", "Select mode left the clipboard as '" .. vim.fn.getreg "+" .. "'")
  vim.snippet.expand "f(${1:arg}, ${2:other})"
  press("F", 150)
  press("<Tab>", 150)
  press("G<Esc>", 200)
  expect(vim.fn.getline(1):find "f%(F, G%)", "snippet fields made: " .. vim.fn.getline(1))
  expect(vim.fn.getreg "+" == "keep", "a snippet field left the clipboard as '" .. vim.fn.getreg "+" .. "'")
  api.nvim_buf_set_lines(0, 0, -1, false, { "keep one" })
  press('w"aciwZ<Esc>', 150)
  expect(vim.fn.getreg "a" == "one", '"aciw filled register a with ' .. vim.fn.getreg "a")
  press("u", 150)
  vim.fn.cursor(1, 1)
  press("dw", 150)
  expect(vim.fn.getreg "+" == "keep ", "dw no longer cuts: clipboard '" .. vim.fn.getreg "+" .. "'")
  vim.cmd "enew!"
end)

check("A file opened inside a project does not replace its session", function()
  -- This window never opened proj as a project (reset() only cd's there).
  local sdir = vim.fn.stdpath "state" .. "/sessions"
  for _, f in ipairs(vim.fn.glob(sdir .. "/*", false, true)) do
    os.remove(f)
  end
  vim.cmd "edit! a.ml"
  require("projects").save()
  local written = vim.fn.glob(sdir .. "/*", false, true)
  expect(#written == 0, "a session was written: " .. table.concat(written, ", "))
end)

check("A project's session is saved under its own name and comes back", function()
  local dir = proj .. "/sub-c"
  vim.fn.mkdir(dir, "p")
  vim.fn.mkdir(proj .. "/sub-a", "p") -- the other folder it visits
  vim.fn.writefile({ "let z = 0" }, dir .. "/z.ml")
  local projects = require "projects"
  projects.open_folder(dir)
  wait(300)
  vim.cmd "edit z.ml"
  projects.save()
  local session = session_file(dir)
  expect(vim.uv.fs_stat(session), "no session at " .. session)
  -- Open another folder, then come back: z.ml is open again.
  projects.open_folder(proj .. "/sub-a")
  wait(300)
  projects.open_folder(dir)
  wait(300)
  expect(vim.fn.bufnr(dir .. "/z.ml") ~= -1, "z.ml did not come back")
end)

check("A zoom is not saved as a tab; no files left = no session", function()
  local dir = proj .. "/sub-d"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "let d = 0" }, dir .. "/d.ml")
  local projects = require "projects"
  projects.open_folder(dir)
  wait(300)
  vim.cmd "edit d.ml"
  vim.cmd "vsplit"
  press(super "f", 200)
  expect(#api.nvim_list_tabpages() == 2, "zoom made no tab")
  projects.save()
  local session = session_file(dir)
  local text = table.concat(vim.fn.readfile(session), "\n")
  expect(not text:find "tabnew", "the zoom tab was saved")
  vim.cmd "silent! tabonly"
  vim.cmd "silent! only"
  vim.cmd "enew"
  pcall(api.nvim_buf_delete, vim.fn.bufnr(dir .. "/d.ml"), { force = true })
  projects.save()
  expect(not vim.uv.fs_stat(session), "the session stayed with no files open")
end)

check("The opam switch the shell has active wins over the default one", function()
  local fake = proj .. "/fake-switch"
  vim.fn.mkdir(fake .. "/bin", "p")
  local saved_path, saved_prefix = vim.env.PATH, vim.env.OPAM_SWITCH_PREFIX
  vim.env.OPAM_SWITCH_PREFIX = fake
  vim.env.PATH = saved_path .. ":" .. fake .. "/bin"
  require("tools").setup_path()
  local first = vim.split(vim.env.PATH, ":")[1]
  vim.env.PATH, vim.env.OPAM_SWITCH_PREFIX = saved_path, saved_prefix
  expect(first == fake .. "/bin", "first on PATH: " .. first)
end)

check("The status line shows the git branch, also in a git worktree", function()
  local repo = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
  wait(100)
  local line = require("statusline").render()
  vim.cmd("cd " .. proj)
  local head = vim.trim(vim.fn.system { "git", "-C", repo, "branch", "--show-current" })
  if head == "" then -- detached: the status line shows the short commit
    head = vim.trim(vim.fn.system { "git", "-C", repo, "rev-parse", "--short", "HEAD" })
  end
  expect(head ~= "" and line:find(head, 1, true), "branch '" .. head .. "' not in: " .. line)
end)

-- ── Found by the second review ────────────────────────────────────────────

check("Tree with no editor left: a file opens beside it, the tree keeps its width", function()
  local term = editor_and_terminal()
  api.nvim_set_current_win(editor_win())
  vim.cmd "close"
  press(super "b", 400)
  local tree = api.nvim_get_current_win()
  local width = api.nvim_win_get_width(tree)
  vim.fn.search "b\\.ml"
  press("<CR>", 400)
  local editor = win_of(function(w)
    return name_of(w) == "b.ml"
  end)
  expect(editor, "b.ml did not open in a pane")
  expect(api.nvim_win_get_width(tree) == width, "tree went from " .. width .. " to " .. api.nvim_win_get_width(tree))
  expect(api.nvim_win_get_width(editor) >= 40, "the new pane is " .. api.nvim_win_get_width(editor) .. " wide")
  expect(is_term(term), "the terminal pane changed")
end)

check("Reopen while a terminal is zoomed never puts the file in the terminal's pane", function()
  vim.cmd "edit! a.ml"
  vim.cmd "edit! b.ml"
  press(super "w", 200) -- closes b.ml: something to reopen
  local term = editor_and_terminal()
  press(super "f", 300)
  press(super "S-t", 300)
  press(super "f", 300)
  expect(api.nvim_win_is_valid(term) and is_term(term), "the terminal pane now shows " .. name_of(term))
end)

check("Alt+W moves on to tabs a session listed but has not loaded yet", function()
  vim.cmd "edit! a.ml"
  vim.cmd "badd b.ml"
  vim.cmd "badd c.ml"
  press(super "w", 200)
  local first = name_of(0)
  press(super "w", 200)
  local second = name_of(0)
  expect(first ~= "" and second ~= "", "showed an empty tab: '" .. first .. "', '" .. second .. "'")
end)

check("Linked fills survive in the flat look: snippet fields, tree row band, overlay diff", function()
  -- (Glass has no cursor-line band on purpose: the cursor marks the row.)
  local look = require("theme").look
  vim.cmd "Look flat"
  local lost = {}
  for _, name in ipairs { "SnippetTabstop", "NvimTreeCursorLine", "MiniDiffOverAdd" } do
    if api.nvim_get_hl(0, { name = name, link = false }).bg == nil then
      lost[#lost + 1] = name
    end
  end
  vim.cmd("Look " .. look)
  expect(#lost == 0, "lost their fill: " .. table.concat(lost, ", "))
end)

check("The tree's current row has the list fill in both looks, focused only", function()
  local look = require("theme").look
  local bad = {}
  for _, l in ipairs { "glass", "flat" } do
    vim.cmd("Look " .. l)
    local row = api.nvim_get_hl(0, { name = "NvimTreeCursorLine", link = false }).bg
    for _, other in ipairs { "PmenuSel", "MiniPickMatchCurrent" } do
      local bg = api.nvim_get_hl(0, { name = other, link = false }).bg
      if row == nil or row ~= bg then
        bad[#bad + 1] = ("%s: tree row %s, %s %s"):format(l, tostring(row), other, tostring(bg))
      end
    end
  end
  press(super "b", 400)
  local tree = api.nvim_get_current_win()
  press("<C-l>", 200)
  local ns = api.nvim_get_hl_ns { winid = tree }
  -- (An empty group in a namespace draws nothing; link = false would read
  -- through to the global one.)
  if ns == 0 or next(api.nvim_get_hl(ns, { name = "NvimTreeCursorLine" })) ~= nil then
    bad[#bad + 1] = "the unfocused tree still shows its row fill"
  end
  vim.cmd("Look " .. look)
  expect(#bad == 0, table.concat(bad, "; "))
end)

check("Terminal colours are Omarchy's 16 (dim text stays readable)", function()
  local p = require("theme").palette
  expect(
    vim.g.terminal_color_8 == (p.muted or vim.g.terminal_color_8),
    "colour 8 is " .. tostring(vim.g.terminal_color_8)
  )
  if p.bright_red then
    expect(vim.g.terminal_color_9 == p.bright_red, "colour 9 is " .. tostring(vim.g.terminal_color_9))
  end
end)

check("Double-click on a space marks nothing", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 4) -- the space after "let"
  require("words").select_word()
  wait(100)
  local marks = word_marks()
  press "<Esc>"
  expect(#marks == 0, "marked " .. #marks)
end)

-- ── Found by the third review ─────────────────────────────────────────────

-- Start another Neovim (headless, same scratch world) and return what `lua`
-- writes, half a second after startup.
local function other_nvim(cwd, args, lua)
  local cmd = { "nvim", "--headless" }
  vim.list_extend(cmd, args)
  vim.list_extend(cmd, {
    "+lua vim.defer_fn(function() io.stdout:write(" .. lua .. ") vim.cmd('qa!') end, 600)",
  })
  local result = vim.system(cmd, { cwd = cwd, text = true }):wait(10000)
  return vim.trim(result.stdout or "")
end

check("`nvim folder` opens that folder as this window's project", function()
  vim.fn.mkdir(proj .. "/sub-a", "p")
  local dir = vim.uv.fs_realpath(proj .. "/sub-a")
  local got = other_nvim(proj, { dir }, "tostring(require('projects').current()) .. ' ' .. vim.fn.getcwd()")
  expect(got == dir .. " " .. dir, "got: " .. got)
end)

check("A bare start in a project's subfolder opens the project's root", function()
  -- proj has a dune-project; sub-a is a folder inside it.
  vim.fn.mkdir(proj .. "/sub-a", "p")
  local got = other_nvim(proj .. "/sub-a", {}, "tostring(require('projects').current())")
  expect(got == vim.uv.fs_realpath(proj), "got: " .. got)
end)

check("A plain `nvim file` owns no project", function()
  local got = other_nvim(proj, { "a.ml" }, "tostring(require('projects').current())")
  expect(got == "nil", "got: " .. got)
end)

check("Tree - moves only the tree's root; the window keeps its folder", function()
  local cwd = vim.fn.getcwd()
  press(super "b", 300)
  press("-", 300)
  local after = vim.fn.getcwd()
  press("q", 200)
  require("nvim-tree.api").tree.change_root(proj)
  expect(after == cwd, "folder changed to " .. after)
end)

check("F5 after swapping panes keeps the file and reuses the terminal", function()
  vim.cmd "edit! hello.py"
  press("<F5>", 1200)
  -- The file moves into the pane F5 ran in (focus follows it).
  press(super "S-Right", 300)
  local file_win = win_of(function(w)
    return name_of(w) == "hello.py"
  end)
  expect(file_win, "hello.py is not in a pane before the second run")
  api.nvim_set_current_win(file_win)
  press("<F5>", 1200)
  expect(vim.fn.buflisted(vim.fn.bufnr "hello.py") == 1, "hello.py was closed")
  local terms = #vim.tbl_filter(is_term, wins())
  expect(terms == 1, terms .. " terminal panes")
  expect(
    win_of(function(w)
      return name_of(w) == "hello.py"
    end),
    "no pane shows hello.py"
  )
end)

check("Org files keep orgmode's own completion", function()
  vim.cmd "edit! README.org"
  wait(800)
  expect(not vim.bo.omnifunc:find "MiniCompletion", "omnifunc is " .. vim.bo.omnifunc)
end)

-- ── Found by the fourth review ────────────────────────────────────────────

check("Dune reuses its pane; q closes it while dune runs", function()
  vim.cmd "edit! a.ml"
  press(" ob", 800)
  press("<C-\\><C-n>", 100)
  vim.cmd "wincmd p"
  press(" ob", 800)
  local terms = #vim.tbl_filter(is_term, wins())
  expect(terms == 1, terms .. " dune panes")
  expect(mode() == "t", "dune pane not in terminal mode: " .. mode())
  press("q", 300)
  expect(#vim.tbl_filter(is_term, wins()) == 0, "q did not close the dune pane")
end)

check("A pane opened while zoomed lands in the layout, not the zoom", function()
  vim.cmd "edit! a.ml"
  vim.cmd "vsplit b.ml"
  press(super "f", 200)
  expect(#api.nvim_list_tabpages() == 2, "no zoom")
  press(super "CR", 400)
  expect(#api.nvim_list_tabpages() == 1, "still zoomed: the terminal went into the zoom tab")
  expect(#vim.tbl_filter(is_term, wins()) == 1, "no terminal in the layout")
end)

check("A zoom tab left alone (:tabonly) acts as a plain tab", function()
  vim.cmd "edit! a.ml"
  vim.cmd "vsplit b.ml"
  press(super "f", 200)
  vim.cmd "tabonly"
  press(super "CR", 400)
  expect(#vim.tbl_filter(is_term, wins()) == 1, "Alt+Return made no terminal")
end)

check("Unzoom from a page that is wiped when hidden gives no error", function()
  vim.cmd "edit! a.ml"
  vim.cmd "vsplit b.ml"
  press(super "f", 200)
  expect(#api.nvim_list_tabpages() == 2, "no zoom")
  -- A throwaway page (plugins open these): gone as soon as no pane shows it.
  vim.cmd "enew"
  vim.bo.bufhidden = "wipe"
  vim.v.errmsg = ""
  press(super "f", 200)
  expect(#api.nvim_list_tabpages() == 1, "still zoomed")
  expect(vim.v.errmsg == "", vim.v.errmsg)
  expect(vim.fn.expand "%:t" == "b.ml", "the pane shows " .. vim.fn.expand "%:t")
end)

check("Alt+O will not open a project another window has", function()
  local dir = proj .. "/sub-e"
  vim.fn.mkdir(dir, "p")
  local close_other = open_in_other_window(dir)
  local before = require("projects").current()
  require("projects").open_folder(dir)
  local after = require("projects").current()
  close_other()
  expect(after == before, "opened it anyway")
end)

check("Alt+Shift symbol keys do nothing (Alt+$ used to jump to the line end)", function()
  vim.cmd "edit! a.ml"
  vim.fn.cursor(1, 1)
  press(super "$", 150)
  expect(vim.fn.col "." == 1, "cursor moved to column " .. vim.fn.col ".")
end)

-- ── Divider hover ─────────────────────────────────────────────────────────

check("divider hover lights exactly the hovered line", function()
  vim.cmd "vsplit b.ml"
  vim.cmd "wincmd l"
  vim.cmd "belowright split README.md"
  -- left: a.ml (full height), right: b.ml over README.md
  local left = vim.fn.win_getid(1)
  local top_right = vim.fn.win_getid(2)
  local col = api.nvim_win_get_width(left) -- 0-based screen col of the divider
  local row = api.nvim_win_get_position(left)[1] + 2
  api.nvim_input_mouse("move", "", "", 0, row, col)
  wait(120)
  expect(lfc(left):find "vert:┃", "left pane's divider not heavy: " .. lfc(left))
  expect(lfc(top_right) == "", "top-right pane changed too")
  -- Horizontal line between b.ml and README.md.
  local hrow = api.nvim_win_get_position(top_right)[1] + api.nvim_win_get_height(top_right)
  api.nvim_input_mouse("move", "", "", 0, hrow, col + 5)
  wait(120)
  expect(lfc(top_right):find "horiz:━", "horizontal divider not heavy")
  expect(lfc(left) == "", "vertical divider stayed lit")
  -- Off every line: nothing lit.
  api.nvim_input_mouse("move", "", "", 0, row, 2)
  wait(120)
  expect(lfc(top_right) == "" and lfc(left) == "", "a line stayed lit")
end)

-- ── Tree layout and sort (the old config's, which the usage log could not see) ──

local function tree_row(pattern)
  for i, line in ipairs(api.nvim_buf_get_lines(api.nvim_win_get_buf(tree_win()), 0, -1, false)) do
    if line:find(pattern) then
      return i
    end
  end
end

check("Tree sort: gn / ga / gs keys and the clickable Sort row", function()
  press(super "b", 400)
  local win = tree_win()
  expect(win, "no tree")
  for _, lhs in ipairs { "gn", "ga", "gs" } do
    expect(vim.fn.maparg(lhs, "n", false, true).buffer == 1, lhs .. " is not a tree key")
  end
  local bar = api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
  expect(
    bar:find("Sort", 1, true) and bar:find("Name (gn)", 1, true) and bar:find("Added (ga)", 1, true),
    "Sort row: '" .. bar .. "'"
  )
  -- A file made now is the newest: Added puts it above a.ml, Name below.
  local newest = proj .. "/zz_newest.ml"
  vim.fn.writefile({ "let z = 0" }, newest)
  local ok, err = pcall(function()
    press("R", 300)
    press("ga", 300)
    expect(require("explorer").sort == "added", "ga did not switch the sort")
    expect(tree_row "zz_newest" < tree_row "a%.ml", "Added: newest file not above a.ml")
    press("gn", 300)
    expect(require("explorer").sort == "name", "gn did not switch the sort")
    expect(tree_row "zz_newest" > tree_row "a%.ml", "Name: zz_newest not below a.ml")
    press("gs", 400)
    expect(picker_active() or floats() > 0, "gs opened no choice")
    press("<Esc>", 200)
  end)
  vim.fn.delete(newest)
  require("explorer").set_sort "name"
  expect(ok, err)
end)

check("Tree keys kept from the old tree: Tab preview, C-v / C-x split, f filter, E / W, D trash", function()
  press(super "b", 400)
  local missing = {}
  for _, lhs in ipairs { "<Tab>", "<C-V>", "<C-X>", "f", "E", "W", "D" } do
    if vim.fn.maparg(lhs, "n", false, true).buffer ~= 1 then
      missing[#missing + 1] = lhs
    end
  end
  expect(#missing == 0, "not tree keys: " .. table.concat(missing, " "))
  vim.fn.search "b.ml"
  local n = #wins()
  press("<Tab>", 400)
  expect(vim.bo.filetype == "NvimTree", "Tab preview moved focus out of the tree")
  expect(#wins() == n, "Tab preview changed the panes")
end)

check("Tree spacing: two-cell gutter, folder arrows, sort row above the folder name", function()
  vim.fn.mkdir(proj .. "/sub", "p")
  vim.fn.writefile({ "x" }, proj .. "/sub/inner.ml")
  press(super "b", 400)
  local win = tree_win()
  expect(win, "no tree")
  local ok, err = pcall(function()
    press("R", 300)
    expect(vim.fn.getwininfo(win)[1].textoff >= 2, "no left gutter: textoff " .. vim.fn.getwininfo(win)[1].textoff)
    expect(vim.wo[win].winbar ~= "", "no Sort row above the tree")
    local rows = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false)
    local folder = rows[tree_row "sub$"] or ""
    local file = rows[tree_row "a%.ml$"] or ""
    -- A closed folder starts with its arrow; a file at the same level is
    -- padded by the arrow's width so the icons line up.
    expect(vim.fn.strdisplaywidth(folder:match "^(.-)sub$") >= 4, "folder row '" .. folder .. "' has no arrow + icon")
    expect(file:match "^%s", "file row '" .. file .. "' not padded under the arrows")
  end)
  vim.fn.delete(proj .. "/sub", "rf")
  expect(ok, err)
end)

check("Tree paste with nothing copied: one short line, clipboard text never read as paths", function()
  press(super "b", 400)
  vim.fn.setreg("+", "just some words\nnot a path")
  local before = floats()
  vim.cmd "messages clear"
  press("p", 300)
  local msgs = vim.split(vim.trim(vim.fn.execute "messages"), "\n", { trimempty = true })
  expect(floats() == before, "a popup appeared")
  expect(#msgs <= 1, #msgs .. " message lines")
  expect(not vim.uv.fs_stat(proj .. "/just some words"), "pasted clipboard text as a file")
end)

check("Flat look is at least as clear as the old opaque look", function()
  local look = require("theme").look
  vim.cmd "Look flat"
  local bg = api.nvim_get_hl(0, { name = "Normal" }).bg
  local dim = api.nvim_get_namespaces().focus_dim
  -- The old config's opaque look, measured 2026-10-23.
  local floor = {
    { 0, "Normal", 13.16 },
    { 0, "Comment", 5.70 },
    { 0, "LineNr", 1.87 },
    { 0, "NvimTreeNormal", 13.16 },
    { dim, "Normal", 4.68 },
    { dim, "Comment", 2.56 },
  }
  local low = {}
  for _, f in ipairs(floor) do
    local hl = api.nvim_get_hl(f[1], { name = f[2], link = false })
    local fg = hl.fg or api.nvim_get_hl(f[1], { name = "Normal", link = false }).fg
    local r = contrast(fg, bg)
    if r < f[3] then
      low[#low + 1] = string.format("%s%s %.2f < %.2f", f[1] == 0 and "" or "dim ", f[2], r, f[3])
    end
  end
  vim.cmd("Look " .. look)
  expect(#low == 0, table.concat(low, "; "))
end)

-- ── Kept from the old config (2026-10-23 keep list) ──

check("Diagnostics: text at every line end, not redrawn while typing", function()
  local cfg = vim.diagnostic.config()
  expect(
    type(cfg.virtual_text) == "table" and not cfg.virtual_text.current_line,
    "virtual text only on the cursor line"
  )
  expect(cfg.update_in_insert == false, "diagnostics update in Insert")
end)

check("Markdown always wraps at word boundaries, also a file with a pipe table", function()
  local plain, tabled = proj .. "/prose.md", proj .. "/table.md"
  vim.fn.writefile({ "# Notes", "", "Some prose." }, plain)
  vim.fn.writefile({ "# Table", "", "| a | b |", "|---|---|", "| 1 | 2 |" }, tabled)
  local got = {}
  for _, f in ipairs { plain, tabled } do
    vim.cmd("edit " .. f)
    got[#got + 1] = { vim.wo.wrap, vim.wo.linebreak, vim.wo.breakindent }
  end
  vim.cmd "bwipeout! | bwipeout!"
  vim.fn.delete(plain)
  vim.fn.delete(tabled)
  for i, g in ipairs(got) do
    expect(
      g[1] and g[2] and g[3],
      (i == 1 and "prose" or "table") .. " file: wrap/linebreak/breakindent = " .. vim.inspect(g)
    )
  end
end)

check("Neovide: the cursor glides in Insert too (0.05 s)", function()
  expect(vim.g.neovide_cursor_animate_in_insert_mode == true, "no glide in Insert")
  expect(vim.g.neovide_cursor_animation_length == 0.05, "glide is " .. tostring(vim.g.neovide_cursor_animation_length))
end)

check("Mac: Cmd keys reach Neovim and nvm's node is on PATH (old Mac branch)", function()
  local cfg = vim.fn.stdpath "config"
  local gui = table.concat(vim.fn.readfile(cfg .. "/lua/gui.lua"), "\n")
  local tools = table.concat(vim.fn.readfile(cfg .. "/lua/tools.lua"), "\n")
  expect(
    gui:find "if is_macos then%s+[^\n]*\n[^\n]*neovide_input_use_logo = true",
    "gui.lua sets no neovide_input_use_logo on macOS"
  )
  expect(tools:find("nvm/alias/default", 1, true), "tools.lua has no nvm PATH on macOS")
end)

check("Status line: the mode as coloured text (no block) and WakaTime's time today", function()
  local saved = package.loaded.wakatime
  package.loaded.wakatime = {
    statusline = function()
      return "1 hr 20 mins"
    end,
  }
  local line = require("statusline").render()
  package.loaded.wakatime = saved
  expect(line:find("%#StatusLineModeNormal#NORMAL", 1, true), "no NORMAL mode text: " .. line)
  local hl = api.nvim_get_hl(0, { name = "StatusLineModeNormal", link = false })
  expect(hl.fg and not hl.bg and not hl.reverse, "the mode is a filled block")
  expect(line:find("1h 20m", 1, true), "no WakaTime time: " .. line)
end)

check("OCaml keywords get tree-sitter colours; a dead query link counts as missing", function()
  local file = proj .. "/colour.ml"
  vim.fn.writefile({ "let x = 1 (* note *)" }, file)
  vim.cmd("edit " .. file)
  vim.treesitter.get_parser(0):parse(true)
  local caps = vim.treesitter.get_captures_at_pos(0, 0, 0)
  vim.cmd "bwipeout!"
  vim.fn.delete(file)
  expect(#caps > 0, "`let` has no tree-sitter capture (highlight queries not loaded)")
  -- The 2026-10-25 data-folder rename left the query links dead.
  local link = vim.fn.stdpath "data" .. "/site/queries/ocaml"
  local target = vim.uv.fs_readlink(link)
  expect(target, "queries/ocaml is not a link")
  vim.uv.fs_unlink(link)
  vim.uv.fs_symlink(proj .. "/no-such-folder", link)
  local missing = require("plugins").missing_parsers()
  vim.uv.fs_unlink(link)
  vim.uv.fs_symlink(target, link)
  expect(vim.tbl_contains(missing, "ocaml"), "dead ocaml query link not seen as missing")
end)

check("OCaml comments show in the comment colour on every line, never in plain text", function()
  -- Friction 2026-10-28: with the highlight queries gone, comments took the
  -- plain text colour and blended into the code.
  local file = proj .. "/comments.ml"
  vim.fn.writefile({
    "(** A doc comment that runs",
    "   onto a second line with [code]. *)",
    "let x = 1 (* a trailing note *)",
  }, file)
  vim.cmd("edit " .. file)
  vim.treesitter.get_parser(0):parse(true)
  -- The colour drawn at a spot: the last (highest) tree-sitter or language
  -- server group that sets one.
  local function fg_at(row, col)
    local pos = vim.inspect_pos(0, row, col)
    local fg, names = nil, {}
    for _, items in ipairs { pos.treesitter, pos.semantic_tokens } do
      for _, item in ipairs(items) do
        local name = item.hl_group or (item.opts and item.opts.hl_group)
        names[#names + 1] = name
        local hl = api.nvim_get_hl(0, { name = name, link = false })
        fg = hl.fg or fg
      end
    end
    return fg, table.concat(names, ",")
  end
  local spots = {
    { 0, 6, "doc comment" },
    { 1, 8, "its second line" },
    { 1, 28, "[code] in it" },
    { 2, 14, "trailing note" },
  }
  local seen = {}
  for _, spot in ipairs(spots) do
    seen[#seen + 1] = { spot[3], fg_at(spot[1], spot[2]) }
  end
  local let_fg = fg_at(2, 0)
  vim.cmd "bwipeout!"
  vim.fn.delete(file)
  local comment = api.nvim_get_hl(0, { name = "Comment", link = false })
  local text = api.nvim_get_hl(0, { name = "Normal", link = false }).fg
  expect(comment.fg and comment.fg ~= text, "Comment has the plain text colour")
  for _, s in ipairs(seen) do
    expect(s[2] == comment.fg, string.format("%s is not in the comment colour (groups: %s)", s[1], s[3]))
  end
  expect(let_fg and let_fg ~= comment.fg, "`let` is drawn in the comment colour")
end)

check("TODO / FIXME in comments are coloured words, never filled blocks", function()
  local file = proj .. "/todo.ml"
  vim.fn.writefile({ "(* TODO: one *)", "(* FIXME: two *)", 'let s = "TODO not a comment"' }, file)
  vim.cmd("edit " .. file)
  wait(400)
  local groups = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    local g = m[4].hl_group
    if type(g) == "string" and g:find "^TodoText" then
      groups[#groups + 1] = m[2] .. ":" .. g
    end
  end
  vim.cmd "bwipeout!"
  vim.fn.delete(file)
  local joined = table.concat(groups, " ")
  expect(joined:find("0:TodoTextTodo", 1, true), "TODO not coloured: " .. joined)
  expect(joined:find("1:TodoTextFix", 1, true), "FIXME not coloured: " .. joined)
  expect(not joined:find("2:", 1, true), "TODO inside a string was coloured")
  for _, g in ipairs { "TodoTextTodo", "TodoTextFix", "TodoTextWarn", "TodoTextNote" } do
    local hl = api.nvim_get_hl(0, { name = g, link = false })
    expect(hl.fg and not hl.bg and not hl.reverse, g .. " is a filled block")
  end
end)

check("TODO in a comment is coloured even before the background syntax parse", function()
  -- Tree-sitter parses in the background; on a busy machine mini.hipatterns
  -- looked first, found no comment, and left TODO plain until the next edit
  -- (the 2026-11-05 nightly merge failed the check above this way). Setting
  -- the filetype starts the highlighter, and nothing here yields, so the
  -- parse has not run when the TODO highlighter decides each word's colour.
  vim.cmd "enew"
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "(* TODO: one *)", 'let s = "TODO not a comment"' })
  vim.bo[buf].filetype = "ocaml"
  local group = MiniHipatterns.config.highlighters.todo.group
  local in_comment = group(buf, "TODO", { line = 1, from_col = 4 })
  local in_string = group(buf, "TODO", { line = 2, from_col = 10 })
  vim.cmd "bwipeout!"
  expect(in_comment == "TodoTextTodo", "TODO in the comment got " .. tostring(in_comment))
  expect(in_string == nil, "TODO inside a string got " .. tostring(in_string))
end)

check("Key hints pop up after a Space pause (mini.clue)", function()
  -- (The hint window itself waits inside getcharstr, which this runner's
  -- timers cannot see; this checks the trigger and its groups.)
  local m = vim.fn.maparg(" ", "n", false, true)
  expect(m.buffer == 1 and (m.desc or ""):find("Query keys", 1, true), "Space is not a hint trigger in this buffer")
  expect(MiniClue.config.window.delay <= 500, "hint delay " .. MiniClue.config.window.delay)
  local groups = {}
  for _, c in ipairs(MiniClue.config.clues) do
    groups[#groups + 1] = c.keys
  end
  expect(vim.tbl_contains(groups, "<Leader>f"), "no +Find group")
end)

check("Finder keys: C-x / C-v split, C-q sends the matches to quickfix", function()
  local maps = require("finder").load().config.mappings
  expect(maps.choose_in_split == "<C-x>", "split is " .. tostring(maps.choose_in_split))
  expect(maps.choose_in_vsplit == "<C-v>", "vsplit is " .. tostring(maps.choose_in_vsplit))
  expect(maps.mark ~= "<C-x>", "C-x still marks")
  vim.fn.setqflist({}, "r")
  press(" ff", 800)
  press("<C-q>", 400)
  expect(not MiniPick.is_picker_active(), "picker still open after C-q")
  expect(#vim.fn.getqflist() > 0, "quickfix list is empty")
  pcall(vim.cmd, "cclose")
end)

check("Tests never load WakaTime: no fake coding time, nothing written to the real home", function()
  wait(700) -- it would load 500 ms after the UI starts
  expect(vim.fn.exists ":WakaTimeToday" == 0, "vim-wakatime loaded with " .. tostring(vim.env.WAKATIME_HOME))
end)

check("A second OCaml snippet expands in the same buffer", function()
  local file = proj .. "/snip2.ml"
  vim.cmd("edit " .. file)
  press("imod_board ", 300)
  press("<Esc>", 100)
  press("Gorec_walk ", 300)
  press("<Esc>", 100)
  local got = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  vim.cmd "bwipeout!"
  vim.fn.delete(file)
  expect(got:find("let rec walk", 1, true), "second snippet stayed as typed: " .. got)
end)

check("OCaml snippets expand as you type; auto-brackets after a function", function()
  local file = proj .. "/snip.ml"
  vim.cmd("edit " .. file)
  press("imod_board ", 300)
  press("<Esc>", 100)
  local got = api.nvim_buf_get_lines(0, 0, -1, false)
  vim.cmd "bwipeout!"
  vim.fn.delete(file)
  expect(got[1] == "module Board = struct" and vim.trim(got[#got]) == "end", "mod_board gave: " .. vim.inspect(got))
  vim.cmd "enew"
  vim.bo.filetype = "python"
  api.nvim_buf_set_lines(0, 0, -1, false, { "print" })
  press("A", 100)
  require("snippets").auto_brackets { word = "print", kind = "Function" }
  local line, col = api.nvim_get_current_line(), api.nvim_win_get_cursor(0)[2]
  press("<Esc>", 100)
  vim.bo.filetype = "ocaml"
  api.nvim_buf_set_lines(0, 0, -1, false, { "List.map" })
  press("A", 100)
  require("snippets").auto_brackets { word = "map", kind = "Function" }
  local ocaml = api.nvim_get_current_line()
  press("<Esc>", 100)
  vim.cmd "bwipeout!"
  expect(line == "print()" and col == 6, "python: '" .. line .. "' cursor " .. col)
  expect(ocaml == "List.map", "OCaml got brackets: " .. ocaml)
end)

check("Closing a tab shows the one to its right (Chrome), else the left", function()
  vim.cmd("edit " .. proj .. "/a.ml | edit " .. proj .. "/b.ml | edit " .. proj .. "/c.ml")
  vim.cmd("buffer " .. vim.fn.bufnr(proj .. "/b.ml"))
  press(super "w", 300)
  local after_middle = name_of(api.nvim_get_current_win())
  press(super "w", 300)
  local after_last = name_of(api.nvim_get_current_win())
  expect(after_middle == "c.ml", "closing b.ml showed " .. after_middle)
  expect(after_last == "a.ml", "closing the last tab showed " .. after_last)
end)

check("Format on save: only OCaml and Rust; other languages only on :Format", function()
  local lsp = require "lsp"
  local calls = {}
  local real = lsp.format
  lsp.format = function(buf)
    calls[#calls + 1] = vim.bo[buf].filetype
  end
  local ok, err = pcall(function()
    for _, f in ipairs { "fmt_save.ml", "fmt_save.rs", "fmt_save.lua", "fmt_save.py" } do
      vim.cmd("edit " .. proj .. "/" .. f)
      api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
      vim.cmd "silent write"
      vim.cmd "bwipeout!"
      vim.fn.delete(proj .. "/" .. f)
    end
  end)
  lsp.format = real
  expect(ok, err)
  table.sort(calls)
  expect(table.concat(calls, ",") == "ocaml,rust", "formatted on save: " .. table.concat(calls, ","))
end)

-- ── Tab bar (tabs.lua) ──

local function tabline()
  local r = api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
  return r.str, r.width
end

check("Tab bar: close button, error count per tab, right-click and x close", function()
  vim.cmd("edit " .. proj .. "/a.ml | edit " .. proj .. "/b.ml | edit " .. proj .. "/c.ml")
  local b = vim.fn.bufnr(proj .. "/b.ml")
  local ns = api.nvim_create_namespace "test-tab-errors"
  vim.diagnostic.set(ns, b, {
    { lnum = 0, col = 0, message = "one", severity = vim.diagnostic.severity.ERROR },
    { lnum = 1, col = 0, message = "two", severity = vim.diagnostic.severity.ERROR },
  })
  local raw = require("tabs").render()
  local text = tabline()
  vim.diagnostic.reset(ns, b)
  expect(text:find("b.ml ●2", 1, true), "no error count on b.ml: " .. text)
  expect(select(2, raw:gsub("Tabs_close", "")) == 3, "not one close button per tab: " .. text)
  _G.Tabs_click(b, 1, "r", "    ")
  wait(200)
  expect(not api.nvim_buf_is_valid(b) or not vim.bo[b].buflisted, "right-click did not close b.ml")
  local c = vim.fn.bufnr(proj .. "/c.ml")
  _G.Tabs_close(c, 1, "l", "    ")
  wait(200)
  expect(not api.nvim_buf_is_valid(c) or not vim.bo[c].buflisted, "x did not close c.ml")
  expect(
    name_of(api.nvim_get_current_win()) == "a.ml",
    "after closing, editor shows " .. name_of(api.nvim_get_current_win())
  )
end)

check("Tab bar: left click from the tree opens the tab in the editor pane", function()
  vim.cmd("edit " .. proj .. "/a.ml | edit " .. proj .. "/b.ml")
  local a = vim.fn.bufnr(proj .. "/a.ml")
  press(super "b", 400)
  _G.Tabs_click(a, 1, "l", "    ")
  wait(200)
  expect(vim.bo.filetype ~= "NvimTree", "the tree now shows a file")
  expect(name_of(api.nvim_get_current_win()) == "a.ml", "editor shows " .. name_of(api.nvim_get_current_win()))
end)

check("Tab bar: 14 tabs shrink like Chrome (current keeps its name), never wider than the window", function()
  local made = {}
  for i = 1, 14 do
    local f = ("%s/a_rather_long_module_name_%02d.ml"):format(proj, i)
    vim.fn.writefile({ "let x = " .. i }, f)
    made[#made + 1] = f
    vim.cmd("edit " .. f)
  end
  vim.cmd("edit " .. made[7])
  local text = tabline()
  local step = require("tabs").step
  -- Room the tabs themselves take (render() before the fill to the right).
  local used = api.nvim_eval_statusline(require("tabs").render():gsub("%%=.*$", ""), { use_tabline = true }).width
  for _, f in ipairs(made) do
    pcall(vim.cmd, "bwipeout! " .. vim.fn.bufnr(f))
    vim.fn.delete(f)
  end
  expect(step > 1, "tabs did not shrink (step " .. step .. ")")
  expect(text:find("a_rather_long_module_name_07.ml", 1, true), "the current tab lost its name: " .. text)
  expect(used <= vim.o.columns, ("tabs take %d cells, window %d: %s"):format(used, vim.o.columns, text))
end)

check("Reopen puts a closed tab back in its place (Chrome)", function()
  vim.cmd("edit " .. proj .. "/a.ml | edit " .. proj .. "/b.ml | edit " .. proj .. "/c.ml")
  vim.cmd("buffer " .. vim.fn.bufnr(proj .. "/b.ml"))
  local before = require("tabs").index(api.nvim_get_current_buf())
  press(super "w", 300)
  press(super "S-t", 400)
  local after = require("tabs").index(api.nvim_get_current_buf())
  expect(name_of(api.nvim_get_current_win()) == "b.ml", "reopened " .. name_of(api.nvim_get_current_win()))
  expect(after == before, ("back at %s, was %s"):format(tostring(after), tostring(before)))
end)

-- ── Friction notes, 2026-10-25 ───────────────────────────────────────────

check("A window resize scales every pane; the terminal is never squeezed to a strip", function()
  expect(vim.env.TMUX, "SKIP not inside tmux")
  local function screen(cols)
    vim.fn.system { "tmux", "resize-window", "-x", tostring(cols), "-y", "50" }
    wait(500)
  end
  local editor = api.nvim_get_current_win()
  -- A bare shell: this check is about the pane, and a zsh that loads nvm takes
  -- a second, or 20 and more on a busy machine (tests run at nice 19).
  local shell = vim.o.shell
  vim.o.shell = "sh"
  local made, term = pcall(editor_and_terminal)
  vim.o.shell = shell
  expect(made, term)
  api.nvim_win_set_width(term, 60)
  local buf = api.nvim_win_get_buf(term)
  vim.fn.chansend(
    vim.b[buf].terminal_job_id,
    "clear; printf 'line %s: the quick brown fox jumps over the lazy dog and keeps running\\n' 1 2 3 4 5 6\n"
  )
  -- Only text already there can rewrap.
  local function shell_text()
    return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end
  for _ = 1, 300 do
    if shell_text():find "line 6: the quick brown fox" then
      break
    end
    wait(100)
  end
  expect(shell_text():find "line 6: the quick brown fox", "the shell printed nothing:\n" .. shell_text())
  local ok, err = pcall(function()
    screen(100)
    expect(vim.o.columns == 100, "the screen did not shrink: " .. vim.o.columns)
    local w = api.nvim_win_get_width(term)
    expect(math.abs(w - 30) <= 2, "after shrinking to 100 columns the terminal is " .. w .. " wide, not about 30")
    screen(200)
    w = api.nvim_win_get_width(term)
    expect(math.abs(w - 60) <= 1, "back at 200 columns the terminal is " .. w .. " wide, not 60")
    expect(math.abs(api.nvim_win_get_width(editor) - 139) <= 1, "editor " .. api.nvim_win_get_width(editor))
    -- The shell's text rewrapped with the pane, never one letter per line.
    local text = shell_text()
    expect(text:find "line 6: the quick brown fox", "the terminal text is mangled:\n" .. text)
  end)
  screen(200)
  expect(ok, err)
end)

check("Every Space key in the key hints has a name (OCaml, Python, Markdown, Org files too)", function()
  local missing = {}
  for _, file in ipairs { "a.ml", "a.mli", "hello.py", "README.md", "README.org" } do
    vim.cmd("edit " .. proj .. "/" .. file)
    wait(150)
    for _, mode in ipairs { "n", "x" } do
      local maps = vim.list_extend(api.nvim_get_keymap(mode), api.nvim_buf_get_keymap(0, mode))
      for _, m in ipairs(maps) do
        if m.lhs:sub(1, 1) == " " and #m.lhs > 1 and (m.desc or "") == "" then
          missing[#missing + 1] = file .. " " .. mode .. " <Space>" .. m.lhs:sub(2) .. " = " .. tostring(m.rhs)
        end
      end
    end
  end
  expect(#missing == 0, "no name: " .. table.concat(missing, ", "))
end)

check("A folder opened at start shows the tree at its full width, not a one-cell strip", function()
  vim.fn.mkdir(proj .. "/sub-start", "p")
  local editor = api.nvim_get_current_win()
  require("projects").open_folder(proj .. "/sub-start", { startup = true })
  wait(600)
  local tree = tree_win()
  expect(tree, "no tree")
  expect(api.nvim_win_get_width(tree) >= 25, "the tree is " .. api.nvim_win_get_width(tree) .. " cells wide")
  expect(api.nvim_get_current_win() == editor, "focus moved to the tree")
  vim.cmd("cd " .. proj)
end)

check("Alt/Cmd+O lists recent projects first, newest first, with their age; typing keeps them on top", function()
  local real = function(path)
    return vim.uv.fs_realpath(vim.fn.expand(path))
  end
  local sessions = vim.fn.stdpath "state" .. "/sessions"
  vim.fn.mkdir(sessions, "p")
  local function session(dir, age)
    local file = session_file(real(dir))
    vim.fn.writefile({ "" }, file)
    vim.uv.fs_utime(file, os.time() - age, os.time() - age)
  end
  for _, d in ipairs { "alphabet", "zeta-recent", "alpbet" } do
    vim.fn.mkdir(proj .. "/" .. d, "p")
  end
  session(proj .. "/alphabet", -60)
  session(proj .. "/zeta-recent", 7200)
  -- Never a project: home, and agents' scratch folders under ~/.cache.
  session("~", -120)
  local cache = vim.fn.glob("~/.cache/*/", false, true)[1]
  if cache then
    session(cache, -120)
  end
  press(super "o", 1500)
  expect(picker_active(), "no folder picker")
  local items = MiniPick.get_picker_items()
  local function path(item)
    return type(item) == "table" and item.path or tostring(item)
  end
  expect(path(items[1]) == real(proj .. "/alphabet"), "first row is " .. path(items[1]))
  local zeta
  for _, item in ipairs(items) do
    expect(path(item) ~= real "~", "home is listed")
    expect(not cache or path(item) ~= real(cache), "a ~/.cache folder is listed")
    if path(item) == real(proj .. "/zeta-recent") then
      zeta = item
    end
  end
  expect(type(zeta) == "table" and zeta.recent == "2h ago", "zeta-recent shows " .. vim.inspect(zeta))
  -- "alpbet" matches the plain folder alpbet better, but the recent
  -- alphabet stays on top.
  press("alpbet", 400)
  local first = MiniPick.get_picker_matches().all[1]
  expect(path(first) == real(proj .. "/alphabet"), "typing put " .. path(first) .. " on top")
  press("<Esc>", 200)
end)

-- ── Space key names, change keys, symbols, OCaml gt ──────────────────────

-- What mini.clue would show after Space, in this buffer and mode: keys with
-- no name, and groups (a prefix of 2+ keys) with no name.
local function unnamed_space_keys(mode)
  local missing, keys, groups = {}, {}, {}
  for _, src in ipairs { api.nvim_get_keymap(mode), api.nvim_buf_get_keymap(0, mode) } do
    for _, m in ipairs(src) do
      local k = vim.keycode(m.lhs)
      if k:sub(1, 1) == " " and #k > 1 then
        keys[k] = keys[k] or (m.desc or "")
      end
    end
  end
  local cfg = vim.list_extend(vim.deepcopy(MiniClue.config.clues), (vim.b.miniclue_config or {}).clues or {})
  for _, c in ipairs(cfg) do
    local modes = type(c.mode) == "table" and c.mode or { c.mode }
    if c.keys and vim.tbl_contains(modes, mode) then
      local d = type(c.desc) == "function" and c.desc() or c.desc
      groups[vim.keycode(c.keys)] = d
    end
  end
  for k, d in pairs(keys) do
    if d == "" then
      missing[#missing + 1] = mode .. " key" .. k:gsub(" ", "SPC ")
    end
    for i = 2, #k - 1 do
      if not keys[k:sub(1, i)] and not groups[k:sub(1, i)] then
        missing[#missing + 1] = mode .. " group" .. k:sub(1, i):gsub(" ", "SPC ")
      end
    end
  end
  return missing, groups
end

check("Every Space key and Space group has a name (OCaml, org, Python; normal and selection)", function()
  local missing = {}
  for _, f in ipairs { "a.ml", "a.mli", "README.org", "hello.py", "a.ml" } do
    vim.cmd("edit! " .. f)
    wait(f == "README.org" and 600 or 150)
    for _, mode in ipairs { "n", "x" } do
      for _, m in ipairs((unnamed_space_keys(mode))) do
        missing[#missing + 1] = f .. " " .. m
      end
    end
  end
  table.sort(missing)
  expect(#missing == 0, "unnamed: " .. table.concat(vim.fn.uniq(missing), ", "))
  vim.cmd "edit! a.ml"
  local _, groups = unnamed_space_keys "n"
  expect(groups[" o"] == "+OCaml", "Space o in OCaml is " .. tostring(groups[" o"]))
  vim.cmd "edit! README.org"
  _, groups = unnamed_space_keys "n"
  expect(groups[" o"] == "+Org", "Space o in org is " .. tostring(groups[" o"]))
  expect(groups[" g"] == "+Git changes", "no +Git changes group")
end)

check("Change keys: Alt+F5 jumps to the next change, Space g s stages it, Space g r undoes one", function()
  local function git(...)
    return vim.system(vim.list_extend({ "git", "-C", proj }, { ... })):wait()
  end
  local f = proj .. "/hunk.ml"
  vim.fn.writefile({ "let a = 1", "let b = 2", "let c = 3", "let d = 4", "let e = 5", "let f = 6" }, f)
  git("add", "hunk.ml")
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "hunk base")
  vim.cmd("edit! " .. f)
  api.nvim_buf_set_lines(0, 1, 2, false, { "let b = 20" })
  api.nvim_buf_set_lines(0, 4, 5, false, { "let e = 50" })
  vim.cmd "silent write"
  for _ = 1, 20 do
    wait(150)
    local d = MiniDiff.get_buf_data(0)
    if d and #d.hunks == 2 then
      break
    end
  end
  vim.fn.cursor(1, 1)
  press("<M-F5>", 200)
  expect(vim.fn.line "." == 2, "Alt+F5 went to line " .. vim.fn.line ".")
  -- Each jump says which change it is and what it did, in the bottom line.
  local said = table.concat(api.nvim_buf_get_lines(require("vim._core.ui2").bufs.cmd, 0, -1, false), " ")
  expect(said:find "Change 1 of 2: 1 line changed", "the bottom line said '" .. said .. "'")
  press("i", 50)
  press("<M-F5>", 200)
  expect(vim.fn.line "." == 5, "Alt+F5 from Insert went to line " .. vim.fn.line ".")
  press("<Esc>", 50)
  press("<M-S-F5>", 200)
  expect(vim.fn.line "." == 2, "Alt+Shift+F5 went to line " .. vim.fn.line ".")
  press(" gs", 400)
  local staged = git("diff", "--cached", "--", "hunk.ml").stdout or ""
  expect(staged:find "let b = 20" and not staged:find "let e = 50", "staged: " .. staged)
  vim.fn.cursor(5, 1)
  press(" gr", 300)
  expect(vim.fn.getline(5) == "let e = 5", "Space g r left line 5 as " .. vim.fn.getline(5))
  press(" gp", 200)
  expect(MiniDiff.get_buf_data(0).overlay == true, "Space g p showed no old lines")
  press(" gp", 200)
  vim.cmd "silent! write"
  git("reset", "-q")
  vim.cmd "bwipeout!"
  vim.fn.delete(f)
end)

check("Space f s lists the project's symbols from ocamllsp", function()
  vim.system({ "dune", "build", "@check" }, { cwd = proj }):wait(60000)
  vim.cmd "edit! b.ml"
  local buf = api.nvim_get_current_buf()
  wait_for_lsp(buf)
  wait(800)
  vim.cmd "edit! a.ml"
  wait(300)
  press(" fs", 300)
  local items = {}
  for _ = 1, 30 do
    wait(200)
    items = picker_active() and MiniPick.get_picker_items() or {}
    if #items > 0 then
      break
    end
  end
  local text = table.concat(
    vim.tbl_map(function(i)
      return type(i) == "table" and (i.text or "") or tostring(i)
    end, items),
    "\n"
  )
  press("<Esc>", 200)
  expect(text:find "helper" and text:find "greeting", "symbols listed: " .. text:sub(1, 200))
end)

check("OCaml gt wraps a motion, a selection or a line in (fun () -> ...)", function()
  vim.cmd "edit! c.ml"
  api.nvim_buf_set_lines(0, 0, -1, false, { "let x = foo bar", "  let y = é 1", "let z = 3" })
  vim.fn.cursor(1, 9)
  press("gt$", 150)
  expect(vim.fn.getline(1) == "let x = (fun () -> foo bar)", "gt$ made: " .. vim.fn.getline(1))
  vim.fn.cursor(2, 11)
  press("vgt", 150)
  expect(vim.fn.getline(2) == "  let y = (fun () -> é) 1", "v gt made: " .. vim.fn.getline(2))
  vim.fn.cursor(3, 1)
  press("gtt", 150)
  expect(vim.fn.getline(3) == "(fun () -> let z = 3)", "gtt made: " .. vim.fn.getline(3))
  vim.cmd "edit! hello.py"
  expect(vim.fn.maparg("gt", "n", false, true).buffer ~= 1, "gt is mapped outside OCaml")
  vim.cmd "edit! c.ml"
  vim.cmd "silent! undo 0"
  vim.cmd "edit! c.ml"
end)

-- ── The test tools themselves ────────────────────────────────────────────

local tests_dir = vim.fn.stdpath "config" .. "/tests"

-- Run a tests/ script against a scratch folder that does not exist yet, with
-- stand-ins for tmux (logs its arguments, runs the command of a new session)
-- and nvim (logs TEST_ONLY, ends the run). Returns its output and the log.
local function run_tool(script, env)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/bin", "p")
  local function stand_in(name, body)
    local file = dir .. "/bin/" .. name
    vim.fn.writefile({ "#!/bin/sh", body }, file)
    vim.fn.setfperm(file, "rwxr-xr-x")
  end
  stand_in("tmux", [[echo "tmux $*" >>"$FAKE_LOG"; case "$*" in *new-session*) for c; do :; done; sh -c "$c" ;; esac]])
  stand_in("nvim", [[echo "nvim TEST_ONLY=$TEST_ONLY" >>"$FAKE_LOG"; echo DONE >>"$NVNEXT/results.txt"]])
  local log_file = dir .. "/log"
  local full_env = vim.tbl_extend("force", {
    NVNEXT = dir .. "/world",
    TMUX_SOCK = "tool-check",
    FAKE_LOG = log_file,
    PATH = dir .. "/bin:" .. vim.env.PATH,
  }, env or {})
  local result = vim.system(script, { cwd = dir, env = full_env, text = true }):wait(30000)
  local logged = vim.uv.fs_stat(log_file) and table.concat(vim.fn.readfile(log_file), "\n") or ""
  return result.stdout or "", logged
end

check("Test tools: check.sh passes TEST_ONLY as typed, a quote in it too", function()
  local name = "A project's session"
  local out, logged = run_tool({ tests_dir .. "/check.sh" }, { TEST_ONLY = name })
  expect(logged:find("nvim TEST_ONLY=" .. name, 1, true), "nvim got: " .. logged .. "\ncheck.sh said: " .. out)
end)

check("Test tools: live.sh starts when the scratch folder is new", function()
  local _, logged = run_tool { tests_dir .. "/live.sh" }
  expect(logged:find("nvim TEST_ONLY", 1, true), "nvim never started: " .. logged)
end)

check("Test tools: capture/all.sh starts when the output folder is new", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.uv.fs_copyfile(tests_dir .. "/capture/all.sh", dir .. "/all.sh")
  vim.fn.setfperm(dir .. "/all.sh", "rwxr-xr-x")
  vim.fn.writefile({ "#!/bin/sh", 'mkdir -p "$2"; touch "$2/shot.png"' }, dir .. "/shoot.sh")
  vim.fn.setfperm(dir .. "/shoot.sh", "rwxr-xr-x")
  local out = run_tool({ dir .. "/all.sh", dir .. "/new/out" }, { ONLY = "new" })
  expect(out:find("new-glass: 1 shots", 1, true) and out:find("new-flat: 1 shots", 1, true), "all.sh said: " .. out)
end)

check("Test tools: open-time.sh uses the run's own tmux socket", function()
  local _, logged = run_tool(
    { tests_dir .. "/open-time.sh", "a.ml" },
    { N = "1", SETTLE = "0", TMUX_SOCK = "my-own-socket" }
  )
  expect(
    logged:find("tmux -L my-own-socket", 1, true) and not logged:find("nvnext-time", 1, true),
    "tmux got: " .. logged
  )
end)

check("Test tools: captures never reach the real WakaTime", function()
  local shoot = table.concat(vim.fn.readfile(tests_dir .. "/capture/shoot.sh"), "\n")
  expect(shoot:find("WAKATIME_HOME=$S/wakatime", 1, true), "shoot.sh leaves WAKATIME_HOME unset")
end)

check("Test tools: old-copy.sh makes the old config, without its WakaTime plugin", function()
  local result = vim.system({ tests_dir .. "/old-copy.sh" }, { text = true }):wait(30000)
  local made = vim.uv.fs_stat "/tmp/nvold/cfg/nvim/init.lua" ~= nil
  local waka = vim.uv.fs_stat "/tmp/nvold/cfg/nvim/lua/plugins/wakatime.lua" ~= nil
  vim.fn.delete("/tmp/nvold", "rf")
  expect(made, "no copy made: " .. (result.stderr or ""))
  expect(not waka, "the copy still has its WakaTime plugin")
end)

-- ── Runner ────────────────────────────────────────────────────────────────

co = coroutine.create(function()
  wait(800)
  -- Tests yank and paste: never let that reach the desktop's clipboard.
  if not (vim.g.clipboard and vim.g.clipboard.name == "test-memory") or vim.env.WAYLAND_DISPLAY then
    log "FAIL runner: the private test clipboard is not active; stopping"
    log "DONE"
    vim.cmd "qa!"
    return
  end
  for _, c in ipairs(checks) do
    if not only or c.name:find(only, 1, true) then
      local ok_reset, reset_err = pcall(reset)
      local ok, err = pcall(c.fn)
      if not ok_reset then
        log("FAIL " .. c.name .. ": reset failed: " .. tostring(reset_err))
      elseif ok then
        log("PASS " .. c.name)
      elseif tostring(err):find "^SKIP" then
        log("SKIP " .. c.name .. ": " .. tostring(err))
      else
        log("FAIL " .. c.name .. ": " .. tostring(err))
      end
    end
  end
  log "DONE"
  vim.cmd "qa!"
end)
coroutine.resume(co)
