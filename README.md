# nvim

My Neovim config. Lazy-loaded with [lazy.nvim](https://github.com/folke/lazy.nvim), everforest colorscheme, built around LeetCode/competitive programming in C++ and Python.

## Plugins

| Category | Plugins |
|----------|---------|
| **Theme** | everforest |
| **UI** | bufferline, lualine, nvim-tree, noice, nvim-notify, dressing, which-key, alpha (dashboard) |
| **Editor** | treesitter, flash, nvim-autopairs, mini (ai, surround, bufremove, bracketed), todo-comments, trouble |
| **Fuzzy finder** | telescope |
| **LSP** | mason, nvim-lspconfig, nvim-cmp, LuaSnip, fidget |
| **Formatting** | conform (stylua, ruff, clang-format, prettier, shfmt) |
| **Linting** | nvim-lint (luacheck, ruff, cppcheck, shellcheck, eslint_d) |
| **Git** | gitsigns |
| **LeetCode** | leetcode.nvim + custom timer & stats modules |
| **Sessions** | persistence.nvim |

## LeetCode Features

**Timer** (`<leader>ls` for stats) — tracks solve time per problem with live display, logs everything to CSV.

**Stats** (`:LeetStats`) — floating chart with solve time trends, difficulty breakdown, and moving average.

Both hook into [kawre/leetcode.nvim](https://github.com/kawre/leetcode.nvim) automatically.

## Keybindings

Leader is `Space`. A few highlights:

| Key | Action |
|-----|--------|
| `Cmd+P` | Find files |
| `Cmd+Shift+F` | Live grep |
| `Cmd+B` | Toggle file tree |
| `F5` / `Cmd+R` | Run current file (C++/Python) |
| `<leader>ff` | Telescope find files |
| `<leader>fg` | Telescope live grep |
| `<leader>ls` | LeetCode stats |
| `<leader>xx` | Diagnostics |
| `s` / `S` | Flash jump |

## Setup

```sh
git clone https://github.com/tms-h/nvim ~/.config/nvim
nvim  # lazy.nvim installs everything on first launch
```

Needs Neovim >= 0.10. Optionally works with [Neovide](https://neovide.dev) (custom cursor, padding, 120Hz configured).
