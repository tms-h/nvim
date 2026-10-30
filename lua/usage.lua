-- Silent usage counter: how often each custom mapping and each typed `:`
-- command is used. Counts live in memory and are appended
-- (as deltas) to ~/.local/state/nvim/usage/counts.jsonl on FocusLost and exit, so
-- there is no disk work per keystroke. :UsageReport sums every line written.
-- :FrictionNote <text> appends a timestamped line to usage/friction.md.
local M = {}

-- One log for every config generation (nvim, nvim-next...), so counts from the
-- old config still add up.
local dir = (vim.env.XDG_STATE_HOME or vim.fn.expand "~/.local/state") .. "/nvim/usage"
local counts_file = dir .. "/counts.jsonl"
local friction_file = dir .. "/friction.md"
local config_dir = vim.fn.stdpath "config"
local config_real = vim.uv.fs_realpath(config_dir) or config_dir

local counts = {}
local dirty = false

local function bump(key)
  counts[key] = (counts[key] or 0) + 1
  dirty = true
end

local function append(path, line)
  vim.fn.mkdir(dir, "p")
  local f = io.open(path, "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

local function flush()
  if not dirty then
    return
  end
  append(
    counts_file,
    vim.json.encode {
      t = os.date "%Y-%m-%dT%H:%M:%S",
      host = vim.uv.os_gethostname(),
      app = vim.env.NVIM_APPNAME or "nvim",
      counts = counts,
    }
  )
  counts, dirty = {}, false
end

-- Only mappings defined by this config are counted; plugins' internal
-- mappings are left alone.
local function is_custom_caller()
  local source = debug.getinfo(3, "S").source
  return source:find(config_dir, 1, true) ~= nil or source:find(config_real, 1, true) ~= nil
end

local function key_for(mode, lhs, opts)
  local modes = type(mode) == "table" and table.concat(mode, "") or mode
  local scope = opts.buffer and " (buffer)" or ""
  return "map " .. modes .. " " .. lhs .. scope .. (opts.desc and ("  -- " .. opts.desc) or "")
end

local set = vim.keymap.set
---@diagnostic disable-next-line: duplicate-set-field
vim.keymap.set = function(mode, lhs, rhs, opts)
  -- Pointer moves are not keys anyone pressed (dividers.lua).
  if lhs == "<MouseMove>" or not is_custom_caller() then
    return set(mode, lhs, rhs, opts)
  end
  opts = vim.deepcopy(opts or {})
  local key = key_for(mode, lhs, opts)
  if type(rhs) == "function" then
    local fn = rhs
    rhs = function(...)
      bump(key)
      return fn(...)
    end
  elseif type(rhs) == "string" and rhs:lower() == "<nop>" then
    -- A no-op is counted and does nothing (an expr map returning "<Nop>"
    -- still touched the buffer).
    opts.desc = opts.desc or rhs
    rhs = function()
      bump(key)
    end
  elseif type(rhs) == "string" and rhs ~= "" and not opts.expr then
    -- An expr mapping that returns the original keys behaves like the plain
    -- mapping (same keys, same remap and count handling).
    local keys = rhs
    if keys:lower():match "^<plug>" then
      opts.remap = true
    end
    opts.desc = opts.desc or keys
    opts.expr = true
    rhs = function()
      bump(key)
      return keys
    end
  end
  return set(mode, lhs, rhs, opts)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UsageLog", { clear = true })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      if vim.fn.getcmdtype() ~= ":" or vim.v.event.abort then
        return
      end
      local line = vim.fn.getcmdline()
      local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})
      local name = ok and parsed.cmd or (line:match "^%s*[%d,.$%%'<>]*%s*(%a+)" or line:sub(1, 20))
      if name ~= "" then
        bump("cmd :" .. name)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "FocusLost", "VimLeavePre" }, { group = group, callback = flush })

  vim.api.nvim_create_user_command("FrictionNote", function(args)
    local file = vim.fn.expand "%:~:."
    append(
      friction_file,
      string.format(
        "- %s  [%s:%d] %s",
        os.date "%Y-%m-%d %H:%M",
        file ~= "" and file or "-",
        vim.fn.line ".",
        args.args
      )
    )
  end, { nargs = "+", desc = "Jot down something that got in the way" })

  vim.api.nvim_create_user_command("UsageReport", function()
    flush()
    local total = {}
    local f = io.open(counts_file, "r")
    if f then
      for line in f:lines() do
        local ok, entry = pcall(vim.json.decode, line)
        if ok and type(entry) == "table" and type(entry.counts) == "table" then
          for k, n in pairs(entry.counts) do
            total[k] = (total[k] or 0) + n
          end
        end
      end
      f:close()
    end
    local rows = {}
    for k, n in pairs(total) do
      rows[#rows + 1] = { k, n }
    end
    table.sort(rows, function(a, b)
      return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1])
    end)
    local lines = { "Usage since logging began (" .. counts_file .. ")", "" }
    for _, r in ipairs(rows) do
      lines[#lines + 1] = string.format("%6d  %s", r[2], r[1])
    end
    vim.cmd "enew"
    vim.bo.buftype, vim.bo.bufhidden, vim.bo.swapfile = "nofile", "wipe", false
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end, { desc = "Show summed mapping and command counts" })
end

return M
