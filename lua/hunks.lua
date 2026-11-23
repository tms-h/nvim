-- Change keys (mini.diff against git's index or hg's working parent `.`):
-- jump to the next or previous change, stage it (git), undo it, show the old
-- lines. keys.lua binds them:
--   Alt+F5 / Alt+Shift+F5   next / previous change (VS Code)
--   Space g s / g r / g p   stage / undo / show old lines (jaymody's keys)
-- With a selection, stage and undo act on the selected lines only.
local M = {}

local api = vim.api

local function tracked(buf)
  if MiniDiff.get_buf_data(buf) then
    return true
  end
  vim.notify("No git or hg changes tracked in this file", vim.log.levels.INFO)
end

-- ── Mercurial source for mini.diff ─────────────────────────────────────────
-- Mirrors mini.diff's built-in git source: reference text is `hg cat -r .`,
-- refreshed whenever `.hg/dirstate` is replaced (commit, update, merge,
-- revert). Runs before git because the `.hg` directory check is synchronous
-- and microsecond-fast; an inner `.git` still wins if nested.
local hg_cache = {}

local function stop_watch(cache)
  if not cache then
    return
  end
  if cache.fs_event then
    pcall(vim.uv.fs_event_stop, cache.fs_event)
    pcall(vim.uv.close, cache.fs_event)
  end
  if cache.timer then
    pcall(vim.uv.timer_stop, cache.timer)
    pcall(vim.uv.close, cache.timer)
  end
end

local function hg_set_ref_text(buf_id, root)
  if not api.nvim_buf_is_valid(buf_id) or not hg_cache[buf_id] then
    return
  end
  local path = vim.uv.fs_realpath(api.nvim_buf_get_name(buf_id)) or ""
  if path == "" then
    pcall(MiniDiff.set_ref_text, buf_id, nil)
    return
  end
  vim.system(
    { "hg", "cat", "-r", ".", "--", path },
    { cwd = root, text = false },
    vim.schedule_wrap(function(res)
      if not api.nvim_buf_is_valid(buf_id) or not hg_cache[buf_id] then
        return
      end
      if res.code ~= 0 then
        pcall(MiniDiff.set_ref_text, buf_id, nil)
        return
      end
      local text = (res.stdout or ""):gsub("\r\n", "\n")
      pcall(MiniDiff.set_ref_text, buf_id, text)
    end)
  )
end

---Custom mini.diff source for Mercurial repositories.
function M.hg_source()
  local function attach(buf_id)
    if hg_cache[buf_id] ~= nil then
      return false
    end
    local path = vim.uv.fs_realpath(api.nvim_buf_get_name(buf_id)) or ""
    if path == "" or vim.fn.executable "hg" == 0 then
      return false
    end
    local dir = vim.fn.fnamemodify(path, ":h")
    local hg_dir = vim.fs.find(".hg", { path = dir, upward = true, type = "directory" })[1]
    if not hg_dir or vim.startswith(path, hg_dir .. "/") then
      return false
    end
    local git_dir = vim.fs.find(".git", { path = dir, upward = true })[1]
    if git_dir and #git_dir > #hg_dir then
      return false
    end
    local root = vim.fn.fnamemodify(hg_dir, ":h")
    local fs_event, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
    local refresh = vim.schedule_wrap(function()
      hg_set_ref_text(buf_id, root)
    end)
    fs_event:start(hg_dir, { recursive = false }, function(_, filename)
      if filename ~= "dirstate" then
        return
      end
      timer:stop()
      timer:start(50, 0, refresh)
    end)
    hg_cache[buf_id] = { fs_event = fs_event, timer = timer }
    hg_set_ref_text(buf_id, root)
  end

  local function detach(buf_id)
    local cache = hg_cache[buf_id]
    hg_cache[buf_id] = nil
    stop_watch(cache)
  end

  local function apply_hunks()
    vim.notify("Mercurial has no staging area", vim.log.levels.INFO)
  end

  api.nvim_create_autocmd("BufUnload", {
    group = api.nvim_create_augroup("MiniDiffSourceHg", { clear = true }),
    callback = function(ev)
      detach(ev.buf)
    end,
    desc = "Clear Mercurial diff cache",
  })

  return { name = "hg", attach = attach, detach = detach, apply_hunks = apply_hunks }
end

---The selected lines (leaving the selection), else the cursor's line.
local function lines()
  local here = vim.fn.line "."
  if vim.fn.mode():find "^[vV\22]" then
    local other = vim.fn.line "v"
    vim.cmd "normal! \27"
    return math.min(here, other), math.max(here, other)
  end
  return here, here
end

local function act(action)
  local buf = vim.api.nvim_get_current_buf()
  local first, last = lines()
  if tracked(buf) then
    MiniDiff.do_hunks(buf, action, { line_start = first, line_end = last })
  end
end

function M.stage()
  local data = MiniDiff.get_buf_data(0)
  if data and data.summary and data.summary.source_name == "hg" then
    vim.notify("Mercurial has no staging area", vim.log.levels.INFO)
    return
  end
  act "apply"
end

function M.reset()
  act "reset"
end

---Show the old lines inline (press again to hide).
function M.preview()
  if tracked(0) then
    MiniDiff.toggle_overlay(0)
  end
end

local WHAT = { add = "added", change = "changed", delete = "removed" }

---Where the cursor is among the changes, in words: "Change 2 of 3: 4 lines
---added". A change (git's "hunk") is one run of lines that differ from
---git's copy; with one change, a jump lands where it already was.
function M.describe(buf)
  local data = MiniDiff.get_buf_data(buf)
  local hunks = vim.list_slice(data and data.hunks or {})
  if #hunks == 0 then
    return "No changes since the last commit"
  end
  table.sort(hunks, function(a, b)
    return a.buf_start < b.buf_start
  end)
  local line = vim.fn.line "."
  for i, h in ipairs(hunks) do
    local last = h.buf_start + math.max(h.buf_count, 1) - 1
    if line >= math.max(h.buf_start, 1) and line <= last then
      local n = h.type == "delete" and h.ref_count or h.buf_count
      local keys = data.summary and data.summary.source_name == "hg" and "r undo, p old lines"
        or "s stage, r undo, p old lines"
      return ("Change %d of %d: %d line%s %s · Space g: %s"):format(
        i,
        #hunks,
        n,
        n == 1 and "" or "s",
        WHAT[h.type] or "changed",
        keys
      )
    end
  end
end

---@param direction "next"|"prev"
function M.go(direction)
  if tracked(0) then
    MiniDiff.goto_hunk(direction, { n_times = 1, wrap = true })
    local text = M.describe(0)
    if text then
      vim.api.nvim_echo({ { text } }, false, {})
    end
  end
end

return M
