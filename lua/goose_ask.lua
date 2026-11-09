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
-- reads callers, definitions, .mli and dune files itself. Jane Street and
-- OCaml questions go to Thomas's wiki first (the jswiki MCP server,
-- ~/Work/js-wiki, find then read, answers cite its page URLs), the web
-- (WebSearch, WebFetch) only for what the wiki lacks. Each tool call shows
-- as a grey line above the answer ("read lib/x.ml", "wiki: searched ...").
-- Alt+K's claude has no tools, so conversions stay fast.
--
-- Memory: when Thomas states a lasting preference or corrects it, the chat
-- saves one note ("remembered: ...", grey) to goose's memory file through
-- tools/goose/memory.py, which can touch only that file; the chat has no
-- Edit or Write. Every new chat and Alt+K session gets the file in its
-- system prompt (goose.with_memory). :GooseMemory opens the file to edit.
--
-- Slash commands: a message that starts with `/mentor` (M.slash) goes to
-- that Claude Code skill's prompt instead of the chat (`/mentor I'm going to
-- X because Y, any reason not to?` gets the mentor-check verdict). See
-- M.slash; anything else after a `/` is an ordinary question.
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
local WIKI = [[


Jane Street and OCaml: for any question about Jane Street's libraries (Core,
Base, Async, Bonsai, Incremental, expect tests, ppx_* such as ppx_let or
ppx_jane), its OCaml style and conventions, its tools or its culture, or
general OCaml practice, search Thomas's Jane Street wiki first: jswiki `find`
with a few keywords, then `read` the best page or section, and answer from
it, citing the page URLs it gives. `quote` only when exact wording matters.
Use WebSearch or WebFetch only for what the wiki lacks, and say that the wiki
did not cover it. Questions only about this code's own logic need no wiki.]]
local WEB = [[


Use WebSearch or WebFetch for outside facts (library docs, error messages)
the project does not answer.]]
local MEMORY = [[


Memory: `remember` saves one short note that every later chat and code
conversion reads. Save one when the programmer states a lasting preference
("I prefer...", "always...", "never..."), a convention of his projects, or
corrects you; then answer as usual. Never save one-off details of the current
question, guesses, or what the memory already says. `forget` drops a note he
says is wrong or outdated.]]
local TOOLS = "Read,Grep,Glob,WebSearch,WebFetch"

-- Slash commands in the box: `/name text` sends text to a skill's prompt,
-- read from the skill's own file (a Claude Code skill, so the box and Claude
-- Code answer the same way; a missing file shows one line in the box). Each
-- box keeps one claude per skill, beside its chat's (a running chat keeps
-- the prompt it started with), in the project root with Read, Grep, Glob
-- and the wiki: no Edit, Write, web or memory. Its answers sit under a grey
-- line with the skill's name. log = a folder in stdpath('state') whose
-- log.jsonl gets a line per answer (time, source, text, first line). One
-- line per skill.
M.slash = {
  mentor = { name = "mentor-check", prompt = "~/.claude/skills/mentor-check/prompt.md", log = "mentor" },
}

---claude options for a slash command's claude in `root`.
function M.slash_opts(root)
  return goose.claude_opts(root, { tools = "Read,Grep,Glob" })
end

---The skill's prompt, or nil and one line saying what is missing.
local function slash_system(cmd, skill)
  local path = vim.fs.normalize(skill.prompt)
  local f = io.open(path, "r")
  if not f then
    return nil, ("/%s needs %s (the %s skill isn't on this machine)"):format(cmd, vim.fn.fnamemodify(path, ":~"), skill.name)
  end
  local text = f:read "*a"
  f:close()
  return text
end

---The lines the box is about, as context for a slash command ("" if blank).
local function slash_context(src, s, e, root)
  local here = table.concat(api.nvim_buf_get_lines(src, s, e + 1, false), "\n")
  if not here:match "%S" then
    return ""
  end
  local name = api.nvim_buf_get_name(src)
  name = vim.fs.relpath(root, name) or vim.fn.fnamemodify(name, ":~")
  if s == e then
    return ("Code at the cursor, %s line %d (context, may be unrelated):\n%s\n\n"):format(name, s + 1, here)
  end
  return ("Selected code, %s lines %d-%d:\n%s\n\n"):format(name, s + 1, e + 1, here)
end

---Append one answer to stdpath('state')/<skill.log>/log.jsonl.
local function slash_log(skill, text, out)
  if not skill.log then
    return
  end
  local dir = vim.fs.joinpath(vim.fn.stdpath "state", skill.log)
  vim.fn.mkdir(dir, "p")
  local first = vim.trim(((out:match "[^\n]*%S[^\n]*") or ""):gsub("%*", ""))
  local line = vim.json.encode { ts = os.date "!%Y-%m-%dT%H:%M:%SZ", source = "nvim", proposal = text, verdict = first }
  vim.fn.writefile({ line }, vim.fs.joinpath(dir, "log.jsonl"), "a")
end

---The hidden buffer a box's skill claude is keyed by (goose's sessions are
---per buffer; deleting it kills the claude).
local function slash_key(c, cmd)
  c.keys = c.keys or {}
  if not (c.keys[cmd] and api.nvim_buf_is_valid(c.keys[cmd])) then
    c.keys[cmd] = api.nvim_create_buf(false, true)
  end
  return c.keys[cmd]
end

function M.slash_key(c, cmd) -- for tests
  return c.keys and c.keys[cmd]
end

---The chat's system prompt: the rules, the wiki's if present, memory's, and
---the memory file itself.
function M.system()
  return goose.with_memory(SYSTEM .. (goose.has_wiki() and WIKI or WEB) .. MEMORY)
end

---claude options for a chat in `root`: read-only built-in tools, the web,
---the wiki and the memory server (--mcp-config; no other MCP server), all
---permitted up front, since -p denies any tool not allowed.
function M.opts(root)
  return goose.claude_opts(root, { tools = TOOLS, allow = { "WebSearch", "WebFetch" }, memory = true })
end

local root_of, describe = goose.root, goose.describe

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
  -- `/mentor ...`: that skill's prompt, on this box's claude for the skill.
  local cmd, text = q:match "^/(%S+)%s*(.*)$"
  local skill = cmd and M.slash[cmd]
  local system, missing
  if skill then
    system, missing = slash_system(cmd, skill)
    if not missing and text == "" then
      missing = ("type the text after /%s"):format(cmd)
    end
  end
  local reads, answer = (skill and not missing) and { skill.name } or {}, nil
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
  -- update rewrites lines, re-greys, refits the box and redraws. The first
  -- text shows at once, then the newest every frame_ms.
  local timer, dirty
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
    -- view stays where it is. Counted from the view's top line, not read off
    -- the screen, which lags until the next redraw.
    local win = c.win and api.nvim_win_is_valid(c.win) and c.win
    local follow, view
    if win then
      view = api.nvim_win_call(win, function()
        vim.fn.line "w0" -- brings the top line up to date with the cursor (no redraw yet)
        return vim.fn.winsaveview()
      end)
      local last = api.nvim_buf_line_count(cb)
      -- Rows above the › line's text: the shown filler (topfill), then from
      -- the top line's text (start_vcol skips its rows scrolled off) to the
      -- › line's text (end_vcol 0 keeps its tinted row above, not the text).
      local rows = view.topfill
        + api.nvim_win_text_height(win, { start_row = view.topline - 1, start_vcol = 0, end_row = last - 1, end_vcol = 0 }).all
      follow = last <= view.topline or rows < api.nvim_win_get_height(win)
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
  local function tick()
    timer = nil
    if dirty then
      dirty = false
      render()
      timer = vim.defer_fn(tick, M.frame_ms)
    end
  end
  local function show(text)
    answer = text or answer
    dirty = true
    if not timer then
      tick()
    end
  end
  fit(c.win or -1)
  local function done(out, err)
    c.busy = false
    answer = out or ("_goose: %s_"):format(err or "no answer")
    render() -- now, not a frame later; a waiting frame then finds no mark
    pcall(api.nvim_buf_del_extmark, cb, ns, mark)
  end
  local function on_tool(name, input)
    reads[#reads + 1] = describe(name, input, root)
    answer = nil
    show()
  end
  if missing then
    return done(nil, missing)
  end
  if skill then
    local about = slash_context(src, s, e, root)
    -- The code goes along only when it changed since this claude last saw it.
    local function build(S)
      return (S and S.sent == about and "" or about) .. text, about
    end
    return goose.session_send(slash_key(c, cmd), {
      system = system,
      opts = M.slash_opts(root),
      build = build,
      full = function()
        return (build(nil))
      end,
      on_partial = show,
      on_tool = on_tool,
      on_done = function(out, err)
        if out then
          slash_log(skill, text, out)
        end
        done(out, err)
      end,
    })
  end
  -- A live claude keeps the prompt it started with (a changed one would
  -- restart it and lose the conversation); a new one reads the memory now.
  if not goose.session(cb) then
    c.system = M.system()
  end
  goose.session_send(cb, {
    system = c.system,
    opts = M.opts(root),
    build = function(S)
      return goose.question_prompt(S, src, q, s, e, root)
    end,
    full = function()
      return (goose.question_prompt(nil, src, q, s, e, root))
    end,
    on_partial = show,
    on_tool = on_tool,
    on_done = done,
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
  cfg.footer = " Alt+K writes it into the file · /mentor checks a plan "
  cfg.footer_pos = "center"
  c.win = api.nvim_open_win(b, true, cfg)
  vim.wo[c.win].wrap, vim.wo[c.win].linebreak = true, true
  vim.wo[c.win].number, vim.wo[c.win].relativenumber, vim.wo[c.win].signcolumn, vim.wo[c.win].list = false, false, "no", false
  -- The block's tint marks your turn; a cursor-line band would blur it.
  vim.wo[c.win].cursorline = false
  fit(c.win)
  -- Its claude starts now, while the question is typed.
  if goose.use_session and not goose.session(b) then
    c.system = M.system()
    goose.start_session(b, c.system, M.opts(root_of(src)))
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
  vim.api.nvim_create_user_command("GooseMemory", function()
    for _, c in pairs(chats) do
      close(c)
    end
    local file = goose.memory_file()
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.cmd.edit(vim.fn.fnameescape(file))
  end, { desc = "Goose: open the memory file (notes every new chat and Alt+K read)" })
  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = api.nvim_create_augroup("GooseAsk", { clear = true }),
    callback = function(a)
      local c = chats[a.buf]
      if c then
        chats[a.buf] = nil
        close(c)
        pcall(api.nvim_buf_delete, c.buf or -1, { force = true })
        -- Each skill's claude: autocmds don't nest, so goose's BufDelete
        -- never sees these buffers go.
        for _, key in pairs(c.keys or {}) do
          goose.kill_session(key)
          pcall(api.nvim_buf_delete, key, { force = true })
        end
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
