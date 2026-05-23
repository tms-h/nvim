--- Solve-time stats viewer for kawre/leetcode.nvim.
--- :LeetStats or <leader>ls — floating chart window.
--- Keys: t=cycle period  m=toggle MA  r=refresh  q/<Esc>=close

local M = {}
local ns = vim.api.nvim_create_namespace("leetcode_stats")

local GRAPH_H = 14
local GRAPH_W = 52
local YLABEL  = 5       -- "%4dm" = 5 chars
local PREFIX  = YLABEL + 2  -- y-label + " │" = 7
local MA_WIN  = 3

local PERIODS = { "all", "30d" }
local PERIOD_LABEL = { all = "All Time", ["30d"] = "Last 30d" }

local function diff_hl(d)
  if d == "Easy" then return "DiagnosticOk"    end
  if d == "Hard" then return "DiagnosticError" end
  return "DiagnosticWarn"
end
local HL_MA  = "Function"
local HL_DIM = "Comment"

-- ── CSV ───────────────────────────────────────────────────────────────────────

local function csv_path()
  return vim.fn.stdpath("data") .. "/leetcode/leetcode_timing_events.csv"
end

local function csv_split(line)
  local t, i = {}, 1
  while i <= #line do
    if line:sub(i, i) == '"' then
      local j = i + 1
      while j <= #line do
        if line:sub(j, j) == '"' then
          if line:sub(j + 1, j + 1) == '"' then j = j + 2 else break end
        else j = j + 1 end
      end
      table.insert(t, line:sub(i + 1, j - 1):gsub('""', '"'))
      i = j + 2
    else
      local j = line:find(",", i, true)
      if j then table.insert(t, line:sub(i, j - 1)); i = j + 1
      else       table.insert(t, line:sub(i));        break end
    end
  end
  return t
end

local function ts_epoch(ts)
  local y, mo, d, h, mi, s = ts:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
  if not y then return 0 end
  return os.time({ year=tonumber(y), month=tonumber(mo), day=tonumber(d),
                   hour=tonumber(h), min=tonumber(mi),  sec=tonumber(s), isdst=false })
end

local function load_all()
  local f = io.open(csv_path(), "r")
  if not f then return {} end

  -- Prefer submit_ac (accepted-only, written by the result patch).
  -- Fall back to submit for rows that predate the patch and have no submit_ac.
  local by_session = {}
  local order      = {}
  local first      = true

  for line in f:lines() do
    if first then
      first = false
    else
      local t     = csv_split(line)
      local event = t[3]
      if #t >= 10 and (event == "submit_ac" or event == "submit") then
        local sid      = t[2]
        local row      = {
          ts    = t[1],
          epoch = ts_epoch(t[1]),
          secs  = tonumber(t[5]) or 0,
          fid   = t[6],
          title = t[9],
          diff  = t[10],
          event = event,
        }
        local existing = by_session[sid]
        if not existing then
          by_session[sid] = row
          table.insert(order, sid)
        elseif event == "submit_ac" and existing.event ~= "submit_ac" then
          by_session[sid] = row  -- upgrade legacy submit → submit_ac
        end
      end
    end
  end
  f:close()

  local rows = {}
  for _, sid in ipairs(order) do
    table.insert(rows, by_session[sid])
  end
  table.sort(rows, function(a, b) return a.epoch < b.epoch end)
  return rows
end

local function filter(all, period)
  if period == "all" then return all end
  local days    = tonumber(period:match("^(%d+)d$")) or 30
  local cutoff  = os.time() - days * 86400
  local result  = {}
  for _, s in ipairs(all) do
    if s.epoch >= cutoff then table.insert(result, s) end
  end
  return result
end

-- ── helpers ───────────────────────────────────────────────────────────────────

local function fmt(sec)
  sec = math.floor(sec)
  local m, s = math.floor(sec / 60), sec % 60
  if m == 0 then return s .. "s" end
  if s == 0 then return m .. "m" end
  return m .. "m " .. s .. "s"
end

local function calc_ma(subs, win)
  local ma = {}
  for i = 1, #subs do
    local s, tot = math.max(1, i - win + 1), 0
    for j = s, i do tot = tot + subs[j].secs end
    ma[i] = tot / (i - s + 1)
  end
  return ma
end

local function to_row(secs, top_m)
  local frac = secs / (top_m * 60)
  return math.max(1, math.min(GRAPH_H,
    GRAPH_H - math.floor(frac * (GRAPH_H - 1) + 0.5)))
end

-- ── render ────────────────────────────────────────────────────────────────────

local function build(all_subs, opts)
  local period  = opts.period  or "all"
  local show_ma = opts.show_ma ~= false

  local lines, marks = {}, {}
  local function mark(l, cs, ce, g) table.insert(marks, { l, cs, ce, g }) end
  local function push(s) table.insert(lines, s); return #lines - 1 end

  local subs = filter(all_subs, period)
  local n    = #subs
  local plabel = PERIOD_LABEL[period] or period

  if n == 0 then
    push("")
    push("  No submissions in this period.")
    push("")
    local l = push("  t  cycle period   q  close")
    mark(l, 2, 3, HL_DIM); mark(l, 18, 19, HL_DIM)
    push("")
    return lines, marks
  end

  -- stats
  local sum, best, worst = 0, math.huge, 0
  local counts = { Easy = 0, Medium = 0, Hard = 0 }
  for _, s in ipairs(subs) do
    sum   = sum + s.secs
    best  = math.min(best, s.secs)
    worst = math.max(worst, s.secs)
    counts[s.diff] = (counts[s.diff] or 0) + 1
  end
  local avg = sum / n

  -- y scale
  local top_m  = math.max(1, math.ceil(worst / 60))
  local tick_m = math.max(1, math.ceil(top_m / GRAPH_H))
  top_m = tick_m * GRAPH_H

  -- x positions (0-based)
  local xcol = {}
  for i = 1, n do
    xcol[i] = n == 1 and math.floor(GRAPH_W / 2)
      or math.floor((i - 1) * (GRAPH_W - 1) / (n - 1))
  end

  -- 2D grid: grid[row][col] = { char, hl|nil }
  local grid = {}
  for r = 1, GRAPH_H do
    grid[r] = {}
    for c = 0, GRAPH_W - 1 do grid[r][c] = { " ", nil } end
  end

  -- 1. MA line (lowest priority)
  if show_ma and n >= 2 then
    local ma = calc_ma(subs, MA_WIN)
    for i = 1, n - 1 do
      local x1, x2, v1, v2 = xcol[i], xcol[i + 1], ma[i], ma[i + 1]
      for c = x1, x2 do
        local t   = (x2 == x1) and 0 or (c - x1) / (x2 - x1)
        local row = to_row(v1 * (1 - t) + v2 * t, top_m)
        if grid[row][c][1] == " " then grid[row][c] = { "─", HL_MA } end
      end
    end
    -- MA endpoint dots (overwrite line chars)
    for i = 1, n do
      local row = to_row(ma[i], top_m)
      grid[row][xcol[i]] = { "◦", HL_MA }
    end
  end

  -- 2. Data dots (highest priority)
  for i, s in ipairs(subs) do
    local row = to_row(s.secs, top_m)
    grid[row][xcol[i]] = { "●", diff_hl(s.diff) }
  end

  -- ── header ──
  push("")
  local header = string.format("  Solve Times  ·  %s", plabel)
  local l = push(header)
  mark(l, 2, 13, "Title")
  mark(l, 17, 17 + #plabel, HL_DIM)
  push("")

  -- ── chart rows ──
  for r = 1, GRAPH_H do
    local val_m  = top_m - (r - 1) * tick_m
    local show   = (r == 1) or (r == GRAPH_H) or (r % 3 == 0)
    local ylabel = show and string.format("%4dm", val_m) or string.rep(" ", YLABEL)

    local row_str = ylabel .. " │"
    for c = 0, GRAPH_W - 1 do row_str = row_str .. grid[r][c][1] end
    l = push(row_str)

    if show then mark(l, 0, YLABEL, HL_DIM) end
    for c = 0, GRAPH_W - 1 do
      local cell = grid[r][c]
      if cell[2] then
        local col = PREFIX + c
        mark(l, col, col + 1, cell[2])
      end
    end
  end

  -- ── x-axis ──
  l = push(string.rep(" ", YLABEL) .. " └" .. string.rep("─", GRAPH_W))
  mark(l, 0, YLABEL + 2 + GRAPH_W, HL_DIM)

  -- ── x-axis labels (rotated vertically, bottom-aligned) ──
  do
    local max_len = 0
    for _, s in ipairs(subs) do
      max_len = math.max(max_len, #tostring(s.fid))
    end
    for row_i = 1, max_len do
      local chars = {}
      for c = 0, GRAPH_W - 1 do chars[c] = " " end
      local row_marks = {}
      for i, s in ipairs(subs) do
        local fid    = tostring(s.fid)
        local offset = row_i - (max_len - #fid)  -- bottom-aligned
        if offset >= 1 and offset <= #fid then
          local c = xcol[i]
          if c >= 0 and c < GRAPH_W then
            chars[c] = fid:sub(offset, offset)
            table.insert(row_marks, { c = c, diff = s.diff })
          end
        end
      end
      local row_str = string.rep(" ", PREFIX)
      for c = 0, GRAPH_W - 1 do row_str = row_str .. chars[c] end
      l = push(row_str)
      for _, h in ipairs(row_marks) do
        local col = PREFIX + h.c
        mark(l, col, col + 1, diff_hl(h.diff))
      end
    end
  end

  -- ── legend ──
  push("")
  local legend = "  ● Easy  ● Medium  ● Hard"
  if show_ma then legend = legend .. "   ─ MA(" .. MA_WIN .. ")" end
  l = push(legend)
  mark(l, 2,  3,  diff_hl("Easy"))
  mark(l, 10, 11, diff_hl("Medium"))
  mark(l, 20, 21, diff_hl("Hard"))
  if show_ma then
    local ma_start = #"  ● Easy  ● Medium  ● Hard   "
    mark(l, ma_start, ma_start + 1, HL_MA)        -- "─"
  end

  -- ── stats ──
  push("")
  push(string.format("  %d solved · avg %s · best %s · worst %s",
    n, fmt(avg), fmt(best), fmt(worst)))

  local parts = {}
  for _, d in ipairs({ "Easy", "Medium", "Hard" }) do
    if (counts[d] or 0) > 0 then
      table.insert(parts, counts[d] .. " " .. d)
    end
  end
  local breakdown = "  " .. table.concat(parts, "  ·  ")
  l = push(breakdown)
  for _, d in ipairs({ "Easy", "Medium", "Hard" }) do
    if (counts[d] or 0) > 0 then
      local pat   = counts[d] .. " " .. d
      local s_pos = breakdown:find(pat, 1, true)
      if s_pos then
        local ds = s_pos - 1 + #tostring(counts[d]) + 1
        mark(l, ds, ds + #d, diff_hl(d))
      end
    end
  end

  -- ── key hints ──
  push("")
  l = push("  t period   m MA   r refresh   q close")
  for _, col in ipairs({ 2, 13, 17, 29 }) do
    mark(l, col, col + 1, HL_DIM)
  end
  push("")

  return lines, marks
end

-- ── window ────────────────────────────────────────────────────────────────────

local state = {
  win        = nil,
  buf        = nil,
  all_subs   = {},
  period_idx = 1,
  show_ma    = true,
}

local function apply(buf, lines, marks)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_add_highlight(buf, ns, m[4], m[1], m[2], m[3])
  end
  vim.bo[buf].modifiable = false
end

local function redraw()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local lines, marks = build(state.all_subs, {
    period  = PERIODS[state.period_idx],
    show_ma = state.show_ma,
  })
  apply(state.buf, lines, marks)
  -- resize window to fit content
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
    local nw = math.max(60, math.min(w + 4, vim.o.columns - 4))
    local nh = math.min(#lines, vim.o.lines - 6)
    pcall(vim.api.nvim_win_set_width,  state.win, nw)
    pcall(vim.api.nvim_win_set_height, state.win, nh)
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  state.all_subs = load_all()
  local lines, marks = build(state.all_subs, {
    period  = PERIODS[state.period_idx],
    show_ma = state.show_ma,
  })

  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
  local width  = math.max(60, math.min(w + 4, vim.o.columns - 4))
  local height = math.min(#lines, vim.o.lines - 6)

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
  apply(state.buf, lines, marks)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative  = "editor",
    row       = math.floor((vim.o.lines - height) / 2),
    col       = math.floor((vim.o.columns - width) / 2),
    width     = width,
    height    = height,
    border    = "rounded",
    title     = " LeetCode Stats ",
    title_pos = "center",
    style     = "minimal",
  })
  vim.wo[state.win].wrap       = false
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].number     = false

  local buf = state.buf

  local function close()
    pcall(vim.api.nvim_win_close, state.win, true)
    state.win = nil
    state.buf = nil
  end

  local function cycle_period()
    state.period_idx = (state.period_idx % #PERIODS) + 1
    redraw()
  end

  local function toggle_ma()
    state.show_ma = not state.show_ma
    redraw()
  end

  local function refresh()
    state.all_subs = load_all()
    redraw()
  end

  vim.keymap.set("n", "q",     close,        { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close,        { buffer = buf, nowait = true })
  vim.keymap.set("n", "t",     cycle_period, { buffer = buf, nowait = true })
  vim.keymap.set("n", "m",     toggle_ma,    { buffer = buf, nowait = true })
  vim.keymap.set("n", "r",     refresh,      { buffer = buf, nowait = true })
end

vim.api.nvim_create_user_command("LeetStats", M.open, { desc = "LeetCode solve-time stats" })

return M
