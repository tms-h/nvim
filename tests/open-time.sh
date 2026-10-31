#!/bin/bash
# Time to open FILE to the first screen in a real TUI (private tmux), median
# of N runs, from --startuptime's "NVIM STARTED" line. OLD=1 times the old
# config copy in /tmp/nvold (tests/old-copy.sh).
#   tests/open-time.sh ~/Work/cambridge-battlecode/sdk/ocaml/cambc.ml
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
FILE=$1
N=${N:-7}
OUT=$(mktemp -d)
SOCK=${TMUX_SOCK:-nvnext-time}
RUN=$HERE/env.sh
[ -n "${OLD:-}" ] && RUN=$HERE/old-env.sh
for i in $(seq "$N"); do
  tmux -L "$SOCK" -f /dev/null new-session -d -x 200 -y 50 -c "$(dirname "$FILE")" \
    "$RUN nvim --startuptime $OUT/$i.log $FILE"
  sleep "${SETTLE:-3}"
  tmux -L "$SOCK" kill-server 2>/dev/null
  sleep 0.3
done
for i in $(seq "$N"); do grep "NVIM STARTED" "$OUT/$i.log" | tail -1 | awk '{print $1}'; done | sort -n |
  awk '{a[NR]=$1} END {printf "median %.1f ms  (min %.1f, max %.1f, n=%d)\n", a[int((NR+1)/2)], a[1], a[NR], NR}'
[ -n "${SHOW:-}" ] && sort -k2 -n -r "$OUT/$N.log" | head -25
rm -rf "$OUT"
