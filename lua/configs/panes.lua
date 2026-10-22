-- Omarchy-style pane keys: a Neovim pane behaves like a Hyprland window.
-- The file tree is a pane you can focus but never swap, zoom into or flip.
local M = {}

local api = vim.api

-- Character cells are about twice as tall as they are wide, so compare a
-- pane's sides in screen pixels, not cells, when picking its longer side.
local CELL_ASPECT = 2

local function is_tree(win)
  return vim.bo[api.nvim_win_get_buf(win)].filetype == "NvimTree"
end

local function is_float(win)
  return api.nvim_win_get_config(win).relative ~= ""
end

local function is_pane(win)
  return api.nvim_win_is_valid(win) and not is_float(win) and not is_tree(win)
end

-- A terminal you land in goes straight to typing, like a Hyprland window.
local function type_if_terminal()
  if vim.bo.buftype == "terminal" then
    vim.cmd "startinsert"
  end
end

---Focus the pane in `dir` (h/j/k/l), tree included.
function M.focus(dir)
  vim.cmd.wincmd(dir)
end

---Run a pane action from a key. The key has already left insert, a
---selection or a terminal; a terminal that has focus afterwards (the one
---you landed in or the one you stayed in) goes back to typing.
function M.run(name, arg)
  M[name](arg)
  type_if_terminal()
end

---Swap the current pane's buffer with its neighbour in `dir` (h/j/k/l).
---Windows, sizes and layout stay; the buffer moves and focus follows it.
function M.swap(dir)
  local cur = api.nvim_get_current_win()
  local target = vim.fn.win_getid(vim.fn.winnr(dir))
  if target == cur or not is_pane(cur) or not is_pane(target) then
    return
  end
  local buf_cur, buf_target = api.nvim_win_get_buf(cur), api.nvim_win_get_buf(target)
  local view_cur = api.nvim_win_call(cur, vim.fn.winsaveview)
  local view_target = api.nvim_win_call(target, vim.fn.winsaveview)
  -- Each window loads its new buffer as if entered by keyboard, so the
  -- terminal/editor background autocmds repaint it without forcing input.
  vim.g.nvim_keyboard_buffer_switch = true
  local ok, err = pcall(function()
    api.nvim_win_call(target, function()
      vim.cmd.buffer(buf_cur)
      vim.fn.winrestview(view_cur)
    end)
    api.nvim_win_call(cur, function()
      vim.cmd.buffer(buf_target)
      vim.fn.winrestview(view_target)
    end)
    api.nvim_set_current_win(target)
  end)
  vim.g.nvim_keyboard_buffer_switch = false
  if not ok then
    error(err)
  end
end

---Open a terminal beside the current pane, split along its longer side
---(wide: to the right; tall: below), like Hyprland's dwindle layout.
function M.new_terminal()
  local win = api.nvim_get_current_win()
  if is_tree(win) or is_float(win) then
    vim.cmd "wincmd l"
    win = api.nvim_get_current_win()
    if not is_pane(win) then
      return
    end
  end
  local wide = api.nvim_win_get_width(win) > CELL_ASPECT * api.nvim_win_get_height(win)
  vim.cmd((wide and "belowright vsplit" or "belowright split") .. " | terminal")
end

---Zoom the current pane: it alone fills the screen, without the tree. The
---same key brings the exact layout back. The zoom is a throwaway tab page,
---so the real layout is never touched and its terminals keep running.
function M.toggle_zoom()
  local origin = vim.t.pane_zoom_origin
  if origin then
    local buf = api.nvim_get_current_buf()
    local view = vim.fn.winsaveview()
    vim.cmd "tabclose"
    if api.nvim_win_is_valid(origin) then
      api.nvim_set_current_win(origin)
    end
    if api.nvim_get_current_buf() ~= buf then
      vim.g.nvim_keyboard_buffer_switch = true
      pcall(vim.cmd.buffer, buf)
      vim.g.nvim_keyboard_buffer_switch = false
    end
    vim.fn.winrestview(view)
    return
  end
  local win = api.nvim_get_current_win()
  local others = vim.tbl_filter(function(w)
    return w ~= win and not is_float(w)
  end, api.nvim_tabpage_list_wins(0))
  if not is_pane(win) or #others == 0 then
    return
  end
  vim.g.nvim_keyboard_buffer_switch = true
  vim.cmd "tab split"
  vim.g.nvim_keyboard_buffer_switch = false
  vim.t.pane_zoom_origin = win
end

-- The layout node (row/col) that directly holds `win`, and its index there.
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

---Flip the current pane and its neighbour between side-by-side and stacked,
---like Hyprland's togglesplit. The tree stays where it is.
function M.flip()
  local cur = api.nvim_get_current_win()
  if not is_pane(cur) then
    return
  end
  local parent, index = parent_of(cur, vim.fn.winlayout())
  if not parent then
    return
  end
  local siblings = parent[2]
  -- Prefer the next pane, else the previous one; never the tree.
  local neighbour, after
  for _, candidate in ipairs { { index + 1, false }, { index - 1, true } } do
    local node = siblings[candidate[1]]
    if node and is_pane(first_leaf(node)) then
      neighbour, after = first_leaf(node), candidate[2]
      break
    end
  end
  if not neighbour then
    return
  end
  local side_by_side = parent[1] == "row"
  local tree = vim.tbl_filter(is_tree, api.nvim_tabpage_list_wins(0))[1]
  local tree_width = tree and api.nvim_win_get_width(tree)
  local width = side_by_side and api.nvim_win_get_width(cur) + api.nvim_win_get_width(neighbour) + 1
    or api.nvim_win_get_width(cur)
  local height = side_by_side and api.nvim_win_get_height(cur)
    or api.nvim_win_get_height(cur) + api.nvim_win_get_height(neighbour) + 1
  local split
  if side_by_side then
    split = after and "below" or "above"
  else
    split = after and "right" or "left"
  end
  api.nvim_win_set_config(cur, { win = neighbour, split = split })
  -- Keep the pair's outer box: same total size, shared evenly.
  if side_by_side then
    api.nvim_win_set_width(cur, width)
    api.nvim_win_set_height(cur, math.floor((height - 1) / 2))
  else
    api.nvim_win_set_height(cur, height)
    api.nvim_win_set_width(cur, math.floor((width - 1) / 2))
  end
  if tree and api.nvim_win_is_valid(tree) then
    api.nvim_win_set_width(tree, tree_width)
  end
  api.nvim_set_current_win(cur)
end

return M
