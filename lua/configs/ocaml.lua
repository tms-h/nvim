local M = {}

local tool_cache = {}

local function executable_name(name)
  return name .. (vim.fn.has "win32" == 1 and ".exe" or "")
end

---Find a tool on PATH or in the active opam switch.
---@param name string
---@return string?
function M.find_tool(name)
  if tool_cache[name] then
    return tool_cache[name]
  end

  local path = vim.fn.exepath(name)
  if path ~= "" then
    tool_cache[name] = path
    return path
  end

  local opam = vim.fn.exepath "opam"
  if opam == "" then
    return
  end

  local opam_bin = vim.fn.trim(vim.fn.system { opam, "var", "bin" })
  if vim.v.shell_error ~= 0 or opam_bin == "" then
    return
  end

  local candidate = opam_bin .. "/" .. executable_name(name)
  if vim.fn.executable(candidate) == 1 then
    tool_cache[name] = candidate
    return candidate
  end
end

---Return an indentation level calculated by ocp-indent.
---@param line_number integer
---@return integer
function M.indent(line_number)
  local ocp_indent = M.find_tool "ocp-indent"
  if not ocp_indent then
    return -1
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local input = table.concat(lines, "\n") .. "\n"
  local output = vim.fn.system({
    ocp_indent,
    "--numeric",
    "--indent-empty",
    "--lines",
    line_number .. "-" .. line_number,
  }, input)

  if vim.v.shell_error ~= 0 then
    return -1
  end
  return tonumber(vim.fn.trim(output)) or -1
end

local function project_root(buffer)
  return vim.fs.root(buffer, { "dune-project", "dune-workspace" }) or vim.fs.root(buffer, { ".git" }) or vim.fn.getcwd()
end

local function run_dune(buffer, arguments)
  local dune = M.find_tool "dune"
  if not dune then
    vim.notify("Dune was not found. Install it in the active opam switch.", vim.log.levels.ERROR)
    return
  end

  vim.cmd "belowright split"
  vim.cmd "resize 15"
  local terminal_buffer = vim.api.nvim_get_current_buf()
  local command = { dune }
  vim.list_extend(command, arguments)
  local job = vim.fn.termopen(command, { cwd = project_root(buffer) })
  if job <= 0 then
    vim.api.nvim_buf_delete(terminal_buffer, { force = true })
    vim.notify("Could not start Dune.", vim.log.levels.ERROR)
    return
  end

  vim.keymap.set("n", "q", function()
    if vim.fn.jobwait({ job }, 0)[1] == -1 then
      vim.fn.jobstop(job)
    end
    if vim.api.nvim_buf_is_valid(terminal_buffer) then
      vim.api.nvim_buf_delete(terminal_buffer, { force = true })
    end
  end, { buffer = terminal_buffer, desc = "Close Dune pane", silent = true })
  vim.cmd "startinsert"
end

local function switch_implementation_interface(buffer)
  if vim.fn.exists ":LspOcamllspSwitchImplIntf" == 2 then
    vim.cmd "LspOcamllspSwitchImplIntf"
    return
  end

  local current = vim.api.nvim_buf_get_name(buffer)
  local extension = vim.fn.fnamemodify(current, ":e")
  local alternate
  if extension == "ml" then
    alternate = current .. "i"
  elseif extension == "mli" then
    alternate = current:sub(1, -2)
  end

  if alternate and vim.fn.filereadable(alternate) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(alternate))
  else
    vim.notify("No matching .ml/.mli file found; ocamllsp may still be starting.", vim.log.levels.WARN)
  end
end

---@param buffer integer
function M.setup(buffer)
  vim.opt_local.expandtab = true
  vim.opt_local.shiftwidth = 2
  vim.opt_local.tabstop = 2
  vim.opt_local.softtabstop = -1

  if M.find_tool "ocp-indent" then
    _G.CodexOCamlIndent = M.indent
    vim.opt_local.indentexpr = "v:lua.CodexOCamlIndent(v:lnum)"
  else
    -- The bundled 2017 OCaml indenter can move top-level `let` in the wrong direction.
    vim.opt_local.indentkeys:remove "0=let"
  end

  local map = function(lhs, rhs, description)
    vim.keymap.set("n", lhs, rhs, { buffer = buffer, desc = description, silent = true })
  end

  map("<leader>of", function()
    require("conform").format { bufnr = buffer, async = false, timeout_ms = 5000, lsp_format = "fallback" }
  end, "OCaml: format")
  map("<leader>oi", function()
    switch_implementation_interface(buffer)
  end, "OCaml: switch .ml/.mli")
  map("<leader>ob", function()
    run_dune(buffer, { "build" })
  end, "OCaml: dune build")
  map("<leader>ot", function()
    run_dune(buffer, { "runtest" })
  end, "OCaml: dune runtest")
  map("<leader>ow", function()
    run_dune(buffer, { "build", "--watch" })
  end, "OCaml: dune watch")
  map("<leader>op", function()
    run_dune(buffer, { "promote" })
  end, "OCaml: dune promote")
end

return M
