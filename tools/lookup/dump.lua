-- Dumps what this config defines, as Neovim itself sees it, for tools/lookup/lookup.py.
-- Loaded with --cmd (before init.lua) so it can note where each key and command is
-- set; the dump itself runs on VimEnter and writes JSON to $LOOKUP_OUT.
local cfg = vim.uv.fs_realpath(vim.fn.stdpath "config") or vim.fn.stdpath "config"
local sites = {} -- "<mode>\0<lhsraw>\0<buffer?>" or "cmd\0<name>" -> "file:line[|file:caller line]"

-- The first stack frame outside Neovim's runtime, this file and the usage counter's wrapper, plus the
-- next frame when it is in the same file (lookup.py uses it when the first is a helper that sets many keys).
local me = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2))
local function site(is_key)
  local first, file
  for level = 3, 40 do
    local info = debug.getinfo(level, "Sl")
    if not info then
      break
    end
    local src = info.source:sub(1, 1) == "@" and (vim.uv.fs_realpath(info.source:sub(2)) or info.source:sub(2))
    if
      src
      and src ~= me
      and not src:find("/runtime/lua/vim/", 1, true)
      and not (is_key and src:find("/lua/usage.lua", 1, true))
    then
      if src:sub(1, #cfg + 1) == cfg .. "/" then
        src = src:sub(#cfg + 2)
      else
        src = src:match "/site/pack/[^/]+/[^/]+/([^/]+/.*)$" or src -- a plugin: "<plugin>/lua/..."
      end
      if not first then
        first, file = src .. ":" .. info.currentline, src
      else
        return src == file and (first .. "|" .. src .. ":" .. info.currentline) or first
      end
    end
  end
  return first
end

-- One spelling per key on both sides: keytrans of Neovim's raw bytes (`<leader>x`, `<C-k>`, `<Space>x` all agree).
local function normal(lhs, mode, buffer)
  local function get()
    return vim.fn.maparg(lhs, mode, false, true)
  end
  local ok, d = pcall(function()
    return type(buffer) == "number" and buffer > 0 and vim.api.nvim_buf_call(buffer, get) or get()
  end)
  return ok and d.lhsraw and vim.fn.keytrans(d.lhsraw) or lhs
end

local function noted(where, modes, lhs, buffer)
  if not where then
    return
  end
  for _, m in ipairs(type(modes) == "table" and modes or { modes }) do
    for _, mm in
      ipairs(m == "" and { "n", "x", "s", "o" } or m == "v" and { "x", "s" } or m == "!" and { "i", "c" } or { m })
    do
      sites[mm .. "\0" .. normal(lhs, mm, buffer) .. "\0" .. (buffer and "b" or "")] = where
    end
  end
end

local set = vim.keymap.set
vim.keymap.set = function(modes, lhs, rhs, opts)
  local where = site(true)
  local r = set(modes, lhs, rhs, opts)
  noted(where, modes, lhs, opts and opts.buffer)
  return r
end
local api_set, api_buf_set = vim.api.nvim_set_keymap, vim.api.nvim_buf_set_keymap
vim.api.nvim_set_keymap = function(mode, lhs, rhs, opts)
  local where = site(true)
  api_set(mode, lhs, rhs, opts)
  noted(where, mode, lhs, false)
end
vim.api.nvim_buf_set_keymap = function(buf, mode, lhs, rhs, opts)
  local where = site(true)
  api_buf_set(buf, mode, lhs, rhs, opts)
  noted(where, mode, lhs, buf == 0 and true or buf)
end
for _, fn in ipairs { "nvim_create_user_command", "nvim_buf_create_user_command" } do
  local orig = vim.api[fn]
  vim.api[fn] = function(...)
    local args = { ... }
    local name = fn == "nvim_create_user_command" and args[1] or args[2]
    sites["cmd\0" .. name] = sites["cmd\0" .. name] or site()
    return orig(...)
  end
end

local MODES = { "n", "i", "x", "s", "o", "t", "c" }
local FILETYPES = { "ocaml", "ocaml_interface", "markdown", "org", "python", "rust", "lua" }

local function entry(k, mode, ft)
  return {
    mode = mode,
    lhs = k.lhs,
    desc = k.desc or "",
    rhs = k.rhs or (k.callback and "<Lua function>") or "",
    ft = ft,
    where = sites[mode .. "\0" .. vim.fn.keytrans(k.lhsraw) .. "\0" .. (ft and "b" or "")],
  }
end

local function dump()
  local out = { maps = {}, cmds = {}, version = tostring(vim.version()), mapleader = vim.g.mapleader }
  for _, m in ipairs(MODES) do
    for _, k in ipairs(vim.api.nvim_get_keymap(m)) do
      out.maps[#out.maps + 1] = entry(k, m, nil)
    end
  end
  local function buffer_maps(buf, ft)
    for _, m in ipairs(MODES) do
      for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, m)) do
        out.maps[#out.maps + 1] = entry(k, m, ft)
      end
    end
  end
  for _, ft in ipairs(FILETYPES) do
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    pcall(function()
      vim.bo[buf].filetype = ft
    end)
    buffer_maps(buf, ft)
  end
  -- The file tree sets its keys when it opens.
  if pcall(vim.cmd, "NvimTreeOpen") then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "NvimTree" then
        buffer_maps(buf, "tree")
      end
    end
  end
  for name, c in pairs(vim.api.nvim_get_commands {}) do
    out.cmds[#out.cmds + 1] =
      { name = name, desc = c.definition or "", nargs = c.nargs, where = sites["cmd\0" .. name] }
  end
  local f = assert(io.open(vim.env.LOOKUP_OUT, "w"))
  f:write(vim.json.encode(out))
  f:close()
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, err = pcall(dump)
      if not ok then
        io.stderr:write("lookup dump failed: " .. tostring(err) .. "\n")
      end
      vim.cmd "qa!"
    end)
  end,
})
