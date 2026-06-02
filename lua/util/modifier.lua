-- VS Code-style GUI bindings: Super/Cmd on macOS, Ctrl on Windows/Linux.
local M = {}

M.key = vim.fn.has("mac") == 1 and "D" or "C"

--- Build a key chord like <C-p> or <D-S-z>.
function M.chord(seq)
  return "<" .. M.key .. "-" .. seq .. ">"
end

return M
