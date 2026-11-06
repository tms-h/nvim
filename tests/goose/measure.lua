-- Real-claude timing: 5 sends on a 300-line OCaml file, one-shot path vs
-- session path. Costs real calls (~10). Run:
--   GOOSE_TEST_DIR=$(mktemp -d) nice -n 19 nvim --headless -u NONE -i NONE \
--     --cmd "set rtp^=$HOME/.config/nvim" -c "luafile tests/goose/measure.lua"
local g = require "goose"
g.setup()
g.flash_ms = 10
local dir = vim.env.GOOSE_TEST_DIR

-- The one-shot path with --output-format json, only to read its token usage.
local usage
local real_cmd = { "claude", "-p", "--model", g.model, "--setting-sources", "", "--strict-mcp-config", "--tools", "", "--no-session-persistence", "--disable-slash-commands", "--output-format", "json", "--system-prompt" }
g.ask = function(system, prompt, cb)
  local c = vim.list_extend(vim.deepcopy(real_cmd), { system })
  vim.system(c, { stdin = prompt, text = true }, function(r)
    vim.schedule(function()
      local ok, j = pcall(vim.json.decode, r.stdout)
      if not ok then
        return cb(nil, r.stderr)
      end
      local u = j.usage or {}
      usage = { input = u.input_tokens or 0, cache_write = u.cache_creation_input_tokens or 0, cache_read = u.cache_read_input_tokens or 0, output = u.output_tokens or 0, prompt_chars = #prompt }
      cb(j.result)
    end)
  end)
end

local lines = {
  "(* Order book helpers. *)",
  "type side = Buy | Sell",
  "type order = { id : int; symbol : string; side : side; price : float; qty : int }",
  "",
}
local i = 0
while #lines < 300 do
  i = i + 1
  vim.list_extend(lines, {
    ("let notional_%d (o : order) = o.price *. float_of_int o.qty *. %d." ):format(i, i),
    ("let is_big_%d (o : order) = o.qty > %d && o.price > %d.0"):format(i, i * 10, i),
    ("let tag_%d (o : order) = Printf.sprintf \"%%s-%%d-%d\" o.symbol o.id"):format(i, i),
    "",
  })
end
local PSEUDO = {
  { 40, "let total_qty orders = sum of qty over orders where side is Buy" },
  { 90, "let avg_price orders = average price, None when the list is empty" },
  { 150, "let best_bid orders = highest price among Buy orders, None if none" },
  { 210, "let by_symbol orders = count orders per symbol into a Hashtbl" },
  { 270, "let drop_small orders = keep orders whose qty is at least 100" },
}

local function median(t)
  local c = vim.deepcopy(t)
  table.sort(c)
  return c[math.ceil(#c / 2)]
end

local function path(name, session)
  g.use_session = session
  local f = ("%s/%s.ml"):format(dir, name)
  vim.fn.writefile(lines, f)
  vim.cmd.edit(f)
  local buf = vim.api.nvim_get_current_buf()
  local ms, first, toks, chars = {}, {}, {}, {}
  for n, p in ipairs(PSEUDO) do
    vim.api.nvim_buf_set_lines(buf, p[1], p[1], false, { p[2] })
    usage, g.last_usage = nil, nil
    local t0 = vim.uv.hrtime()
    local t_first
    local pns = vim.api.nvim_get_namespaces().goose_preview
    g.convert(buf, p[1], p[1])
    vim.wait(60000, function()
      if not t_first and pns and #vim.api.nvim_buf_get_extmarks(buf, pns, 0, -1, {}) > 0 then
        t_first = vim.uv.hrtime()
      end
      return g.pending_count(buf) == 0
    end, 5)
    local u = session and g.last_usage or usage
    ms[n] = math.floor((vim.uv.hrtime() - t0) / 1e6)
    first[n] = t_first and math.floor((t_first - t0) / 1e6) or ms[n]
    toks[n] = u and (u.input + u.cache_write + u.cache_read) or -1
    chars[n] = u and u.prompt_chars or -1
    io.stdout:write(("%s send %d: %d ms (first ghost line %d ms), tokens in %d (new %d, cache write %d, cache read %d), prompt %d chars, out: %s\n"):format(
      name, n, ms[n], first[n], toks[n], u and u.input or -1, u and u.cache_write or -1, u and u.cache_read or -1, chars[n],
      (vim.api.nvim_buf_get_lines(buf, p[1], p[1] + 1, false)[1] or "")))
  end
  io.stdout:write(("%s: median %d ms, median first-visible %d ms, median tokens in %d, median prompt %d chars\n"):format(name, median(ms), median(first), median(toks), median(chars)))
  vim.cmd "silent! write"
  vim.cmd "silent! bwipeout!"
end

path("oneshot", false)
path("session", true)
vim.cmd "qa!"
