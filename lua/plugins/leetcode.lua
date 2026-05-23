return {
  {
    "kawre/leetcode.nvim",
    build = ":TSUpdate html",
    cmd = "Leet",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = function(_, opts)
      opts = vim.tbl_deep_extend("force", opts or {}, {
        lang = "cpp",
        plugins = { non_standalone = true },
      })
      opts.hooks = opts.hooks or {}
      opts.hooks.enter = opts.hooks.enter or {}
      table.insert(opts.hooks.enter, function()
        require("configs.leetcode_timer").patch_runner()
      end)
      opts.hooks.question_enter = opts.hooks.question_enter or {}
      table.insert(opts.hooks.question_enter, function(q)
        require("configs.leetcode_timer").on_question_enter(q)
      end)
      opts.hooks.leave = opts.hooks.leave or {}
      table.insert(opts.hooks.leave, function()
        require("configs.leetcode_timer").on_leave()
      end)
      return opts
    end,
    config = function(_, opts)
      require("leetcode").setup(opts)
      require("configs.leetcode_stats")
    end,
  },
}
