-- Double-click selects a word and marks its other occurrences in that pane,
-- like VS Code. The marks are their own soft highlight, not a search: the
-- search pattern, `n`/`N` and the green search hits are left alone, and the
-- marks go away as soon as the selection does.
local M = {}

local api = vim.api
local marked -- { win = id, match = id }

function M.clear()
  if marked and api.nvim_win_is_valid(marked.win) then
    pcall(vim.fn.matchdelete, marked.match, marked.win)
  end
  marked = nil
end

---Select the word under the cursor and mark its occurrences in this pane.
function M.select_word()
  M.clear()
  -- On a space, select the space alone (<cword> would name the next word).
  local char = vim.fn.getline("."):sub(vim.fn.col ".", vim.fn.col ".")
  local word = vim.fn.expand "<cword>"
  if word == "" or char:match "^%s?$" then
    vim.cmd "normal! viw"
    return
  end
  local pattern = "\\V" .. vim.fn.escape(word, "\\")
  if word:match "^[%w_]+$" then
    pattern = "\\V\\<" .. vim.fn.escape(word, "\\") .. "\\>"
  end
  marked = { win = api.nvim_get_current_win(), match = vim.fn.matchadd("WordOccurrence", pattern, -1) }
  vim.cmd "normal! viw"
end

-- The WordOccurrence colour is set with the theme (plugins/ui.lua).
function M.setup()
  local group = api.nvim_create_augroup("WordOccurrences", { clear = true })
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = { "v:*", "V:*", "\22:*" },
    callback = function()
      if not vim.fn.mode():match "^[vV\22]" then
        M.clear()
      end
    end,
  })
  api.nvim_create_autocmd("WinLeave", { group = group, callback = M.clear })
end

return M
