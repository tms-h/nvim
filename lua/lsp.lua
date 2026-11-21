-- Language servers (built-in vim.lsp; each server's settings are in lsp/),
-- diagnostics, and format on save. Keys are Neovim's own: K hover, grn
-- rename, grr references, gra code action, gri implementation, grt type
-- definition, gO symbols, [d ]d diagnostics, <C-s> signature; plus gd
-- (keys.lua) and Alt+. quick fix (seconder.lua). ocamllsp also shows each
-- top-level let's type above it (code lens), and a failing expect test from
-- `dune test -w` as an error at its [%expect] with only the changed lines.
-- A non-exhaustive match names Alt+. Destruct, which writes the missing cases.
local M = {}

local api = vim.api
local tools = require "tools"

-- Started only when the program is installed, so a machine without one is
-- silent about it.
local SERVERS = {
  ocamllsp = "ocamllsp",
  rust_analyzer = "rust-analyzer",
  pyright = "pyright-langserver",
  ruff = "ruff",
  lua_ls = "lua-language-server",
}

-- ocamllsp's plain hover on a record or variant value shows only the type's
-- name; its extended hover prints the whole definition.
local function ocaml_hover(client, buf)
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.verbosity = 1
  client:request("ocamllsp/hoverExtended", params, function(err, result)
    if err or not (result and result.contents) then
      return vim.lsp.buf.hover()
    end
    local contents = result.contents
    if contents.kind == "plaintext" then
      contents = { kind = "markdown", value = "```ocaml\n" .. contents.value .. "\n```" }
    end
    local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
    vim.lsp.util.open_floating_preview(lines, "markdown", { focus_id = "ocaml_hover", max_width = 90 })
  end, buf)
end

-- ── Formatting ────────────────────────────────────────────────────────────
-- OCaml: ocamlformat with the project's .ocamlformat, else the Jane Street
-- profile; where the project turns ocamlformat off, ocp-indent re-indents.
-- Markdown: prettier. Dune files: dune format-dune-file. Everything else:
-- the language server's own formatter (ruff, rust-analyzer, lua_ls), if it
-- has one. Which languages format on save: FORMAT_ON_SAVE below.

---The whole buffer as one string, as a formatter reads it on stdin.
local function buffer_text(buf)
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
end

---Replace the buffer's text with a formatter's output.
local function apply_output(buf, stdout)
  local new = vim.split(stdout:gsub("\n$", ""), "\n", { plain = true })
  local a, b = buffer_text(buf), table.concat(new, "\n") .. "\n"
  if a == b then
    return
  end
  -- Change only the lines that differ, so marks and the view stay put.
  local hunks = vim.text.diff(a, b, { result_type = "indices", algorithm = "histogram" }) --[[@as integer[][] ]]
  for i = #hunks, 1, -1 do
    local sa, ca, sb, cb = unpack(hunks[i])
    local start = ca == 0 and sa or sa - 1
    api.nvim_buf_set_lines(buf, start, start + ca, false, vim.list_slice(new, sb, sb + cb - 1))
  end
end

---Run a formatter on the buffer's text (stdin) and take its output. When it
---fails (a syntax error, unbalanced parentheses), the buffer stays as typed
---and this returns false.
local function run_formatter(buf, args, cwd)
  local result = vim.system(args, { stdin = buffer_text(buf), cwd = cwd, text = true }):wait(5000)
  if result.code ~= 0 then
    return false
  end
  apply_output(buf, result.stdout)
  return true
end

---Re-indent with ocp-indent: leading spaces only, so a project that turns
---ocamlformat off still gets Jane Street indentation. `lines` ("X-Y",
---1-based) limits it to those lines; nil = the whole buffer.
local function indent_ocaml(buf, dir, lines)
  local result = require("ocaml").ocp_indent(dir, lines and { "--lines", lines } or {}, buffer_text(buf))
  if result and result.code == 0 then
    apply_output(buf, result.stdout)
  end
end

---ocamlformat on the whole buffer, or ocp-indent where it is off. `lines`
---("X-Y", 1-based): lines a tool just wrote; when the file does not parse
---(unfinished code elsewhere), those lines are still re-indented.
function M.format_ocaml(buf, lines)
  local ocamlformat = tools.find "ocamlformat"
  local file = api.nvim_buf_get_name(buf)
  local dir = vim.fs.dirname(file)
  -- The file's folder was moved or deleted on disk: running a formatter there
  -- throws ENOENT, which aborted the save with a stack trace on top of
  -- Neovim's own E212 (2026-11-12). The save cannot land anyway; skip.
  if vim.fn.isdirectory(dir) == 0 then
    return
  end
  local conf = require("ocaml").ocamlformat_conf(dir)
  if not ocamlformat or (conf and conf.disable) then
    indent_ocaml(buf, dir, lines)
    return
  end
  local args = { ocamlformat, "--name=" .. file, "--enable-outside-detected-project", "-" }
  if not conf then
    table.insert(args, 2, "--profile=janestreet")
  end
  -- A syntax error: the file stays as typed (the error is in diagnostics).
  if not run_formatter(buf, args, dir) and lines then
    indent_ocaml(buf, dir, lines)
  end
end

---Prettier for Markdown: lines up table pipes and tidies lists. Prose
---wrapping is left as typed (`--prose-wrap preserve`).
local function format_markdown(buf)
  local prettier = tools.find "prettier"
  if not prettier then
    return
  end
  local file = api.nvim_buf_get_name(buf)
  run_formatter(buf, { prettier, "--stdin-filepath", file ~= "" and file or "untitled.md", "--prose-wrap", "preserve" })
end

---dune format-dune-file for dune, dune-project and dune-workspace files.
local function format_dune(buf)
  local dune = tools.find "dune"
  if not dune then
    return
  end
  run_formatter(buf, { dune, "format-dune-file" })
end

-- ruff formats Python; pyright does not.
local function not_pyright(client)
  return client.name ~= "pyright"
end

-- Formatted on every save: OCaml (ocamlformat), Rust (rust-analyzer, which
-- runs rustfmt), Markdown (prettier, so tables line up) and dune files.
-- Every other language only on :Format, so a save never restyles a Lua,
-- Python or shell file.
local FORMAT_ON_SAVE = { ocaml = true, ocaml_interface = true, rust = true, markdown = true, dune = true }

function M.format(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if require("library").is_library(buf) then
    return
  end
  local ft = vim.bo[buf].filetype
  if ft == "ocaml" or ft == "ocaml_interface" then
    M.format_ocaml(buf)
    return
  end
  if ft == "markdown" then
    format_markdown(buf)
    return
  end
  if ft == "dune" then
    format_dune(buf)
    return
  end
  local clients = vim.lsp.get_clients { bufnr = buf, method = "textDocument/formatting" }
  if #clients > 0 then
    vim.lsp.buf.format { bufnr = buf, timeout_ms = 3000, filter = not_pyright }
  end
end

---Format lines s..e (0-based, inclusive) that a tool just wrote (goose).
---Where a save formats the file (FORMAT_ON_SAVE), the whole file, as the
---next save would. Elsewhere, or with `only_lines` (other unfinished text in
---the file that a whole-file formatter could join onto code), only those
---lines: ocp-indent for OCaml, else the language server's range formatting
---where it has one, so the rest of a Lua or Python file is never restyled.
function M.format_lines(buf, s, e, only_lines)
  if vim.g.format_on_save == false or require("library").is_library(buf) then
    return
  end
  local ft = vim.bo[buf].filetype
  if ft == "ocaml" or ft == "ocaml_interface" then
    local lines = ("%d-%d"):format(s + 1, e + 1)
    if only_lines then
      indent_ocaml(buf, vim.fs.dirname(api.nvim_buf_get_name(buf)), lines)
    else
      M.format_ocaml(buf, lines)
    end
    return
  end
  if FORMAT_ON_SAVE[ft] and not only_lines then
    M.format(buf)
    return
  end
  local clients = vim.lsp.get_clients { bufnr = buf, method = "textDocument/rangeFormatting" }
  if #vim.tbl_filter(not_pyright, clients) == 0 then
    return
  end
  local last = api.nvim_buf_get_lines(buf, e, e + 1, false)[1] or ""
  vim.lsp.buf.format {
    bufnr = buf,
    timeout_ms = 3000,
    range = { start = { s + 1, 0 }, ["end"] = { e + 1, #last } },
    filter = not_pyright,
  }
end

-- A diagnostic's first line, cut with "…" where it would pass the window's
-- right edge after the code on its line.
local function fit_beside_code(diagnostic)
  local message = diagnostic.message:match "^[^\n]*"
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= diagnostic.bufnr then
    return message
  end
  local info = vim.fn.getwininfo(win)[1]
  local line = api.nvim_buf_get_lines(diagnostic.bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1] or ""
  -- Room after the code, the two spaces of spacing and the "● " prefix.
  local room = info.width - info.textoff - vim.fn.strdisplaywidth(line) - 5
  if vim.fn.strdisplaywidth(message) > room then
    message = vim.fn.strcharpart(message, 0, math.max(room - 1, 12)) .. "…"
  end
  return message
end

local QUICK_FIX = require("util").is_macos and "Cmd+." or "Alt+."

---ocamllsp's "this pattern-matching is not exhaustive" (warning 8) gets the
---key that writes the missing cases at the end of its first line. Destruct
---needs the cursor on a case's pattern: on the `match` keyword, where ]d
---lands, it wraps the whole match in a new one. When every case has a
---`when` guard the compiler can't see the guards cover everything, and
---Destruct has no constructors to add (an int match), so that message gets
---the real fix instead: make the last case unguarded.
function M.destruct_hint(diagnostics)
  return vim.tbl_map(function(d)
    if not d.message:find("pattern-matching is not exhaustive", 1, true) then
      return d
    end
    local first, rest = d.message:match "^([^\n]*)(.*)$"
    local hint = rest:find("All clauses in this pattern-matching are guarded", 1, true)
        and " guards are never checked for coverage: drop the `when` on the last case"
      or (" %s on a case's pattern (after a |): Destruct adds the missing cases"):format(QUICK_FIX)
    return vim.tbl_extend("force", d, { message = first .. hint .. rest })
  end, diagnostics)
end

local EXPECT_HEAD = ("expect test output differs (- expected, + got); %s Promote accepts it"):format(QUICK_FIX)

---A file's text, or nil when it can't be read.
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

---The changed blocks between dune's two files (`old` the test as built,
---`news` the places its .corrected may be), each as {line, s, e, lines}
---with -|/+| lines, or nil when a file is gone or they no longer differ.
local function hunks_from_files(old, news)
  local ta, tb = read_file(old), nil
  for _, new in ipairs(news) do
    tb = tb or read_file(new)
  end
  if not (ta and tb) then
    return nil
  end
  local indices = vim.text.diff(ta, tb, { result_type = "indices", algorithm = "histogram" }) --[[@as integer[][] ]]
  if #indices == 0 then
    return nil
  end
  local a, b = vim.split(ta, "\n", { plain = true }), vim.split(tb, "\n", { plain = true })
  local hunks = {}
  for _, h in ipairs(indices) do
    local sa, ca, sb, cb = unpack(h)
    local lines = { EXPECT_HEAD }
    for i = sa, sa + ca - 1 do
      lines[#lines + 1] = "-|" .. a[i]
    end
    for i = sb, sb + cb - 1 do
      lines[#lines + 1] = "+|" .. b[i]
    end
    -- A pure insertion (ca == 0) comes after line sa, shown on that line.
    hunks[#hunks + 1] = { line = math.max(sa - 1, 0), s = 0, e = 0, lines = lines }
  end
  return hunks
end

local MIXED_NOTE = "(!| is one changed line, its old and new words run together: colour told them apart)"

---patdiff's hunks from the message text: its `File "...", line N,
---characters a-b:` lines, then only the changed lines under each. A hunk
---with no changed line found keeps all its lines, so the float never shows
---the header alone.
local function hunks_from_message(rest)
  local hunks, cur = {}, nil
  for line in (rest .. "\n"):gmatch "([^\n]*)\n" do
    local lnum, s, e = line:match '^File "[^"]*", line (%d+), characters (%d+)%-(%d+)'
    if lnum then
      cur = { line = tonumber(lnum) - 1, s = tonumber(s), e = tonumber(e), lines = { EXPECT_HEAD }, all = {} }
      hunks[#hunks + 1] = cur
    elseif cur then
      cur.all[#cur.all + 1] = line
      if line:match "^[-+!]|" then
        cur.lines[#cur.lines + 1] = line
        cur.mixed = cur.mixed or line:match "^!|" ~= nil
      end
    end
  end
  for _, h in ipairs(hunks) do
    if #h.lines == 1 then
      vim.list_extend(h.lines, h.all)
    elseif h.mixed then
      h.lines[#h.lines + 1] = MIXED_NOTE
    end
  end
  return hunks
end

---A failing expect test reaches ocamllsp from `dune test -w` (Dune RPC) as
---one error on line 1: dune's `(cd _build/default && patdiff ... old new)`
---command, the diff's `------ old` / `++++++ new` header, then patdiff's
---hunks with the whole file around them, styles dropped. When dune's
---terminal has colour, patdiff runs without `-ascii` and shows a one-line
---change as a single `!|` line holding the old and new words together,
---told apart only by colour, so the text alone can't say what the test
---printed. Turn it into one error per changed block, on that block's line,
---with the header above and then only the changed lines, taken from a diff
---of the two files under `root`, or from the message's own hunks when
---those files can't be read. Dune 3.23 keeps `new` (the .corrected) not in
---_build/default but as `_build/.promotion-staging/<old>`. Other
---diagnostics pass as they are. `diagnostics` are LSP ones (0-based ranges).
function M.expect_diffs(diagnostics, root)
  local out = {}
  for _, d in ipairs(diagnostics) do
    local dir = d.message:match "^%(cd (%S+) &&" or "_build/default"
    local rest = d.message:gsub("^%(cd [^\n]*%)\n", "", 1)
    -- patdiff's header is ------/++++++, diff -u's ---/+++.
    local old, new = rest:match "^%-%-%-+ ([^\n]*)\n%+%+%++ ([^\n]*)"
    if d.source ~= "dune" or not old then
      out[#out + 1] = d
    else
      local hunks = root
          and hunks_from_files(vim.fs.joinpath(root, dir, old), {
            vim.fs.joinpath(root, dir, new),
            vim.fs.joinpath(root, dir:match "^[^/]+", ".promotion-staging", old),
          })
        or hunks_from_message(rest)
      if #hunks == 0 then
        -- Plain diff (no patdiff): no locations, so line 1 with the diff.
        out[#out + 1] = vim.tbl_extend("force", d, { message = EXPECT_HEAD .. "\n" .. rest })
      end
      for _, h in ipairs(hunks) do
        local range = { start = { line = h.line, character = h.s }, ["end"] = { line = h.line, character = h.e } }
        out[#out + 1] = vim.tbl_extend("force", d, { range = range, message = table.concat(h.lines, "\n") })
      end
    end
  end
  return out
end

-- ocamllsp started in a dune project before its first build reports "No
-- config found" and "Unbound module" (merlin has no build output to read),
-- and keeps reporting them after `dune build` or `dune test -w` until it
-- restarts. So when it attaches to a file whose folder has no merlin config
-- yet, watch for the one dune writes (_build/default/<folder>/.merlin-conf,
-- in plain and watch builds alike), give the build 3 s more to compile, and
-- restart it once. One stat each second, stopped after the restart or after
-- 30 minutes.
local watching = {} -- root -> true while a watch runs

local function restart_after_first_build(root, buf)
  local file = api.nvim_buf_get_name(buf)
  if not root or watching[root] or not vim.uv.fs_stat(root .. "/dune-project") then
    return
  end
  local rel = vim.fs.relpath(root, vim.fs.dirname(file))
  if not rel then
    return
  end
  local conf = root .. "/_build/default/" .. (rel == "." and "" or rel .. "/") .. ".merlin-conf"
  if vim.uv.fs_stat(conf) then
    return
  end
  watching[root] = true
  local timer = vim.uv.new_timer()
  local ticks, seen = 0, nil
  timer:start(1000, 1000, function()
    ticks = ticks + 1
    if not seen and vim.uv.fs_stat(conf) then
      seen = ticks
    end
    if (seen and ticks >= seen + 3) or ticks > 1800 then
      timer:stop()
      timer:close()
      vim.schedule(function()
        watching[root] = nil
        if ticks > 1800 then
          return
        end
        for _, client in ipairs(vim.lsp.get_clients { name = "ocamllsp" }) do
          if client.root_dir == root then
            vim.cmd "silent! lsp restart ocamllsp"
            return
          end
        end
      end)
    end
  end)
end

-- One error, three causes: every redraw raised `Decoration provider "win"
-- (ns=nvim.lsp.codelens): ... pos.lua:145: Index out of bounds` whenever a
-- lens's range ended past the buffer's last line, because the code lens
-- converts the whole range with strict line reads. Two are Neovim 0.12 bugs
-- fixed on master, hit after a file was rewritten shorter on disk and
-- reloaded (:checktime, autoread; 2026-11-12): a reload changes the text but
-- not the buffer's LSP version, so lenses (and other answers) for the old
-- text still counted as current; and the code lens draws the last answer on
-- any row it has not drawn yet. As on master: a reload sets the version to
-- the new changedtick, and lenses draw only for the current version (marks
-- already drawn stay; the answer asked 200 ms after each change draws the
-- rest). The third is a server out of step with the buffer: after binary
-- text with NULs was pasted and undone (2026-11-13), ocamllsp's copy kept
-- 190 lines while the buffer had 17, so its lens for the current version
-- still ran to line 190. Such a lens is skipped until a sane answer comes.
local reload_tracked = {} -- buf -> true once its reloads bump the version

local function bump_version_on_reload(buf)
  if reload_tracked[buf] then
    return
  end
  reload_tracked[buf] = true
  api.nvim_buf_attach(buf, false, {
    on_reload = function(_, b)
      if vim.lsp.util.buf_versions[b] then
        vim.lsp.util.buf_versions[b] = api.nvim_buf_get_changedtick(b)
      end
    end,
    on_detach = function(_, b)
      reload_tracked[b] = nil
    end,
  })
end

local function codelens_current_text_only()
  require "vim.lsp.codelens"
  local Provider = require("vim.lsp._capability").all.codelens
  local on_win = Provider and Provider.on_win
  if not on_win then
    return
  end
  Provider.on_win = function(self, toprow, botrow)
    if self.version ~= vim.lsp.util.buf_versions[self.bufnr] then
      return
    end
    -- Only rows about to be drawn; a range may end at (last + 1, 0).
    local count = api.nvim_buf_line_count(self.bufnr)
    for _, state in pairs(self.client_state) do
      local rows = state.row_lenses
      for row = toprow, botrow do
        local lenses = rows[row]
        if lenses and self.row_version[row] ~= self.version then
          for i = #lenses, 1, -1 do
            local e = lenses[i].range["end"]
            if e.line > count or (e.line == count and e.character > 0) then
              table.remove(lenses, i)
            end
          end
          if #lenses == 0 then
            rows[row] = nil
          end
        end
      end
    end
    return on_win(self, toprow, botrow)
  end
end

function M.setup()
  codelens_current_text_only()
  for name, cmd in pairs(SERVERS) do
    if tools.find(cmd) then
      vim.lsp.enable(name)
    end
  end

  vim.diagnostic.config {
    -- Each line's message at its end (as in the old config), cut to fit the
    -- window (it never runs off screen); the full text, wrapped, with
    -- <leader>d or ]d. Not redrawn while typing (update_in_insert).
    virtual_text = { spacing = 2, prefix = "●", format = fit_beside_code },
    underline = true,
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "●",
        [vim.diagnostic.severity.WARN] = "●",
        [vim.diagnostic.severity.INFO] = "●",
        [vim.diagnostic.severity.HINT] = "·",
      },
    },
    severity_sort = true,
    update_in_insert = false,
    float = { border = "rounded", source = "if_many", max_width = 90 },
    jump = {
      on_jump = function(_, bufnr)
        vim.diagnostic.open_float { bufnr = bufnr, scope = "cursor", focus = false }
      end,
    },
  }

  -- Every ocamllsp whose root holds a dune project hears that project's
  -- `dune build -w` (Dune RPC) and re-checks its own open copies after each
  -- build. One rooted above the project (a file outside any project) or one
  -- already restarted thus put errors on a buffer it doesn't track: errors of
  -- text long since fixed, back on every :w, or left forever when that
  -- server exits, since Neovim clears a server's marks only on its own
  -- buffers (2026-11-22). The server attached to the buffer reports the same
  -- build, so a loaded buffer takes ocamllsp's reports only from its own.
  local publish = vim.lsp.handlers["textDocument/publishDiagnostics"]
  vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, ...)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if result and client and client.name == "ocamllsp" then
      local buf = vim.uri_to_bufnr(result.uri)
      if api.nvim_buf_is_loaded(buf) and not client.attached_buffers[buf] then
        return
      end
      local diagnostics = M.destruct_hint(M.expect_diffs(result.diagnostics, client.root_dir))
      result = vim.tbl_extend("force", result, { diagnostics = diagnostics })
    end
    return publish(err, result, ctx, ...)
  end

  local group = api.nvim_create_augroup("Lsp", { clear = true })
  api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      vim.bo[args.buf].omnifunc = "v:lua.MiniCompletion.completefunc_lsp"
      bump_version_on_reload(args.buf)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "ocamllsp" then
        restart_after_first_build(client.root_dir, args.buf)
        -- Each top-level let's inferred type on a grey line above it
        -- (ocamllsp's code lens, turned on in lsp/ocamllsp.lua).
        vim.lsp.codelens.enable(true, { bufnr = args.buf })
        vim.keymap.set("n", "K", function()
          ocaml_hover(client, args.buf)
        end, { buffer = args.buf, desc = "Hover (full type)" })
      end
    end,
  })
  api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function(args)
      if
        vim.g.format_on_save ~= false
        and vim.bo[args.buf].buftype == ""
        and FORMAT_ON_SAVE[vim.bo[args.buf].filetype]
      then
        M.format(args.buf)
      end
    end,
  })
  api.nvim_create_user_command("Format", function()
    M.format(0)
  end, { desc = "Format this file" })
end

return M
