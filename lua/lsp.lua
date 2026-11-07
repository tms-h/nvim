-- Language servers (built-in vim.lsp; each server's settings are in lsp/),
-- diagnostics, and format on save. Keys are Neovim's own: K hover, grn
-- rename, grr references, gra code action, gri implementation, grt type
-- definition, gO symbols, [d ]d diagnostics, <C-s> signature; plus gd
-- (keys.lua).
local M = {}

local api = vim.api

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
-- Markdown: prettier. Everything else: the language server's own formatter
-- (ruff, rust-analyzer, lua_ls), if it has one. Which languages format on
-- save: FORMAT_ON_SAVE below.

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

---The project's .ocamlformat (path `conf`, may be nil) turns ocamlformat off
---(`disable = true`).
local function ocamlformat_disabled(conf)
  if not conf then
    return false
  end
  for line in io.lines(conf) do
    if line:match "^%s*disable%s*=%s*true%s*$" then
      return true
    end
  end
  return false
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
  local ocamlformat = require("tools").find "ocamlformat"
  local file = api.nvim_buf_get_name(buf)
  local dir = vim.fs.dirname(file)
  local conf = vim.fs.find(".ocamlformat", { path = dir, upward = true })[1]
  if not ocamlformat or ocamlformat_disabled(conf) then
    indent_ocaml(buf, dir, lines)
    return
  end
  local args = { ocamlformat, "--name=" .. file, "--enable-outside-detected-project", "-" }
  if not conf then
    table.insert(args, 2, "--profile=janestreet")
  end
  local result = vim.system(args, { stdin = buffer_text(buf), cwd = dir, text = true }):wait(5000)
  -- A syntax error: leave the file as typed; the error is in diagnostics.
  if result.code == 0 then
    apply_output(buf, result.stdout)
  elseif lines then
    indent_ocaml(buf, dir, lines)
  end
end

---Prettier for Markdown: lines up table pipes and tidies lists. Prose
---wrapping is left as typed (`--prose-wrap preserve`).
local function format_markdown(buf)
  local prettier = require("tools").find "prettier"
  if not prettier then
    return
  end
  local file = api.nvim_buf_get_name(buf)
  local args = { prettier, "--stdin-filepath", file ~= "" and file or "untitled.md", "--prose-wrap", "preserve" }
  local result = vim.system(args, { stdin = buffer_text(buf), text = true }):wait(5000)
  -- Broken Markdown: leave the file as typed.
  if result.code == 0 then
    apply_output(buf, result.stdout)
  end
end

-- ruff formats Python; pyright does not.
local function not_pyright(client)
  return client.name ~= "pyright"
end

-- Formatted on every save: OCaml (ocamlformat), Rust (rust-analyzer, which
-- runs rustfmt) and Markdown (prettier, so tables line up). Every other
-- language only on :Format, so a save never restyles a Lua, Python or shell
-- file.
local FORMAT_ON_SAVE = { ocaml = true, ocaml_interface = true, rust = true, markdown = true }

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

-- ocamllsp started in a dune project before its first build reports "No
-- config found" and "Unbound module" (merlin has no build output to read),
-- and keeps reporting them after `dune build` or `dune test -w` until it
-- restarts. So when it attaches to a file whose folder has no merlin config
-- yet, watch for the one dune writes (_build/default/<folder>/.merlin-conf,
-- in plain and watch builds alike), give the build 3 s more to compile, and
-- restart it once. One stat each second, stopped after the restart or after
-- 30 minutes.
local watching = {} -- root -> true while a watch runs

function M.restart_after_first_build(root, buf)
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

function M.setup()
  for name, cmd in pairs(SERVERS) do
    if require("tools").find(cmd) then
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

  local group = api.nvim_create_augroup("Lsp", { clear = true })
  api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      vim.bo[args.buf].omnifunc = "v:lua.MiniCompletion.completefunc_lsp"
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "ocamllsp" then
        M.restart_after_first_build(client.root_dir, args.buf)
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
