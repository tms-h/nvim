#!/usr/bin/env bash
# Goose headless tests: session (stub claude), the one-shot path, and the
# memory server.
# Scratch state/cache, no network, no desktop keys.
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0
for t in session oneshot reach esc memory; do
  mkdir -p "$tmp/$t"
  (cd "$tmp/$t" && GOOSE_TEST_DIR="$tmp/$t" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
    timeout 120 nice -n 19 nvim --headless -u NONE -i NONE --cmd "set rtp^=$root" -c "luafile $root/tests/goose/$t.lua" 2>&1) || status=1
done
exit $status
