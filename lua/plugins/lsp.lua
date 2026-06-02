return {
  {
    "mason-org/mason.nvim",
    lazy = false,
    priority = 100,
    opts = { PATH = "prepend" },
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local ok, blink = pcall(require, "blink.cmp")
      if ok then
        capabilities = blink.get_lsp_capabilities(capabilities)
      end

      vim.lsp.config("*", { capabilities = capabilities })
      vim.lsp.enable({ "html", "cssls", "clangd", "pyright", "ts_ls", "lua_ls" })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local m = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          m("n", "gd", vim.lsp.buf.definition, "Go to definition")
          m("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
          m("n", "gr", vim.lsp.buf.references, "References")
          m("n", "gi", vim.lsp.buf.implementation, "Implementation")
          m("n", "K", vim.lsp.buf.hover, "Hover")
          m("n", "<leader>rn", vim.lsp.buf.rename, "Rename")
          m("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
          m("n", "<leader>d", vim.diagnostic.open_float, "Line diagnostics")
          m("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, "Previous diagnostic")
          m("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic")
        end,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    opts = {
      keymap = { preset = "enter" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    lazy = false,
    config = function()
      local by_ft = { lua = { "stylua" } }
      if vim.fn.executable("ruff") == 1 then
        by_ft.python = { "ruff_format" }
      end
      if vim.fn.executable("clang-format") == 1 then
        by_ft.c = { "clang_format" }
        by_ft.cpp = { "clang_format" }
      end
      if vim.fn.executable("prettier") == 1 then
        for _, ft in ipairs({
          "javascript", "javascriptreact", "typescript", "typescriptreact",
          "json", "jsonc", "yaml", "markdown", "css", "html",
        }) do
          by_ft[ft] = { "prettier" }
        end
      end
      if vim.fn.executable("shfmt") == 1 then
        for _, ft in ipairs({ "sh", "bash", "zsh" }) do
          by_ft[ft] = { "shfmt" }
        end
      end

      require("conform").setup({
        formatters_by_ft = by_ft,
        formatters = {
          clang_format = {
            prepend_args = {
              "--style",
              "{BasedOnStyle: LLVM, IndentWidth: 2, TabWidth: 2, UseTab: Never, ColumnLimit: 120, DerivePointerAlignment: false, PointerAlignment: Left, ReferenceAlignment: Left}",
            },
          },
        },
        format_on_save = function(bufnr)
          local ft = vim.bo[bufnr].filetype
          if ft == "c" or ft == "cpp" then
            return {
              timeout_ms = 4000,
              stop_after_first = true,
              lsp_format = vim.fn.executable("clang-format") == 1 and "never" or "prefer",
            }
          end
          return { timeout_ms = 1200, lsp_format = "prefer" }
        end,
      })
    end,
  },

  {
    "mfussenegger/nvim-lint",
    lazy = false,
    config = function()
      local lint = require("lint")
      local by_ft = {}
      local function add(ft, name, exe)
        if vim.fn.executable(exe or name) == 1 then
          by_ft[ft] = { name }
        end
      end
      add("lua", "luacheck")
      add("python", "ruff")
      add("c", "cppcheck")
      add("cpp", "cppcheck")
      add("sh", "shellcheck")
      add("bash", "shellcheck")
      add("zsh", "shellcheck")
      add("yaml", "yamllint")
      add("json", "jsonlint")
      add("dockerfile", "hadolint")
      add("javascript", "eslint_d")
      add("javascriptreact", "eslint_d")
      add("typescript", "eslint_d")
      add("typescriptreact", "eslint_d")
      lint.linters_by_ft = by_ft
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
        callback = function() lint.try_lint() end,
      })
    end,
  },

  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {},
  },
}
