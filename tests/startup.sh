#!/bin/bash
# Startup time, median of N headless runs (ms), for the new config or, with
# OLD=1, the old config: a copy in /tmp/nvold (made by tests/old-copy.sh; it
# has no .git, so its auto-pull cannot run).
#   tests/startup.sh [FILE]     time to open FILE (default: empty start)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
N=${N:-9}
FILE=${1:-}
OUT=$(mktemp -d)
for i in $(seq "$N"); do
  if [ -n "${OLD:-}" ]; then
    XDG_CONFIG_HOME=/tmp/nvold/cfg XDG_DATA_HOME=/tmp/nvold/data XDG_STATE_HOME=/tmp/nvold/state \
      XDG_CACHE_HOME=/tmp/nvold/cache nice -n 19 nvim --headless --startuptime "$OUT/$i.log" ${FILE:+"$FILE"} +'qa!' >/dev/null 2>&1
  else
    "$HERE/env.sh" nvim --headless --startuptime "$OUT/$i.log" ${FILE:+"$FILE"} +'qa!' >/dev/null 2>&1
  fi
done
for i in $(seq "$N"); do grep "NVIM STARTED" "$OUT/$i.log" | tail -1 | awk '{print $1}'; done | sort -n |
  awk '{a[NR]=$1} END {printf "median %.1f ms  (min %.1f, max %.1f, n=%d)\n", a[int((NR+1)/2)], a[1], a[NR], NR}'
[ -n "${SHOW:-}" ] && sort -k2 -n -r "$OUT/$N.log" | head -25
rm -rf "$OUT"
