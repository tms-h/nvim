-- Ask goose a question about the code: a popup chat box (Cursor's Cmd+L).
--
--   Alt+L / Cmd+L, :GooseAsk  open the chat box over the code, in the
--     Command box's spot, and type the question at the › line; Enter sends.
--     The question is about the selected lines, else the cursor's line. The
--     answer streams in above the › line; ask follow-ups the same way.
--     Asking never changes the file.
--   The look copies omp's: your turn (the › line, and each question asked)
--     sits on a tinted block with a row of the tint above and below it;
--     goose's answer is plain text on the box's surface after a blank row,
--     and the files it reads and its "thinking…" are grey.
--   Alt+K / Cmd+K in the box  write what the chat settled on into the file:
--     the box closes and the asked-about lines go through Alt+K's conversion
--     (grey "writing…", ghost lines, one change, one `u` undoes it), which
--     may also change other lines of this file. Other files are out of reach.
--   Wheel, Ctrl+U / Ctrl+D scroll the box, also while typing: a prompt buffer
--     keeps the cursor on the › line in Insert mode, so they leave typing
--     first; i (or a, A) types at the › line again. A streaming answer is
--     followed only while the end is in view: scrolled up, the view stays
--     put until you scroll back down or type again. No scroll glide here
--     (mini.animate), so every wheel step lands at once.
--   Ctrl+Backspace deletes the word before the cursor, never the › prompt.
--   Esc leaves typing (scroll, copy); Esc again, q, Alt+L or Alt+W close the
--     box, and so does moving to another window. Alt+L brings the same
--     conversation back: one per file.
--
-- Each file's chat has its own claude, started when the box opens, running
-- in the project root (the folder with .git, dune-project, Cargo.toml...)
-- with read-only tools (Read, Grep, Glob): it gets the current file and
-- reads callers, definitions, .mli and dune files itself. Each file it reads
-- shows as a grey line above the answer. Alt+K's claude has no tools, so
-- conversions stay fast.
local M = {}

local goose = require "goose"
local api = vim.api
local ns = api.nvim_create_namespace "goose_ask"
local turns = api.nvim_create_namespace "goose_ask_turns"
local notes = api.nvim_create_namespace "goose_ask_notes"

local chats = {} -- chats[source buf] = { buf = chat buf, s, e = lines asked about }
local PROMPT = "› "
M.frame_ms = 40 -- a streaming answer updates the box at most this often
-- One row of the question block's tint. Virtual lines never wrap, so a long
-- run of spaces is cut at the box's edge and fills the row.
local FILL = { { (" "):rep(500), "GooseAskQuestion" } }

-- Alt+K in the box: the instruction that replaces "turn the pseudocode into
-- code". Without the "unchanged" line, an answer that only edits other lines
-- would delete the region, as it does for pseudocode.
local WRITE = [[Change the region the way this chat about it settled on. The region is
code, not pseudocode: keep everything the chat does not change, and if the
region itself does not change, output its lines unchanged. Change other
lines of this file only as the chat requires. Changes the chat asks for in
other files are out of reach: leave them.

The chat (lines starting with › are the programmer's questions):
%s]]

local SYSTEM = [[You answer the programmer's questions about their code. You run
in the project's root folder and can use Read, Grep and Glob on any file in it.
Whenever the answer depends on code outside the current file (callers,
definitions, interfaces, build files, tests), look it up instead of guessing.
The first message gives the current file; later ones give a diff of it since
the previous message. Answer in short Markdown; code blocks allowed. You never
edit files.]]
local TOOLS = "Read,Grep,Glob"
local ROOT_MARKERS = { ".git", "dune-project", "Cargo.toml", "package.json", "pyproject.toml", "go.mod" }

local function root_of(src)
  return vim.fs.root(src, ROOT_MARKERS) or vim.fs.dirname(api.nvim_buf_get_name(src))
end

---One grey line per tool call: what it read or searched for.
local function describe(name, input, root)
  local path = input.file_path or input.path
  if path then
    path = vim.fs.relpath(root, path) or vim.fn.fnamemodify(path, ":~")
  end
  if name == "Read" then
    return "read " .. (path or "?")
  elseif name == "Grep" then
    return ("searched for `%s`%s"):format(input.pattern or "?", path and (" in " .. path) or "")
  elseif name == "Glob" then
    return ("listed `%s`"):format(input.pattern or "?")
  end
  return name
end

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

---Your turn as a block (theme.lua's GooseAskQuestion, like omp's user
---message): the line on the tint, with a tinted row above and below. A sent
---question also gets a blank row before its answer. All padding is virtual,
---so the chat's text stays what was typed. `ids` moves an existing block.
local function block(b, row, sent, ids)
  ids = ids or {}
  ids[1] = api.nvim_buf_set_extmark(b, turns, row, 0, { id = ids[1], virt_lines = { FILL }, virt_lines_above = true })
  ids[2] = api.nvim_buf_set_extmark(b, turns, row, 0, {
    id = ids[2],
    line_hl_group = "GooseAskQuestion",
    virt_lines = sent and { FILL, {} } or { FILL },
  })
  return ids
end

---Grow the box with the conversation, up to its maximum.
local function fit(win)
  if api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, box(api.nvim_win_text_height(win, {}).all))
    -- The tinted row above the first question is a virtual line above line
    -- 1, which Neovim draws only when the view asks for it (topfill).
    api.nvim_win_call(win, function()
      if vim.fn.line "w0" == 1 then
        vim.fn.winrestview { topfill = 1 }
      end
    end)
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
  local cb, src, s, e = c.buf, c.src, c.s, c.e
  -- The new › line is the last line; the answer and a blank go above it.
  local at = api.nvim_buf_line_count(cb) - 1
  block(cb, at, false, c.live) -- the › line's block moves down with it
  if q == "" then
    return
  end
  block(cb, at - 1, true)
  if not api.nvim_buf_is_valid(src) then
    return
  end
  local root = root_of(src)
  local reads, answer = {}, nil
  c.busy = true
  local wait = body()[1]
  api.nvim_buf_set_lines(cb, at, at, false, { wait, "" })
  local mark = api.nvim_buf_set_extmark(cb, ns, at, 0, { end_row = at, end_col = #wait, right_gravity = false, end_right_gravity = true })
  ---Grey the first `n` of the answer's `lines` from row `row`: the files read
  ---and the placeholder, not the answer.
  local function grey(row, lines, n)
    api.nvim_buf_clear_namespace(cb, notes, row, row + #lines)
    for i = 1, n do
      api.nvim_buf_set_extmark(cb, notes, row + i - 1, 0, { end_col = #lines[i], hl_group = "GooseAskNote" })
    end
  end
  grey(at, { wait }, 1)
  -- One buffer update per frame at most, not one per streamed token: each
  -- update rewrites lines, re-greys, refits the box and redraws.
  local timer
  local function render()
    if not api.nvim_buf_is_valid(cb) then
      return
    end
    local p = api.nvim_buf_get_extmark_by_id(cb, ns, mark, { details = true })
    if not p[1] then
      return
    end
    local lines = {}
    for _, r in ipairs(reads) do
      lines[#lines + 1] = "_" .. r .. "_"
    end
    vim.list_extend(lines, body(answer))
    -- Follow the answer only while the view shows the end (the › line's text
    -- is on screen, its tinted rows may be cut off); scrolled up to read, the
    -- view stays where it is.
    local win = c.win and api.nvim_win_is_valid(c.win) and c.win
    local follow, view
    if win then
      follow = vim.fn.screenpos(win, api.nvim_buf_line_count(cb), 1).row > 0
      view = api.nvim_win_call(win, vim.fn.winsaveview)
    end
    -- Only the lines that changed (the tail, while streaming).
    local old = api.nvim_buf_get_lines(cb, p[1], p[3].end_row + 1, false)
    local k = 1
    while k <= #old and k <= #lines and old[k] == lines[k] do
      k = k + 1
    end
    if k <= #old or k <= #lines then
      api.nvim_buf_set_lines(cb, p[1] + k - 1, p[3].end_row + 1, false, vim.list_slice(lines, k))
    end
    api.nvim_buf_set_extmark(cb, ns, p[1], 0, {
      id = mark,
      end_row = p[1] + #lines - 1,
      end_col = #lines[#lines],
      right_gravity = false,
      end_right_gravity = true,
    })
    grey(p[1], lines, #reads + ((answer or ""):match "%S" and 0 or 1))
    if not win then
      return
    end
    fit(win)
    local last = api.nvim_buf_line_count(cb)
    if not follow then
      api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
      end)
    elseif api.nvim_win_get_cursor(win)[1] ~= last and not api.nvim_get_mode().mode:find "^[vVs\22\19]" then
      api.nvim_win_set_cursor(win, { last, 0 })
    end
  end
  local function show(text)
    answer = text or answer
    if not timer then
      timer = vim.defer_fn(function()
        timer = nil
        render()
      end, M.frame_ms)
    end
  end
  fit(c.win or -1)
  goose.session_send(cb, {
    system = SYSTEM,
    opts = { tools = TOOLS, cwd = root },
    build = function(S)
      return goose.question_prompt(S, src, q, s, e, root)
    end,
    full = function()
      return (goose.question_prompt(nil, src, q, s, e, root))
    end,
    on_partial = show,
    on_tool = function(name, input)
      reads[#reads + 1] = describe(name, input, root)
      answer = nil
      show()
    end,
    on_done = function(out, err)
      c.busy = false
      answer = out or ("_goose: %s_"):format(err or "no answer")
      render() -- now, not a frame later; a waiting frame then finds no mark
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
  -- mini.animate's 120 ms glide (terminal Neovim) restarted on every streamed
  -- line and swallowed wheel steps inside it, so the box lagged and scrolled
  -- back down under the reader.
  vim.b[b].minianimate_disable = true
  vim.fn.prompt_setprompt(b, PROMPT)
  c.live = block(b, 0) -- the › line being typed: your turn's block
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
  map({ "n", "i" }, require("util").chord "k", function()
    M.write(c)
  end, "Goose: write what the chat settled on into the file")
  -- Typing pins the cursor to the › line, so these leave typing first, then
  -- do their usual scroll (the wheel scrolls the window under the mouse).
  for _, key in ipairs { "<ScrollWheelUp>", "<ScrollWheelDown>", "<C-u>", "<C-d>" } do
    vim.keymap.set("i", key, "<Esc>" .. key, { buffer = b, desc = "Goose: scroll the chat box" })
  end
  -- Ctrl+Backspace deletes the word before the cursor, as in VS Code (Ctrl+W
  -- starts a window command in a prompt buffer), never the › prompt. Not an
  -- expr map: one runs before fast-typed text ahead of it reaches the line.
  -- Neovide sends <C-BS>; a terminal (kitty, through tmux) sends Ctrl+H.
  for _, key in ipairs { "<C-BS>", "<C-h>" } do
    vim.keymap.set("i", key, function()
      local row, col = unpack(api.nvim_win_get_cursor(0))
      local typed = api.nvim_get_current_line():sub(#vim.fn.prompt_getprompt(b) + 1, col)
      local word = vim.fn.matchstr(typed, [[\v(\k+|(\k@!\S)+)?\s*$]])
      if word ~= "" then
        api.nvim_buf_set_text(b, row - 1, col - #word, row - 1, col, {})
        api.nvim_win_set_cursor(0, { row, col - #word })
      end
    end, { buffer = b, desc = "Goose: delete the word before the cursor" })
  end
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

---Alt+K in the box: close it and convert the asked-about lines of the file
---with the chat as the instruction.
function M.write(c)
  if c.busy then
    return vim.notify "goose: wait for the answer to finish"
  end
  local talk = api.nvim_buf_get_lines(c.buf, 0, -1, false)
  table.remove(talk) -- the › line being typed
  if not table.concat(talk, ""):match "%S" then
    return vim.notify "goose: ask something first; then Alt+K writes it into the file"
  end
  vim.cmd.stopinsert()
  close(c)
  goose.convert(c.src, c.s, c.e, nil, WRITE:format(table.concat(talk, "\n")))
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
  cfg.footer = " Alt+K writes it into the file "
  cfg.footer_pos = "center"
  c.win = api.nvim_open_win(b, true, cfg)
  vim.wo[c.win].wrap, vim.wo[c.win].linebreak = true, true
  vim.wo[c.win].number, vim.wo[c.win].relativenumber, vim.wo[c.win].signcolumn, vim.wo[c.win].list = false, false, "no", false
  -- The block's tint marks your turn; a cursor-line band would blur it.
  vim.wo[c.win].cursorline = false
  fit(c.win)
  -- Its claude starts now, while the question is typed.
  if goose.use_session and not goose.session(b) then
    goose.start_session(b, SYSTEM, { tools = TOOLS, cwd = root_of(src) })
  end
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
  -- The box is sized and centred for the editor it opened in; refit it when
  -- the editor grows or shrinks (window fullscreen, Neovide resize).
  api.nvim_create_autocmd("VimResized", {
    group = "GooseAsk",
    callback = function()
      for _, c in pairs(chats) do
        if c.win then
          fit(c.win)
        end
      end
    end,
  })
end

return M
