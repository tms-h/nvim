# Nightly Neovim config pass (unattended)

You are the nightly job for Thomas's Neovim/Neovide config (this repo, shared with his Mac). Nobody is
watching and nobody will answer: never ask questions, never wait. When a note is unclear, make the best
call, do it, and flag it in the result file. Run every build, test and capture under `nice -n 19`, one
test run at a time.

Read first: `~/Work/.claude/skills/neovim-config-repo/SKILL.md` (the repo's rules: keybinds, one surface,
dividers and hover, pane sizes, focus cue, test method) and `AGENTS.md`. They override anything below.

## Hard rules
- Work only in your cwd (the worktree, on its branch). Commit there; never push, merge, switch branch or
  touch `main` or the live checkout (`~/.config/nvim`). This script does the merge after re-running tests.
- Never edit `tools/nightly/` (this job). Leave no uncommitted or untracked files: the startup auto-pull
  (`lua/sync.lua`) refuses to run on a dirty repo. Backups and scratch go in /tmp, never in the repo.
- Never touch the live Neovide or the desktop: no keys (wtype, hyprctl dispatch, ydotool), no clipboard,
  no `nvim --server` to a live socket. Test only with `tests/check.sh` (private tmux nvim, scratch state,
  private clipboard) and `tests/env.sh nvim --headless ...`.
- Never remove a feature or change a keybind unless a friction note asks for it. A complaint about how
  something looks is not an order to remove it: Thomas once wrote "hovering over the bars have weird
  effects" and an agent removed divider hover, then he wrote "NO I MEAN THE HOVER EFFECTS ARE GONE I MISS
  HOVER". Fix the look, keep the feature. Do not switch the focus cue default (pending his pick).
- A new key copies the VS Code/Chrome shortcut, Alt on Linux and Cmd on Mac via `require("util").chord`,
  and does the same thing in every mode (normal, insert, visual, terminal).

## Part 1: friction notes (listed under "Tonight", oldest first, numbered N1..)
Each line is `- <date time>  [<file:line where he was>] <his words>`. Fix every one, in order.
- One commit per note (`Fix friction N<k>: <plain-English summary>`), each with a check in
  `tests/run.lua` that fails without the fix and passes with it. Prove it: run the check against the
  unfixed code (e.g. `git stash` the fix, or check out `HEAD~1` of the file), see it fail, then pass.
  Run single checks with `TEST_ONLY="<name>" tests/check.sh`.
- Two notes about the same thing (e.g. "looks off" and "should be centered") may share one fix and
  commit; list both ids.
- Look changes (colours, layout, borders, popups): take before and after shots in the sealed nested
  Hyprland with `tests/capture/shoot.sh` (read its header; `new` = the config of the repo the script
  lives in, so run main's copy at the live checkout path for "before" and your worktree's copy for
  "after"). Never use a hidden monitor on the live desktop. Judge both looks (glass and `OPAQUE=1` flat).
  Save the PNGs under `~/.local/state/nvim/nightly/shots/<date>/` and name them in the result.
- A note already fixed on main (someone fixed it by hand since): confirm it with a check (add one if
  missing), list it under `fixed` with that commit, and move on.
- If a fix needs something only Thomas can confirm (a real key on his keyboard, the Mac), do the fix
  anyway and flag what he should try.

## Part 2: cleanup of tonight's area
Review the files of tonight's cleanup area (listed under "Tonight") for dead code, duplication,
stale or wrong comments, and needless complexity; fix what you find with behaviour unchanged.
- No new features, no keybind changes, no look changes. If you find a real bug, fix it only if it is
  small and you add a failing-then-passing check; otherwise flag it.
- Small coherent commits (`Cleanup <file>: <what>`). Skip the area rather than make a risky change.
- Run `tests/check.sh` (all checks) at the end; every check must pass, or nothing merges. Fix what you
  broke. A check that also fails on the untouched base, or only in the full run (order-dependent or
  timing), is a broken check: fix its root cause in its own commit (`Fix check: ...`) and say so in
  `notes`. Never delete a check or loosen what it proves to get a pass.

## Result file (required, last step)
Write JSON to the result path under "Tonight":
```
{"fixed":   [{"id": "N1", "summary": "<=12 plain words", "commit": "<short sha>", "check": "<check name>", "shots": "<dir or empty>"}],
 "flagged": [{"id": "N3", "why": "<=20 plain words: the call you made, or what Thomas should try>"}],
 "cleaned": ["<=10 plain words per cleanup commit"],
 "notes":   "anything else for Thomas, one line, or empty"}
```
A note fixed with a judgement call goes in both `fixed` and `flagged`. A note you could not fix at all
goes only in `flagged`, with why. Plain everyday English, no jargon. Then reply with the same content.
