#!/usr/bin/env bash
# Seconder eval with REAL claude calls (one per fixture per mode: 12 fixtures,
# so 12 calls for one mode, 24 for both). Each fixture in fixtures/ is a tiny
# OCaml project with one planted problem a wiki rule targets (manifest.json
# names the rule, the planted lines and keywords), or none (clean_*).
#   tests/seconder/eval.sh            before (base rubric only) and after (+ rubric/wiki-rules.json)
#   tests/seconder/eval.sh after      one mode
# Prints caught / missed plants and false-positive CRs per mode; JSON in $EVAL_DIR.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=${EVAL_DIR:-/tmp/seconder-eval}
mkdir -p "$out"
modes=${1:-before after}
for mode in $modes; do
  tmp=$(mktemp -d)
  EVAL_MODE=$mode EVAL_OUT=$out/$mode.json EVAL_WORK=$tmp/work SECONDER_ROOT=$root \
    XDG_STATE_HOME=$tmp/state XDG_CACHE_HOME=$tmp/cache \
    timeout 1500 nice -n 19 nvim --headless -u NONE -i NONE --cmd "set rtp^=$root" \
    -c "luafile $root/tests/seconder/eval.lua" | tee "$out/$mode.txt"
  rm -rf "$tmp"
done
