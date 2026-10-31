# Sourced by the scenarios: tree on the left, terminal with some output on the
# right of the file, editor focused in Normal mode, cursor inside a function.
if [ "$WHICH" = new ]; then
  L '(function() require("explorer").toggle(); vim.cmd("wincmd p"); require("panes").new_terminal(); return 1 end)()' >/dev/null
else
  # Lazy-loaded command: anything after "|" would become its argument.
  R "execute('NvimTreeToggle')" >/dev/null
  sleep 1
  R "execute('wincmd p | vsplit | terminal')" >/dev/null
fi
sleep 2
L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do local b = vim.api.nvim_win_get_buf(w) if vim.bo[b].buftype == "terminal" then vim.fn.chansend(vim.b[b].terminal_job_id, "dune build 2>&1 | head -5; ls lib\n") end end return 1 end)()' >/dev/null
sleep 2
L '(function() vim.cmd("stopinsert") for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "ocaml" then vim.api.nvim_set_current_win(w) end end vim.api.nvim_win_set_cursor(0, {14, 4}) return 1 end)()' >/dev/null
sleep 1.2
