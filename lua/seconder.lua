-- Seconder: a Jane Street-style reviewer that only writes CR comments.
--
--   Space r   review this file: adds CR / CR-soon comments, deletes ones it is
--             satisfied with, reopens XCRs it is not. Never edits code. A
--             note on the cursor's line says "reviewing…", then "no issues"
--             or how many comments there are.
--   ]r / [r   next / previous CR, CR-soon or XCR line (the list also goes to
--             the location list after a review).
--   Alt+.     (Cmd+. on the Mac, VS Code's Quick Fix) applies the fix shown
--             in grey under the cursor's CR-soon and removes that CR; one `u`
--             undoes both. Only CR-soon nits carry a fix, never a CR, and a
--             fix is never applied by itself.
--
-- Reply to a CR by turning it into `XCR thomas: <why>`; the next Space r reads
-- it. The rubric is rubric/seconder.md (condensed from the js-wiki articles),
-- then the wiki's own review rules for this file's language
-- (rubric/wiki-rules.json, refreshed by the nightly job from
-- ~/Work/js-wiki/site/seconder-rules.json), then Thomas's checklist
-- (~/Work/js-intern-notes/review-checklist.md); either file may be missing.
-- A CR a wiki rule drove ends with "(wiki: <page>)". An optional REVIEW.md at
-- the project root adds house rules. Each review stores what it read under
-- stdpath('state')/seconder/, so the next one is told only what changed since
-- ("review brain"), and appends what happened to each CR (add, fixed,
-- pushback with the XCR reply, reopen, fix-accepted) to log.jsonl there, which
-- the wiki's /seconder page counts to flag rules Thomas keeps rejecting.
local M = {}

local goose = require "goose"
local ns = vim.api.nvim_create_namespace "seconder"
local fix_ns = vim.api.nvim_create_namespace "seconder.fix"

local here = debug.getinfo(1, "S").source:sub(2)
local ROOT = vim.fs.dirname(vim.fs.dirname(here))
local RUBRIC = vim.fs.joinpath(ROOT, "rubric", "seconder.md")
M.rules_path = vim.fs.joinpath(ROOT, "rubric", "wiki-rules.json")
M.checklist_path = vim.fs.normalize "~/Work/js-intern-notes/review-checklist.md"
M.fix_max_lines = 6 -- a fix replaces at most this many lines, with at most this many

local CR_LINE = "%f[%w]X?CR[%-%w]*%s+[%w_.%-]+%s*:"
M.pattern = CR_LINE

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

local function state_dir()
  local dir = vim.fs.joinpath(vim.fn.stdpath "state", "seconder")
  vim.fn.mkdir(dir, "p")
  return dir
end

local function state_file(buf)
  return vim.fs.joinpath(state_dir(), vim.fn.sha256(vim.api.nvim_buf_get_name(buf)):sub(1, 16) .. ".txt")
end

local function project_root(buf)
  return vim.fs.root(buf, { "REVIEW.md", ".git", "dune-project" })
end

-- The file's path from its project root (the log and the prompt use it).
local function rel_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local root = project_root(buf)
  return root and vim.fs.relpath and vim.fs.relpath(root, name) or vim.fn.fnamemodify(name, ":~:.")
end

-- ── Wiki rules ─────────────────────────────────────────────────────────────

---The language a rule's `langs` names for buf: .ml/.mli/.mll/.mly and dune
---files are "ocaml", anything else its filetype.
function M.lang(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local base = vim.fs.basename(name)
  if base == "dune" or base == "dune-project" or name:match "%.ml[ily]?$" then
    return "ocaml"
  end
  local ft = vim.bo[buf].filetype
  return ft == "ocamlinterface" and "ocaml" or ft
end

local function str(v)
  return type(v) == "string" and v ~= "" and v or nil
end

---The wiki rules (rubric/wiki-rules.json) that apply to buf's language:
---langs holds it or "any". A missing or broken file gives none.
function M.rules(buf)
  local ok, data = pcall(vim.json.decode, read(M.rules_path) or "")
  if not ok or type(data) ~= "table" or type(data.rules) ~= "table" then
    return {}
  end
  local lang, out = M.lang(buf), {}
  for _, r in ipairs(data.rules) do
    if type(r) == "table" and str(r.id) and str(r.rule) and type(r.langs) == "table" then
      for _, l in ipairs(r.langs) do
        if l == "any" or l == lang then
          out[#out + 1] = r
          break
        end
      end
    end
  end
  return out
end

-- `[id] (kind) rule Cost: … When: … — source: who, date; wiki: page`
local function rule_line(r)
  local srcs = {}
  for _, s in ipairs(type(r.sources) == "table" and r.sources or {}) do
    local who = type(s) == "table" and table.concat(vim.tbl_filter(str, { s.who, s.date }), ", ") or ""
    if who ~= "" then
      srcs[#srcs + 1] = who
    end
  end
  local line = ("[%s] (%s) %s"):format(r.id, str(r.kind) or "CR", r.rule)
  if str(r.cost) then
    line = line .. " Cost: " .. r.cost
  end
  if str(r.when) then
    line = line .. " When: " .. r.when
  end
  line = line .. " —"
  if #srcs > 0 then
    line = line .. " source: " .. table.concat(srcs, "; ") .. ";"
  end
  return line .. " wiki: " .. (str(r.page) or "?")
end

-- ── Log (stdpath('state')/seconder/log.jsonl) ──────────────────────────────

function M.log_path()
  return vim.fs.joinpath(state_dir(), "log.jsonl")
end

local function squash(s)
  return (vim.trim(s or ""):gsub("%s+", " "))
end

-- One event per line, keys in the contract's order; rule is null when no
-- wiki rule drove the CR.
local function log(buf, event, rule, kind, text, reply)
  local fields = {
    { "ts", os.date "%Y-%m-%dT%H:%M:%S" },
    { "file", rel_path(buf) },
    { "event", event },
    { "rule", rule or vim.NIL },
    { "kind", kind },
    { "text", squash(text) },
  }
  if reply then
    fields[#fields + 1] = { "reply", squash(reply) }
  end
  local parts = {}
  for _, f in ipairs(fields) do
    parts[#parts + 1] = vim.json.encode(f[1]) .. ": " .. vim.json.encode(f[2])
  end
  pcall(vim.fn.writefile, { "{" .. table.concat(parts, ", ") .. "}" }, M.log_path(), "a")
end

---Every CR-style comment block: { id, s, e (0-based), text }.
function M.comments(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, i = {}, 1
  while i <= #lines do
    if lines[i]:match(CR_LINE) then
      local s = i
      -- A comment runs to its closing *) (a multi-line reply included).
      while i < #lines and not lines[i]:find("*)", 1, true) and lines[i + 1]:match "%S" do
        i = i + 1
      end
      out[#out + 1] = { id = #out + 1, s = s - 1, e = i - 1, text = table.concat(vim.list_slice(lines, s, i), "\n") }
    end
    i = i + 1
  end
  return out
end

local SYSTEM = [[You are a Jane Street seconder reviewing one file. You never edit
code: you only add, delete or reopen CR comments. Follow the rubric exactly.
Answer with one JSON object and nothing else:
{"verdict": "seconded" | "crs",
 "reason": "<one line: why seconded, or the main problem>",
 "add": [{"line": <1-based line number the comment goes above>,
          "kind": "CR" | "CR-soon", "text": "<concrete, failing input first>",
          "rule": "<id of the wiki rule that drove it>" | null,
          "fix": {"from": <first line>, "to": <last line>, "lines": ["<replacement line>", ...]}}],
 "delete": [{"id": <comment id>, "why": "fixed" | "pushback"}],
 "reopen": [{"id": <comment id>, "text": "<why it still fails>"}]}
Comment ids refer to the "Existing CR comments" list. Do not add a CR that
repeats an existing one. Line numbers refer to the numbered file.
"rule": set it only when one of the "Rules from the wiki" drove the CR, and
then end the text with "(wiki: <that rule's page>)"; otherwise null.
"why": "fixed" when the code now handles the CR, "pushback" when the author's
XCR reply gave a real reason.
"fix": optional, only on a CR-soon, never on a CR: the exact replacement for
lines from..to (at most 6 lines, same indentation), only when it is small and
obviously right. The author reviews it before it lands. Leave it out otherwise.]]

local function numbered(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = ("%4d| %s"):format(i, l)
  end
  return table.concat(out, "\n")
end

---The prompt for buf, its lines, and the wiki rules sent (by id).
function M.prompt_for(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local name = vim.api.nvim_buf_get_name(buf)
  local parts = { "Rubric:\n" .. (read(RUBRIC) or "") }
  local rules, by_id = M.rules(buf), {}
  if #rules > 0 then
    local list = {}
    for _, r in ipairs(rules) do
      list[#list + 1] = rule_line(r)
      by_id[r.id] = r
    end
    parts[#parts + 1] = "Rules from the wiki (each names its source). Raise one only when its Cost applies in "
      .. "THIS file and its When holds; a rule's own kind is its default:\n"
      .. table.concat(list, "\n")
  end
  local mine = M.checklist_path and read(M.checklist_path)
  if mine and mine:match "%S" then
    parts[#parts + 1] = "Your own checklist (from real review feedback):\n" .. mine
  end
  local root = project_root(buf)
  local house = root and read(vim.fs.joinpath(root, "REVIEW.md"))
  if house then
    parts[#parts + 1] = "House rules (REVIEW.md):\n" .. house
  end
  local sib, stext = goose.sibling(buf)
  if sib then
    parts[#parts + 1] = ("Interface %s:\n%s"):format(vim.fn.fnamemodify(sib, ":t"), stext)
  end
  local last = read(state_file(buf))
  if last and last ~= text then
    parts[#parts + 1] = "Changed since your last review (focus here; earlier code you already read):\n"
      .. vim.diff(last, text, { ctxlen = 2 })
  elseif last then
    parts[#parts + 1] = "Unchanged since your last review except for comment replies."
  end
  local diags = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    diags[#diags + 1] = ("line %d: %s"):format(d.lnum + 1, d.message)
  end
  if #diags > 0 then
    parts[#parts + 1] = "Compiler diagnostics:\n" .. table.concat(diags, "\n")
  end
  local cs = M.comments(buf)
  if #cs > 0 then
    local list = {}
    for _, c in ipairs(cs) do
      list[#list + 1] = ("id %d (line %d): %s"):format(c.id, c.s + 1, c.text)
    end
    parts[#parts + 1] = "Existing CR comments (XCR = the author's reply to your CR):\n" .. table.concat(list, "\n")
  end
  -- The file's role (library vs executable) decides whether some CRs apply,
  -- so send its path from the project root and the dune file next to it.
  local rel = rel_path(buf)
  local dune = read(vim.fs.joinpath(vim.fs.dirname(name), "dune"))
  if dune then
    parts[#parts + 1] = "dune file in the same folder:\n" .. dune
  end
  parts[#parts + 1] = ("File %s:\n%s"):format(rel, numbered(lines))
  return table.concat(parts, "\n\n"), lines, by_id
end

local function comment(buf, indent, kind, body)
  local cs = vim.bo[buf].commentstring
  if cs == "" or not cs:find "%%s" then
    cs = "(* %s *)"
  end
  return indent .. cs:format(kind .. " claude: " .. body:gsub("%s*\n%s*", " "))
end

local function decode(out)
  local json = out:match "%b{}"
  local ok, v = pcall(vim.json.decode, json or "")
  return ok and type(v) == "table" and v or nil
end

-- What a comment block says, without its comment markers, on one line.
local function plain(buf, text)
  local cs = vim.bo[buf].commentstring
  if cs == "" or not cs:find "%%s" then
    cs = "(* %s *)"
  end
  local open, close = cs:match "^%s*(.-)%s*%%s%s*(.-)%s*$"
  local out = {}
  for line in (text .. "\n"):gmatch "(.-)\n" do
    line = vim.trim(line)
    if open ~= "" and line:sub(1, #open) == open then
      line = line:sub(#open + 1)
    end
    if close ~= "" and line:sub(-#close) == close then
      line = line:sub(1, -#close - 1)
    end
    out[#out + 1] = line
  end
  return squash(table.concat(out, " "))
end

-- This file's add and reopen events, oldest first: what each CR said when raised.
local function history(buf)
  local rel, out = rel_path(buf), {}
  local ok, lines = pcall(vim.fn.readfile, M.log_path())
  for _, l in ipairs(ok and lines or {}) do
    local good, e = pcall(vim.json.decode, l)
    if good and type(e) == "table" and e.file == rel and (e.event == "add" or e.event == "reopen") and str(e.text) then
      out[#out + 1] = e
    end
  end
  return out
end

local HEAD = "^(X?CR[%-%w]*)%s+([%w_.%-]+)%s*:%s*"

-- An existing comment's rule, kind and text as raised (found in the log, else
-- read from the comment and its "(wiki: page)"), and the author's reply.
local function origin(buf, c, rules, past)
  local said = plain(buf, c.text)
  local head, who = said:match(HEAD)
  local kind = head and head:gsub("^X", "") == "CR" and "CR" or "CR-soon"
  for i = #past, 1, -1 do
    local e = past[i]
    local at = said:find(e.text, 1, true)
    if at then
      local rest = said:sub(1, at - 1) .. " " .. said:sub(at + #e.text)
      if who == "claude" then
        rest = vim.trim(rest):gsub(HEAD, "")
      end
      rest = squash(rest)
      return str(e.rule), str(e.kind) or kind, e.text, rest ~= "" and rest or said
    end
  end
  local rule
  local page = said:match "%(wiki: ([^)]+)%)"
  for id, r in pairs(page and rules or {}) do
    if r.page == page then
      rule = rule == nil and id or false -- two rules on one page: unknown
    end
  end
  return rule or nil, kind, (said:gsub(HEAD, "")), said
end

-- ── Fix previews (CR-soon only) ────────────────────────────────────────────
-- fixes[buf][id of the mark on the CR line] = { range (mark over the lines it
-- replaces), line (the CR line), old, new, rule, kind, text }. The marks
-- follow edits; a fix whose CR line or old lines changed is dropped.
local fixes = {}
local KEY = require("util").is_macos and "Cmd+." or "Alt+."

local function drop_fix(buf, id)
  local f = (fixes[buf] or {})[id]
  if f then
    fixes[buf][id] = nil
    pcall(vim.api.nvim_buf_del_extmark, buf, fix_ns, id)
    pcall(vim.api.nvim_buf_del_extmark, buf, fix_ns, f.range)
  end
end

-- Where fix f stands: the CR's row and the replaced rows (0-based), or nil.
local function where(buf, id, f)
  local cr = vim.api.nvim_buf_get_extmark_by_id(buf, fix_ns, id, {})
  local r = vim.api.nvim_buf_get_extmark_by_id(buf, fix_ns, f.range, { details = true })
  if not cr[1] or not r[1] or not r[3].end_row then
    return
  end
  local s, e = r[1], r[3].end_row
  if vim.api.nvim_buf_get_lines(buf, cr[1], cr[1] + 1, false)[1] ~= f.line then
    return
  end
  if not vim.deep_equal(vim.api.nvim_buf_get_lines(buf, s, e + 1, false), f.old) then
    return
  end
  return cr[1], s, e
end

local function prune(buf)
  for id, f in pairs(fixes[buf] or {}) do
    if not where(buf, id, f) then
      drop_fix(buf, id)
    end
  end
end

-- Ghost lines under the CR (goose's preview look): the replacement, never in
-- the buffer until the key.
local function show_fix(buf, cr, s, e, f)
  local tab = (" "):rep(vim.bo[buf].tabstop)
  local virt = {}
  for i, l in ipairs(f.new) do
    virt[i] = { { (l:gsub("\t", tab)), "Comment" } }
  end
  if #virt == 0 then
    virt[1] = { { "  (deleted)", "Comment" } }
  end
  local n = e - s + 1
  local what = s == cr + 1 and ("the %d line%s below"):format(n, n == 1 and "" or "s")
    or ("line%s %d-%d"):format(n == 1 and "" or "s", s + 1, e + 1)
  local id = vim.api.nvim_buf_set_extmark(buf, fix_ns, cr, 0, {
    virt_text = { { ("  %s replaces %s with:"):format(KEY, what), "DiagnosticVirtualTextInfo" } },
    virt_text_pos = "eol",
    virt_lines = virt,
  })
  f.range = vim.api.nvim_buf_set_extmark(buf, fix_ns, s, 0, { end_row = e, end_col = #f.old[#f.old] })
  fixes[buf] = fixes[buf] or {}
  fixes[buf][id] = f
end

---The fix previews in buf, for tests: { { cr, s, e (0-based), new } }.
function M.fixes(buf)
  local out = {}
  for id, f in pairs(fixes[buf] or {}) do
    local cr, s, e = where(buf, id, f)
    if cr then
      out[#out + 1] = { cr = cr, s = s, e = e, new = f.new }
    end
  end
  table.sort(out, function(x, y)
    return x.cr < y.cr
  end)
  return out
end

-- A model's fix, if well formed and small: { from, to, lines }.
local function valid_fix(fx)
  if type(fx) ~= "table" or type(fx.lines) ~= "table" then
    return
  end
  local from, to = tonumber(fx.from), tonumber(fx.to)
  if not from or not to or from < 1 or to < from or to - from + 1 > M.fix_max_lines or #fx.lines > M.fix_max_lines then
    return
  end
  for _, l in ipairs(fx.lines) do
    if type(l) ~= "string" or l:find "\n" then
      return
    end
  end
  return { from = from, to = to, lines = fx.lines }
end

---Apply the CR-soon fix under the cursor's CR: replace its lines and remove
---the CR, as one undo step.
function M.accept_fix(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  prune(buf)
  local pick
  for id, f in pairs(fixes[buf] or {}) do
    local cr, s, e = where(buf, id, f)
    if row >= math.min(cr, s) and row <= math.max(cr, e) then
      pick = { id = id, f = f, cr = cr, s = s, e = e }
      break
    end
  end
  if not pick then
    return vim.notify "seconder: no fix at the cursor's CR"
  end
  local f, cr, s, e = pick.f, pick.cr, pick.s, pick.e
  drop_fix(buf, pick.id)
  -- Its own undo step, even straight after typing (the insert-mode key).
  vim.cmd "let &l:undolevels = &l:undolevels"
  if cr > e then
    vim.api.nvim_buf_set_lines(buf, cr, cr + 1, false, {})
    vim.api.nvim_buf_set_lines(buf, s, e + 1, false, f.new)
  else
    vim.api.nvim_buf_set_lines(buf, s, e + 1, false, f.new)
    vim.api.nvim_buf_set_lines(buf, cr, cr + 1, false, {})
    s = s - 1
  end
  local last = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(s + 1, last)), 0 })
  log(buf, "fix-accepted", f.rule, f.kind, f.text)
end

-- Apply the answer: only comment lines change. Bottom-up so line numbers hold.
-- rules: the wiki rules sent, by id. Logs every add, delete and reopen.
local function apply(buf, ans, snapshot, rules)
  local now = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local moved = #now ~= #snapshot
  -- A line the model named, found in today's buffer (it may have shifted).
  local function locate(l)
    local want = snapshot[l]
    if not want then
      return
    end
    if not moved and now[l] == want then
      return l
    end
    for d = 0, 50 do
      for _, c in ipairs { l - d, l + d } do
        if now[c] == want then
          return c
        end
      end
    end
  end
  local function list(v)
    return type(v) == "table" and v or {}
  end
  local past = history(buf)
  local edits, added, n_del, n_reopen, held = {}, {}, 0, 0, {}
  local cs = M.comments(buf)
  local by_id = {}
  for _, c in ipairs(cs) do
    by_id[c.id] = c
  end
  -- Plain ids (the old answer shape) still work; they count as fixed.
  for _, d in ipairs(list(ans.delete)) do
    local id, why = d, nil
    if type(d) == "table" then
      id, why = d.id, d.why
    end
    local c = by_id[tonumber(id)]
    if c then
      edits[#edits + 1] = { s = c.s, e = c.e + 1, lines = {} }
      by_id[c.id] = nil
      n_del = n_del + 1
      local rule, kind, text, reply = origin(buf, c, rules, past)
      if why == "pushback" then
        log(buf, "pushback", rule, kind, text, reply)
      else
        log(buf, "fixed", rule, kind, text)
      end
    end
  end
  for _, r in ipairs(list(ans.reopen)) do
    local c = type(r) == "table" and by_id[tonumber(r.id)]
    if c then
      local indent = now[c.s + 1]:match "^%s*"
      local rule, _, _, said = origin(buf, c, rules, past)
      local text = squash(str(r.text) or "still open")
      if rule and rules[rule] and not text:find("(wiki: " .. rules[rule].page .. ")", 1, true) then
        text = text .. " (wiki: " .. rules[rule].page .. ")"
      end
      -- One comment again: the reopened CR, then the reply it answers.
      local reply = c.text:gsub("^%s*%(%*%s*", ""):gsub("%s*%*%)%s*$", ""):gsub("\n%s*", " ")
      reply = reply:gsub("^X?CR[%-%w]*%s+([%w_.%-]+)%s*:", "%1 replied:")
      local cr = comment(buf, indent, "CR", text)
      edits[#edits + 1] = { s = c.s, e = c.e + 1, lines = {
        (cr:gsub("%s*%*%)$", "")),
        indent .. "   " .. reply .. " *)",
      } }
      by_id[c.id] = nil
      n_reopen = n_reopen + 1
      log(buf, "reopen", rule, "CR", text, said)
    end
  end
  for _, a in ipairs(list(ans.add)) do
    local l = type(a) == "table" and locate(tonumber(a.line) or 0)
    if l and str(a.text) then
      local kind = a.kind == "CR-soon" and "CR-soon" or "CR"
      local rule = type(a.rule) == "string" and rules[a.rule] or nil
      local text = squash(a.text)
      if rule and not text:find("(wiki: " .. rule.page .. ")", 1, true) then
        text = text .. " (wiki: " .. rule.page .. ")"
      end
      local line = comment(buf, now[l]:match "^%s*", kind, text)
      edits[#edits + 1] = { s = l - 1, e = l - 1, lines = { line } }
      added[#added + 1] = { rule = rule and rule.id, kind = kind, text = text }
      -- A CR never carries a fix: the author does the thinking there.
      local fx = kind == "CR-soon" and valid_fix(a.fix)
      local s, e = fx and locate(fx.from), fx and locate(fx.to)
      if s and e and e - s == fx.to - fx.from then
        local old = vim.list_slice(now, s, e)
        if not vim.deep_equal(old, fx.lines) then
          local function mark(row)
            return vim.api.nvim_buf_set_extmark(buf, fix_ns, row, 0, {})
          end
          held[#held + 1] = { anchor = mark(l - 1), s = mark(s - 1), e = mark(e - 1),
            f = { line = line, old = old, new = fx.lines, rule = added[#added].rule, kind = kind, text = text } }
        end
      end
    end
  end
  table.sort(edits, function(x, y)
    return x.s > y.s
  end)
  for _, ed in ipairs(edits) do
    vim.api.nvim_buf_set_lines(buf, ed.s, ed.e, false, ed.lines)
  end
  for _, a in ipairs(added) do
    log(buf, "add", a.rule, a.kind, a.text)
  end
  -- Each fix: its CR sits just above the line it was added at (several CRs
  -- may share that line), and its old lines must still be where they were.
  local shown = 0
  for _, h in ipairs(held) do
    local function row(id)
      local p = vim.api.nvim_buf_get_extmark_by_id(buf, fix_ns, id, {})
      vim.api.nvim_buf_del_extmark(buf, fix_ns, id)
      return p[1]
    end
    local anchor, s, e = row(h.anchor), row(h.s), row(h.e)
    local cr
    for r = anchor - 1, math.max(0, anchor - #added), -1 do
      if vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1] == h.f.line then
        cr = r
        break
      end
    end
    if cr and e - s == #h.f.old - 1 and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, s, e + 1, false), h.f.old) then
      show_fix(buf, cr, s, e, h.f)
      shown = shown + 1
    end
  end
  return #added, n_del, n_reopen, shown
end

---Location list of every CR line in buf.
function M.list(buf)
  local items = {}
  for _, c in ipairs(M.comments(buf)) do
    items[#items + 1] = { bufnr = buf, lnum = c.s + 1, col = 1, text = vim.trim(c.text:gsub("\n", " ")) }
  end
  return items
end

local busy = {}

-- The review's status: one note at the end of the cursor's line in the file
-- under review, moved along with the cursor (goose's "writing…" look), so it
-- stays in view wherever you go and never takes a key. It reads "reviewing…"
-- while claude reads, then turns into the result, which stays until the first
-- key pressed in that file once M.result_ms has passed, so it is still there
-- after looking away. (A bottom-line message alone went at the next cursor
-- move, and a note on line 1 scrolled out of view.)
M.result_ms = 4000
local status = {} -- buf -> { mark, row, text, hl, done (ms), group }
local key_ns = vim.api.nvim_create_namespace "seconder.key"

local function place(buf)
  local st = status[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local win = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  if win ~= -1 then
    st.row = vim.api.nvim_win_get_cursor(win)[1] - 1
  end
  st.row = math.min(st.row or 0, vim.api.nvim_buf_line_count(buf) - 1)
  st.mark = vim.api.nvim_buf_set_extmark(buf, ns, st.row, 0, {
    id = st.mark,
    virt_text = { { "  " .. st.text, st.hl } },
    virt_text_pos = "eol",
  })
end

local function clear(buf)
  local st = status[buf]
  if not st then
    return
  end
  status[buf] = nil
  pcall(vim.api.nvim_del_augroup_by_id, st.group)
  if st.mark then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, st.mark)
  end
end

-- A result goes at the first key in its file after M.result_ms.
local function on_key()
  local buf = vim.api.nvim_get_current_buf()
  local st = status[buf]
  if st and st.done and vim.uv.now() - st.done >= M.result_ms then
    vim.schedule(function()
      if status[buf] == st then
        clear(buf)
      end
      if not next(status) then
        vim.on_key(nil, key_ns)
      end
    end)
  end
end

local function show(buf, text, hl)
  clear(buf)
  local group = vim.api.nvim_create_augroup("seconder.status." .. buf, { clear = true })
  status[buf] = { text = text, hl = hl, group = group }
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufWinEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      place(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    buffer = buf,
    callback = function()
      status[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  place(buf)
end

local function finish(buf, text, hl)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  show(buf, text, hl)
  status[buf].done = vim.uv.now()
  vim.on_key(on_key, key_ns)
end

---The status note's text in buf ("" when none shows), for tests.
function M.status(buf)
  local st = status[buf or vim.api.nvim_get_current_buf()]
  return st and st.text or ""
end

function M.review(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if busy[buf] then
    return vim.notify "seconder: already reviewing this file"
  end
  busy[buf] = true
  prune(buf)
  local prompt, snapshot, rules = M.prompt_for(buf)
  show(buf, "seconder reviewing…", "DiagnosticVirtualTextInfo")
  goose.ask(SYSTEM, prompt, function(out, err)
    busy[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local ans = out and decode(out)
    if not ans then
      finish(buf, "seconder: review failed", "DiagnosticVirtualTextError")
      return vim.notify("seconder: " .. (err or ("no JSON in answer: " .. (out or ""):sub(1, 200))), vim.log.levels.ERROR)
    end
    local added, deleted, reopened, fixed = apply(buf, ans, snapshot, rules)
    vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), state_file(buf))
    local items = M.list(buf)
    vim.fn.setloclist(0, items, "r")
    vim.fn.setloclist(0, {}, "a", { title = "seconder" })
    M.last = { verdict = ans.verdict, reason = ans.reason, added = added, deleted = deleted, reopened = reopened, fixes = fixed }
    local text, hl
    if #items == 0 then
      text, hl = "seconder: no issues", "DiagnosticVirtualTextOk"
    else
      text = ("seconder: %d comment%s, ]r jumps to them"):format(#items, #items == 1 and "" or "s")
      hl = "DiagnosticVirtualTextWarn"
    end
    finish(buf, text, hl)
    local changes = {}
    for _, c in ipairs { { added, "new" }, { deleted, "closed" }, { reopened, "reopened" }, { fixed, "with a fix (" .. KEY .. ")" } } do
      if c[1] > 0 then
        changes[#changes + 1] = c[1] .. " " .. c[2]
      end
    end
    local extra = #changes > 0 and (" (" .. table.concat(changes, ", ") .. ")") or ""
    vim.notify(("%s%s. %s"):format(text, extra, ans.reason or ""))
  end)
end

---Jump to the next (dir 1) or previous (dir -1) CR line.
function M.jump(dir)
  local cur = vim.fn.line "." - 1
  local cs = M.comments(0)
  local pick
  for i = dir > 0 and 1 or #cs, dir > 0 and #cs or 1, dir do
    if (dir > 0 and cs[i].s > cur) or (dir < 0 and cs[i].s < cur) then
      pick = cs[i]
      break
    end
  end
  pick = pick or cs[dir > 0 and 1 or #cs] -- wrap
  if pick then
    vim.api.nvim_win_set_cursor(0, { pick.s + 1, 0 })
  else
    vim.notify "seconder: no CRs here"
  end
end

function M.setup()
  local map = vim.keymap.set
  map({ "n", "x" }, "<leader>r", function()
    M.review()
  end, { desc = "Review (seconder CRs)" })
  map("n", "]r", function()
    M.jump(1)
  end, { desc = "Next CR" })
  map("n", "[r", function()
    M.jump(-1)
  end, { desc = "Previous CR" })
  -- VS Code's Quick Fix is Ctrl+. (Cmd+. on the Mac): Alt+. / Cmd+. here.
  local chord = require("util").chord
  local desc = "Seconder: apply the fix shown under the cursor's CR-soon (one u undoes)"
  map("n", chord ".", function()
    M.accept_fix()
  end, { desc = desc })
  map("i", chord ".", function()
    vim.cmd.stopinsert()
    vim.schedule(function()
      M.accept_fix()
    end)
  end, { desc = desc })
  map("x", chord ".", function()
    vim.cmd "normal! \27"
    M.accept_fix()
  end, { desc = desc })
end

return M
