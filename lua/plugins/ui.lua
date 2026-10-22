local explorer_sort = require "configs.explorer_sort"
local now_playing = require "configs.now_playing"
local buffer_close = require "configs.buffer_close"
local bufferline_fit = require "configs.bufferline_fit"

-- Files opened from the explorer land in the editor window you were last in:
-- never a terminal or panel, and never a "pick a window" prompt.
-- Recorded on WinLeave: a window entered by a split still shows the old file
-- for a moment (the tree's own window starts that way).
local last_file_win
local function is_file_window(win)
  return vim.api.nvim_win_is_valid(win)
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
    and vim.api.nvim_win_get_config(win).relative == ""
end
vim.api.nvim_create_autocmd("WinLeave", {
  group = vim.api.nvim_create_augroup("ExplorerTarget", { clear = true }),
  callback = function()
    if is_file_window(0) then
      last_file_win = vim.api.nvim_get_current_win()
    end
  end,
})

local function explorer_target_window()
  local tab_wins = vim.api.nvim_tabpage_list_wins(0)
  if last_file_win and vim.tbl_contains(tab_wins, last_file_win) and is_file_window(last_file_win) then
    return last_file_win
  end
  for _, win in ipairs(tab_wins) do
    if is_file_window(win) then
      return win
    end
  end
  -- Only the tree and panels are open: give the file a new window on the right.
  vim.cmd "botright vnew"
  return vim.api.nvim_get_current_win()
end

-- Opening the explorer never resizes the other panes; only the column next
-- to it gives up the room. nvim-tree opens by splitting the current window,
-- moving the new half to the far left and shrinking it, which reshuffled
-- every width on the way. Remember the sizes before it opens and put them back.
local sizes_before_tree
local function remember_pane_sizes()
  sizes_before_tree = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      sizes_before_tree[win] = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
    end
  end
end

local function restore_pane_sizes()
  local before = sizes_before_tree
  sizes_before_tree = nil
  if not before then
    return
  end
  local tree = require("nvim-tree.view").get_winnr()
  if not tree or not vim.api.nvim_win_is_valid(tree) then
    return
  end
  -- The panes touching the tree absorb its width; every other pane keeps its
  -- old size. Set the far ones right to left so each change only moves the
  -- divider on that pane's left.
  local tree_width = vim.api.nvim_win_get_width(tree)
  local tree_edge = vim.api.nvim_win_get_position(tree)[2] + tree_width + 1
  local far = {}
  for win, size in pairs(before) do
    if vim.api.nvim_win_is_valid(win) and win ~= tree then
      vim.api.nvim_win_set_height(win, size[2])
      if vim.api.nvim_win_get_position(win)[2] > tree_edge then
        far[#far + 1] = { win = win, width = size[1] }
      end
    end
  end
  table.sort(far, function(a, b)
    return vim.api.nvim_win_get_position(a.win)[2] > vim.api.nvim_win_get_position(b.win)[2]
  end)
  for _, pane in ipairs(far) do
    vim.api.nvim_win_set_width(pane.win, pane.width)
  end
  vim.api.nvim_win_set_width(tree, tree_width)
end

local function wakatime_statusline()
  local ok, wakatime = pcall(require, "wakatime")
  if not ok then
    return ""
  end

  return wakatime
    .statusline()
    :gsub("(%d+)%s*hours?", "%1h")
    :gsub("(%d+)%s*hrs?", "%1h")
    :gsub("(%d+)%s*minutes?", "%1m")
    :gsub("(%d+)%s*mins?", "%1m")
end

-- cmdheight=0 hides Vim's own "recording @q" message, so show it here.
local recording_component = {
  function()
    return "recording @" .. vim.fn.reg_recording()
  end,
  cond = function()
    return vim.fn.reg_recording() ~= ""
  end,
  color = { fg = "#ff9f74", gui = "bold" },
}

local wakatime_component = {
  wakatime_statusline,
  cond = function()
    return wakatime_statusline() ~= ""
  end,
  __wakatime_statusline = true,
}

local backgrounds = {
  dim = "#0e1113",
  editor = "#161a1c",
  raised = "#1b2023",
  status = "#0a0d0e",
  tab_inactive = "#0d0f11",
  tab_selected = "#1a1f22",
  tab_fill = "#060708",
}

local function bufferline_highlights()
  local inactive_bg = backgrounds.tab_inactive
  local selected_bg = backgrounds.tab_selected
  local fill_bg = backgrounds.tab_fill
  local highlights = {
    fill = { bg = fill_bg },
    background = { fg = "#7a8478", bg = inactive_bg },
    buffer = { fg = "#7a8478", bg = inactive_bg },
    buffer_visible = { fg = "#7a8478", bg = inactive_bg },
    buffer_selected = { fg = "#e6dcc3", bg = selected_bg, bold = true, italic = false },
    close_button = { fg = "#4f5b58", bg = inactive_bg },
    close_button_visible = { fg = "#4f5b58", bg = inactive_bg },
    close_button_selected = { fg = "#9da9a0", bg = selected_bg },
    separator = { fg = inactive_bg, bg = inactive_bg },
    separator_visible = { fg = inactive_bg, bg = inactive_bg },
    separator_selected = { fg = selected_bg, bg = selected_bg },
    indicator_visible = { fg = inactive_bg, bg = inactive_bg },
    indicator_selected = { fg = "#c5e396", bg = selected_bg },
    modified = { fg = "#859289", bg = inactive_bg },
    modified_visible = { fg = "#859289", bg = inactive_bg },
    modified_selected = { fg = "#b5db7a", bg = selected_bg },
    duplicate = { fg = "#7a8478", bg = inactive_bg, italic = true },
    duplicate_visible = { fg = "#7a8478", bg = inactive_bg, italic = true },
    duplicate_selected = { fg = "#e6dcc3", bg = selected_bg, italic = true },
  }

  for _, name in ipairs { "diagnostic", "hint_diagnostic", "info_diagnostic", "warning_diagnostic", "error_diagnostic" } do
    highlights[name] = { bg = inactive_bg }
    highlights[name .. "_visible"] = { bg = inactive_bg }
    highlights[name .. "_selected"] = { bg = selected_bg, bold = true }
  end

  return highlights
end

local function dark_lualine_theme()
  local theme = vim.deepcopy(require "lualine.themes.everforest")
  local status_bg = backgrounds.status

  for name, mode in pairs(theme) do
    if mode.b then
      mode.b.bg = status_bg
    end
    if mode.c then
      mode.c.bg = status_bg
    end
    if name == "inactive" and mode.a then
      mode.a.bg = status_bg
    end
  end

  return theme
end

return {
  {
    "sainnhe/everforest",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.everforest_background = "hard"
      -- Unfocused panes are dimmed by configs/focus_dim.lua instead: a darker
      -- background was too faint to see and doubled every divider.
      vim.g.everforest_dim_inactive_windows = 0
      vim.g.everforest_colors_override = {
        bg_dim = { backgrounds.dim, "233" },
        bg0 = { backgrounds.editor, "235" },
        bg1 = { "#1d2326", "236" },
        bg2 = { "#262d30", "237" },
        bg3 = { "#2f3639", "238" },
        bg4 = { "#373d40", "239" },
        bg5 = { "#3c4541", "240" },
        bg_visual = { "#4a3440", "52" },
        bg_red = { "#302427", "52" },
        bg_yellow = { "#2c2a22", "136" },
        bg_green = { "#262e27", "22" },
        bg_blue = { "#233037", "17" },
        bg_purple = { "#2e272d", "54" },
        -- Everforest Night: same hues as the desktop theme
        -- (~/.config/omarchy/themes/everforest/colors.toml).
        fg = { "#e6dcc3", "223" },
        red = { "#ff797c", "167" },
        orange = { "#ff9f74", "208" },
        yellow = { "#fcce73", "214" },
        green = { "#b5db7a", "142" },
        aqua = { "#7eda94", "108" },
        blue = { "#7ad5c9", "109" },
        purple = { "#ee95c0", "175" },
        statusline1 = { "#b5db7a", "142" },
        statusline2 = { "#e6dcc3", "223" },
        statusline3 = { "#ff797c", "167" },
      }
      vim.g.everforest_better_performance = 1
      vim.g.everforest_enable_italic = 1
      vim.cmd.colorscheme "everforest"
      -- One surface for every float (hover, diagnostics, pickers, notices,
      -- which-key): the window's own card colour and alpha, a soft rounded
      -- border on that same surface. A second shade inside or around the
      -- border read as a box drawn in a box.
      vim.api.nvim_set_hl(0, "NormalFloat", { link = "Normal" })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#4f5b58" })
      vim.api.nvim_set_hl(0, "FloatTitle", { fg = "#b5db7a", bold = true })
      vim.api.nvim_set_hl(0, "TelescopeBorder", { link = "FloatBorder" })

      -- Every pane (editor, explorer, terminal, focused or not) sits on the
      -- one card surface, so a divider is a thin line drawn on that surface
      -- with nothing beside it. A full-cell gutter read as a thick bar, and
      -- panes of different shades left a strip of one beside the other.
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#2f3639" })
      vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { link = "WinSeparator" })

      vim.api.nvim_set_hl(0, "ExplorerHeader", { fg = "#b5db7a", bold = true })
      vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = "#859289", italic = true })
      vim.api.nvim_set_hl(0, "ExplorerSortTitle", { fg = "#859289" })
      vim.api.nvim_set_hl(0, "ExplorerSortButton", { fg = "#e6dcc3" })
      vim.api.nvim_set_hl(0, "ExplorerSortActive", { fg = "#b5db7a", bold = true })
      vim.api.nvim_set_hl(0, "WinBar", {})
      vim.api.nvim_set_hl(0, "WinBarNC", {})
      for _, group in ipairs { "NvimTreeNormal", "NvimTreeNormalNC", "NvimTreeSignColumn", "NormalNC" } do
        vim.api.nvim_set_hl(0, group, { link = "Normal" })
      end
      vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { link = "EndOfBuffer" })
      require("configs.focus_dim").setup()
    end,
  },

  {
    "akinsho/bufferline.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      highlights = bufferline_highlights(),
      options = {
        close_command = buffer_close.delete,
        right_mouse_command = buffer_close.delete,
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        show_close_icon = false,
        show_buffer_close_icons = true,
        separator_style = "thin",
        name_formatter = bufferline_fit.name_formatter,
        offsets = {
          -- The open folder's name heads the explorer, so you always know
          -- which project you are in; the tree's root line shows where it lives.
          {
            filetype = "NvimTree",
            text = function()
              return "\u{f07c}  " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
            end,
            highlight = "ExplorerHeader",
            padding = 1,
          },
        },
      },
    },
    config = function(_, opts)
      require("bufferline").setup(opts)
      bufferline_fit.setup()
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function()
      now_playing.setup()
      vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
        group = vim.api.nvim_create_augroup("LualineRecording", { clear = true }),
        callback = function()
          -- reg_recording() is still set during RecordingLeave; refresh after it clears.
          vim.schedule(function()
            require("lualine").refresh()
          end)
        end,
      })
      return {
        options = {
          theme = dark_lualine_theme(),
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          globalstatus = true,
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff" },
          lualine_c = { { "filename", path = 1 } },
          lualine_x = {
            recording_component,
            "diagnostics",
            { now_playing.statusline, color = { fg = "#b5db7a" } },
            "filetype",
            wakatime_component,
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      }
    end,
  },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFocus" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
      sort = { sorter = explorer_sort.nvim_tree_sorter },
      view = { width = 30, side = "left", preserve_window_proportions = true },
      renderer = {
        group_empty = true,
        highlight_git = true,
        -- The folder's name is in the header above; the root line says where
        -- it lives ("in ~/Work/project"), shortened so it never runs off.
        root_folder_label = function(path)
          local parent = vim.fn.fnamemodify(path, ":~:h")
          local width = 30 - 4
          if vim.fn.strdisplaywidth(parent) > width then
            parent = vim.fn.pathshorten(parent)
          end
          return "in " .. parent
        end,
      },
      filters = { dotfiles = false },
      git = { enable = true },
      actions = {
        change_dir = { global = true },
        open_file = { window_picker = { picker = explorer_target_window } },
      },
      -- Name files in notices, not their full path, so a notice fits one line.
      notify = { absolute_path = false },
      on_attach = function(bufnr)
        local api = require "nvim-tree.api"
        api.config.mappings.default_on_attach(bufnr)
        explorer_sort.attach(bufnr)
        -- Ctrl+K moves to the window above everywhere; nvim-tree's file-info
        -- popup on that key broke it inside the tree.
        vim.keymap.del("n", "<C-k>", { buffer = bufnr })

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(winid) == bufnr then
              vim.wo[winid].winbar = "%!v:lua.require'configs.explorer_sort'.winbar()"
            end
          end
        end)

        -- With nothing copied in the tree, nvim-tree's paste reads the system
        -- clipboard and tries to copy every line as a file path, so an image
        -- or a paragraph on the clipboard became a stack of red popups. Only
        -- fall back to the clipboard when every line names a real file.
        local function paste_guarded(action)
          return function()
            local explorer = require("nvim-tree.core").get_explorer()
            local own = explorer and explorer.clipboard and explorer.clipboard.data or {}
            if #(own.copy or {}) == 0 and #(own.cut or {}) == 0 then
              local lines = vim.split(vim.fn.getreg "+", "\n", { trimempty = true })
              local paths = #lines > 0
              for _, line in ipairs(lines) do
                paths = paths and line:sub(1, 1) == "/" and vim.uv.fs_stat(line) ~= nil
              end
              if not paths then
                vim.api.nvim_echo({ { "Nothing to paste: copy a file with c or x first" } }, false, {})
                return
              end
            end
            action()
          end
        end
        local paste_opts = { buffer = bufnr, noremap = true, silent = true, nowait = true }
        vim.keymap.set("n", "p", paste_guarded(api.fs.paste), vim.tbl_extend("force", paste_opts, { desc = "Paste" }))
        vim.keymap.set("n", "gp", paste_guarded(api.fs.move), vim.tbl_extend("force", paste_opts, { desc = "Move" }))

        vim.keymap.del("n", "<CR>", { buffer = bufnr })
        vim.keymap.set("n", "<CR>", function()
          local node = api.tree.get_node_under_cursor()
          if not node then
            return
          end
          if node.nodes then
            api.tree.change_root_to_node()
          else
            api.node.open.edit()
          end
        end, { buffer = bufnr, noremap = true, silent = true, nowait = true })

        vim.keymap.set(
          "n",
          "<BS>",
          api.tree.change_root_to_parent,
          { buffer = bufnr, noremap = true, silent = true, nowait = true }
        )
        vim.keymap.set(
          "n",
          "-",
          api.tree.change_root_to_parent,
          { buffer = bufnr, noremap = true, silent = true, nowait = true }
        )
      end,
    },
    config = function(_, opts)
      require("nvim-tree").setup(opts)
      local api = require "nvim-tree.api"
      api.events.subscribe(api.events.Event.TreePreOpen, remember_pane_sizes)
      api.events.subscribe(api.events.Event.TreeOpen, restore_pane_sizes)
    end,
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>m", group = "Multicursor" },
        { "<leader>x", group = "Diagnostics" },
        { "<leader>S", group = "Session" },
        { "<leader>l", group = "Lint" },
        { "<leader>s", group = "Search" },
        { "<leader>g", group = "Git" },
        { "<leader>t", group = "Terminal & todo" },
      },
    },
  },

  {
    "rcarriga/nvim-notify",
    lazy = true,
    opts = {
      background_colour = "#000000",
      stages = "fade",
      timeout = 2000,
      render = "wrapped-compact",
      minimum_width = 28,
      max_width = function()
        return math.min(72, math.max(30, math.floor(vim.o.columns * 0.42)), vim.o.columns - 4)
      end,
      max_height = function()
        return math.min(12, math.max(4, math.floor(vim.o.lines * 0.3)), vim.o.lines - 4)
      end,
    },
  },

  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    opts = {
      cmdline = { view = "cmdline_popup" },
      messages = { view = "mini" },
      popupmenu = { enabled = true },
      notify = { enabled = true, view = "notify" },
      -- A stray key should cost at most one short line. One-line Vim refusals
      -- (E21 "not modifiable" in a tree or terminal, E486 "pattern not found")
      -- and one-line info notices go to the corner line; multi-line errors
      -- (real bugs, with tracebacks) still get a popup.
      routes = {
        { filter = { event = "msg_show", kind = "emsg", find = "^E%d+: [^\n]*$" }, view = "mini" },
        { filter = { event = "notify", kind = { "info", "debug", "trace" }, max_height = 1 }, view = "mini" },
      },
      views = {
        -- Popups replace each other instead of stacking down the screen.
        notify = { replace = true },
        cmdline_popup = {
          position = { row = "50%", col = "50%" },
          size = { width = 70, height = "auto" },
          border = { style = "rounded" },
        },
        cmdline_popupmenu = {
          position = { row = "62%", col = "50%" },
          size = { width = 70, height = 10 },
          border = { style = "rounded" },
        },
      },
    },
  },
}
