-- Ask goose a question about the code (Cursor's Cmd+L chat).
--
--   Alt+L / Cmd+L, :GooseAsk  type a question in the box; the answer streams
--     into the "goose answers" pane on the right. In a selection, the
--     question is about the selected lines, else about the cursor's line.
--     Nothing in the file changes. Ask again for a follow-up: it goes to
--     the same claude as Alt+K for this file, which remembers the earlier
--     questions and already has the file. Alt+W closes the pane.
local M = {}

local goose = require "goose"
local ns = vim.api.nvim_create_namespace "goose_ask"

local pane_buf -- one answers buffer for every file
local last = {} -- the file and lines asked about last, for asking from the pane

function M.pane_buf() -- for tests
  return pane_buf
end

---The answers buffer, shown in a pane right of the current window.
local function pane()
  if not (pane_buf and vim.api.nvim_buf_is_valid(pane_buf)) then
    pane_buf = vim.api.nvim_create_buf(false, true) -- nofile, hidden, no swap
    vim.api.nvim_buf_set_name(pane_buf, "goose answers")
    vim.bo[pane_buf].filetype = "markdown"
    vim.bo[pane_buf].modifiable = false
  end
  local win = vim.fn.bufwinid(pane_buf)
  if win == -1 then
    local width = math.max(40, math.floor(vim.api.nvim_win_get_width(0) * 0.4))
    win = vim.api.nvim_open_win(pane_buf, false, { split = "right", win = 0, width = width })
  end
  return pane_buf, win
end

local function write(buf, s, e, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, s, e, false, lines)
  vim.bo[buf].modifiable = false
end

---Lines of the answer so far: what the model sent, or a placeholder.
local function body(text)
  local lines = vim.split((text or ""):gsub("\r", ""), "\n", { plain = true })
  while #lines > 0 and lines[#lines]:match "^%s*$" do
    table.remove(lines)
  end
  return #lines > 0 and lines or { "_thinking…_" }
end

---Ask about lines s..e (0-based) of buf.
function M.send(buf, q, s, e)
  local pb, win = pane()
  local where = s == e and ("line %d"):format(s + 1) or ("lines %d-%d"):format(s + 1, e + 1)
  local head = { "## " .. q, ("_%s, %s_"):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"), where), "" }
  local n = vim.api.nvim_buf_line_count(pb)
  local empty = n == 1 and vim.api.nvim_buf_get_lines(pb, 0, 1, false)[1] == ""
  local top = empty and 0 or n + 1
  local wait = body()[1]
  write(pb, empty and 0 or n, -1, vim.list_extend(empty and {} or { "" }, { head[1], head[2], head[3], wait }))
  local row = top + #head
  -- The answer's lines, followed through later questions' appends.
  local mark = vim.api.nvim_buf_set_extmark(pb, ns, row, 0, { end_row = row, end_col = #wait, right_gravity = false, end_right_gravity = true })
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { top + 1, 0 })
    vim.cmd "normal! zt"
  end)
  local function show(text)
    if not vim.api.nvim_buf_is_valid(pb) then
      return
    end
    local p = vim.api.nvim_buf_get_extmark_by_id(pb, ns, mark, { details = true })
    if not p[1] then
      return
    end
    local lines = body(text)
    write(pb, p[1], p[3].end_row + 1, lines)
    vim.api.nvim_buf_set_extmark(pb, ns, p[1], 0, {
      id = mark,
      end_row = p[1] + #lines - 1,
      end_col = #lines[#lines],
      right_gravity = false,
      end_right_gravity = true,
    })
  end
  goose.session_send(buf, {
    system = goose.session_system,
    build = function(S)
      return goose.question_prompt(S, buf, q, s, e)
    end,
    full = function()
      return (goose.question_prompt(nil, buf, q, s, e))
    end,
    on_partial = show,
    on_done = function(out, err)
      show(out or ("_goose: %s_"):format(err or "no answer"))
      pcall(vim.api.nvim_buf_del_extmark, pb, ns, mark)
    end,
  })
end

---Alt+L: ask about lines s..e of the current file (default: the cursor's
---line); from the answers pane, about the file asked about last.
function M.ask(s, e)
  local buf = vim.api.nvim_get_current_buf()
  if buf == pane_buf then
    buf, s, e = last.buf, last.s, last.e
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
      return vim.notify "goose: ask from a file"
    end
  elseif vim.bo[buf].buftype ~= "" then
    return vim.notify "goose: ask from a file"
  else
    local row = vim.fn.line "." - 1
    s, e = s or row, e or row
  end
  last = { buf = buf, s = s, e = e }
  vim.ui.input({ prompt = "Ask goose: " }, function(q)
    if q and q:match "%S" then
      M.send(buf, vim.trim(q), s, e)
    end
  end)
end

function M.setup()
  local chord = require("util").chord
  local map = vim.keymap.set
  map("n", chord "l", function()
    M.ask()
  end, { desc = "Goose: ask a question about this line" })
  map("i", chord "l", function()
    vim.cmd.stopinsert()
    vim.schedule(M.ask)
  end, { desc = "Goose: ask a question about this line" })
  map("x", chord "l", function()
    local s, e = vim.fn.line "v" - 1, vim.fn.line "." - 1
    if s > e then
      s, e = e, s
    end
    vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
    M.ask(s, e)
  end, { desc = "Goose: ask a question about the selection" })
  vim.api.nvim_create_user_command("GooseAsk", function(a)
    if a.range > 0 then
      M.ask(a.line1 - 1, a.line2 - 1)
    else
      M.ask()
    end
  end, { range = true, desc = "Goose: ask a question about the code" })
end

return M
