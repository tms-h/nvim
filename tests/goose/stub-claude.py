"""Fake `claude --input-format stream-json`: one long-lived process that
answers each user message with streamed text, like the real CLI. Logs each
message (pid, content) to $GOOSE_STUB_LOG. "CRASH" in a message makes it die
mid-answer. $GOOSE_STUB_DELAY = seconds between streamed chunks."""
import json, os, sys, time

log = os.environ.get("GOOSE_STUB_LOG")
delay = float(os.environ.get("GOOSE_STUB_DELAY", "0.05"))
n = 0
for line in sys.stdin:
    msg = json.loads(line)
    content = msg["message"]["content"]
    n += 1
    if log:
        with open(log, "a") as f:
            f.write(json.dumps({"pid": os.getpid(), "n": n, "content": content}) + "\n")
    chunks = ["```\n", f"let a{n} = {n}", f"\nlet b{n} = {n}\n", "```"]
    for i, c in enumerate(chunks):
        ev = {"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                                                "delta": {"type": "text_delta", "text": c}}}
        print(json.dumps(ev), flush=True)
        if i == 1 and "CRASH" in content:
            sys.exit(3)
        time.sleep(delay)
    usage = {"input_tokens": len(content) // 4, "cache_creation_input_tokens": 0,
             "cache_read_input_tokens": 0, "output_tokens": 10}
    print(json.dumps({"type": "result", "subtype": "success", "is_error": False,
                      "result": "".join(chunks), "usage": usage}), flush=True)
