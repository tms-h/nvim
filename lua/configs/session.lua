local M = {}

local uv = vim.uv or vim.loop
local is_windows = vim.fn.has "win32" == 1

local function normalize(path)
  if not path or path == "" then
    return nil
  end

  local resolved = uv.fs_realpath(vim.fn.expand(path))
  path = resolved or vim.fn.fnamemodify(path, ":p")
  path = path:gsub("\\", "/"):gsub("/+$", "")
  return is_windows and path:lower() or path
end

local function is_within(path, root)
  return path and root and (path == root or vim.startswith(path, root .. "/"))
end

local config_root = normalize(vim.fn.stdpath "config")
local temporary_roots = {}

for _, path in ipairs { vim.env.TMPDIR, vim.env.TEMP, vim.env.TMP, "/tmp", "/private/tmp" } do
  local root = normalize(path)
  if root then
    temporary_roots[root] = true
  end
end

function M.is_config_path(path)
  return is_within(normalize(path), config_root)
end

function M.is_config_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return M.is_config_path(vim.api.nvim_buf_get_name(bufnr))
end

local function is_temporary_path(path)
  path = normalize(path)
  for root in pairs(temporary_roots) do
    if is_within(path, root) then
      return true
    end
  end
  return false
end

local function session_directory(session_file)
  local filename = vim.fn.fnamemodify(session_file, ":t")
  if not vim.endswith(filename, ".vim") then
    return nil
  end

  local encoded = filename:sub(1, -5)
  encoded = vim.split(encoded, "%%", { plain = true })[1]
  local directory = encoded:gsub("%%", "/")
  if is_windows then
    directory = directory:gsub("^(%w)/", "%1:/")
  end
  return normalize(directory)
end

function M.last_project()
  for _, session_file in ipairs(require("persistence").list()) do
    local directory = session_directory(session_file)
    if
      directory
      and vim.fn.isdirectory(directory) == 1
      and not M.is_config_path(directory)
      and not is_temporary_path(directory)
    then
      return session_file, directory
    end
  end
end

function M.load_last_project()
  local _, directory = M.last_project()
  if not directory then
    return false
  end

  vim.fn.chdir(directory)
  require("persistence").load()
  return true
end

function M.cleanup_restored_config_buffers()
  if M.is_config_path(vim.fn.getcwd()) then
    return
  end

  local config_buffers = {}
  local replacement
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if M.is_config_buffer(bufnr) then
      config_buffers[#config_buffers + 1] = bufnr
    elseif
      not replacement
      and vim.bo[bufnr].buflisted
      and vim.bo[bufnr].buftype == ""
      and vim.api.nvim_buf_get_name(bufnr) ~= ""
    then
      replacement = bufnr
    end
  end

  if #config_buffers == 0 then
    return
  end

  replacement = replacement or vim.api.nvim_create_buf(true, false)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if
      vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_win_get_config(winid).relative == ""
      and M.is_config_buffer(vim.api.nvim_win_get_buf(winid))
    then
      vim.api.nvim_win_set_buf(winid, replacement)
    end
  end

  for _, bufnr in ipairs(config_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and not vim.bo[bufnr].modified then
      local name = vim.api.nvim_buf_get_name(bufnr)
      pcall(vim.cmd, "silent! argdelete " .. vim.fn.fnameescape(name))
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

-- Open a project folder the way `nvim some/folder` does (VS Code's Open
-- Folder): save this folder's session, close its buffers, cd in, restore the
-- new folder's session and show the explorer.
---@param opts? { startup: boolean } startup: Neovim is just opening, nothing to save
function M.open_folder(path, opts)
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("[/\\]+$", "")
  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify("Not a folder: " .. path, vim.log.levels.WARN)
    return
  end
  if not (opts and opts.startup) then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[bufnr].buflisted and vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
        local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
        vim.notify("Save or close " .. (name ~= "" and name or "[No Name]") .. " first", vim.log.levels.WARN)
        return
      end
    end
    local persistence = require "persistence"
    if persistence.active() then
      persistence.save()
    end
    vim.cmd "silent! %bwipeout!"
  end
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  vim.cmd "silent! %argdelete"
  require("persistence").load()
  -- After SessionLoadPost's scheduled cleanup, which closes explorer windows.
  vim.schedule(function()
    vim.cmd "NvimTreeFocus"
    vim.cmd "wincmd p"
  end)
end

-- Fuzzy-pick a folder to open: recent projects first, then folders under ~.
function M.pick_folder()
  local seen, folders = {}, {}
  local function add(dir)
    dir = dir and vim.fn.fnamemodify(dir, ":p"):gsub("[/\\]+$", "")
    if dir and dir ~= "" and not seen[dir] and vim.fn.isdirectory(dir) == 1 then
      seen[dir] = true
      folders[#folders + 1] = dir
    end
  end
  for _, file in ipairs(require("persistence").list()) do
    add(session_directory(file))
  end
  if vim.fn.executable "fd" == 1 then
    local home = vim.fn.expand "~"
    local fd = { "fd", "--type", "d", "--max-depth", "4", "--absolute-path" }
    for _, skip in ipairs { "node_modules", "_build", "_opam", "target", ".git" } do
      vim.list_extend(fd, { "--exclude", skip })
    end
    vim.list_extend(fd, { ".", home })
    for _, dir in ipairs(vim.split(vim.system(fd, { text = true }):wait().stdout or "", "\n", { trimempty = true })) do
      add(dir)
    end
  end

  local home = vim.fn.expand "~"
  require("telescope.pickers")
    .new({}, {
      prompt_title = "Open Folder",
      finder = require("telescope.finders").new_table {
        results = folders,
        entry_maker = function(dir)
          local shown = vim.startswith(dir, home) and "~" .. dir:sub(#home + 1) or dir
          return { value = dir, display = shown, ordinal = shown }
        end,
      },
      sorter = require("telescope.config").values.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        local actions = require "telescope.actions"
        actions.select_default:replace(function()
          local entry = require("telescope.actions.state").get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            M.open_folder(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
