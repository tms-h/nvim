-- OCaml: ocp-indent while typing, ocamlformat on save (lsp.lua), ocamllsp,
-- and dune in a terminal pane. Keys (OCaml files only):
--   <leader>oi  switch .ml / .mli        <leader>of  format now
--   <leader>ob  dune build               <leader>ot  dune runtest
--   <leader>ow  dune build --watch       <leader>op  dune promote
local M = {}

local api = vim.api
local tools = require "tools"

---Indent of one line as ocp-indent computes it from the whole buffer.
function M.indent(lnum)
  local ocp = tools.find "ocp-indent"
  if not ocp then
    return -1
  end
  local input = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
  -- Run from the file's folder, so ocp-indent finds the project's .ocp-indent.
  local dir = vim.fs.dirname(api.nvim_buf_get_name(0))
  local result = vim
    .system(
      { ocp, "--numeric", "--indent-empty", "--lines", lnum .. "-" .. lnum },
      { stdin = input, cwd = dir ~= "" and vim.fn.isdirectory(dir) == 1 and dir or nil }
    )
    :wait(2000)
  return result.code == 0 and (tonumber(vim.trim(result.stdout or "")) or -1) or -1
end

local function use_ocp_indent(buf)
  if tools.find "ocp-indent" then
    vim.bo[buf].indentexpr = "v:lua.require'ocaml'.indent(v:lnum)"
  else
    -- The bundled indenter moves top-level `let` the wrong way.
    vim.opt_local.indentkeys:remove "0=let"
  end
end

local function root(buf)
  return vim.fs.root(buf, { "dune-project", "dune-workspace" }) or vim.fs.root(buf, ".git") or vim.fn.getcwd()
end

---Run dune in a terminal pane below; `q` there closes it.
local dune_buf -- the terminal of the last dune run

function M.dune(buf, args)
  local dune = tools.find "dune"
  if not dune then
    vim.notify("dune is not installed in the active opam switch", vim.log.levels.WARN)
    return
  end
  local panes = require "panes"
  panes.leave_zoom()
  -- The dune pane: the last one if it is still shown, else a new one below.
  -- Always a new empty buffer: a terminal job takes over the buffer it
  -- starts in, and the old run is stopped.
  local old = dune_buf
  local win
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if old and api.nvim_win_get_buf(w) == old then
      win = w
    end
  end
  if win then
    api.nvim_set_current_win(win)
    vim.cmd.enew()
  else
    vim.cmd "rightbelow 15new"
  end
  if old and api.nvim_buf_is_valid(old) then
    pcall(api.nvim_buf_delete, old, { force = true })
  end
  vim.fn.jobstart(vim.list_extend({ dune }, args), { term = true, cwd = root(buf) })
  dune_buf = api.nvim_get_current_buf()
  vim.bo[dune_buf].buflisted = false
  -- dune reads no keys, so q can close the pane while it runs too.
  vim.keymap.set({ "n", "t" }, "q", "<Cmd>bwipeout!<CR>", { buffer = dune_buf, desc = "Close dune" })
  vim.cmd "startinsert"
end

---Jump between foo.ml and foo.mli.
function M.switch(buf)
  local name = api.nvim_buf_get_name(buf)
  local other = name:match "%.mli$" and name:sub(1, -2) or name:match "%.ml$" and name .. "i"
  if other and vim.uv.fs_stat(other) then
    vim.cmd.edit(vim.fn.fnameescape(other))
  else
    vim.notify("No " .. (other and vim.fn.fnamemodify(other, ":t") or ".ml/.mli pair"))
  end
end

function M.setup(buf)
  buf = buf == 0 and api.nvim_get_current_buf() or buf
  vim.bo[buf].expandtab = true
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].softtabstop = -1
  use_ocp_indent(buf)
  -- Tree-sitter's FileType setup runs after this; take indenting back after.
  vim.schedule(function()
    if api.nvim_buf_is_valid(buf) then
      use_ocp_indent(buf)
    end
  end)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = "OCaml: " .. desc })
  end
  map("<leader>oi", function()
    M.switch(buf)
  end, "switch .ml/.mli")
  map("<leader>of", function()
    require("lsp").format_ocaml(buf)
  end, "format")
  map("<leader>ob", function()
    M.dune(buf, { "build" })
  end, "dune build")
  map("<leader>ot", function()
    M.dune(buf, { "runtest" })
  end, "dune runtest")
  map("<leader>ow", function()
    M.dune(buf, { "build", "--watch" })
  end, "dune watch")
  map("<leader>op", function()
    M.dune(buf, { "promote" })
  end, "dune promote")
end

return M
