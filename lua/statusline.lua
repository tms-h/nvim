-- One status line for the whole window (laststatus=3): words on the surface,
-- no blocks. Left: the mode as coloured text, macro recording, the file.
-- Right: language-server progress, diagnostics, git changes, branch,
-- WakaTime's time today, position.
local M = {}

local api = vim.api

local MODES = {
  n = "NORMAL",
  i = "INSERT",
  R = "REPLACE",
  v = "VISUAL",
  V = "V-LINE",
  ["\22"] = "V-BLOCK",
  s = "SELECT",
  S = "S-LINE",
  t = "TERMINAL",
  c = "COMMAND",
}

-- Each mode's colour (theme.lua: StatusLineMode<Name>, text only).
local MODE_HL = {
  n = "Normal",
  i = "Insert",
  R = "Replace",
  v = "Visual",
  V = "Visual",
  ["\22"] = "Visual",
  s = "Visual",
  S = "Visual",
  t = "Terminal",
  c = "Command",
}

local branch = ""

---WakaTime's coding time today ("20m", "1h 5m"), from the plugin's cache;
---"" before it has loaded or when it has nothing.
function M.wakatime()
  local ok, wakatime = pcall(require, "wakatime")
  if not ok or type(wakatime.statusline) ~= "function" then
    return ""
  end
  local ok2, text = pcall(wakatime.statusline)
  if not ok2 or type(text) ~= "string" then
    return ""
  end
  return (
    text
      :gsub("(%d+)%s*hours?", "%1h")
      :gsub("(%d+)%s*hrs?", "%1h")
      :gsub("(%d+)%s*minutes?", "%1m")
      :gsub("(%d+)%s*mins?", "%1m")
  )
end

local function first_line(path)
  local f = io.open(path)
  if not f then
    return ""
  end
  local line = f:read "*l" or ""
  f:close()
  return line
end

local function read_branch()
  branch = ""
  local dot_git = vim.fs.find(".git", { upward = true, path = vim.fn.getcwd() })[1]
  if not dot_git then
    return
  end
  -- A worktree's .git is a file pointing at its own git folder.
  local dir = dot_git
  if vim.fn.isdirectory(dot_git) == 0 then
    local target = first_line(dot_git):match "^gitdir: (.+)$"
    if not target then
      return
    end
    dir = vim.fs.normalize(target:match "^/" and target or vim.fs.dirname(dot_git) .. "/" .. target)
  end
  local head = first_line(dir .. "/HEAD")
  branch = head:match "ref: refs/heads/(.+)" or head:sub(1, 7)
end

local function file_part()
  local buf = api.nvim_get_current_buf()
  local bt = vim.bo[buf].buftype
  if bt == "terminal" then
    return "%#StatusLineDim#terminal%*"
  end
  local name = api.nvim_buf_get_name(buf)
  if vim.bo[buf].filetype == "NvimTree" then
    return "%#StatusLineDim#" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~") .. "%*"
  end
  if name == "" then
    return "%#StatusLineDim#untitled%*"
  end
  local rel = vim.fn.fnamemodify(name, ":~:.")
  local dir, tail = rel:match "^(.*[/\\])([^/\\]+)$"
  local s = dir and ("%#StatusLineDim#" .. dir:gsub("%%", "%%%%") .. "%*" .. tail:gsub("%%", "%%%%"))
    or rel:gsub("%%", "%%%%")
  if vim.bo[buf].modified then
    s = s .. " %#StatusLineAccent#●%*"
  end
  if vim.bo[buf].readonly then
    s = s .. " %#StatusLineDim#read-only%*"
  end
  return s
end

local function diagnostics()
  local counts = vim.diagnostic.count(0)
  local out = {}
  local S = vim.diagnostic.severity
  for _, item in ipairs { { S.ERROR, "DiagnosticError" }, { S.WARN, "DiagnosticWarn" } } do
    local n = counts[item[1]]
    if n and n > 0 then
      out[#out + 1] = "%#" .. item[2] .. "#● " .. n .. "%*"
    end
  end
  return table.concat(out, " ")
end

function M.render()
  local parts = {}
  local key = api.nvim_get_mode().mode:sub(1, 1)
  local mode = MODES[key]
  if mode then
    parts[#parts + 1] = "%#StatusLineMode" .. MODE_HL[key] .. "#" .. mode .. "%*"
  end
  local reg = vim.fn.reg_recording()
  if reg ~= "" then
    parts[#parts + 1] = "%#DiagnosticWarn#recording @" .. reg .. "%*"
  end
  parts[#parts + 1] = file_part()
  local right = {}
  local progress = vim.lsp.status()
  if progress ~= "" then
    right[#right + 1] = "%#StatusLineDim#" .. progress:sub(1, 40):gsub("%%", "%%%%") .. "%*"
  end
  local diag = diagnostics()
  if diag ~= "" then
    right[#right + 1] = diag
  end
  -- Lines added / changed / removed against git, like VS Code's gutter.
  local diff = vim.b.minidiff_summary
  if diff and ((diff.add or 0) + (diff.change or 0) + (diff.delete or 0)) > 0 then
    local d = {}
    for _, item in ipairs { { "add", "+", "Added" }, { "change", "~", "Changed" }, { "delete", "-", "Removed" } } do
      if (diff[item[1]] or 0) > 0 then
        d[#d + 1] = "%#" .. item[3] .. "#" .. item[2] .. diff[item[1]] .. "%*"
      end
    end
    right[#right + 1] = table.concat(d, " ")
  end
  if branch ~= "" then
    right[#right + 1] = "%#StatusLineDim# " .. branch .. "%*"
  end
  local today = M.wakatime()
  if today ~= "" then
    right[#right + 1] = "%#StatusLineDim#" .. today:gsub("%%", "%%%%") .. "%*"
  end
  right[#right + 1] = "%l:%c"
  return " " .. table.concat(parts, "  ") .. "%=" .. table.concat(right, "   ") .. " "
end

function M.setup()
  vim.o.statusline = "%!v:lua.require'statusline'.render()"
  local group = api.nvim_create_augroup("Statusline", { clear = true })
  api.nvim_create_autocmd({ "VimEnter", "DirChanged", "FocusGained" }, { group = group, callback = read_branch })
  api.nvim_create_autocmd({ "LspProgress", "DiagnosticChanged", "RecordingEnter", "RecordingLeave" }, {
    group = group,
    callback = function()
      vim.schedule(function()
        vim.cmd.redrawstatus()
      end)
    end,
  })
end

return M
