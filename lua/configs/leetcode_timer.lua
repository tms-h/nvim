--- Timing + CSV logging for kawre/leetcode.nvim
--- Starts on question_enter; logs a row on each Run (test) and on Submit.
--- Live elapsed time: right-aligned virtual text on the last buffer line (away from top-corner notifications).

local M = {}

local patched        = false
local result_patched = false

---@type integer? hrtime ns when current session started
local session_start_ns = nil

---@type table?
local session_meta = nil

local ns_id = vim.api.nvim_create_namespace("leetcode_timer")

--- uv_timer updating the display
local display_timer = nil

--- buffer where the extmark is drawn
local display_bufnr = nil

local TICK_MS = 500

--- Prefer bottom line so right-aligned text avoids top-corner notification stacks (noice, etc.).
local function timer_row(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end
  local n = vim.api.nvim_buf_line_count(bufnr)
  return math.max(0, n - 1)
end

local function format_elapsed(sec)
  sec = math.floor(sec)
  local s = sec % 60
  local m = math.floor(sec / 60) % 60
  local h = math.floor(sec / 3600)
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function tick_display()
  if not session_start_ns or not display_bufnr then
    return
  end
  if not vim.api.nvim_buf_is_valid(display_bufnr) then
    M.stop_display_timer()
    return
  end
  local elapsed = (vim.uv.hrtime() - session_start_ns) / 1e9
  local row = timer_row(display_bufnr)
  local text = " ⏱ " .. format_elapsed(elapsed) .. " "
  vim.api.nvim_buf_clear_namespace(display_bufnr, ns_id, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, display_bufnr, ns_id, row, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
    priority = 20000,
  })
end

--- Stop ticking and leave final time on buffer (after submit).
---@param elapsed_sec number
function M.freeze_timer_display(elapsed_sec)
  if display_timer then
    display_timer:stop()
    display_timer:close()
    display_timer = nil
  end
  session_start_ns = nil
  session_meta = nil
  if not display_bufnr or not vim.api.nvim_buf_is_valid(display_bufnr) then
    return
  end
  local row = timer_row(display_bufnr)
  local text = (" ⏱ %s · submitted "):format(format_elapsed(elapsed_sec))
  vim.api.nvim_buf_clear_namespace(display_bufnr, ns_id, 0, -1)
  pcall(vim.api.nvim_buf_set_extmark, display_bufnr, ns_id, row, 0, {
    virt_text = { { text, "DiagnosticOk" } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
    priority = 20000,
  })
end

--- Stop timer and remove all timer marks (new problem or leaving Leet).
function M.stop_display_timer()
  if display_timer then
    display_timer:stop()
    display_timer:close()
    display_timer = nil
  end
  local buf = display_bufnr
  display_bufnr = nil
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns_id, 0, -1)
  end
end

local function start_display_timer(bufnr)
  M.stop_display_timer()
  if not bufnr or bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  display_bufnr = bufnr
  display_timer = assert(vim.uv.new_timer())
  display_timer:start(0, TICK_MS, vim.schedule_wrap(tick_display))
  vim.schedule(tick_display)
end

local function csv_escape(val)
  local s = tostring(val == nil and "" or val)
  if s:find('[,"\r\n]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

local function tags_str(q)
  local tags = q.topic_tags
  if not tags or #tags == 0 then
    return ""
  end
  local parts = {}
  for _, t in ipairs(tags) do
    if type(t) == "table" and t.name then
      table.insert(parts, t.name)
    elseif type(t) == "string" then
      table.insert(parts, t)
    end
  end
  return table.concat(parts, "|")
end

local function csv_path()
  local data = vim.fn.stdpath("data") .. "/leetcode"
  vim.fn.mkdir(data, "p")
  return data .. "/leetcode_timing_events.csv"
end

local header =
  "iso_ts,session_id,event,elapsed_ms,elapsed_sec,frontend_id,question_id,title_slug,title,difficulty,tags,lang"

local function append_row(row)
  local path = csv_path()
  local need_header = vim.fn.filereadable(path) == 0
  local f = io.open(path, "a")
  if not f then
    return
  end
  if need_header then
    f:write(header .. "\n")
  end
  f:write(table.concat(row, ",") .. "\n")
  f:close()
end

local function iso_timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function new_session_id()
  math.randomseed(vim.uv.hrtime())
  return ("%x-%x"):format(math.random(0, 0xffffffff), vim.uv.hrtime() % 0x100000000)
end

--- Called from hooks.question_enter
---@param question lc.ui.Question
function M.on_question_enter(question)
  session_start_ns = vim.uv.hrtime()
  local q = question.q
  session_meta = {
    id = new_session_id(),
    frontend_id = q.frontend_id or "",
    question_id = q.id or "",
    title_slug = q.title_slug or "",
    title = q.title or "",
    difficulty = q.difficulty or "",
    tags = tags_str(q),
    lang = question.lang or "",
  }

  local elapsed_ms = 0
  append_row({
    csv_escape(iso_timestamp()),
    csv_escape(session_meta.id),
    csv_escape("start"),
    csv_escape(string.format("%.3f", elapsed_ms)),
    csv_escape(string.format("%.6f", elapsed_ms / 1000)),
    csv_escape(session_meta.frontend_id),
    csv_escape(session_meta.question_id),
    csv_escape(session_meta.title_slug),
    csv_escape(session_meta.title),
    csv_escape(session_meta.difficulty),
    csv_escape(session_meta.tags),
    csv_escape(session_meta.lang),
  })

  start_display_timer(question.bufnr)
end

---@param submit boolean
function M.on_runner_run(question, submit)
  if not session_start_ns or not session_meta then
    return
  end
  local elapsed_ns = vim.uv.hrtime() - session_start_ns
  local elapsed_ms = elapsed_ns / 1e6
  local event = submit and "submit" or "test"

  append_row({
    csv_escape(iso_timestamp()),
    csv_escape(session_meta.id),
    csv_escape(event),
    csv_escape(string.format("%.3f", elapsed_ms)),
    csv_escape(string.format("%.6f", elapsed_ms / 1000)),
    csv_escape(session_meta.frontend_id),
    csv_escape(session_meta.question_id),
    csv_escape(session_meta.title_slug),
    csv_escape(session_meta.title),
    csv_escape(session_meta.difficulty),
    csv_escape(session_meta.tags),
    csv_escape(session_meta.lang),
  })

end

--- Called from hooks.leave when closing leetcode.nvim session.
function M.on_leave()
  session_start_ns = nil
  session_meta = nil
  M.stop_display_timer()
end

--- Freeze display and log submit_ac only when the submission is Accepted.
--- Patched into ResultPopup:handle; status_code 10 == "Accepted" in LeetCode's API.
function M.patch_result()
  if result_patched then
    return
  end
  local ok, ResultPopup = pcall(require, "leetcode-ui.popup.console.result")
  if not ok or not ResultPopup then
    return
  end
  result_patched = true
  local orig = ResultPopup.handle
  ResultPopup.handle = function(self, item)
    orig(self, item)
    if item._.submission and item.status_code == 10 and session_start_ns and session_meta then
      local elapsed_ns = vim.uv.hrtime() - session_start_ns
      local elapsed_ms = elapsed_ns / 1e6
      append_row({
        csv_escape(iso_timestamp()),
        csv_escape(session_meta.id),
        csv_escape("submit_ac"),
        csv_escape(string.format("%.3f", elapsed_ms)),
        csv_escape(string.format("%.6f", elapsed_ms / 1000)),
        csv_escape(session_meta.frontend_id),
        csv_escape(session_meta.question_id),
        csv_escape(session_meta.title_slug),
        csv_escape(session_meta.title),
        csv_escape(session_meta.difficulty),
        csv_escape(session_meta.tags),
        csv_escape(session_meta.lang),
      })
      M.freeze_timer_display(elapsed_ns / 1e9)
    end
  end
end

--- Must run only after `leetcode`'s `config.setup()` (e.g. `hooks.enter`), never from Lazy `config`:
--- requiring `leetcode.runner` loads `leetcode.cache.cookie`, which needs `config.storage.cache`.
function M.patch_runner()
  if patched then
    return
  end
  local ok, Runner = pcall(require, "leetcode.runner")
  if not ok or not Runner then
    return
  end
  patched = true
  local orig = Runner.run
  Runner.run = function(self, submit)
    -- Skip when runner would early-return ("Runner is busy") — no real run/submit.
    -- Runner.running is an internal field of kawre/leetcode.nvim; may break on upstream changes.
    if not Runner.running and self and self.question then
      M.on_runner_run(self.question, submit == true)
    end
    return orig(self, submit)
  end
  M.patch_result()
end

return M
