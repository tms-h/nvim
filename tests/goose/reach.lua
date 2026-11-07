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
check("two places typed make two draft blocks", #blocks == 2 and blocks[1][1] == 1 and blocks[2][1] == 6, vim.inspect(blocks))
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
check("outside edit: message names the line", vim.tbl_contains(g.last_elsewhere and g.last_elsewhere.rows or {}, 1), vim.inspect(g.last_elsewhere))
keys "u"
check("outside edit: one u restores the region and line 1", lines(buf)[1] == "let target = 1" and lines(buf)[4] == "ELSEWHERE bump target", vim.inspect(lines(buf)))
keys "u"
check("outside edit: the next u undoes the typing", vim.deep_equal(lines(buf), before), vim.inspect(lines(buf)))

-- 4. An instruction about other lines only: it goes, they change.
buf = open { "let target = 1", "let x = 1" }
type_at(2, "ONLYELSEWHERE make target 2")
keys "<M-k>"
wait_idle(buf)
check("instruction only: target changed, instruction removed", vim.deep_equal(lines(buf), { "let target = 2", "let x = 1" }), vim.inspect(lines(buf)))

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
local region, edits = g.split_answer "```ocaml\nlet a = 1\n```\n<<<<<<< SEARCH\nlet b = 1\n=======\nlet b = 2\n>>>>>>> REPLACE\n"
check("split_answer: region without fences", vim.deep_equal(region, { "let a = 1" }), vim.inspect(region))
check("split_answer: one edit", #edits == 1 and edits[1].search[1] == "let b = 1" and edits[1].replace[1] == "let b = 2", vim.inspect(edits))

-- 7. Alt+L: a question goes to the file's claude; the answer fills a pane.
buf = open { "let a = 1", "let b = 2", "let c = 3" }
before = lines(buf)
type_at(2, "pseudo q")
keys "<M-k>" -- starts this file's session
wait_idle(buf)
local pid = g.session(buf) and g.session(buf).pid
before = lines(buf)
local answers = { "what is b", "and c?" }
vim.ui.input = function(_, cb)
  cb(table.remove(answers, 1))
end
local code_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 4, 0 })
keys "<M-l>"
local pb
vim.wait(3000, function()
  pb = ask.pane_buf()
  return pb and table.concat(vim.api.nvim_buf_get_lines(pb, 0, -1, false), "\n"):find("second line", 1, true) ~= nil
end, 20)
local P = pb and vim.api.nvim_buf_get_lines(pb, 0, -1, false) or {}
check("Alt+L: question heads the pane", P[1] == "## what is b", vim.inspect(P))
check("Alt+L: answer streamed into the pane", table.concat(P, "\n"):find("to: what is b", 1, true) ~= nil, vim.inspect(P))
check("Alt+L: pane shown, focus stays in the code", pb and vim.fn.bufwinid(pb) ~= -1 and vim.api.nvim_get_current_win() == code_win)
check("Alt+L: the file is unchanged", vim.deep_equal(lines(buf), before), vim.inspect(lines(buf)))
check("Alt+L: same claude as Alt+K for this file", g.session(buf) and g.session(buf).pid == pid)
local E = {}
for _, l in ipairs(vim.fn.readfile(log)) do
  E[#E + 1] = vim.json.decode(l)
end
check("Alt+L: message names the cursor's line", E[#E].content:find("cursor is on line 4", 1, true) ~= nil, E[#E].content)
-- A follow-up from inside the pane is about the same file, appended below.
vim.api.nvim_set_current_win(vim.fn.bufwinid(pb))
keys "<M-l>"
vim.wait(3000, function()
  return table.concat(vim.api.nvim_buf_get_lines(pb, 0, -1, false), "\n"):find("to: and c?", 1, true) ~= nil
end, 20)
P = vim.api.nvim_buf_get_lines(pb, 0, -1, false)
check("follow-up from the pane appends below the first answer", P[1] == "## what is b" and vim.tbl_contains(P, "## and c?"), vim.inspect(P))
check("pane is read-only", not vim.bo[pb].modifiable)

vim.notify = notify
io.stdout:write(("goose reach: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit 1")
