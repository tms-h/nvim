-- The focused pane is obvious: it is the one at full strength. Every other
-- pane's words are pulled toward the background (like Hyprland's
-- dim_inactive), and only the focused pane shows its cursor line and search
-- hits. Backgrounds are never copied, so every pane stays on the one surface
-- and dividers stay single thin lines.
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace "focus_dim"
-- Divider hover (dividers.lua) colours a window's separator by giving it a
-- lit namespace: dimmed + lit, or full strength + lit (ns_bright_lit, set
-- by build() with the cue's colours).
local ns_lit = api.nvim_create_namespace "focus_dim_lit"
local ns_bright_lit

-- How the focused pane stands out (vim.g.focus_cue, :FocusCue to switch).
-- Other panes must stay easy to read, so dimming alone cannot be the cue:
--   "title"    (default) others pulled only 20% toward the background, and
--              each pane has a title row (its file name; the tree's "Sort"
--              row) in the accent colour where focus is, muted elsewhere;
--              the focused row is a soft accent-tinted bar, so focus can be
--              found at a glance after a break (Thomas's pick, 2026-10-25)
--   "dim"      the look until 2026-10-24: others pulled 45%, no other cue
--              (the unfocused tree got hard to read)
--   "light"    others pulled 20%, no other cue (focus too hard to tell)
--   "divider"  light, plus the focused pane's own dividers in a soft accent
--              (a pane on the right edge has none, so no cue there)
--   "number"   light, plus the cursor's line number in the accent colour
--              (too small to notice; the tree and terminals have none)
M.CUES = { "title", "dim", "light", "divider", "number" }
local function cue()
  local c = vim.g.focus_cue
  return vim.tbl_contains(M.CUES, c) and c or "title"
end
M.cue = cue
-- Share of the way each colour moves toward the background.
local function strength()
  return cue() == "dim" and 0.45 or 0.2
end
-- The focused pane's namespace: 0 (the global groups) or the cue's colours.
local focus_ns = 0
-- Dividers belong to two panes at once, so they never dim.
local SEPARATORS = { WinSeparator = true, NvimTreeWinSeparator = true }

local function mix(a, b, t)
  local function channel(shift)
    local x, y = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
    return bit.lshift(math.floor(x + (y - x) * t + 0.5), shift)
  end
  return channel(16) + channel(8) + channel(0)
end

local built_count = 0

---Copy every group into the dim namespace, words pulled toward the surface.
function M.build()
  local all = api.nvim_get_hl(0, {})
  local base = api.nvim_get_hl(0, { name = "Normal" }).bg or 0
  local STRENGTH = strength()
  local count = 0
  for name in pairs(all) do
    count = count + 1
    local hl = api.nvim_get_hl(0, { name = name, link = false })
    if not SEPARATORS[name] then
      if hl.bg == base then
        hl.bg = nil
      end
      if hl.fg then
        hl.fg = mix(hl.fg, base, STRENGTH)
      end
      if hl.sp then
        hl.sp = mix(hl.sp, base, STRENGTH)
      end
    end
    hl.link, hl.default = nil, nil
    pcall(api.nvim_set_hl, ns, name, hl)
    pcall(api.nvim_set_hl, ns_lit, name, hl)
  end
  for _, space in ipairs { ns, ns_lit } do
    api.nvim_set_hl(space, "CursorLine", {})
    api.nvim_set_hl(space, "NvimTreeCursorLine", {})
    api.nvim_set_hl(space, "CursorLineNr", api.nvim_get_hl(ns, { name = "LineNr" }))
    for _, group in ipairs { "Search", "CurSearch", "IncSearch" } do
      api.nvim_set_hl(space, group, {})
    end
  end
  -- The focused pane: full strength plus its cue. A namespace falls back to
  -- the global groups for anything it does not define.
  local hover = api.nvim_get_hl(0, { name = "WinSeparatorHover", link = false })
  local accent = hover.fg or 0xffffff
  local cue_groups = {}
  if cue() == "divider" then
    local line = api.nvim_get_hl(0, { name = "WinSeparator", link = false }).fg or base
    for name in pairs(SEPARATORS) do
      cue_groups[name] = { fg = mix(line, accent, 0.6) }
    end
  elseif cue() == "number" then
    cue_groups.CursorLineNr = { fg = accent, bold = true }
  end
  -- Each cue has its own pair of namespaces, so a cue switched off leaves
  -- none of its colours behind.
  local ns_focus = api.nvim_create_namespace("focus_cue_" .. cue())
  ns_bright_lit = api.nvim_create_namespace("focus_bright_lit_" .. cue())
  for _, space in ipairs { ns_focus, ns_bright_lit } do
    for name, hl in pairs(cue_groups) do
      api.nvim_set_hl(space, name, hl)
    end
  end
  -- With no cue colours the focused pane uses the global groups (namespace 0).
  focus_ns = next(cue_groups) and ns_focus or 0
  for name in pairs(SEPARATORS) do
    api.nvim_set_hl(ns_lit, name, hover)
    api.nvim_set_hl(ns_bright_lit, name, hover)
  end
  -- Titles: the focused pane's in the accent on a soft accent tint (a block
  -- of colour, like Chrome's active tab), the others muted.
  api.nvim_set_hl(0, "FocusTitle", { fg = accent, bg = mix(base, accent, 0.28), bold = true })
  api.nvim_set_hl(0, "FocusTitleNC", { link = "StatusLineNC" })
  api.nvim_set_hl(ns, "FocusTitle", { link = "FocusTitleNC" })
  api.nvim_set_hl(ns_lit, "FocusTitle", { link = "FocusTitleNC" })
  built_count = count
end

---A pane's title row ("title" cue): its file or terminal name.
function M.title()
  local win = vim.g.statusline_winid or api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local name = vim.bo[buf].buftype == "terminal" and "terminal" or vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  -- "%=" carries the title's tint to the end of the row.
  return "%#FocusTitle# " .. (name ~= "" and name or "[No Name]") .. " %="
end
local TITLE = "%!v:lua.require'focus'.title()"

local function set_titles()
  local want = cue() == "title"
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_win_get_config(win).relative == "" and vim.bo[buf].filetype ~= "NvimTree" then
      local has = vim.wo[win].winbar == TITLE
      if want and not has then
        vim.wo[win].winbar = TITLE
      elseif not want and has then
        vim.wo[win].winbar = ""
      end
    end
  end
end

local active
local lit = {}
local given = {} -- namespace each pane has now, so a no-op pass redraws nothing

---Dim every pane except the focused one. A float keeps the pane it came from
---at full strength.
function M.apply()
  set_titles()
  local cur = api.nvim_get_current_win()
  if api.nvim_win_get_config(cur).relative == "" then
    active = cur
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      local want
      if win == active then
        want = lit[win] and ns_bright_lit or focus_ns
      else
        want = lit[win] and ns_lit or ns
      end
      if given[win] ~= want then
        api.nvim_win_set_hl_ns(win, want)
        given[win] = want
      end
    end
  end
end

---Switch the focus cue (one of M.CUES).
function M.set_cue(name)
  vim.g.focus_cue = name
  given = {}
  M.build()
  M.apply()
end

---Light the separators of exactly these windows (a set).
function M.set_lit(wins)
  lit = wins
  M.apply()
end

function M.setup()
  M.build()
  api.nvim_create_user_command("FocusCue", function(args)
    M.set_cue(args.args)
  end, {
    nargs = 1,
    complete = function()
      return M.CUES
    end,
    desc = "How the focused pane stands out",
  })
  local group = api.nvim_create_augroup("FocusDim", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.build })
  -- Plugins define groups late (orgmode, LSP semantic tokens): rebuild when
  -- the set has grown.
  api.nvim_create_autocmd({ "FileType", "LspAttach" }, {
    group = group,
    callback = function()
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
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      given[win], lit[win] = nil, nil
    end,
  })
end

return M
