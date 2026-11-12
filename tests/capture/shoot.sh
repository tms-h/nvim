#!/bin/bash
# shoot.sh WHICH OUTDIR SCENARIO.sh [PROJECT_DIR] [FILE]
# Sealed nested Hyprland (dummy parent: no display, no input, no seat, no DRM,
# private runtime dir) with the live look: current wallpaper (mpvpaper on the
# still image), live blur, border, Omarchy's default window opacity. One
# Neovide runs WHICH config (new = this config via tests/env.sh's scratch
# world; old = the copy from tests/old-copy.sh) in PROJECT_DIR. SCENARIO.sh is
# sourced with R (nvim remote-expr), L (lua through R), SHOT name (grim), WHICH
# and N (this folder).
# OPAQUE=1 gives the flat look (the new config's :Look flat; the old one only
# had opacity 1).
set -u
WHICH=$1 OUT=$2 SCEN=$(readlink -f "$3")
PROJ=${4:-$HOME/Work/interview-prep/ocaml/workshop/03-snake}
FILE=${5:-lib/game.ml}
N=$(dirname "$(readlink -f "$0")")
mkdir -p "$OUT"
BIN=$HOME/.cache/lyrics-blur/iso/dummy-parent
WALL=$(readlink -f "$HOME/.local/state/omarchy/current/background")
RT=/run/user/$(id -u)/nvnest.$$
mkdir -p "$RT"
chmod 700 "$RT"
PIDS=""
# Every process in the nest, found by its private XDG_RUNTIME_DIR, not by
# parent: pkill -P missed children reparented to systemd once their parent
# died, and an mpvpaper ran on for hours. Read per thread, because
# /proc/PID/environ is unreadable once the main thread has exited while
# others still run (how mpvpaper is left after SIGTERM).
nest() { grep -lsxzF "XDG_RUNTIME_DIR=$RT" /proc/[0-9]*/task/[0-9]*/environ | cut -d/ -f3 | sort -u; }
cleanup() {
  # SIGKILL, not SIGTERM: mpvpaper's SIGTERM handler hangs on NVIDIA (see
  # ~/.local/bin/live-wallpaper). The wait keeps bash's "Killed" line quiet.
  [ -n "${MPV:-}" ] && { kill -9 "$MPV"; wait "$MPV"; } 2>/dev/null
  P=$(nest)
  [ -n "$P" ] && kill $P 2>/dev/null && sleep 0.5
  for _ in 1 2 3 4 5; do
    P=$(nest)
    [ -z "$P" ] && break
    kill -9 $P 2>/dev/null
    sleep 0.2
  done
  rm -rf "$RT"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
base() { env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$RT" LANG=C.UTF-8 "$@"; }
base nice -n 19 "$BIN" parent >"$OUT/dummy.log" 2>&1 &
PIDS="$PIDS $!"
echo "nest pids:$PIDS" >"$OUT/pids.txt"
sleep 0.3
base WAYLAND_DISPLAY=parent LIBSEAT_BACKEND=seatd SEATD_SOCK=/nonexistent/seatd.sock \
  AQ_DRM_DEVICES=/nonexistent/card HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_SD_VARS=1 \
  HYPRLAND_NO_CRASHREPORTER=1 HYPRLAND_NO_RT=1 \
  nice -n 19 Hyprland --config "$N/hypr.conf" >"$OUT/hypr.log" 2>&1 &
PIDS="$PIDS $!"
echo "nest pids:$PIDS" >"$OUT/pids.txt"
for _ in $(seq 40); do [ -S "$RT/wayland-1" ] && break; sleep 0.2; done
[ -S "$RT/wayland-1" ] || { echo "inner Hyprland did not start"; exit 1; }
SIG=$(ls "$RT/hypr" | head -1)
inner() { base WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE="$SIG" "$@"; }
inner nice -n 19 mpvpaper -o "no-audio image-display-duration=inf load-scripts=no" ALL "$WALL" >"$OUT/mpvpaper.log" 2>&1 &
MPV=$!
PIDS="$PIDS $MPV"
sleep 1.5
SOCK=$RT/nv.sock
cd "$PROJ" || exit 1
if [ "$WHICH" = new ]; then
  S=${NVNEXT:-/tmp/nvnext}
  mkdir -p "$S/cfg"
  ln -sfn "$(cd "$N/../.." && pwd -P)" "$S/cfg/nvim"
  ENVS=(XDG_CONFIG_HOME=$S/cfg XDG_DATA_HOME=$S/data XDG_STATE_HOME=$OUT/state XDG_CACHE_HOME=$S/cache
    NVIM_NO_CONFIG_PULL=1 WAKATIME_HOME=$S/wakatime NEOVIDE_CONFIG=$S/cfg/nvim/neovide.toml)
else
  S=/tmp/nvold
  ENVS=(XDG_CONFIG_HOME=$S/cfg XDG_DATA_HOME=$S/data XDG_STATE_HOME=$OUT/state XDG_CACHE_HOME=$S/cache)
fi
mkdir -p "$OUT/state"
inner "${ENVS[@]}" PATH="$PATH" nice -n 19 neovide --no-fork "$FILE" -- --listen "$SOCK" \
  --cmd 'let g:no_restore = 1' ${EXTRA:-} >"$OUT/neovide.log" 2>&1 &
PIDS="$PIDS $!"
echo "nest pids:$PIDS" >"$OUT/pids.txt"
for _ in $(seq 60); do [ -S "$SOCK" ] && break; sleep 0.25; done
[ -S "$SOCK" ] || { echo "neovide did not start (see $OUT/neovide.log)"; exit 1; }
sleep 3
R() { nvim --server "$SOCK" --remote-expr "$1"; }
L() { R "luaeval('$1')"; }
SHOT() {
  inner hyprctl dismissnotify >/dev/null 2>&1
  sleep 0.2
  inner grim "$OUT/$1.png"
}
# The file goes before "--" so Neovide opens it (after "--" it stays hidden
# behind [No Name], even with --clean). The :edit is a no-op safety net.
[ -z "${NOEDIT:-}" ] && R "execute('edit $FILE')" >/dev/null
sleep 1
if [ -n "${OPAQUE:-}" ]; then
  if [ "$WHICH" = new ]; then
    R "execute('Look flat')" >/dev/null
  else
    R "execute('let g:neovide_opacity = 1.0 | let g:neovide_normal_opacity = 1.0')" >/dev/null
  fi
  sleep 0.5
fi
. "$SCEN"
