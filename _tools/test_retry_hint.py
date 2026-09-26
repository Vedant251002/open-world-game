"""Test retry_hint_seconds() against the real 429 bodies gateways send.

The parser is the one piece of new logic that can be wrong in a way that
matters: too short and the retry is refused, too long and the player waits for
nothing. So it is tested against strings captured from the live API, not
against what the regex was written for.
"""
import re
import sys

# Captured verbatim from Groq during the --aitest runs, and the structured
# shapes other gateways in the wild are documented to use.
CASES = [
    # (raw body, expected seconds, label)
    ('{"error":{"message":"Rate limit reached for model `openai/gpt-oss-120b` in organization `org_x` service tier `on_demand` on tokens per minute (TPM): Limit 8000, Used 5953, Requested 6704. Please try again in 34.9275s. Need more tokens? Upgrade to Dev Tier today at https://console.groq.com/settings/billing","type":"rate_limit_error"}}',
     34.9275, "groq 34.9275s"),
    ('{"error":{"message":"Rate limit reached ... Please try again in 7.5825s."}}',
     7.5825, "groq 7.58s"),
    ('{"error":{"message":"... Please try again in 0.4312s."}}',
     0.4312, "groq sub-second"),
    ('{"error":{"message":"Rate limit reached"}}',
     0.0, "no hint in prose"),
    ('{"error":{"message":"slow down","retry_after":12.5}}',
     12.5, "structured retry_after"),
    ('{"error":{"message":"slow down","retry_after_seconds":30}}',
     30.0, "structured retry_after_seconds"),
    ('{"error":{"message":"slow","metadata":{"retry_after":5}}}',
     5.0, "nested metadata"),
    ('{"error":{"message":"please retry-after 8s"}}',
     8.0, "retry-after prose"),
    ('{"error":{"message":"property \'reasoning\' is unsupported"}}',
     0.0, "unrelated error"),
    ('{"error":{"message":"Rate limit reached ... Please try again in 120s."}}',
     120.0, "large hint (capped later, not here)"),
    ('', 0.0, "empty body"),
    ('not json at all', 0.0, "garbage"),
]


def retry_hint_seconds(raw: str) -> float:
    """Mirror of the GDScript implementation, for testing outside the engine."""
    raw = raw.strip()
    if raw.startswith("{"):
        try:
            import json
            d = json.loads(raw)
        except Exception:
            d = None
        if isinstance(d, dict):
            err = d.get("error", {})
            if isinstance(err, dict):
                for key in ("retry_after", "retry_after_seconds", "retry_delay"):
                    if key in err:
                        v = float(err[key])
                        if v > 0.0:
                            return v
                meta = err.get("metadata", {})
                if isinstance(meta, dict):
                    for key in ("retry_after", "retry_after_seconds"):
                        if key in meta:
                            v = float(meta[key])
                            if v > 0.0:
                                return v
    m = re.search(r"try again in\s*([0-9]+(?:\.[0-9]+)?)\s*s?", raw, re.I)
    if m:
        return max(0.0, float(m.group(1)))
    m2 = re.search(r"retry[- ]after\s*([0-9]+(?:\.[0-9]+)?)\s*s?", raw, re.I)
    if m2:
        return max(0.0, float(m2.group(1)))
    return 0.0


fails = 0
for raw, want, label in CASES:
    got = retry_hint_seconds(raw)
    ok = abs(got - want) < 0.001
    if not ok:
        fails += 1
    print(f"  [{'OK ' if ok else 'FAIL'}] {label:42s} want={want:<10} got={got}")

print()
print("ALL PASS" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
