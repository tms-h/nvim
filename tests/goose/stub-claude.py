"""Fake `claude --input-format stream-json`: one long-lived process that
answers each user message with streamed text, like the real CLI. Logs each
message (pid, content) to $GOOSE_STUB_LOG. "CRASH" in a message makes it die
mid-answer; "UGLY" gets an answer ocamlformat would change. A last part
"Question: ..." gets a Markdown answer, after a preamble and a Read of
bin/main.ml when the question mentions main; "ELSEWHERE" also changes
`let target = 1` to 2 (a SEARCH/REPLACE block), "ONLYELSEWHERE" does only
that. Each log line has the folder the stub runs in (cwd).
$GOOSE_STUB_DELAY = seconds between streamed chunks."""
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
            f.write(json.dumps({"pid": os.getpid(), "n": n, "content": content, "cwd": os.getcwd()}) + "\n")
    chunks = ["```\n", f"let a{n} = {n}", f"\nlet b{n} = {n}\n", "```"]
    block = ["<<<<<<< SEARCH\n", "let target = 1\n", "=======\n", "let target = 2\n", ">>>>>>> REPLACE\n"]
    if "UGLY" in content:
        chunks = ["let   u", " =  (1+2)\n"]
    elif "\n\nQuestion: " in content:
        q = content.rsplit("Question: ", 1)[1]
        if "main" in q:
            for c in ["Let me look at main."]:
                print(json.dumps({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                                                                     "delta": {"type": "text_delta", "text": c}}}), flush=True)
            print(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "id": "t1", "name": "Read", "input": {"file_path": os.path.join(os.getcwd(), "bin/main.ml")}}]}}), flush=True)
        chunks = [f"**answer {n}**", " to: ", q, "\n\nsecond line\n"]
    elif "ONLYELSEWHERE" in content:
        chunks = block
    elif "ELSEWHERE" in content:
        chunks = [f"let z{n} = 0\n"] + block
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
