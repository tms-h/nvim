#!/usr/bin/env python3
"""What this Neovim config does, read from the config itself, so it can't drift from the machine it runs on.

  python3 tools/lookup/lookup.py keys zoom          # keys by what they do, or by key: "alt+f", "space o", "<C-k>"
  python3 tools/lookup/lookup.py keys "space o" --ft ocaml
  python3 tools/lookup/lookup.py where "divider hover"   # modules, code blocks, :commands, plugins
  python3 tools/lookup/lookup.py mcp                # MCP server `nvimcfg` (~/.omp/agent/mcp.json, ~/.claude.json)
  python3 tools/lookup/lookup.py check              # exit 1 if a key this config sets has no desc

Keys and :commands come from a headless Neovim that loads this checkout (tools/lookup/dump.lua notes the file:line
that set each one), twice: as Neovide and as a terminal Neovim inside tmux, since some keys exist in only one. It
runs with scratch state, no clipboard, no window and no GitHub pull. The dump is cached in ~/.cache/nvim-lookup/ and
redone when any config file changes. Use counts come from :UsageReport's log (usage/counts.jsonl).
"""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import threading
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "nvim-lookup"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
SOURCES = ("init.lua", "lua", "after", "lsp", "plugin", "nvim-pack-lock.json", "tools/lookup")
MODIFIERS = {"M": "Alt", "A": "Alt", "C": "Ctrl", "S": "Shift", "D": "Cmd"}
NAMES = {"cr": "Enter", "return": "Enter", "esc": "Esc", "bs": "Backspace", "space": "Space", "lt": "<", "bslash": "\\",
         "bar": "|", "del": "Delete", "leader": "Space", "localleader": "Space", "tab": "Tab", "nl": "Ctrl+J"}
CONTEXTS = {"neovide": "Neovide only", "tmux": "tmux/herdr only"}


# ---------------------------------------------------------------- dump

def config_files():
    for name in SOURCES:
        p = ROOT / name
        if p.is_file():
            yield p
        elif p.is_dir():
            yield from (f for f in sorted(p.rglob("*")) if f.is_file() and f.suffix in (".lua", ".json", ".py", ".vim"))


def signature():
    h = hashlib.sha1()
    nvim = next((Path(d) / "nvim" for d in os.environ.get("PATH", "").split(os.pathsep) if (Path(d) / "nvim").exists()), None)
    for f in [*config_files(), *([nvim] if nvim else [])]:
        st = f.stat()
        h.update(f"{f}\0{st.st_mtime_ns}\0{st.st_size}\n".encode())
    return h.hexdigest()


def run_dump(context):
    """One headless start of this config. Real plugins and caches; scratch state; nothing reaches the desktop."""
    with tempfile.TemporaryDirectory(prefix="nvim-lookup-") as tmp:
        env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY", "TMUX", "HERDR_ENV", "NVIM")}
        env.update(XDG_STATE_HOME=f"{tmp}/state", NVIM_NO_CONFIG_PULL="1", WAKATIME_HOME=f"{tmp}/wakatime",
                   LOOKUP_OUT=f"{tmp}/out.json")
        pre = "let g:no_restore = 1"
        if context == "neovide":
            pre += " | let g:neovide = v:true"
        else:
            env["TMUX"] = f"{tmp}/tmux-none,0,0"  # the in-tmux branch; no server is ever reached at startup
        cmd = ["nvim", "--headless", "-i", "NONE", "--cmd", pre, "--cmd", f"luafile {HERE / 'dump.lua'}"]
        if os.name == "posix":
            cmd = ["nice", "-n", "19", *cmd]
        proc = subprocess.run(cmd, env=env, cwd=tmp, capture_output=True, text=True, timeout=60,
                              stdin=subprocess.DEVNULL)
        out = Path(tmp, "out.json")
        if not out.exists():
            raise RuntimeError(f"nvim dump ({context}) wrote nothing: {proc.stderr.strip()[-400:]}")
        return json.loads(out.read_text())


def load_dump():
    sig = signature()
    path = CACHE / "dump.json"
    try:
        data = json.loads(path.read_text())
        if data["sig"] == sig:
            return data
    except (OSError, ValueError, KeyError):
        pass
    with ThreadPoolExecutor(2) as pool:
        neovide, tmux = pool.map(run_dump, ("neovide", "tmux"))
    data = {"sig": sig, "neovide": neovide, "tmux": tmux}
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, path)
    return data


def readable(lhs):
    """`<M-S-Left>` → Alt+Shift+Left, `<M-F>` → Alt+Shift+F, `<D-p>` → Cmd+P, ` fs` → Space f s."""
    out = []
    for tok in re.findall(r"<[^<>]+>|.", lhs):
        if len(tok) > 2 and tok[0] == "<":
            body = tok[1:-1]
            parts = body.split("-")
            if body.endswith("-") and len(body) > 1:
                parts = parts[:-2] + ["-"]
            *mods, key = parts if all(len(m) == 1 for m in parts[:-1]) else [body]
            mods = [MODIFIERS.get(m.upper(), m) for m in mods]
            if len(key) == 1 and key.isalpha() and mods:
                # Vim tells Alt+Shift+F from Alt+F by the letter's case (<M-F>); Ctrl chords ignore it
                if key.isupper() and "Ctrl" not in mods and "Shift" not in mods:
                    mods.append("Shift")
                key = key.upper()
            key = NAMES.get(key.lower(), key if len(key) == 1 else key[:1].upper() + key[1:])
            mods.sort(key=lambda m: ("Ctrl", "Alt", "Cmd", "Shift").index(m) if m in ("Ctrl", "Alt", "Cmd", "Shift") else 9)
            out.append("+".join(mods + [key]))
        else:
            out.append("Space" if tok == " " else tok)
    return " ".join(out)


def usage_counts():
    """readable key + buffer flag → times pressed, summed over :UsageReport's log."""
    counts = Counter()
    f = STATE / "nvim" / "usage" / "counts.jsonl"
    if not f.exists():
        return counts
    for line in f.read_text().splitlines():
        try:
            for k, n in json.loads(line).get("counts", {}).items():
                m = re.match(r"map \S+ (.+?)( \(buffer\))?(?:  -- .*)?$", k)
                if m:
                    counts[(readable(m.group(1)), bool(m.group(2)))] += n
        except ValueError:
            continue
    return counts


def is_filler(m):
    d, rhs = m.get("desc", ""), m.get("rhs", "")
    return rhs.upper() == "<NOP>" or d == "<Nop>" or d.startswith("Stray") or (not rhs and not d)


def pick_sites(maps):
    """dump.lua records the first config frame and, when there is one, the next frame in the same file. A helper
    that sets many keys (explorer.lua's `map`) reports its own line for all of them, so for a line that sets 4+
    different keys the caller's line is the useful one; loops and one-off calls keep their own."""
    per_line = defaultdict(set)
    for m in maps:
        per_line[(m.get("where") or "").split("|")[0]].add(m["lhs"])
    for m in maps:
        first, _, caller = (m.get("where") or "").partition("|")
        m["where"] = caller if caller and len(per_line[first]) >= 4 else first
    return maps


_keys = {}


def key_table(dump):
    """Rows cached until the config or the usage log changes."""
    log = STATE / "nvim" / "usage" / "counts.jsonl"
    stamp = (dump["sig"], log.stat().st_mtime_ns if log.exists() else 0)
    if _keys.get("stamp") != stamp:
        _keys.update(stamp=stamp, rows=build_key_table(dump))
    return _keys["rows"]


def build_key_table(dump):
    rows = {}
    for context in ("neovide", "tmux"):
        for m in pick_sites(dump[context]["maps"]):
            if is_filler(m):
                continue
            where = m.get("where") or ""
            ident = (readable(m["lhs"]), m.get("ft") or "", m.get("desc", ""), m.get("rhs", ""), where)
            row = rows.setdefault(ident, {"modes": set(), "contexts": set()})
            row["modes"].add(m["mode"])
            row["contexts"].add(context)
    used = usage_counts()
    out = []
    for (key, ft, desc, rhs, where), row in rows.items():
        builtin = not where or where.startswith("/") and "/runtime/" in where
        only = row["contexts"] if len(row["contexts"]) == 1 else set()
        out.append({"key": key, "ft": ft, "desc": desc or (rhs if rhs != "<Lua function>" else ""),
                    "modes": "".join(m for m in "nixsotc" if m in row["modes"]), "where": "" if builtin else where,
                    "builtin": builtin, "only": CONTEXTS[next(iter(only))] if only else "",
                    "used": used.get((key, bool(ft)), 0)})
    return out


def norm_key(q):
    """A query that names a key, in any notation, in the readable form; None for a plain-words query."""
    q = q.strip()
    if re.search(r"<[^>]+>", q):
        return readable(q).lower()
    if re.fullmatch(r"(?i)((alt|cmd|ctrl|shift|meta|super)\+)+\S+|space( \S)*|\S", q):
        return re.sub(r"(?i)\b(meta|super)\b", "alt", q).lower()
    return None


def words(s):
    return [w for w in re.findall(r"[a-z0-9]+", s.lower()) if len(w) > 1]


def keys(query, ft="", limit=20):
    rows = key_table(load_dump())
    if ft:
        rows = [r for r in rows if r["ft"] in ("", ft)]
    nk = norm_key(query)
    if nk is not None:
        hits = [r for r in rows if r["key"].lower() == nk or r["key"].lower().startswith(nk + " ")]
        hits.sort(key=lambda r: (r["key"].lower() != nk, r["builtin"], r["key"]))
    else:
        q = set(terms(query))
        scored = []
        for r in rows:
            n = len(q & set(terms(f"{r['desc']} {r['key']} {r['ft']} {r['where']}")))
            if n:
                mine = r["where"].startswith(("lua/", "after/", "lsp/", "plugin/", "init.lua"))
                scored.append((-n, r["builtin"], not mine, -r["used"], r["key"], r))
        scored.sort(key=lambda x: x[:5])
        best = scored[0][0] if scored else 0
        hits = [s[-1] for s in scored if s[0] <= best + (1 if len(q) > 2 else 0)]
    if not hits:
        return f"No key matches {query!r}." + (" Try words from what it does." if nk is not None else "")
    lines = []
    for r in hits[:limit]:
        tags = [t for t in (r["ft"] and f"{r['ft']} buffers", r["only"], "built-in" if r["builtin"] else "") if t]
        lines.append(f"{r['key']}  [{r['modes']}]  {r['desc']}" + (f"  ({', '.join(tags)})" if tags else "")
                     + (f"  · {r['where']}" if r["where"] else "") + (f"  · used {r['used']}×" if r["used"] else ""))
    if len(hits) > limit:
        lines.append(f"[{len(hits) - limit} more; narrow the query or raise limit]")
    return "\n".join(lines)


# ---------------------------------------------------------------- where

STOP = set("a an the and or of to in on at for with by from as is are be it its this that not no if then local end "
           "function return do".split())


def terms(s):
    out = []
    for w in re.findall(r"[A-Za-z0-9_]+", s):
        parts = [p for p in re.split(r"_|(?<=[a-z])(?=[A-Z])", w) if p]
        for t in {w.lower(), *(p.lower() for p in parts)}:
            if t not in STOP and len(t) > 1:
                out.append(t[:-1] if len(t) > 4 and t.endswith("s") and not t.endswith("ss") else t)
    return out


def check():
    """Every key this config sets must say what it does (its desc), or keys/which-key can't explain it."""
    bad = [r for r in key_table(load_dump()) if r["where"].startswith(("lua/", "after/", "lsp/", "init.lua"))
           and (not r["desc"] or r["desc"].startswith("<"))]
    for r in bad:
        print(f"{r['where']}: {r['key']} [{r['modes']}] has no desc")
    return 1 if bad else 0


def code_docs(dump):
    """Searchable pieces: each module's header comment, each blank-line-separated block of Lua (with the comment
    above it), each :command this config defines, each plugin."""
    docs = []
    for f in config_files():
        rel = f.relative_to(ROOT).as_posix()
        if f.suffix != ".lua" or rel.startswith("tools/"):
            continue
        lines = f.read_text(errors="replace").splitlines()
        header = []
        for l in lines:
            if not l.startswith("--"):
                break
            header.append(l[2:].strip())
        if header:
            docs.append((f"{rel}:1", f"module: {header[0]}", " ".join(header) + " " + rel, 2))
        start, block = 0, []
        for i, l in enumerate(lines + [""], 1):
            if l.strip():
                if not block:
                    start = i
                block.append(l)
                continue
            if block and not all(b.lstrip().startswith("--") for b in block):
                docs.append((f"{rel}:{start}", "", "\n".join(block), 1))  # summary: the best line, at query time
            elif block:  # a comment-only block belongs to the code after it
                continue
            block = []
    for c in dump["neovide"]["cmds"]:
        w = (c.get("where") or "").split("|")[0]
        if w and not w.startswith("/"):
            docs.append((w, f":{c['name']}  {c.get('desc', '')}".strip(), f"{c['name']} {c.get('desc', '')} command", 3))
    lock = ROOT / "nvim-pack-lock.json"
    if lock.exists():
        for name, p in json.loads(lock.read_text()).get("plugins", {}).items():
            docs.append(("nvim-pack-lock.json", f"plugin {name} @ {p.get('rev', '')[:7]} {p.get('src', '')}",
                         f"plugin {name} {p.get('src', '')}", 3))
    return docs


_index = {}


def index(dump):
    if _index.get("sig") != dump["sig"]:
        docs = code_docs(dump)
        toks = [Counter(terms(text) + terms(summary) * boost) for _, summary, text, boost in docs]
        df = Counter(t for c in toks for t in c)
        _index.update(sig=dump["sig"], docs=docs, toks=toks, df=df,
                      avg=sum(sum(c.values()) for c in toks) / max(len(toks), 1))
    return _index


def where(query, limit=8):
    ix = index(load_dump())
    q = set(terms(query))
    if not q:
        return "Empty query."
    n, scored = len(ix["docs"]), []
    for d, tf in enumerate(ix["toks"]):
        hits = [t for t in q if t in tf]
        if not hits:
            continue
        length = sum(tf.values())
        s = sum(math.log(1 + (n - ix["df"][t] + .5) / (ix["df"][t] + .5)) * tf[t] * 2.2
                / (tf[t] + 1.2 * (.25 + .75 * length / ix["avg"])) for t in hits)
        scored.append((s * (len(hits) / len(q)) ** 2, d))
    scored.sort(reverse=True)
    out, seen = [], set()
    for _, d in scored:
        loc, summary, text, _ = ix["docs"][d]
        if not summary:  # a code block: point at its line with the most query words
            lines = text.splitlines()
            i = max(range(len(lines)), key=lambda j: (len(q & set(terms(lines[j]))), -j))
            file, start = loc.rsplit(":", 1)
            loc, summary = f"{file}:{int(start) + i}", lines[i].strip()[:110]
        if loc in seen and loc != "nvim-pack-lock.json":
            continue
        seen.add(loc)
        out.append(f"{loc}  {summary}")
        if len(out) >= limit:
            break
    return "\n".join(out) or f"Nothing matches {query!r}."


# ---------------------------------------------------------------- MCP (stdio JSON-RPC, no SDK)

INSTRUCTIONS = ("Thomas's Neovim config (~/.config/nvim), read live from this machine's checkout. Use keys for "
                "'what key does X / what does key Y do', where for 'which file/function/plugin handles X'; then read "
                "the file:line it gives. Answer with keys, not typed :commands.")
TOOLS = [
    {"name": "keys", "description": "Neovim keys in Thomas's config. query = a key in any notation (alt+f, "
     "<C-k>, 'space o') or words from what it does. Lines: key [modes] what · file:line · times used. ft limits "
     "to one filetype's buffer keys plus globals.",
     "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}, "ft": {"type": "string"},
                                                      "limit": {"type": "integer", "default": 20}},
                     "required": ["query"]}},
    {"name": "where", "description": "Find code in Thomas's Neovim config: module headers, Lua blocks, "
     ":commands and plugins, ranked. Returns file:line + first line.",
     "inputSchema": {"type": "object", "properties": {"query": {"type": "string"},
                                                      "limit": {"type": "integer", "default": 8}},
                     "required": ["query"]}},
]
for _t in TOOLS:
    _t["annotations"] = {"readOnlyHint": True, "openWorldHint": False}
CALLS = {"keys": lambda a: keys(a["query"], a.get("ft", ""), int(a.get("limit", 20))),
         "where": lambda a: where(a["query"], int(a.get("limit", 8)))}
PROTOCOLS = {"2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"}


def handle(method, params):
    if method == "initialize":
        v = params.get("protocolVersion")
        return {"protocolVersion": v if v in PROTOCOLS else "2025-06-18", "capabilities": {"tools": {}},
                "serverInfo": {"name": "nvimcfg", "version": "1"}, "instructions": INSTRUCTIONS}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        try:
            text, err = CALLS[params["name"]](params.get("arguments") or {}), False
        except KeyError as e:  # a bad call is the model's to fix, not a protocol error
            text, err = f"Unknown tool or missing argument: {e}", True
        except Exception as e:
            text, err = f"{type(e).__name__}: {e}", True
        return {"content": [{"type": "text", "text": text}], "isError": err}
    raise LookupError(method)


def serve():
    out, sys.stdout = sys.stdout, sys.stderr  # nothing but protocol frames may reach the real stdout
    threading.Thread(target=lambda: index(load_dump()), daemon=True).start()  # warm while the client connects
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if "method" not in msg or "id" not in msg:
            continue
        try:
            reply = {"result": handle(msg["method"], msg.get("params") or {})}
        except LookupError:
            reply = {"error": {"code": -32601, "message": f"Method not found: {msg['method']}"}}
        out.write(json.dumps({"jsonrpc": "2.0", "id": msg["id"], **reply}, ensure_ascii=False) + "\n")
        out.flush()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    k = sub.add_parser("keys")
    k.add_argument("query", nargs="+")
    k.add_argument("--ft", default="")
    k.add_argument("-n", type=int, default=20)
    w = sub.add_parser("where")
    w.add_argument("query", nargs="+")
    w.add_argument("-n", type=int, default=8)
    sub.add_parser("mcp")
    sub.add_parser("check", help="exit 1 if a key this config sets has no desc")
    a = ap.parse_args()
    if a.cmd == "mcp":
        return serve()
    if a.cmd == "check":
        sys.exit(check())
    print(keys(" ".join(a.query), a.ft, a.n) if a.cmd == "keys" else where(" ".join(a.query), a.n))


if __name__ == "__main__":
    main()
