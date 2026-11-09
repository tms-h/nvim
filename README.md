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
| `lua/goose_ask.lua` | `Alt+L` opens a popup chat box about the line or selection: type at `›`, Enter asks, the answer streams in; its claude runs in the project root and reads other files itself (Read, Grep, Glob); Esc, Esc closes; nothing in the file changes. A message starting `/mentor` gets the mentor-check verdict instead (prompt from `~/.claude/skills/mentor-check/prompt.md`, its own claude, logged to `stdpath('state')/mentor/log.jsonl`) |
| `lua/seconder.lua`, `rubric/seconder.md`, `rubric/wiki-rules.json` | `Space r` review that writes CR comments, using the rubric, the js-wiki's review rules for the file's language (each CR a rule drove ends with `(wiki: page)`) and `~/Work/js-intern-notes/review-checklist.md`; `]r` / `[r` jump between CRs; a CR-soon may show a fix in grey that only `Alt+.` (Cmd+.) applies, one `u` undoes; every add, fix, pushback and reopen goes to `stdpath('state')/seconder/log.jsonl`; `tests/seconder/eval.sh` scores it on planted bugs (real calls) |

## Asking an AI about this config

`tools/lookup/lookup.py` answers from the config itself, so it can't drift from what this machine has checked
out: a headless Neovim loads the checkout (as Neovide and as a terminal Neovim in tmux, scratch state, no pull) and
reports every key with what it does, the `file:line` that set it and how often you've pressed it.

    python3 tools/lookup/lookup.py keys zoom        # by what it does, or by key: alt+f, "<C-k>", "space o"
    python3 tools/lookup/lookup.py where "divider hover"   # module headers, Lua blocks, :commands, plugins
    python3 tools/lookup/lookup.py check            # exit 1 if a key this config sets has no desc

As MCP tools (`keys`, `where`) for omp and Claude Code, once per machine:

    claude mcp add -s user nvimcfg -- python3 ~/.config/nvim/tools/lookup/lookup.py mcp
    # omp: add the same command as "nvimcfg" under mcpServers in ~/.omp/agent/mcp.json

## Tests

    tests/check.sh            # every friction rule and key, in a private tmux (all checks)
    tests/sync.sh             # the startup pull, against a throwaway git remote
    tests/startup.sh          # headless startup, median of 9
    tests/open-time.sh FILE   # time to open a file in the TUI
    tests/capture/all.sh      # screenshots in a sealed nested Hyprland

Everything runs in a scratch world under `/tmp/nvnext` (see `tests/env.sh`).
