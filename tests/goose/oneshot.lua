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
check(
  "an insert two lines away adds a second block",
  #g.draft_blocks(buf) == 2 and dr() == "3-4",
  vim.inspect(g.draft_blocks(buf))
)
keys "<M-k>"
wait_idle()
check("Alt+K sends both blocks", L(3, 5) == "CODE1||CODE2", L(3, 5))
check(
  "each block is its own region",
  #sent == 2
    and sent[1]:find("<<<REGION\npseudo a\npseudo b\nREGION>>>", 1, true) ~= nil
    and sent[2]:find("<<<REGION\n # far\nREGION>>>", 1, true) ~= nil
)
keys "u"
check("one u brings the last block's pseudocode back", L(5, 5) == " # far", L(5, 5))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
keys "A more<M-k>"
wait_idle()
check("Alt+K from insert mode", L(4, 4) == "CODE3", L(4, 4))
keys "<M-k>"
check("Alt+K with nothing typed sends nothing", #sent == 3, #sent)
keys "Gopseudo last<Esc>"
keys "<M-k>"
vim.cmd "silent write"
check(":w while writing keeps it pending", g.pending_count(buf) == 1)
wait_idle()
check("last-line draft lands", L(9, 9) == "CODE4", L(8, 9))
keys "ggVj<M-k>"
wait_idle()
check("a selection sends the selected lines", L(1, 1) == "CODE5", L(1, 3))
io.stdout:write(("goose one-shot: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit 1")
