"""Re-run only the cases a previous run could not test.

The first full matrix stopped at 4 of 14 because the gateway ran out of daily
tokens, not because the other ten were broken. This retries exactly the ones
that were blocked, so a fresh budget is spent on gaps rather than repeating
what already worked.

    python _tools/retry_blocked.py            # everything that was blocked
    python _tools/retry_blocked.py chat       # one category

Spacing matters more here than anywhere else in the tooling: a planning prompt
is about 3,400 tokens against a 200,000 daily budget, so five back to back
gets through and six does not. The wait is set from the gateway's own retry
hint when it sends one.
"""
import json
import re
import subprocess
import sys
import time

ROOT = r"C:\Users\vedan\Desktop\Projects\kingdom-city"
GODOT = r"C:\Users\vedan\Tools\godot\godot_console.exe"
RESULTS = r"C:\Users\vedan\kc_refs\task_results.json"
MERGED = r"C:\Users\vedan\kc_refs\task_results_merged.json"


def blocked(r):
    """True when the gateway, not the game, stopped this case."""
    if r.get("ok") and (r.get("line") or "").strip():
        return False
    blob = " ".join(str(r.get(k, "")) for k in ("line", "why_harness", "cause"))
    return bool(re.search(
        r"429|rate limit|tokens per (minute|day)|token budget|"
        r"rate limited|gateway error", blob, re.I))


def run_one(say, cat, timeout_s=200):
    cmd = [GODOT, "--path", ROOT, "--rendering-driver", "vulkan",
           "--resolution", "800x450", "--",
           "--tasktest", f'--say={say}', "--nofar", "--nosave"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout_s, errors="replace")
    except subprocess.TimeoutExpired:
        return {"ok": False, "say": say, "cat": cat, "line": "",
                "why_harness": "process outlived its timeout",
                "cause": "harness timeout", "seconds": 0.0}
    blob = (p.stdout or "") + (p.stderr or "")

    line = ""
    for m in re.finditer(r"^\[task\]\s+\[(?:ok|FAIL)\]\s+\S+\s+(.*?)\s{2,}"
                         r"([\d.]+)s\s*(.*)$", blob, re.M):
        line = m.group(3).strip()
        secs = float(m.group(2))
        break
    else:
        secs = 0.0

    ok = "[ok]" in blob and "=== PASS ===" in blob
    cause = ""
    for pat, tag in [
        (r"tokens per day", "daily token budget spent"),
        (r"tokens per minute", "per-minute token budget spent"),
        (r"http=(429)", "rate limited"),
        (r"http=(400)[^\n]*(expected string|not in request\.tools)", "schema rejected"),
        (r"http=(\d{3})", "gateway error"),
    ]:
        m = re.search(pat, blob, re.I)
        if m:
            cause = f"{tag} (http={m.group(1)})" if m.groups() else tag
            break
    if not ok and not cause:
        m = re.search(r"\[llm\][^\n]{0,120}", blob)
        if m:
            cause = m.group(0)[:110]
    return {"ok": ok, "say": say, "cat": cat, "line": line,
            "why_harness": "" if ok else cause, "cause": cause,
            "seconds": secs}


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    prev = json.load(open(RESULTS))
    todo = [r for r in prev if blocked(r) and (not only or r["cat"] == only)]

    print(f"{len(todo)} case(s) were blocked by the gateway; retrying those.\n")
    results = []
    for i, r in enumerate(todo, 1):
        print(f"  ({i}/{len(todo)}) {r['cat']:11s} {r['say'][:40]}", flush=True)
        n = run_one(r["say"], r["cat"])
        results.append(n)
        tail = n["line"] or n["cause"] or "(silent)"
        print(f"        -> {'ok  ' if n['ok'] else 'FAIL'} {tail[:76]}", flush=True)

        merged = {x["say"]: x for x in prev}
        merged[r["say"]] = n
        json.dump(list(merged.values()), open(MERGED, "w"), indent=1)
        json.dump(list(merged.values()), open(RESULTS, "w"), indent=1)

        # A prompt that came back rate-limited is retried on the clock the
        # gateway asked for, not on a guess. Otherwise, 20s: long enough that
        # the 8k/minute tier has room for the next one.
        wait = 20
        m = re.search(r"try again in\s*([\d.]+)", n.get("cause", "") or "")
        if m:
            wait = max(20, min(300, float(m.group(1)) + 5))
        elif n["ok"]:
            wait = 25
        print(f"        waiting {wait:.0f}s\n", flush=True)
        time.sleep(wait)

    ok = sum(1 for r in results if r["ok"])
    print(f"\n{ok}/{len(results)} of the blocked cases now worked")
    print(f"merged -> {MERGED}")


if __name__ == "__main__":
    main()
