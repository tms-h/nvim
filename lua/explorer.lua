-- The file tree (nvim-tree), laid out like the old config's: a two-cell
-- gutter, folder arrows and git marks before each name, and a clickable
-- "Sort" row on top (Name gn, Added ga; gs picks any sort, also Edited). Its first line is the open
-- folder's name. Files open in the editor pane used last, never in a
-- terminal and never with a "which window?" prompt. Only the keys below do
-- anything; any other key is plain Vim on a read-only list (at most one
-- short line).
local M = {}

local api = vim.api

-- ── Sort ─────────────────────────────────────────────────────────────────
-- name: folders first, A-Z (nvim-tree's own). added / modified: folders
-- first, newest first (file birth time / modification time), then A-Z.
M.sort = "name"

local SORTS = {
  { mode = "name", label = "Name (A-Z)" },
  { mode = "added", label = "Recently added" },
  { mode = "modified", label = "Recently modified" },
}

---nvim-tree's sorter: a string picks a built-in one, else sort in place.
function M.sorter(nodes)
  if M.sort == "name" then
    return "name"
  end
  local field = M.sort == "added" and "birthtime" or "mtime"
  local meta = {}
  for _, node in ipairs(nodes) do
    local stat = vim.uv.fs_stat(node.absolute_path)
    meta[node] = {
      dir = stat ~= nil and stat.type == "directory",
      time = stat and stat[field] and stat[field].sec or 0,
    }
  end
  table.sort(nodes, function(a, b)
    local x, y = meta[a], meta[b]
    if x.dir ~= y.dir then
      return x.dir
    end
    if x.time ~= y.time then
      return x.time > y.time
    end
    return a.name:lower() < b.name:lower()
  end)
end

---Sort the tree by `mode` ("name", "added" or "modified").
function M.set_sort(mode)
  M.sort = mode
  local tree = require "nvim-tree.api"
  if tree.tree.is_visible() then
    tree.tree.reload()
  end
  vim.cmd.redrawstatus { bang = true }
end

---gs: pick any sort, the current one marked.
function M.choose_sort()
  vim.ui.select(SORTS, {
    prompt = "Sort the tree by",
    format_item = function(item)
      return item.label .. (item.mode == M.sort and "  (now)" or "")
    end,
  }, function(choice)
    if choice then
      M.set_sort(choice.mode)
    end
  end)
end

local function button(id, label, active)
  return ("%%#%s#%%%d@v:lua.ExplorerSortClick@ %s %%T"):format(
    active and "ExplorerSortActive" or "ExplorerSortButton",
    id,
    label
  )
end

---The tree's winbar, as in the old config: " Sort  Name (gn)  Added (ga)",
---29 cells so it fits the 30-cell tree. Sorted by modification time (gs),
---the second button reads "Edited (gs)". Clicking Added or Edited sorts.
function M.winbar()
  local edited = M.sort == "modified"
  return table.concat {
    -- With the "title" focus cue (focus.lua), "Sort" is the tree's title:
    -- accent while the tree has focus, muted otherwise.
    (require("focus").cue() == "title" and "%#FocusTitle#" or "%#ExplorerSortTitle#") .. " Sort",
    button(1, "Name (gn)", M.sort == "name"),
    edited and button(3, "Edited (gs)", true) or button(2, "Added (ga)", M.sort == "added"),
    "%#ExplorerSortTitle#",
  }
end

-- selene: allow(global_usage)
_G.ExplorerSortClick = function(id, _, mouse)
  if mouse ~= "l" then
    return
  end
  if id == 1 then
    M.set_sort "name"
  elseif id == 2 then
    M.set_sort "added"
  else
    vim.schedule(M.choose_sort)
  end
end

local WINBAR = "%!v:lua.require'explorer'.winbar()"

local function set_winbar()
  for _, win in ipairs(api.nvim_list_wins()) do
    if require("panes").is_tree(win) and vim.wo[win].winbar ~= WINBAR then
      vim.wo[win].winbar = WINBAR
    end
  end
end

-- ── Keys ─────────────────────────────────────────────────────────────────

-- With nothing copied in the tree, nvim-tree's paste reads the system
-- clipboard and copies every line as a file path, so a paragraph on the
-- clipboard became a stack of red popups. Only fall back to the clipboard
-- when every line names a real file.
local function guarded_paste()
  local explorer = require("nvim-tree.core").get_explorer()
  local clipboard = explorer and explorer.clipboard or {}
  local own = clipboard.data or {}
  if #(own.copy or {}) == 0 and #(own.cut or {}) == 0 then
    local lines = vim.split(vim.fn.getreg(clipboard.reg or "+"), "\n", { trimempty = true })
    local paths = #lines > 0
    for _, line in ipairs(lines) do
      paths = paths and line:sub(1, 1) == "/" and vim.uv.fs_stat(line) ~= nil
    end
    if not paths then
      api.nvim_echo({ { "Nothing to paste: copy a file with c or x first" } }, false, {})
      return
    end
  end
  require("nvim-tree.api").fs.paste()
end

local function on_attach(buf)
  local tree = require "nvim-tree.api"
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "Tree: " .. desc })
  end
  -- Enter on a folder steps into it (it becomes the tree's top), as in the
  -- old config; o and a double-click fold it open or shut.
  map("<CR>", function()
    local node = tree.tree.get_node_under_cursor()
    if node and node.nodes and node.name ~= ".." then
      tree.tree.change_root_to_node(node)
    else
      tree.node.open.edit()
    end
  end, "Open file / step into folder")
  map("o", tree.node.open.edit, "Open")
  map("<Tab>", tree.node.open.preview, "Preview (focus stays in the tree)")
  map("<C-v>", tree.node.open.vertical, "Open in a split beside")
  map("<C-x>", tree.node.open.horizontal, "Open in a split below")
  map("f", tree.filter.live.start, "Filter by name")
  map("E", tree.tree.expand_all, "Expand all folders")
  map("W", tree.tree.collapse_all, "Collapse all folders")
  map("D", tree.fs.trash, "Move to the trash")
  map("<2-LeftMouse>", tree.node.open.edit, "Open")
  map("<BS>", tree.tree.change_root_to_parent, "Up a folder")
  map("-", tree.tree.change_root_to_parent, "Up a folder")
  map("C", tree.tree.change_root_to_node, "Make this the root")
  map("a", tree.fs.create, "New file or folder/")
  map("r", tree.fs.rename, "Rename")
  map("d", tree.fs.remove, "Delete")
  map("x", tree.fs.cut, "Cut")
  map("c", tree.fs.copy.node, "Copy")
  map("p", guarded_paste, "Paste")
  map("y", tree.fs.copy.filename, "Copy name")
  map("Y", tree.fs.copy.relative_path, "Copy relative path")
  map("gy", tree.fs.copy.absolute_path, "Copy absolute path")
  map("R", tree.tree.reload, "Refresh")
  map("H", tree.tree.toggle_hidden_filter, "Show hidden files")
  map("I", tree.tree.toggle_gitignore_filter, "Show ignored files")
  map("gn", function()
    M.set_sort "name"
  end, "Sort by name")
  map("ga", function()
    M.set_sort "added"
  end, "Sort by recently added")
  map("gs", M.choose_sort, "Choose sort")
  map("?", tree.tree.toggle_help, "Keys")
  map("q", tree.tree.close, "Close the tree")
end

function M.setup()
  require("nvim-tree").setup {
    on_attach = on_attach,
    hijack_cursor = true,
    -- A folder argument is projects.lua's job (it opens the folder's session).
    hijack_directories = { enable = false },
    sync_root_with_cwd = true,
    update_focused_file = { enable = true },
    sort = { sorter = M.sorter },
    -- The old layout: a two-cell gutter on the left, a folder arrow and a git
    -- mark before each name, two cells per level.
    view = { width = 30, preserve_window_proportions = true, signcolumn = "yes" },
    renderer = {
      root_folder_label = function(path)
        return vim.fn.fnamemodify(path, ":t")
      end,
      group_empty = true,
      highlight_git = "name",
      highlight_opened_files = "name",
      indent_width = 2,
      indent_markers = { enable = false },
      icons = { padding = " ", show = { git = true, folder_arrow = true } },
    },
    filters = { git_ignored = true, custom = { "^.git$", "^_build$", "^_opam$" } },
    actions = {
      -- `-` and C move the tree's root only: the window stays on its
      -- project (Alt+O switches projects), so its session keeps saving.
      change_dir = { enable = false },
      open_file = {
        quit_on_open = false,
        resize_window = false,
        window_picker = {
          enable = true,
          -- The editor pane used last; a new one if none (panes.editor).
          picker = function()
            local tree_win = api.nvim_get_current_win()
            local win = require("panes").editor()
            api.nvim_set_current_win(tree_win)
            return win
          end,
        },
      },
    },
    notify = { threshold = vim.log.levels.WARN },
  }
  local tree = require "nvim-tree.api"
  tree.events.subscribe(tree.events.Event.TreeOpen, set_winbar)
  api.nvim_create_autocmd("BufWinEnter", {
    group = api.nvim_create_augroup("ExplorerWinbar", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype == "NvimTree" then
        vim.schedule(set_winbar)
      end
    end,
  })
end

---Alt/Cmd+B: show the tree and focus it, or hide it. Other panes keep their
---sizes.
function M.toggle()
  local tree = require "nvim-tree.api"
  local panes = require "panes"
  local sizes = panes.snapshot()
  if tree.tree.is_visible() then
    tree.tree.close()
  else
    tree.tree.open { find_file = true }
  end
  -- Only the pane beside the tree gives (or gets back) its columns.
  local neighbour
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if
      sizes[win]
      and api.nvim_win_is_valid(win)
      and api.nvim_win_get_position(win)[2] <= 31
      and not panes.is_tree(win)
    then
      neighbour = win
    end
  end
  for win, size in pairs(sizes) do
    if win == neighbour or not api.nvim_win_is_valid(win) or panes.is_tree(win) then
      sizes[win] = nil
    else
      sizes[win] = { size[1], size[2] }
    end
  end
  panes.restore(sizes)
end

return M
