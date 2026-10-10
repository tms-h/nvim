# nvim

My Neovim config. Lazy-loaded with [lazy.nvim](https://github.com/folke/lazy.nvim), everforest colorscheme, built around LeetCode/competitive programming in C++ and Python.

## Plugins

| Category | Plugins |
|----------|---------|
| **Theme** | everforest |
| **UI** | bufferline, lualine, nvim-tree, noice, nvim-notify, dressing, which-key, alpha (dashboard) |
| **Editor** | treesitter, flash, nvim-autopairs, mini (ai, surround, bufremove, bracketed), Oil, vim-easy-align, todo-comments, trouble |
| **Fuzzy finder** | telescope + fzf-native |
| **LSP** | mason, mason-tool-installer, nvim-lspconfig, blink.cmp, LuaSnip, friendly-snippets, fidget |
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

### Multicursor and faster editing

Start in Normal mode (`Esc`). Press `Space m` and pause to see the multicursor menu.

| Keys | Action |
|------|--------|
| `Space m n` | Add the next occurrence of the word or visual selection |
| `Space m s` | Skip the next occurrence |
| `Space m a` | Add all occurrences in this buffer |
| `Space m j` / `Space m k` | Add a cursor below / above |
| `Space m x` | Clear extra cursors |
| `Space m r` | Restore the previous cursors |
| `Cmd+D` (Mac) / `Ctrl+D` (Windows) | Add next occurrence in Neovide, Normal or Visual mode |
| `Cmd+click` (Mac) / `Ctrl+click` (Windows) | Add or remove a cursor in Neovide, Normal mode |
| `Space f k` | Search all keyboard shortcuts |

Try this in a scratch buffer: put `apple + apple + apple` on a line, place the
cursor on the first `apple`, then press `Space m n` twice. Type `ciw`, type
`pear`, and press `Esc`. All three words change together. Press `Esc` again to
clear the extra cursors. `u` undoes the edit. To target a phrase, select it with
`v` first, add matches, then use `c` to replace the selections.

For several lines with different lengths, add cursors with `Space m j`, then
press `A` to append to every line. Press `Esc` twice when finished.

Other useful approaches already installed:

- **Jump by sight:** press `s`, type a few characters of a visible target, then
  its displayed label. This uses Flash to avoid repeated arrow presses.
- **Edit a whole unit:** `ciw` changes a word, `ci"` changes text inside quotes,
  and `ci(` changes text inside parentheses. Type the replacement, then `Esc`.
- **Repeat an edit:** after `ciwpear<Esc>`, move to another word and press `.`.
- **Wrap text:** on a word, `saiw)` wraps it in parentheses. `sd)` removes the
  surrounding parentheses. These are mini.surround mappings.
- **Rename a code symbol:** `Space r n` asks the language server to rename its
  references. Use this for a variable or function; multicursor matches text.
- **Discover shortcuts:** `Space f k` searches their descriptions. `Space o s`
  browses the OCaml snippets in an OCaml buffer.

Multicursor is supplied by [multicursor.nvim](https://github.com/jake-stewart/multicursor.nvim).
Its full reference is available with `:help multicursor`.

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
Automatic startup restores the latest real project session, excluding config and temporary
QA sessions; config-only buffers are also removed from restored project buffer lists.

On macOS, [`neovide.toml`](./neovide.toml) uses a transparent, titleless native strip. The
real traffic-light controls remain functional and the window stays movable/resizable;
zero outer padding removes the extra inset around the Neovim grid. Double-clicking that
strip performs macOS Zoom; use the green traffic light or `Ctrl+Cmd+F` for native
fullscreen. Split borders use Neovide's native box renderer so junctions stay aligned.

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

Typing `mod_board ` at the start of a line expands to a `module Board = struct`
block and places the cursor inside it. Underscored names become PascalCase, so
`mod_game_board ` creates `GameBoard`. Blink also offers the friendly-snippets
OCaml templates for `module`, `struct`, `sig`, `match`, `type`, `let`, and `val`.
Custom named snippets also include `rec_name `, `test_name `, `expect_name `,
`record_name `, and `orerror_name `. Type any prefix ending in `_` to see its
description in Blink. Press Enter to accept a completion and Tab or Shift-Tab to
move through its fields. Use `<leader>os` to browse every snippet available in an
OCaml buffer.

| Key | Action |
|-----|--------|
| `<leader>of` | Format with ocamlformat |
| `<leader>oi` | Switch between `.ml` and `.mli` |
| `<leader>os` | Show available OCaml snippets |
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
