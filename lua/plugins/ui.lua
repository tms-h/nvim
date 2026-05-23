return {
  {
    "sainnhe/everforest",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.everforest_background = "medium"
      vim.g.everforest_better_performance = 1
      vim.g.everforest_enable_italic = 1
      vim.cmd.colorscheme("everforest")
    end,
  },

  {
    "akinsho/bufferline.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        close_command = function(n) require("mini.bufremove").delete(n, false) end,
        right_mouse_command = function(n) require("mini.bufremove").delete(n, false) end,
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        show_close_icon = false,
        show_buffer_close_icons = true,
        separator_style = "thin",
        offsets = {
          { filetype = "NvimTree", text = "Explorer", highlight = "Directory", padding = 1 },
        },
      },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "everforest",
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        globalstatus = true,
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "diagnostics", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFocus" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
      view = { width = 30, side = "left" },
      renderer = { group_empty = true, highlight_git = true },
      filters = { dotfiles = true },
      git = { enable = true },
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)

        vim.keymap.del("n", "<CR>", { buffer = bufnr })
        vim.keymap.set("n", "<CR>", function()
          local node = api.tree.get_node_under_cursor()
          if not node then return end
          if node.nodes then
            api.tree.change_root_to_node()
          else
            api.node.open.edit()
          end
        end, { buffer = bufnr, noremap = true, silent = true, nowait = true })

        vim.keymap.set("n", "<BS>", api.tree.change_root_to_parent,
          { buffer = bufnr, noremap = true, silent = true, nowait = true })
        vim.keymap.set("n", "-", api.tree.change_root_to_parent,
          { buffer = bufnr, noremap = true, silent = true, nowait = true })
      end,
    },
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>x", group = "Diagnostics" },
        { "<leader>q", group = "Session" },
        { "<leader>l", group = "Lint/LeetCode" },
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
      render = "compact",
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
    },
  },

  {
    "stevearc/dressing.nvim",
    lazy = true,
    init = function()
      vim.ui.select = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.select(...)
      end
      vim.ui.input = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.input(...)
      end
    end,
    opts = {},
  },
}
