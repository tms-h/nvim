-- One status line for the whole window (laststatus=3): words on the surface,
-- no blocks. Left: the mode as coloured text, macro recording, goose's vibe
-- level and pending writes, the file (the folder when the tree is focused).
-- Right: language-server progress, diagnostics, git changes, branch,
-- WakaTime's time today, position.
local M = {}

local api = vim.api

-- Each mode's name and colour (theme.lua: StatusLineMode<colour>, text only).
local MODES = {
  n = { "NORMAL", "Normal" },
  i = { "INSERT", "Insert" },
  R = { "REPLACE", "Replace" },
  v = { "VISUAL", "Visual" },
  V = { "V-LINE", "Visual" },
  ["\22"] = { "V-BLOCK", "Visual" },
  s = { "SELECT", "Visual" },
  S = { "S-LINE", "Visual" },
  t = { "TERMINAL", "Terminal" },
  c = { "COMMAND", "Command" },
}

-- Text shown as is: a "%" in it would start a status line item.
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

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
    return "%#StatusLineDim#" .. escape(vim.fn.fnamemodify(vim.fn.getcwd(), ":~")) .. "%*"
  end
  if name == "" then
    return "%#StatusLineDim#untitled%*"
  end
  local rel = vim.fn.fnamemodify(name, ":~:.")
  local dir, tail = rel:match "^(.*[/\\])([^/\\]+)$"
  local s = dir and ("%#StatusLineDim#" .. escape(dir) .. "%*" .. escape(tail)) or escape(rel)
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
  local mode = MODES[api.nvim_get_mode().mode:sub(1, 1)]
  if mode then
    parts[#parts + 1] = "%#StatusLineMode" .. mode[2] .. "#" .. mode[1] .. "%*"
  end
  local reg = vim.fn.reg_recording()
  if reg ~= "" then
    parts[#parts + 1] = "%#DiagnosticWarn#recording @" .. reg .. "%*"
  end
  -- Goose (goose.lua): its vibe level (:GooseVibe), and "goose writing N"
  -- while any conversion is pending.
  local goose = package.loaded.goose
  if goose and goose.vibe then
    parts[#parts + 1] = "%#StatusLineDim#vibe:" .. goose.vibe .. "%*"
  end
  local n = goose and goose.pending_count(0) or 0
  if n > 0 then
    parts[#parts + 1] = "%#DiagnosticWarn#goose writing " .. n .. "%*"
  end
  parts[#parts + 1] = file_part()
  local right = {}
  local progress = vim.lsp.status()
  if progress ~= "" then
    right[#right + 1] = "%#StatusLineDim#" .. escape(progress:sub(1, 40)) .. "%*"
  end
  local diag = diagnostics()
  if diag ~= "" then
    right[#right + 1] = diag
  end
  -- Lines added / changed / removed against git, like VS Code's gutter.
  local diff = vim.b.minidiff_summary or {}
  local d = {}
  for _, item in ipairs { { "add", "+", "Added" }, { "change", "~", "Changed" }, { "delete", "-", "Removed" } } do
    if (diff[item[1]] or 0) > 0 then
      d[#d + 1] = "%#" .. item[3] .. "#" .. item[2] .. diff[item[1]] .. "%*"
    end
  end
  if #d > 0 then
    right[#right + 1] = table.concat(d, " ")
  end
  if branch ~= "" then
    right[#right + 1] = "%#StatusLineDim# " .. escape(branch) .. "%*"
  end
  local today = M.wakatime()
  if today ~= "" then
    right[#right + 1] = "%#StatusLineDim#" .. escape(today) .. "%*"
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
