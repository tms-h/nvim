-- F5 runs the file you are in, in a terminal pane beside it (the same pane
-- each time). Ctrl+Shift+G opens lazygit full-window; quitting it closes it.
local M = {}

local api = vim.api
local tools = require "tools"

local function command_for(file, ft)
  local quoted = vim.fn.shellescape(file)
  if ft == "python" then
    local python = tools.find "python3" or tools.find "python" or "python3"
    return python .. " " .. quoted
  elseif ft == "ocaml" then
    -- In a dune project, dune's own errors; else the toplevel.
    if vim.fs.root(file, "dune-project") then
      return "dune exec ./" .. vim.fn.fnamemodify(file, ":t:r") .. ".exe"
    end
    return "ocaml " .. quoted
  elseif ft == "rust" then
    return "cargo run"
  elseif ft == "sh" or ft == "bash" then
    return "bash " .. quoted
  elseif ft == "lua" then
    return "nvim -l " .. quoted
  end
end

local runner_buf -- the terminal F5 last ran in

function M.current_file()
  local buf = api.nvim_get_current_buf()
  local file = api.nvim_buf_get_name(buf)
  local cmd = file ~= "" and command_for(file, vim.bo[buf].filetype)
  if not cmd then
    vim.notify "Nothing to run for this file"
    return
  end
  if vim.bo[buf].modified then
    vim.cmd.write()
  end
  require("panes").leave_zoom()
  local editor = api.nvim_get_current_win()
  -- The pane showing the last run, wherever swaps moved it; else a new one.
  local runner_win
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if runner_buf and api.nvim_win_get_buf(win) == runner_buf then
      runner_win = win
    end
  end
  if runner_win then
    api.nvim_set_current_win(runner_win)
  else
    require("panes").new_terminal()
  end
  local old = api.nvim_get_current_buf()
  vim.cmd.enew()
  if vim.bo[old].buftype == "terminal" then
    pcall(api.nvim_buf_delete, old, { force = true })
  end
  vim.fn.jobstart({ vim.o.shell, "-c", cmd }, { term = true, cwd = vim.fs.dirname(file) })
  runner_buf = api.nvim_get_current_buf()
  vim.bo.buflisted = false
  api.nvim_set_current_win(editor)
end

function M.lazygit()
  if not tools.find "lazygit" then
    vim.notify "lazygit is not installed"
    return
  end
  vim.cmd "tabnew"
  local buf = api.nvim_get_current_buf()
  vim.fn.jobstart({ "lazygit" }, {
    term = true,
    on_exit = function()
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
  vim.bo[buf].buflisted = false
  vim.cmd "startinsert"
end

return M
