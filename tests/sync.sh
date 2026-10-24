#!/bin/bash
# The startup pull (lua/sync.lua) against a throwaway git remote: a clean
# checkout fast-forwards; one with an untracked file is left alone.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
git -C "$T/seed" commit -q --allow-empty -m one && git -C "$T/seed" push -q origin main
mkdir -p "$T/cfg" && git clone -q "$T/origin.git" "$T/cfg/nvim"
git -C "$T/seed" commit -q --allow-empty -m two && git -C "$T/seed" push -q origin main
NEW=$(git -C "$T/seed" rev-parse HEAD)

pull() { # run M.pull in the scratch config, print what it said
  env -u NVIM_APPNAME XDG_CONFIG_HOME=$T/cfg XDG_STATE_HOME=$T/state XDG_DATA_HOME=$T/data \
    nice -n 19 nvim --headless -u NONE --cmd "set rtp^=$HERE" \
    -c 'lua vim.notify = function(m) io.stdout:write(m, "\n") end' \
    -c 'lua require("sync").pull()' -c 'lua vim.wait(5000, function() return false end)' -c 'qa!' 2>&1
}
fail=0
check() { if [ "$2" = yes ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

touch "$T/cfg/nvim/stray.bak"
out=$(pull)
[ "$(git -C "$T/cfg/nvim" rev-parse HEAD)" != "$NEW" ] && [[ $out == *"untracked"* ]] && r=yes || r=no
check "an untracked file stops the pull, with one line saying so" $r

rm "$T/cfg/nvim/stray.bak"
out=$(pull)
[ "$(git -C "$T/cfg/nvim" rev-parse HEAD)" = "$NEW" ] && [[ $out == *"restart"* ]] && r=yes || r=no
check "a clean checkout fast-forwards and asks for a restart" $r
exit $fail
