#!/bin/bash
# How many global keys a config adds on top of stock Neovim, as Neovide sees
# them (g:neovide set), counted once per key whatever its modes; <Nop>
# fillers left out. OLD=1 counts the old config copy in /tmp/nvold
# (tests/old-copy.sh).
#   tests/keymap-count.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
TMP=$(mktemp -d)
LUA='local out, nop = {}, {}
for _, m in ipairs { "n", "i", "x", "s", "o", "t", "c" } do
  for _, k in ipairs(vim.api.nvim_get_keymap(m)) do
    local d, rhs = k.desc or "", k.rhs or ""
    if (rhs == "" and not k.callback) or rhs:upper() == "<NOP>" or d == "<Nop>" or d:match "^Stray" then
      nop[k.lhs] = true
    else
      out[k.lhs .. "\t" .. (k.callback and "fn" or rhs)] = true
    end
  end
end
local f = io.open(vim.env.OUT, "w")
for id in pairs(out) do f:write(id, "\n") end
f:close()
io.open(vim.env.OUT .. ".nop", "w"):write(vim.tbl_count(nop) .. "\n")'
run() { OUT=$1 "${@:2}" --headless --cmd 'let g:neovide = v:true | let g:no_restore = 1' +"lua $LUA" +'qa!' >/dev/null 2>&1; sort -o "$1" "$1"; }
run "$TMP/stock" nice -n 19 nvim --clean
if [ -n "${OLD:-}" ]; then
  run "$TMP/cfg" env XDG_CONFIG_HOME=/tmp/nvold/cfg XDG_DATA_HOME=/tmp/nvold/data \
    XDG_STATE_HOME=/tmp/nvold/state XDG_CACHE_HOME=/tmp/nvold/cache nice -n 19 nvim
else
  run "$TMP/cfg" "$HERE/env.sh" nvim
fi
# A key counts if the config added it or changed what it does.
added=$(comm -13 "$TMP/stock" "$TMP/cfg" | cut -f1 | sort -u | wc -l)
echo "keys added or changed: $added  (no-op fillers: $(cat "$TMP/cfg.nop"))"
rm -rf "$TMP"
