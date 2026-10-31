#!/bin/bash
# A runnable copy of the old config (commit 6ca7883, main before the rebuild)
# in /tmp/nvold, for side-by-side numbers and captures. Its plugins are read
# from ~/.local/share/nvim/lazy through a link; state and cache are scratch,
# the copy has no .git, so its auto-pull cannot run, and no WakaTime plugin,
# so its runs log no coding time. Run commands in it with tests/old-env.sh.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
rm -rf /tmp/nvold
mkdir -p /tmp/nvold/cfg/nvim /tmp/nvold/data/nvim /tmp/nvold/state /tmp/nvold/cache
git -C "$REPO" archive 6ca7883 | tar -x -C /tmp/nvold/cfg/nvim
rm "/tmp/nvold/cfg/nvim/lua/plugins/wakatime.lua"
cp ~/.config/nvim/lua/surface.lua /tmp/nvold/cfg/nvim/lua/ 2>/dev/null || true
ln -s ~/.local/share/nvim/lazy /tmp/nvold/data/nvim/lazy
ln -s ~/.local/share/nvim/site /tmp/nvold/data/nvim/site
