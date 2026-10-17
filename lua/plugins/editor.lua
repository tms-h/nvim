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
    -- `;` is command mode; repeat f/t by pressing f/t again instead.
    opts = { modes = { char = { keys = { "f", "F", "t", "T", "," } } } },
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
      -- Default s-prefixed mappings make Flash's `s` wait for timeoutlen and
      -- steal jumps whose first character is a, d, r, f, h or n.
      require("mini.surround").setup {
        mappings = {
          add = "gsa",
          delete = "gsd",
          find = "gsf",
          find_left = "gsF",
          highlight = "gsh",
          replace = "gsr",
          update_n_lines = "gsn",
        },
      }
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
    opts = {
      -- Render in every mode; only the cursor line shows raw markdown.
      render_modes = true,
      heading = {
        sign = false,
        width = "block",
        left_pad = 1,
        right_pad = 2,
        border = true,
        border_virtual = true,
      },
      code = {
        sign = false,
        width = "block",
        left_pad = 1,
        right_pad = 2,
        border = "thin",
      },
      pipe_table = { preset = "round", cell = "trimmed" },
      latex = { enabled = false },
      checkbox = { checked = { scope_highlight = "@markup.strikethrough" } },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)
      -- Prose reads better soft-wrapped at word boundaries, but wrapped
      -- tables render as garbage (neovim conceal + wrap limitation), so files
      -- with a pipe table stay unwrapped and scroll sideways instead.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("MarkdownReading", { clear = true }),
        pattern = "markdown",
        callback = function(args)
          local has_table = false
          for _, line in ipairs(vim.api.nvim_buf_get_lines(args.buf, 0, 2000, false)) do
            if line:match "^%s*|.*|%s*$" then
              has_table = true
              break
            end
          end
          vim.opt_local.wrap = not has_table
          vim.opt_local.linebreak = true
          vim.opt_local.breakindent = true
        end,
      })
    end,
  },

  {
    "junegunn/vim-easy-align",
    cmd = "EasyAlign",
    keys = {
      { "ga", "<Plug>(EasyAlign)", mode = { "n", "x" }, desc = "EasyAlign" },
    },
  },
}
