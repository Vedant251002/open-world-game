"""What the AI costs, per thing a player does and per session.

Joins the gateway log written by _tools/mock_gateway.py with the step stamps
written by `--costrun`, and prints and saves a cost model:

    python _tools/token_report.py --calls calls.jsonl --steps cost_run.json \
        --out token_report.json

Input tokens are measured: they are exactly what the game sent. Output tokens
are not -- the mock writes a short stand-in reply -- so they are modelled from
each call's purpose and its cap (see OUTPUT_EST), with a low and a high case.
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict

# Output tokens a real gpt-oss-120b reply is expected to use, per call kind:
# (low, typical, high). The high case is the cap the game sets. gpt-oss reasons
# before answering and the reasoning is billed as output, which is why a plan
# is far above the length of the tool call it ends in.
OUTPUT_EST = {
    "plan": (150, 450, 3200),      # tool call ~80-250 + medium reasoning
    "talk": (40, 110, 260),        # a line or two + low reasoning
    "answer": (40, 100, 220),
    "text": (250, 420, 600),       # role composition / foreman's round
}

# USD per million tokens (input, output), checked September 2026.
PRICES = {
    "groq gpt-oss-120b": (0.15, 0.60),
    "groq gpt-oss-20b": (0.075, 0.30),
}
# Groq free plan for gpt-oss-120b, from .env.example.
FREE_TPM, FREE_TPD, FREE_RPD = 8_000, 200_000, 1_000


def load(calls_path: str, steps_path: str):
    calls = [json.loads(l) for l in open(calls_path, encoding="utf8") if l.strip()]
    calls = [c for c in calls if not str(c.get("kind", "")).startswith("fail")]
    steps = json.load(open(steps_path, encoding="utf8"))
    return calls, steps


def assign(calls, steps):
    """Each call belongs to the step whose window it fell in."""
    out = defaultdict(list)
    for c in calls:
        owner = None
        for s in steps:
            t1 = s.get("t1", s["t0"] + 60)
            if s["t0"] - 0.5 <= c["t"] <= t1 + 0.5:
                owner = s["i"]
        out[owner].append(c)
    return out


def est_out(kind: str, which: int) -> int:
    return OUTPUT_EST.get(kind, OUTPUT_EST["talk"])[which]


def cost(inp: int, out: int, price) -> float:
    return inp / 1e6 * price[0] + out / 1e6 * price[1]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--calls", required=True)
    ap.add_argument("--steps", required=True)
    ap.add_argument("--out", default="token_report.json")
    a = ap.parse_args()
    calls, steps = load(a.calls, a.steps)
    by_step = assign(calls, steps)

    rows = []
    for s in steps:
        cs = by_step.get(s["i"], [])
        inp = sum(c["prompt_tokens"] for c in cs)
        out_t = sum(est_out(c["kind"], 1) for c in cs)
        out_h = sum(est_out(c["kind"], 2) for c in cs)
        rows.append({
            "i": s["i"], "kind": s["kind"], "say": s["say"], "calls": len(cs),
            "call_kinds": [c["kind"] for c in cs], "input": inp,
            "output_typical": out_t, "output_cap": out_h,
            "usd_120b_typical": cost(inp, out_t, PRICES["groq gpt-oss-120b"]),
        })

    per_kind = defaultdict(lambda: {"n": 0, "input": 0, "max": 0, "parts": defaultdict(int)})
    for c in calls:
        k = per_kind[c["kind"]]
        k["n"] += 1
        k["input"] += c["prompt_tokens"]
        k["max"] = max(k["max"], c["prompt_tokens"])
        for p, v in c.get("parts", {}).items():
            k["parts"][p] += v

    total_in = sum(c["prompt_tokens"] for c in calls)
    total_out = {w: sum(est_out(c["kind"], i) for c in calls)
                 for i, w in enumerate(["low", "typical", "high"])}

    print(f"{'#':>2} {'kind':10} {'calls':>5} {'input':>7} {'out~':>6} {'$ 120b':>9}  said")
    for r in rows:
        print(f"{r['i']:>2} {r['kind']:10} {r['calls']:>5} {r['input']:>7} "
              f"{r['output_typical']:>6} {r['usd_120b_typical']:>9.6f}  {r['say'][:48]}")
    print()
    print(f"{'call kind':8} {'n':>3} {'avg in':>7} {'max in':>7}  where the input goes (avg)")
    for kind, k in sorted(per_kind.items(), key=lambda x: -x[1]["input"]):
        parts = ", ".join(f"{p} {v // k['n']}" for p, v in k["parts"].items() if v)
        print(f"{kind:8} {k['n']:>3} {k['input'] // k['n']:>7} {k['max']:>7}  {parts}")
    print()
    n_steps = len(steps)
    print(f"session: {n_steps} player actions, {len(calls)} model calls, "
          f"{total_in} input tokens, output ~{total_out['typical']} "
          f"({total_out['low']}-{total_out['high']})")
    for name, price in PRICES.items():
        lo = cost(total_in, total_out["low"], price)
        ty = cost(total_in, total_out["typical"], price)
        hi = cost(total_in, total_out["high"], price)
        print(f"  {name:20s} ${ty:.4f} per session  (${lo:.4f} - ${hi:.4f})")

    report = {
        "steps": rows,
        "per_kind": {k: {"n": v["n"], "avg_input": v["input"] // v["n"], "max_input": v["max"],
                         "avg_parts": {p: x // v["n"] for p, x in v["parts"].items()}}
                     for k, v in per_kind.items()},
        "session": {"actions": n_steps, "calls": len(calls), "input": total_in,
                    "output": total_out},
        "prices_usd_per_m": PRICES, "output_estimates": OUTPUT_EST,
        "free_plan": {"tpm": FREE_TPM, "tpd": FREE_TPD, "rpd": FREE_RPD},
    }
    json.dump(report, open(a.out, "w"), indent=2)
    print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
