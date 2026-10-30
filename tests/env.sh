#!/bin/bash
# Run the new config in a scratch world: its own config link, data, state and
# cache under $NVNEXT (default /tmp/nvnext), under the default app name
# (no NVIM_APPNAME). Never touches ~/.local/*/nvim, never pulls from GitHub.
#   tests/env.sh nvim --headless ...      any command, with the env set
set -eu
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
export NVNEXT=${NVNEXT:-/tmp/nvnext}
mkdir -p "$NVNEXT"/{cfg,data,state,cache}
ln -sfn "$HERE" "$NVNEXT/cfg/nvim"
export XDG_CONFIG_HOME=$NVNEXT/cfg XDG_DATA_HOME=$NVNEXT/data XDG_STATE_HOME=$NVNEXT/state XDG_CACHE_HOME=$NVNEXT/cache
unset NVIM_APPNAME
export NVIM_NO_CONFIG_PULL=1
# No way to the real WakaTime: tests would log fake coding time, and its state
# file in the real home fails every buffer switch on a full disk.
export WAKATIME_HOME=$NVNEXT/wakatime
# No way to the desktop: no clipboard, no windows (tests/clipboard.vim gives
# check.sh and live.sh a private clipboard instead).
unset WAYLAND_DISPLAY DISPLAY
exec nice -n 19 "$@"
