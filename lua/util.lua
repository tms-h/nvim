local M = {}

-- Which system this is: the one place the config asks.
M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
-- Neovim in a terminal inside tmux or herdr (in_mux): a plain editor. The
-- multiplexer owns tabs, terminals and the session (~/.config/tmux/tmux.conf,
-- ~/.config/herdr/config.toml), so the terminal and tab keys and per-folder
-- sessions are off, and the file tab bar shows only while 2+ files are open.
-- in_tmux and in_herdr only read the environment, which a Neovide started
-- from a tmux or herdr shell inherits: gate on in_mux, never true in Neovide.
M.in_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
M.in_herdr = vim.env.HERDR_ENV == "1" and not M.in_tmux
M.in_mux = (M.in_tmux or M.in_herdr) and not vim.g.neovide
-- Cmd on macOS. Elsewhere Ctrl would shadow core Vim keys (<C-w> windows,
-- <C-b>/<C-d> scrolling, <C-t> tags, <C-v> block select), so Alt.
local key = M.is_macos and "D" or "A"

---A primary-modifier chord: <D-p> on macOS, <A-p> elsewhere.
---@param sequence string
---@return string
function M.chord(sequence)
  return "<" .. key .. "-" .. sequence .. ">"
end

return M
