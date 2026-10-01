"""A stand-in model gateway that records what the game sends and what it costs.

Run it, point the game at it, and play:

    python _tools/mock_gateway.py --port 8787 --log /tmp/calls.jsonl
    godot4 --path . -- --proxy=http://127.0.0.1:8787/v1/chat/completions

Every request is answered with something the game can use -- a tool call for
an order, a filled-in object for a JSON-schema call, a sentence for talk -- so
the whole flow runs end to end without a key or a network. Every request is
also written to the log with its token counts, which is what
_tools/token_report.py reads.

The counts are cl100k_base (tiktoken). The gateways the game uses run on
o200k-family tokenizers, which come out a few percent lower on English, so
treat the numbers as a slight overestimate. Output tokens here are what this
mock wrote, which is far less than a real model writes; the report estimates
real output separately.

Needs tiktoken and a cl100k_base.tiktoken file (pass --bpe, or install the
tiktoken-offline wheel).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import tiktoken
from tiktoken.load import load_tiktoken_bpe

PAT = (r"""'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+|"""
       r""" ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s""")
ENC: tiktoken.Encoding | None = None
LOG = None


def tokens(text: str) -> int:
    return len(ENC.encode(text, disallowed_special=()))


# ------------------------------------------------------------- schema filler

def fill(schema: dict, hint: str = "") -> object:
    """The smallest value that satisfies a JSON schema, with a little sense."""
    t = schema.get("type")
    if isinstance(t, list):
        t = next((x for x in t if x != "null"), "string")
    if "enum" in schema:
        options = [e for e in schema["enum"] if e is not None]
        for o in options:
            if isinstance(o, str) and o.lower() in hint.lower():
                return o
        return options[0] if options else None
    if t == "object":
        props = schema.get("properties", {})
        out = {}
        for k in schema.get("required", list(props)):
            if k in props:
                out[k] = fill(props[k], hint)
        return out
    if t == "array":
        n = max(1, int(schema.get("minItems", 1)))
        return [fill(schema.get("items", {"type": "string"}), hint) for _ in range(n)]
    if t == "integer":
        lo = int(schema.get("minimum", 1))
        hi = int(schema.get("maximum", lo + 10))
        nums = [int(x) for x in re.findall(r"\b(\d{1,3})\b", hint)]
        for v in nums:
            if lo <= v <= hi:
                return v
        return max(lo, min(hi, 2))
    if t == "number":
        return float(schema.get("minimum", 1))
    if t == "boolean":
        return False
    return "Right, I will see to it."


def last_user(body: dict) -> str:
    for m in reversed(body.get("messages", [])):
        if m.get("role") == "user":
            return str(m.get("content", ""))
    return ""


def instruction_of(text: str) -> str:
    # Prompt.user() quotes the player's sentence; fall back to the whole text.
    m = re.search(r'"([^"\n]{2,200})"', text)
    return m.group(1) if m else text[-200:]


def pick_tool(tools: list, said: str) -> dict:
    words = set(re.findall(r"[a-z_]+", said.lower()))
    best, best_score = None, 0
    for t in tools:
        name = t["function"]["name"]
        score = 3 if name in words else 0
        score += sum(1 for w in name.split("_") if w in words)
        if score > best_score:
            best, best_score = t, score
    if best is None:
        best = next(t for t in tools if t["function"]["name"] == "reply")
    return best


def answer(body: dict) -> tuple[dict, str]:
    """What to send back, and which kind of call this was."""
    user = last_user(body)
    if body.get("tools"):
        said = instruction_of(user)
        tool = pick_tool(body["tools"], said)
        fn = tool["function"]
        args = fill(fn.get("parameters", {"type": "object"}), said)
        if fn["name"] == "reply":
            args = {"text": "I am not sure that is a job for me."}
        msg = {"role": "assistant", "content": None, "tool_calls": [{
            "id": "call_mock", "type": "function",
            "function": {"name": fn["name"], "arguments": json.dumps(args)},
        }]}
        return msg, "plan"
    rf = body.get("response_format") or {}
    if rf.get("type") == "json_schema":
        js = rf.get("json_schema", {})
        content = json.dumps(fill(js.get("schema", {}), user))
        return {"role": "assistant", "content": content}, "schema:" + js.get("name", "?")
    cap = int(body.get("max_tokens") or body.get("max_completion_tokens") or 0)
    kind = "answer" if cap <= 230 else "talk" if cap <= 300 else "text"
    return {"role": "assistant", "content": "Right you are. I will keep at it."}, kind


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_a):
        pass

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type, x-provider")
        self.end_headers()

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        t0 = time.time()
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return
        msg, kind = answer(body)
        sys_txt = "".join(str(m.get("content", "")) for m in body.get("messages", [])
                          if m.get("role") == "system")
        msgs_txt = "".join(str(m.get("content", "")) for m in body.get("messages", [])
                           if m.get("role") != "system")
        tools_txt = json.dumps(body.get("tools", [])) if body.get("tools") else ""
        schema_txt = json.dumps(body.get("response_format", {})) \
            if body.get("response_format") else ""
        # ~4 tokens of framing per message, as the chat format adds them.
        framing = 4 * len(body.get("messages", []))
        parts = {
            "system": tokens(sys_txt), "messages": tokens(msgs_txt),
            "tools": tokens(tools_txt), "schema": tokens(schema_txt), "framing": framing,
        }
        prompt = sum(parts.values())
        out_txt = msg.get("content") or json.dumps(msg.get("tool_calls"))
        completion = tokens(out_txt)
        rec = {
            "t": t0, "kind": kind, "path": self.path, "model": body.get("model"),
            "max_out": body.get("max_tokens") or body.get("max_completion_tokens"),
            "n_messages": len(body.get("messages", [])), "n_tools": len(body.get("tools", [])),
            "prompt_tokens": prompt, "parts": parts, "mock_completion_tokens": completion,
            "said": instruction_of(last_user(body))[:160],
            "tool": (msg.get("tool_calls") or [{}])[0].get("function", {}).get("name"),
            "bytes": len(raw),
        }
        LOG.write(json.dumps(rec) + "\n")
        LOG.flush()
        reply = {
            "id": "mock", "object": "chat.completion", "model": body.get("model", "mock"),
            "choices": [{"index": 0, "message": msg,
                         "finish_reason": "tool_calls" if msg.get("tool_calls") else "stop"}],
            "usage": {"prompt_tokens": prompt, "completion_tokens": completion,
                      "total_tokens": prompt + completion},
        }
        data = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    global ENC, LOG
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--log", default="calls.jsonl")
    ap.add_argument("--bpe", default="", help="path to cl100k_base.tiktoken")
    a = ap.parse_args()
    if a.bpe:
        ENC = tiktoken.Encoding(name="cl100k_local", pat_str=PAT,
                                mergeable_ranks=load_tiktoken_bpe(a.bpe), special_tokens={})
    else:
        ENC = tiktoken.get_encoding("cl100k_base")
    LOG = open(a.log, "a", encoding="utf8")
    print(f"mock gateway on :{a.port}, logging to {a.log}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
