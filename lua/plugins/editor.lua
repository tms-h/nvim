return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "c",
        "cpp",
        "python",
        "lua",
        "javascript",
        "typescript",
        "html",
        "css",
        "json",
        "markdown",
        "markdown_inline",
        "vim",
        "vimdoc",
        "ocaml",
        "ocaml_interface",
      }

      local treesitter = require "nvim-treesitter"
      treesitter.setup()
      treesitter.install(parsers)

      local filetypes = {
        "c",
        "cpp",
        "python",
        "lua",
        "javascript",
        "javascriptreact",
        "typescript",
        "typescriptreact",
        "html",
        "css",
        "json",
        "jsonc",
        "markdown",
        "vim",
        "help",
        "ocaml",
        "ocamlinterface",
      }
      local group = vim.api.nvim_create_augroup("TreesitterFeatures", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = filetypes,
        callback = function()
          if not pcall(vim.treesitter.start) then
            return
          end
          vim.wo.foldmethod = "expr"
          vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })

      -- Re-entered headers may retain their filetype without an active highlighter.
      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        pattern = { "*.h", "*.hh", "*.hpp", "*.hxx" },
        callback = function(args)
          local filetype = vim.bo[args.buf].filetype
          if filetype ~= "c" and filetype ~= "cpp" then
            return
          end
          if not pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].syntax = filetype
          end
        end,
      })
    end,
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local autopairs = require "nvim-autopairs"
      autopairs.setup()

      -- OCaml uses a leading apostrophe for type variables, e.g. ['a].
      -- Keep pairing characters generally, but do not insert a second
      -- apostrophe in implementation or interface buffers.
      for _, rule in ipairs(autopairs.get_rules "'") do
        rule.not_filetypes = { "ocaml", "ocamlinterface" }
      end
    end,
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash jump",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash treesitter",
      },
    },
  },

  {
    "echasnovski/mini.nvim",
    version = false,
    event = "VeryLazy",
    config = function()
      require("mini.ai").setup()
      require("mini.surround").setup()
      require("mini.bufremove").setup()
      require("mini.bracketed").setup()
    end,
  },

  {
    "folke/todo-comments.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = {},
  },

  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },

  {
    "windwp/nvim-ts-autotag",
    ft = { "html", "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "xml", "markdown" },
    opts = {},
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {},
  },

  {
    "junegunn/vim-easy-align",
    cmd = "EasyAlign",
    keys = {
      { "ga", "<Plug>(EasyAlign)", mode = { "n", "x" }, desc = "EasyAlign" },
    },
  },
}
