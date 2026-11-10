-- Project rules (goose.with_rules): the project's AGENTS.md / CLAUDE.md
-- reaches every goose system prompt once (Alt+K session and one-shot, the
-- Alt+L chat, /mentor, seconder), never the user's message, never the
-- global ~/.claude/CLAUDE.md; a project without one is unchanged; Alt+K's
-- claude stays tool-free with claude's own settings off. Stub claude.
-- Run: tests/goose/run.sh   (headless, no network, no desktop keys)
local lib = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/lib.lua")
local g = require "goose"
g.setup()
local ask = require "goose_ask"
ask.setup()
local seconder = require "seconder"
local dir = vim.env.GOOSE_TEST_DIR
local log = dir .. "/stub.log"
lib.stub(g, log, "0.02")
g.prewarm = false
g.lsp_wait = 50
g.flash_ms = 50

local check = lib.check
local keys = lib.keys
---How many times `needle` is in `s`.
local function count(s, needle)
  local n, at = 0, 1
  while s do
    local i = s:find(needle, at, true)
    if not i then
      break
    end
    n, at = n + 1, i + #needle
  end
  return n
end
local function once(s)
  return count(s, "RULELINE") == 1 and count(s, "\n<project-rules>\n") == 1 and count(s, "\n</project-rules>") == 1
end
local function wait_idle(buf)
  vim.wait(100)
  return vim.wait(5000, function()
    return g.pending_count(buf) == 0
  end, 20)
end
local function project(name, files)
  local p = dir .. "/" .. name
  vim.fn.mkdir(p .. "/lib", "p")
  vim.fn.writefile({ "(lang dune 3.0)" }, p .. "/dune-project")
  for f, text in pairs(files) do
    vim.fn.writefile(type(text) == "table" and text or { text }, p .. "/" .. f)
  end
  vim.fn.writefile({ "let a = 1", "let b = 2", "let c = 3" }, p .. "/lib/x.ml")
  return p
end

-- A global ~/.claude/CLAUDE.md that must never load.
local home = dir .. "/home"
vim.fn.mkdir(home .. "/.claude", "p")
vim.fn.writefile({ "- GLOBALRULE end with one Habit: line" }, home .. "/.claude/CLAUDE.md")
vim.env.HOME = home
vim.env.CLAUDE_CONFIG_DIR = nil

local RULES = { "# rules for AI agents", "- RULELINE return Or_error rather than raising", "- One prompt makes at most 40 changed lines." }
local proj = project("proj", { ["AGENTS.md"] = RULES })
vim.uv.fs_symlink("AGENTS.md", proj .. "/CLAUDE.md")
local bare = project("bare", {})

-- 1. The loader.
local ok, err = pcall(function()
  local text, names = g.project_rules(proj)
  check("AGENTS.md with CLAUDE.md linked to it: read once", text and count(text, "RULELINE") == 1 and names == "AGENTS.md", vim.inspect { text, names })
  check("no rules file: nothing", g.project_rules(bare) == nil and g.with_rules("SYS", bare, "how") == "SYS")
  local twin = project("twin", { ["AGENTS.md"] = RULES, ["CLAUDE.md"] = RULES })
  text = g.project_rules(twin)
  check("two files with the same text: read once", text and count(text, "RULELINE") == 1, text)
  local pair = project("pair", { ["AGENTS.md"] = "- AGENTRULE", ["CLAUDE.md"] = "- CLAUDERULE" })
  text, names = g.project_rules(pair)
  check(
    "two different files: both, each once, named",
    text and count(text, "AGENTRULE") == 1 and count(text, "CLAUDERULE") == 1 and text:find("From CLAUDE.md:", 1, true) and names == "AGENTS.md, CLAUDE.md",
    vim.inspect { text, names }
  )
  local only_claude = project("onlyclaude", { ["CLAUDE.md"] = RULES })
  text, names = g.project_rules(only_claude)
  check("CLAUDE.md alone is read", text and count(text, "RULELINE") == 1 and names == "CLAUDE.md", names)
  local big = project("big", { ["AGENTS.md"] = vim.split(("RULELINE " .. ("x"):rep(70) .. "\n"):rep(400), "\n") })
  text = g.with_rules("SYS", big, "how")
  check("a big rules file is cut at rules_max", #g.project_rules(big) <= g.rules_max and #text < g.rules_max + 1000, #text)
  check("the global ~/.claude/CLAUDE.md never loads, even as a root's file", g.project_rules(home .. "/.claude") == nil)
  text = g.with_rules("SYS", proj, "HOWTEXT")
  check(
    "the block says follow, never copy into code or comments, and how it applies",
    text:find("Follow the ones that apply here", 1, true)
      and text:find("never copy or quote their lines into code or comments", 1, true)
      and text:find("HOWTEXT", 1, true)
      and vim.endswith(text, "\n</project-rules>"),
    text
  )
end)
check("the loader runs", ok, err)

-- 2. Alt+K, session path.
vim.cmd.edit(proj .. "/lib/x.ml")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
keys "Opseudo q<Esc>"
keys "<M-k>"
wait_idle(buf)
local S = g.session(buf)
local sys = S and S.system or ""
check("Alt+K session: the rules are in its system prompt once", once(sys), sys)
check("Alt+K session: rules about replying never add text to the code", sys:find("they never add text, prose or comments to the answer", 1, true) ~= nil)
check("Alt+K session: no global CLAUDE.md", not sys:find("GLOBALRULE", 1, true))
local msgs = vim.uv.fs_stat(log) and vim.fn.readfile(log) or {}
check("Alt+K: the rules are never in the user's message", #msgs > 0 and not table.concat(msgs, "\n"):find("RULELINE", 1, true), #msgs)
local argv = S and g.cmd(S.system, S.opts) or {}
local function flag(name)
  local i = vim.fn.index(argv, name)
  return i >= 0 and argv[i + 2] or nil
end
check(
  "Alt+K's claude stays tool-free with claude's own settings off",
  flag "--tools" == "" and flag "--setting-sources" == "" and vim.tbl_contains(argv, "--strict-mcp-config") and not vim.tbl_contains(argv, "--mcp-config"),
  vim.inspect(argv)
)

-- 3. Alt+K, one-shot path.
local real_ask = g.ask
local seen
g.use_session = false
g.ask = function(system, prompt, cb)
  seen = { system = system, prompt = prompt }
  vim.defer_fn(function()
    cb "let q = 1"
  end, 20)
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
keys "Opseudo r<Esc>"
keys "<M-k>"
wait_idle(buf)
check("Alt+K one-shot: the rules are in its system prompt once", seen and once(seen.system), seen and seen.system)
check("Alt+K one-shot: not in the prompt", seen and not seen.prompt:find("RULELINE", 1, true))

-- 4. A project without a rules file: no block anywhere.
vim.cmd.edit(bare .. "/lib/x.ml")
local bbuf = vim.api.nvim_get_current_buf()
keys "Opseudo s<Esc>"
keys "<M-k>"
wait_idle(bbuf)
check("no rules file: Alt+K's system prompt has no block", seen and not seen.system:find("project-rules", 1, true), seen and seen.system)
check("no rules file: the chat's prompt is unchanged", ask.system(bare) == ask.system(nil))
check("no rules file: seconder's prompt is unchanged", not seconder.claude(bbuf):find("project-rules", 1, true))
g.ask = real_ask
g.use_session = true

-- 5. Alt+L chat and /mentor.
local prompt = dir .. "/prompt.md"
vim.fn.writefile({ "MENTORPROMPT You are a Jane Street mentor." }, prompt)
ask.slash.mentor.prompt = prompt
vim.cmd.edit(proj .. "/lib/x.ml")
local function chat_text()
  local c = ask.chat(buf)
  return c and c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n") or ""
end
keys "<M-l>what is b<CR>"
vim.wait(3000, function()
  return chat_text():find("second line", 1, true) ~= nil
end, 20)
local c = ask.chat(buf)
local C = c and g.session(c.buf)
check("Alt+L chat: the rules are in its system prompt once", C and once(C.system), C and C.system)
keys "i/mentor VERDICT plan<CR>"
vim.wait(3000, function()
  return chat_text():find("Message: clear.", 1, true) ~= nil
end, 20)
local key = c and ask.slash_key(c, "mentor")
local Mt = key and g.session(key)
check("/mentor: the skill's prompt, then the rules once", Mt and Mt.system:find("^MENTORPROMPT") and once(Mt.system), Mt and Mt.system)

-- 6. Seconder.
local ssys, sopts = seconder.claude(buf)
check("seconder: the rules are in its system prompt once", once(ssys) and sopts.cwd == proj, ssys)

lib.finish "goose rules"
