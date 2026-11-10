-- Driven by tests/lsp-first-build.sh: open FILE, build, read the diagnostics.
local out = {}
local function diags()
  local t = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    t[#t + 1] = d.message:match "^[^\n]*"
  end
  return #t == 0 and "(none)" or table.concat(t, " | ")
end
local function client()
  return vim.lsp.get_clients({ name = "ocamllsp", bufnr = 0 })[1]
end
vim.cmd.edit(vim.env.FILE or "bin/main.ml")
vim.wait(15000, function()
  return client() ~= nil
end)
local first = client().id
vim.wait(4000, function()
  return #vim.diagnostic.get(0) > 0
end)
out[#out + 1] = "before build: " .. diags()
local opam = vim.fn.expand "~/.opam/default/bin/"
local cmd = vim.env.WATCH and { opam .. "dune", vim.env.WATCH, "-w" } or { opam .. "dune", "build" }
local job = vim.system(cmd, { env = { PATH = opam .. ":" .. vim.env.PATH } })
if not vim.env.WATCH then
  job:wait()
end
local restarted = vim.wait(20000, function()
  local c = client()
  return c ~= nil and c.id ~= first
end)
out[#out + 1] = "new server attached: " .. tostring(restarted)
vim.wait(6000, function()
  return false
end)
out[#out + 1] = "after build, no edit: " .. diags()
if vim.env.WATCH then
  job:kill(15)
end
vim.fn.writefile(out, vim.env.REPRO_OUT)
vim.cmd "qa!"
