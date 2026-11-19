-- Shared by the goose test files (tests/goose/run.sh): one "pass"/"FAIL" line
-- per check, keys typed as a keyboard would, the stub claude, waiting for
-- goose to go idle, the Alt+L box's text, and the summary line with the exit
-- status. Load with dofile(<this folder> .. "/lib.lua").
local M = { pass = 0, fail = 0 }
M.here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

function M.check(name, ok, detail)
  if ok then
    M.pass = M.pass + 1
    io.stdout:write("pass  " .. name .. "\n")
  else
    M.fail = M.fail + 1
    io.stdout:write("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "") .. "\n")
  end
end

function M.keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "xt", false)
end

---Run goose's sessions on the stub claude (tests/goose/stub-claude.py), which
---logs each message it gets to `log` and answers after `delay` seconds.
function M.stub(g, log, delay)
  vim.env.GOOSE_STUB_LOG = log
  vim.env.GOOSE_STUB_DELAY = delay
  g.session_argv = { "python3", "-I", M.here .. "/stub-claude.py" }
end

---Wait until goose `g` has no pending edit left in `buf`: 100 ms for the
---edit to start, then up to 5 s. True if it finished in time.
function M.wait_idle(g, buf)
  vim.wait(100)
  return vim.wait(5000, function()
    return g.pending_count(buf) == 0
  end, 20)
end

---The text of `buf`'s Alt+L chat box (goose_ask `ask`), "" when it has none.
function M.chat_text(ask, buf)
  local c = ask.chat(buf)
  return c and c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n") or ""
end

---Print "<label>: N pass, M fail" and quit; exit status 1 when any check failed.
function M.finish(label)
  io.stdout:write(("%s: %d pass, %d fail\n"):format(label, M.pass, M.fail))
  vim.cmd(M.fail == 0 and "qa!" or "cquit 1")
end

return M
