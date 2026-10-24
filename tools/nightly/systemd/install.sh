#!/bin/bash
# Copy the nightly units into systemd and start the timer (Linux only; the Mac skips this).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd -P)
mkdir -p ~/.config/systemd/user
for u in nvim-nightly.service nvim-nightly.timer; do cp -f "$HERE/$u" ~/.config/systemd/user/$u; done
systemctl --user daemon-reload
systemctl --user enable --now nvim-nightly.timer
