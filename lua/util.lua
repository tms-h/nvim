local M = {}

-- Which system this is: the one place the config asks.
M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
-- Neovim in a terminal inside tmux: a plain editor. tmux owns tabs,
-- terminals and the session (~/.config/tmux/tmux.conf), so the tab bar, the
-- terminal keys and per-folder sessions are off. Neovide started from a tmux
-- shell inherits $TMUX, so it is checked too: Neovide never changes.
M.in_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= "" and not vim.g.neovide
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
