-- The tab bar: one tab per open file, in the order you opened them, like
-- Chrome. Each tab: icon, name, its error count, a close button (×). Left
-- click shows the file in the editor pane; right or middle click, or ×,
-- closes it. When the tabs do not fit, the other tabs' names shrink evenly
-- to the longest that fit, the cells left over go back to the names, and
-- short names stay short (the current tab keeps its name). Names this short
-- drop the other tabs' ×; when no name fits every tab, the current tab's
-- nearest neighbours keep names and the rest show icons only; only past
-- that does the bar scroll around the current tab (‹ ›).
-- fe-nvim's pages read like their file's tab under their own icon, with
-- their kind in front ("review bin/dune") when every page has room for it.
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
  for _, bufs in ipairs { order, api.nvim_list_bufs() } do
    for _, buf in ipairs(bufs) do
      if listed(buf) and not seen[buf] then
        kept[#kept + 1], seen[buf] = buf, true
      end
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

-- `text` in `cells` cells, the last one an ellipsis when it is cut.
local function cut(text, cells)
  if vim.fn.strdisplaywidth(text) <= cells then
    return text
  end
  return vim.fn.strcharpart(text, 0, cells - 1) .. "…"
end

-- fe-nvim names its pages fe://KIND/FEATURE[ -- FILE] (mini-iron's
-- Page.name): { kind, path } for a file's page, { kind, name } for the
-- feature's (its last part), { name } for fe://todo.
local function fe_page(full)
  local rest = full:match "^fe://(.+)$"
  if not rest then
    return nil
  end
  local kind, feature = rest:match "^(%l+)/(.+)$"
  if not kind then
    return { name = rest }
  end
  local file = feature:match " %-%- (.+)$"
  return file and { kind = kind, path = file } or { kind = kind, name = feature:match "[^/]+$" }
end

-- Each tab's names, longest first, and their widths. A file reads its name,
-- with the parent folder when two files share it ("bin/dune"), then the
-- folder's first letter ("b/dune"), then the name alone. An fe page reads
-- its kind, then what a file's tab would ("review bin/dune").
local function names(list)
  local out, count = {}, { files = {}, pages = {} }
  for _, buf in ipairs(list) do
    local full = api.nvim_buf_get_name(buf)
    local page = fe_page(full)
    local n = page or { path = full ~= "" and full or nil, name = "untitled" }
    n.fe = page ~= nil
    if n.path then
      n.tail = vim.fs.basename(n.path)
      local seen = count[n.fe and "pages" or "files"]
      seen[n.tail] = (seen[n.tail] or 0) + 1
    end
    out[buf] = n
  end
  for _, buf in ipairs(list) do
    local n = out[buf]
    if n.path then
      local dir = vim.fs.basename(vim.fs.dirname(n.path))
      n.forms = { n.tail }
      if count[n.fe and "pages" or "files"][n.tail] > 1 and dir ~= "." and dir ~= "" then
        local short = vim.fn.strcharpart(dir, 0, 1)
        n.forms = { dir .. "/" .. n.tail, short .. "/" .. n.tail, n.tail }
        if short == dir then
          table.remove(n.forms, 2)
        end
      end
    else
      n.forms = { n.name }
    end
    n.plain = 1 -- the first name without the kind
    if n.kind then
      table.insert(n.forms, 1, n.kind .. " " .. n.forms[1])
      n.plain = 2
    end
    n.widths = {}
    for k, f in ipairs(n.forms) do
      n.widths[k] = vim.fn.strdisplaywidth(f)
    end
  end
  return out
end

local NAME_MAX = 40 -- the most cells a name takes, the current tab's too
local NAME_MIN = 4 -- the fewest cells a cut name gets, else icons only
local NEAR_MIN = 6 -- the fewest when only the current tab's neighbours get names
local CLOSE_MIN = 12 -- names shorter than this: the other tabs drop ×

-- The longest of a tab's names from the `from`-th on that fits in `cap`
-- cells, else its shortest cut to `cap` (or none under NAME_MIN): which
-- name, and its width.
local function fit(n, cap, from)
  for k = from or 1, #n.widths do
    if n.widths[k] <= cap then
      return k, n.widths[k]
    end
  end
  return #n.widths, cap >= NAME_MIN and cap or 0
end

-- One tab's parts, looked up once per draw. `width`: its cells without the
-- name and ×: " icon", " ●N" and the gap after it. fe pages share one
-- colour: a diff icon for a file's page, git's for the feature's.
local function parts(buf, n, current)
  local icon, icon_hl = "", nil
  if MiniIcons then
    if n.fe then
      icon, icon_hl = MiniIcons.get("filetype", n.path and "diff" or "git"), "MiniIconsAzure"
    else
      icon, icon_hl = MiniIcons.get("file", n.forms[1])
    end
  end
  local visible = #vim.fn.win_findbuf(buf) > 0
  local kind = current and "Current" or visible and "Visible" or "Hidden"
  local err = errors(buf)
  return {
    buf = buf,
    n = n,
    current = current,
    icon = icon,
    icon_hl = icon_hl,
    hl = "Tabs" .. (vim.bo[buf].modified and "Modified" or "") .. kind,
    err = err,
    width = 1 + vim.fn.strdisplaywidth(icon) + (err and 2 + #tostring(err) or 0) + 1,
  }
end

-- Draw tab `t` with its name `k` in `w` cells (0: none), × if `close`.
local function draw(t, k, w, close)
  local name = w == 0 and "" or cut(t.n.forms[k], w)
  t.name, t.width = name, t.width + (w > 0 and w + 1 or 0) + (close and 2 or 0)
  local s = { "%" .. t.buf .. "@v:lua.Tabs_click@%#" .. t.hl .. "# " }
  if t.icon ~= "" then
    s[#s + 1] = "%#" .. (t.icon_hl or t.hl) .. "#" .. t.icon .. "%#" .. t.hl .. "#"
  end
  if name ~= "" then
    s[#s + 1] = " " .. name:gsub("%%", "%%%%")
  end
  if t.err then
    s[#s + 1] = " %#TabsError#●" .. t.err .. "%#" .. t.hl .. "#"
  end
  s[#s + 1] = "%T"
  if close then
    s[#s + 1] = " %" .. t.buf .. "@v:lua.Tabs_close@%#TabsClose#×%T"
  end
  -- The gap after a tab is never underlined with it.
  s[#s + 1] = "%#TabsFill# "
  t.s = table.concat(s)
end

---How the bar was drawn last, for checks: `cap`, the most cells another
---tab's name may take (0 = icons only); `named`, how many of the tabs
---nearest the current one have names; `close`, whether the other tabs keep
---×; `scroll`, whether it scrolls; `names`, each tab's name by buffer.
M.fit = {}

function M.render()
  local list = M.list()
  local cur = api.nvim_get_current_buf()
  if not listed(cur) then
    -- The tree, a terminal: the editor pane's file is the current tab.
    local win = require("panes").last_editor()
    cur = win and api.nvim_win_get_buf(win) or cur
  end
  local n = names(list)
  local pages = #api.nvim_list_tabpages()
  local right = pages > 1 and ("%#TabsTabpage# " .. vim.fn.tabpagenr() .. "/" .. pages .. " ") or ""
  local room = vim.o.columns - (pages > 1 and #tostring(pages) * 2 + 3 or 0)
  local tabs, ci = {}, nil -- ci: the current tab's place
  local budget = room -- cells left for the other tabs
  for j, buf in ipairs(list) do
    local t = parts(buf, n[buf], buf == cur)
    tabs[j] = t
    if t.current then
      ci = j
      -- Never wider than the bar with ‹ › beside it.
      t.k, t.w = fit(t.n, math.min(NAME_MAX, room - t.width - 5), t.n.plain)
      budget = budget - (t.width + (t.w > 0 and t.w + 1 or 0) + 2)
    end
  end
  -- The other tabs by nearness to the current one, the right side first
  -- (Ctrl+Tab's next), as `t.near`; without a current tab, left to right.
  local others = 0
  for d = 1, #tabs do
    for _, j in ipairs(ci and { ci + d, ci - d } or { d }) do
      if tabs[j] then
        others = others + 1
        tabs[j].near = others
      end
    end
  end
  -- The other tabs' cells when the `named` nearest have names of at most
  -- `cap` cells, without their kind, and the rest icons only.
  local function total(cap, close, named)
    local sum = 0
    for _, t in ipairs(tabs) do
      if not t.current then
        local w = t.near <= named and select(2, fit(t.n, cap, t.n.plain)) or 0
        sum = sum + t.width + (w > 0 and w + 1 or 0) + (close and 2 or 0)
      end
    end
    return sum
  end
  -- The largest cap from `low` up to NAME_MAX that fits, or nil.
  local function largest(low, close, named)
    if total(low, close, named) > budget then
      return nil
    end
    local high = NAME_MAX
    while low < high do
      local mid = math.ceil((low + high) / 2)
      if total(mid, close, named) <= budget then
        low = mid
      else
        high = mid - 1
      end
    end
    return low
  end
  -- × stays on the other tabs while their names are CLOSE_MIN or more, but
  -- not when dropping it is what saves every name from a cut.
  local whole = 0 -- the cap no name is cut at
  for _, t in ipairs(tabs) do
    if not t.current then
      whole = math.max(whole, t.n.widths[#t.n.widths])
    end
  end
  local named = others
  local with, without = largest(CLOSE_MIN, true, named), largest(NAME_MIN, false, named)
  local close = with ~= nil and (with >= whole or not without or without < whole)
  local cap = close and with or without
  -- Names for every tab do not fit: readable names for as many of the
  -- current tab's neighbours as fit, icons only for the rest.
  while not cap and named > 1 do
    named = named - 1
    cap = largest(NEAR_MIN, false, named)
  end
  if not cap then
    cap, named = 0, 0
  end
  -- Hand the cells left over back, a cell of cap at a time: to cut names
  -- first (left to right), then to names a folder fits back in; last, when
  -- every fe page has room for it, their kinds.
  local spare = budget - total(cap, close, named)
  local named_tabs = {}
  for _, t in ipairs(tabs) do
    if not t.current then
      t.k, t.w = 1, 0
      if t.near <= named then
        t.k, t.w = fit(t.n, cap, t.n.plain)
        named_tabs[#named_tabs + 1] = t
      end
    end
  end
  local more = cap
  while spare > 0 and more < NAME_MAX and #named_tabs > 0 do
    more = more + 1
    for pass = 1, 2 do
      for _, t in ipairs(named_tabs) do
        if (pass == 1) == (t.w < t.n.widths[#t.n.widths]) then
          local k, w = fit(t.n, more, t.n.plain)
          if w > t.w and w - t.w <= spare then
            spare, t.k, t.w = spare - (w - t.w), k, w
          end
        end
      end
    end
  end
  -- The current tab follows the same rule, so every fe page reads alike.
  local kinded = { tabs[ci or 0], unpack(named_tabs) }
  local kinds = 0 -- the cells every kind takes, or nil
  for _, t in pairs(kinded) do
    if kinds and t.n.plain > 1 then
      local fits = t.k == t.n.plain and t.n.widths[1] <= NAME_MAX
      kinds = fits and kinds + t.n.widths[1] - t.w or nil
    end
  end
  if kinds and kinds <= spare then
    spare = spare - kinds
    for _, t in pairs(kinded) do
      if t.n.plain > 1 then
        t.k, t.w = 1, t.n.widths[1]
      end
    end
  end
  for _, t in ipairs(tabs) do
    draw(t, t.k, t.w, close or t.current)
  end
  ci = ci or 1
  -- Past icons only: a window of tabs around the current one.
  local first, last, total_cells = 1, #tabs, room - spare
  if total_cells > room then
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
  local drawn = {}
  for _, t in ipairs(tabs) do
    drawn[t.buf] = t.name
  end
  M.fit = { cap = cap, close = close, named = named, scroll = first > 1 or last < #tabs, names = drawn }
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
  vim.o.tabline = "%!v:lua.require'tabs'.render()"
  local group = api.nvim_create_augroup("Tabs", { clear = true })
  api.nvim_create_autocmd({ "DiagnosticChanged", "BufModifiedSet" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        vim.cmd.redrawtabline()
      end)
    end,
  })
  if not require("util").in_mux then
    vim.o.showtabline = 2
    return
  end
  -- Inside tmux or herdr the multiplexer draws its own tab row, so this bar
  -- shows only while there is more than one file to see (and Alt+W or
  -- Ctrl+Tab would otherwise go to files you cannot see).
  vim.o.showtabline = 0
  api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout", "BufEnter", "OptionSet" }, {
    group = group,
    callback = function(ev)
      if ev.event == "OptionSet" and ev.match ~= "buflisted" then
        return
      end
      -- BufDelete fires while the buffer is still listed: count after it.
      vim.schedule(function()
        local show = #M.list() > 1 and 2 or 0
        if vim.o.showtabline == show then
          return
        end
        -- The bar takes a row from every pane. That is no split, so it
        -- scrolls as in plain Neovim ('splitkeep' "cursor"): with
        -- options.lua's "topline" each pane kept its first line and Neovim
        -- moved the cursor up to stay 'scrolloff' clear of the new bottom,
        -- so `:edit +N` of a second file left the cursor up to 8 lines above
        -- N (fe-nvim's jump from a review diff, 2026-11-21). A hiding bar
        -- only adds a row: "topline" then moves nothing, so it stays.
        local keep = vim.o.splitkeep
        if show > 0 then
          vim.o.splitkeep = "cursor"
        end
        vim.o.showtabline = show
        vim.o.splitkeep = keep
      end)
    end,
  })
end

return M
