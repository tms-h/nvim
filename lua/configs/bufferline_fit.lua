-- Chrome-style tab shrinking: before bufferline hides tabs behind an overflow
-- arrow, try progressively more compact layouts until every tab fits.
local M = {}

-- Roomiest first. The overflow arrow only appears if the last step still overflows.
-- Compact steps drop the folder prefix bufferline adds to same-named tabs,
-- since shortened names collide often and the prefix costs the width we saved.
local steps = {
  { tab_size = 18 },
  { tab_size = 12 },
  { tab_size = 0 },
  { tab_size = 0, strip_ext = true, compact = true },
  { tab_size = 0, strip_ext = true, compact = true, max_len = 4 },
  { tab_size = 0, compact = true, icon_only = true },
}

local step = steps[1]

---Format a tab name for the current step. The active tab always keeps its full name.
---@param buf { name: string, bufnr: integer }
---@return string
function M.name_formatter(buf)
  if buf.bufnr == vim.api.nvim_get_current_buf() then
    return buf.name
  end
  if step.icon_only then
    return ""
  end
  local name = step.strip_ext and buf.name:gsub("^(.+)%.[^.]+$", "%1") or buf.name
  if step.max_len and vim.fn.strchars(name) > step.max_len then
    name = vim.fn.strcharpart(name, 0, step.max_len - 1) .. "…"
  end
  return name
end

-- Anything that changes how much room the tabs need or have. Rendering every
-- step costs ~10 ms, so only search again when this changes.
local function layout_key()
  local parts = { vim.o.columns, vim.api.nvim_get_current_buf() }
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      parts[#parts + 1] = buf .. vim.api.nvim_buf_get_name(buf)
    end
  end
  -- Window widths catch the file tree opening, which shrinks the tab area.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    parts[#parts + 1] = vim.api.nvim_win_get_width(win)
  end
  return table.concat(parts, ":")
end

local function apply(options, candidate)
  step = candidate
  options.tab_size = candidate.tab_size
  options.show_duplicate_prefix = not candidate.compact
end

function M.setup()
  local render = _G.nvim_bufferline
  local config = require "bufferline.config"
  local state = require "bufferline.state"
  local last_key

  _G.nvim_bufferline = function()
    local key = layout_key()
    if key == last_key then
      return render()
    end
    last_key = key
    local str, segments
    for _, candidate in ipairs(steps) do
      apply(config.options, candidate)
      str, segments = render()
      if #state.visible_components >= #state.components then
        break
      end
    end
    return str, segments
  end
end

return M
