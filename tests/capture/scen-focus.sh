# Sourced by shoot.sh (R, SHOT, WHICH, OUT). Tree + game.ml + side terminal,
# editor focused, one shot per focus cue (focus.lua M.CUES).
L() { R "luaeval('$1')"; }
L '(function() require("explorer").toggle(); vim.cmd("wincmd p"); require("panes").new_terminal(); return 1 end)()' >/dev/null
sleep 2
L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do local b = vim.api.nvim_win_get_buf(w) if vim.bo[b].buftype == "terminal" then vim.fn.chansend(vim.b[b].terminal_job_id, "dune build 2>&1 | head -5; ls lib\n") end end return 1 end)()' >/dev/null
sleep 2
L '(function() vim.cmd("stopinsert") for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "ocaml" then vim.api.nvim_set_current_win(w) end end vim.api.nvim_win_set_cursor(0, {14, 4}) return 1 end)()' >/dev/null
sleep 1
for cue in ${CUES:-dim light divider title number}; do
  R "execute('FocusCue $cue')" >/dev/null
  sleep 1
  SHOT "focus-$cue"
done
# The default cue with focus in the tree, then in the terminal, then a crowded
# layout (the .mli stacked under the .ml).
if [ -n "${FOCUS_TOUR:-}" ]; then
  R "execute('FocusCue title')" >/dev/null
  L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "NvimTree" then vim.api.nvim_set_current_win(w) end end return 1 end)()' >/dev/null
  sleep 0.8; SHOT focus-title-tree
  L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "terminal" then vim.api.nvim_set_current_win(w) end end vim.cmd("stopinsert") return 1 end)()' >/dev/null
  sleep 0.8; SHOT focus-title-terminal
  L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "ocaml" then vim.api.nvim_set_current_win(w) end end vim.cmd("belowright split lib/game.mli") return 1 end)()' >/dev/null
  sleep 1; SHOT focus-title-crowded
fi
if [ -n "${FOCUS_TOUR:-}" ]; then
  # Pointer on the line between game.ml and game.mli: it must light.
  HR=$(L '(function() for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.fn.bufname(vim.api.nvim_win_get_buf(w)):match("game.ml$") then return vim.api.nvim_win_get_position(w)[1] + vim.api.nvim_win_get_height(w) end end return 0 end)()')
  HC=$(L '(function() return vim.api.nvim_win_get_position(0)[2] + 10 end)()')
  R "nvim_input_mouse('move','','',0,$HR,$HC)" >/dev/null
  sleep 0.8; SHOT focus-title-hover
  R "string(getmousepos())" >"$OUT/hover.txt"; echo "HR=$HR HC=$HC" >>"$OUT/hover.txt"; L "vim.inspect(vim.tbl_map(function(w) return {w, vim.api.nvim_win_get_position(w), vim.api.nvim_win_get_height(w), vim.wo[w].fillchars} end, vim.api.nvim_list_wins()))" >>"$OUT/hover.txt"
fi
