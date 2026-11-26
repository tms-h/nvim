-- The finder (mini.pick, mini.extra): Alt/Cmd+P and friends (keys.lua),
-- :Pick, vim.ui.select and the folder picker. Set up on first use, which
-- keeps ~3 ms off every start.
local M = {}

local ready = false

---Where the finder opens: centred, a little above the middle. The command
---box (cmdline.lua) opens on the same row.
function M.window()
  local width = math.min(90, math.floor(vim.o.columns * 0.6))
  local height = math.min(18, math.floor(vim.o.lines * 0.45))
  return {
    anchor = "NW",
    row = math.floor((vim.o.lines - height) * 0.3),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
  }
end

---MiniPick, set up.
function M.load()
  if not ready then
    ready = true
    -- One window; Tab shows the chosen item's preview in it. The old
    -- Telescope keys: C-x split below, C-v split beside, C-q every match to
    -- the quickfix list (marking moves to Alt+X).
    require("mini.pick").setup {
      options = { use_cache = true },
      mappings = {
        choose_in_split = "<C-x>",
        choose_in_vsplit = "<C-v>",
        mark = "<M-x>",
        to_quickfix = {
          char = "<C-q>",
          func = function()
            local matches = MiniPick.get_picker_matches()
            if matches and #matches.all > 0 then
              MiniPick.default_choose_marked(matches.all)
            end
            return true
          end,
        },
      },
      window = {
        config = M.window,
        prompt_prefix = "  ",
      },
    }
    require("mini.extra").setup()
  end
  return MiniPick
end

-- A picker opens its choice in the window it started from: start it from
-- the editor pane, never a terminal or the tree.
local function from_editor(fn)
  return function(...)
    local args = { ... }
    require("panes").in_editor(function()
      M.load()
      fn(unpack(args))
    end)
  end
end

-- Old bot copies in cambridge-battlecode (bots/T, opp-*, ...) stay out of the
-- file and grep lists, so a file name finds the live bots/main copy.
local hidden = { "!bots/{T,TR2b,cppbot,fuzz-opp,starter,idle,sdk-probe}/**", "!bots/{opp,ref,dbg}-*/**" }

M.files = from_editor(function()
  local command = { "rg", "--files", "--no-follow", "--color=never" }
  for _, glob in ipairs(hidden) do
    vim.list_extend(command, { "--glob", glob })
  end
  local show = function(buf, items, query)
    MiniPick.default_show(buf, items, query, { show_icons = true })
  end
  MiniPick.builtin.cli({ command = command }, { source = { name = "Files", show = show } })
end)

M.grep = from_editor(function()
  MiniPick.builtin.grep_live { globs = hidden }
end)

M.commands = from_editor(function()
  MiniExtra.pickers.commands()
end)

---Every symbol in the project, from the language server (ocamllsp:
---workspace symbols; needs a dune build). Typing narrows the list here.
M.symbols = from_editor(function()
  local has = #vim.lsp.get_clients { bufnr = 0, method = "workspace/symbol" } > 0
  if not has then
    vim.notify("No language server here to list project symbols", vim.log.levels.INFO)
    return
  end
  MiniExtra.pickers.lsp { scope = "workspace_symbol", symbol_query = "" }
end)

---`:Pick <args>` from the editor pane (the leader keys).
M.pick = from_editor(function(args)
  vim.cmd("Pick " .. args)
end)

function M.setup()
  vim.ui.select = function(...)
    return M.load().ui_select(...)
  end
  -- Stands in until the first use: mini.pick's setup replaces it with its own.
  vim.api.nvim_create_user_command("Pick", function(args)
    M.load()
    vim.cmd("Pick " .. args.args)
  end, { nargs = "+", desc = "Open a finder (mini.pick)" })
end

return M
