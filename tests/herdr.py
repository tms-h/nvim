#!/usr/bin/env python3
"""Neovim inside herdr, driven by kitty's key bytes in a throwaway session.

  python3 tests/herdr.py                 all checks
  HERDR_KEYS=/path/to/herdr-keys python3 tests/herdr.py   another herdr-keys

A private `herdr --session` with a copy of ~/.config/herdr/config.toml whose
commands go through a guard: it refuses the live socket, then runs herdr-keys
with scratch state. Neovim runs in the scratch world of tests/env.sh ($NVNEXT,
default /tmp/nvnext, plugins installed by check.sh). Never touches the live
herdr, kitty or desktop.

Checks:
  * Alt+Enter beside Neovim then Alt+W puts the agent view's 60/40 back
    exactly (it was 50/50, seen after a zoom: "50/50 after unfullscreen",
    2026-11-08), and Neovim's view (first line on screen) comes back too.
  * Alt+F zoom and unzoom from Neovim keeps the herdr ratios and the view.
  * Alt+= / Alt+- / Alt+Shift+= / Alt+Shift+- resize a Neovim split, the
    herdr pane when Neovim has no split that way, and a plain shell pane.
"""
import json, os, pty, select, signal, struct, subprocess, sys, tempfile, threading, time, fcntl, termios

HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.realpath(os.path.expanduser("~/.config/herdr/herdr.sock"))
KEYS = os.environ.get("HERDR_KEYS", os.path.expanduser("~/.local/bin/herdr-keys"))
NVNEXT = os.environ.get("NVNEXT", "/tmp/nvnext")
NAME = f"nvt{os.getpid()}"
TMP = tempfile.mkdtemp(prefix="nvh", dir="/tmp")
SOCK = os.path.expanduser(f"~/.config/herdr/sessions/{NAME}/herdr.sock")

# Kitty's bytes once herdr turns on the kitty keyboard protocol.
ALT_F, ALT_ENTER, ALT_W = b"\x1b[102;3u", b"\x1b[13;3u", b"\x1b[119;3u"
ALT_EQ, ALT_MINUS, ALT_S_EQ, ALT_S_MINUS = b"\x1b[61;3u", b"\x1b[45;3u", b"\x1b[61;4u", b"\x1b[45;4u"

results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else ": " + detail), flush=True)


# ── A throwaway herdr ─────────────────────────────────────────────────────────
guard = os.path.join(TMP, "guard")
with open(guard, "w") as f:
    f.write(f"""#!/bin/bash
live={LIVE}
if [ -z "${{HERDR_SOCKET_PATH:-}}" ] || [ "$(readlink -f "$HERDR_SOCKET_PATH")" = "$live" ]; then
  echo "guard: refusing $HERDR_SOCKET_PATH" >&2; exit 1
fi
export XDG_STATE_HOME={TMP}/state
exec {KEYS} "$@"
""")
os.chmod(guard, 0o755)
config = os.path.join(TMP, "config.toml")
with open(os.path.expanduser("~/.config/herdr/config.toml")) as f:
    text = f.read().replace("~/.local/bin/herdr-keys", guard)
with open(config, "w") as f:
    f.write(text)
proj = os.path.join(TMP, "proj")
os.makedirs(proj)
with open(os.path.join(proj, "long.ml"), "w") as f:
    for i in range(1, 301):
        f.write(f'let long_name_{i} = "{i} the quick brown fox jumps over the lazy dog and keeps running far away"\n')
with open(os.path.join(proj, "b.ml"), "w") as f:
    f.write("let y = 2\n")

env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_") and k not in ("TMUX", "TMUX_PANE")}
env.update(HERDR_CONFIG_PATH=config, TERM="xterm-kitty")
henv = dict(env, HERDR_SOCKET_PATH=SOCK)

pid, fd = pty.fork()
if pid == 0:
    os.chdir(TMP)
    os.execvpe("herdr", ["herdr", "--session", NAME], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
os.kill(pid, signal.SIGWINCH)
stop = False


def drain():
    while not stop:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                os.read(fd, 65536)
            except OSError:
                return


threading.Thread(target=drain, daemon=True).start()


def herdr(*args):
    r = subprocess.run(["herdr", *args], env=henv, capture_output=True, text=True)
    return json.loads(r.stdout) if r.stdout.strip().startswith("{") else r.stdout


def call(method, **params):
    req = json.dumps({"id": "t", "method": method, "params": params}) + "\n"
    r = subprocess.run(["socat", "-", f"UNIX-CONNECT:{SOCK}"], input=req, capture_output=True, text=True)
    return json.loads(r.stdout)


def layout(pane):
    return call("layout.export", pane_id=pane)["result"]["layout"]


def ratios(node):
    if node["type"] == "pane":
        return node["pane_id"]
    return [round(node["ratio"], 3), ratios(node["first"]), ratios(node["second"])]


def key(b, wait=1.2):
    os.write(fd, b)
    time.sleep(wait)


def q(expr, sock):
    r = subprocess.run(["nvim", "--clean", "--headless", "--server", sock, "--remote-expr", expr],
                       capture_output=True, text=True)
    return r.stdout.strip()


def agent_tab(sock):
    """A new tab in the agent view (herdr-keys agent): nvim | sh over sh."""
    r = herdr("tab", "create", "--cwd", proj, "--focus")
    p = r["result"]["root_pane"]["pane_id"]
    e = dict(henv, HERDR_PANE_ID=p, AGENT_CMD="sh",
             EDITOR_CMD=f"NVNEXT={NVNEXT} {HERE}/env.sh nvim --listen {sock} .")
    subprocess.run([guard, "agent", p], env=e, capture_output=True)
    for _ in range(80):
        if os.path.exists(sock) and q("v:vim_did_enter", sock) == "1":
            break
        time.sleep(0.5)
    time.sleep(2)
    return p


try:
    for _ in range(40):
        if os.path.exists(SOCK):
            break
        time.sleep(0.25)
    time.sleep(1)
    if os.path.realpath(SOCK) == LIVE:
        sys.exit("refusing: the test socket is the live one")

    # ── Split beside Neovim, close it, zoom: sizes and view come back ────────
    nv = os.path.join(TMP, "a.sock")
    p = agent_tab(nv)
    q("execute('wincmd l | edit long.ml | normal! 150Gzz')", nv)
    time.sleep(1)
    top = q("line('w0')", nv)
    start = ratios(layout(p)["root"])
    key(ALT_ENTER)  # herdr-keys split right: thirds across the top row
    key(ALT_W)  # close the new shell
    after = ratios(layout(p)["root"])
    check("Alt+Enter beside Neovim then Alt+W keeps the 60/40 row", after == start, f"{start} -> {after}")
    check("... and Neovim's view", q("line('w0')", nv) == top, f"first line {top} -> {q('line(\"w0\")', nv)}")
    key(ALT_F, 1.5)
    zoomed = layout(p)["zoomed"]
    key(ALT_F, 1.5)
    L = layout(p)
    check("Alt+F from Neovim zooms and unzooms the herdr pane", zoomed and not L["zoomed"], f"zoomed {zoomed}, after {L['zoomed']}")
    check("... ratios unchanged", ratios(L["root"]) == start, f"{start} -> {ratios(L['root'])}")
    check("... view unchanged", q("line('w0')", nv) == top, f"first line {top} -> {q('line(\"w0\")', nv)}")

    # ── Resize keys ──────────────────────────────────────────────────────────
    root = lambda: layout(p)["root"]
    key(ALT_EQ)
    check("Alt+= in Neovim beside the tree widens the herdr pane", root()["ratio"] > 0.62, str(ratios(root())))
    key(ALT_MINUS)
    check("Alt+- narrows it back", abs(root()["ratio"] - 0.6) < 0.01, str(ratios(root())))
    q("execute('vsplit b.ml')", nv)
    time.sleep(0.5)
    w = int(q("winwidth(0)", nv))
    key(ALT_EQ)
    w2 = int(q("winwidth(0)", nv))
    check("Alt+= with two Neovim splits widens the split, not the herdr pane",
          w2 > w and abs(root()["ratio"] - 0.6) < 0.01, f"split {w} -> {w2}, {ratios(root())}")
    key(ALT_MINUS)
    check("Alt+- narrows the split", int(q("winwidth(0)", nv)) < w2, q("winwidth(0)", nv))
    q("execute('only | split b.ml')", nv)
    time.sleep(0.5)
    h = int(q("winheight(0)", nv))
    key(ALT_S_EQ)
    h2 = int(q("winheight(0)", nv))
    check("Alt+Shift+= makes a Neovim split taller", h2 > h, f"{h} -> {h2}")
    key(ALT_S_MINUS)
    check("Alt+Shift+- makes it shorter", int(q("winheight(0)", nv)) < h2, q("winheight(0)", nv))
    q("execute('only')", nv)
    shell = root()["second"]["first"]["pane_id"]
    call("pane.focus", pane_id=shell)
    time.sleep(0.5)
    key(ALT_EQ)
    check("Alt+= in a shell pane widens it", root()["ratio"] < 0.58, str(ratios(root())))
    key(ALT_MINUS)
    check("Alt+- in a shell pane narrows it", abs(root()["ratio"] - 0.6) < 0.01, str(ratios(root())))
    key(ALT_S_EQ)
    col = root()["second"]["ratio"]
    check("Alt+Shift+= in a shell pane makes it taller", col > 0.72, str(ratios(root())))
    key(ALT_S_MINUS)
    check("Alt+Shift+- in a shell pane makes it shorter", root()["second"]["ratio"] < col, str(ratios(root())))
finally:
    stop = True
    subprocess.run(["herdr", "session", "stop", NAME], env=env, capture_output=True)
    subprocess.run(["herdr", "session", "delete", NAME], env=env, capture_output=True)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    subprocess.run(["rm", "-rf", TMP])

print(f"pass {results.count(True)} fail {results.count(False)}")
sys.exit(0 if results and all(results) else 1)
