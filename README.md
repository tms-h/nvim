# nvim

My Neovim config. Lazy-loaded with [lazy.nvim](https://github.com/folke/lazy.nvim), everforest colorscheme, built around LeetCode/competitive programming in C++ and Python.

## Plugins

| Category | Plugins |
|----------|---------|
| **Theme** | everforest |
| **UI** | bufferline, lualine, nvim-tree, noice, nvim-notify, dressing, which-key, alpha (dashboard) |
| **Editor** | treesitter, flash, nvim-autopairs, mini (ai, surround, bufremove, bracketed), Oil, vim-easy-align, todo-comments, trouble |
| **Fuzzy finder** | telescope + fzf-native |
| **LSP** | mason, mason-tool-installer, nvim-lspconfig, blink.cmp, fidget |
| **Formatting** | conform (stylua, ruff, clang-format, prettier, shfmt) |
| **Linting** | nvim-lint (selene, ruff, cppcheck, shellcheck, eslint_d) |
| **Git** | gitsigns |
| **Search/replace** | grug-far.nvim |
| **Competitive** | competitest.nvim (+ blink.cmp) |
| **LeetCode** | leetcode.nvim + custom timer & stats modules |
| **Sessions** | persistence.nvim |
| **Activity** | WakaTime |
| **OCaml** | ocamllsp, ocamlformat (Jane Street profile), ocp-indent, Dune |

## LeetCode Features

**Timer** (`<leader>ls` for stats) — tracks solve time per problem with live display, logs everything to CSV.

**Stats** (`:LeetStats`) — floating chart with solve time trends, difficulty breakdown, and moving average.

Both hook into [kawre/leetcode.nvim](https://github.com/kawre/leetcode.nvim) automatically.

## Cross-platform setup

The same `main` branch runs on macOS and Windows. Platform differences are selected at
runtime, so shared behavior cannot drift between long-lived branches.

`lua/util/modifier.lua` maps VS Code-style shortcuts to **Cmd** on macOS and **Ctrl** on
Windows. `lua/configs/runner.lua` handles executable and path differences for C, C++,
and Python. Neovide-specific settings remain shared, with Mac-only options guarded by
an OS check. Leader is `Space`.

## Keybindings

### VS Code-style shortcuts

| Action | Mac | Windows |
|--------|-----|---------|
| Undo | `Cmd+Z` | `Ctrl+Z` |
| Redo | `Cmd+Shift+Z` | `Ctrl+Shift+Z` |
| Find files | `Cmd+P` | `Ctrl+P` |
| Command palette | `Cmd+Shift+P` | `Ctrl+Shift+P` |
| Search in project (grep) | `Cmd+Shift+F` | `Ctrl+Shift+F` |
| Close tab/buffer | `Cmd+W` | `Ctrl+W` |
| New tab/file | `Cmd+T` | `Ctrl+T` |
| Next tab | `Cmd+Shift+]` | `Ctrl+Shift+]` |
| Previous tab | `Cmd+Shift+[` | `Ctrl+Shift+[` |
| Go to tab 1–9 | `Cmd+1`…`Cmd+9` | `Ctrl+1`…`Ctrl+9` |
| Toggle file tree | `Cmd+B` | `Ctrl+B` |

**Neovide only:** paste `Cmd+V` / `Ctrl+V`, zoom in `Cmd+=` / `Ctrl+=`, zoom out `Cmd+-` / `Ctrl+-`.
Draggable split dividers brighten slightly when hovered. Keyboard buffer shortcuts land
on terminals in Terminal-Normal mode; clicking a terminal returns it to input mode.

On macOS, [`neovide.toml`](./neovide.toml) uses a transparent, titleless native strip. The
real traffic-light controls remain functional and the window stays movable/resizable;
zero outer padding removes the extra inset around the Neovim grid.

### Motions & windows (same on both)

| Key | Action |
|-----|--------|
| `;` | Enter command mode (`:`) |
| `jk` | Escape (insert mode) |
| `Esc` | Clear search highlight |
| `s` / `S` | Flash jump |
| `Shift+H` / `Shift+L` | Previous / next buffer |
| `Ctrl+H/J/K/L` | Move between windows |
| `Ctrl+Arrow` | Resize the current split |
| `Alt+J` / `Alt+K` | Move line down / up (normal, insert, visual) |
| `<` / `>` (visual) | Indent, keep selection |

### Leader — find & files

| Key | Action |
|-----|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fh` | Help tags |
| `<leader>ft` | Todos (Telescope) |
| `<leader>e` | Toggle file explorer |
| `-` | Edit the parent directory with Oil |
| `<leader>n` | New file |
| `<leader>c` | Close buffer |
| `<leader>q` | Quit window |

Oil and nvim-tree have **Name** and **Recently added** sort controls. Oil also provides
a **More…** menu for modification-time and file-size sorting.

### Leader — terminal, LSP & diagnostics

| Key | Action |
|-----|--------|
| `<leader>th` / `<leader>tv` | Terminal (bottom / side split) |
| `q` (in run pane) | Close terminal/run pane |
| `gd` / `gD` | Go to definition / declaration |
| `gr` / `gi` | References / implementation |
| `K` | Hover docs |
| `<leader>rn` | Rename symbol |
| `<leader>ca` | Code action |
| `<leader>d` | Line diagnostics (float) |
| `<leader>xx` / `<leader>xb` | Diagnostics list / buffer diagnostics (Trouble) |
| `<leader>ll` | Run linter |
| `<leader>ls` | LeetCode stats |

### Project search and replace

| Key | Action |
|-----|--------|
| `<leader>sr` | Project search and replace |

### Leader — sessions & todo

| Key | Action |
|-----|--------|
| `<leader>qs` | Restore session |
| `<leader>ql` | Restore last session |
| `<leader>qd` | Stop session recording |
| `<leader>td` | Open todo list (floating `todo.md`) |
| `<leader>tw` | Toggle the corner todo widget |
| `<CR>` (in todo) | Toggle checkbox |
| `o` (in todo) | New checklist item |
| `q` (in todo) | Close todo |

### Competitive programming

C/C++ and Python buffers get extra buffer-local mappings. In `c`/`cpp` buffers the
CompetiTest `<leader>e` mapping shadows the global file-explorer mapping.

| Key | Action | Filetypes |
|-----|--------|-----------|
| `F5` | Compile & run current file | `c`, `cpp`, `python` |
| `Cmd+R` / `Ctrl+R` | Compile & run (Neovide only) | `c`, `cpp`, `python` |
| `<leader>r` | CompetiTest: run testcases | `c`, `cpp` |
| `<leader>a` | CompetiTest: add testcase | `c`, `cpp` |
| `<leader>e` | CompetiTest: edit testcase | `c`, `cpp` |

Also driven by commands: `:CompetiTest receive problem`, `:CompetiTest receive contest`,
`:CompetiTest run`. C++ compiles with `g++ -std=c++20` (`-Wall -Wextra
-fsanitize=address,undefined` under CompetiTest); template at `~/cp/templates/template.cpp`.

### OCaml / Jane Street workflow

OCaml buffers use `ocp-indent` while typing, so top-level `let` stays at column zero.
`:w` runs `ocamlformat`, using project `.ocamlformat` settings when present and the
`janestreet` profile otherwise. `ocamllsp` supplies diagnostics, completion, navigation,
and `.ml`/`.mli` switching.

| Key | Action |
|-----|--------|
| `<leader>of` | Format with ocamlformat |
| `<leader>oi` | Switch between `.ml` and `.mli` |
| `<leader>ob` | `dune build` |
| `<leader>ot` | `dune runtest` |
| `<leader>ow` | `dune build --watch` |
| `<leader>op` | `dune promote` |

Install the tools in each opam switch used for development:

```sh
opam install dune ocaml-lsp-server ocamlformat ocp-indent
```

For a Jane Street-formatted project, commit this `.ocamlformat` file:

```text
profile=janestreet
```

## Setup

```sh
# macOS
git clone https://github.com/tms-h/nvim ~/.config/nvim

# Windows (PowerShell)
git clone https://github.com/tms-h/nvim $env:LOCALAPPDATA\nvim
```

Open `nvim` and lazy.nvim installs everything on first launch. Needs Neovim >= 0.12,
`ripgrep`, `fd`, `make`, and a C compiler. Optionally works with
[Neovide](https://neovide.dev) (custom cursor, padding, 120Hz configured).

If an existing Windows checkout still uses the old `windows` branch, migrate it once:

```powershell
git fetch origin
git switch main
git pull --ff-only
```
