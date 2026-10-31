#!/bin/bash
# Run a command in the old config copy's world (/tmp/nvold, tests/old-copy.sh),
# as tests/env.sh does for this config.
#   tests/old-env.sh nvim --headless ...
exec env XDG_CONFIG_HOME=/tmp/nvold/cfg XDG_DATA_HOME=/tmp/nvold/data XDG_STATE_HOME=/tmp/nvold/state \
  XDG_CACHE_HOME=/tmp/nvold/cache nice -n 19 "$@"
