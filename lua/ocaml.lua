-- OCaml: ocp-indent while typing, ocamlformat on save (lsp.lua), ocamllsp,
-- and dune in a terminal pane. Keys (OCaml files only):
--   <leader>oi  switch .ml / .mli        <leader>of  format now
--   <leader>ob  dune build               <leader>ot  dune test, this folder
--   <leader>ow  dune test -w, this folder <leader>op  dune promote, this file only
--   gt{motion} / gt on a selection / gtt   wrap in (fun () -> ...)
local M = {}

local api = vim.api
local tools = require "tools"

-- Names for the Space keys Neovim's own OCaml plugin maps (runtime
-- ftplugin/ocaml.vim), by what they run.
local STOCK_KEYS = {
  ["<Plug>LUncomOn"] = "comment out the line (* *)",
  ["<Plug>LUncomOff"] = "uncomment the line",
  ["<Plug>BUncomOn"] = "comment out the selection (* *)",
  ["<Plug>BUncomOff"] = "uncomment the selection",
  ["<Plug>OCamlSwitchEdit"] = "switch .ml/.mli (stock)",
  ["<Plug>OCamlSwitchNewWin"] = "switch .ml/.mli in a split",
  ["<Plug>OCamlPrintType"] = "type from old .annot files (K is better)",
}

---ocp-indent with `args` on `input`, run from the folder `dir`: the
---project's .ocp-indent if it has one, else Jane Street style (the same rule
---as ocamlformat's --profile=janestreet), so no machine-wide file is needed.
function M.ocp_indent(dir, args, input)
  local ocp = tools.find "ocp-indent"
  if not ocp then
    return nil
  end
  dir = dir ~= "" and vim.fn.isdirectory(dir) == 1 and dir or nil
  local cmd = { ocp }
  if not vim.fs.find(".ocp-indent", { path = dir or vim.fn.getcwd(), upward = true })[1] then
    cmd[2] = "--config=JaneStreet"
  end
  return vim.system(vim.list_extend(cmd, args), { stdin = input, cwd = dir, text = true }):wait(2000)
end

---Indent of one line as ocp-indent computes it from the whole buffer.
function M.indent(lnum)
  local input = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
  local dir = vim.fs.dirname(api.nvim_buf_get_name(0))
  local result = M.ocp_indent(dir, { "--numeric", "--indent-empty", "--lines", lnum .. "-" .. lnum }, input)
  if not result or result.code ~= 0 then
    return -1
  end
  return tonumber(vim.trim(result.stdout or "")) or -1
end

local function use_ocp_indent(buf)
  if tools.find "ocp-indent" then
    vim.bo[buf].indentexpr = "v:lua.require'ocaml'.indent(v:lnum)"
  else
    -- The bundled indenter moves top-level `let` the wrong way.
    vim.opt_local.indentkeys:remove "0=let"
  end
end

---The .ocamlformat that applies to files in `dir`, read: nil without one,
---else `disable` (the project turns ocamlformat off) and its `margin` and
---`profile`, if set. Read here for the ruler and by lsp.lua for formatting.
---@return { disable: boolean, margin: string?, profile: string? }?
function M.ocamlformat_conf(dir)
  local path = vim.fs.find(".ocamlformat", { path = dir, upward = true })[1]
  if not path then
    return nil
  end
  local conf = { disable = false }
  for line in io.lines(path) do
    conf.disable = conf.disable or line:match "^%s*disable%s*=%s*true%s*$" ~= nil
    conf.margin = line:match "^%s*margin%s*=%s*(%d+)" or conf.margin
    conf.profile = line:match "^%s*profile%s*=%s*(%w+)" or conf.profile
  end
  return conf
end

---The column ocamlformat wraps at for this file: the project's `margin`, else
---its profile's width (Jane Street 90, every other profile 80). 90 without an
---.ocamlformat, where a save uses the Jane Street profile (lsp.lua). nil where
---the project turns ocamlformat off: nothing wraps there.
local function wrap_column(buf)
  local conf = M.ocamlformat_conf(vim.fs.dirname(api.nvim_buf_get_name(buf)))
  if not conf then
    return "90"
  end
  if conf.disable then
    return nil
  end
  return conf.margin or (conf.profile == "janestreet" and "90" or "80")
end

local function root(buf)
  return vim.fs.root(buf, { "dune-project", "dune-workspace" }) or vim.fs.root(buf, ".git") or vim.fn.getcwd()
end

local dune_buf -- the terminal of the last dune run

---Run dune in a terminal pane below; `q` there closes it.
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

---`path` relative to the dune root, or nil with a warning when it lies outside.
local function in_project(buf, path)
  local rel = vim.fs.relpath(root(buf), path)
  if not rel then
    vim.notify("This file is outside the dune project", vim.log.levels.WARN)
  end
  return rel
end

---`dune promote` for this buffer's file only: a bare promote accepts every
---pending correction, so accepting your own test's output also rewrote a
---spec test file next to it (2026-11-12).
function M.promote(buf)
  local file = in_project(buf, api.nvim_buf_get_name(buf))
  if file then
    M.dune(buf, { "promote", file })
  end
end

---`dune test` on this buffer's folder only (with `-w`, rerun on every save).
---From the root, runtest also ran sibling folders, such as the drills'
---hidden edge-case tests, and showed their diffs (2026-11-12).
function M.test(buf, watch)
  local dir = in_project(buf, vim.fs.dirname(api.nvim_buf_get_name(buf)))
  if dir then
    M.dune(buf, watch and { "test", dir, "-w" } or { "test", dir })
  end
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

---Operator (g@): wrap the text it covered in `(fun () -> ...)`, bcc32's
---`gt`. Whole lines are wrapped from their first non-blank to their end.
function M.wrap_thunk(kind)
  local first = api.nvim_buf_get_mark(0, "[")
  local last = api.nvim_buf_get_mark(0, "]")
  local srow, scol, erow, ecol = first[1] - 1, first[2], last[1] - 1, last[2]
  local end_line = api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or ""
  if kind == "line" then
    scol = #(api.nvim_buf_get_lines(0, srow, srow + 1, false)[1] or ""):match "^%s*"
    ecol = #end_line
  else
    -- `]` marks the start of the last character; take all of it.
    ecol = math.min(#end_line, ecol + #vim.fn.strcharpart(end_line:sub(ecol + 1), 0, 1))
  end
  api.nvim_buf_set_text(0, erow, ecol, erow, ecol, { ")" })
  api.nvim_buf_set_text(0, srow, scol, srow, scol, { "(fun () -> " })
end

function M.setup(buf)
  buf = buf == 0 and api.nvim_get_current_buf() or buf
  vim.bo[buf].expandtab = true
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].softtabstop = -1
  vim.opt_local.colorcolumn = wrap_column(buf) or ""
  use_ocp_indent(buf)
  -- Neovim's own indent/ocaml.vim runs after this and sets GetOCamlIndent();
  -- take indenting back after it.
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
    M.test(buf, false)
  end, "dune test this folder")
  map("<leader>ow", function()
    M.test(buf, true)
  end, "dune test this folder on every save")
  map("<leader>op", function()
    M.promote(buf)
  end, "dune promote this file")
  -- gt: stock "next tab page", which here only reaches an Alt+F zoom.
  local function thunk(motion)
    return function()
      vim.o.operatorfunc = "v:lua.require'ocaml'.wrap_thunk"
      return "g@" .. motion
    end
  end
  local wrap = { buffer = buf, expr = true, desc = "OCaml: wrap in (fun () -> ...)" }
  vim.keymap.set({ "n", "x" }, "gt", thunk "", wrap)
  vim.keymap.set(
    "n",
    "gtt",
    thunk "_",
    vim.tbl_extend("force", wrap, { desc = "OCaml: wrap the line in (fun () -> ...)" })
  )
  -- `*` typed between the pair mini.pairs made for `(` opens a comment:
  -- `(|)` becomes `(* | *)`, as VS Code's OCaml Platform does. Without this
  -- the comment read `(*|)`, closed by a stray `)` (2026-11-13).
  vim.keymap.set("i", "*", function()
    local line, col = api.nvim_get_current_line(), api.nvim_win_get_cursor(0)[2]
    if line:sub(col, col + 1) == "()" then
      return "*  *<C-g>U<Left><C-g>U<Left>"
    end
    return "*"
  end, { buffer = buf, expr = true, desc = "OCaml: (* opens a comment, closed with *)" })
  -- Neovim's own OCaml plugin adds Space keys with no name, so the key hints
  -- (mini.clue) listed them blank. Same keys, now named.
  for _, mode in ipairs { "n", "x" } do
    for _, m in ipairs(api.nvim_buf_get_keymap(buf, mode)) do
      local desc = STOCK_KEYS[m.rhs]
      if desc and not m.desc then
        vim.keymap.set(mode, m.lhs, m.rhs, { buffer = buf, remap = true, desc = "OCaml: " .. desc })
      end
    end
  end
end

return M
