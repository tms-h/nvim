-- Seconder: a Jane Street-style reviewer that only writes CR comments.
--
--   Space r   review this file: adds CR / CR-soon comments, deletes ones it is
--             satisfied with, reopens XCRs it is not. Never edits code. A
--             note on the cursor's line says "reviewing…", then "no issues"
--             or how many comments there are.
--   ]r / [r   next / previous CR, CR-soon or XCR line (the list also goes to
--             the location list after a review).
--
-- Reply to a CR by turning it into `XCR thomas: <why>`; the next Space r reads
-- it. The rubric is rubric/seconder.md (condensed from the js-wiki articles);
-- an optional REVIEW.md at the project root adds house rules. Each review
-- stores what it read under stdpath('state')/seconder/, so the next one is
-- told only what changed since ("review brain").
local M = {}

local goose = require "goose"
local ns = vim.api.nvim_create_namespace "seconder"

local here = debug.getinfo(1, "S").source:sub(2)
local RUBRIC = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(here)), "rubric", "seconder.md")

local CR_LINE = "%f[%w]X?CR[%-%w]*%s+[%w_.%-]+%s*:"
M.pattern = CR_LINE

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

local function state_file(buf)
  local dir = vim.fs.joinpath(vim.fn.stdpath "state", "seconder")
  vim.fn.mkdir(dir, "p")
  return vim.fs.joinpath(dir, vim.fn.sha256(vim.api.nvim_buf_get_name(buf)):sub(1, 16) .. ".txt")
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
          "kind": "CR" | "CR-soon", "text": "<concrete, failing input first>"}],
 "delete": [<comment id>],
 "reopen": [{"id": <comment id>, "text": "<why it still fails>"}]}
Comment ids refer to the "Existing CR comments" list. Do not add a CR that
repeats an existing one. Line numbers refer to the numbered file.]]

local function numbered(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = ("%4d| %s"):format(i, l)
  end
  return table.concat(out, "\n")
end

local function prompt_for(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local name = vim.api.nvim_buf_get_name(buf)
  local parts = { "Rubric:\n" .. (read(RUBRIC) or "") }
  local root = vim.fs.root(buf, { "REVIEW.md", ".git", "dune-project" })
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
  local rel = root and vim.fs.relpath and vim.fs.relpath(root, name) or vim.fn.fnamemodify(name, ":~:.")
  local dune = read(vim.fs.joinpath(vim.fs.dirname(name), "dune"))
  if dune then
    parts[#parts + 1] = "dune file in the same folder:\n" .. dune
  end
  parts[#parts + 1] = ("File %s:\n%s"):format(rel, numbered(lines))
  return table.concat(parts, "\n\n"), lines
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

-- Apply the answer: only comment lines change. Bottom-up so line numbers hold.
local function apply(buf, ans, snapshot)
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
  local edits = {}
  local cs = M.comments(buf)
  local by_id = {}
  for _, c in ipairs(cs) do
    by_id[c.id] = c
  end
  for _, id in ipairs(ans.delete or {}) do
    local c = by_id[tonumber(id)]
    if c then
      edits[#edits + 1] = { s = c.s, e = c.e + 1, lines = {} }
      by_id[c.id] = nil
    end
  end
  for _, r in ipairs(ans.reopen or {}) do
    local c = by_id[tonumber(r.id)]
    if c then
      local indent = now[c.s + 1]:match "^%s*"
      -- One comment again: the reopened CR, then the reply it answers.
      local reply = c.text:gsub("^%s*%(%*%s*", ""):gsub("%s*%*%)%s*$", ""):gsub("\n%s*", " ")
      reply = reply:gsub("^X?CR[%-%w]*%s+([%w_.%-]+)%s*:", "%1 replied:")
      local cr = comment(buf, indent, "CR", (r.text or "still open"))
      edits[#edits + 1] = { s = c.s, e = c.e + 1, lines = {
        (cr:gsub("%s*%*%)$", "")),
        indent .. "   " .. reply .. " *)",
      } }
      by_id[c.id] = nil
    end
  end
  for _, a in ipairs(ans.add or {}) do
    local l = locate(tonumber(a.line) or 0)
    if l and a.text then
      local kind = a.kind == "CR-soon" and "CR-soon" or "CR"
      edits[#edits + 1] = { s = l - 1, e = l - 1, lines = { comment(buf, now[l]:match "^%s*", kind, a.text) } }
    end
  end
  table.sort(edits, function(x, y)
    return x.s > y.s
  end)
  for _, ed in ipairs(edits) do
    vim.api.nvim_buf_set_lines(buf, ed.s, ed.e, false, ed.lines)
  end
  return #(ans.add or {}), #(ans.delete or {}), #(ans.reopen or {})
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
  local prompt, snapshot = prompt_for(buf)
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
    local added, deleted, reopened = apply(buf, ans, snapshot)
    vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), state_file(buf))
    local items = M.list(buf)
    vim.fn.setloclist(0, items, "r")
    vim.fn.setloclist(0, {}, "a", { title = "seconder" })
    M.last = { verdict = ans.verdict, reason = ans.reason, added = added, deleted = deleted, reopened = reopened }
    local text, hl
    if #items == 0 then
      text, hl = "seconder: no issues", "DiagnosticVirtualTextOk"
    else
      text = ("seconder: %d comment%s, ]r jumps to them"):format(#items, #items == 1 and "" or "s")
      hl = "DiagnosticVirtualTextWarn"
    end
    finish(buf, text, hl)
    local changes = {}
    for _, c in ipairs { { added, "new" }, { deleted, "closed" }, { reopened, "reopened" } } do
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
end

return M
