local M = {}

M.is_macos = vim.fn.has "macunix" == 1
M.is_windows = vim.fn.has "win32" == 1
-- Cmd on macOS. Elsewhere Ctrl would shadow core Vim keys (<C-w> windows,
-- <C-b>/<C-d> scrolling, <C-t> tags, <C-v> block select), so Alt.
M.key = M.is_macos and "D" or "A"

---A primary-modifier chord: <D-p> on macOS, <A-p> elsewhere.
---@param sequence string
---@return string
function M.chord(sequence)
  return "<" .. M.key .. "-" .. sequence .. ">"
end

---Show the n-th listed buffer (tab) in this pane; -1 is the last one.
function M.go_to_tab(n)
  require("tabs").go_to(n)
end

return M
