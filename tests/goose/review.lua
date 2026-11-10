-- Seconder's codebase context: its claude runs in the project root with
-- read-only tools, the wiki and the memory file, and each tool call shows in
-- its status note. Run: tests/goose/run.sh (no network: a fake claude).
local lib = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/lib.lua")
local g, sec = require "goose", require "seconder"
local dir = vim.env.GOOSE_TEST_DIR

local check = lib.check

-- A fake `claude` first on PATH: streams a Read of lib/x.mli, then a review
-- with one CR, as `claude -p --output-format stream-json --verbose` does.
local bin = dir .. "/bin"
vim.fn.mkdir(bin, "p")
vim.fn.writefile({
  "#!/usr/bin/env python3",
  "import json, os, sys",
  "sys.stdin.read()",
  "open(os.environ['FAKE_ARGV'], 'w').write(json.dumps({'argv': sys.argv[1:], 'cwd': os.getcwd()}))",
  "ev = lambda e: print(json.dumps(e), flush=True)",
  "ev({'type': 'system', 'subtype': 'init'})",
  "ev({'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Read', 'input': {'file_path': os.getcwd() + '/lib/x.mli'}}]}})",
  "import time; time.sleep(0.5)",
  "ans = {'verdict': 'crs', 'reason': 'r', 'add': [{'line': 1, 'kind': 'CR', 'text': 'FAKECR', 'rule': None}], 'delete': [], 'reopen': []}",
  "ev({'type': 'result', 'subtype': 'success', 'is_error': False, 'result': json.dumps(ans)})",
}, bin .. "/claude")
vim.fn.setfperm(bin .. "/claude", "rwxr-xr-x")
vim.env.PATH = bin .. ":" .. vim.env.PATH
vim.env.FAKE_ARGV = dir .. "/argv.json"

local proj = dir .. "/proj"
vim.fn.mkdir(proj .. "/lib", "p")
vim.fn.writefile({ "(lang dune 3.0)" }, proj .. "/dune-project")
vim.fn.writefile({ "val get : int array -> int" }, proj .. "/lib/x.mli")
vim.fn.writefile({ "let get a = a.(0)" }, proj .. "/lib/x.ml")
vim.fn.mkdir(vim.fs.dirname(g.memory_file()), "p")
vim.fn.writefile({ "- MEMNOTE prefer Core's List" }, g.memory_file())
vim.cmd.edit(proj .. "/lib/x.ml")
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].commentstring = "(* %s *)"

local system = sec.claude(buf)
check("review prompt: codebase rules and the memory file", system:find("look it up instead of guessing", 1, true) and system:find("MEMNOTE", 1, true), system)

sec.review(buf)
local saw
vim.wait(5000, function()
  saw = saw or (sec.status(buf):find("read lib", 1, true) and sec.status(buf))
  return not vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find "^let"
end, 10)
check("the note shows the file it reads", saw == "seconder reviewing: read lib/x.mli…", saw)
local L = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check("the streamed answer is applied", L[1] == "(* CR claude: FAKECR *)" and L[2] == "let get a = a.(0)", vim.inspect(L))
local run = vim.json.decode(table.concat(vim.fn.readfile(vim.env.FAKE_ARGV), "\n"))
local function after(flag)
  return run.argv[vim.fn.index(run.argv, flag) + 2]
end
check("claude runs in the project root", run.cwd == proj, run.cwd)
check("with read-only tools only", after "--tools" == "Read,Grep,Glob", after "--tools")
local mcp = vim.fn.index(run.argv, "--mcp-config") >= 0 and vim.json.decode(after "--mcp-config").mcpServers or {}
check("no memory server: a review never writes", mcp.memory == nil and not (after "--allowedTools" or ""):find("memory", 1, true))
check(
  "the jswiki server where the wiki exists, and allowed",
  g.has_wiki() == (mcp.jswiki ~= nil) and (not mcp.jswiki or after("--allowedTools"):find("mcp__jswiki", 1, true) ~= nil),
  vim.inspect(run.argv)
)

lib.finish "goose review"
