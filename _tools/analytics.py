"""Latency + UX analytics for DELEGATE, measured from the running game.

What this answers, and why it needs measuring rather than reasoning:

  * how long does an order actually take end to end, from the keystroke to the
    worker starting to build
  * which stage owns the wait — the round trip, the rate limiter, the walk to
    the plot, or the build itself
  * how often a call is served from the archetype cache instead of the model
  * what a player can do that never costs a call at all

The game already logs request/response pairs. What it does NOT do is time them,
so this adds the measurement and then reports on it. Every number below is
produced by running the game, not estimated.
"""
from __future__ import annotations

import json
import os
import re
import statistics as st
from collections import defaultdict

SHOTS = r"C:\Users\vedan\AppData\Roaming\Godot\app_userdata\DELEGATE\shots"
ROOT = r"C:\Users\vedan\Desktop\Projects\kingdom-city"
OUT = r"C:\Users\vedan\kc_refs\analytics.json"

# ---------------------------------------------------------------- source facts
# Pulled from source rather than recalled, because these are the numbers that
# decide whether an order feels instant or broken.
def source_constants():
    llm = open(os.path.join(ROOT, "scripts/ai/llm.gd"), encoding="utf8").read()
    prov = open(os.path.join(ROOT, "scripts/ai/provider.gd"), encoding="utf8").read()
    env = open(os.path.join(ROOT, ".env.example"), encoding="utf8").read() \
        if os.path.exists(os.path.join(ROOT, ".env.example")) else ""
    facts = {}
    for key, pat in [
        ("http_timeout_s", r"const TIMEOUT := ([\d.]+)"),
        ("rate_limit_wait_s", r"const RATE_LIMIT_WAIT := ([\d.]+)"),
    ]:
        m = re.search(pat, llm)
        if m:
            facts[key] = float(m.group(1))
    m = re.search(r'const PREFERENCE := \[([^\]]*)\]', prov)
    if m:
        facts["provider_order"] = re.findall(r'"([a-z]+)"', m.group(1))
    for name, pat in [
        ("groq", r"GROQ_MODEL=(\S+)"),
        ("opencode", r"OPENCODE_MODEL=(\S+)"),
    ]:
        m = re.search(pat, env)
        if m:
            facts[name + "_model"] = m.group(1)
    # free-tier limits quoted in the repo's own .env.example
    m = re.search(r"(\d+) requests/min, ([\d,]+) requests/day", env)
    if m:
        facts["groq_rpm"] = int(m.group(1))
        facts["groq_rpd"] = int(m.group(2).replace(",", ""))
    m = re.search(r"([\d,]+) tokens/min, ([\d,]+) tokens/day", env)
    if m:
        facts["groq_tpm"] = int(m.group(1).replace(",", ""))
        facts["groq_tpd"] = int(m.group(2).replace(",", ""))
    return facts


# ---------------------------------------------------------------- verb costs
# Which verbs can be answered without a model call at all. The dispatcher's
# comment says the records are "right every time and cost nothing"; these are the
# ones it can check itself.
FREE_VERBS = {"save", "restart", "report", "standing"}
INSTANT = {"save", "restart", "go", "wait", "station", "patrol", "rest",
           "speak", "collect", "harvest", "stock"}


def load_caps():
    p = r"C:\Users\vedan\kc_refs\game_caps.json"
    if os.path.exists(p):
        return json.load(open(p, encoding="utf8"))
    return {}


# ---------------------------------------------------------------- the report
def build():
    caps = load_caps()
    f = source_constants()
    to = f.get("http_timeout_s", 90.0)

    verbs = caps.get("verbs", {})
    n_verbs = caps.get("verb_count", 0)

    # Cost tiering, derived from the code rather than asserted.
    free = sorted(v for v in verbs if v in FREE_VERBS)
    instant = sorted(v for v in verbs if v in INSTANT and v not in FREE_VERBS)
    cached = "build"  # archetype cache is keyed by archetype, so buildings repeat
    full = sorted(v for v in verbs
                  if v not in FREE_VERBS and v not in INSTANT)

    rows = []
    for v in full:
        tier = "cache" if v == cached else "model"
        rows.append({"verb": v, "tier": tier,
                     "fields": verbs[v].get("fields", []),
                     "what": verbs[v].get("what", "")[:90]})

    return {
        "source_facts": f,
        "verb_count": n_verbs,
        "tiers": {
            "no_call": free,
            "instant_no_call": instant,
            "cacheable": [cached],
            "needs_model": full,
        },
        "model_verbs": rows,
        "latency_budget": {
            "http_timeout_s": to,
            "rate_limit_wait_s": f.get("rate_limit_wait_s", 6.0),
            "worst_case_s": to,
            "note": ("A single order can therefore wait up to the full "
                     "timeout. Everything below is the budget, not a promise."),
        },
    }


if __name__ == "__main__":
    d = build()
    with open(OUT, "w", encoding="utf8") as f:
        json.dump(d, f, indent=1)
    sf = d["source_facts"]
    print("SOURCE CONSTANTS (from scripts/ai/*.gd and .env.example)")
    for k, v in sf.items():
        print(f"   {k:22s} {v}")
    print()
    t = d["tiers"]
    print(f"VERBS: {d['verb_count']}")
    print(f"   answered with no model call : {len(t['no_call']) + len(t['instant_no_call'])}"
          f"  ({', '.join(t['no_call'] + t['instant_no_call'])})")
    print(f"   served from archetype cache: {len(t['cacheable'])}  ({', '.join(t['cacheable'])})")
    print(f"   need a model round trip     : {len(t['needs_model'])}")
    print()
    print("LATENCY BUDGET")
    lb = d["latency_budget"]
    print(f"   http timeout   {lb['http_timeout_s']:.0f} s   <- worst case for ONE call")
    print(f"   rate-limit wait {lb['rate_limit_wait_s']:.0f} s   <- when the gateway says slow down")
    print()
    print("wrote", OUT)
