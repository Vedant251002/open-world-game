"""Which free model has capacity right now?

The router's free tier is full, which is not the same as a token budget: there
is no number in the refusal and no time to wait it out. Three models were
verified to hold the tool schema earlier today, so when the one in use is full
the question is whether any of the others is open -- and the answer changes
hour to hour, so it is asked rather than assumed.

Each probe is a real tool-schema call at roughly the size the planner sends,
because a model can be idle for chatter and full for a 2,000-token plan.

    python _tools/pick_model.py
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = "https://api.orcarouter.ai/v1/chat/completions"
KEY = os.environ.get("ORCAROUTER_API_KEY", "")

SCHEMA = {
    "type": "function",
    "function": {
        "name": "bakery",
        "description": "put up, redesign or extend a building",
        "parameters": {
            "type": "object",
            "properties": {
                "brief": {"type": "string"},
                "material": {"type": "string",
                             "enum": ["timber", "plank", "stone", "brick"]},
                "size": {"type": "array", "minItems": 2, "maxItems": 2,
                         "items": {"type": "integer"}},
            },
            "required": ["brief"],
        },
    },
}

# The town context the planner really sends, so the probe is the same shape of
# work rather than a toy.
FILLER = ("The town has a well, a field, a smithy, a bakery and a store. "
          "Mira keeps the store, Tobias builds, Ren farms. " * 60)

MODELS = [
    "z-ai/glm-5.3-flash-free",
    "tencent/hy3-free",
    "deepseek/deepseek-v4-flash-free",
]


def probe(model, planner_shaped=True, timeout=90):
    user = (FILLER + "\n\nBuild me a bakery facing the square."
            if planner_shaped else "Build me a bakery facing the square.")
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content":
                "You plan building work for a village. You act by calling "
                "a tool."},
            {"role": "user", "content": user},
        ],
        "tools": [SCHEMA],
        "tool_choice": "auto",
        "max_tokens": 700,
    }
    req = urllib.request.Request(
        ENDPOINT, data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + KEY,
                 "Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            msg = json.loads(raw).get("error", {}).get("message", raw[:120])
        except Exception:
            msg = raw[:120]
        return {"model": model, "state": "refused", "why": msg[:110],
                "secs": time.time() - t0}
    except Exception as e:
        return {"model": model, "state": "error", "why": str(e)[:90],
                "secs": time.time() - t0}

    msg = (d.get("choices") or [{}])[0].get("message", {})
    calls = msg.get("tool_calls") or []
    u = d.get("usage", {})
    return {
        "model": model,
        "state": "works" if calls else "no tool call",
        "why": calls[0].get("function", {}).get("name", "") if calls
        else "answered in prose",
        "in": u.get("prompt_tokens", "?"), "out": u.get("completion_tokens", "?"),
        "secs": time.time() - t0,
    }


def main():
    if not KEY:
        raise SystemExit("ORCAROUTER_API_KEY is not in the environment")
    print("free models, probed with a planner-sized request:\n")
    usable = []
    for m in MODELS:
        r = probe(m)
        tag = {"works": "WORKS", "refused": "full ", "no tool call": "NOTOOL",
               "error": "ERROR"}.get(r["state"], "?")
        print(f"  [{tag}] {m:34s} {r['secs']:5.1f}s  {r['why'][:70]}")
        if r["state"] == "works":
            usable.append((m, r.get("in", 0)))
        time.sleep(2)

    print()
    if not usable:
        print("None of the free models are taking requests right now.")
        print("This is a capacity pause, not a budget: it clears on its own,")
        print("and retrying in a few minutes is the right move rather than")
        print("treating it as a broken game.")
        return 1
    usable.sort(key=lambda x: x[1] if isinstance(x[1], int) else 10**9)
    print(f"use: --provider=orcarouter and set ORCAROUTER_MODEL="
          f"{usable[0][0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
