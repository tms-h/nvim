-- A project is a folder. Each folder keeps its own session (its tabs and
-- splits), saved on exit and when you switch folders.
--
--   nvim / neovide          open the project you started in (its repository
--                           root), else the project a window last opened or
--                           closed on that no other window has open (two
--                           windows never show the same project)
--   nvim some/folder        open that folder: its session and the tree
--   Alt/Cmd+O, :OpenFolder  switch this window to another folder; in that
--                           picker Alt/Cmd+N makes the typed folder (a bare
--                           name goes in ~/Work) and opens it
--
-- Files changed on disk (by agents, git) reload without a keypress.
--
-- Inside tmux or herdr (util.in_mux) the multiplexer keeps the session: the
-- running Neovim lives in its pane, and in tmux a closed tab comes back
-- through tmux-tabs. So there `nvim folder` just opens the folder and the
-- tree: no session is loaded or saved (Neovide's own session for that folder
-- stays untouched), and the window is not counted as "open", so Neovide and
-- the multiplexer never refuse a folder because the other has it.
local M = {}

local api, uv = vim.api, vim.uv
local is_windows = require("util").is_windows
local in_mux = require("util").in_mux

local session_dir = vim.fn.stdpath "state" .. "/sessions"
-- When each project was last in use: one file per project holding its path,
-- written when a window opens the project and when that window closes. Its
-- time, not the session's, picks the project to reopen: switching away saves
-- the folder being left, which made it look newest, and a window closed with
-- no file open removes its own session (a bare start kept reopening ISErepo
-- after a switch away from it, 2026-11-15).
local used_dir = vim.fn.stdpath "state" .. "/projects-used"
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

-- A folder's path as one file name: every / \ and : becomes %.
local function flat(dir)
  return (dir:gsub("[/\\:]", "%%"))
end

local function session_file(dir)
  return session_dir .. "/" .. flat(normalize(dir)) .. ".vim"
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
  if in_mux then
    return
  end
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

-- When a file last changed, in seconds (0 when it is gone). Fractions of a
-- second count: a switch can open two projects within one.
local function mtime(file)
  local stat = uv.fs_stat(file)
  return stat and stat.mtime.sec + stat.mtime.nsec / 1e9 or 0
end

-- Marks `dir` (normalized) as this window's project as of now.
local function mark_used(dir)
  if in_mux or not dir then
    return
  end
  vim.fn.mkdir(used_dir, "p")
  vim.fn.writefile({ dir }, used_dir .. "/" .. flat(dir))
end

---Projects by when a window last had them open, newest first, as
---`{ dir, time }`. A project not opened since these records began goes by
---its session's time.
function M.recent()
  local time = {}
  for _, file in ipairs(vim.fn.glob(session_dir .. "/*.vim", false, true)) do
    time[dir_of_session(file)] = mtime(file)
  end
  for _, file in ipairs(vim.fn.glob(used_dir .. "/*", false, true)) do
    local ok, lines = pcall(vim.fn.readfile, file)
    if ok and lines[1] and lines[1] ~= "" then
      time[lines[1]] = mtime(file)
    end
  end
  local list = {}
  for dir, t in pairs(time) do
    list[#list + 1] = { dir = dir, time = t }
  end
  table.sort(list, function(a, b)
    return a.time > b.time
  end)
  return list
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
  if in_mux or not project or cwd ~= project or not is_project(cwd) then
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

local function load_session(dir)
  if in_mux then
    return
  end
  local file = session_file(dir)
  if uv.fs_stat(file) then
    vim.cmd("silent! source " .. vim.fn.fnameescape(file))
  end
end

---The project a window last opened or closed on that no other window has
---open now.
function M.last_project()
  local elsewhere = M.open_elsewhere()
  for _, used in ipairs(M.recent()) do
    local dir = used.dir
    if vim.fn.isdirectory(dir) == 1 and not elsewhere[normalize(dir)] and is_project(dir) then
      return dir
    end
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
  if not in_mux and path ~= project and M.open_elsewhere()[path] then
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
  mark_used(path)
  load_session(path)
  vim.schedule(require("explorer").show)
end

-- "5m ago", "3h ago", "2d ago".
local function ago(sec)
  local d = math.max(0, os.time() - sec)
  if d < 3600 then
    return math.max(1, math.floor(d / 60)) .. "m ago"
  elseif d < 86400 then
    return math.floor(d / 3600) .. "h ago"
  end
  return math.floor(d / 86400) .. "d ago"
end

local pick_ns = api.nvim_create_namespace "PickFolder"

-- Each row: an icon, the path with its last folder in bold, and on the right
-- when a recent project was last open.
local function show_folders(buf, items, query)
  local pick = require("finder").load()
  pick.default_show(buf, items, query)
  api.nvim_buf_clear_namespace(buf, pick_ns, 0, -1)
  for i, item in ipairs(items) do
    local name = item.text:find "[^/]+$" or 1
    api.nvim_buf_set_extmark(buf, pick_ns, i - 1, 0, {
      virt_text = { { item.recent and "󰋚 " or "󰉋 ", item.recent and "PickFolderRecent" or "PickFolderIcon" } },
      virt_text_pos = "inline",
    })
    api.nvim_buf_set_extmark(buf, pick_ns, i - 1, name - 1, { end_col = #item.text, hl_group = "PickFolderName" })
    if item.recent then
      api.nvim_buf_set_extmark(buf, pick_ns, i - 1, 0, {
        virt_text = { { item.recent .. " ", "PickFolderAge" } },
        virt_text_pos = "right_align",
      })
    end
  end
end

-- Recent projects (the first `recent` items) stay on top while you type,
-- newest first; the other folders follow, best match first.
local function match_folders(recent)
  return function(stritems, inds, query)
    local pick = require("finder").load()
    local top, rest = {}, {}
    for _, i in ipairs(pick.default_match(stritems, inds, query, { sync = true }) or {}) do
      table.insert(i <= recent and top or rest, i)
    end
    table.sort(top)
    pick.set_picker_match_inds(vim.list_extend(top, rest))
  end
end

---Alt/Cmd+O: pick a folder. Recent projects first, newest first, each with
---when it was last open; then folders inside this one, then folders under
---home. Typing keeps the recent projects on top. Alt/Cmd+N makes the typed
---folder (a bare name goes in ~/Work; ~/x and /x as typed; parents too) and
---opens it.
function M.pick_folder()
  local home = normalize "~"
  local scratch = normalize "~/.cache"
  local seen, items = M.open_elsewhere(), {}
  local function add(dir, recent)
    if dir and not seen[dir] then
      seen[dir] = true
      items[#items + 1] = {
        text = vim.startswith(dir, home) and "~" .. dir:sub(#home + 1) or dir,
        path = dir,
        recent = recent,
      }
    end
  end
  local config = normalize(vim.fn.stdpath "config")
  for _, used in ipairs(M.recent()) do
    local dir = normalize(used.dir)
    -- Left out: home, / and temp folders (never a project) and agents'
    -- scratch folders under ~/.cache. This config stays: it opens, it just
    -- keeps no session.
    local listed = dir and (is_project(dir) or dir == config) and not vim.startswith(dir, scratch .. "/")
    if listed and vim.fn.isdirectory(dir) == 1 then
      add(dir, ago(used.time))
    end
  end
  local recent = #items
  -- Then folders inside this one, then folders under home, each shallow
  -- first, then A-Z.
  if vim.fn.executable "fd" == 1 then
    for _, where in ipairs { { vim.fn.getcwd(), "3" }, { home, "4" } } do
      local cmd = { "fd", "--type", "d", "--max-depth", where[2], "--absolute-path" }
      for _, skip in ipairs { "node_modules", "_build", "_opam", "target", ".git" } do
        vim.list_extend(cmd, { "--exclude", skip })
      end
      -- The Mac's app data and media folders: never projects, and reading
      -- them from Neovide waits on a macOS permission prompt that may never
      -- show, which froze the editor. The timeout keeps any other slow folder
      -- from doing the same.
      for _, skip in ipairs { "/Library", "/Pictures", "/Music", "/Movies" } do
        vim.list_extend(cmd, { "--exclude", skip })
      end
      vim.list_extend(cmd, { ".", where[1] })
      local found =
        vim.split(vim.system(cmd, { text = true, timeout = 2000 }):wait().stdout or "", "\n", { trimempty = true })
      found = vim.tbl_map(normalize, found)
      table.sort(found, function(a, b)
        local da, db = select(2, a:gsub("/", "")), select(2, b:gsub("/", ""))
        if da ~= db then
          return da < db
        end
        return a < b
      end)
      for _, dir in ipairs(found) do
        add(dir)
      end
    end
  end
  local pick = require("finder").load()
  pick.start {
    source = {
      name = "Open folder",
      items = items,
      show = show_folders,
      match = match_folders(recent),
      choose = function(item)
        vim.schedule(function()
          M.open_folder(item.path)
        end)
      end,
    },
    mappings = {
      new_folder = {
        char = require("util").chord "n",
        func = function()
          local typed = vim.trim(table.concat(pick.get_picker_query() or {}))
          if typed == "" then
            vim.notify("Type the new folder's name first", vim.log.levels.WARN)
            return
          end
          if typed:sub(1, 1) == "~" then
            typed = home .. typed:sub(2)
          elseif vim.fn.isabsolutepath(typed) == 0 then
            typed = home .. "/Work/" .. typed
          end
          local path = vim.fs.normalize(typed)
          if vim.fn.isdirectory(path) == 0 and vim.fn.mkdir(path, "p") == 0 then
            vim.notify("Could not make " .. path, vim.log.levels.ERROR)
            return
          end
          vim.schedule(function()
            M.open_folder(path)
          end)
          return true
        end,
      },
    },
  }
end

-- Reloads each loaded file that changed on disk and has no edits here (a
-- plain `checktime` would also ask W12 about the edited ones). Skipped while
-- Neovim waits on a prompt, a pending key or the command line.
function M.reload_unedited()
  local mode = api.nvim_get_mode()
  if mode.blocking or mode.mode:find "^[cr]" or vim.fn.getcmdwintype() ~= "" then
    return
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if
      api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buftype == ""
      and not vim.bo[buf].modified
      and api.nvim_buf_get_name(buf) ~= ""
    then
      -- 'autoread' off (it is global-local, nil here when not set for this
      -- buffer) would turn a reload into W11.
      local autoread = vim.bo[buf].autoread
      if autoread == nil then
        autoread = vim.go.autoread
      end
      if autoread then
        vim.cmd("silent! checktime " .. buf)
      end
    end
  end
end

local reload_timer

function M.setup()
  local group = api.nvim_create_augroup("Projects", { clear = true })
  api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, { group = group, callback = record_open })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      os.remove(open_file)
      -- The window closed last on a project reopens it, even when its
      -- session is removed for having no file open.
      mark_used(project)
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
  -- project Neovim started in (its repository root), unless another window
  -- has it open. Started outside any project, it opens the project a window
  -- last opened or closed on (M.recent: the time it was in use, not when its
  -- session was saved) that nobody else has open; inside tmux or herdr it
  -- opens nothing. Files and stdin open as given.
  -- (Read now: by VimEnter a folder argument's buffer can be replaced.)
  local argv = vim.fn.argv()
  local start_dir = #argv == 1 and vim.fn.isdirectory(argv[1]) == 1 and argv[1] or nil
  api.nvim_create_autocmd("VimEnter", {
    group = group,
    nested = true,
    callback = function()
      if start_dir then
        vim.cmd "silent! %argdelete"
        local netrw_buf = api.nvim_get_current_buf()
        M.open_folder(start_dir, { startup = true })
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
          if in_mux or not M.open_elsewhere()[here] then
            M.open_folder(here, { startup = true })
          end
        elseif not in_mux then
          local dir = M.last_project()
          if dir then
            M.open_folder(dir, { startup = true })
          end
        end
      end
    end,
  })

  -- Files changed outside reload on their own (unless you edited them too).
  -- Focus, entering a buffer and the pause after a key check every file; one
  -- you edited too asks (W12), as you are there to answer.
  api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave" }, {
    group = group,
    callback = function()
      if vim.fn.getcmdwintype() == "" and vim.bo.buftype == "" then
        vim.cmd "silent! checktime"
      end
    end,
  })
  -- A pane you are not in (herdr, tmux, Neovide behind another window) gets
  -- none of those, so once a second a timer checks the files you have not
  -- edited. Edited ones wait for you: their W12 prompt would sit unseen.
  if reload_timer then
    reload_timer:stop()
  else
    reload_timer = uv.new_timer()
    reload_timer:unref()
  end
  reload_timer:start(1000, 1000, vim.schedule_wrap(M.reload_unedited))
end

return M
