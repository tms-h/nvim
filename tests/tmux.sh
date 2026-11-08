#!/bin/bash
# Neovim inside tmux is a plain editor (util.in_tmux): no tab or terminal keys
# but Ctrl+Tab, a tab bar only with 2+ files, no sessions, no background of
# its own. Runs `nvim .` the way tmux-agent does, in a private tmux server,
# without g:neovide, and reads the state back over its socket. A second run
# with g:neovide set proves Neovide keeps everything.
#   tests/tmux.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# The same scratch world as check.sh (plugins already installed there).
export NVNEXT=${NVNEXT:-/tmp/nvnext}
SOCK=${TMUX_SOCK:-nvtmux-test}
PROJ=$NVNEXT/tmuxproj
rm -rf "$PROJ" "$NVNEXT/state/nvim/sessions" "$NVNEXT/state/nvim/open-projects"
mkdir -p "$PROJ" "$NVNEXT/state/nvim/open-projects"
printf 'let x = 1\n' >"$PROJ/a.ml"
(cd "$PROJ" && git init -q .)
# Another window (a live pid: this shell) already has the folder open, as
# Neovide would. Inside tmux that must not stop `nvim .`.
printf '%s\n' "$(cd "$PROJ" && pwd -P)" >"$NVNEXT/state/nvim/open-projects/$$"

pass=0 fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
    pass=$((pass + 1))
  else
    echo "FAIL $1: want '$2', got '$3'"
    fail=$((fail + 1))
  fi
}

run() { # extra --cmd, label
  local sock=$NVNEXT/n.sock
  rm -f "$sock"
  tmux -L "$SOCK" kill-server 2>/dev/null
  tmux -L "$SOCK" -f /dev/null new-session -d -x 160 -y 40 -c "$PROJ" \
    "$HERE/env.sh nvim --listen $sock --cmd '$1' --cmd 'source $HERE/clipboard.vim' . ; sleep 1"
  # Ctrl+Tab reaches Neovim as itself only with extended keys (tmux.conf).
  tmux -L "$SOCK" set -g extended-keys always
  q() { nvim --clean --headless --server "$sock" --remote-expr "$1" 2>/dev/null; }
  for _ in $(seq 120); do [ -S "$sock" ] && [ "$(q 'v:vim_did_enter')" = 1 ] && break; sleep 0.25; done
  sleep 5
  if [ "$2" = tmux ]; then
    check "tmux: in_tmux set" true "$(q 'luaeval("tostring(require(\"util\").in_tmux)")')"
    check "tmux: no tab bar with one file" 0 "$(q '&showtabline')"
    for key in '<A-t>' '<A-T>' '<A-1>' '<C-PageDown>' '<A-CR>' '<C-`>'; do
      check "tmux: $key not mapped" "" "$(q "get(maparg('$key', 'n', 0, 1), 'desc', '') =~# 'tab\\|terminal' ? 'mapped' : ''")"
    done
    check "tmux: Normal has no background" nil "$(q 'luaeval("tostring(vim.api.nvim_get_hl(0, {name=\"Normal\"}).bg)")')"
    check "tmux: tree opened beside the folder" 1 "$(q "luaeval('#vim.tbl_filter(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype == \"NvimTree\" end, vim.api.nvim_list_wins())')")"
    pid=$(q 'getpid()')
    check "tmux: not counted as open" no "$( [ -e "$NVNEXT/state/nvim/open-projects/$pid" ] && echo yes || echo no)"
    # Two files: the bar shows and Ctrl+Tab cycles them; back to one, it hides.
    printf 'let y = 2\n' >"$PROJ/b.ml"
    q 'execute("edit a.ml | edit b.ml")' >/dev/null
    sleep 0.3
    check "tmux: tab bar with two files" 2 "$(q '&showtabline')"
    tmux -L "$SOCK" send-keys -t 0 C-Tab
    sleep 0.5
    check "tmux: Ctrl+Tab cycles files" a.ml "$(q 'bufname()')"
    q 'execute("bwipeout b.ml")' >/dev/null
    sleep 0.3
    check "tmux: tab bar hides at one file" 0 "$(q '&showtabline')"
    # Alt+W on the last window closes the file, never Neovim.
    q 'execute("edit a.ml")' >/dev/null
    q 'execute("wincmd l")' >/dev/null
    q 'execute("lua require(\"explorer\").toggle()")' >/dev/null
    tmux -L "$SOCK" send-keys -t 0 M-w
    sleep 1
    check "tmux: Alt+W on the last window keeps Neovim" 1 "$( [ -S "$sock" ] && q '1')"
    check "tmux: Alt+W closed the file" "" "$(q 'bufname()')"
    # One file left (none, after Alt+W): Ctrl+Tab hands back to tmux's next tab.
    tmux -L "$SOCK" new-window -d
    tmux -L "$SOCK" send-keys -t 0 C-Tab
    sleep 0.5
    check "tmux: Ctrl+Tab with one file goes to the next tmux tab" 1 "$(tmux -L "$SOCK" display -p '#{window_index}')"
    tmux -L "$SOCK" select-window -t 0
    # Alt+Shift+Left at Neovim's edge (the tree counts) swaps the whole tmux pane.
    nv=$(tmux -L "$SOCK" display -p -t :0.0 '#{pane_id}')
    tmux -L "$SOCK" split-window -h -b -d -t "$nv"
    q 'execute("wincmd l")' >/dev/null
    tmux -L "$SOCK" send-keys -t "$nv" M-S-Left
    sleep 0.5
    check "tmux: Alt+Shift+Left at the edge swaps the tmux pane, focus follows" 0,1 "$(tmux -L "$SOCK" display -p -t "$nv" '#{pane_left},#{pane_active}')"
    q 'execute("qa!")' >/dev/null
    sleep 1
    check "tmux: no session saved" 0 "$(ls "$NVNEXT/state/nvim/sessions" 2>/dev/null | wc -l)"
  else
    check "neovide: in_mux unset" false "$(q 'luaeval("tostring(require(\"util\").in_mux)")')"
    check "neovide: tab bar shows" 2 "$(q '&showtabline')"
    check "neovide: Alt+T mapped" 1 "$(q "get(maparg('<A-t>', 'n', 0, 1), 'desc', '') ==# 'New tab' ? 1 : 0")"
    check "neovide: Ctrl+backtick mapped" 1 "$(q "get(maparg('<C-\`>', 'n', 0, 1), 'desc', '') =~# 'panel' ? 1 : 0")"
    check "neovide: Normal keeps its background" 1 "$(q 'luaeval("vim.api.nvim_get_hl(0, {name=\"Normal\"}).bg ~= nil and 1 or 0")')"
    q 'execute("qa!")' >/dev/null
  fi
  tmux -L "$SOCK" kill-server 2>/dev/null
}

run 'let g:tmux_test = 1' tmux
run 'let g:neovide = v:true' neovide
echo "pass $pass fail $fail"
