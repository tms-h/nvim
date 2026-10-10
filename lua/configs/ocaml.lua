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

  -- GUI launches may not inherit opam's shell environment. Check the switch
  -- associated with the current buffer before asking opam itself.
  local buffer_name = vim.api.nvim_buf_get_name(0)
  local start = buffer_name ~= "" and vim.fs.dirname(buffer_name) or vim.fn.getcwd()
  local local_switch = vim.fs.find("_opam", { path = start, upward = true, type = "directory" })[1]
  local candidates = {}
  if local_switch then
    candidates[#candidates + 1] = local_switch .. "/bin/" .. executable_name(name)
  end
  if vim.env.OPAM_SWITCH_PREFIX then
    candidates[#candidates + 1] = vim.env.OPAM_SWITCH_PREFIX .. "/bin/" .. executable_name(name)
  end
  candidates[#candidates + 1] = vim.fn.expand("~/.opam/default/bin/" .. executable_name(name))
  if vim.fn.has "macunix" == 1 then
    candidates[#candidates + 1] = "/opt/homebrew/bin/" .. name
    candidates[#candidates + 1] = "/usr/local/bin/" .. name
  end
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then
      tool_cache[name] = candidate
      return candidate
    end
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

local function format_ocaml(buffer)
  local ocamlformat = M.find_tool "ocamlformat"
  if not ocamlformat then
    vim.notify("ocamlformat was not found in the active opam switch.", vim.log.levels.ERROR)
    return
  end

  local conform = require "conform"
  conform.formatters.ocamlformat = {
    command = ocamlformat,
    prepend_args = function(_, ctx)
      local config = vim.fs.find(".ocamlformat", { path = ctx.dirname, upward = true })[1]
      return config and {} or { "--profile=janestreet" }
    end,
  }
  conform.format {
    bufnr = buffer,
    formatters = { "ocamlformat" },
    async = false,
    timeout_ms = 5000,
    lsp_format = "never",
  }
end

function M.setup_indent()
  if M.find_tool "ocp-indent" then
    -- selene: allow(global_usage)
    _G.CodexOCamlIndent = M.indent
    vim.opt_local.indentexpr = "v:lua.CodexOCamlIndent(v:lnum)"
  else
    -- The bundled OCaml indenter can move top-level `let` in the wrong direction.
    vim.opt_local.indentkeys:remove "0=let"
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

local function show_snippets()
  local luasnip_ok, luasnip = pcall(require, "luasnip")
  local pickers_ok, pickers = pcall(require, "telescope.pickers")
  if not luasnip_ok or not pickers_ok then
    vim.notify("The OCaml snippet picker is not available yet.", vim.log.levels.WARN)
    return
  end

  local finders = require "telescope.finders"
  local telescope_config = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local snippets = {}

  for _, info in ipairs(luasnip.available().ocaml or {}) do
    -- The automatic regex snippets duplicate the readable hint entries.
    if not info.trigger:find("(", 1, true) then
      snippets[#snippets + 1] = {
        trigger = info.trigger,
        name = info.name,
        description = table.concat(info.description or {}, " "),
      }
    end
  end

  table.sort(snippets, function(left, right)
    if left.trigger == right.trigger then
      return left.name < right.name
    end
    return left.trigger < right.trigger
  end)

  local target_window = vim.api.nvim_get_current_win()
  pickers
    .new({}, {
      prompt_title = "OCaml snippets (Enter inserts the trigger)",
      finder = finders.new_table {
        results = snippets,
        entry_maker = function(item)
          local display = string.format("%-10s  %-32s  %s", item.trigger, item.name, item.description)
          return {
            value = item,
            display = display,
            ordinal = table.concat({ item.trigger, item.name, item.description }, " "),
          }
        end,
      },
      sorter = telescope_config.generic_sorter {},
      attach_mappings = function(prompt_buffer)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_buffer)
          if not selection or not vim.api.nvim_win_is_valid(target_window) then
            return
          end

          vim.api.nvim_set_current_win(target_window)
          vim.api.nvim_put({ selection.value.trigger }, "c", true, true)
          vim.cmd "startinsert"
        end)
        return true
      end,
    })
    :find()
end

---@param buffer integer
function M.setup(buffer)
  buffer = buffer == 0 and vim.api.nvim_get_current_buf() or buffer

  vim.opt_local.expandtab = true
  vim.opt_local.shiftwidth = 2
  vim.opt_local.tabstop = 2
  vim.opt_local.softtabstop = -1

  M.setup_indent()

  -- Tree-sitter's FileType callback runs after the standard indent scripts.
  -- Reassert ocp-indent once all FileType callbacks have completed.
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buffer) or vim.bo[buffer].filetype ~= "ocaml" then
      return
    end
    vim.api.nvim_buf_call(buffer, M.setup_indent)
  end)

  local ok, which_key = pcall(require, "which-key")
  if ok then
    which_key.add { { "<leader>o", group = "OCaml", buffer = buffer } }
  end

  local map = function(lhs, rhs, description)
    vim.keymap.set("n", lhs, rhs, { buffer = buffer, desc = description, silent = true })
  end

  map("<leader>of", function()
    format_ocaml(buffer)
  end, "OCaml: format")
  map("<leader>oi", function()
    switch_implementation_interface(buffer)
  end, "OCaml: switch .ml/.mli")
  map("<leader>os", show_snippets, "OCaml: show snippets")
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
