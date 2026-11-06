-- Goose draft rules on the one-shot path (use_session = false), with a stub
-- ask. Run: tests/goose/run.sh
local g = require "goose"
g.setup()
g.use_session = false
g.flash_ms = 50
local dir = vim.env.GOOSE_TEST_DIR
local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    io.stdout:write("pass  " .. name .. "\n")
  else
    fail = fail + 1
    io.stdout:write("FAIL  " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or "") .. "\n")
  end
end
local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "xt", false)
end
vim.fn.writefile({ "def total(orders):", "    return 0", "", "", "", "x = 1", "y = 2", "z = 3" }, dir .. "/t.py")
vim.cmd.edit(dir .. "/t.py")
local buf = vim.api.nvim_get_current_buf()
local sent = {}
g.ask = function(_, prompt, cb)
  sent[#sent + 1] = prompt
  local id = #sent
  vim.defer_fn(function()
    cb("CODE" .. id)
  end, 100)
end
local function dr()
  local s, e = g.draft_range(buf)
  return s and (s + 1 .. "-" .. e + 1) or "none"
end
local function L(a, b)
  return table.concat(vim.api.nvim_buf_get_lines(buf, a - 1, b, false), "|")
end
local function wait_idle()
  vim.wait(50)
  vim.wait(2000, function()
    return g.pending_count(buf) == 0
  end, 20)
end

vim.api.nvim_win_set_cursor(0, { 3, 0 })
keys "ipseudo a<Esc>"
keys "opseudo b<Esc>"
check("two inserts with Esc between: no call, one draft", #sent == 0 and dr() == "3-4", #sent .. " " .. dr())
vim.api.nvim_win_set_cursor(0, { 6, 0 })
keys "A # far<Esc>"
check("an insert two lines away replaces the draft", dr() == "6-6", dr())
keys "<M-k>"
wait_idle()
check("Alt+K sends only the draft", L(3, 6) == "pseudo a|pseudo b||CODE1", L(3, 6))
check("only the draft is in the region", sent[1]:find("<<<REGION\n # far\nREGION>>>", 1, true) ~= nil)
keys "u"
check("one u brings the pseudocode back", L(6, 6) == " # far", L(6, 6))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
keys "A more<M-k>"
wait_idle()
check("Alt+K from insert mode", L(4, 4) == "CODE2", L(4, 4))
keys "<M-k>"
check("Alt+K with nothing typed sends nothing", #sent == 2, #sent)
keys "Gopseudo last<Esc>"
keys "<M-k>"
vim.cmd "silent write"
check(":w while writing keeps it pending", g.pending_count(buf) == 1)
wait_idle()
check("last-line draft lands", L(10, 10) == "CODE3", L(9, 10))
keys "ggVj<M-k>"
wait_idle()
check("a selection sends the selected lines", L(1, 1) == "CODE4", L(1, 3))
io.stdout:write(("goose one-shot: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit 1")
