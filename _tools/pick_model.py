"""Which Orca Router free model can actually plan a building?

Four free models are on offer and they are not interchangeable for this game:
the planner needs strict JSON Schema tool calling, and a model that cannot hold
that shape fails every build order in the same silent way. So each is tried
against the game's real tool schema rather than picked on reputation.

Also measures what a prompt costs, because the reason Groq ran out was 3,400
tokens a plan against a 200,000 daily budget. The figure decides whether a
fourteen-case matrix is affordable at all.

    python _tools/pick_model.py
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = "https://api.orcarouter.ai/v1/chat/completions"
KEY = os.environ.get("ORCAROUTER_API_KEY", "")

# Straight from ArchetypeLibrary.fallback()'s output, so the model is asked to
# return the shape the dispatcher actually consumes.
SCHEMA = {
    "type": "function",
    "function": {
        "name": "bakery",
        "description": "put up, redesign or extend a building",
        "parameters": {
            "type": "object",
            "properties": {
                "brief": {"type": "string", "description": "what it is for, in words"},
                "material": {"type": "string", "enum": ["timber", "plank", "stone", "brick"]},
                "size": {"type": "array", "minItems": 2, "maxItems": 2,
                         "items": {"type": "integer"}},
            },
            "required": ["brief"],
        },
    },
}

PROMPT = ("A player said: build me a bakery facing the square, timber framed, "
          "with a big window. Call the bakery tool.")

MODELS = [
    "orcarouter/free",
    "z-ai/glm-5.3-flash-free",
    "deepseek/deepseek-v4-flash-free",
    "tencent/hy3-free",
    "orca/orcaverify-text1.0-free",
]


def call(model, timeout=90):
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content":
                "You plan building work for a village. You act by calling a tool."},
            {"role": "user", "content": PROMPT},
        ],
        "tools": [SCHEMA],
        "tool_choice": "auto",
        "max_tokens": 900,
    }
    req = urllib.request.Request(
        ENDPOINT, data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + KEY,
                 "Content-Type": "application/json",
                 "HTTP-Referer": "https://vedant251002.github.io"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r), time.time() - t0, None
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            msg = json.loads(raw).get("error", {}).get("message", raw[:150])
        except Exception:
            msg = raw[:150]
        return None, time.time() - t0, f"http={e.code} {msg[:110]}"
    except Exception as e:
        return None, time.time() - t0, f"{type(e).__name__}: {str(e)[:90]}"


def tool_call_ok(d):
    """Did it produce a real tool call, and does the payload fit the schema?"""
    if not d:
        return False, "no response"
    msg = (d.get("choices") or [{}])[0].get("message", {})
    calls = msg.get("tool_calls") or []
    if not calls:
        return False, "no tool call (plain text instead)"
    fn = calls[0].get("function", {})
    name = fn.get("name", "")
    if name != "bakery":
        return False, f"called {name!r} not 'bakery'"
    try:
        args = json.loads(fn.get("arguments") or "{}")
    except Exception:
        return False, "arguments were not JSON"
    if "brief" not in args:
        return False, "arguments missing the required 'brief'"
    bad = [k for k, v in args.items()
           if k != "size" and v is None]           # the null bug, live
    if bad:
        return False, f"null in optional field(s) {bad}"
    return True, "tool call valid"


def main():
    if not KEY:
        raise SystemExit("ORCAROUTER_API_KEY is not in the environment")
    print("Orca Router free models, against the game's real tool schema:\n")
    winners = []
    for m in MODELS:
        d, secs, err = call(m)
        ok, why = tool_call_ok(d) if not err else (False, err)
        u = (d or {}).get("usage", {})
        pt = u.get("prompt_tokens", "?")
        ct = u.get("completion_tokens", "?")
        tag = "WORKS" if ok else "no  "
        print(f"  [{tag}] {m:36s} {secs:5.1f}s  in={pt} out={ct}")
        print(f"          {why}")
        if ok:
            winners.append((m, pt, ct, secs))
        time.sleep(2)

    print()
    if not winners:
        print("None of the free models can hold the tool schema. The game")
        print("cannot be tested against this provider as it stands.")
        return 1
    # Cheapest prompt wins: a fourteen-case matrix at 3,400 tokens a plan is
    # 48,000 tokens, which is what exhausted the 200,000 daily budget at
    # Groq once the retries were counted.
    winners.sort(key=lambda w: (w[1] if isinstance(w[1], int) else 10**9))
    best = winners[0]
    print(f"best: {best[0]}  ({best[1]} in / {best[2]} out, {best[3]:.1f}s)")
    if isinstance(best[1], int):
        print(f"a 14-case matrix at this size is about "
              f"{best[1] * 14:,} prompt tokens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
