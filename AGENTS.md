# Neovim configuration guidelines

- Keep one cross-platform configuration on `main`; do not create permanent OS-specific branches.
- Put shared behavior and keybindings in the existing shared modules.
- Build Cmd/Alt GUI chords with `require("util.modifier").chord(...)` so macOS uses Cmd and Linux/Windows use Alt (Ctrl collides with core Vim keys).
- Detect macOS with `vim.fn.has("macunix")` and Windows with `vim.fn.has("win32")`.
- Treat `vim.g.neovide` as a GUI check, not an operating-system check.
- Keep executable discovery and path differences behind small utility modules such as `lua/configs/runner.lua`.
- Preserve these matching actions on both platforms: file tree, find, command palette, tabs, paste, zoom, and code runner.
- Keep machine-only paths or preferences out of tracked shared files unless they have a safe runtime fallback.
- Preserve the OCaml workflow: ocp-indent while typing, ocamlformat with project settings or the Jane Street fallback profile, ocamllsp, and Dune commands.
- Run Lua formatting and a headless Neovim startup check after configuration changes when those tools are available.
