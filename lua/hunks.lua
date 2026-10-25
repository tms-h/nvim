-- Change keys (mini.diff against git's index): jump to the next or previous
-- change, stage it, undo it, show the old lines. keys.lua binds them:
--   Alt+F5 / Alt+Shift+F5   next / previous change (VS Code)
--   Space g s / g r / g p   stage / undo / show old lines (jaymody's keys)
-- With a selection, stage and undo act on the selected lines only.
local M = {}

local function tracked(buf)
  if MiniDiff.get_buf_data(buf) then
    return true
  end
  vim.notify("No git changes tracked in this file", vim.log.levels.INFO)
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
      return ("Change %d of %d: %d line%s %s · Space g: s stage, r undo, p old lines"):format(
        i,
        #hunks,
        n,
        n == 1 and "" or "s",
        WHAT[h.type] or "changed"
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
