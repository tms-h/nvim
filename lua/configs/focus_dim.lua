-- The focused pane is the one at full strength; every other pane's text is
-- dimmed toward the background, like Hyprland's dim_inactive. Backgrounds stay
-- the same everywhere, so dividers stay clean thin lines. Only the focused
-- pane shows its cursor line.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace "focus_dim"
-- Share of the way each colour moves toward the background.
local STRENGTH = 0.45
-- Lines belong to two panes at once, so they never dim.
local KEEP = { WinSeparator = true, NvimTreeWinSeparator = true }

local function mix(fg, bg, t)
  local function channel(shift)
    local a, b = bit.band(bit.rshift(fg, shift), 0xff), bit.band(bit.rshift(bg, shift), 0xff)
    return bit.lshift(math.floor(a + (b - a) * t + 0.5), shift)
  end
  return channel(16) + channel(8) + channel(0)
end

local built_count = 0

---Copy every highlight group into the dim namespace with its colours pulled
---toward the background. Run again when plugins add groups.
function M.build()
  local all = api.nvim_get_hl(0, {})
  local base = api.nvim_get_hl(0, { name = "Normal" }).bg or 0x111416
  local count = 0
  for name in pairs(all) do
    count = count + 1
    if not KEEP[name] then
      local hl = api.nvim_get_hl(0, { name = name, link = false })
      if hl.fg then
        hl.fg = mix(hl.fg, base, STRENGTH)
      end
      if hl.sp then
        hl.sp = mix(hl.sp, base, STRENGTH)
      end
      hl.link, hl.default = nil, nil
      pcall(api.nvim_set_hl, ns, name, hl)
    end
  end
  for name in pairs(KEEP) do
    api.nvim_set_hl(ns, name, api.nvim_get_hl(0, { name = name, link = false }))
  end
  -- The cursor line marks the pane you are typing in, not every pane.
  api.nvim_set_hl(ns, "CursorLine", {})
  api.nvim_set_hl(ns, "CursorLineNr", api.nvim_get_hl(ns, { name = "LineNr" }))
  built_count = count
end

local active_pane

---Dim every pane except the focused one. A float (picker, hover) keeps the
---pane it came from at full strength.
function M.apply()
  local cur = api.nvim_get_current_win()
  if api.nvim_win_get_config(cur).relative == "" then
    active_pane = cur
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      api.nvim_win_set_hl_ns(win, win == active_pane and 0 or ns)
    end
  end
end

function M.setup()
  M.build()
  local group = api.nvim_create_augroup("FocusDim", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.build })
  -- Lazy-loaded plugins define their groups late; rebuild when the set grows.
  api.nvim_create_autocmd({ "FileType", "LspAttach", "User" }, {
    group = group,
    callback = function(args)
      if args.event == "User" and args.match ~= "LazyLoad" and args.match ~= "VeryLazy" then
        return
      end
      vim.schedule(function()
        if vim.tbl_count(api.nvim_get_hl(0, {})) ~= built_count then
          M.build()
        end
      end)
    end,
  })
  api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinNew", "TabEnter", "VimEnter" }, {
    group = group,
    callback = M.apply,
  })
end

return M
