-- Iron, Jane Street's code review tool, as mini-iron's `fe` (~/Work/mini-iron):
--   Space i t  the fe todo: features to review first, then features you own
--   Space i r  review what is left in the feature the current file belongs to
--   Space i c  a CR comment above the cursor line, ready to type
-- The todo and review buffers have their own keys (Enter, s, e, r, a, m, R);
-- see the top of mini-iron's nvim/src/fe_nvim.ml.
--
-- The work is done by fe-nvim, mini-iron's vcaml plugin (OCaml), started as a
-- job on the first key press: it fires `User FeNvimReady` with its channel,
-- and the key that started it then runs. This file only owns the keys.
-- Without fe-nvim on PATH (installed next to fe), a key says so in one line.
local M = {}

local tools = require "tools"

local job, channel
local pending -- the RPC asked for while fe-nvim was starting

local function say(text)
  vim.notify("Iron: " .. text, vim.log.levels.WARN)
end

local function request(rpc)
  local ok, err = pcall(vim.rpcrequest, channel, rpc)
  if not ok then
    say(tostring(err))
  end
end

local function start()
  local exe = tools.find "fe-nvim"
  if not exe then
    say "fe-nvim is not on PATH; install mini-iron (its README)"
    return false
  end
  if job then
    return true
  end
  local stderr = {}
  job = vim.fn.jobstart({ exe }, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      stderr = data
    end,
    on_exit = function(_, code)
      job, channel, pending = nil, nil, nil
      if code ~= 0 and vim.v.exiting == vim.NIL then
        say(("fe-nvim exited with code %d: %s"):format(code, vim.trim(table.concat(stderr, "\n"))))
      end
    end,
  })
  if job <= 0 then
    job = nil
    say "could not start fe-nvim"
    return false
  end
  return true
end

---A key's action: run fe-nvim's `rpc`, starting fe-nvim first if needed.
local function call(rpc)
  return function()
    if channel then
      request(rpc)
    elseif start() then
      pending = rpc
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("Iron", { clear = true }),
    pattern = "FeNvimReady",
    callback = function(args)
      channel = args.data
      local rpc = pending
      pending = nil
      if rpc then
        -- After fe-nvim's own call into Neovim has returned.
        vim.schedule(function()
          request(rpc)
        end)
      end
    end,
  })
  local map = vim.keymap.set
  map("n", "<Leader>it", call "todo", { desc = "Iron todo: features to review, then yours" })
  map("n", "<Leader>ir", call "review", { desc = "Iron review this file's feature" })
  map("n", "<Leader>ic", call "insert-cr", { desc = "Iron CR above this line; on a CR, reply (CR <-> XCR)" })
end

return M
