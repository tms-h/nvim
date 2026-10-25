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

-- ── Format on save ────────────────────────────────────────────────────────
-- OCaml: ocamlformat with the project's .ocamlformat, else the Jane Street
-- profile; where the project turns ocamlformat off, ocp-indent re-indents. Everything else: the language server's own formatter (ruff,
-- rust-analyzer, lua_ls), if it has one.

local function apply_lines(buf, new)
  local old = api.nvim_buf_get_lines(buf, 0, -1, false)
  local a, b = table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n"
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

---The project's .ocamlformat turns ocamlformat off (`disable = true`).
local function ocamlformat_disabled(dir)
  local conf = vim.fs.find(".ocamlformat", { path = dir, upward = true })[1]
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

---Re-indent the whole buffer with ocp-indent: leading spaces only, so a
---project that turns ocamlformat off still gets Jane Street indentation.
local function indent_ocaml(buf, dir)
  local input = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  local result = require("ocaml").ocp_indent(dir, {}, input)
  if not result then
    return false
  end
  if result.code ~= 0 then
    return true
  end
  apply_lines(buf, vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true }))
  return true
end

function M.format_ocaml(buf)
  local ocamlformat = require("tools").find "ocamlformat"
  local file = api.nvim_buf_get_name(buf)
  local dir = vim.fs.dirname(file)
  if not ocamlformat or ocamlformat_disabled(dir) then
    return indent_ocaml(buf, dir)
  end
  local args = { ocamlformat, "--name=" .. file, "--enable-outside-detected-project", "-" }
  if not vim.fs.find(".ocamlformat", { path = dir, upward = true })[1] then
    table.insert(args, 2, "--profile=janestreet")
  end
  local input = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  local result = vim.system(args, { stdin = input, cwd = dir, text = true }):wait(5000)
  if result.code ~= 0 then
    -- A syntax error: leave the file as typed; the error is in diagnostics.
    return true
  end
  apply_lines(buf, vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true }))
  return true
end

-- Formatted on every save: OCaml (ocamlformat) and Rust (rust-analyzer,
-- which runs rustfmt). Every other language only on :Format, so a save
-- never restyles a Lua, Python or shell file.
M.FORMAT_ON_SAVE = { ocaml = true, ocaml_interface = true, rust = true }

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
  local clients = vim.lsp.get_clients { bufnr = buf, method = "textDocument/formatting" }
  if #clients > 0 then
    vim.lsp.buf.format {
      bufnr = buf,
      timeout_ms = 3000,
      -- ruff formats Python; pyright does not.
      filter = function(client)
        return client.name ~= "pyright"
      end,
    }
  end
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
        and M.FORMAT_ON_SAVE[vim.bo[args.buf].filetype]
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
