-- The file tree (nvim-tree), laid out like the old config's: a two-cell
-- gutter, folder arrows before each name, git status as VS Code shows it
-- (letters at the right edge, names coloured; see Git status below), and a
-- clickable Sort row on top (M.winbar). Its first line is the folder's name.
-- Files open in the editor pane used last, never in a terminal and never
-- with a "which window?" prompt. Only the keys below do anything; any other
-- key is plain Vim on a read-only list (at most one short line).
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
---at most 29 cells so it fits the 30-cell tree. Sorted by modification time
---(gs), the second button reads "Edited (gs)". Clicking Name or Added sorts
---by it; clicking Edited opens the gs list.
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

-- ── Git status ───────────────────────────────────────────────────────────
-- As VS Code's explorer: a letter at the right edge of each changed file
-- (U untracked, A added, M modified, D deleted, R renamed, C copied, T type
-- changed, ! conflict) with the name in the same colour (ExplorerGit* in
-- theme.lua), and a dot on each folder holding changes, coloured by the most
-- urgent one. Ignored names are dimmed, without a letter. Open files are
-- bold only (NvimTreeOpenedHL), so being open never hides or fakes a status.

local GIT_GROUP = {
  U = "ExplorerGitUntracked",
  A = "ExplorerGitAdded",
  C = "ExplorerGitAdded",
  M = "ExplorerGitModified",
  T = "ExplorerGitModified",
  D = "ExplorerGitDeleted",
  R = "ExplorerGitRenamed",
  ["!"] = "ExplorerGitConflict",
  I = "ExplorerGitIgnored",
}
-- A folder's colour: its most urgent change.
local GIT_RANK = { ["!"] = 6, M = 5, T = 5, D = 4, A = 3, C = 3, U = 2, R = 1 }
local CONFLICT = { DD = true, AU = true, UD = true, UA = true, DU = true, AA = true, UU = true }

---VS Code's letter for a `git status --porcelain` XY (X the index, Y the
---working tree): a conflict first, then the working tree's change, then the
---index's. " A" is `git add -N` (intent to add): A, as VS Code shows it.
function M.git_letter(xy)
  if xy == "??" then
    return "U"
  elseif xy == "!!" then
    return "I"
  elseif CONFLICT[xy] then
    return "!"
  end
  local y = xy:sub(2, 2)
  return y ~= " " and y or xy:sub(1, 1)
end

---The letter that decides a node's colour; a folder takes its most urgent
---change, its own or any below it.
local function node_letter(node)
  local status = node.git_status
  if not status then
    return nil
  end
  if not node.nodes or status.file == "!!" then
    return status.file and M.git_letter(status.file)
  end
  local best = status.file and M.git_letter(status.file)
  local dir = status.dir or {}
  for _, xys in ipairs { dir.direct or {}, dir.indirect or {} } do
    for _, xy in ipairs(xys) do
      local letter = M.git_letter(xy)
      if (GIT_RANK[letter] or 0) > (GIT_RANK[best] or 0) then
        best = letter
      end
    end
  end
  return best
end

-- nvim-tree's decorator for the above, built once nvim-tree is loaded.
local function git_decorator()
  local Git = require("nvim-tree.api").Decorator:extend()
  function Git:new()
    self.enabled = true
    self.highlight_range = "name"
    self.icon_placement = "right_align"
  end
  function Git:highlight_group(node)
    return GIT_GROUP[node_letter(node)]
  end
  function Git:icons(node)
    local letter = node_letter(node)
    if not GIT_GROUP[letter] or letter == "I" then
      return nil
    end
    -- nvim-tree puts one space after it, before the window's edge. Folders
    -- get ● (VS Code's • is a speck in Neovide's font).
    return { { str = node.nodes and "●" or letter, hl = { GIT_GROUP[letter] } } }
  end
  return Git
end

-- nvim-tree remembers "not a git repo" for a folder until Neovim quits, and
-- its R refresh keeps that, so a folder opened before its `git init` never
-- showed any status (~/Work/janus, 2026-11-11). After each draw, a root
-- still marked so is looked at again: once it has a .git, git status loads
-- and from then on nvim-tree's watcher on .git (index, HEAD) follows outside
-- adds and commits. Tried once per change of that .git, so a .git that git
-- cannot read (another user's, say) costs nothing on later draws.
local tried, pending = {}, false

local function load_new_repo()
  pending = false
  local git = require "nvim-tree.git"
  local root = require("nvim-tree.core").get_cwd()
  if not root or git._toplevels_by_path[root] ~= false then
    return
  end
  local top = vim.fs.root(root, ".git")
  local stat = top and vim.uv.fs_stat(top .. "/.git")
  if not stat then
    return
  end
  local key = ("%d.%d"):format(stat.mtime.sec, stat.mtime.nsec)
  if tried[root] == key then
    return
  end
  tried[root] = key
  git.purge_state()
  git.load_project(root)
  require("nvim-tree.api").tree.reload()
end

---TreeRendered: cheap unless the root is a folder git did not know. The
---look waits a moment, so a `git init` still writing its files is done.
function M.after_draw()
  local root = require("nvim-tree.core").get_cwd()
  if not pending and root and require("nvim-tree.git")._toplevels_by_path[root] == false then
    pending = true
    vim.defer_fn(load_new_repo, 200)
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
    -- The old layout: a two-cell gutter on the left, a folder arrow before
    -- each name, two cells per level.
    view = { width = 30, preserve_window_proportions = true, signcolumn = "yes" },
    renderer = {
      root_folder_label = function(path)
        return vim.fn.fnamemodify(path, ":t")
      end,
      group_empty = true,
      -- nvim-tree's own "Git" swapped for the VS Code look (git_decorator).
      decorators = { git_decorator(), "Open", "Hidden", "Modified", "Bookmark", "Diagnostics", "Copied", "Cut" },
      highlight_opened_files = "name",
      indent_width = 2,
      indent_markers = { enable = false },
      icons = { padding = " ", show = { folder_arrow = true } },
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
  tree.events.subscribe(tree.events.Event.TreeRendered, M.after_draw)
  api.nvim_create_autocmd("BufWinEnter", {
    group = api.nvim_create_augroup("ExplorerWinbar", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype == "NvimTree" then
        vim.schedule(set_winbar)
      end
    end,
  })
end

-- Show or hide the tree with `change`. Only the panes along the tree's edge
-- give (or get back) its columns; every other pane keeps its size. Putting
-- every pane back, those along the edge included, would squeeze the tree to
-- one cell. Two of them touch the edge when the editor is split top and
-- bottom, or when the bottom panel shows.
local function beside_tree(change)
  local panes = require "panes"
  local sizes = panes.snapshot()
  change()
  -- The column just right of the tree (the tree sits at the left edge).
  local edge = 0
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if panes.is_tree(win) then
      edge = api.nvim_win_get_width(win) + 1
    end
  end
  for win in pairs(sizes) do
    if not api.nvim_win_is_valid(win) or panes.is_tree(win) or api.nvim_win_get_position(win)[2] == edge then
      sizes[win] = nil
    end
  end
  panes.restore(sizes)
end

---Alt/Cmd+B: show the tree and focus it, or hide it.
function M.toggle()
  local tree = require("nvim-tree.api").tree
  local panes = require "panes"
  beside_tree(function()
    if tree.is_visible() then
      tree.close()
    else
      panes.without_panel(function()
        tree.open { find_file = true }
      end)
    end
  end)
end

---Show the tree beside a folder just opened; focus stays where it was.
function M.show()
  local tree = require("nvim-tree.api").tree
  if tree.is_visible() then
    return
  end
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  beside_tree(function()
    require("panes").without_panel(tree.open)
  end)
  -- The panel comes back in a new window: find it by its buffer.
  win = api.nvim_win_is_valid(win) and win or vim.fn.win_findbuf(buf)[1]
  if win then
    api.nvim_set_current_win(win)
  end
end

return M
