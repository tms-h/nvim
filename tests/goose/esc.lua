-- Esc Esc forgets the goose draft (the typed lines were real code); a single
-- Esc, a slow second Esc, or an Esc in another buffer keeps it.
-- Run: tests/goose/run.sh   (headless, no network, no desktop keys)
local lib = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/lib.lua")
local g = require "goose"
g.setup()
g.prewarm = false
g.double_esc_ms = 150
local dir = vim.env.GOOSE_TEST_DIR

local check = lib.check
local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "xt", false)
  vim.wait(20) -- let the scheduled clear run
end
local function blocks(buf)
  return #g.draft_blocks(buf)
end

local n = 0
local function open()
  n = n + 1
  local file = ("%s/e%d.ml"):format(dir, n)
  vim.fn.writefile({ "let x = 1" }, file)
  vim.cmd.edit(file)
  return vim.api.nvim_get_current_buf()
end

local buf = open()
keys "otake the max<Esc>"
check("one Esc keeps the draft", blocks(buf) == 1, blocks(buf))
vim.wait(300)

keys "olet y = 2<Esc><Esc>"
check("Esc Esc straight after typing clears the draft", blocks(buf) == 0, blocks(buf))

keys "olet z = 3<Esc>"
vim.wait(300)
keys "<Esc>"
check("a slow second Esc keeps the draft", blocks(buf) == 1, blocks(buf))
vim.wait(300)

keys "<Esc><Esc>"
check("Esc Esc in normal mode clears the draft", blocks(buf) == 0, blocks(buf))

keys "osum the list<Esc>"
local other = open()
keys "<Esc>"
vim.cmd.buffer(buf)
check("an Esc in another buffer does not pair up", blocks(buf) == 1, blocks(buf))
vim.api.nvim_buf_delete(other, { force = true })

lib.finish "goose esc"
