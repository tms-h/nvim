-- Alt+L slash commands, against the stub claude: `/mentor ...` goes to the
-- mentor-check skill's prompt file on the box's own mentor claude (no Edit
-- or Write) and its verdict is logged; plain questions still go to the chat
-- with Alt+L's flags unchanged; a missing prompt file shows one line.
-- Run: tests/goose/run.sh   (headless, no network, no desktop keys)
local lib = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/lib.lua")
local g = require "goose"
g.setup()
local ask = require "goose_ask"
ask.setup()
local dir = vim.env.GOOSE_TEST_DIR
local log = dir .. "/stub.log"
lib.stub(g, log, "0.02")
g.prewarm = false

local check = lib.check
local keys = lib.keys
local function sent()
  local out = {}
  for _, l in ipairs(vim.uv.fs_stat(log) and vim.fn.readfile(log) or {}) do
    out[#out + 1] = vim.json.decode(l)
  end
  return out
end

local prompt = dir .. "/prompt.md"
vim.fn.writefile({ "MENTORPROMPT You are a Jane Street mentor.", "Start with Sounds good." }, prompt)
ask.slash.mentor.prompt = prompt
local verdicts = vim.fs.joinpath(vim.fn.stdpath "state", "mentor", "log.jsonl")

local proj = dir .. "/proj"
vim.fn.mkdir(proj .. "/lib", "p")
vim.fn.writefile({ "(lang dune 3.0)" }, proj .. "/dune-project")
vim.fn.writefile({ "let a = 1", "let trades = Int.Map.empty", "let c = 3" }, proj .. "/lib/x.ml")
vim.cmd.edit(proj .. "/lib/x.ml")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local function text()
  local c = ask.chat(buf)
  return c and c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n") or ""
end
local function settle(want)
  vim.wait(4000, function()
    return text():find(want, 1, true) ~= nil and not ask.chat(buf).busy
  end, 20)
end

-- 1. /mentor: the mentor prompt from the skill's file, on its own claude.
keys "<M-l>/mentor VERDICT I'm going to key trades by order id because corrections come by id. Any reason not to?<CR>"
settle "Message: clear."
local c = ask.chat(buf)
local T = text()
check(
  "/mentor: the verdict shows in the box under a grey mentor-check line",
  T:find(
    "› /mentor VERDICT I'm going to key trades by order id because corrections come by id. Any reason not to?\n_mentor-check_\nSounds good.\n\nMessage: clear.",
    1,
    true
  ) ~= nil,
  T
)
local note_row = vim.fn.index(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "_mentor-check_")
local grey = vim.tbl_filter(function(m)
  return m[4].hl_group == "GooseAskNote"
end, vim.api.nvim_buf_get_extmarks(c.buf, -1, { note_row, 0 }, { note_row, -1 }, { details = true }))
check("/mentor: the mentor-check line is grey", note_row >= 0 and #grey == 1, note_row)
local key = ask.slash_key(c, "mentor")
local M = key and g.session(key)
check(
  "/mentor: its system prompt is the skill's prompt file",
  M and M.system == table.concat(vim.fn.readfile(prompt), "\n") .. "\n",
  M and M.system
)
check("/mentor: not the chat's claude", M and g.session(c.buf) and M.pid ~= g.session(c.buf).pid)
local argv = M and g.cmd(M.system, M.opts) or {}
local flags = argv[vim.fn.index(argv, "--tools") + 2] .. "," .. (argv[vim.fn.index(argv, "--allowedTools") + 2] or "")
check(
  "/mentor: Read, Grep, Glob and the wiki only: no Edit, Write, web or memory",
  M
    and M.opts.tools == "Read,Grep,Glob"
    and not flags:find "Edit"
    and not flags:find "Write"
    and not flags:find "Web"
    and not flags:find "memory",
  flags
)
check("/mentor: claude runs in the project root", M and M.opts.cwd == proj, M and M.opts.cwd)
local E = sent()
check(
  "/mentor: the message is the cursor's code, then the proposal, no Question",
  E[#E].content:find(
    "Code at the cursor, lib/x.ml line 2 (context, may be unrelated):\nlet trades = Int.Map.empty\n\nVERDICT",
    1,
    true
  )
      == 1
    and not E[#E].content:find("Question:", 1, true),
  E[#E].content
)
local V = vim.uv.fs_stat(verdicts) and vim.fn.readfile(verdicts) or {}
local v = V[#V] and vim.json.decode(V[#V]) or {}
check(
  "/mentor: the verdict is logged to stdpath('state')/mentor/log.jsonl",
  #V == 1
    and v.source == "nvim"
    and v.verdict == "Sounds good."
    and v.proposal:find "^VERDICT I'm going"
    and v.ts:match "^%d+%-%d+%-%d+T",
  vim.inspect(V)
)
check(
  "the footer hints at /mentor",
  vim.inspect(vim.api.nvim_win_get_config(c.win).footer):find("/mentor", 1, true) ~= nil
)

-- 2. A follow-up /mentor reuses its claude and doesn't resend the same code.
local pid = M and M.pid
keys "i/mentor VERDICT the time is recorded in the log<CR>"
settle "the time is recorded in the log\n_mentor-check_\nSounds good."
E = sent()
check("/mentor follow-up: same claude", g.session(key) and g.session(key).pid == pid)
check(
  "/mentor follow-up: the same code isn't sent again",
  E[#E].content == "VERDICT the time is recorded in the log",
  E[#E].content
)

-- 3. A plain question and an unknown slash go to the chat, flags unchanged.
keys "i/foo VERDICT what is this<CR>"
settle "to: /foo VERDICT what is this"
E = sent()
check(
  "an unknown /name is an ordinary question",
  E[#E].content:find("Question: /foo VERDICT what is this", 1, true) ~= nil,
  E[#E].content
)
local A = g.session(c.buf)
check("the chat keeps Alt+L's system prompt", A and A.system == ask.system(proj))
local want = g.cmd(
  ask.system(proj),
  g.claude_opts(
    proj,
    { tools = "Read,Grep,Glob,WebSearch,WebFetch", allow = { "WebSearch", "WebFetch" }, memory = true }
  )
)
check(
  "Alt+L's claude flags are unchanged",
  A and vim.deep_equal(g.cmd(A.system, A.opts), want),
  A and vim.inspect(g.cmd(A.system, A.opts))
)
check("the mentor log has no line for a plain question", #vim.fn.readfile(verdicts) == 2)

-- 4. No prompt file (the skill isn't on this machine): one line, no claude call.
ask.slash.mentor.prompt = dir .. "/missing/prompt.md"
local before = #sent()
keys "i/mentor VERDICT anything<CR>"
settle "isn't on this machine"
T = text()
local tail = vim.split(T:sub((T:find("› /mentor VERDICT anything", 1, true) or 0)), "\n")
check(
  "missing prompt file: one clear line in the box",
  tail[2]
      == ("_goose: /mentor needs %s/missing/prompt.md (the mentor-check skill isn't on this machine)_"):format(
        vim.fn.fnamemodify(dir, ":~")
      )
    and tail[3] == "",
  vim.inspect(tail)
)
check("missing prompt file: no claude call, nothing logged", #sent() == before and #vim.fn.readfile(verdicts) == 2)

-- 5. Wiping the file ends its mentor claude too.
local mpid = g.session(key) and g.session(key).pid
keys "<Esc>" -- leaves typing and closes the box, back in the file
vim.cmd("bwipeout! " .. buf)
local gone = vim.wait(2000, function()
  return mpid and vim.uv.kill(mpid, 0) ~= 0
end, 20)
check(
  "wiping the file ends the mentor claude",
  gone and g.session(key) == nil and not vim.api.nvim_buf_is_valid(key),
  mpid
)

lib.finish "goose slash"
