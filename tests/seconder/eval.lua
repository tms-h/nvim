-- Seconder eval, one mode per run (tests/seconder/eval.sh starts it): every
-- fixture in fixtures/manifest.json is reviewed once with the real goose.ask,
-- at most `PARALLEL` claude calls at a time. A CR counts as catching a plant
-- when it names the plant's rule (or an alt rule), or sits within 2 lines of
-- the plant and its text has one of the plant's keywords. Every other CR is a
-- false positive (all CRs on a clean file are).
--   EVAL_MODE   before (base rubric only) | after (with rubric/wiki-rules.json)
--   EVAL_OUT    where the JSON results go
--   EVAL_WORK   scratch folder (one project per fixture)
--   SECONDER_ROOT  the config checkout under test
local root, mode, work = vim.env.SECONDER_ROOT, vim.env.EVAL_MODE, vim.env.EVAL_WORK
local PARALLEL = 4
local fixtures = root .. "/tests/seconder/fixtures"
local manifest = vim.json.decode(table.concat(vim.fn.readfile(fixtures .. "/manifest.json"), "\n"))
for _, m in ipairs(manifest) do
  if m.rule == vim.NIL then -- a clean file
    m.rule = nil
  end
end
local g, sec = require "goose", require "seconder"
vim.notify = function() end -- the review's own messages; the table below says it all

-- Same inputs in both modes but the rules: no personal checklist.
sec.checklist_path = nil
if mode == "before" then
  sec.rules_path = work .. "/no-rules.json"
end

-- Real calls, throttled; each answer is kept by case.
local real_ask, running, queue, raw = g.ask, 0, {}, {}
local current
local function pump()
  while running < PARALLEL and #queue > 0 do
    local job = table.remove(queue, 1)
    running = running + 1
    real_ask(job.system, job.prompt, function(out, err)
      running = running - 1
      raw[job.case] = { out = out, err = err, prompt_chars = #job.prompt }
      job.cb(out, err)
      pump()
    end, job.opts)
  end
end
g.ask = function(system, prompt, cb, opts)
  queue[#queue + 1] = { case = current, system = system, prompt = prompt, cb = cb, opts = opts }
  pump()
end

local bufs = {}
for _, m in ipairs(manifest) do
  local dir = work .. "/" .. m.case
  vim.fn.mkdir(dir, "p")
  for _, f in ipairs(vim.fn.readdir(fixtures .. "/" .. m.case)) do
    if f ~= m.previous then
      vim.fn.writefile(vim.fn.readfile(fixtures .. "/" .. m.case .. "/" .. f), dir .. "/" .. f)
    end
  end
  vim.fn.writefile({ "(lang dune 3.0)" }, dir .. "/dune-project")
  vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/" .. m.file))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].commentstring = "(* %s *)"
  if m.previous then
    -- The seconder's "last review" of this file: the version before the fix,
    -- so the prompt shows the fix as the change since then.
    local state = vim.fs.joinpath(vim.fn.stdpath "state", "seconder")
    vim.fn.mkdir(state, "p")
    local name = vim.fn.sha256(vim.api.nvim_buf_get_name(buf)):sub(1, 16) .. ".txt"
    vim.fn.writefile(vim.fn.readfile(fixtures .. "/" .. m.case .. "/" .. m.previous), state .. "/" .. name)
  end
  bufs[m.case] = buf
  current = m.case
  sec.review(buf)
end
current = nil

vim.wait(20 * 60 * 1000, function()
  return vim.tbl_count(raw) == #manifest
end, 500)

local function has_keyword(text, words)
  text = text:lower()
  for _, w in ipairs(words or {}) do
    if text:find(w:lower(), 1, true) then
      return true
    end
  end
  return false
end

local results, totals = {}, { caught = 0, missed = 0, fp = 0, crs = 0, calls = 0, wiki_tagged = 0, plants = 0 }
for _, m in ipairs(manifest) do
  local r = raw[m.case] or {}
  totals.calls = totals.calls + 1
  local ans = r.out and r.out:match "%b{}"
  local ok, v = pcall(vim.json.decode, ans or "")
  local adds = ok and type(v) == "table" and type(v.add) == "table" and v.add or {}
  local res = { case = m.case, file = m.file, rule = m.rule, error = r.err, verdict = ok and v and v.verdict, crs = {} }
  local caught = false
  for _, a in ipairs(adds) do
    local rule = type(a.rule) == "string" and a.rule or nil
    local line = tonumber(a.line) or 0
    local hit = false
    if m.rule then
      local named = rule == m.rule or vim.tbl_contains(m.alt_rules or {}, rule)
      local near = m.lines and line >= m.lines[1] - 2 and line <= m.lines[2] + 2
      hit = named or (near and has_keyword(tostring(a.text), m.keywords))
    end
    caught = caught or hit
    res.crs[#res.crs + 1] = { line = line, kind = a.kind, rule = rule, text = a.text, plant = hit, fix = a.fix ~= nil }
    totals.crs = totals.crs + 1
    if not hit then
      totals.fp = totals.fp + 1
    end
  end
  -- The CR lines written into the buffer: a rule's CR must end with (wiki: page).
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufs[m.case], 0, -1, false)) do
    if l:find "CR[%-%w]* claude:" and l:find("(wiki: ", 1, true) then
      totals.wiki_tagged = totals.wiki_tagged + 1
    end
  end
  if m.rule then
    totals.plants = totals.plants + 1
    res.caught = caught
    totals[caught and "caught" or "missed"] = totals[caught and "caught" or "missed"] + 1
  end
  results[#results + 1] = res
end

vim.fn.writefile({ vim.json.encode { mode = mode, totals = totals, results = results } }, vim.env.EVAL_OUT)
local out = {}
for _, res in ipairs(results) do
  local tag = res.rule and (res.caught and "caught" or "MISSED") or "clean"
  out[#out + 1] = ("%-16s %-7s %d CRs%s"):format(
    res.case,
    tag,
    #res.crs,
    res.error and ("  error: " .. res.error:sub(1, 80)) or ""
  )
  for _, c in ipairs(res.crs) do
    out[#out + 1] = ("    %s %-7s L%-3d [%s] %s"):format(
      c.plant and "+" or "-",
      c.kind or "?",
      c.line,
      c.rule or "-",
      tostring(c.text):sub(1, 150)
    )
  end
end
out[#out + 1] = ("%s: caught %d/%d, missed %d, false positives %d of %d CRs, wiki-tagged CR lines %d, calls %d"):format(
  mode,
  totals.caught,
  totals.plants,
  totals.missed,
  totals.fp,
  totals.crs,
  totals.wiki_tagged,
  totals.calls
)
io.stdout:write(table.concat(out, "\n") .. "\n")
vim.cmd "qa!"
