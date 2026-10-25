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

---@param direction "next"|"prev"
function M.go(direction)
  if tracked(0) then
    MiniDiff.goto_hunk(direction, { n_times = 1, wrap = true })
  end
end

return M
