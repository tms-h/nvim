"""Goose's memory as a tiny stdio MCP server: `remember` and `forget` edit one
Markdown file, the path given on the command line, and nothing else (the
tools take no path). Each note is one `- ` line; Thomas edits the file freely
(:GooseMemory). The Alt+L chat runs it as `python3 memory.py <file> [max]`;
goose puts the file into the system prompt of each new session.

Protocol: newline-delimited JSON-RPC 2.0 (MCP stdio), no SDK, as in
~/Work/js-wiki/tools/wiki.py."""
import json, os, sys

PATH = os.path.abspath(sys.argv[1])
MAX = int(sys.argv[2]) if len(sys.argv) > 2 else 4000  # bytes; goose cuts the prompt copy there too

TOOLS = [
    {"name": "remember", "description": "Save one lasting note about Thomas (a preference, a project convention, "
     "a correction he gave) to goose's memory, which every new chat and Alt+K conversion reads. One short "
     "sentence. Not for one-off details of the current question.",
     "inputSchema": {"type": "object", "properties": {"note": {"type": "string"}}, "required": ["note"]}},
    {"name": "forget", "description": "Delete the memory notes containing this text (case-insensitive), when "
     "Thomas says a saved note is wrong or no longer holds.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}},
]


def lines():
    try:
        with open(PATH, encoding="utf-8") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def save(rows):
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    tmp = PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("".join(r + "\n" for r in rows))
    os.replace(tmp, PATH)


def remember(a):
    note = " ".join(str(a["note"]).split()).lstrip("-* ").strip()
    if not note:
        return "Empty note: nothing saved.", True
    rows = lines()
    if any(note.lower() == r.lstrip("-* ").strip().lower() for r in rows):
        return "Already in memory.", False
    rows.append("- " + note)
    if len("".join(r + "\n" for r in rows).encode()) > MAX:
        return f"Memory is full ({MAX} bytes): nothing saved. Forget an old note first, or ask Thomas to prune it (:GooseMemory).", True
    save(rows)
    return f"Saved to {PATH}: - {note}", False


def forget(a):
    text = str(a["text"]).strip().lower()
    if not text:
        return "Empty text: nothing forgotten.", True
    rows = lines()
    gone = [r for r in rows if r.startswith(("-", "*")) and text in r.lower()]
    if not gone:
        return "No note contains that text.", False
    save([r for r in rows if r not in gone])
    return "Forgot:\n" + "\n".join(gone), False


CALLS = {"remember": remember, "forget": forget}


def handle(method, params):
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion") or "2025-06-18", "capabilities": {"tools": {}},
                "serverInfo": {"name": "goose-memory", "version": "1"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        try:
            text, err = CALLS[params["name"]](params.get("arguments") or {})
        except KeyError as e:  # the model's to fix, not a protocol error
            text, err = f"Unknown tool or missing argument: {e}", True
        except OSError as e:
            text, err = f"{type(e).__name__}: {e}", True
        return {"content": [{"type": "text", "text": text}], "isError": err}
    raise LookupError(method)


def serve():
    out, sys.stdout = sys.stdout, sys.stderr  # only protocol frames on the real stdout
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if "method" not in msg or "id" not in msg:  # notifications need no answer
            continue
        try:
            reply = {"result": handle(msg["method"], msg.get("params") or {})}
        except LookupError:
            reply = {"error": {"code": -32601, "message": f"Method not found: {msg['method']}"}}
        out.write(json.dumps({"jsonrpc": "2.0", "id": msg["id"], **reply}, ensure_ascii=False) + "\n")
        out.flush()


if __name__ == "__main__":
    serve()
