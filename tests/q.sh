#!/bin/bash
# Ask the running test Neovim (tests/check.sh) for an expression's value.
#   tests/q.sh 'mode(1)'
exec nvim --server "${NVNEXT:-/tmp/nvnext}/test.sock" --remote-expr "$1"
