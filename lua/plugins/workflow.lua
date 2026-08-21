local explorer_sort = require "configs.explorer_sort"

return {
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      default_file_explorer = false,
      view_options = { show_hidden = true },
      win_options = { winbar = "%!v:lua.require'configs.explorer_sort'.winbar()" },
      keymaps = {
        ["gn"] = { callback = explorer_sort.sort_name, desc = "Sort by name", mode = "n" },
        ["ga"] = { callback = explorer_sort.sort_recent, desc = "Sort by recently added", mode = "n" },
        ["gs"] = { callback = explorer_sort.show_more, desc = "Choose sort", mode = "n" },
      },
    },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Edit parent directory" },
    },
  },

  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = {},
    keys = {
      { "<leader>sr", "<cmd>GrugFar<cr>", desc = "Search and replace" },
    },
  },
}
