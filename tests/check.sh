#!/bin/bash
# Run tests/run.lua in a real Neovim TUI inside a private tmux server (its own
# socket, its own scratch state), then print the results.
#   tests/check.sh                  all checks
#   TEST_ONLY="Alt+J" tests/check.sh   checks whose name contains the text
set -u
START=$(date +%s)
HERE=$(cd "$(dirname "$0")" && pwd)
export NVNEXT=${NVNEXT:-/tmp/nvnext}
SOCK=${TMUX_SOCK:-nvnext-test}
PROJ=$NVNEXT/proj
OUT=$NVNEXT/results.txt
rm -f "$NVNEXT/test.sock"; rm -rf "$PROJ" "$OUT" "$NVNEXT/state/nvim/sessions"
mkdir -p "$PROJ"
cat >"$PROJ/a.ml" <<'EOF'
let greeting = "hello"
let count = 3
let () = print_endline greeting
EOF
printf 'val greeting : string\nval count : int\n' >"$PROJ/a.mli"
cat >"$PROJ/b.ml" <<'EOF'
let helper x = x + 1

type point = { x : int; y : int }

let use = helper 41
let origin = { x = 0; y = 0 }
EOF
printf 'let broken : int = "not an int"\n' >"$PROJ/broken.ml"
printf '(lang dune 3.0)\n' >"$PROJ/dune-project"
printf '(executables (names a b broken c fmt))\n' >"$PROJ/dune"
cat >"$PROJ/README.md" <<'EOF'
# Title

Some **bold** text, a [link](https://example.com) and `code`.

<!-- screenshot: full test run, add when all tests are done -->

- item one
EOF
cat >"$PROJ/README.org" <<'EOF'
* Heading
Some *bold* and /italic/ text with a [[https://example.com][link]].
#+BEGIN_SRC ocaml
let x = 1
#+END_SRC
EOF
printf 'print("hello from python")\n' >"$PROJ/hello.py"
printf 'let y = 2\n' >"$PROJ/c.ml"
printf 'let x = 1\n' >"$PROJ/fmt.ml"
mkdir -p "$PROJ/noformat"
printf 'disable = true\n' >"$PROJ/noformat/.ocamlformat"
printf 'let prices = List.map (fun item ->\n    item * 2) [ 1; 2; 3 ]\n' >"$PROJ/noformat/indent_me.ml"
(cd "$PROJ" && git init -q . 2>/dev/null)

# Through the environment, not spliced into the command: a check's name can
# hold a quote.
export TEST_OUT=$OUT TEST_PROJ=$PROJ TEST_ONLY=${TEST_ONLY:-}
tmux -L "$SOCK" kill-server 2>/dev/null
tmux -L "$SOCK" -f /dev/null new-session -d -x 200 -y 50 -c "$PROJ" \
  "$HERE/env.sh nvim --listen $NVNEXT/test.sock --cmd 'let g:neovide = v:true | let g:no_restore = 1' --cmd 'source $HERE/clipboard.vim' -c 'luafile $HERE/run.lua' 2>$NVNEXT/check.err; sleep 2"
for _ in $(seq "${WAIT_TICKS:-600}"); do
  grep -q '^DONE' "$OUT" 2>/dev/null && break
  [ -S "$NVNEXT/test.sock" ] || [ "$(date +%s)" -lt "$((START + 5))" ] || break
  sleep 0.5
done
grep -q '^DONE' "$OUT" 2>/dev/null || tmux -L "$SOCK" capture-pane -p 2>/dev/null | tail -20
tmux -L "$SOCK" kill-server 2>/dev/null
cat "$OUT" 2>/dev/null || echo "no results (nvim crashed or hung)"
echo "pass $(grep -c '^PASS' "$OUT" 2>/dev/null) fail $(grep -c '^FAIL' "$OUT" 2>/dev/null) skip $(grep -c '^SKIP' "$OUT" 2>/dev/null)"
echo "elapsed $(($(date +%s) - START))s"
