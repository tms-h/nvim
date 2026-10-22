local modifier = require "util.modifier"

local M = {}

function M.find_python()
  for _, name in ipairs { "python3", "python", "py" } do
    local path = vim.fn.exepath(name)
    if path ~= "" then
      return path
    end
  end
end

local function shell_quote(value)
  if modifier.is_windows then
    return '"' .. value:gsub('"', '\\"') .. '"'
  end
  return vim.fn.shellescape(value)
end

-- Run in a separate terminal window so the editor layout stays untouched. The
-- window waits for a key after the program exits so its output stays readable.
local function open_external_terminal(command)
  if modifier.is_windows or modifier.is_macos or vim.fn.executable "xdg-terminal-exec" == 0 then
    return false
  end

  local script = command .. '; printf "\\n[exit %d] press any key to close" $?; read -rsn1'
  local job = vim.fn.jobstart({ "xdg-terminal-exec", "bash", "-c", script }, {
    cwd = vim.fn.expand "%:p:h",
    detach = true,
  })
  return job > 0
end

local function open_terminal(command)
  if open_external_terminal(command) then
    return
  end

  vim.cmd "belowright split"
  vim.cmd "resize 15"
  local terminal_buffer = vim.api.nvim_get_current_buf()
  vim.fn.termopen(command)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(terminal_buffer) then
      vim.api.nvim_buf_delete(terminal_buffer, { force = true })
    end
  end, { buffer = terminal_buffer, desc = "Close run pane", silent = true })
  vim.cmd.startinsert()
end

local function current_file()
  local file = vim.fn.expand "%:p"
  if file == "" then
    vim.notify("Save the file before running it.", vim.log.levels.WARN)
    return
  end
  vim.cmd.write()
  return file
end

function M.run_python()
  local python = M.find_python()
  if not python then
    vim.notify("Python was not found on PATH.", vim.log.levels.ERROR)
    return
  end

  local file = current_file()
  if not file then
    return
  end
  open_terminal(shell_quote(python) .. " " .. shell_quote(file))
end

local function bind_run(buffer, run, description)
  local keys = { "<F5>" }
  -- Only Cmd+R on macOS: Ctrl+R is Vim's redo everywhere else.
  if vim.g.neovide and modifier.is_macos then
    keys[#keys + 1] = modifier.chord "r"
  end

  for _, key in ipairs(keys) do
    vim.keymap.set("n", key, run, {
      buffer = buffer,
      desc = description,
      silent = true,
    })
  end
end

function M.setup_python(buffer)
  bind_run(buffer, M.run_python, "Run Python")
end

return M
