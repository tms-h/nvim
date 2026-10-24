-- A project is a folder. Each folder keeps its own session (its tabs and
-- splits), saved on exit and when you switch folders.
--
--   nvim / neovide          reopen the last project that no other window has
--                           open (two windows never show the same project)
--   nvim some/folder        open that folder: its session and the tree
--   Alt/Cmd+O, :OpenFolder  switch this window to another folder
--
-- Files changed on disk (by agents, git) reload without a keypress.
local M = {}

local api, uv = vim.api, vim.uv
local is_windows = vim.fn.has "win32" == 1

local session_dir = vim.fn.stdpath "state" .. "/sessions"
-- Shared with every config generation, so the old and new config see each
-- other's windows.
local open_dir = (vim.env.XDG_STATE_HOME or vim.fn.expand "~/.local/state") .. "/nvim/open-projects"
local open_file = open_dir .. "/" .. vim.fn.getpid()

local function normalize(path)
  if not path or path == "" then
    return nil
  end
  path = uv.fs_realpath(vim.fn.expand(path)) or vim.fn.fnamemodify(path, ":p")
  path = path:gsub("\\", "/"):gsub("(.)/+$", "%1")
  return is_windows and path:lower() or path
end

local function session_file(dir)
  return session_dir .. "/" .. normalize(dir):gsub("[/\\:]", "%%") .. ".vim"
end

local function dir_of_session(file)
  local dir = vim.fn.fnamemodify(file, ":t:r"):gsub("%%", "/")
  if is_windows then
    dir = dir:gsub("^(%a)/", "%1:/")
  end
  return dir
end

-- Folders that are never a project: home, /, a temp folder itself, this config.
local function is_project(dir)
  dir = normalize(dir)
  if not dir or dir == normalize "~" or dir == "/" then
    return false
  end
  -- The temp folders themselves (a clone inside one is a project).
  for _, root in ipairs { vim.env.TMPDIR or "/tmp", "/tmp", "/private/tmp" } do
    if dir == normalize(root) then
      return false
    end
  end
  -- This config and anything in it.
  local config = normalize(vim.fn.stdpath "config")
  return not (config and (dir == config or vim.startswith(dir, config .. "/")))
end

-- ── One project per window ────────────────────────────────────────────────

-- The project this window opened (Alt+O, a folder argument, or a bare
-- start). Only it gets saved, and only it counts as "open in a window": a
-- `nvim README.md` or a git commit message inside a project is neither.
local project

---The project this window owns, or nil.
function M.current()
  return project
end

local function record_open()
  vim.fn.mkdir(open_dir, "p")
  vim.fn.writefile({ project or "" }, open_file)
end

---Folders other running Neovims have open (stale entries are removed).
function M.open_elsewhere()
  local open = {}
  for name, kind in vim.fs.dir(open_dir) do
    local pid = tonumber(name)
    if kind == "file" and pid and pid ~= vim.fn.getpid() then
      if uv.kill(pid, 0) == 0 then
        local ok, lines = pcall(vim.fn.readfile, open_dir .. "/" .. name)
        if ok and lines[1] then
          open[lines[1]] = true
        end
      else
        os.remove(open_dir .. "/" .. name)
      end
    end
  end
  return open
end

-- ── Sessions ──────────────────────────────────────────────────────────────

---Session files, newest first.
function M.sessions()
  local files = vim.fn.glob(session_dir .. "/*.vim", false, true)
  table.sort(files, function(a, b)
    return (uv.fs_stat(a) or { mtime = { sec = 0 } }).mtime.sec > (uv.fs_stat(b) or { mtime = { sec = 0 } }).mtime.sec
  end)
  return files
end

local function has_files()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

---Save this window's project: its tabs and splits. The tree, terminals and
---a zoom are left out: they are reopened fresh. With no file left open, the
---session is removed, so the next start is empty too.
function M.save()
  local cwd = normalize(vim.fn.getcwd(-1, -1))
  if not project or cwd ~= project or not is_project(cwd) then
    return
  end
  if not has_files() then
    os.remove(session_file(cwd))
    return
  end
  vim.fn.mkdir(session_dir, "p")
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    if vim.t[tab].zoom_origin and #api.nvim_list_tabpages() > 1 then
      api.nvim_set_current_tabpage(tab)
      pcall(vim.cmd.tabclose)
    end
  end
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" and #api.nvim_list_wins() > 1 then
      pcall(api.nvim_win_close, win, true)
    end
  end
  local saved = vim.o.sessionoptions
  vim.o.sessionoptions = "buffers,curdir,folds,tabpages,winsize"
  -- Taken as written: :mksession would read the % in the name as "this file".
  pcall(vim.cmd.mksession, { args = { session_file(cwd) }, bang = true, magic = { file = false } })
  vim.o.sessionoptions = saved
end

local function load(dir)
  local file = session_file(dir)
  if uv.fs_stat(file) then
    vim.cmd("silent! source " .. vim.fn.fnameescape(file))
  end
end

---The newest project with a session that no other window has open.
function M.last_project()
  local elsewhere = M.open_elsewhere()
  for _, file in ipairs(M.sessions()) do
    local dir = dir_of_session(file)
    if vim.fn.isdirectory(dir) == 1 and not elsewhere[normalize(dir)] and is_project(dir) then
      return dir
    end
  end
end

local function show_tree()
  local editor = api.nvim_get_current_win()
  -- The tree takes its columns from the pane beside it, as with Alt+B.
  local panes = require "panes"
  local sizes = panes.snapshot()
  require("nvim-tree.api").tree.open()
  panes.restore(sizes)
  if api.nvim_win_is_valid(editor) then
    api.nvim_set_current_win(editor)
  end
end

---Switch this window to `path`: save this folder, close its tabs and
---terminals, then open the folder's own session and the tree.
---@param opts? { startup: boolean }
function M.open_folder(path, opts)
  path = normalize(path)
  if not path or vim.fn.isdirectory(path) == 0 then
    vim.notify("Not a folder: " .. tostring(path), vim.log.levels.WARN)
    return
  end
  -- One window per project: two would overwrite each other's session.
  if path ~= project and M.open_elsewhere()[path] then
    vim.notify(vim.fn.fnamemodify(path, ":t") .. " is open in another window")
    return
  end
  if not (opts and opts.startup) then
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if vim.bo[buf].modified and vim.bo[buf].buftype == "" then
        vim.notify("Save or close " .. vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t") .. " first")
        return
      end
    end
    M.save()
    vim.cmd "silent! only"
    vim.cmd "enew"
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if buf ~= api.nvim_get_current_buf() then
        pcall(api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
  vim.cmd.cd(vim.fn.fnameescape(path))
  project = path
  record_open()
  load(path)
  vim.schedule(show_tree)
end

---Alt/Cmd+O: pick a folder. Recent projects first, then folders under home.
function M.pick_folder()
  local home = normalize "~"
  local seen, items = M.open_elsewhere(), {}
  local function add(dir)
    if dir and not seen[dir] then
      seen[dir] = true
      items[#items + 1] = vim.startswith(dir, home) and "~" .. dir:sub(#home + 1) or dir
    end
  end
  for _, file in ipairs(M.sessions()) do
    local dir = dir_of_session(file)
    if vim.fn.isdirectory(dir) == 1 then
      add(dir)
    end
  end
  local function finish()
    require("finder").load().start {
      source = {
        name = "Open folder",
        items = items,
        choose = function(item)
          vim.schedule(function()
            M.open_folder(item)
          end)
        end,
      },
    }
  end
  -- Then folders inside this one, then folders under home.
  if vim.fn.executable "fd" == 1 then
    for _, where in ipairs { { vim.fn.getcwd(), "3" }, { home, "4" } } do
      local cmd = { "fd", "--type", "d", "--max-depth", where[2], "--absolute-path" }
      for _, skip in ipairs { "node_modules", "_build", "_opam", "target", ".git" } do
        vim.list_extend(cmd, { "--exclude", skip })
      end
      vim.list_extend(cmd, { ".", where[1] })
      local found = vim.system(cmd, { text = true }):wait().stdout or ""
      for _, dir in ipairs(vim.split(found, "\n", { trimempty = true })) do
        add(normalize(dir))
      end
    end
  end
  finish()
end

function M.setup()
  local group = api.nvim_create_augroup("Projects", { clear = true })
  api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, { group = group, callback = record_open })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      os.remove(open_file)
      M.save()
    end,
  })
  api.nvim_create_user_command("OpenFolder", function(args)
    if args.args == "" then
      M.pick_folder()
    else
      M.open_folder(args.args)
    end
  end, { nargs = "?", complete = "dir", desc = "Open a folder" })

  -- Startup: a folder argument opens that folder. No argument opens the
  -- folder Neovim started in when it is a project, else the last project
  -- nobody else has open. Files and stdin open as given.
  -- (Read now: by VimEnter a folder argument's buffer can be replaced.)
  local argv = vim.fn.argv()
  local start_dir = #argv == 1 and vim.fn.isdirectory(argv[1]) == 1 and argv[1] or nil
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    nested = true,
    callback = function()
      if start_dir then
        local dir = start_dir
        vim.cmd "silent! %argdelete"
        local netrw_buf = api.nvim_get_current_buf()
        M.open_folder(dir, { startup = true })
        if api.nvim_buf_is_valid(netrw_buf) and api.nvim_buf_get_name(netrw_buf) ~= "" then
          pcall(api.nvim_buf_delete, netrw_buf, { force = true })
        end
      elseif vim.fn.argc() == 0 and vim.fn.line2byte "$" == -1 and not vim.g.no_restore then
        -- Started in a subfolder: the project is its repository (or dune,
        -- cargo, python project) root.
        local cwd = vim.fn.getcwd(-1, -1)
        local here = normalize(
          vim.fs.root(cwd, ".git") or vim.fs.root(cwd, { "dune-project", "Cargo.toml", "pyproject.toml" }) or cwd
        )
        if is_project(here) then
          if not M.open_elsewhere()[here] then
            M.open_folder(here, { startup = true })
          end
        else
          local dir = M.last_project()
          if dir then
            M.open_folder(dir, { startup = true })
          end
        end
      end
    end,
  })

  -- Files changed outside reload on their own (unless you edited them too).
  api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave" }, {
    group = group,
    callback = function()
      if vim.fn.getcmdwintype() == "" and vim.bo.buftype == "" then
        vim.cmd "silent! checktime"
      end
    end,
  })
end

return M
