local M = {}

local GPP_FALLBACKS = {
  "C:/msys64/ucrt64/bin/g++.exe",
  "C:/msys64/mingw64/bin/g++.exe",
  "C:/MinGW/bin/g++.exe",
}

function M.find_gpp()
  local path = vim.fn.exepath("g++")
  if path ~= "" then
    return path
  end
  for _, candidate in ipairs(GPP_FALLBACKS) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  return nil
end

function M.find_python()
  local path = vim.fn.exepath("python3")
  if path ~= "" then
    return path
  end
  path = vim.fn.exepath("python")
  if path ~= "" then
    return path
  end
  return nil
end

--- Open a horizontal terminal and run a shell command (cmd.exe on Windows).
function M.run_in_terminal(cmd)
  vim.cmd.write()
  vim.cmd("belowright split")
  vim.fn.termopen(cmd)
  vim.cmd.startinsert()
end

function M.run_cpp()
  local gpp = M.find_gpp()
  if not gpp then
    vim.notify("g++ not found. Install MSYS2 MinGW and add ucrt64\\bin to PATH.", vim.log.levels.ERROR)
    return
  end

  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("Save the file first.", vim.log.levels.WARN)
    return
  end

  local out = vim.fn.tempname() .. (vim.fn.has("win32") == 1 and ".exe" or "")
  local cmd
  if vim.fn.has("win32") == 1 then
    cmd = string.format(
      '"%s" -std=c++20 -Wall -o "%s" "%s" && "%s"',
      gpp,
      out,
      file,
      out
    )
  else
    cmd = string.format(
      '%s -std=c++20 -Wall -o %s %s && %s',
      vim.fn.shellescape(gpp),
      vim.fn.shellescape(out),
      vim.fn.shellescape(file),
      vim.fn.shellescape(out)
    )
  end

  M.run_in_terminal(cmd)
end

function M.run_python()
  local python = M.find_python()
  if not python then
    vim.notify("python not found on PATH.", vim.log.levels.ERROR)
    return
  end

  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("Save the file first.", vim.log.levels.WARN)
    return
  end

  local cmd = string.format('"%s" "%s"', python, file)
  M.run_in_terminal(cmd)
end

local function bind_run(buf, run_fn, desc)
  local keys = { "<F5>" }
  if vim.g.neovide and vim.fn.has("mac") == 1 then
    table.insert(keys, require("util.modifier").chord("r"))
  end
  local function run()
    if vim.api.nvim_get_mode().mode:match("^[iv]") then
      vim.cmd.stopinsert()
    end
    run_fn()
  end
  for _, lhs in ipairs(keys) do
    vim.keymap.set({ "n", "i", "v" }, lhs, run, { buffer = buf, desc = desc, silent = true })
  end
end

function M.setup_ft(buf, ft)
  if ft == "cpp" or ft == "c" then
    bind_run(buf, M.run_cpp, "Compile and run (F5)")
  elseif ft == "python" then
    bind_run(buf, M.run_python, "Run Python (F5)")
  end
end

return M
