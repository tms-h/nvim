#!/bin/bash
# The tree's git look (explorer.lua, Git status), in the sealed nested Neovide:
#   tests/capture/scen-tree-git.sh prep DIR    a repo with every git state in DIR
#   tests/capture/shoot.sh new OUT tests/capture/scen-tree-git.sh DIR edited.ml
# Shot 1: every state, edited.ml open. Shot 2: DIR-init, a folder shown before
# its `git init`; shot 3: the same after git init + git add -N, nothing pressed.
if [ "${1:-}" = prep ]; then
  set -eu
  D=$2
  rm -rf "$D" "$D-init"
  mkdir -p "$D" "$D-init/lib"
  g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -C "$D" "$@" >/dev/null 2>&1; }
  for f in edited.ml staged_edit.ml old.ml both.ml clean.ml gone/x.ml gone/y.ml work/w.ml; do
    mkdir -p "$D/$(dirname $f)"
    echo "let x = 1" >"$D/$f"
  done
  g init
  g add .
  g commit -m one
  g checkout -b other && echo "let x = 2" >"$D/both.ml" && g commit -am other
  g checkout main && echo "let x = 3" >"$D/both.ml" && g commit -am main
  g merge other || true
  echo "let x = 2" >"$D/edited.ml"
  echo "let x = 2" >"$D/staged_edit.ml" && g add staged_edit.ml
  g mv old.ml renamed.ml
  echo new >"$D/untracked.ml"
  echo new >"$D/intent.ml" && g add -N intent.ml
  echo new >"$D/staged_new.ml" && g add staged_new.ml
  rm "$D/gone/x.ml"
  echo "let x = 2" >"$D/work/w.ml"
  echo "let x = 1" >"$D-init/main.ml"
  echo "let y = 2" >"$D-init/lib/event.ml"
  exit 0
fi
DIR=$PWD
L '(function() require("explorer").show() return 1 end)()' >/dev/null
sleep 2
SHOT 1-git-states
R "execute('cd $DIR-init | edit main.ml')" >/dev/null
L '(function() require("explorer").show() return 1 end)()' >/dev/null
sleep 2
SHOT 2-before-git-init
git -C "$DIR-init" init -q && git -C "$DIR-init" add -N .
sleep 2.5
SHOT 3-after-git-init
