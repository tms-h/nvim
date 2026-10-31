#!/bin/bash
# Startup time, median of N headless runs (ms), for the new config or, with
# OLD=1, the old config copy in /tmp/nvold (tests/old-copy.sh).
#   tests/startup.sh [FILE]     time to open FILE (default: empty start)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
N=${N:-9}
FILE=${1:-}
OUT=$(mktemp -d)
RUN=$HERE/env.sh
[ -n "${OLD:-}" ] && RUN=$HERE/old-env.sh
for i in $(seq "$N"); do
  "$RUN" nvim --headless --startuptime "$OUT/$i.log" ${FILE:+"$FILE"} +'qa!' >/dev/null 2>&1
done
for i in $(seq "$N"); do grep "NVIM STARTED" "$OUT/$i.log" | tail -1 | awk '{print $1}'; done | sort -n |
  awk '{a[NR]=$1} END {printf "median %.1f ms  (min %.1f, max %.1f, n=%d)\n", a[int((NR+1)/2)], a[1], a[NR], NR}'
[ -n "${SHOW:-}" ] && sort -k2 -n -r "$OUT/$N.log" | head -25
rm -rf "$OUT"
