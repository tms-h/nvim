#!/bin/bash
# Start this config in the private tmux server for poking by hand:
#   tests/live.sh [file]     then tests/q.sh 'expr', tests/live.sh --screen,
#   tests/live.sh --keys '<C-h>', tests/live.sh --stop
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
export NVNEXT=${NVNEXT:-/tmp/nvnext}
SOCK=${TMUX_SOCK:-nvnext-live}
case "${1:-}" in
--screen) exec tmux -L "$SOCK" capture-pane -p ;;
--keys) exec nvim --server "$NVNEXT/test.sock" --remote-send "$2" ;;
--stop) exec tmux -L "$SOCK" kill-server ;;
esac
mkdir -p "$NVNEXT/proj" # the command below sends its errors into $NVNEXT
rm -f "$NVNEXT/test.sock"
tmux -L "$SOCK" kill-server 2>/dev/null
tmux -L "$SOCK" -f /dev/null new-session -d -x "${COLS:-200}" -y "${ROWS:-50}" -c "${CWD:-$NVNEXT/proj}" \
  "$HERE/env.sh nvim --listen $NVNEXT/test.sock --cmd 'let g:neovide = v:true | let g:no_restore = 1' --cmd 'source $HERE/clipboard.vim' ${1:-} 2>$NVNEXT/live.err"
sleep 1.5
