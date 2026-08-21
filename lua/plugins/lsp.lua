return {
  {
    "mason-org/mason.nvim",
    lazy = false,
    priority = 100,
    dependencies = { "WhoIsSethDaniel/mason-tool-installer.nvim" },
    config = function()
      require("mason").setup { PATH = "prepend" }
      require("mason-tool-installer").setup {
        ensure_installed = {
          "clangd",
          "clang-format",
          "pyright",
          "ruff",
          "typescript-language-server",
          "eslint_d",
          "lua-language-server",
          "selene",
          "html-lsp",
          "css-lsp",
          "shellcheck",
          "yamllint",
          "jsonlint",
          "hadolint",
          "stylua",
          "prettier",
          "shfmt",
          "tree-sitter-cli",
        },
        auto_update = false,
        run_on_start = true,
        start_delay = 1000,
        debounce_hours = 24,
      }
    end,
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

      -- Keep diagnostics visible and responsive while editing, closer to the
      -- Monaco/CoderPad experience.
      vim.diagnostic.config {
        virtual_text = { spacing = 2, source = "if_many" },
        signs = true,
        underline = true,
        update_in_insert = true,
        severity_sort = true,
        float = { border = "rounded", source = true },
      }

      local competitive_headers = { "bits/stdcpp.h", "bits/stdc++.h" }
      local function is_missing_competitive_include(diagnostic)
        local message = diagnostic.message or ""
        if not message:find("not found", 1, true) then
          return false
        end
        for _, header in ipairs(competitive_headers) do
          if message:find(header, 1, true) then
            return true
          end
        end
        return false
      end

      local function filter_competitive_include_diagnostics(diagnostics)
        return vim.tbl_filter(function(diagnostic)
          return not is_missing_competitive_include(diagnostic)
        end, diagnostics or {})
      end

      local publish_diagnostics = vim.lsp.handlers["textDocument/publishDiagnostics"]
      vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
        if result and result.diagnostics then
          result = vim.deepcopy(result)
          result.diagnostics = filter_competitive_include_diagnostics(result.diagnostics)
        end
        return publish_diagnostics(err, result, ctx, config)
      end

      -- Let clangd query the compiler selected by the cross-platform runner so
      -- it can discover the matching standard-library include paths.
      local clangd_cmd = {
        "clangd",
        "--header-insertion=never",
        "--background-index",
      }
      local cpp_compiler = require("configs.runner").find_cpp_compiler()
      if cpp_compiler then
        table.insert(clangd_cmd, 2, "--query-driver=" .. cpp_compiler)
      end
      vim.lsp.config("clangd", {
        cmd = clangd_cmd,
      })

      local servers = { "html", "cssls", "clangd", "pyright", "ts_ls", "lua_ls" }
      local ocamllsp = require("configs.ocaml").find_tool "ocamllsp"
      if ocamllsp then
        vim.lsp.config("ocamllsp", { cmd = { ocamllsp } })
        servers[#servers + 1] = "ocamllsp"
      end
      vim.lsp.enable(servers)

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
          m("n", "[d", function()
            vim.diagnostic.jump { count = -1 }
          end, "Previous diagnostic")
          m("n", "]d", function()
            vim.diagnostic.jump { count = 1 }
          end, "Next diagnostic")
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
      local ocamlformat = require("configs.ocaml").find_tool "ocamlformat"
      if ocamlformat then
        by_ft.ocaml = { "ocamlformat" }
      end
      if vim.fn.executable "ruff" == 1 then
        by_ft.python = { "ruff_format" }
      end
      if vim.fn.executable "clang-format" == 1 then
        by_ft.c = { "clang_format" }
        by_ft.cpp = { "clang_format" }
      end
      if vim.fn.executable "prettier" == 1 then
        for _, ft in ipairs {
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "json",
          "jsonc",
          "yaml",
          "markdown",
          "css",
          "html",
        } do
          by_ft[ft] = { "prettier" }
        end
      end
      if vim.fn.executable "shfmt" == 1 then
        for _, ft in ipairs { "sh", "bash", "zsh" } do
          by_ft[ft] = { "shfmt" }
        end
      end

      require("conform").setup {
        formatters_by_ft = by_ft,
        formatters = {
          ocamlformat = {
            command = ocamlformat or "ocamlformat",
            prepend_args = function(_, ctx)
              local project_config = vim.fs.find(".ocamlformat", { path = ctx.dirname, upward = true })[1]
              return project_config and {} or { "--profile=janestreet", "--enable-outside-detected-project" }
            end,
          },
          clang_format = {
            prepend_args = {
              "--style",
              "{BasedOnStyle: LLVM, IndentWidth: 2, TabWidth: 2, UseTab: Never, ColumnLimit: 100, BreakBeforeBinaryOperators: NonAssignment, AllowShortFunctionsOnASingleLine: None, DerivePointerAlignment: false, PointerAlignment: Left, ReferenceAlignment: Left, AlwaysBreakTemplateDeclarations: Yes, AlignConsecutiveDeclarations: true, AlignConsecutiveAssignments: true}",
            },
          },
        },
        format_on_save = function(bufnr)
          local ft = vim.bo[bufnr].filetype
          if ft == "ocaml" then
            return nil
          end
          if ft == "c" or ft == "cpp" then
            return {
              timeout_ms = 4000,
              stop_after_first = true,
              lsp_format = vim.fn.executable "clang-format" == 1 and "never" or "prefer",
            }
          end
          return { timeout_ms = 1200, lsp_format = "prefer" }
        end,
      }

      vim.keymap.set({ "n", "v" }, "<leader>=", function()
        require("conform").format { async = true, lsp_format = "fallback" }
      end, { desc = "Format buffer" })
    end,
  },

  {
    "mfussenegger/nvim-lint",
    lazy = false,
    config = function()
      local lint = require "lint"
      local selene = lint.linters.selene
      selene.args = {
        "--config",
        vim.fn.stdpath "config" .. "/selene.toml",
        "--display-style",
        "json",
        "-",
      }

      local cppcheck = lint.linters.cppcheck
      local cppcheck_parser = cppcheck.parser
      cppcheck.parser = function(output, bufnr, linter_cwd)
        local diagnostics = cppcheck_parser(output, bufnr, linter_cwd)
        return vim.tbl_filter(function(diagnostic)
          local message = diagnostic.message or ""
          return not (
            message:find("not found", 1, true)
            and (message:find("bits/stdcpp.h", 1, true) or message:find("bits/stdc++.h", 1, true))
          )
        end, diagnostics or {})
      end

      local by_ft = {}
      local function add(filetype, linter, executable)
        if vim.fn.executable(executable or linter) == 1 then
          by_ft[filetype] = { linter }
        end
      end
      add("lua", "selene")
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

      local lint_group = vim.api.nvim_create_augroup("lint", { clear = true })
      local function try_lint(args)
        if not vim.api.nvim_buf_is_valid(args.buf) or vim.bo[args.buf].buftype ~= "" then
          return
        end
        vim.api.nvim_buf_call(args.buf, function()
          lint.try_lint()
        end)
      end

      -- Run every linter when opening/saving a file. Fast linters also refresh
      -- after leaving insert mode; clangd already provides live C/C++ errors,
      -- so avoid repeatedly starting the heavier cppcheck process while typing.
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = lint_group,
        callback = try_lint,
      })
      vim.api.nvim_create_autocmd("InsertLeave", {
        group = lint_group,
        callback = function(args)
          local ft = vim.bo[args.buf].filetype
          if ft ~= "c" and ft ~= "cpp" then
            try_lint(args)
          end
        end,
      })
    end,
  },

  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {},
  },
}
