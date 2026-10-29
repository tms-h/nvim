-- Where the toolchains live. A GUI launch (Neovide from a launcher or Finder)
-- does not run the shell's startup files, so opam, cargo, Mason and Homebrew
-- are put on PATH here. Every machine-specific path has a fallback: a missing
-- folder is skipped.
local M = {}

local is_macos = vim.fn.has "macunix" == 1
local is_windows = vim.fn.has "win32" == 1
local sep = is_windows and ";" or ":"

---Put `dir` on PATH. A folder already there keeps its place, unless
---`first` (then it moves to the front).
local function prepend(dir, first)
  if not dir or dir == "" then
    return
  end
  dir = vim.fn.expand(dir)
  if vim.fn.isdirectory(dir) == 0 then
    return
  end
  local parts = vim.split(vim.env.PATH or "", sep, { plain = true })
  if vim.tbl_contains(parts, dir) then
    if not first then
      return
    end
    parts = vim.tbl_filter(function(p)
      return p ~= dir
    end, parts)
  end
  table.insert(parts, 1, dir)
  vim.env.PATH = table.concat(parts, sep)
end

function M.setup_path()
  -- Mason's tools: this config's own data folder first, then the default
  -- one (the same folder on a normal start; a scratch test setup borrows it).
  prepend "~/.local/share/nvim/mason/bin"
  prepend(vim.fn.stdpath "data" .. "/mason/bin")
  prepend "~/.cargo/bin"
  if is_macos then
    prepend "/opt/homebrew/bin"
    prepend "~/.pyenv/shims"
    -- nvm sets PATH in shell startup files, which Finder does not run.
    local alias = vim.fn.expand "~/.nvm/alias/default"
    if vim.fn.filereadable(alias) == 1 then
      local version = vim.trim(vim.fn.readfile(alias)[1] or "")
      local bins = vim.fn.glob(vim.fn.expand("~/.nvm/versions/node/v" .. version .. "*/bin"), false, true)
      table.sort(bins)
      prepend(bins[#bins])
    end
  elseif is_windows then
    prepend "~/.pyenv/pyenv-win/shims"
  end
  -- OCaml: the switch the shell has active, else the default one; a
  -- project's own switch (_opam, use_project_switch) wins over both.
  if vim.env.OPAM_SWITCH_PREFIX then
    prepend(vim.env.OPAM_SWITCH_PREFIX .. "/bin", true)
  else
    prepend "~/.opam/default/bin"
  end
  M.use_project_switch()
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("ProjectSwitch", { clear = true }),
    callback = M.use_project_switch,
  })
end

local project_bin -- the _opam/bin this window put on PATH

---Put the current folder's own opam switch (_opam) first on PATH, and take
---the previous folder's off.
function M.use_project_switch()
  if project_bin then
    vim.env.PATH = table.concat(
      vim.tbl_filter(function(p)
        return p ~= project_bin
      end, vim.split(vim.env.PATH or "", sep, { plain = true })),
      sep
    )
    project_bin = nil
  end
  local switch = vim.fs.find("_opam", { upward = true, type = "directory", path = vim.fn.getcwd() })[1]
  if switch and vim.fn.isdirectory(switch .. "/bin") == 1 then
    project_bin = switch .. "/bin"
    prepend(project_bin, true)
  end
end

---Path of an executable, or nil.
---@param name string
---@return string?
function M.find(name)
  local path = vim.fn.exepath(name)
  return path ~= "" and path or nil
end

return M
