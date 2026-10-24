-- Panes behave like Hyprland windows: the same keys focus, swap, zoom, flip,
-- resize and close them, from any mode. Three kinds of pane:
--   editor    a file (buftype ""), shows tabs
--   terminal  a shell or a TUI
--   tree      the file tree; it can be focused and closed, never swapped,
--             zoomed or flipped
-- Floats (finder, hover, completion docs) are not panes.
local M = {}

local api = vim.api

-- Cells are about twice as tall as wide: compare sides in pixels, not cells.
local CELL_ASPECT = 2

function M.is_float(win)
  return api.nvim_win_get_config(win).relative ~= ""
end

function M.is_tree(win)
  return vim.bo[api.nvim_win_get_buf(win)].filetype == "NvimTree"
end

function M.is_terminal(win)
  return vim.bo[api.nvim_win_get_buf(win)].buftype == "terminal"
end

function M.is_editor(win)
  return api.nvim_win_is_valid(win) and not M.is_float(win) and vim.bo[api.nvim_win_get_buf(win)].buftype == ""
end

local function is_pane(win)
  return api.nvim_win_is_valid(win) and not M.is_float(win) and not M.is_tree(win)
end

local function panes()
  return vim.tbl_filter(function(w)
    return not M.is_float(w)
  end, api.nvim_tabpage_list_wins(0))
end

-- The editor pane used last: where the tree opens files and where tab keys
-- act when a terminal or the tree has focus.
local last_editor
function M.last_editor()
  if last_editor and api.nvim_win_is_valid(last_editor) and M.is_editor(last_editor) then
    if api.nvim_win_get_tabpage(last_editor) == api.nvim_get_current_tabpage() then
      return last_editor
    end
  end
  for _, win in ipairs(panes()) do
    if M.is_editor(win) then
      return win
    end
  end
end

---The editor pane a file opens in: the focused one, else the one used last,
---else a new one. A new one takes half of the widest pane (never room from
---the tree); with only the tree, the rest of the row. Focus moves to it.
---The tree, the finder, reopen and the tab keys all open files here.
function M.editor()
  local win = api.nvim_get_current_win()
  if M.is_editor(win) then
    return win
  end
  win = M.last_editor()
  if not win then
    M.leave_zoom()
    win = M.last_editor()
  end
  if not win then
    local sizes = M.snapshot()
    local widest
    for _, w in ipairs(panes()) do
      if not M.is_tree(w) and (not widest or api.nvim_win_get_width(w) > api.nvim_win_get_width(widest)) then
        widest = w
      end
    end
    if widest then
      api.nvim_set_current_win(widest)
      vim.cmd "leftabove vnew"
      sizes[widest] = nil
    else
      vim.cmd "rightbelow vnew"
    end
    win = api.nvim_get_current_win()
    M.restore(sizes)
  end
  api.nvim_set_current_win(win)
  return win
end

-- A terminal you land in is ready to type into, like a Hyprland window.
local function type_if_terminal()
  if vim.bo.buftype == "terminal" then
    vim.cmd "startinsert"
  end
end

---Run a pane action from a key. Keys first leave insert, a selection or a
---terminal (keys.lua from_any_mode), so every action starts in Normal mode.
function M.run(name, arg)
  M[name](arg)
  type_if_terminal()
end

function M.focus(dir)
  vim.cmd.wincmd(dir)
end

---Swap this pane's content with its neighbour in `dir`; sizes stay, focus
---follows the content.
function M.swap(dir)
  local cur = api.nvim_get_current_win()
  local target = vim.fn.win_getid(vim.fn.winnr(dir))
  if target == cur or not is_pane(cur) or not is_pane(target) then
    return
  end
  local buf_cur, buf_target = api.nvim_win_get_buf(cur), api.nvim_win_get_buf(target)
  local view_cur = api.nvim_win_call(cur, vim.fn.winsaveview)
  local view_target = api.nvim_win_call(target, vim.fn.winsaveview)
  api.nvim_win_set_buf(target, buf_cur)
  api.nvim_win_set_buf(cur, buf_target)
  api.nvim_win_call(target, function()
    vim.fn.winrestview(view_cur)
  end)
  api.nvim_win_call(cur, function()
    vim.fn.winrestview(view_target)
  end)
  api.nvim_set_current_win(target)
end

---Leave a zoom before opening a pane. The zoom is a throwaway tab: a pane
---opened in it would vanish on unzoom, its job still running out of reach.
function M.leave_zoom()
  if M.zoomed() then
    M.zoom()
  end
end

---Is this tab a zoom? A zoom tab left on its own (:tabonly, the other tabs
---closed) has no layout to go back to: it is a plain tab again.
function M.zoomed()
  if vim.t.zoom_origin and #api.nvim_list_tabpages() == 1 then
    vim.t.zoom_origin, vim.t.zoom_win = nil, nil
  end
  return vim.t.zoom_origin ~= nil
end

---Open a terminal beside the focused pane, on its longer side.
function M.new_terminal()
  M.leave_zoom()
  local win = api.nvim_get_current_win()
  if not is_pane(win) then
    win = M.last_editor() or win
    api.nvim_set_current_win(win)
  end
  local wide = api.nvim_win_get_width(win) > CELL_ASPECT * api.nvim_win_get_height(win)
  vim.cmd(wide and "rightbelow vsplit" or "rightbelow split")
  vim.cmd.terminal()
end

-- ── The bottom panel (Ctrl+`, VS Code's terminal panel) ───────────────────
-- One shell, shown full width under every pane. Hiding it keeps the shell
-- running; the next Ctrl+` shows the same one at the height it had.
local panel = { buf = nil, height = nil, sizes = nil, back = nil }

local function panel_alive()
  local buf = panel.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return false
  end
  local job = vim.b[buf].terminal_job_id
  return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
end

---The panel's window in this tab, if it shows.
function M.panel_win()
  for _, win in ipairs(panes()) do
    if vim.w[win].panel and api.nvim_win_get_buf(win) == panel.buf then
      return win
    end
  end
end

---Ctrl+`: show the panel and focus it; focused already, hide it.
---Shown but not focused, focus it (as VS Code does).
function M.toggle_panel()
  M.leave_zoom()
  local win = M.panel_win()
  if win and win == api.nvim_get_current_win() then
    panel.height = api.nvim_win_get_height(win)
    local back = panel.back
    if #panes() > 1 then
      api.nvim_win_close(win, false)
    end
    -- The rows go back to the panes they came from.
    if panel.sizes then
      M.restore(panel.sizes)
    end
    if back and api.nvim_win_is_valid(back) and api.nvim_win_get_tabpage(back) == api.nvim_get_current_tabpage() then
      api.nvim_set_current_win(back)
    end
    return
  end
  if win then
    return api.nvim_set_current_win(win)
  end
  panel.back = api.nvim_get_current_win()
  panel.sizes = M.snapshot()
  local height = panel.height or math.max(8, math.floor(vim.o.lines * 0.3))
  vim.cmd(("botright %dsplit"):format(height))
  if panel_alive() then
    api.nvim_win_set_buf(0, panel.buf)
  else
    vim.cmd.terminal()
    panel.buf = api.nvim_get_current_buf()
  end
  vim.w.panel = true
  -- [0][0] is :setlocal (as for any terminal, see TermOpen below).
  local wo = vim.wo[0][0]
  wo.number, wo.relativenumber, wo.signcolumn, wo.scrolloff = false, false, "no", 0
end

---Zoom: the pane alone fills the window; the same key brings the layout
---back exactly. The zoom is a throwaway tab page, so nothing is resized.
function M.zoom()
  local origin = M.zoomed() and vim.t.zoom_origin
  if origin then
    -- What the zoomed pane shows now (it may have switched tabs), even if
    -- focus is in another pane opened while zoomed.
    local zoomed = vim.t.zoom_win
    zoomed = zoomed and api.nvim_win_is_valid(zoomed) and zoomed or api.nvim_get_current_win()
    local buf = api.nvim_win_get_buf(zoomed)
    local view = api.nvim_win_call(zoomed, vim.fn.winsaveview)
    vim.cmd "tabclose"
    if api.nvim_win_is_valid(origin) then
      api.nvim_set_current_win(origin)
      local same = api.nvim_get_current_buf() == buf
      if not same and M.is_editor(origin) and vim.bo[buf].buftype == "" and api.nvim_buf_is_valid(buf) then
        api.nvim_win_set_buf(origin, buf)
        same = true
      end
      if same then
        vim.fn.winrestview(view)
      end
    end
    return
  end
  local win = api.nvim_get_current_win()
  if not is_pane(win) or #panes() < 2 then
    return
  end
  vim.cmd "tab split"
  vim.t.zoom_origin = win
  vim.t.zoom_win = api.nvim_get_current_win()
end

local function parent_of(win, node)
  if node[1] == "leaf" then
    return nil
  end
  for i, child in ipairs(node[2]) do
    if child[1] == "leaf" and child[2] == win then
      return node, i
    end
    local parent, index = parent_of(win, child)
    if parent then
      return parent, index
    end
  end
end

local function first_leaf(node)
  while node[1] ~= "leaf" do
    node = node[2][1]
  end
  return node[2]
end

---Flip this pane and its neighbour between side by side and stacked, like
---Hyprland's togglesplit. Their outer box keeps its size.
function M.flip()
  local cur = api.nvim_get_current_win()
  if not is_pane(cur) then
    return
  end
  local parent, index = parent_of(cur, vim.fn.winlayout())
  if not parent then
    return
  end
  local neighbour, after
  for _, candidate in ipairs { { index + 1, false }, { index - 1, true } } do
    local node = parent[2][candidate[1]]
    if node and is_pane(first_leaf(node)) then
      neighbour, after = first_leaf(node), candidate[2]
      break
    end
  end
  if not neighbour then
    return
  end
  local side_by_side = parent[1] == "row"
  local sizes = M.snapshot()
  local width = side_by_side and api.nvim_win_get_width(cur) + api.nvim_win_get_width(neighbour) + 1
    or api.nvim_win_get_width(cur)
  local height = side_by_side and api.nvim_win_get_height(cur)
    or api.nvim_win_get_height(cur) + api.nvim_win_get_height(neighbour) + 1
  local split = side_by_side and (after and "below" or "above") or (after and "right" or "left")
  api.nvim_win_set_config(cur, { win = neighbour, split = split })
  if side_by_side then
    api.nvim_win_set_width(cur, width)
    api.nvim_win_set_height(cur, math.floor((height - 1) / 2))
  else
    api.nvim_win_set_height(cur, height)
    api.nvim_win_set_width(cur, math.floor((width - 1) / 2))
  end
  sizes[cur], sizes[neighbour] = nil, nil
  M.restore(sizes)
  api.nvim_set_current_win(cur)
end

---Move a divider toward the arrow: the pane's right (lower) divider when it
---has one, else its left (upper) one. Ctrl+Left on a right-hand terminal
---widens it; on a left-hand editor it narrows it.
function M.move_divider(arrow)
  local win = api.nvim_get_current_win()
  if M.is_float(win) then
    return
  end
  local sideways = arrow == "Left" or arrow == "Right"
  local has_far = vim.fn.winnr(sideways and "l" or "j") ~= vim.fn.winnr()
  local toward_far = arrow == "Right" or arrow == "Down"
  local step = 2 * vim.v.count1 * ((has_far == toward_far) and 1 or -1)
  if sideways then
    api.nvim_win_set_width(win, api.nvim_win_get_width(win) + step)
  else
    api.nvim_win_set_height(win, api.nvim_win_get_height(win) + step)
  end
end

-- ── Sizes stay put ─────────────────────────────────────────────────────────

---Every pane's size, by window id.
function M.snapshot()
  local sizes = {}
  for _, win in ipairs(panes()) do
    sizes[win] = { api.nvim_win_get_width(win), api.nvim_win_get_height(win) }
  end
  return sizes
end

---Put panes back to their snapshot sizes (closed ones are skipped).
function M.restore(sizes)
  for _ = 1, 2 do
    for win, size in pairs(sizes) do
      if api.nvim_win_is_valid(win) then
        api.nvim_win_set_width(win, size[1])
        api.nvim_win_set_height(win, size[2])
      end
    end
  end
end

-- ── Close (Alt/Cmd+W): whatever has focus ─────────────────────────────────

local closed = {} -- recently closed files, newest last

-- Show another tab in every pane that shows `buf`, so deleting it never
-- closes a pane by accident. Like Chrome: the tab to its right, else the
-- one to its left.
local function replace_everywhere(buf)
  local list = require("tabs").list()
  local i = require("tabs").index(buf)
  local next_buf = i and (list[i + 1] or list[i - 1])
  if next_buf == buf then
    next_buf = nil
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      if next_buf then
        api.nvim_win_set_buf(win, next_buf)
      else
        api.nvim_win_call(win, function()
          vim.cmd "enew"
        end)
      end
    end
  end
end

local function close_pane(win)
  local editors = vim.tbl_filter(M.is_editor, panes())
  if #panes() > 1 then
    api.nvim_win_close(win, true)
  elseif #editors == 0 then
    api.nvim_win_call(win, function()
      vim.cmd "enew"
    end)
  end
end

---Note a tab being closed, for reopen: its file, cursor and place in the bar.
function M.remember_closed(buf, cursor)
  local name = api.nvim_buf_get_name(buf)
  if name ~= "" then
    cursor = cursor or api.nvim_buf_get_mark(buf, '"')
    table.insert(closed, { name = name, cursor = cursor, index = require("tabs").index(buf) })
  end
end

---Close the tab (file) in an editor; close a terminal, the tree, a float or a
---help/list pane outright.
function M.close()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  if M.is_float(win) then
    return api.nvim_win_close(win, true)
  end
  if M.is_tree(win) then
    return require("nvim-tree.api").tree.close()
  end
  local buftype = vim.bo[buf].buftype
  if buftype == "terminal" then
    close_pane(win)
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_delete(buf, { force = true })
    end
    return
  end
  if buftype ~= "" then
    return close_pane(win)
  end
  if vim.bo[buf].modified then
    local choice = vim.fn.confirm("Save changes to " .. vim.fn.expand "%:t" .. "?", "&Save\n&Discard\n&Cancel", 3)
    if choice == 1 then
      if api.nvim_buf_get_name(buf) == "" then
        local file = vim.fn.input("Save as: ", vim.fn.getcwd() .. "/", "file")
        if file == "" or not pcall(vim.cmd.write, vim.fn.fnameescape(file)) then
          return
        end
      else
        vim.cmd.write()
      end
    elseif choice ~= 2 then
      return
    end
  end
  M.remember_closed(buf, api.nvim_win_get_cursor(win))
  -- A split beside another editor closes with its tab; the last editor
  -- pane stays and shows the next tab.
  local editors = vim.tbl_filter(M.is_editor, panes())
  if #editors > 1 then
    api.nvim_win_close(win, true)
    -- The same file still open in another split: that split keeps it.
    if #vim.fn.win_findbuf(buf) > 0 then
      return
    end
  end
  if api.nvim_buf_is_valid(buf) then
    replace_everywhere(buf)
    api.nvim_buf_delete(buf, { force = true })
  end
end

---Reopen the last closed tab (Alt/Cmd+Shift+T).
function M.reopen()
  local entry = table.remove(closed)
  if not entry then
    return
  end
  M.editor()
  vim.cmd.edit(vim.fn.fnameescape(entry.name))
  pcall(api.nvim_win_set_cursor, 0, entry.cursor)
  -- Back in its old place in the tab bar (Chrome).
  if entry.index then
    require("tabs").place(api.nvim_get_current_buf(), entry.index)
  end
end

---Run a tab command (next, previous, go to N) in the editor pane, wherever
---focus is.
function M.in_editor(fn)
  M.editor()
  fn()
end

function M.setup()
  local group = api.nvim_create_augroup("Panes", { clear = true })
  -- A terminal is a pane, not a tab: it stays out of the tab bar and Ctrl+Tab,
  -- and opens ready to type.
  api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(args)
      vim.bo[args.buf].buflisted = false
      -- [0][0] is :setlocal: a file opened later in this window keeps its
      -- numbers and signs.
      local wo = vim.wo[0][0]
      wo.number, wo.relativenumber, wo.signcolumn = false, false, "no"
      -- Scrollback stays scrollable to its last line in a short split.
      wo.scrolloff = 0
      -- Only if focus is still here when the key that opened it is done (F5
      -- opens a terminal, then goes back to the file).
      vim.schedule(function()
        if api.nvim_get_current_buf() == args.buf then
          vim.cmd "startinsert"
        end
      end)
      -- A click in a terminal is a click in the shell.
      vim.keymap.set("n", "<LeftMouse>", "<LeftMouse><Cmd>if &buftype ==# 'terminal' | startinsert | endif<CR>", {
        buffer = args.buf,
        desc = "Terminal: click to type",
      })
    end,
  })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      if M.is_editor(win) then
        last_editor = win
      end
    end,
  })
end

return M
