#!/bin/bash
# ocamllsp opened in a brand-new dune project, before its first build, must
# drop "No config found" / "Unbound module" once the build has run, with no
# edit and no :LspRestart (lsp.lua restart_after_first_build).
#   tests/lsp-first-build.sh            plain `dune build`
#   WATCH=test FILE=test/test_demo.ml tests/lsp-first-build.sh   `dune test -w`
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OPAM=$HOME/.opam/default/bin
D=$(mktemp -d /tmp/lspfirst.XXXX)
trap 'rm -rf "$D"' EXIT
cd "$D" && PATH=$OPAM:$PATH dune init project demo >/dev/null 2>&1 && cd demo || exit 1
echo 'let greet = "hi"' >lib/demo.ml
echo 'let () = print_endline Demo.greet' >bin/main.ml
echo 'let () = assert (Demo.greet = "hi")' >test/test_demo.ml
unset TMUX
REPRO_OUT=$D/out.txt timeout 120 "$HERE/env.sh" nvim --headless --cmd 'let g:no_restore=1' \
  -c "luafile $HERE/lsp-first-build.lua" 2>/dev/null
cat "$D/out.txt"
if grep -q '^after build, no edit: (none)$' "$D/out.txt"; then echo "pass 1 fail 0"; else echo "pass 0 fail 1"; fi
