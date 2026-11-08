-- Goose memory server (tools/goose/memory.py): remember/forget edit only the
-- file named on its command line. Run: tests/goose/run.sh
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local server = vim.fs.joinpath(here, "../../tools/goose/memory.py")
local dir = vim.env.GOOSE_TEST_DIR
local file = dir .. "/state/memory.md"
local other = dir .. "/other.md"

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

---Run the server on `calls` ({ name, arguments } each); the reply texts.
local function run(calls, max)
  local msgs = { vim.json.encode { jsonrpc = "2.0", id = 0, method = "initialize", params = { protocolVersion = "2025-06-18" } } }
  for i, c in ipairs(calls) do
    msgs[#msgs + 1] = vim.json.encode {
      jsonrpc = "2.0",
      id = i,
      method = c[1] == "list" and "tools/list" or "tools/call",
      params = { name = c[1], arguments = c[2] },
    }
  end
  local r = vim.system({ "python3", "-I", server, file, max and tostring(max) }, { stdin = table.concat(msgs, "\n") .. "\n", text = true }):wait()
  local out = {}
  for _, l in ipairs(vim.split(vim.trim(r.stdout), "\n")) do
    local m = vim.json.decode(l)
    if m.id > 0 then
      out[m.id] = m.result.tools or m.result.content[1].text
    end
  end
  return out, r
end
local function lines()
  return vim.uv.fs_stat(file) and vim.fn.readfile(file) or {}
end

local out = run {
  { "list" },
  { "remember", { note = "Thomas prefers Core's List\nover Stdlib" } },
  { "remember", { note = "Prefer   `let%bind`", path = other, file = other } },
  { "remember", { note = "thomas prefers core's list over stdlib" } },
}
check(
  "the server offers remember and forget only",
  vim.deep_equal(vim.tbl_map(function(t)
    return t.name
  end, out[1]), { "remember", "forget" }),
  vim.inspect(out[1])
)
check("remember writes one line per note to its file", vim.deep_equal(lines(), { "- Thomas prefers Core's List over Stdlib", "- Prefer `let%bind`" }), vim.inspect(lines()))
check("a path in the call is ignored: no other file is written", not vim.uv.fs_stat(other))
check("a note already saved is not saved twice", out[4] == "Already in memory.", out[4])

out = run({ { "remember", { note = "a note that does not fit in a sixty byte memory file at all" } } }, 60)
check("a full memory saves nothing", out[1]:find("full", 1, true) and #lines() == 2, vim.inspect { out[1], lines() })

out = run { { "forget", { text = "core's LIST" } }, { "forget", { text = "nothing like this" } } }
check("forget drops the matching note", vim.deep_equal(lines(), { "- Prefer `let%bind`" }), vim.inspect(lines()))
check("forget with no match changes nothing", out[2] == "No note contains that text." and #lines() == 1, out[2])

io.stdout:write(("goose memory: %d pass, %d fail\n"):format(pass, fail))
vim.cmd(fail == 0 and "qa!" or "cquit")
