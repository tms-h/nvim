#!/bin/bash
# Capture old and new, glass and flat, one nest at a time, into $1
# (default /tmp/nvnext/cap); ONLY=old for one side. Needs tests/old-copy.sh run once for "old".
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
OUT=${1:-/tmp/nvnext/cap}
export MDFILE=${MDFILE:-/tmp/nvnext/sample/README.md}
for which in ${ONLY:-new old}; do
  for look in glass flat; do
    dir=$OUT/$which-$look
    rm -rf "$dir"
    if [ "$look" = flat ]; then
      OPAQUE=1 timeout 150 "$HERE/shoot.sh" "$which" "$dir" "$HERE/scen-main.sh" >"$dir.log" 2>&1
    else
      timeout 150 "$HERE/shoot.sh" "$which" "$dir" "$HERE/scen-main.sh" >"$dir.log" 2>&1
    fi
    echo "$which-$look: $(ls "$dir"/*.png 2>/dev/null | wc -l) shots"
  done
done
