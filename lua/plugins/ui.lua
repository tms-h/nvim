local explorer_sort = require "configs.explorer_sort"
local now_playing = require "configs.now_playing"
local buffer_close = require "configs.buffer_close"

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
  terminal = "#07090a",
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
      vim.g.everforest_dim_inactive_windows = 1
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
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = backgrounds.raised })
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#2a312e", bg = backgrounds.editor })
      vim.api.nvim_set_hl(0, "WinSeparatorHover", { fg = "#56625c", bg = backgrounds.editor })

      -- Keep the existing panel colors, including underneath their divider
      -- cells and chrome, so only the one-pixel separator changes surface.
      vim.api.nvim_set_hl(0, "ExplorerHeader", { fg = "#b5db7a", bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "ExplorerSortTitle", { fg = "#859289", bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "ExplorerSortButton", { fg = "#e6dcc3", bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "ExplorerSortActive", { fg = "#b5db7a", bg = backgrounds.dim, bold = true })
      vim.api.nvim_set_hl(0, "WinBar", { bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "WinBarNC", { bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = backgrounds.dim, bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeSignColumn", { bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = "#2a312e", bg = backgrounds.dim })
      vim.api.nvim_set_hl(0, "NvimTreeWinSeparatorHover", { fg = "#56625c", bg = backgrounds.dim })
      -- A darker shade of the editor background keeps terminal panes distinct.
      vim.api.nvim_set_hl(0, "TermNormal", { bg = backgrounds.terminal })
      vim.api.nvim_set_hl(0, "TermWinSeparator", { fg = "#2a312e", bg = backgrounds.terminal })
      vim.api.nvim_set_hl(0, "TermWinSeparatorHover", { fg = "#56625c", bg = backgrounds.terminal })
      -- Horizontal split separators are a full character cell tall. When a
      -- terminal is directly below an editor, make that cell belong visually
      -- to the terminal so the divider stays a single line instead of a bar.
      vim.api.nvim_set_hl(0, "TerminalBoundary", { fg = "#2a312e", bg = backgrounds.terminal })
      vim.api.nvim_set_hl(0, "TerminalBoundaryHover", { fg = "#56625c", bg = backgrounds.terminal })
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
        offsets = {
          { filetype = "NvimTree", text = "Explorer", highlight = "ExplorerHeader", padding = 1 },
        },
      },
    },
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
      renderer = { group_empty = true, highlight_git = true },
      filters = { dotfiles = false },
      git = { enable = true },
      actions = { change_dir = { global = true } },
      on_attach = function(bufnr)
        local api = require "nvim-tree.api"
        api.config.mappings.default_on_attach(bufnr)
        explorer_sort.attach(bufnr)

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
        { "<leader>l", group = "Lint/LeetCode" },
        { "<leader>j", group = "Judge (CompetiTest)" },
        { "<leader>s", group = "Search" },
        { "<leader>g", group = "Git" },
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
      views = {
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

  {
    "stevearc/dressing.nvim",
    lazy = true,
    init = function()
      vim.ui.select = function(...)
        require("lazy").load { plugins = { "dressing.nvim" } }
        return vim.ui.select(...)
      end
      vim.ui.input = function(...)
        require("lazy").load { plugins = { "dressing.nvim" } }
        return vim.ui.input(...)
      end
    end,
    opts = {},
  },
}
