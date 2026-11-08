-- Goose's reach, against the stub claude (tests/goose/stub-claude.py):
-- every typed block goes on Alt+K, answers may change lines outside the
-- block, and Alt+L answers a question without touching the file.
-- Run: tests/goose/run.sh   (headless, no network, no desktop keys)
local g = require "goose"
g.setup()
local ask = require "goose_ask"
ask.setup()
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local dir = vim.env.GOOSE_TEST_DIR
local log = dir .. "/stub.log"
vim.env.GOOSE_STUB_LOG = log
vim.env.GOOSE_STUB_DELAY = "0.02"
g.session_argv = { "python3", "-I", here .. "/stub-claude.py" }
g.prewarm = false
g.lsp_wait = 50
g.flash_ms = 50

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    io.stdout:write("pass  " .. name .. "\n")
  else
    fail = fail + 1
    io.stdout:write("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "") .. "\n")
  end
end
local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "xt", false)
end
local notes = {}
local notify = vim.notify
vim.notify = function(m, ...)
  notes[#notes + 1] = m
  return notify(m, ...)
end

local n = 0
local function open(lines)
  n = n + 1
  local file = ("%s/f%d.ml"):format(dir, n)
  vim.fn.writefile(lines, file)
  vim.cmd.edit(file)
  return vim.api.nvim_get_current_buf()
end
local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function wait_idle(buf)
  vim.wait(100)
  return vim.wait(5000, function()
    return g.pending_count(buf) == 0
  end, 20)
end
local function type_at(row, text)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  keys("O" .. text .. "<Esc>")
end

-- 1. Two places typed (line 2 and line 6): both are the draft, both convert.
local buf = open { "let a = 1", "let b = 2", "let c = 3", "let d = 4", "let e = 5", "let f = 6" }
type_at(2, "pseudo top")
type_at(7, "pseudo bottom")
local blocks = g.draft_blocks(buf)
check(
  "two places typed make two draft blocks",
  #blocks == 2 and blocks[1][1] == 1 and blocks[2][1] == 6,
  vim.inspect(blocks)
)
keys "<M-k>"
wait_idle(buf)
local L = lines(buf)
check("Alt+K converts the first block", L[2]:match "^let a%d" and L[3]:match "^let b%d", vim.inspect(L))
check("Alt+K converts the second block too", L[8]:match "^let a%d" and L[9]:match "^let b%d", vim.inspect(L))
check("nothing typed is left as draft", #g.draft_blocks(buf) == 0)
check("code between the blocks untouched", L[4] == "let b = 2" and L[7] == "let e = 5", vim.inspect(L))

-- 2. Adjacent inserts still merge into one block.
type_at(1, "one")
type_at(2, "two")
check("touching inserts merge into one block", #g.draft_blocks(buf) == 1, vim.inspect(g.draft_blocks(buf)))
keys "<M-k>"
wait_idle(buf)

-- 3. The answer changes a line outside the block; one u undoes both.
buf = open { "let target = 1", "", "let x = 1", "", "let y = 2" }
local before = lines(buf)
type_at(4, "ELSEWHERE bump target")
keys "<M-k>"
wait_idle(buf)
L = lines(buf)
check("outside edit: line 1 changed", L[1] == "let target = 2", vim.inspect(L))
check("outside edit: region replaced", L[4]:match "^let z%d+ = 0$" ~= nil, vim.inspect(L))
check("outside edit: no markers in the file", not table.concat(L, "\n"):find("SEARCH", 1, true), vim.inspect(L))
check(
  "outside edit: message names the line",
  vim.tbl_contains(g.last_elsewhere and g.last_elsewhere.rows or {}, 1),
  vim.inspect(g.last_elsewhere)
)
keys "u"
check(
  "outside edit: one u restores the region and line 1",
  lines(buf)[1] == "let target = 1" and lines(buf)[4] == "ELSEWHERE bump target",
  vim.inspect(lines(buf))
)
keys "u"
check("outside edit: the next u undoes the typing", vim.deep_equal(lines(buf), before), vim.inspect(lines(buf)))

-- 4. An instruction about other lines only: it goes, they change.
buf = open { "let target = 1", "let x = 1" }
type_at(2, "ONLYELSEWHERE make target 2")
keys "<M-k>"
wait_idle(buf)
check(
  "instruction only: target changed, instruction removed",
  vim.deep_equal(lines(buf), { "let target = 2", "let x = 1" }),
  vim.inspect(lines(buf))
)

-- 5. SEARCH lines not in the file: skipped with a warning, region still lands.
buf = open { "let x = 1", "let y = 2" }
notes = {}
type_at(2, "ELSEWHERE but no target")
keys "<M-k>"
wait_idle(buf)
check("missing SEARCH: region still replaced", lines(buf)[2]:match "^let z%d+ = 0$" ~= nil, vim.inspect(lines(buf)))
check("missing SEARCH: warned", #vim.tbl_filter(function(m)
  return m:find("could not find", 1, true)
end, notes) == 1, vim.inspect(notes))

-- 6. split_answer: fenced region, then a block; the fence never lands.
local region, edits =
  g.split_answer "```ocaml\nlet a = 1\n```\n<<<<<<< SEARCH\nlet b = 1\n=======\nlet b = 2\n>>>>>>> REPLACE\n"
check("split_answer: region without fences", vim.deep_equal(region, { "let a = 1" }), vim.inspect(region))
check(
  "split_answer: one edit",
  #edits == 1 and edits[1].search[1] == "let b = 1" and edits[1].replace[1] == "let b = 2",
  vim.inspect(edits)
)

-- 7. Alt+L: a chat box over the code; the question goes to its own claude,
-- running in the project root with read-only tools.
local proj = dir .. "/proj"
vim.fn.mkdir(proj .. "/lib", "p")
vim.fn.writefile({ "(lang dune 3.0)" }, proj .. "/dune-project")
vim.fn.writefile({ "let a = 1", "let b = 2", "let c = 3" }, proj .. "/lib/x.ml")
vim.cmd.edit(proj .. "/lib/x.ml")
-- A memory note, saved before both claudes start: it must reach each
-- one's system prompt.
vim.fn.mkdir(vim.fs.dirname(g.memory_file()), "p")
vim.fn.writefile({ "- MEMNOTE prefer Core's List over Stdlib" }, g.memory_file())
buf = vim.api.nvim_get_current_buf()
type_at(2, "pseudo q")
keys "<M-k>" -- starts this file's Alt+K session
wait_idle(buf)
local pid = g.session(buf) and g.session(buf).pid
before = lines(buf)
local code_win = vim.api.nvim_get_current_win()
local function chat_text()
  local c = ask.chat(buf)
  return c and c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n") or ""
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
keys "<M-l>what is b<CR>"
vim.wait(3000, function()
  return chat_text():find("second line", 1, true) ~= nil
end, 20)
local c = ask.chat(buf)
local cwin = c and c.win
check(
  "Alt+L: a focused popup, not a pane",
  cwin and vim.api.nvim_get_current_win() == cwin and vim.api.nvim_win_get_config(cwin).relative == "editor"
)
check(
  "Alt+L: title names the file and line",
  cwin and vim.inspect(vim.api.nvim_win_get_config(cwin).title):find("line 4", 1, true) ~= nil
)
check("Alt+L: question and answer in the box", chat_text():find("› what is b\n**answer", 1, true) ~= nil, chat_text())
check("Alt+L: the file is unchanged", vim.deep_equal(lines(buf), before), vim.inspect(lines(buf)))
check(
  "the box fits the tinted rows",
  vim.api.nvim_win_get_config(cwin).height == vim.api.nvim_win_text_height(cwin, {}).all,
  ("height %d, text %d"):format(vim.api.nvim_win_get_config(cwin).height, vim.api.nvim_win_text_height(cwin, {}).all)
)
check("the tinted row above the first question shows", vim.api.nvim_win_call(cwin, vim.fn.winsaveview).topfill == 1)
local ask_S = c and g.session(c.buf)
check("Alt+L: its own claude, not Alt+K's", ask_S and ask_S.pid ~= pid and g.session(buf).pid == pid)
check("Alt+L: its claude has read-only tools and the web", ask_S and ask_S.opts and ask_S.opts.tools == "Read,Grep,Glob,WebSearch,WebFetch")
check("memory reaches the chat's system prompt", ask_S and ask_S.system:find("MEMNOTE", 1, true) ~= nil)
check("memory reaches Alt+K's system prompt", g.session(buf).system:find("MEMNOTE", 1, true) ~= nil)
local mcp = ask_S and ask_S.opts.mcp and vim.json.decode(ask_S.opts.mcp).mcpServers or {}
-- The memory server as the chat's claude would start it: it must run and
-- save to the memory file.
local srv = mcp.memory and vim.system(vim.list_extend({ mcp.memory.command }, mcp.memory.args), {
  stdin = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"remember","arguments":{"note":"SRVNOTE"}}}\n',
}):wait()
check(
  "Alt+L: the memory server starts, saves to the memory file, and is allowed",
  srv and srv.code == 0 and vim.fn.readfile(g.memory_file())[2] == "- SRVNOTE" and ask_S.opts.allow:find("mcp__memory", 1, true) ~= nil,
  vim.inspect { ask_S and ask_S.opts, srv }
)
local argv_k = g.cmd(g.session(buf).system, g.session(buf).opts)
check(
  "Alt+K's claude stays tool-free: no tools, no MCP server",
  argv_k[vim.fn.index(argv_k, "--tools") + 2] == "" and not vim.tbl_contains(argv_k, "--mcp-config"),
  vim.inspect(argv_k)
)
local E = {}
for _, l in ipairs(vim.fn.readfile(log)) do
  E[#E + 1] = vim.json.decode(l)
end
check(
  "Alt+L: message names the cursor's line",
  E[#E].content:find("cursor is on line 4", 1, true) ~= nil,
  E[#E].content
)
check("Alt+L: claude runs in the project root", E[#E].cwd == proj, E[#E].cwd)
check("Alt+L: the file is named from the project root", E[#E].content:find("File: lib/x.ml", 1, true) ~= nil)
keys "iand main?<CR>" -- keys() ends typing after each feed; i types at the › line
vim.wait(3000, function()
  return chat_text():find("to: and main?", 1, true) ~= nil
end, 20)
local T = chat_text()
check(
  "follow-up appends below the first answer",
  T:find("to: what is b", 1, true) and T:find("to: what is b", 1, true) < (T:find("› and main?", 1, true) or 0),
  T
)
check(
  "a file it reads shows above the answer",
  T:find("› and main?\n_read bin/main.ml_\n**answer", 1, true) ~= nil,
  T
)
check("text before a tool call is dropped", not T:find("Let me look", 1, true), T)
keys "iWIKI REMEMBER ppx_let?<CR>"
vim.wait(3000, function()
  return chat_text():find("to: WIKI", 1, true) ~= nil and not ask.chat(buf).busy
end, 20)
T = chat_text()
check(
  "wiki searches, reads and a saved note show as grey lines",
  T:find(
    '› WIKI REMEMBER ppx_let?\n_wiki: searched "ppx_let Deferred"_\n_wiki: read ppx-let › How it reads_\n_remembered: Thomas prefers Core\'s List over Stdlib_\n**answer',
    1,
    true
  ) ~= nil,
  T
)
local underlined = vim.tbl_filter(function(m)
  return m[4].hl_group == "GooseDraft"
end, vim.api.nvim_buf_get_extmarks(c.buf, -1, 0, -1, { details = true }))
check("typing in the box underlines nothing (no draft)", #underlined == 0, vim.inspect(underlined))
-- The look copies omp's: each question and the › line sit on a tinted block
-- with a tinted row above and below, answers stay plain, the files read are
-- grey, and the box grows to fit the virtual rows.
local function marks_on(row)
  return vim.api.nvim_buf_get_extmarks(c.buf, -1, { row, 0 }, { row, -1 }, { details = true })
end
local function has(row, key, group)
  for _, m in ipairs(marks_on(row)) do
    if m[4][key] == group then
      return true
    end
  end
  return false
end
local wrong = {}
for i, l in ipairs(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false)) do
  local question = vim.startswith(l, "› ")
  local pads = 0
  for _, m in ipairs(marks_on(i - 1)) do
    for _, v in ipairs(m[4].virt_lines or {}) do
      pads = pads + ((v[1] and v[1][2] == "GooseAskQuestion") and 1 or 0)
    end
  end
  if has(i - 1, "line_hl_group", "GooseAskQuestion") ~= question or pads ~= (question and 2 or 0) then
    wrong[#wrong + 1] = ("%d %q pads %d"):format(i, l, pads)
  end
end
check("questions and the › line are tinted blocks, answers are not", #wrong == 0, table.concat(wrong, "; "))
local read_row = vim.fn.index(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "_read bin/main.ml_")
check("a file it reads is grey", read_row >= 0 and has(read_row, "hl_group", "GooseAskNote"), read_row)
-- Window fullscreen resizes the editor: the box re-centres and takes the new
-- width, growing and shrinking ("the window doesnt auto resize", 2026-11-08).
local cols0, lines0 = vim.o.columns, vim.o.lines
local function fits(cols, rows)
  vim.o.columns, vim.o.lines = cols, rows
  vim.cmd "doautocmd VimResized"
  local w = math.min(math.max(math.min(100, math.floor(cols * 0.6)), math.min(60, cols - 4)), cols - 4)
  local cfg = vim.api.nvim_win_get_config(cwin)
  local ok = cfg.width == w and cfg.col == math.floor((cols - w - 2) / 2) and cfg.row + cfg.height <= rows
  return ok, ("%dx%d: width %d col %d row %d height %d"):format(cols, rows, cfg.width, cfg.col, cfg.row, cfg.height)
end
vim.o.columns, vim.o.lines = 80, 24
vim.cmd "doautocmd VimResized"
check("the box refits when the editor grows", fits(200, 60))
check("the box refits when the editor shrinks", fits(90, 30))
vim.o.columns, vim.o.lines = cols0, lines0
vim.cmd "doautocmd VimResized"
keys "<Esc><Esc>"
check(
  "Esc, Esc closes the box, back in the code",
  not vim.api.nvim_win_is_valid(cwin) and vim.api.nvim_get_current_win() == code_win
)
keys "<M-l>"
c = ask.chat(buf)
check(
  "Alt+L brings the conversation back",
  c.win and vim.api.nvim_win_is_valid(c.win) and chat_text():find("to: and main?", 1, true) ~= nil
)
keys "<Esc>"
vim.api.nvim_set_current_win(code_win)
vim.wait(200)
check("leaving the box closes it", not (c.win and vim.api.nvim_win_is_valid(c.win)))

-- 8. Scrolling while typing: a prompt buffer pins the cursor to the › line in
-- Insert mode, so Ctrl+U must leave typing and scroll the conversation.
vim.api.nvim_set_current_win(code_win)
keys "<M-l>"
c = ask.chat(buf)
local long = {}
for i = 1, 150 do
  long[i] = "old line " .. i
end
vim.api.nvim_buf_set_lines(c.buf, 0, 0, false, long)
vim.api.nvim_win_set_config(c.win, { height = 20 })
vim.api.nvim_win_set_cursor(c.win, { vim.api.nvim_buf_line_count(c.buf), 0 })
local top = vim.fn.getwininfo(c.win)[1].topline
keys "A<C-u>"
check(
  "Ctrl+U while typing scrolls the box up",
  vim.fn.getwininfo(c.win)[1].topline < top,
  ("topline %d -> %d"):format(top, vim.fn.getwininfo(c.win)[1].topline)
)

-- 8b. Ctrl+Backspace deletes the word before the cursor (Neovide sends
-- <C-BS>, a terminal Ctrl+H) and never the › prompt.
local function prompt_line()
  return vim.api.nvim_buf_get_lines(c.buf, -2, -1, false)[1]
end
keys "Aone two.three  <C-BS>"
check("Ctrl+Backspace deletes the last word and its spaces", prompt_line() == "› one two.", prompt_line())
keys "A<C-h><C-BS>"
check("Ctrl+Backspace (Ctrl+H) deletes one word at a time", prompt_line() == "› one ", prompt_line())
keys "A<C-BS><C-BS><C-h>"
check("Ctrl+Backspace stops at the › prompt", prompt_line() == "› ", prompt_line())
keys "<Esc>"

-- 9. Alt+K in the box: the asked-about line becomes code from the chat, the
-- box closes, and one u undoes it.
vim.fn.writefile({ "let a = 1", "let b = 2", "let c = 3" }, proj .. "/lib/y.ml")
vim.cmd.edit(proj .. "/lib/y.ml")
buf = vim.api.nvim_get_current_buf()
before = lines(buf)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
keys "<M-l>rename b to bee<CR>"
vim.wait(3000, function()
  return chat_text():find("second line", 1, true) ~= nil and not ask.chat(buf).busy
end, 20)
cwin = ask.chat(buf).win
keys "<M-k>"
wait_idle(buf)
L = lines(buf)
check("Alt+K in the box closes it", not vim.api.nvim_win_is_valid(cwin))
check(
  "Alt+K in the box rewrites the asked-about line",
  L[1] == "let a = 1" and L[2]:match "^let a%d" and L[3]:match "^let b%d" and L[4] == "let c = 3",
  vim.inspect(L)
)
check(
  "Alt+K in the box saves the file",
  not vim.bo[buf].modified and vim.deep_equal(vim.fn.readfile(proj .. "/lib/y.ml"), L),
  vim.inspect(vim.fn.readfile(proj .. "/lib/y.ml"))
)
E = {}
for _, l in ipairs(vim.fn.readfile(log)) do
  E[#E + 1] = vim.json.decode(l)
end
check(
  "Alt+K in the box sends the chat as the instruction",
  E[#E].content:find("› rename b to bee", 1, true) and E[#E].content:find("the way this chat", 1, true),
  E[#E].content
)
keys "u"
check("Alt+K in the box: one u undoes it", vim.deep_equal(lines(buf), before), vim.inspect(lines(buf)))

-- 10. Saved once the conversion has landed, compile retry included, so the
-- build's errors (dune, read from disk) clear without a :w. A fake language
-- server makes replace() wait for its report; an error in the region then
-- triggers the retry.
local function on_disk(b)
  return vim.fn.readfile(vim.api.nvim_buf_get_name(b))
end
buf = open { "let a = 1", "let b = 2" }
local client = vim.lsp.start({
  name = "fake",
  root_dir = dir,
  cmd = function()
    return {
      request = function(method, _, cb)
        if method == "initialize" then
          cb(nil, { capabilities = {} })
        else
          cb(nil, nil)
        end
        return true, 1
      end,
      notify = function()
        return true
      end,
      is_closing = function()
        return false
      end,
      terminate = function() end,
    }
  end,
}, { bufnr = buf })
vim.wait(2000, function()
  return #vim.lsp.get_clients { bufnr = buf } > 0
end, 20)
g.lsp_wait = 3000
g.last = nil
type_at(2, "pseudo compile")
keys "<M-k>"
vim.wait(5000, function()
  return g.last ~= nil
end, 20)
check("retry: not saved while the compile check waits", vim.bo[buf].modified, vim.inspect(on_disk(buf)))
local diag_ns = vim.api.nvim_create_namespace "test-compile"
vim.diagnostic.set(diag_ns, buf, { { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR, message = "boom" } })
vim.wait(5000, function()
  return g.last.retry and g.pending_count(buf) == 0
end, 20)
vim.wait(200)
check("retry: the fix-up ran", g.last.retry == true, vim.inspect(g.last))
check(
  "retry: the fixed file is saved, no :w",
  not vim.bo[buf].modified and vim.deep_equal(on_disk(buf), lines(buf)),
  vim.inspect(on_disk(buf))
)
keys "u"
check("retry: one u still brings the pseudocode back", lines(buf)[2] == "pseudo compile", vim.inspect(lines(buf)))
-- An error from dune (dune --watch through ocamllsp) is about the saved
-- file, not the new code: it must not send a retry.
vim.diagnostic.reset(diag_ns, buf)
g.last = nil
type_at(1, "pseudo dune")
keys "<M-k>"
vim.wait(5000, function()
  return g.last ~= nil
end, 20)
vim.diagnostic.set(diag_ns, buf, {
  { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "old error", source = "dune" },
})
vim.wait(3000, function()
  return not vim.bo[buf].modified
end, 20)
check("a stale dune error sends no retry", g.last.retry == false and not vim.bo[buf].modified, vim.inspect(g.last))
vim.lsp.get_client_by_id(client):stop(true)
vim.diagnostic.reset(diag_ns, buf)
g.lsp_wait = 50

-- 11. An answer thrown away (the region edited while writing) saves nothing.
buf = open { "let a = 1", "let b = 2" }
type_at(2, "pseudo kept")
keys "<M-k>"
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "pseudo changed" })
wait_idle(buf)
check(
  "a thrown-away answer saves nothing",
  vim.bo[buf].modified and vim.deep_equal(on_disk(buf), { "let a = 1", "let b = 2" }),
  vim.inspect(on_disk(buf))
)

-- 12. A long answer streaming into the Alt+L box (stub "LONG": 120 lines in
-- 360 chunks): the view follows only while the end is in view, and the box
-- updates once per frame, not once per chunk.
vim.env.GOOSE_STUB_DELAY = "0.005" -- read by the box's claude, started on open
vim.fn.writefile({ "let a = 1" }, proj .. "/lib/z.ml")
vim.cmd.edit(proj .. "/lib/z.ml")
buf = vim.api.nvim_get_current_buf()
keys "<M-l>"
c = ask.chat(buf)
local function view()
  local info = vim.fn.getwininfo(c.win)[1]
  return info.topline, info.botline, vim.api.nvim_buf_line_count(c.buf)
end
local tick0 = vim.b[c.buf].changedtick
keys "iLONG please<CR>"
vim.wait(5000, function()
  return vim.api.nvim_buf_line_count(c.buf) > 40
end, 10)
local _, bot, count = view()
check("streaming: the view follows the answer while the end is in view", bot == count, bot .. "/" .. count)
keys "<C-u>"
local top = view()
vim.wait(5000, function()
  return vim.api.nvim_buf_line_count(c.buf) > 70
end, 10)
check("streaming: scrolled up, the view stays put", view() == top, top .. " -> " .. view())
-- Back down to the end, as the wheel does (Ctrl+E drags the cursor along
-- only as far as the view needs): it follows again, cursor anywhere.
vim.api.nvim_win_call(c.win, function()
  for _ = 1, 200 do
    local _, b, n = view()
    if b >= n then
      break
    end
    vim.cmd "normal! \5"
  end
end)
vim.wait(5000, function()
  return vim.api.nvim_buf_line_count(c.buf) > 95
end, 10)
_, bot, count = view()
check("streaming: scrolled back to the end, it follows again", bot == count, bot .. "/" .. count)
keys "<C-u>"
keys "A"
vim.wait(5000, function()
  return not c.busy
end, 20)
_, bot, count = view()
check("streaming: back at the › line, it follows again", bot == count, bot .. "/" .. count)
check(
  "streaming: the box updates once per frame, not per chunk",
  vim.b[c.buf].changedtick - tick0 < 200,
  vim.b[c.buf].changedtick - tick0 .. " changes for 360 chunks"
)
check("streaming: no scroll glide in the box", vim.b[c.buf].minianimate_disable == true)
-- The first streamed text shows at once; only later text waits for a frame.
-- A frame longer than the whole answer (360 chunks, about 2 s) would show
-- nothing before the end without that.
keys "<Esc>"
ask.frame_ms = 3000
keys "<M-l>"
local t_ask = vim.uv.hrtime()
keys "iLONG next<CR>"
vim.wait(4000, function()
  return chat_text():find("› LONG next\nline 0", 1, true) ~= nil
end, 5)
local shown_ms = (vim.uv.hrtime() - t_ask) / 1e6
check("Alt+L: the first text shows without waiting a frame", shown_ms < 1000, ("%d ms"):format(shown_ms))
ask.frame_ms = 40
vim.wait(5000, function()
  return not ask.chat(buf).busy
end, 20)
keys "<Esc><Esc>"

-- 13. Alt+K's ghost lines: one update per frame, not one per streamed token.
buf = open { "let a = 1" }
local preview_ns, previews_set = vim.api.nvim_get_namespaces().goose_preview, 0
local set_extmark = vim.api.nvim_buf_set_extmark
vim.api.nvim_buf_set_extmark = function(b, ns_id, ...)
  if ns_id == preview_ns then
    previews_set = previews_set + 1
  end
  return set_extmark(b, ns_id, ...)
end
type_at(1, "LONGCODE write it")
keys "<M-k>"
wait_idle(buf)
vim.api.nvim_buf_set_extmark = set_extmark
check(
  "Alt+K: ghost lines update once per frame, not per chunk",
  previews_set > 0 and previews_set < 200 and lines(buf)[120] ~= nil,
  previews_set .. " updates for 360 chunks"
)

vim.notify = notify
io.stdout:write(("goose reach: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit 1")
