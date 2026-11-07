# Neovim + Neovide config

A Neovim + Neovide config for Neovim 0.12: built-ins first, eight plugins,
one surface, the VS Code / Chrome keys on Alt (Linux, Windows) or Cmd (macOS).
It replaced the old lazy.nvim config on 2026-10-25; the old one is the git tag
`old-config-2026-10-25`.

## Install

    git clone <this repo> ~/.config/nvim
    mkdir -p ~/.config/neovide
    ln -sfn ~/.config/nvim/neovide.toml ~/.config/neovide/config.toml        # Linux
    ln -sfn ~/.config/nvim/neovide-macos.toml ~/.config/neovide/config.toml  # macOS

Then plain `nvim` or `neovide`. Neovide reads its startup settings (window
chrome, divider widths) only from `~/.config/neovide/config.toml`, hence the
link. The first start installs the plugins (`vim.pack`, pinned in
`nvim-pack-lock.json`) and the tree-sitter parsers.

One second after each start, `lua/sync.lua` fast-forwards this checkout from
GitHub, unless it has uncommitted or untracked files (then it says so in one
line). Restart to apply a pull.

## Where things are

`init.lua` lists every module and the order they load in. In short:

| File | What it does |
| --- | --- |
| `lua/keys.lua` | every global key, with the rules for adding one |
| `lua/panes.lua` | focus, swap, zoom, flip, divider moves, close, reopen |
| `lua/theme.lua` | all colours, from the Omarchy palette; `:Look glass` / `:Look flat` |
| `lua/gui.lua` | Neovide: font, motion, opacity |
| `lua/dividers.lua` | divider hover (`vim.g.divider_hover = "line"` or `"colour"`) |
| `lua/projects.lua` | `Alt+O` open folder, per-folder sessions, one project per window |
| `lua/lsp.lua`, `lsp/*.lua` | language servers, format on save (ocamlformat for OCaml) |
| `lua/ocaml.lua` | ocp-indent, `.ml`/`.mli` switch, dune |
| `lua/usage.lua` | usage log, `:FrictionNote`, `:UsageReport` |
| `lua/goose.lua` | goose: type pseudocode with plain inserts (dotted underline = draft, one block per place typed), `Alt+K` sends every block or a selection to claude; the answer may also change other lines when asked; the answer is formatted as a save would format it; one `u` undoes |
| `lua/goose_ask.lua` | `Alt+L` asks a question about the line or selection; the answer streams into a "goose answers" pane, nothing in the file changes |
| `lua/seconder.lua`, `rubric/seconder.md` | `Space r` review that writes CR comments; `]r` / `[r` jump between CRs |

## Tests

    tests/check.sh            # every friction rule and key, in a private tmux (all checks)
    tests/sync.sh             # the startup pull, against a throwaway git remote
    tests/startup.sh          # headless startup, median of 9
    tests/open-time.sh FILE   # time to open a file in the TUI
    tests/capture/all.sh      # screenshots in a sealed nested Hyprland

Everything runs in a scratch world under `/tmp/nvnext` (see `tests/env.sh`).
