local M = {
  modes = {
    oil = "name",
    NvimTree = "name",
  },
}

local function clicked_window()
  local winid = vim.fn.getmousepos().winid
  if winid ~= 0 and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
end

local function explorer_window(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
  if filetype == "oil" or filetype == "NvimTree" then
    return winid
  end
end

local function apply_sort(winid, mode, oil_sort)
  winid = explorer_window(winid)
  if not winid then
    return
  end

  vim.api.nvim_win_call(winid, function()
    local filetype = vim.bo.filetype
    if filetype == "oil" then
      require("oil").set_sort(oil_sort)
      M.modes.oil = mode
    elseif filetype == "NvimTree" then
      M.modes.NvimTree = mode
      require("nvim-tree.api").tree.reload()
    end
  end)
  vim.cmd.redrawstatus()
end

function M.sort_name(winid)
  apply_sort(winid, "name", { { "type", "asc" }, { "name", "asc" } })
end

function M.sort_recent(winid)
  apply_sort(winid, "recent", { { "type", "asc" }, { "birthtime", "desc" } })
end

function M.show_more(winid)
  winid = explorer_window(winid)
  if not winid then
    return
  end

  local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype

  local choices = {
    { label = "Name (A–Z)", mode = "name", sort = { { "type", "asc" }, { "name", "asc" } } },
    { label = "Recently added", mode = "recent", sort = { { "type", "asc" }, { "birthtime", "desc" } } },
  }
  if filetype == "oil" then
    vim.list_extend(choices, {
      { label = "Recently modified", mode = "other", sort = { { "type", "asc" }, { "mtime", "desc" } } },
      { label = "Largest first", mode = "other", sort = { { "type", "asc" }, { "size", "desc" } } },
      { label = "Smallest first", mode = "other", sort = { { "type", "asc" }, { "size", "asc" } } },
    })
  end

  vim.ui.select(choices, {
    prompt = "Sort explorer by",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice or not vim.api.nvim_win_is_valid(winid) then
      return
    end
    apply_sort(winid, choice.mode, choice.sort)
  end)
end

function M.attach(bufnr)
  local options = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "gn", M.sort_name, vim.tbl_extend("force", options, { desc = "Sort explorer by name" }))
  vim.keymap.set(
    "n",
    "ga",
    M.sort_recent,
    vim.tbl_extend("force", options, { desc = "Sort explorer by recently added" })
  )
  vim.keymap.set("n", "gs", M.show_more, vim.tbl_extend("force", options, { desc = "Choose explorer sort" }))
end

function M.nvim_tree_sorter(nodes)
  if M.modes.NvimTree ~= "recent" then
    return "name"
  end

  local metadata = {}
  for _, node in ipairs(nodes) do
    local stat = vim.uv.fs_stat(node.absolute_path)
    metadata[node.absolute_path] = {
      directory = stat and stat.type == "directory" or false,
      added = stat and stat.birthtime and stat.birthtime.sec or 0,
    }
  end

  table.sort(nodes, function(a, b)
    local a_meta = metadata[a.absolute_path]
    local b_meta = metadata[b.absolute_path]
    if a_meta.directory ~= b_meta.directory then
      return a_meta.directory
    end
    if a_meta.added ~= b_meta.added then
      return a_meta.added > b_meta.added
    end
    return a.name:lower() < b.name:lower()
  end)
end

local function format_button(id, label, active)
  local highlight = active and "ExplorerSortActive" or "ExplorerSortButton"
  return ("%%#%s#%%%d@v:lua.ExplorerSortClick@ %s %%T"):format(highlight, id, label)
end

function M.winbar()
  local winid = tonumber(vim.g.statusline_winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return ""
  end

  local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
  if filetype ~= "oil" and filetype ~= "NvimTree" then
    return ""
  end

  local mode = M.modes[filetype]
  local parts = {
    "%#ExplorerSortTitle# Sort ",
    format_button(1, "Name (gn)", mode == "name"),
    " ",
    format_button(2, "Added (ga)", mode == "recent"),
  }
  if filetype == "oil" then
    parts[#parts + 1] = " "
    parts[#parts + 1] = format_button(3, "More… (gs)", mode == "other")
  end
  parts[#parts + 1] = "%#WinBar#"
  return table.concat(parts)
end

function M.click(id, mouse_button)
  if mouse_button ~= "l" then
    return
  end

  local winid = clicked_window()
  if not winid then
    return
  end
  if id == 1 then
    M.sort_name(winid)
  elseif id == 2 then
    M.sort_recent(winid)
  elseif id == 3 then
    M.show_more(winid)
  end
end

-- selene: allow(global_usage)
_G.ExplorerSortClick = function(id, _, mouse_button)
  require("configs.explorer_sort").click(id, mouse_button)
end

return M
