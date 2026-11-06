-- Pseudocode to code (John Crepezzi, Signals and Threads ep 31: "type
-- pseudocode... when you exit insert mode, it turns it into real code... it
-- can only edit the area that you typed in").
--
--   Goose ("loosey-goosey mode"): type pseudocode with plain i/a/o and Esc;
--   nothing fires. The lines typed since the last send are the draft (dotted
--   underline); an insert away from the draft replaces it.
--   Alt+K / Cmd+K (Cursor's inline edit key), :Goose  send the draft to
--     `claude -p`. In a selection, sends the selected lines.
--   While it writes: the region greys out with "writing…"; edit elsewhere
--   freely. An edit inside the region throws the answer away. One `u` brings
--   the pseudocode back.
--
-- ask() is shared with seconder.lua.
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

local function clear(buf, mark)
  pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark)
  if pending[buf] then
    pending[buf][mark] = nil
  end
  vim.cmd.redrawstatus()
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

local run

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
  M.ask(SYSTEM, prompt_for(buf, s, e, lines, errors), function(out, err)
    finish(buf, mark, out, err, errors ~= nil)
  end)
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
end

---Send the draft (or nothing). Called after the insert has ended.
function M.send()
  local buf = vim.api.nvim_get_current_buf()
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
