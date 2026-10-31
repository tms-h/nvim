# Sourced by shoot.sh (R, SHOT, WHICH, OUT). OCaml file + tree + side terminal,
# then the divider hover, then a markdown file ($MDFILE, default the README
# tests/check.sh makes).
. "$N/scen-layout.sh"
L 'vim.inspect(vim.tbl_map(function(w) local b = vim.api.nvim_win_get_buf(w) return { w, vim.fn.bufname(b), vim.bo[b].filetype, vim.api.nvim_buf_line_count(b), vim.api.nvim_win_get_config(w).relative } end, vim.api.nvim_list_wins()))' >"$OUT/windows.txt"
R 'execute("messages")' >"$OUT/messages.txt"
SHOT 1-ocaml-tree-terminal

# Where the dividers are.
VC=$(L '(function() local w = vim.api.nvim_get_current_win() return vim.api.nvim_win_get_position(w)[2] + vim.api.nvim_win_get_width(w) end)()')
hover() { R "nvim_input_mouse('move','','',0,$1,$2)" >/dev/null; }
hover 10 "$VC"
sleep 0.8
SHOT 2-hover-editor-terminal
hover 10 $((VC - 30))
sleep 0.5

# Stack the .mli under the .ml: now the editor panes have a bottom edge too.
R "execute('belowright split lib/game.mli')" >/dev/null
sleep 1
R "execute('wincmd k')" >/dev/null
sleep 0.5
VC=$(L '(function() local w = vim.api.nvim_get_current_win() return vim.api.nvim_win_get_position(w)[2] + vim.api.nvim_win_get_width(w) end)()')
HR=$(L '(function() local w = vim.api.nvim_get_current_win() return vim.api.nvim_win_get_position(w)[1] + vim.api.nvim_win_get_height(w) end)()')
HC=$(L '(function() local w = vim.api.nvim_get_current_win() return vim.api.nvim_win_get_position(w)[2] + 10 end)()')
if [ "$WHICH" = new ]; then
  for style in line colour; do
    R "execute('let g:divider_hover = \"$style\"')" >/dev/null
    hover 10 $((VC - 30)); sleep 0.4
    hover 6 "$VC"; sleep 0.8
    SHOT "3-hover-vertical-stacked-$style"
    hover "$HR" "$HC"; sleep 0.8
    SHOT "4-hover-horizontal-$style"
  done
  R "execute('let g:divider_hover = \"line\"')" >/dev/null
else
  hover 6 "$VC"; sleep 0.8
  SHOT 3-hover-vertical-stacked
  hover "$HR" "$HC"; sleep 0.8
  SHOT 4-hover-horizontal
fi
hover 6 $((VC - 30))
sleep 0.4

# A markdown file with an HTML comment, a link, a code block.
R "execute('only | edit ${MDFILE:-${NVNEXT:-/tmp/nvnext}/proj/README.md}')" >/dev/null
if [ "$WHICH" = new ]; then
  L '(function() require("explorer").toggle(); vim.cmd("wincmd p") return 1 end)()' >/dev/null
else
  R "execute('NvimTreeToggle')" >/dev/null
  sleep 1
  R "execute('wincmd p')" >/dev/null
fi
sleep 1.5
R "execute('call cursor(1, 1)')" >/dev/null
sleep 0.8
SHOT 5-markdown
