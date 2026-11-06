-- The tab bar: one tab per open file, in the order you opened them, like
-- Chrome. Each tab: icon, name, its error count, a close button (×). Left
-- click shows the file in the editor pane; right or middle click, or ×,
-- closes it. When the tabs do not fit, they shrink in steps (shorter names,
-- no extension, icon only; the current tab keeps its name), and only past
-- the last step does the bar scroll around the current tab (‹ ›).
-- Reopen (Alt/Cmd+Shift+T) puts a tab back where it was.
local M = {}

local api = vim.api

local order = {} -- buffer numbers, left to right

local function listed(buf)
  return api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted
end

---The tabs, left to right (drops closed ones, adds new ones at the end).
function M.list()
  local seen, kept = {}, {}
  for _, buf in ipairs(order) do
    if listed(buf) and not seen[buf] then
      kept[#kept + 1], seen[buf] = buf, true
    end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if listed(buf) and not seen[buf] then
      kept[#kept + 1], seen[buf] = buf, true
    end
  end
  order = kept
  return order
end

---Position of `buf` in the bar, or nil.
function M.index(buf)
  for i, b in ipairs(M.list()) do
    if b == buf then
      return i
    end
  end
end

---Move `buf` to position `index` (reopen in place).
function M.place(buf, index)
  -- M.list() hands back `order` itself, so editing it moves the tab.
  local list = M.list()
  for i, b in ipairs(list) do
    if b == buf then
      table.remove(list, i)
      break
    end
  end
  table.insert(list, math.max(1, math.min(index, #list + 1)), buf)
  vim.cmd.redrawtabline()
end

---The tab `step` places from the current one (Ctrl+Tab is +1), wrapping.
function M.next(step)
  local list = M.list()
  if #list == 0 then
    return
  end
  local i = M.index(api.nvim_get_current_buf()) or 1
  api.nvim_win_set_buf(0, list[(i - 1 + step) % #list + 1])
end

---The n-th tab (-1 = the last).
function M.go_to(n)
  local list = M.list()
  local buf = list[n == -1 and #list or n]
  if buf then
    api.nvim_win_set_buf(0, buf)
  end
end

---Close tab `buf`: through Alt+W's close when a pane shows it (save prompt,
---next tab to the right), else straight away (asks first if unsaved).
function M.close(buf)
  if not listed(buf) then
    return
  end
  local panes = require "panes"
  local wins = vim.tbl_filter(panes.is_editor, vim.fn.win_findbuf(buf))
  if #wins > 0 then
    api.nvim_set_current_win(wins[1])
    return panes.close()
  end
  if vim.bo[buf].modified then
    local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
    local choice = vim.fn.confirm("Save changes to " .. name .. "?", "&Save\n&Discard\n&Cancel", 3)
    if choice == 1 then
      api.nvim_buf_call(buf, function()
        vim.cmd.write()
      end)
    elseif choice ~= 2 then
      return
    end
  end
  panes.remember_closed(buf)
  api.nvim_buf_delete(buf, { force = true })
  vim.cmd.redrawtabline()
end

-- ── Drawing ───────────────────────────────────────────────────────────────

local function errors(buf)
  local n = vim.diagnostic.count(buf)[vim.diagnostic.severity.ERROR]
  return n and n > 0 and n or nil
end

local function cut(text, cells)
  if vim.fn.strdisplaywidth(text) <= cells then
    return text
  end
  return vim.fn.strcharpart(text, 0, cells - 1) .. "…"
end

-- Names, with the parent folder when two tabs share a name.
local function names(list)
  local full, tails, count = {}, {}, {}
  for _, buf in ipairs(list) do
    full[buf] = api.nvim_buf_get_name(buf)
    local tail = full[buf] == "" and "untitled" or vim.fn.fnamemodify(full[buf], ":t")
    tails[buf] = tail
    count[tail] = (count[tail] or 0) + 1
  end
  for _, buf in ipairs(list) do
    if count[tails[buf]] > 1 and full[buf] ~= "" then
      tails[buf] = vim.fn.fnamemodify(full[buf], ":h:t") .. "/" .. tails[buf]
    end
  end
  return tails
end

-- Shrink steps: the most a name may take, and what is left of a tab.
local STEPS = {
  { name = 40 },
  { name = 20 },
  { name = 12 },
  { name = 8, no_ext = true },
  { name = 0, no_close = true },
}

---One tab as { s = statusline string, width = its width in cells }.
local function tab(buf, name, step, current)
  local icon, icon_hl = "", nil
  if MiniIcons then
    icon, icon_hl = MiniIcons.get("file", name)
  end
  if not current then
    if step.no_ext then
      name = name:gsub("(.)%.[^.]+$", "%1")
    end
    name = step.name > 0 and cut(name, step.name) or ""
  else
    name = cut(name, 40)
  end
  local visible = #vim.fn.win_findbuf(buf) > 0
  local modified = vim.bo[buf].modified
  local kind = current and "Current" or visible and "Visible" or "Hidden"
  local hl = "Tabs" .. (modified and "Modified" or "") .. kind
  local err = errors(buf)
  local close = current or not step.no_close
  -- The same tab as plain text, to measure it.
  local text = " "
    .. icon
    .. (name ~= "" and " " .. name or "")
    .. (err and " ●" .. err or "")
    .. (close and " ×" or "")
    .. " "
  local s = { "%" .. buf .. "@v:lua.Tabs_click@%#" .. hl .. "# " }
  if icon ~= "" then
    s[#s + 1] = "%#" .. (icon_hl or hl) .. "#" .. icon .. "%#" .. hl .. "#"
  end
  if name ~= "" then
    s[#s + 1] = " " .. name:gsub("%%", "%%%%")
  end
  if err then
    s[#s + 1] = " %#TabsError#●" .. err .. "%#" .. hl .. "#"
  end
  s[#s + 1] = "%T"
  if close then
    s[#s + 1] = " %" .. buf .. "@v:lua.Tabs_close@%#TabsClose#×%T"
  end
  -- The gap after a tab is never underlined with it.
  s[#s + 1] = "%#TabsFill# "
  return { s = table.concat(s), width = vim.fn.strdisplaywidth(text) }
end

---The step the bar is drawn at now (1 = full names), for checks.
M.step = 1

function M.render()
  local list = M.list()
  local cur = api.nvim_get_current_buf()
  if not listed(cur) then
    -- The tree, a terminal: the editor pane's file is the current tab.
    local win = require("panes").last_editor()
    cur = win and api.nvim_win_get_buf(win) or cur
  end
  local tail = names(list)
  local pages = #api.nvim_list_tabpages()
  local right = pages > 1 and ("%#TabsTabpage# " .. vim.fn.tabpagenr() .. "/" .. pages .. " ") or ""
  local room = vim.o.columns - (pages > 1 and #tostring(pages) * 2 + 3 or 0)
  local tabs, total
  local ci = 1 -- the current tab's place (the first if it has none)
  for i, step in ipairs(STEPS) do
    tabs, total = {}, 0
    for j, buf in ipairs(list) do
      local t = tab(buf, tail[buf], step, buf == cur)
      tabs[j], total = t, total + t.width
      if buf == cur then
        ci = j
      end
    end
    M.step = i
    if total <= room then
      break
    end
  end
  -- Past the last step: a window of tabs around the current one.
  local first, last = 1, #tabs
  if total > room then
    first, last = ci, ci
    local used = tabs[ci] and tabs[ci].width or 0
    local grew = true
    while grew do
      grew = false
      if last < #tabs and used + tabs[last + 1].width + 2 <= room then
        last, used, grew = last + 1, used + tabs[last + 1].width, true
      end
      if first > 1 and used + tabs[first - 1].width + 2 <= room then
        first, used, grew = first - 1, used + tabs[first - 1].width, true
      end
    end
  end
  local out = {}
  if first > 1 then
    out[#out + 1] = "%#TabsTrunc#‹"
  end
  for i = first, last do
    out[#out + 1] = tabs[i].s
  end
  if last < #tabs then
    out[#out + 1] = "%#TabsTrunc#›"
  end
  return table.concat(out) .. "%#TabsFill#%=" .. right
end

-- selene: allow(global_usage)
_G.Tabs_click = function(buf, _, button)
  if button == "l" then
    require("panes").in_editor(function()
      if listed(buf) then
        api.nvim_win_set_buf(0, buf)
      end
    end)
  elseif button == "r" or button == "m" then
    vim.schedule(function()
      M.close(buf)
    end)
  end
end

-- selene: allow(global_usage)
_G.Tabs_close = function(buf, _, button)
  if button == "l" or button == "m" then
    vim.schedule(function()
      M.close(buf)
    end)
  end
end

function M.setup()
  -- Inside tmux the tabs are tmux's (Alt+T, Alt+1..9, Ctrl+Tab): no bar here.
  -- Files are switched with the finder (Alt+P, Space f b).
  if require("util").in_mux then
    vim.o.showtabline = 0
    return
  end
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'tabs'.render()"
  api.nvim_create_autocmd({ "DiagnosticChanged", "BufModifiedSet" }, {
    group = api.nvim_create_augroup("Tabs", { clear = true }),
    callback = function()
      vim.schedule(function()
        vim.cmd.redrawtabline()
      end)
    end,
  })
end

return M
