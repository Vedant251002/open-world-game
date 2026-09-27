"""Ask the gateway how much budget is actually left, at the size the game uses.

A 'hi' probe is misleading: it costs 77 tokens and succeeds while a real plan
prompt costing 2,900 is refused. Twice now a cheap probe said "quota reset" and
the matrix immediately failed on 429. So this sends a prompt of roughly the
size the game sends, and reports the tokens the gateway counted, so the answer
is about the real workload and not a toy one.

    python _tools/quota.py
"""
import json
import os
import urllib.error
import urllib.request

ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
MODEL = os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b")

# Roughly what the planner sends: the town's context, the rules, and the
# player's sentence. The count is printed back so the estimate is checkable.
FILLER = ("The town has a well, a field, a smithy, a bakery and a store. "
          "Mira keeps the store, Tobias builds, Ren farms. " * 170)


def probe(label, user_text, max_tokens=40):
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "You plan building work."},
            {"role": "user", "content": user_text},
        ],
        "max_tokens": max_tokens,
    }
    req = urllib.request.Request(
        ENDPOINT, data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + os.environ["GROQ_API_KEY"],
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            d = json.load(r)
        u = d.get("usage", {})
        print(f"  {label:18s} OK   prompt_tokens={u.get('prompt_tokens')}")
        return True
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            msg = json.loads(raw).get("error", {}).get("message", "")
        except Exception:
            msg = raw[:200]
        print(f"  {label:18s} http={e.code}  {msg[:190]}")
        return False
    except Exception as e:
        print(f"  {label:18s} {type(e).__name__}: {str(e)[:150]}")
        return False


if __name__ == "__main__":
    print("quota, measured at the size the game actually sends:\n")
    probe("tiny (77 tok)", "hi")
    print()
    probe("planner-sized", FILLER + "\n\nBuild me a bakery facing the square.")
    print("\nA tiny probe succeeding while the planner-sized one is refused is "
          "the normal state of\na nearly-spent daily budget, not a reset.")
    print("\nIf urllib is refused with 403 'error code: 1010' that is "
          "Cloudflare refusing\nthis script's user agent, not the gateway's "
          "quota -- rerun through\ncurl, which is the path the game itself "
          "uses and the one that works.")
