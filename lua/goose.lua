-- Pseudocode to code (John Crepezzi, Signals and Threads ep 31: "type
-- pseudocode... when you exit insert mode, it turns it into real code... it
-- can only edit the area that you typed in").
--
--   Goose ("loosey-goosey mode"): type pseudocode with plain i/a/o and Esc;
--   nothing fires. The lines typed since the last send are the draft (dotted
--   underline), one block per place you typed.
--   Alt+K / Cmd+K (Cursor's inline edit key), :Goose  send every draft block
--     to claude. In a selection, sends the selected lines. The answer may
--     also change lines outside the block when the pseudocode asks for it
--     ("add a field to type t"); they flash and a message says where.
--   While it writes: the region greys out with "writing…" and the answer
--   streams in as grey ghost lines under it; the file itself changes once,
--   when the answer is complete, and the new lines flash. Edit elsewhere
--   freely. An edit inside the region throws the answer away. One `u` brings
--   the pseudocode back.
--
--   :GooseVibe hint|step|full|agent  how much Alt+K writes, by who writes
--     the logic (+ / - step one level, no argument shows it). Global for the
--     session, `vibe:step` in the statusline, step when Neovim opens. A first
--     pseudocode line `hint:`, `step:`, `full:` or `agent:` sets it for that
--     send only (`test:` is not a level: an expect test at every level).
--       hint   you write all the code: no code, the pseudocode stays with
--              `(* hint: ... *)` lines under it (Core functions, shape, edge
--              case), and a CR on a bug you can name an input for nearby.
--              No compile retry.
--       step   you write the logic as pseudocode: translated line for line;
--              anything not spelled out, even a helper you only name, is a
--              typed `failwith "TODO: ..."` stub. At most one CR.
--       full   you say what you want: it writes the logic and the obvious
--              helpers.
--       agent  a one-line ask: a stronger model (agent_model), one-shot in
--              the project root with Read, Grep, Glob and the jswiki, writes
--              a high-quality function and may tidy nearby code in the same
--              file (one undo step, flashed, a message says where). Slower;
--              the note on the region shows what it reads.
--
-- Each buffer keeps one long-lived claude process (stream-json). The first
-- message carries the whole file; later ones carry only a diff since the
-- last message, so a 1000-line file is not resent every Alt+K. A spare
-- process is started when you start typing, so a buffer's first send does
-- not wait for the CLI to start. If the process dies, that send falls back
-- to a one-shot `claude -p`.
--
-- The answer goes through the file's formatter (lsp.format_lines) in the
-- same undo step; a compile error in it gets one retry as soon as the
-- language server reports it. Once every conversion in the file has landed
-- (retry included), the file is saved, so the build's errors clear by
-- themselves.
--
-- Every claude goose starts (Alt+K, the Alt+L chat, seconder) gets the
-- project's AGENTS.md / CLAUDE.md as rules in its system prompt (with_rules).
--
-- Your text is never dropped silently. An answer with no lines for the
-- region removes it only on a first send whose SEARCH/REPLACE edits really
-- change the file (an instruction about other lines); otherwise the text
-- stays and a message says why. An answer that kept the pseudocode on
-- purpose (a CR above it says why it cannot be written) gets no compile
-- retry: the retry used to "fix" it by deleting the line. A half-written
-- line of code (`| c when is_digit`, `let add_token`) counts as pseudocode
-- and is completed in place.
--
-- What claude is told, so Alt+K writes what Space r (seconder) accepts:
--   - The wiki rules seconder reviews with (rubric/wiki-rules.json, this
--     file's language or "any"), minus the review-process ones (REVIEW_ONLY:
--     split the feature, which tests to add), as rules to follow while
--     writing. A missing or broken file means no rules, no error.
--   - OCaml files that use Core (they open Core, or the folder's dune file
--     lists core): Jane Street house style (`open! Core`, `~f`, option /
--     Or_error, print_s / [%message], deriving, variants for closed sets).
--     A pseudocode line starting `test:` becomes a let%expect_test that
--     prints with print_s, its [%expect {||}] always empty for dune runtest
--     to fill.
--   - Stubs (step, or a large piece full does not get described): typed
--     `failwith "TODO: name: job"` with `_`-prefixed parameters; the
--     compile-error retry never fills one in.
--   - The other modules of the same dune directory the file uses (`Token.x`,
--     `open Token`): each one's .mli, else its .ml, interfaces_max bytes in
--     all, plus the directory's dune file. A session sends them in its first
--     message and again only when their text (or the set used) changed.
--   No tool calls below agent: everything is in the prompt, so Alt+K stays
--   fast. hint, step and full share one system prompt (each message names
--   its level), so switching levels keeps the session.
--
-- ask() (one-shot) is shared with seconder.lua.
local M = {}

local ns = vim.api.nvim_create_namespace "goose"

-- Lean CLI: claude's own settings stay off (hooks, plugins, ~/.claude's
-- CLAUDE.md), no MCP, no tools, no session file. Measured 2026-11-06: 3.1 s
-- per call vs 3.8 s for plain `claude -p`. --bare would be faster but needs
-- an API key (OAuth logins fail). The project's own AGENTS.md / CLAUDE.md is
-- read by goose and put in the system prompt (with_rules), not by claude.
M.model = "claude-sonnet-5-5"
-- opts (questions, reviews and the agent vibe): tools = built-in tools
-- ("Read,Grep,..."), mcp = an --mcp-config JSON, allow = tools permitted
-- without asking (-p denies the rest), cwd = the project root, model =
-- instead of M.model; see claude_opts. --strict-mcp-config keeps every
-- other MCP server out.
local function cmd(system, opts)
  opts = opts or {}
  local c = {
    "claude", "-p", "--model", opts.model or M.model,
    "--setting-sources", "", "--strict-mcp-config", "--tools", opts.tools or "",
    "--no-session-persistence", "--disable-slash-commands",
    "--system-prompt", system,
  }
  if opts.mcp then
    vim.list_extend(c, { "--mcp-config", opts.mcp })
  end
  if opts.allow then
    vim.list_extend(c, { "--allowedTools", opts.allow })
  end
  return c
end
M.cmd = cmd -- for tests

-- Memory: Thomas's notes (preferences, conventions, corrections), one `- `
-- line each, in a Markdown file he can edit (:GooseMemory). The Alt+L chat
-- adds notes through tools/goose/memory.py; every new session (chat or
-- Alt+K) gets the file in its system prompt, cut at memory_max bytes. Kept
-- in state, not the repo: an untracked file would stop the startup pull.
M.memory_max = 4000
function M.memory_file()
  return vim.fs.joinpath(vim.fn.stdpath "state", "goose", "memory.md")
end

---`system` plus the memory file, if it has anything in it.
function M.with_memory(system)
  local f = io.open(M.memory_file(), "r")
  local text = f and f:read(M.memory_max) or ""
  if f then
    f:close()
  end
  text = vim.trim(text)
  if text == "" then
    return system
  end
  return system
    .. "\n\nMemory: notes saved from earlier chats with the programmer (Thomas), his preferences and conventions. Follow the ones that apply:\n"
    .. text
end

-- ── Project context: shared by Alt+K, the Alt+L chat and seconder ─────────
local ROOT_MARKERS = { "REVIEW.md", ".git", "dune-project", "Cargo.toml", "package.json", "pyproject.toml", "go.mod" }

---The project root of buf (the nearest folder with .git, dune-project,
---REVIEW.md...), else the file's folder: where claude runs and reads.
function M.root(buf)
  return vim.fs.root(buf, ROOT_MARKERS) or vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
end

-- Project rules: the project's own AGENTS.md and/or CLAUDE.md, in the root
-- above, read here and put in every goose system prompt (Alt+K, the chat,
-- /mentor, seconder) as one marked block, cut at rules_max bytes. claude
-- itself still runs with --setting-sources "", so ~/.claude/CLAUDE.md, hooks
-- and plugins never load; a root that holds the global file skips it.
-- The 2026-11-06 leak this guards against: plain `claude -p` loaded
-- ~/.claude/CLAUDE.md as a user message saying it OVERRIDES any default
-- behaviour, and its "end with one Habit: line" rule added a Habit line after
-- the code in 2 of 5 calls. Here the rules sit in the system prompt under
-- each path's own answer format, the block says its text never goes into
-- code or comments, and `how` says which kinds of rule apply on that path
-- (for Alt+K, rules about how to reply never add text to the code).
M.rules_max = 8000
M.rules_files = { "AGENTS.md", "CLAUDE.md" }

---The rules files in `root`, each once (a link to the other, or the same
---text, counts once): their text cut at rules_max bytes and the names it came
---from ("AGENTS.md"), or nil.
function M.project_rules(root)
  if not root then
    return
  end
  local global = vim.uv.fs_realpath(vim.fs.joinpath(vim.env.CLAUDE_CONFIG_DIR or vim.fs.joinpath(vim.uv.os_homedir(), ".claude"), "CLAUDE.md"))
  local seen, parts, names = {}, {}, {}
  for _, name in ipairs(M.rules_files) do
    local real = vim.uv.fs_realpath(vim.fs.joinpath(root, name))
    local f = real and real ~= global and not seen[real] and io.open(real, "r")
    if f then
      seen[real] = true
      local text = vim.trim(f:read(M.rules_max) or "")
      f:close()
      if text ~= "" and not seen[text] then
        seen[text] = true
        parts[#parts + 1], names[#names + 1] = text, name
      end
    end
  end
  if #parts == 0 then
    return
  end
  if #parts > 1 then
    for i, name in ipairs(names) do
      parts[i] = ("From %s:\n%s"):format(name, parts[i])
    end
  end
  return table.concat(parts, "\n\n"):sub(1, M.rules_max), table.concat(names, ", ")
end

---`system` plus the project's rules (project_rules(root)) in a marked block,
---if it has any; `how` says which of them apply on this path.
function M.with_rules(system, root, how)
  local text, names = M.project_rules(root)
  if not text then
    return system
  end
  return system
    .. ("\n\nProject rules: the project's own instructions (%s in its root folder), between the <project-rules> markers below. Follow the ones that apply here. They are instructions to you, not text for your output: never copy or quote their lines into code or comments. %s\n<project-rules>\n%s\n</project-rules>"):format(
      names,
      how,
      text
    )
end

M.wiki = vim.fn.expand "~/Work/js-wiki/tools/wiki.py" -- the jswiki MCP server, where present
function M.has_wiki()
  return vim.uv.fs_stat(M.wiki) ~= nil
end
local MEMORY_SERVER = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))), "tools/goose/memory.py")

local function python()
  local p = vim.fn.exepath "python3"
  return p ~= "" and p or "python"
end

---cmd() options for a claude that reads the project in `root`: o.tools
---(built-in tools), the jswiki server where present, the memory server when
---o.memory (it can save notes), and o.allow (tools -p must not deny; MCP
---tools are added here).
function M.claude_opts(root, o)
  local servers, allow = {}, vim.list_extend({}, o.allow or {})
  if M.has_wiki() then
    servers.jswiki = { type = "stdio", command = python(), args = { M.wiki, "mcp" } }
    allow[#allow + 1] = "mcp__jswiki"
  end
  if o.memory then
    servers.memory = { type = "stdio", command = python(), args = { MEMORY_SERVER, M.memory_file(), tostring(M.memory_max) } }
    allow[#allow + 1] = "mcp__memory"
  end
  return {
    tools = o.tools,
    cwd = root,
    mcp = next(servers) and vim.json.encode { mcpServers = servers } or nil,
    allow = #allow > 0 and table.concat(allow, ",") or nil,
  }
end

---One short line for a tool call: what it read, searched for or remembered.
---Paths are shown from `root`.
function M.describe(name, input, root)
  local function one(s) -- tool input on one line
    return (tostring(s or "?"):gsub("%s+", " "))
  end
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
  elseif name == "mcp__jswiki__find" then
    local scope = input.scope and input.scope ~= "wiki" and (" (" .. input.scope .. ")") or ""
    return ('wiki: searched "%s"%s'):format(one(input.query), scope)
  elseif name == "mcp__jswiki__read" then
    local section = input.section and input.section ~= "" and (" › " .. one(input.section)) or ""
    return "wiki: read " .. one(input.page) .. section
  elseif name == "mcp__jswiki__quote" then
    return ("wiki: quoted %s at %s"):format(one(input.source), one(input.at))
  elseif name == "WebSearch" then
    return ('web: searched "%s"'):format(one(input.query))
  elseif name == "WebFetch" then
    return "web: read " .. one(input.url)
  elseif name == "mcp__memory__remember" then
    return "remembered: " .. one(input.note)
  elseif name == "mcp__memory__forget" then
    return ('forgot notes with "%s"'):format(one(input.text))
  end
  local server, tool = name:match "^mcp__(.-)__(.+)$"
  return server and (server .. ": " .. tool) or name
end

---Run claude on `prompt` (stdin) with `system`; on_done(text|nil, err) on the
---main loop. opts: see cmd(); with opts.on_tool(name, input) the answer
---streams (stream-json) so each tool call is reported as it starts.
function M.ask(system, prompt, on_done, opts)
  local argv, stdout, result = cmd(system, opts), nil, nil
  if opts and opts.on_tool then
    vim.list_extend(argv, { "--output-format", "stream-json", "--verbose" })
    local acc = ""
    stdout = function(_, data)
      acc = acc .. (data or "")
      for line in acc:gmatch "([^\n]*)\n" do
        local ok, ev = pcall(vim.json.decode, line)
        if ok and type(ev) == "table" and ev.type == "assistant" then
          for _, c in ipairs(vim.tbl_get(ev, "message", "content") or {}) do
            if type(c) == "table" and c.type == "tool_use" then
              vim.schedule(function()
                opts.on_tool(c.name, c.input or {})
              end)
            end
          end
        elseif ok and type(ev) == "table" and ev.type == "result" then
          result = ev
        end
      end
      acc = acc:match "[^\n]*$"
    end
  end
  local ok, err = pcall(vim.system, argv, { stdin = prompt, text = true, cwd = opts and opts.cwd, stdout = stdout }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        on_done(nil, (r.stderr ~= "" and r.stderr or r.stdout or ""):gsub("%s+$", ""))
      elseif not stdout then
        on_done(r.stdout)
      elseif result and not result.is_error and type(result.result) == "string" then
        on_done(result.result)
      else
        on_done(nil, tostring(result and (result.result or result.subtype) or "no result"))
      end
    end)
  end)
  if not ok then
    vim.schedule(function()
      on_done(nil, "claude not found: " .. tostring(err))
    end)
  end
end

-- ── Session: one long-lived claude per buffer ──────────────────────────────
-- Measured 2026-11-07 (Sonnet, lean flags, 300-line file): first text
-- 1.4-1.8 s, whole answer ~2 s on a running process; a process started on
-- the send adds ~0.65 s, hence the spare. Haiku and `--effort low` were no
-- faster (Sonnet does not think here; Haiku does).
M.use_session = true -- false: every send is a one-shot `claude -p`
M.session_max_tokens = 60000 -- restart (whole file again) past this history
M.session_max_msgs = 25 -- ...or after this many messages
M.session_argv = nil -- tests: replace the claude command line
M.prewarm = true -- keep one idle claude (~190 MB) ready for the next session

local sessions = {} -- sessions[buf] = session table, see spawn()
local spare -- an idle session no buffer owns yet
local warned = false

function M.session(buf) -- for tests and measurement
  return sessions[buf]
end
function M.spare() -- for tests
  return spare
end

local function kill(S)
  if sessions[S.buf] == S then
    sessions[S.buf] = nil
  end
  S.dead = true
  pcall(S.job.kill, S.job, 15)
end
function M.kill_session(buf)
  if sessions[buf] then
    kill(sessions[buf])
  end
end

local pump, warm

-- A send the session cannot finish goes to the one-shot path; notify once.
local function fall_back(item, why)
  if not warned then
    warned = true
    vim.notify("goose: claude session failed (" .. why .. "); using a one-shot call", vim.log.levels.WARN)
  end
  local full = item.full()
  if not full then
    return item.on_done(nil, "region gone")
  end
  M.ask(item.system, full, item.on_done, item.opts)
end

local function on_event(S, ev)
  local cur = S.cur
  if ev.type == "stream_event" and cur then
    local d = ev.event and ev.event.delta
    if d and d.type == "text_delta" and d.text then
      cur.text = cur.text .. d.text
      if cur.on_partial then
        cur.on_partial(cur.text)
      end
    end
  elseif ev.type == "assistant" and cur then
    -- A tool call (questions read the project): the text so far was a
    -- preamble; the answer starts after it.
    for _, c in ipairs(vim.tbl_get(ev, "message", "content") or {}) do
      if type(c) == "table" and c.type == "tool_use" then
        cur.text = ""
        if cur.on_tool then
          cur.on_tool(c.name, c.input or {})
        end
      end
    end
  elseif ev.type == "result" and cur then
    S.cur = nil
    local u = ev.usage or {}
    -- Context size of this turn = the history the next message re-reads.
    S.tokens = (u.input_tokens or 0) + (u.cache_creation_input_tokens or 0) + (u.cache_read_input_tokens or 0) + (u.output_tokens or 0)
    M.last_usage = {
      input = u.input_tokens or 0,
      cache_write = u.cache_creation_input_tokens or 0,
      cache_read = u.cache_read_input_tokens or 0,
      output = u.output_tokens or 0,
      prompt_chars = #cur.prompt,
    }
    if ev.is_error or (ev.subtype and ev.subtype ~= "success") then
      kill(S)
      fall_back(cur, tostring(ev.result or ev.subtype))
    else
      cur.on_done(ev.result or cur.text)
    end
    if not S.dead and (S.tokens >= M.session_max_tokens or S.msgs >= M.session_max_msgs) then
      kill(S) -- the next send starts fresh with the whole file...
      warm(S.system) -- ...on a process started now
    end
    if S.dead then
      local q = S.queue
      S.queue = {}
      for _, item in ipairs(q) do
        M.session_send(S.buf, item)
      end
    else
      pump(S)
    end
  end
end

local function on_stdout(S, data)
  S.acc = S.acc .. data
  while true do
    local nl = S.acc:find("\n", 1, true)
    if not nl then
      return
    end
    local line = S.acc:sub(1, nl - 1)
    S.acc = S.acc:sub(nl + 1)
    local ok, ev = pcall(vim.json.decode, line)
    if ok and type(ev) == "table" then
      on_event(S, ev)
    end
  end
end

local function on_exit(S, r)
  if sessions[S.buf] == S then
    sessions[S.buf] = nil
  end
  local on_purpose = S.dead
  S.dead = true
  local items = S.queue
  S.queue = {}
  if S.cur then
    table.insert(items, 1, S.cur)
    S.cur = nil
  end
  local why = ("exit %s%s"):format(tostring(r.code), S.err ~= "" and (": " .. S.err:gsub("%s+$", ""):sub(1, 120)) or "")
  for _, item in ipairs(items) do
    if on_purpose then
      M.session_send(S.buf, item) -- restarted on purpose: a fresh session
    else
      fall_back(item, why)
    end
  end
end

local function argv(system, opts)
  if M.session_argv then
    return M.session_argv
  end
  local c = cmd(system, opts)
  vim.list_extend(c, { "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages" })
  return c
end

local function spawn(system, opts)
  local S = { system = system, opts = opts, queue = {}, msgs = 0, tokens = 0, acc = "", err = "" }
  local ok, job = pcall(vim.system, argv(system, opts), {
    cwd = opts and opts.cwd,
    stdin = true,
    stdout = function(_, data)
      if data then
        vim.schedule(function()
          on_stdout(S, data)
        end)
      end
    end,
    stderr = function(_, data)
      if data then
        S.err = (S.err .. data):sub(-2000)
      end
    end,
  }, function(r)
    vim.schedule(function()
      on_exit(S, r)
    end)
  end)
  if not ok then
    return nil, tostring(job)
  end
  S.job, S.pid = job, job.pid
  return S
end

---Have a spare process running for the next session that starts. A spare
---started with another system prompt (the memory or the project's rules
---changed, or a file of another project) is replaced.
warm = function(system)
  if spare and not spare.dead and spare.system ~= system then
    kill(spare)
  end
  if M.use_session and M.prewarm and not (spare and not spare.dead) then
    spare = spawn(system)
  end
end

---buf's session: the spare if one is running (goose's own sessions only),
---else a new process.
local function start_session(buf, system, opts)
  local S, err = nil, nil
  if not opts and spare and not spare.dead and spare.system == system then
    S, spare = spare, nil
  end
  if not S then
    S, err = spawn(system, opts)
    if not S then
      return nil, err
    end
  end
  S.buf = buf
  sessions[buf] = S
  return S
end
M.start_session = start_session

pump = function(S)
  if S.cur or S.dead then
    return
  end
  local item = table.remove(S.queue, 1)
  if not item then
    return
  end
  local prompt, sent = item.build(S)
  if not prompt then
    item.on_done(nil, "region gone")
    return pump(S)
  end
  item.text, item.prompt = "", prompt
  S.cur = item
  S.msgs = S.msgs + 1
  S.sent = sent
  local msg = vim.json.encode { type = "user", message = { role = "user", content = prompt } }
  local ok, err = pcall(S.job.write, S.job, msg .. "\n")
  if not ok then
    S.cur = nil
    kill(S)
    fall_back(item, "write failed: " .. tostring(err))
  end
end

---Queue `item` on buf's session, starting one if needed. item = {
---  system, opts (cmd()), build(S) -> prompt, file text (nil prompt = region
---  gone), full() -> one-shot prompt, on_partial(text), on_tool(name, input),
---  on_done(text|nil, err) }.
function M.session_send(buf, item)
  if not vim.api.nvim_buf_is_valid(buf) then
    return item.on_done(nil, "buffer closed")
  end
  local S = sessions[buf]
  if S and S.system ~= item.system then
    kill(S)
    S = nil
  end
  if not S then
    local err
    S, err = start_session(buf, item.system, item.opts)
    if not S then
      return fall_back(item, err)
    end
  end
  table.insert(S.queue, item)
  pump(S)
end

---Drop ``` fences and trailing blank lines from model output.
function M.strip_fences(text)
  local lines = vim.split(text:gsub("\r", ""), "\n", { plain = true })
  if lines[1] and lines[1]:match "^%s*```" then
    table.remove(lines, 1)
    for i = #lines, 1, -1 do
      if lines[i]:match "^%s*```%s*$" then
        for _ = i, #lines do
          table.remove(lines)
        end
        break
      end
    end
  end
  while #lines > 0 and lines[#lines]:match "^%s*$" do
    table.remove(lines)
  end
  return lines
end

local SEARCH, SPLIT, REPLACE = "^%s*<<<<<<<+%s*SEARCH%s*$", "^%s*=======+%s*$", "^%s*>>>>>>>+%s*REPLACE%s*$"

---Model output -> the region's new lines, and the changes outside it
---({ search = lines, replace = lines }, from SEARCH/REPLACE blocks).
function M.split_answer(text)
  local lines = vim.split(text:gsub("\r", ""), "\n", { plain = true })
  local cut = #lines + 1
  for i, l in ipairs(lines) do
    if l:match(SEARCH) then
      cut = i
      break
    end
  end
  local region = M.strip_fences(table.concat(vim.list_slice(lines, 1, cut - 1), "\n"))
  local edits, cur, side = {}, nil, nil
  for i = cut, #lines do
    local l = lines[i]
    if l:match(SEARCH) then
      cur, side = { search = {}, replace = {} }, "search"
    elseif cur and side == "search" and l:match(SPLIT) then
      side = "replace"
    elseif cur and side == "replace" and l:match(REPLACE) then
      edits[#edits + 1], cur = cur, nil
    elseif cur then
      table.insert(cur[side], l)
    end
  end
  return region, edits, cut <= #lines
end

---The other half of an OCaml pair (foo.ml <-> foo.mli), if it exists.
function M.sibling(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local other = name:match "%.mli$" and name:sub(1, -2) or name:match "%.ml$" and name .. "i"
  if other and vim.uv.fs_stat(other) then
    return other, table.concat(vim.fn.readfile(other), "\n")
  end
end

local SYSTEM = [[You turn the programmer's pseudocode into real code, in place. How much
you write is set by the vibe level each message names (see "Vibe levels").
Rules:
- Implement the behaviour written. You may use better idiom or helpers that
  already exist in the file.
- If a different design would change behaviour (for example the written
  version fails on some input), still write their version, and add ONE comment
  line above it: `(* CR claude: <concrete failing input and what happens> *)`.
  Use CR only when you can name an input that breaks it. Use
  `(* CR-soon claude: ... *)` for "works but there is a clearly better way".
  Nothing for taste. At most one CR comment in total.
- If the pseudocode cannot work as written (contradiction, unknown type),
  output the pseudocode lines unchanged with one CR comment above saying why.
- A stub, where the level calls for one: typed from how the code uses it,
  each parameter prefixed with `_`, at the top of the region's output:
  `let scan_token (_source : string) (_pos : int) : token option * int =
     failwith "TODO: scan_token: <its job in a few words>"`.
  Other parts you cannot write: `failwith "TODO: ..."`.
- A half-written line of code (`| c when is_digit`, `let add_token`) is
  pseudocode too: complete it in place from the code around it (the match it
  sits in, the types in use). Never answer it with nothing.
- Write the marked region. Change lines outside it only when the pseudocode
  asks for it ("also add a field to type t", "rename x everywhere", "open Core
  at the top") or the region cannot compile without it (a new record field, a
  missing `rec`). Never fill a `failwith "TODO"` hole outside the region, even
  one right next to it; the region itself is always yours to write.
- Keep the region's indentation. Use the file's language and comment syntax.
- Output the region's replacement lines first: no fences, no prose. Output no
  region lines only when the pseudocode explicitly asks for changes elsewhere
  and for nothing in place ("add a field x to type t"); the instruction is
  then deleted.
- Then one block per change outside the region, nothing for no changes:
<<<<<<< SEARCH
exact current lines of the file, enough to be unique
=======
what they become
>>>>>>> REPLACE]]

-- ── Vibe: how much Alt+K writes (:GooseVibe) ───────────────────────────────
-- One question splits the levels: who writes the logic? hint: you write all
-- the code; step: you write the logic as pseudocode, goose translates it;
-- full: you say what you want, goose writes the logic; agent: a one-line
-- ask, goose writes it well and may tidy nearby code, with tools. hint, step
-- and full share one system prompt (each message names its level), so the
-- session survives a switch; agent is a one-shot call of its own.
M.VIBES = { "hint", "step", "full", "agent" }
M.vibe = "step" -- the level for every send; :GooseVibe changes it
M.agent_model = "claude-opus-5-5" -- agent only; the others stay on M.model
M.agent_tools = "Read,Grep,Glob"

local VIBE = [[Vibe levels: who writes the logic. Each message names one.
- hint: the programmer writes all the code. Write NO code. Your region
  lines are only a few comment lines, each starting `(* hint:`: the Core
  functions to look at, the shape of the code, the edge case to watch for
  (a `test:` line: how to write that expect test). They go under the
  region, whose lines stay as they are: do not repeat them. If code near the
  region has a bug you can name a failing input for, put one CR comment
  above that code with a SEARCH/REPLACE block that adds only the comment
  line.
- step: the programmer writes the logic as pseudocode; translate exactly
  that, line for line, plus the glue it needs to compile. Keep their logic
  even where it is wrong: a CR above it names the failing input; do not fix
  it. Anything it does not spell out, including a function it only names
  (or marks "stub" or "later"), is a stub. At most one CR, on a concrete bug
  in what they wrote: the region, or code of theirs it calls (a SEARCH/REPLACE
  block that adds only the comment line).
- full: the programmer says what they want; write the logic, including the
  obvious helpers it needs, as real code. Stub only a large piece that is
  named but not described.
At hint, step and full, a bug in code outside the region gets a CR comment,
never a fix: changing their other code is only for the agent level.
A first region line `hint:`, `step:` or `full:` only sets the level for this
message; it is not pseudocode. `test:` is not a level: it is an expect test
at every level.]]

-- The agent's own section; it replaces VIBE in a one-shot call that can read
-- the project.
local AGENT = [[Vibe level: agent. The programmer gives a short ask ("write
scan_number"; a first line `agent:` is part of the ask). Write a complete,
high-quality implementation: real helpers, no stubs unless the ask is far
bigger than one function. At this level you may also tidy code near the
region in this same file (dead code, duplication, wrong idioms, unclear
names, a bug you can name an input for) with SEARCH/REPLACE blocks; never
another file, and never behaviour the ask did not touch.
You run in the project's root folder with Read, Grep and Glob: read the
.mli, callers and conventions you need before writing, and only those.]]
local AGENT_WIKI = [[
For a Jane Street idiom you are unsure of, check Thomas's wiki (jswiki find,
then read).]]
local AGENT_END = [[Your final message is only the answer in the format
above: region lines, then SEARCH/REPLACE blocks. No prose about what you
read or why.]]

---The level a send asks for: a first non-blank line `hint:`, `step:`,
---`full:` or `agent:` overrides M.vibe for that send.
function M.vibe_of(lines)
  for _, l in ipairs(lines) do
    if l:match "%S" then
      local word = l:match "^%s*(%a+):"
      return word and vim.tbl_contains(M.VIBES, word) and word or M.vibe
    end
  end
  return M.vibe
end

---:GooseVibe [hint|step|full|agent|+|-]: set, step or show the level.
function M.set_vibe(arg)
  arg = vim.trim(arg or "")
  local i = vim.fn.index(M.VIBES, M.vibe) + 1
  if arg == "+" or arg == "-" then
    M.vibe = M.VIBES[math.max(1, math.min(#M.VIBES, i + (arg == "+" and 1 or -1)))]
  elseif vim.tbl_contains(M.VIBES, arg) then
    M.vibe = arg
  elseif arg ~= "" then
    return vim.notify("goose: vibe is one of " .. table.concat(M.VIBES, ", ") .. ", + or -", vim.log.levels.ERROR)
  end
  vim.cmd.redrawstatus()
  vim.notify("goose: vibe " .. M.vibe)
end

-- OCaml files that use Core (uses_core): Jane Street house style and expect
-- tests. What the wiki rules below already say (poly compare, _exn,
-- structured errors, illegal states) is not repeated here. Lua decides
-- whether a file uses Core: asked to, the model explained its choice in
-- prose at the top of the answer.
local OCAML = [[OCaml house style (Jane Street, Core); this file uses Core:
- Keep `open! Core` as the first line; add it if missing.
- Core's labelled arguments: `List.map xs ~f:(fun x -> ...)`,
  `List.fold xs ~init ~f`, `String.concat ~sep`.
- Ordinary failure (not found, bad input) returns an option or `Or_error.t`.
- Output and error text come from values: `print_s [%sexp (x : t)]`,
  `Or_error.error_s [%message "unexpected char" (c : char) (line : int)]`,
  `Error.create`; no Printf or sprintf strings. The type named in [%sexp]
  needs a sexp_of in scope: name the type that derives sexp, not a plain
  alias of it.
- New types get `[@@deriving sexp, compare, equal]` when they are printed,
  compared or put in maps.
- A closed set of cases is a variant, never a string or int. Use the types
  the project already has (shown under "Other modules") over new ones.
- A pseudocode line starting `test:` is an expect test:
  `let%expect_test "<short name>" =` then code that runs it and prints with
  `print_s [%sexp (... : type)]`, then `[%expect {||}]`. Every [%expect] stays
  empty, exactly `[%expect {||}]`: never write the output you expect;
  `dune runtest` fills it in.]]

-- Wiki rules about reviewing, not writing (splitting features, which tests a
-- change needs): seconder raises them, Alt+K does not follow them.
local REVIEW_ONLY = {
  ["split-refactor"] = true,
  ["pin-bug-with-test"] = true,
  ["test-shows-behaviour"] = true,
  ["counterfactual-expect"] = true,
}

---The wiki rules to follow while writing buf, as a system-prompt section:
---seconder's (rubric/wiki-rules.json, buf's language or "any") minus
---REVIEW_ONLY. nil when there are none (a missing or broken file).
local function write_rules(buf)
  -- seconder requires goose, so it is loaded here, not at the top.
  local ok, sec = pcall(require, "seconder")
  local ok2, rules = false, nil
  if ok then
    ok2, rules = pcall(sec.rules, buf)
  end
  local out = {}
  for _, r in ipairs(ok2 and rules or {}) do
    if not REVIEW_ONLY[r.id] then
      local when = type(r.when) == "string" and r.when ~= "" and (" When: " .. r.when) or ""
      out[#out + 1] = "- " .. r.rule .. when
    end
  end
  if #out > 0 then
    return "Jane Street rules (from Thomas's wiki, the ones his reviewer checks). Follow them in the code you write; they never widen which lines you may change:\n"
      .. table.concat(out, "\n")
  end
end

local function is_ocaml(buf)
  local ft = vim.bo[buf].filetype
  return ft == "ocaml" or ft == "ocamlinterface" or vim.api.nvim_buf_get_name(buf):match "%.mli?$" ~= nil
end

-- ── Project interfaces: other modules of the same dune directory ───────────
M.interfaces_max = 8000 -- bytes of other modules' code per message, at most

---The file's text: the buffer's lines when it is loaded (maybe unsaved),
---else the file on disk.
local function file_text(path)
  local b = vim.fn.bufnr(path)
  if b > 0 and vim.api.nvim_buf_is_loaded(b) then
    return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

---Does `text` use module `m` (`M.x`, `open M`, `include M`, `module X = M`)?
local function uses(text, m)
  return text:find("%f[%w_']" .. m .. "%s*%.")
    or text:find("open!?%s+" .. m .. "%f[^%w_']")
    or text:find("include%s+" .. m .. "%f[^%w_']")
    or text:find("=%s*" .. m .. "%f[^%w_'.]")
end

---The other modules of buf's directory (an OCaml file's dune library) that
---buf uses, each as its .mli or, without one, its .ml, sorted by name and
---cut at interfaces_max bytes in all; then the directory's dune file. One
---prompt section, nil when buf uses none.
function M.interfaces(buf)
  if not is_ocaml(buf) then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local dir, own = vim.fs.dirname(name), vim.fs.basename(name):gsub("%.mli?$", "")
  local files = {} -- files[module base] = "foo.mli" or "foo.ml"
  for f, kind in vim.fs.dir(dir) do
    local base, ext = f:match "^([%w_]+)%.(mli?)$"
    if kind == "file" and base and base ~= own and (ext == "mli" or not files[base]) then
      files[base] = f
    end
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local bases = vim.tbl_keys(files)
  table.sort(bases)
  local parts, left = {}, M.interfaces_max
  for _, base in ipairs(bases) do
    if left > 0 and uses(text, base:sub(1, 1):upper() .. base:sub(2)) then
      local body = file_text(vim.fs.joinpath(dir, files[base]))
      if body then
        if #body > left then
          body = body:sub(1, left) .. "\n(… cut)"
        end
        left = left - #body
        parts[#parts + 1] = files[base] .. ":\n" .. body
      end
    end
  end
  if #parts == 0 then
    return
  end
  local dune = file_text(vim.fs.joinpath(dir, "dune"))
  if dune then
    parts[#parts + 1] = "dune:\n" .. dune:sub(1, 1000)
  end
  return "Other modules this file uses (same dune directory; use their real constructors, fields and functions):\n\n"
    .. table.concat(parts, "\n\n")
end

---The last part of a conversion message: fix errors, or the vibe level and
---then an instruction (Alt+K in the Alt+L chat box) or "convert the
---pseudocode".
local function task(errors, instruction, level)
  if errors then
    return "Your last answer for the region (shown above) gave these compiler errors; fix them without implementing any `failwith \"TODO\"` stub and without deleting the region's code (a missing definition goes in as a stub):\n"
      .. errors
  end
  local default = level == "hint" and "Write no code: output only your hint comments; the region's lines stay."
    or level == "agent" and "Do what the region asks."
    or "Rewrite the region's pseudocode as code."
  return (level and ("Vibe level: " .. level .. ". ") or "") .. (instruction or default)
end

local function prompt_for(buf, s, e, lines, errors, instruction, level)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = table.concat(vim.list_slice(all, 1, s), "\n")
  local after = table.concat(vim.list_slice(all, e + 2), "\n")
  local name = vim.api.nvim_buf_get_name(buf)
  -- The agent reads files from the project root: give it that path.
  local path = level == "agent" and vim.fs.relpath and vim.fs.relpath(M.root(buf), name) or vim.fn.fnamemodify(name, ":~:.")
  local parts = { ("File: %s (filetype %s)"):format(path, vim.bo[buf].filetype) }
  local sib, text = M.sibling(buf)
  if sib then
    parts[#parts + 1] = ("Matching %s:\n%s"):format(vim.fn.fnamemodify(sib, ":t"), text)
  end
  local ifaces = M.interfaces(buf)
  if ifaces then
    parts[#parts + 1] = ifaces
  end
  parts[#parts + 1] = "Whole file, region marked:\n" .. before .. "\n<<<REGION\n" .. table.concat(lines, "\n") .. "\nREGION>>>\n" .. after
  parts[#parts + 1] = task(errors, instruction, level)
  return table.concat(parts, "\n\n")
end

-- How later session messages look; the session's system prompt ends with it.
local SESSION = [[This is a running session on one file. The first message gives the whole
file. Each later message gives only a unified diff of the file since the
previous message (your earlier answers appear in it only if they were
applied), then the new region with its line numbers. Keep your picture of
the file up to date from the diffs. Other modules the file uses are sent
again only when they changed. Each answer replaces the current region
(plus its SEARCH/REPLACE blocks).]]

-- How the project's rules apply to a conversion (with_rules): the answer is
-- only code, so rules about replying cannot add text to it.
local CONVERT_RULES = [[Here your whole answer is code in the format above, and no rule changes
that format. Rules about code (style, idioms, libraries, error handling)
shape the code you write. Rules about how to reply or work (ask questions
first, answer with a plan, a split or a summary, end with a note) do not
apply here: they never add text, prose or comments to the answer. Never add
a comment that only says a rule was followed. If a rule rules out writing
the region as asked (too big, say), output the region unchanged with one CR
comment above it, saying why in a few words of your own.]]

---Does buf's OCaml use Core: it opens Core, or its directory's dune file
---lists core (a library, a test or an executable)?
local function uses_core(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if text:find "open!?%s+Core%f[^%w_']" or text:find "%f[%w_]Core%." then
    return true
  end
  local dune = file_text(vim.fs.joinpath(vim.fs.dirname(vim.api.nvim_buf_get_name(buf)), "dune"))
  return dune ~= nil and dune:find "%f[%w_]core%f[^%w_]" ~= nil
end

---Alt+K's system prompt for buf: SYSTEM, the vibe levels (or, for `agent`,
---the agent's section), the house style (OCaml files that use Core), the
---wiki rules for buf's language, the project's rules (with_rules), SESSION
---for a session, then the memory file.
local function system_for(buf, session, agent)
  local parts = { SYSTEM, agent and (AGENT .. (M.has_wiki() and AGENT_WIKI or "")) or VIBE }
  if is_ocaml(buf) and uses_core(buf) then
    parts[#parts + 1] = OCAML
  end
  parts[#parts + 1] = write_rules(buf)
  parts = { M.with_rules(table.concat(parts, "\n\n"), M.root(buf), CONVERT_RULES) }
  if session then
    parts[#parts + 1] = SESSION
  end
  if agent then
    parts[#parts + 1] = AGENT_END
  end
  return M.with_memory(table.concat(parts, "\n\n"))
end
M.system_for = system_for -- for tests

local text_diff = (vim.text and vim.text.diff) or vim.diff

---Session message for the region: the whole file the first time, after
---that a diff since the last message plus the region. Returns prompt, file.
local function session_prompt(S, buf, s, e, lines, errors, instruction, level)
  local file = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  -- Other modules go in the first message, then again whenever their text
  -- (or which ones the file uses) changed.
  local ifaces, last = M.interfaces(buf) or "", S.ifaces
  S.ifaces = ifaces
  if not S.sent then
    return prompt_for(buf, s, e, lines, errors, instruction, level), file
  end
  local d = text_diff(S.sent, file, { result_type = "unified", ctxlen = 2 })
  local parts = {}
  if ifaces ~= last and ifaces ~= "" then
    parts[1] = "These changed since the last message. " .. ifaces
  end
  parts[#parts + 1] = d == "" and "The file is unchanged since the last message." or ("File changes since the last message:\n" .. d)
  parts[#parts + 1] = ("Region (lines %d-%d):\n<<<REGION\n%s\nREGION>>>"):format(s + 1, e + 1, table.concat(lines, "\n"))
  parts[#parts + 1] = task(errors, instruction, level)
  return table.concat(parts, "\n\n"), file
end

---Question message (Alt+L): the file (whole the first time, then the diff
---since the last message), the lines it is about, the question. Returns
---prompt, file. S = nil for the one-shot fallback; paths are relative to
---`root`, the folder claude runs in.
function M.question_prompt(S, buf, q, s, e, root)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local file = table.concat(all, "\n") .. "\n"
  local parts = {}
  if S and S.sent then
    local d = text_diff(S.sent, file, { result_type = "unified", ctxlen = 2 })
    parts[1] = d == "" and "The file is unchanged since the last message." or ("File changes since the last message:\n" .. d)
  else
    local name = vim.api.nvim_buf_get_name(buf)
    parts[1] = ("File: %s (filetype %s)"):format(root and vim.fs.relpath(root, name) or vim.fn.fnamemodify(name, ":~:."), vim.bo[buf].filetype)
    local sib, text = M.sibling(buf)
    if sib then
      parts[#parts + 1] = ("Matching %s:\n%s"):format(vim.fn.fnamemodify(sib, ":t"), text)
    end
    parts[#parts + 1] = "Whole file:\n" .. table.concat(all, "\n")
  end
  local here = table.concat(vim.list_slice(all, s + 1, e + 1), "\n")
  if s == e then
    parts[#parts + 1] = ("The cursor is on line %d:\n%s"):format(s + 1, here)
  else
    parts[#parts + 1] = ("About lines %d-%d (selected):\n%s"):format(s + 1, e + 1, here)
  end
  parts[#parts + 1] = "Question: " .. q
  return table.concat(parts, "\n\n"), file
end

-- Pending conversions: pending[buf][mark] = text sent. Several can run at
-- once (insert, Esc, insert again elsewhere).
local pending = {}

function M.pending_count(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  return vim.tbl_count(pending[buf] or {})
end

local function region_lines(buf, mark)
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, { details = true })
  if not m[1] then
    return
  end
  return m[1], m[3].end_row
end

local preview_ns = vim.api.nvim_create_namespace "goose_preview"
local flash_ns = vim.api.nvim_create_namespace "goose_flash"
local previews = {} -- previews[buf][mark] = extmark id of the ghost lines

local function clear(buf, mark)
  pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark)
  local p = previews[buf] and previews[buf][mark]
  if p then
    pcall(vim.api.nvim_buf_del_extmark, buf, preview_ns, p)
    previews[buf][mark] = nil
  end
  if pending[buf] then
    pending[buf][mark] = nil
  end
  vim.cmd.redrawstatus()
end

M.preview_max = 200 -- ghost lines shown at most
M.preview_ms = 40 -- ghost lines update at most this often while streaming

---Ghost lines under the region: the answer so far, never in the buffer.
local function show_preview(buf, mark, text)
  if not vim.api.nvim_buf_is_valid(buf) or not (pending[buf] or {})[mark] then
    return
  end
  local _, e = region_lines(buf, mark)
  if not e then
    return
  end
  local lines, edits, more = M.split_answer(text)
  local tab = (" "):rep(vim.bo[buf].tabstop)
  local virt = {}
  for i = 1, math.min(#lines, M.preview_max) do
    virt[i] = { { (lines[i]:gsub("\t", tab)), "Comment" } }
  end
  if more then
    virt[#virt + 1] = { { ("  + changes elsewhere in the file (%d so far)"):format(#edits), "DiagnosticVirtualTextInfo" } }
  end
  previews[buf] = previews[buf] or {}
  if #virt == 0 then
    return
  end
  previews[buf][mark] = vim.api.nvim_buf_set_extmark(buf, preview_ns, e, 0, {
    id = previews[buf][mark],
    virt_lines = virt,
  })
end
M.flash_ms = 400 -- how long the new lines stay lit after the swap

local function flash(buf, s, new)
  local id = vim.api.nvim_buf_set_extmark(buf, flash_ns, s, 0, {
    end_row = s + #new - 1,
    end_col = #new[#new],
    hl_group = "GooseFlash",
    hl_eol = true,
    priority = 250,
  })
  vim.defer_fn(function()
    pcall(vim.api.nvim_buf_del_extmark, buf, flash_ns, id)
  end, M.flash_ms)
end

local function errors_in(buf, s, e)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })) do
    -- dune's errors (dune --watch, through ocamllsp) are about the saved
    -- file, not the answer just written: one on these rows sent a retry for
    -- code that compiled. Merlin checks the new text itself.
    local stale = d.source == "dune" and vim.bo[buf].modified
    if d.lnum >= s and d.lnum <= e and not stale then
      out[#out + 1] = ("line %d: %s"):format(d.lnum - s + 1, d.message)
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

-- The retry waits for the language server's first report after a replace,
-- this long at most (ms).
M.lsp_wait = 2500
M.format = true -- run the file's formatter on the new lines

-- true: a finished answer waits as ghost lines; Alt+K accepts it, Esc or `u`
-- drops it. false (default): it replaces the draft as soon as it is complete.
M.accept_first = false
local ready = {} -- ready[buf] = { mark, text, new, retry } awaiting Alt+K

local run, draft_range

-- The file is written once every conversion in it has landed, compile retry
-- included, so the build's errors (dune --watch, reported through ocamllsp)
-- refresh without a :w. They come from the file on disk, so they stayed
-- after a fix until the next save.
M.save = true
local checking = {} -- checking[buf] = compile checks waiting on the language server
local landed = {} -- landed[buf] = changedtick after goose's last change, not yet saved

---Save buf if goose changed it and nothing in it is still writing, waiting
---for a compile check or waiting to be accepted. A failed or empty answer
---never sets `landed`, so it never saves.
local function settle(buf)
  if not landed[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if M.pending_count(buf) > 0 or (checking[buf] or 0) > 0 or ready[buf] then
    return
  end
  if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode:find "^[iR]" then
    -- Typing in this file: the formatter on save would move text under the
    -- cursor, so the save waits until Insert ends.
    vim.api.nvim_create_autocmd("InsertLeave", {
      buffer = buf,
      once = true,
      callback = vim.schedule_wrap(function()
        settle(buf)
      end),
    })
    return
  end
  local tick = landed[buf]
  landed[buf] = nil
  local name = vim.api.nvim_buf_get_name(buf)
  if not M.save or vim.bo[buf].buftype ~= "" or name == "" or require("library").is_library(buf) or not vim.bo[buf].modified then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    if vim.b[buf].changedtick == tick then
      pcall(vim.cmd.undojoin) -- the formatter's change on save stays in the same `u`
    end
    local ok, err = pcall(vim.cmd, "silent update")
    if not ok then
      vim.notify("goose: could not save: " .. tostring(err), vim.log.levels.WARN)
    end
  end)
end

---The one buffer change: lines s..e become `new`, formatted, then flash and
---maybe retry.
local function replace(buf, s, e, new, retry, nocheck)
  local watch
  vim.api.nvim_buf_call(buf, function()
    if retry then
      pcall(vim.cmd.undojoin) -- the fix-up joins the first replace: one `u`
    else
      -- Close the insert's undo block first. With no key pressed since Esc,
      -- the replace would join it, and `u` would drop the pseudocode too.
      vim.cmd "let &undolevels = &undolevels"
    end
    vim.api.nvim_buf_set_lines(buf, s, e + 1, false, new)
    -- Follows the new lines through the formatter's changes.
    watch = vim.api.nvim_buf_set_extmark(
      buf,
      ns,
      s,
      0,
      { end_row = s + #new - 1, end_col = #new[#new], right_gravity = false, end_right_gravity = true }
    )
    if M.format then
      pcall(vim.cmd.undojoin) -- formatting is part of the same `u`
      -- Another region still writing, or a draft being typed: a whole-file
      -- formatter could join that text onto code, so only these lines.
      local only_lines = M.pending_count(buf) > 0 or draft_range(buf) ~= nil
      local ok, err = pcall(require("lsp").format_lines, buf, s, s + #new - 1, only_lines)
      if not ok then
        vim.notify("goose: formatter failed: " .. tostring(err), vim.log.levels.WARN)
      end
    end
  end)
  local s2, e2 = region_lines(buf, watch)
  local lines = vim.api.nvim_buf_get_lines(buf, s2, e2 + 1, false)
  flash(buf, s2, lines)
  M.last = { buf = buf, lines = lines, retry = retry } -- for tests
  if retry or nocheck or #vim.lsp.get_clients { bufnr = buf } == 0 then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, watch)
    return
  end
  -- One retry with the compiler's errors, never a loop: on the language
  -- server's first report after the change, or after lsp_wait at most.
  local checked, au = false, nil
  checking[buf] = (checking[buf] or 0) + 1
  local function check()
    if checked then
      return
    end
    checked = true
    checking[buf] = (checking[buf] or 1) - 1
    pcall(vim.api.nvim_del_autocmd, au)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local s3, e3 = region_lines(buf, watch)
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, watch)
    local errs = s3 and errors_in(buf, s3, e3)
    if errs then
      run(buf, s3, e3, errs)
    end
    settle(buf)
  end
  au =
    vim.api.nvim_create_autocmd("DiagnosticChanged", { buffer = buf, once = true, callback = vim.schedule_wrap(check) })
  vim.defer_fn(check, M.lsp_wait)
end

-- ── Changes outside the region (SEARCH/REPLACE blocks) ─────────────────────
local edit_ns = vim.api.nvim_create_namespace "goose_edit"

local function same_rstrip(a, b)
  return a:gsub("%s+$", "") == b:gsub("%s+$", "")
end
local function same_trim(a, b)
  return vim.trim(a) == vim.trim(b)
end

---0-based row where `want` matches `all` in a block clear of rows s..e; the
---match nearest the region wins.
local function find(all, want, s, e, eq)
  local n, best, dist = #want, nil, math.huge
  for i = 0, #all - n do
    if i + n - 1 < s or i > e then
      local ok = true
      for k = 1, n do
        if not eq(all[i + k], want[k]) then
          ok = false
          break
        end
      end
      local d = i > e and i - e or s - (i + n - 1)
      if ok and d < dist then
        best, dist = i, d
      end
    end
  end
  return best
end

---Lines s..e become `new` (replace(): flash, compile retry), and each edit
---outside them is made in the same undo step. An edit whose lines are not
---in the file is skipped with a warning; one that changes nothing is
---dropped. With no region lines the region goes only on a first send whose
---edits change the file (an instruction about other lines); otherwise the
---text stays and a message says why.
local function apply(buf, s, e, new, edits, retry, nocheck)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks, missed, taken = {}, {}, {}
  for _, ed in ipairs(edits or {}) do
    local n = #ed.search
    local at = n > 0 and (find(all, ed.search, s, e, same_rstrip) or find(all, ed.search, s, e, same_trim)) or nil
    for _, t in ipairs(taken) do
      if at and at <= t[2] and at + n - 1 >= t[1] then
        at = nil -- overlaps an earlier edit
      end
    end
    if not at then
      missed[#missed + 1] = vim.trim(ed.search[1] or "(empty SEARCH)")
    elseif not vim.deep_equal(vim.list_slice(all, at + 1, at + n), ed.replace) then
      taken[#taken + 1] = { at, at + n - 1 }
      local id = vim.api.nvim_buf_set_extmark(buf, edit_ns, at, 0, { end_row = at + n - 1, end_col = #all[at + n], end_right_gravity = true })
      marks[#marks + 1] = { id = id, replace = ed.replace }
    end
  end
  if #missed > 0 then
    vim.notify("goose: could not find the lines to change: " .. table.concat(missed, " | "), vim.log.levels.WARN)
  end
  if #new == 0 and #marks == 0 then
    local why = #(edits or {}) == 0 and "empty answer" or "the answer had no code for these lines and changed nothing else"
    return vim.notify("goose: " .. why .. "; kept your text", vim.log.levels.WARN)
  end
  if #new > 0 then
    replace(buf, s, e, new, retry, nocheck)
  elseif retry then
    -- A fix made only elsewhere (a missing definition): the region keeps the
    -- first answer; the edits below join its undo step.
    vim.notify("goose: the compile fix changed only other lines; kept the region", vim.log.levels.INFO)
  else -- an instruction about other lines: it goes, they change
    vim.api.nvim_buf_call(buf, function()
      vim.cmd "let &undolevels = &undolevels"
      vim.api.nvim_buf_set_lines(buf, s, e + 1, false, {})
    end)
  end
  local at = {}
  for _, m in ipairs(marks) do
    local p = vim.api.nvim_buf_get_extmark_by_id(buf, edit_ns, m.id, { details = true })
    pcall(vim.api.nvim_buf_del_extmark, buf, edit_ns, m.id)
    if p[1] then
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd.undojoin) -- one `u` undoes the region and these
        vim.api.nvim_buf_set_lines(buf, p[1], p[3].end_row + 1, false, m.replace)
      end)
      if #m.replace > 0 then
        flash(buf, p[1], m.replace)
      end
      at[#at + 1] = vim.api.nvim_buf_set_extmark(buf, edit_ns, math.min(p[1], vim.api.nvim_buf_line_count(buf) - 1), 0, {})
    end
  end
  -- Report where, read after every edit has moved the lines.
  local rows = {}
  for _, id in ipairs(at) do
    rows[#rows + 1] = vim.api.nvim_buf_get_extmark_by_id(buf, edit_ns, id, {})[1] + 1
    pcall(vim.api.nvim_buf_del_extmark, buf, edit_ns, id)
  end
  table.sort(rows)
  M.last_elsewhere = { rows = rows, missed = missed } -- for tests
  if #rows > 0 then
    vim.notify(("goose: also changed line%s %s (one u undoes it all)"):format(#rows > 1 and "s" or "", table.concat(rows, ", ")))
  end
  if not vim.deep_equal(all, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
    landed[buf] = vim.b[buf].changedtick -- settle() saves it
  end
end

local function drop_ready(buf)
  local r = ready[buf]
  if not r then
    return
  end
  ready[buf] = nil
  pcall(vim.api.nvim_buf_del_extmark, buf, ns, r.mark)
  pcall(vim.api.nvim_buf_del_extmark, buf, preview_ns, r.preview)
  pcall(vim.keymap.del, "n", "<Esc>", { buffer = buf })
  pcall(vim.keymap.del, "n", "u", { buffer = buf })
end

---Alt+K on a waiting answer (accept_first): apply it if the region is
---untouched. Returns true when there was one.
local function accept(buf)
  local r = ready[buf]
  if not r then
    return false
  end
  local s, e = region_lines(buf, r.mark)
  drop_ready(buf)
  if not s or table.concat(vim.api.nvim_buf_get_lines(buf, s, e + 1, false), "\n") ~= r.text then
    vim.notify("goose: you edited the region; kept your text", vim.log.levels.WARN)
  else
    apply(buf, s, e, r.new, r.edits, r.retry, r.nocheck)
  end
  settle(buf)
  return true
end
M.accept = accept

local function hold(buf, s, e, text, new, edits, retry, nocheck)
  drop_ready(buf)
  local last = vim.api.nvim_buf_get_lines(buf, e, e + 1, false)[1] or ""
  local r = { text = text, new = new, edits = edits, retry = retry, nocheck = nocheck }
  r.mark = vim.api.nvim_buf_set_extmark(buf, ns, s, 0, {
    end_row = e,
    end_col = #last,
    hl_group = "Comment",
    hl_eol = true,
    virt_text = { { "  Alt+K accepts, Esc drops", "DiagnosticVirtualTextInfo" } },
    virt_text_pos = "eol",
    right_gravity = false,
    end_right_gravity = true,
  })
  local virt = {}
  for i = 1, math.min(#new, M.preview_max) do
    virt[i] = { { new[i], "Comment" } }
  end
  if #edits > 0 then
    virt[#virt + 1] = { { ("  + %d change%s elsewhere in the file"):format(#edits, #edits > 1 and "s" or ""), "DiagnosticVirtualTextInfo" } }
  end
  r.preview = vim.api.nvim_buf_set_extmark(buf, preview_ns, e, 0, { virt_lines = virt })
  ready[buf] = r
  -- Nothing in the file has changed yet, so `u` only drops the answer; it
  -- never undoes the pseudocode as well.
  local function dropper(key)
    vim.keymap.set("n", key, function()
      drop_ready(buf)
    end, { buffer = buf, desc = "Goose: drop the waiting answer" })
  end
  dropper "<Esc>"
  dropper "u"
end

---Does `new` still hold every line of the pseudocode `text` (a CR above it
---says why it cannot be written)? Then its compile errors are expected.
local function kept_pseudocode(new, text)
  local have = {}
  for _, l in ipairs(new) do
    have[vim.trim(l)] = true
  end
  for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
    if vim.trim(l) ~= "" and not have[vim.trim(l)] then
      return false
    end
  end
  return true
end

---`hint`: the vibe level of the send; its answer is no code, so no compile
---check either.
local function finish(buf, mark, out, err, retry, hint)
  local text = (pending[buf] or {})[mark]
  if not text or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local s, e = region_lines(buf, mark)
  if not s then
    return clear(buf, mark)
  end
  local now = vim.api.nvim_buf_get_lines(buf, s, e + 1, false)
  clear(buf, mark)
  if table.concat(now, "\n") ~= text then
    return vim.notify("goose: you edited the region while it was writing; kept your text", vim.log.levels.WARN)
  end
  if not out then
    return vim.notify("goose: " .. (err or "no answer"), vim.log.levels.ERROR)
  end
  local new, edits = M.split_answer(out)
  if #new == 0 and #edits == 0 then
    return vim.notify("goose: empty answer; kept your text", vim.log.levels.WARN)
  end
  if hint then
    -- The answer is only the hints: the pseudocode stays, they go under it.
    new = vim.list_extend(vim.split(text, "\n", { plain = true }), new)
  end
  -- Pseudocode the answer kept on purpose does not compile: a retry would
  -- only "fix" it by dropping the programmer's lines.
  local nocheck = hint or kept_pseudocode(new, text)
  if M.accept_first and not retry then
    return hold(buf, s, e, text, new, edits, retry, nocheck)
  end
  apply(buf, s, e, new, edits, retry, nocheck)
end

---The region's "writing…" note becomes `text` (the agent's tool calls).
local function set_note(buf, mark, text)
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, { details = true })
  if not m[1] then
    return
  end
  local d = m[3]
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], {
    id = mark,
    end_row = d.end_row,
    end_col = d.end_col,
    hl_group = d.hl_group,
    hl_eol = d.hl_eol,
    virt_text = { { "  " .. text, "DiagnosticVirtualTextInfo" } },
    virt_text_pos = "eol",
    right_gravity = false,
    end_right_gravity = true,
  })
end

---Convert lines s..e (0-based, inclusive) of buf at the vibe level
---(M.vibe, or a first line `hint:`/`step:`/`full:`/`agent:`). `errors` = a
---retry; `instruction` replaces "turn the pseudocode into code" (the region
---may then be code, or blank).
run = function(buf, s, e, errors, instruction)
  local lines = vim.api.nvim_buf_get_lines(buf, s, e + 1, false)
  if #lines == 0 or not (instruction or table.concat(lines, ""):match "%S") then
    return
  end
  e = s + #lines - 1 -- a region past the buffer's end is cut to what exists
  local level = not errors and M.vibe_of(lines) or nil -- a retry only fixes errors
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, s, 0, {
    end_row = e,
    end_col = #lines[#lines],
    hl_group = "Comment",
    hl_eol = true,
    virt_text = {
      {
        errors and "  fixing compile errors…" or level == "agent" and "  agent writing…" or "  writing…",
        "DiagnosticVirtualTextInfo",
      },
    },
    virt_text_pos = "eol",
    right_gravity = false,
    end_right_gravity = true,
  })
  pending[buf] = pending[buf] or {}
  pending[buf][mark] = table.concat(lines, "\n")
  vim.cmd.redrawstatus()
  local function done(out, err)
    finish(buf, mark, out, err, errors ~= nil, level == "hint")
    settle(buf)
  end
  if level == "agent" then
    -- Slower on purpose: a stronger model that reads the project first.
    local root = M.root(buf)
    local opts = M.claude_opts(root, { tools = M.agent_tools })
    opts.model = M.agent_model
    opts.on_tool = function(name, input)
      set_note(buf, mark, "agent: " .. M.describe(name, input, root))
    end
    return M.ask(system_for(buf, false, true), prompt_for(buf, s, e, lines, nil, instruction, level), done, opts)
  end
  if not M.use_session then
    return M.ask(system_for(buf, false), prompt_for(buf, s, e, lines, errors, instruction, level), done)
  end
  -- The region is read again when the message goes out: an earlier send in
  -- this buffer may still be writing and move it.
  local function now()
    local s2, e2 = region_lines(buf, mark)
    if not s2 or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    return s2, e2, vim.api.nvim_buf_get_lines(buf, s2, e2 + 1, false)
  end
  -- One ghost-line update per frame, not one per streamed token: the first
  -- text shows at once, then the newest text every preview_ms.
  local latest, frame
  local function tick()
    frame = nil
    if latest then
      local text = latest
      latest = nil
      show_preview(buf, mark, text)
      frame = vim.defer_fn(tick, M.preview_ms)
    end
  end
  M.session_send(buf, {
    system = system_for(buf, true),
    build = function(S)
      local s2, e2, l2 = now()
      if not s2 then
        return
      end
      return session_prompt(S, buf, s2, e2, l2, errors, instruction, level)
    end,
    full = function()
      local s2, e2, l2 = now()
      return s2 and prompt_for(buf, s2, e2, l2, errors, instruction, level)
    end,
    on_partial = function(text)
      latest = text
      if not frame then
        tick()
      end
    end,
    on_done = done,
  })
end
M.convert = run

-- ── Goose (loosey-goosey mode) ─────────────────────────────────────────────
-- Type anything with plain i/a/o and Esc; nothing fires. The lines you typed
-- since the last send are the draft (dotted underline), in as many blocks as
-- the places you typed. Alt+K sends every block: each becomes code, one
-- after another on the same claude. In a selection, Alt+K sends the selected
-- lines only.

local draft_ns = vim.api.nvim_create_namespace "goose_draft"
local draft = {} -- draft[buf] = extmark ids, one per block of typed lines
local start = {} -- start[buf] = { from, before, orig } for the current insert
M.max_draft = 60 -- more lines than this must be selected explicitly

---The draft's blocks, top to bottom: { { s, e, id }, ... }, 0-based rows.
local function draft_blocks(buf)
  local out = {}
  for _, id in ipairs(draft[buf] or {}) do
    local m = vim.api.nvim_buf_get_extmark_by_id(buf, draft_ns, id, { details = true })
    if m[1] then
      out[#out + 1] = { m[1], m[3].end_row, id }
    end
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  draft[buf] = #out > 0 and vim.tbl_map(function(b)
    return b[3]
  end, out) or nil
  return out
end
M.draft_blocks = draft_blocks -- for tests

---The first block (nil: no draft).
draft_range = function(buf)
  local b = draft_blocks(buf)[1]
  if b then
    return b[1], b[2]
  end
end
M.draft_range = draft_range -- for tests

local function drop_draft(buf)
  for _, id in ipairs(draft[buf] or {}) do
    pcall(vim.api.nvim_buf_del_extmark, buf, draft_ns, id)
  end
  draft[buf] = nil
end

---Two Esc presses this close together (ms) drop the draft: the lines typed
---were real code. The Esc that leaves Insert counts as the first press.
M.double_esc_ms = 300
local last_esc = {} -- { at = hrtime, buf = buffer } of the last typed Esc

local function on_esc(buf)
  local now = vim.uv.hrtime()
  local double = last_esc.buf == buf and (now - last_esc.at) / 1e6 <= M.double_esc_ms
  last_esc = double and {} or { at = now, buf = buf }
  if double then
    -- After the key: the first Esc's InsertLeave has recorded its lines.
    vim.schedule(function()
      if draft[buf] then
        drop_draft(buf)
        vim.notify "goose: draft cleared"
      end
    end)
  end
end

---Add lines s..e to the draft; blocks they touch or overlap merge into one.
local function add_draft(buf, s, e)
  local keep = {}
  for _, b in ipairs(draft_blocks(buf)) do
    if s <= b[2] + 1 and e >= b[1] - 1 then
      s, e = math.min(s, b[1]), math.max(e, b[2])
      pcall(vim.api.nvim_buf_del_extmark, buf, draft_ns, b[3])
    else
      keep[#keep + 1] = b[3]
    end
  end
  local last = vim.api.nvim_buf_get_lines(buf, e, e + 1, false)[1] or ""
  keep[#keep + 1] = vim.api.nvim_buf_set_extmark(buf, draft_ns, s, 0, {
    end_row = e,
    end_col = #last,
    hl_group = "GooseDraft",
    right_gravity = false,
    end_right_gravity = true,
  })
  draft[buf] = keep
end

local function set_hl()
  local hint = vim.api.nvim_get_hl(0, { name = "DiagnosticHint", link = false })
  vim.api.nvim_set_hl(0, "GooseDraft", { default = true, underdotted = true, sp = hint.fg })
  vim.api.nvim_set_hl(0, "GooseFlash", { default = true, link = "IncSearch" })
end

---Send the draft (or nothing). Called after the insert has ended.
function M.send()
  local buf = vim.api.nvim_get_current_buf()
  if accept(buf) then
    return
  end
  local blocks = draft_blocks(buf)
  drop_draft(buf)
  if #blocks == 0 then
    return vim.notify "goose: nothing typed since the last send"
  end
  local total = 0
  for _, b in ipairs(blocks) do
    total = total + b[2] - b[1] + 1
  end
  if total > M.max_draft then
    return vim.notify(("goose: %d lines is a lot for one go; select the lines you mean and press Alt+K"):format(total), vim.log.levels.WARN)
  end
  for _, b in ipairs(blocks) do
    run(buf, b[1], b[2])
  end
end

function M.setup()
  set_hl()
  local group = vim.api.nvim_create_augroup("Goose", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(a)
      M.kill_session(a.buf)
      ready[a.buf], previews[a.buf], pending[a.buf] = nil, nil, nil
      checking[a.buf], landed[a.buf] = nil, nil
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for buf in pairs(sessions) do
        M.kill_session(buf)
      end
      if spare then
        kill(spare)
      end
    end,
  })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function(a)
      -- Drafts are typed code, so only file buffers get them: typing in the
      -- Alt+L chat box (a prompt buffer) underlined the whole conversation.
      if vim.bo[a.buf].buftype ~= "" then
        return
      end
      -- Typing may end in Alt+K: have a process ready if this buffer has none.
      if not sessions[a.buf] then
        warm(system_for(a.buf, true))
      end
      start[a.buf] = {
        from = vim.fn.line "." - 1,
        before = vim.api.nvim_buf_line_count(a.buf),
        orig = vim.api.nvim_get_current_line(),
      }
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(a)
      local st = start[a.buf]
      start[a.buf] = nil
      if not st then
        return
      end
      -- The typed lines: from the start line, as many as the insert added.
      local s = st.from
      local e = s + vim.api.nvim_buf_line_count(a.buf) - st.before
      if e < s then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(a.buf, s, e + 1, false)
      if s == e and lines[1] == st.orig then
        return -- nothing typed
      end
      add_draft(a.buf, s, e)
    end,
  })
  -- Esc Esc: forget the draft. on_key sees the key as typed, so the Insert
  -- Esc and the normal-mode Esc map (nohlsearch) both count.
  vim.on_key(function(_, typed)
    if typed == "\27" then
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].buftype == "" then
        on_esc(buf)
      end
    end
  end, vim.api.nvim_create_namespace "goose_esc")
  local chord = require("util").chord
  local map = vim.keymap.set
  map("n", chord "k", M.send, { desc = "Goose: the underlined lines you typed become code" })
  map("i", chord "k", function()
    vim.cmd.stopinsert() -- InsertLeave records this insert, then send
    vim.schedule(M.send)
  end, { desc = "Goose: what you typed becomes code" })
  map("x", chord "k", function()
    local s, e = vim.fn.line "v" - 1, vim.fn.line "." - 1
    if s > e then
      s, e = e, s
    end
    vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
    local buf = vim.api.nvim_get_current_buf()
    drop_draft(buf)
    run(buf, s, e)
  end, { desc = "Goose: selection becomes code" })
  vim.api.nvim_create_user_command("Goose", M.send, { desc = "Goose: send the typed lines" })
  vim.api.nvim_create_user_command("GooseVibe", function(a)
    M.set_vibe(a.args)
  end, {
    nargs = "?",
    complete = function()
      return vim.list_extend(vim.deepcopy(M.VIBES), { "+", "-" })
    end,
    desc = "Goose vibe: how much Alt+K writes. hint (no code, hints) | step (your pseudocode, line for line; default) | full (writes the logic) | agent (one-line ask, tools, tidies nearby); + / - step; none shows it",
  })
end

return M
