-- Ask goose a question about the code: a popup chat box (Cursor's Cmd+L).
--
--   Alt+L / Cmd+L, :GooseAsk  open the chat box over the code, in the
--     Command box's spot, and type the question at the › line; Enter sends.
--     The question is about the selected lines, else the cursor's line. The
--     answer streams in above the › line; ask follow-ups the same way. The
--     file never changes.
--   Esc leaves typing (scroll, copy); Esc again, q, Alt+L or Alt+W close the
--     box, and so does moving to another window. Alt+L brings the same
--     conversation back: one per file, on the same claude as Alt+K for that
--     file, which remembers the earlier questions and already has the file.
local M = {}

local goose = require "goose"
local api = vim.api
local ns = api.nvim_create_namespace "goose_ask"

local chats = {} -- chats[source buf] = { buf = chat buf, s, e = lines asked about }
local PROMPT = "› "

function M.chat(src) -- for tests
  return chats[src]
end

---Box geometry: the Command box's column and top row, taller.
local function box(height)
  local cols, lines = vim.o.columns, vim.o.lines
  local width = math.min(math.max(math.min(100, math.floor(cols * 0.6)), math.min(60, cols - 4)), cols - 4)
  local ok, finder = pcall(require, "finder")
  local row = ok and finder.window and finder.window().row or math.floor(lines * 0.15)
  local max = math.max(5, lines - row - 4)
  return {
    relative = "editor",
    row = row,
    col = math.floor((cols - width - 2) / 2),
    width = math.max(width, 10),
    height = math.max(5, math.min(height, max, math.floor(lines * 0.6))),
  }
end

---Grow the box with the conversation, up to its maximum.
local function fit(win)
  if api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, box(api.nvim_win_text_height(win, {}).all))
  end
end

local function where(c)
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(c.src), ":t")
  return c.s == c.e and ("%s, line %d"):format(name, c.s + 1) or ("%s, lines %d-%d"):format(name, c.s + 1, c.e + 1)
end

local function close(c)
  if c.win and api.nvim_win_is_valid(c.win) then
    api.nvim_win_close(c.win, true)
  end
  c.win = nil
end

---Lines of the answer so far: what the model sent, or a placeholder.
local function body(text)
  local lines = vim.split((text or ""):gsub("\r", ""), "\n", { plain = true })
  while #lines > 0 and lines[#lines]:match "^%s*$" do
    table.remove(lines)
  end
  return #lines > 0 and lines or { "_thinking…_" }
end

---Enter on the › line: stream the answer in above the next › line.
local function send(c, q)
  q = vim.trim(q or "")
  if q == "" then
    return
  end
  local cb, src, s, e = c.buf, c.src, c.s, c.e
  if not api.nvim_buf_is_valid(src) then
    return
  end
  -- The new › line is the last line; the answer and a blank go above it.
  local at = api.nvim_buf_line_count(cb) - 1
  local wait = body()[1]
  api.nvim_buf_set_lines(cb, at, at, false, { wait, "" })
  local mark = api.nvim_buf_set_extmark(cb, ns, at, 0, { end_row = at, end_col = #wait, right_gravity = false, end_right_gravity = true })
  local function show(text)
    if not api.nvim_buf_is_valid(cb) then
      return
    end
    local p = api.nvim_buf_get_extmark_by_id(cb, ns, mark, { details = true })
    if not p[1] then
      return
    end
    local lines = body(text)
    api.nvim_buf_set_lines(cb, p[1], p[3].end_row + 1, false, lines)
    api.nvim_buf_set_extmark(cb, ns, p[1], 0, {
      id = mark,
      end_row = p[1] + #lines - 1,
      end_col = #lines[#lines],
      right_gravity = false,
      end_right_gravity = true,
    })
    if c.win then
      fit(c.win)
    end
  end
  fit(c.win or -1)
  goose.session_send(src, {
    system = goose.session_system,
    build = function(S)
      return goose.question_prompt(S, src, q, s, e)
    end,
    full = function()
      return (goose.question_prompt(nil, src, q, s, e))
    end,
    on_partial = show,
    on_done = function(out, err)
      show(out or ("_goose: %s_"):format(err or "no answer"))
      pcall(api.nvim_buf_del_extmark, cb, ns, mark)
    end,
  })
end

---The chat buffer for source file `src`: a prompt buffer (type after ›).
local function chat_buf(c)
  if c.buf and api.nvim_buf_is_valid(c.buf) then
    return c.buf
  end
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].buftype = "prompt"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].filetype = "markdown"
  vim.fn.prompt_setprompt(b, PROMPT)
  vim.fn.prompt_setcallback(b, function(q)
    send(c, q)
  end)
  local function map(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = b, desc = desc, nowait = true })
  end
  local function shut()
    vim.cmd.stopinsert()
    close(c)
  end
  map("n", "<Esc>", shut, "Goose: close the chat box")
  map("n", "q", shut, "Goose: close the chat box")
  map({ "n", "i" }, require("util").chord "l", shut, "Goose: close the chat box")
  api.nvim_create_autocmd("WinLeave", {
    buffer = b,
    callback = function()
      vim.schedule(function()
        close(c)
      end)
    end,
  })
  c.buf = b
  return b
end

---Alt+L: open the chat box about lines s..e of the current file (default:
---the cursor's line), ready to type.
function M.ask(s, e)
  local src = api.nvim_get_current_buf()
  if vim.bo[src].buftype ~= "" then
    return vim.notify "goose: ask from a file"
  end
  local row = vim.fn.line "." - 1
  local c = chats[src] or { src = src }
  chats[src] = c
  c.s, c.e = s or row, e or row
  local b = chat_buf(c)
  close(c)
  local cfg = box(api.nvim_buf_line_count(b))
  cfg.border = vim.o.winborder ~= "" and vim.o.winborder or "rounded"
  cfg.title = (" Goose · %s "):format(where(c))
  cfg.title_pos = "center"
  c.win = api.nvim_open_win(b, true, cfg)
  vim.wo[c.win].wrap, vim.wo[c.win].linebreak = true, true
  vim.wo[c.win].number, vim.wo[c.win].relativenumber, vim.wo[c.win].signcolumn, vim.wo[c.win].list = false, false, "no", false
  fit(c.win)
  vim.cmd "startinsert!"
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
  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = api.nvim_create_augroup("GooseAsk", { clear = true }),
    callback = function(a)
      local c = chats[a.buf]
      if c then
        chats[a.buf] = nil
        close(c)
        pcall(api.nvim_buf_delete, c.buf or -1, { force = true })
      end
    end,
  })
end

return M
