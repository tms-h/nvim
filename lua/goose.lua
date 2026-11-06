-- Pseudocode to code (John Crepezzi, Signals and Threads ep 31: "type
-- pseudocode... when you exit insert mode, it turns it into real code... it
-- can only edit the area that you typed in").
--
--   Goose ("loosey-goosey mode"): type pseudocode with plain i/a/o and Esc;
--   nothing fires. The lines typed since the last send are the draft (dotted
--   underline); an insert away from the draft replaces it.
--   Alt+K / Cmd+K (Cursor's inline edit key), :Goose  send the draft to
--     `claude -p`. In a selection, sends the selected lines.
--   While it writes: the region greys out with "writing…" and the answer
--   streams in as grey ghost lines under it; the file itself changes once,
--   when the answer is complete, and the new lines flash. Edit elsewhere
--   freely. An edit inside the region throws the answer away. One `u` brings
--   the pseudocode back.
--
-- Each buffer keeps one long-lived claude process (stream-json). The first
-- message carries the whole file; later ones carry only a diff since the
-- last message, so a 1000-line file is not resent every Alt+K. If the
-- process dies, that send falls back to a one-shot `claude -p`.
--
-- ask() (one-shot) is shared with seconder.lua.
local M = {}

local ns = vim.api.nvim_create_namespace "goose"

-- Lean CLI: no settings (hooks, plugins, CLAUDE.md), no MCP, no tools, no
-- session file. Measured 2026-11-06: 3.1 s per call vs 3.8 s for plain
-- `claude -p`, and plain leaked CLAUDE.md lines into the code. --bare would be
-- faster but needs an API key (OAuth logins fail).
M.model = "claude-sonnet-5-5"
local function cmd(system)
  return {
    "claude", "-p", "--model", M.model,
    "--setting-sources", "", "--strict-mcp-config", "--tools", "",
    "--no-session-persistence", "--disable-slash-commands",
    "--system-prompt", system,
  }
end

---Run claude on `prompt` (stdin) with `system`; on_done(text|nil, err) on the
---main loop.
function M.ask(system, prompt, on_done)
  local ok, err = pcall(vim.system, cmd(system), { stdin = prompt, text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        on_done(nil, (r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", ""))
      else
        on_done(r.stdout)
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
-- Measured 2026-11-06 (Sonnet, lean flags): a fresh `claude -p` costs 3-4 s,
-- of which ~2.9 s is fixed startup; messages 2+ on one stream-json process
-- took 2.1-3.5 s, with the ~7k-token harness prefix read from cache.

M.use_session = true -- false: every send is a one-shot `claude -p`
M.session_max_tokens = 60000 -- restart (whole file again) past this history
M.session_max_msgs = 25 -- ...or after this many messages
M.session_argv = nil -- tests: replace the claude command line

local sessions = {} -- sessions[buf] = session table, see start_session()
local warned = false

function M.session(buf) -- for tests and measurement
  return sessions[buf]
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

local pump

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
  M.ask(item.system, full, item.on_done)
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
      kill(S) -- the next send starts fresh with the whole file
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

local function argv(system)
  if M.session_argv then
    return M.session_argv
  end
  local c = cmd(system)
  vim.list_extend(c, { "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages" })
  return c
end

local function start_session(buf, system)
  local S = { buf = buf, system = system, queue = {}, msgs = 0, tokens = 0, acc = "", err = "" }
  local ok, job = pcall(vim.system, argv(system), {
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
---  system, build(S) -> prompt, file text (nil prompt = region gone),
---  full() -> one-shot prompt, on_partial(text), on_done(text|nil, err) }.
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
    S, err = start_session(buf, item.system)
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

---The other half of an OCaml pair (foo.ml <-> foo.mli), if it exists.
function M.sibling(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local other = name:match "%.mli$" and name:sub(1, -2) or name:match "%.ml$" and name .. "i"
  if other and vim.uv.fs_stat(other) then
    return other, table.concat(vim.fn.readfile(other), "\n")
  end
end

local SYSTEM = [[You turn the programmer's pseudocode into real code, in place.
Rules:
- Implement exactly the behaviour written. You may use better idiom or helpers
  that already exist in the file.
- If a different design would change behaviour (for example the written
  version fails on some input), still write their version, and add ONE comment
  line above it: `(* CR claude: <concrete failing input and what happens> *)`.
  Use CR only when you can name an input that breaks it. Use
  `(* CR-soon claude: ... *)` for "works but there is a clearly better way".
  Nothing for taste. At most one comment in total.
- If the pseudocode cannot work as written (contradiction, unknown type or
  function), output the pseudocode lines unchanged with one CR comment above
  saying why.
- Parts you cannot write: `failwith "TODO: ..."`.
- Only write the marked region. Never fill `failwith "TODO"` holes elsewhere.
- Keep the region's indentation. Use the file's language and comment syntax.
- Output only the replacement lines: no fences, no prose.]]

local function prompt_for(buf, s, e, lines, errors)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = table.concat(vim.list_slice(all, 1, s), "\n")
  local after = table.concat(vim.list_slice(all, e + 2), "\n")
  local parts = {
    ("File: %s (filetype %s)"):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":~:."), vim.bo[buf].filetype),
  }
  local sib, text = M.sibling(buf)
  if sib then
    parts[#parts + 1] = ("Matching %s:\n%s"):format(vim.fn.fnamemodify(sib, ":t"), text)
  end
  parts[#parts + 1] = "Whole file, region marked:\n" .. before .. "\n<<<REGION\n" .. table.concat(lines, "\n") .. "\nREGION>>>\n" .. after
  if errors then
    parts[#parts + 1] = "Your last answer for the region (shown above) gave these compiler errors; fix them:\n" .. errors
  else
    parts[#parts + 1] = "Rewrite the region's pseudocode as code."
  end
  return table.concat(parts, "\n\n")
end

-- The session's system prompt: the same rules plus how later messages look.
local SESSION_SYSTEM = SYSTEM .. [[


This is a running session on one file. The first message gives the whole
file. Each later message gives only a unified diff of the file since the
previous message (your earlier answers appear in it only if they were
applied), then the new region with its line numbers. Keep your picture of
the file up to date from the diffs. Each answer replaces only the current
region.]]

local text_diff = (vim.text and vim.text.diff) or vim.diff

---Session message for the region: the whole file the first time, after
---that a diff since the last message plus the region. Returns prompt, file.
local function session_prompt(S, buf, s, e, lines, errors)
  local file = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  if not S.sent then
    return prompt_for(buf, s, e, lines, errors), file
  end
  local d = text_diff(S.sent, file, { result_type = "unified", ctxlen = 2 })
  local parts = {
    d == "" and "The file is unchanged since the last message." or ("File changes since the last message:\n" .. d),
    ("Region (lines %d-%d):\n<<<REGION\n%s\nREGION>>>"):format(s + 1, e + 1, table.concat(lines, "\n")),
  }
  if errors then
    parts[#parts + 1] = "Your last answer for the region (shown above) gave these compiler errors; fix them:\n" .. errors
  else
    parts[#parts + 1] = "Rewrite the region's pseudocode as code."
  end
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

---Ghost lines under the region: the answer so far, never in the buffer.
local function show_preview(buf, mark, text)
  if not vim.api.nvim_buf_is_valid(buf) or not (pending[buf] or {})[mark] then
    return
  end
  local _, e = region_lines(buf, mark)
  if not e then
    return
  end
  local lines = M.strip_fences(text)
  local tab = (" "):rep(vim.bo[buf].tabstop)
  local virt = {}
  for i = 1, math.min(#lines, M.preview_max) do
    virt[i] = { { (lines[i]:gsub("\t", tab)), "Comment" } }
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
    if d.lnum >= s and d.lnum <= e then
      out[#out + 1] = ("line %d: %s"):format(d.lnum - s + 1, d.message)
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

-- How long to wait for the language server after a replace (ms).
M.lsp_wait = 2500

-- true: a finished answer waits as ghost lines; Alt+K accepts it, Esc or `u`
-- drops it. false (default): it replaces the draft as soon as it is complete.
M.accept_first = false
local ready = {} -- ready[buf] = { mark, text, new, retry } awaiting Alt+K

local run

---The one buffer change: lines s..e become `new`, then flash and maybe retry.
local function replace(buf, s, e, new, retry)
  vim.api.nvim_buf_call(buf, function()
    if retry then
      pcall(vim.cmd.undojoin) -- the fix-up joins the first replace: one `u`
    else
      -- Close the insert's undo block first. With no key pressed since Esc,
      -- the replace would join it, and `u` would drop the pseudocode too.
      vim.cmd "let &undolevels = &undolevels"
    end
    vim.api.nvim_buf_set_lines(buf, s, e + 1, false, new)
  end)
  flash(buf, s, new)
  M.last = { buf = buf, lines = new, retry = retry } -- for tests
  if retry or #vim.lsp.get_clients { bufnr = buf } == 0 then
    return
  end
  -- One retry with the compiler's errors, never a loop.
  local watch = vim.api.nvim_buf_set_extmark(buf, ns, s, 0, { end_row = s + #new - 1, end_col = #new[#new], right_gravity = false, end_right_gravity = true })
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local s2, e2 = region_lines(buf, watch)
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, watch)
    local errs = s2 and errors_in(buf, s2, e2)
    if errs then
      run(buf, s2, e2, errs)
    end
  end, M.lsp_wait)
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
    replace(buf, s, e, r.new, r.retry)
  end
  return true
end
M.accept = accept

local function hold(buf, s, e, text, new, retry)
  drop_ready(buf)
  local last = vim.api.nvim_buf_get_lines(buf, e, e + 1, false)[1] or ""
  local r = { text = text, new = new, retry = retry }
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

local function finish(buf, mark, out, err, retry)
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
  local new = M.strip_fences(out)
  if #new == 0 then
    return vim.notify("goose: empty answer; kept your text", vim.log.levels.WARN)
  end
  if M.accept_first and not retry then
    return hold(buf, s, e, text, new, retry)
  end
  replace(buf, s, e, new, retry)
end

local used = {} -- buffers goose has sent from (their session restarts on BufEnter)

---Convert lines s..e (0-based, inclusive) of buf. `errors` = a retry.
run = function(buf, s, e, errors)
  local lines = vim.api.nvim_buf_get_lines(buf, s, e + 1, false)
  if #lines == 0 or not table.concat(lines, ""):match "%S" then
    return
  end
  e = s + #lines - 1 -- a region past the buffer's end is cut to what exists
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, s, 0, {
    end_row = e,
    end_col = #lines[#lines],
    hl_group = "Comment",
    hl_eol = true,
    virt_text = { { errors and "  fixing compile errors…" or "  writing…", "DiagnosticVirtualTextInfo" } },
    virt_text_pos = "eol",
    right_gravity = false,
    end_right_gravity = true,
  })
  pending[buf] = pending[buf] or {}
  pending[buf][mark] = table.concat(lines, "\n")
  vim.cmd.redrawstatus()
  local function done(out, err)
    finish(buf, mark, out, err, errors ~= nil)
  end
  if not M.use_session then
    return M.ask(SYSTEM, prompt_for(buf, s, e, lines, errors), done)
  end
  used[buf] = true
  -- The region is read again when the message goes out: an earlier send in
  -- this buffer may still be writing and move it.
  local function now()
    local s2, e2 = region_lines(buf, mark)
    if not s2 or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    return s2, e2, vim.api.nvim_buf_get_lines(buf, s2, e2 + 1, false)
  end
  M.session_send(buf, {
    system = SESSION_SYSTEM,
    build = function(S)
      local s2, e2, l2 = now()
      if not s2 then
        return
      end
      return session_prompt(S, buf, s2, e2, l2, errors)
    end,
    full = function()
      local s2, e2, l2 = now()
      return s2 and prompt_for(buf, s2, e2, l2, errors)
    end,
    on_partial = function(text)
      show_preview(buf, mark, text)
    end,
    on_done = done,
  })
end
M.convert = run

-- ── Goose (loosey-goosey mode) ─────────────────────────────────────────────
-- Type anything with plain i/a/o and Esc; nothing fires. The lines you typed
-- since the last send are the draft (dotted underline). Alt+K sends the
-- draft: those lines become code. The draft is one block: an insert away
-- from it starts a new draft and drops the old one, so Alt+K never reaches
-- old or distant text. In a selection, Alt+K sends the selected lines.

local draft_ns = vim.api.nvim_create_namespace "goose_draft"
local draft = {} -- draft[buf] = extmark id over the draft lines
local start = {} -- start[buf] = { from, before, orig } for the current insert
M.max_draft = 60 -- more lines than this must be selected explicitly

local function draft_range(buf)
  local id = draft[buf]
  if not id then
    return
  end
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, draft_ns, id, { details = true })
  if not m[1] then
    draft[buf] = nil
    return
  end
  return m[1], m[3].end_row
end
M.draft_range = draft_range -- for tests

local function drop_draft(buf)
  if draft[buf] then
    pcall(vim.api.nvim_buf_del_extmark, buf, draft_ns, draft[buf])
  end
  draft[buf] = nil
end

local function set_draft(buf, s, e)
  drop_draft(buf)
  local last = vim.api.nvim_buf_get_lines(buf, e, e + 1, false)[1] or ""
  draft[buf] = vim.api.nvim_buf_set_extmark(buf, draft_ns, s, 0, {
    end_row = e,
    end_col = #last,
    hl_group = "GooseDraft",
    right_gravity = false,
    end_right_gravity = true,
  })
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
  local s, e = draft_range(buf)
  drop_draft(buf)
  if not s then
    return vim.notify "goose: nothing typed since the last send"
  end
  if e - s + 1 > M.max_draft then
    return vim.notify(("goose: %d lines is a lot for one go; select the lines you mean and press Alt+K"):format(e - s + 1), vim.log.levels.WARN)
  end
  run(buf, s, e)
end

function M.setup()
  set_hl()
  local group = vim.api.nvim_create_augroup("Goose", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(a)
      M.kill_session(a.buf)
      used[a.buf], ready[a.buf], previews[a.buf], pending[a.buf] = nil, nil, nil, nil
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for buf in pairs(sessions) do
        M.kill_session(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(a)
      -- Back in a buffer goose was used in: have its process ready again.
      if M.use_session and used[a.buf] and not sessions[a.buf] then
        start_session(a.buf, SESSION_SYSTEM)
      end
    end,
  })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function(a)
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
      -- Touching or overlapping the draft grows it; anywhere else replaces it.
      local ds, de = draft_range(a.buf)
      if ds and s <= de + 1 and e >= ds - 1 then
        s, e = math.min(s, ds), math.max(e, de)
      end
      set_draft(a.buf, s, e)
    end,
  })
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
end

return M
