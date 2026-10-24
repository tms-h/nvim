-- Library files are read-only reference: installed packages (opam, Rust,
-- Python, node), plugin and tool folders, Neovim's runtime and system files.
-- Opening one to read a signature must not light it up with errors that only
-- mean "this file is not part of your build" (ocamllsp: "Unbound module
-- Import" twenty times in base/list.mli), nor lint it or reformat it on save.
-- LSP still attaches, so hover and go-to-definition keep working there.
local M = {}

local is_windows = vim.fn.has "win32" == 1

local function normalize(path)
  path = path:gsub("\\", "/")
  return is_windows and path:lower() or path
end

local function home(sub)
  return normalize(vim.fn.expand("~/" .. sub))
end

-- Folders whose whole tree is installed code, not his projects.
local roots = vim.tbl_map(normalize, {
  home ".opam",
  home ".rustup",
  home ".cargo/registry",
  home ".cargo/git",
  home ".pyenv/versions",
  home ".nvm/versions",
  vim.fn.stdpath "data", -- Lazy plugins and Mason tools
  vim.env.VIMRUNTIME or "",
  "/usr",
  "/opt/homebrew",
  "/Library",
  "/nix/store",
})

-- Folder names that mark installed or generated code anywhere, including
-- inside a project (its local opam switch, node packages, dune build copies).
local markers = { "/_opam/", "/_build/", "/node_modules/", "/site-packages/", "/dist-packages/", "/.venv/" }

---@param path string
---@return boolean
function M.is_library_path(path)
  if path == "" or path:find "^%a+://" then
    return false
  end
  path = normalize(vim.fn.fnamemodify(path, ":p"))
  for _, root in ipairs(roots) do
    if root ~= "" and vim.startswith(path, root .. "/") then
      return true
    end
  end
  for _, marker in ipairs(markers) do
    if path:find(marker, 1, true) then
      return true
    end
  end
  return false
end

---@param buf? integer
---@return boolean
function M.is_library(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ""
    and M.is_library_path(vim.api.nvim_buf_get_name(buf))
end

local function mark(buf)
  if M.is_library(buf) then
    vim.bo[buf].readonly = true
  end
end

-- Language servers still answer hover and go-to-definition in library files;
-- only their error reports are dropped, before they are stored, so no sign,
-- underline, tab badge or status-line count ever sees them.
local function drop_library_diagnostics(method, field, uri_of)
  local handler = vim.lsp.handlers[method]
  vim.lsp.handlers[method] = function(err, result, ctx, ...)
    local uri = result and uri_of(result, ctx)
    if uri and M.is_library_path(vim.uri_to_fname(uri)) then
      result = vim.tbl_extend("force", result, { [field] = {} })
    end
    return handler(err, result, ctx, ...)
  end
end

function M.setup()
  drop_library_diagnostics("textDocument/publishDiagnostics", "diagnostics", function(result)
    return result.uri
  end)
  drop_library_diagnostics("textDocument/diagnostic", "items", function(_, ctx)
    return ctx.params and ctx.params.textDocument and ctx.params.textDocument.uri
  end)
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("LibraryReadOnly", { clear = true }),
    callback = function(args)
      mark(args.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      mark(buf)
    end
  end
end

return M
