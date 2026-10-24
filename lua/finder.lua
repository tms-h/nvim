-- The finder (mini.pick, mini.extra): Alt/Cmd+P and friends (keys.lua),
-- :Pick, vim.ui.select and the folder picker. Set up on first use, which
-- keeps ~3 ms off every start.
local M = {}

local ready = false

---MiniPick, set up.
function M.load()
  if not ready then
    ready = true
    pcall(vim.api.nvim_del_user_command, "Pick")
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
        config = function()
          local width = math.min(90, math.floor(vim.o.columns * 0.6))
          local height = math.min(18, math.floor(vim.o.lines * 0.45))
          return {
            anchor = "NW",
            row = math.floor((vim.o.lines - height) * 0.3),
            col = math.floor((vim.o.columns - width) / 2),
            width = width,
            height = height,
          }
        end,
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

M.files = from_editor(function()
  MiniPick.builtin.files()
end)

M.grep = from_editor(function()
  MiniPick.builtin.grep_live()
end)

M.commands = from_editor(function()
  MiniExtra.pickers.commands()
end)

---`:Pick <args>` from the editor pane (the leader keys).
M.pick = from_editor(function(args)
  vim.cmd("Pick " .. args)
end)

function M.setup()
  vim.ui.select = function(...)
    return M.load().ui_select(...)
  end
  vim.api.nvim_create_user_command("Pick", function(args)
    M.load()
    vim.cmd("Pick " .. args.args)
  end, { nargs = "+", desc = "Open a finder (mini.pick)" })
end

return M
