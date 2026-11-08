-- Goose session tests against a stub claude (tests/goose/stub-claude.py).
-- Run: tests/goose/run.sh   (headless, no network, no desktop keys)
local g = require "goose"
g.setup()
-- ocamlformat (the format checks) from opam, as the editor finds it; without
-- this the format checks failed under a shell whose PATH lacks opam.
require("tools").setup_path()
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local dir = vim.env.GOOSE_TEST_DIR
local log = dir .. "/stub.log"
vim.env.GOOSE_STUB_LOG = log
vim.env.GOOSE_STUB_DELAY = "0.15"
g.session_argv = { "python3", "-I", here .. "/stub-claude.py" }
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
local function entries()
  local out = {}
  if vim.uv.fs_stat(log) then
    for _, l in ipairs(vim.fn.readfile(log)) do
      out[#out + 1] = vim.json.decode(l)
    end
  end
  return out
end
local function alive(pid)
  return pid and vim.uv.kill(pid, 0) == 0
end

-- A 300-line file, so "whole file" and "diff only" differ clearly in size.
local file = dir .. "/big.ml"
local body = {}
for i = 1, 300 do
  body[i] = ("let f%d x = x + %d"):format(i, i)
end
vim.fn.writefile(body, file)
vim.cmd.edit(file)
local buf = vim.api.nvim_get_current_buf()
local filesize = #table.concat(body, "\n")

local function wait_idle()
  vim.wait(100)
  return vim.wait(5000, function()
    return g.pending_count(buf) == 0
  end, 20)
end
local function send_at(row, text)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  keys("O" .. text .. "<Esc>")
  keys "<M-k>"
end

-- 1. Session reused across 3 sends, diff-only after the first.
send_at(10, "pseudo one")
wait_idle()
local S1 = g.session(buf)
local pid1 = S1 and S1.pid
send_at(100, "pseudo two")
wait_idle()
send_at(200, "pseudo three")
wait_idle()
local E = entries()
check("3 sends reach the stub", #E == 3, #E)
check("one process for all 3 sends", E[3] and E[1].pid == E[2].pid and E[2].pid == E[3].pid and E[1].pid == pid1, vim.inspect(vim.tbl_map(function(x) return x.pid end, E)))
check("first message carries the whole file", E[1] and E[1].content:find("Whole file", 1, true) and #E[1].content > filesize, E[1] and #E[1].content)
check("later messages carry only a diff (< 1/10 of the file)", E[3] and #E[2].content < filesize / 10 and #E[3].content < filesize / 10, E[3] and (#E[2].content .. "," .. #E[3].content .. " vs file " .. filesize))
check("diff message names the region and the last answer", E[3] and E[3].content:find("pseudo three", 1, true) and E[3].content:find("let a2 = 2", 1, true), E[3] and E[3].content)
check("answer landed", vim.api.nvim_buf_get_lines(buf, 199, 201, false)[1] == "let a3 = 3", vim.api.nvim_buf_get_lines(buf, 199, 201, false)[1])

-- 2. Preview lines appear mid-stream; buffer untouched until the end.
local edits = 0
vim.api.nvim_buf_attach(buf, false, {
  on_lines = function()
    edits = edits + 1
  end,
})
vim.api.nvim_win_set_cursor(0, { 50, 0 })
keys "Opseudo four<Esc>"
local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
edits = 0
keys "<M-k>"
local pns = vim.api.nvim_get_namespaces().goose_preview
local function ghost()
  local m = vim.api.nvim_buf_get_extmarks(buf, pns, 0, -1, { details = true })
  return m[1] and m[1][4].virt_lines
end
vim.wait(3000, function()
  return ghost() ~= nil
end, 10)
local gl = ghost()
check("ghost lines show mid-stream", gl and gl[1][1][1] == "let a4 = 4" and gl[1][1][2] == "Comment", vim.inspect(gl))
check("buffer unchanged mid-stream", vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), before) and edits == 0, edits)
wait_idle()
check("one buffer change for the whole answer", edits == 1, edits)
check("ghost lines gone after the swap", ghost() == nil)
check("new lines flash", #vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_get_namespaces().goose_flash, 0, -1, {}) == 1)
check("replaced in place", vim.api.nvim_buf_get_lines(buf, 49, 51, false)[2] == "let b4 = 4", vim.inspect(vim.api.nvim_buf_get_lines(buf, 49, 51, false)))
keys "u"
check("one u restores the pseudocode", vim.api.nvim_buf_get_lines(buf, 49, 50, false)[1] == "pseudo four", vim.api.nvim_buf_get_lines(buf, 49, 50, false)[1])

-- 3. An edit inside the region while it writes throws the answer away.
vim.api.nvim_win_set_cursor(0, { 60, 0 })
keys "Opseudo five<Esc>"
keys "<M-k>"
vim.wait(100)
vim.api.nvim_buf_set_lines(buf, 59, 60, false, { "pseudo five edited" })
wait_idle()
check("edited region keeps your text", vim.api.nvim_buf_get_lines(buf, 59, 60, false)[1] == "pseudo five edited")

-- 4. Restart after the threshold (lowered to 2 messages here).
local n0 = #entries()
g.session_max_msgs = 2
local pidA = g.session(buf) and g.session(buf).pid
send_at(70, "pseudo six")
wait_idle()
send_at(80, "pseudo seven")
wait_idle()
E = entries()
local last = E[#E]
check("restart: new process after the threshold", last and last.pid ~= pidA and E[n0 + 1].pid == pidA, vim.inspect(vim.tbl_map(function(x) return x.pid end, E)))
check("restart: whole file again", last and last.content:find("Whole file", 1, true) ~= nil)
check("restart: old process gone", (vim.wait(2000, function() return not alive(pidA) end, 20)))
g.session_max_msgs = 25

-- 5. Fallback when the process dies mid-send: one-shot path, notify once.
local oneshot, notes = 0, {}
g.ask = function(_, prompt, cb)
  oneshot = oneshot + 1
  vim.defer_fn(function()
    cb "let fallback = 1"
  end, 50)
end
local notify = vim.notify
vim.notify = function(m, ...)
  notes[#notes + 1] = m
  return notify(m, ...)
end
send_at(90, "CRASH please")
wait_idle()
check("fallback: one-shot call made", oneshot == 1, oneshot)
check("fallback: its answer lands", vim.api.nvim_buf_get_lines(buf, 89, 90, false)[1] == "let fallback = 1", vim.api.nvim_buf_get_lines(buf, 89, 90, false)[1])
send_at(95, "CRASH again")
wait_idle()
local warns = #vim.tbl_filter(function(m) return m:find("session failed", 1, true) end, notes)
check("fallback: notified once over two failures", warns == 1 and oneshot == 2, warns .. " notes, " .. oneshot .. " calls")
send_at(97, "pseudo eight")
wait_idle()
check("after a failure the next send gets a fresh session", vim.api.nvim_buf_get_lines(buf, 96, 97, false)[1] == "let a1 = 1", vim.api.nvim_buf_get_lines(buf, 96, 97, false)[1])
vim.notify = notify

-- 6. accept_first: the answer waits; Alt+K accepts, Esc drops.
g.accept_first = true
local tick = vim.api.nvim_buf_get_changedtick(buf)
send_at(120, "pseudo nine")
local tick1 = vim.api.nvim_buf_get_changedtick(buf)
wait_idle()
check("accept_first: buffer unchanged when done", vim.api.nvim_buf_get_changedtick(buf) == tick1 and vim.api.nvim_buf_get_lines(buf, 119, 120, false)[1] == "pseudo nine")
check("accept_first: answer waits as ghost lines", ghost() ~= nil)
keys "<M-k>"
check("accept_first: Alt+K accepts", vim.api.nvim_buf_get_lines(buf, 119, 120, false)[1]:match "^let a" ~= nil, vim.api.nvim_buf_get_lines(buf, 119, 120, false)[1])
send_at(130, "pseudo ten")
wait_idle()
keys "<Esc>"
check("accept_first: Esc drops", vim.api.nvim_buf_get_lines(buf, 129, 130, false)[1] == "pseudo ten" and ghost() == nil)
send_at(140, "pseudo eleven")
wait_idle()
keys "u"
check("accept_first: u drops, pseudocode stays", vim.api.nvim_buf_get_lines(buf, 139, 140, false)[1] == "pseudo eleven" and ghost() == nil, vim.api.nvim_buf_get_lines(buf, 139, 140, false)[1])
keys "u"
check("accept_first: the next u is a normal undo again", vim.api.nvim_buf_get_lines(buf, 139, 140, false)[1] ~= "pseudo eleven")
g.accept_first = false

-- 7. Process killed on BufDelete.
local pidB = g.session(buf) and g.session(buf).pid
check("a live session before BufDelete", alive(pidB))
vim.cmd "silent! write"
vim.cmd.enew()
vim.cmd("bdelete! " .. buf)
check("process killed on BufDelete", (vim.wait(2000, function() return not alive(pidB) end, 20)))

-- 8. A new buffer's first send runs on the spare started by the insert, and
-- the answer goes through the formatter in the same undo step.
local fmt = dir .. "/fmt.ml"
vim.fn.writefile({ "let x = 1" }, fmt)
vim.cmd.edit(fmt)
local buf2 = vim.api.nvim_get_current_buf()
vim.bo[buf2].filetype = "ocaml" -- -u NONE: no filetype detection
local function wait_idle2()
  vim.wait(100)
  return vim.wait(5000, function()
    return g.pending_count(buf2) == 0
  end, 20)
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
keys "oUGLY pseudo<Esc>"
local spare = g.spare()
check("spare: a process is up before Alt+K", spare and alive(spare.pid))
keys "<M-k>"
wait_idle2()
check("spare: the send runs on it", spare and g.session(buf2) == spare and g.spare() ~= spare)
local got = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
check("format: the answer is formatted", got[2] == "let u = 1 + 2", vim.inspect(got))
keys "u"
got = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
check("format: one u restores the pseudocode", vim.deep_equal(got, { "let x = 1", "UGLY pseudo" }), vim.inspect(got))

-- 9. While another region is still writing, formatting leaves it alone
-- (ocamlformat would join "UGLY two" onto "let y = 2" above it), and that
-- region's answer still lands.
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "let x = 1", "", "let y = 2" })
local notes2 = {}
local notify2 = vim.notify
vim.notify = function(m, ...)
  notes2[#notes2 + 1] = m
  return notify2(m, ...)
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
keys "oUGLY one<Esc>"
keys "<M-k>"
keys "GoUGLY two<Esc>"
keys "<M-k>"
wait_idle2()
vim.notify = notify2
got = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
local answers = #vim.tbl_filter(function(l)
  return l == "let u = 1 + 2"
end, got)
check("format: a region still writing is left alone", answers == 2 and #notes2 == 0, vim.inspect(got) .. " " .. vim.inspect(notes2))

io.stdout:write(("goose session: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit 1")
