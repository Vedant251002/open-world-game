"""Run every task case in its OWN Godot process and merge the JSON.

Why one process per case, when --tasktest already runs them in sequence: the
first sequenced run reported 11/14 and that number was wrong twice over. Cases
shared one Dispatcher, so a rate-limit or a dropped connection in case 3 left
cases 4-14 reading a broken harness and all nine came back "(silent)" in 0.3s.
Then a second run of the same matrix gave 3/14. Neither is a measurement of the
game; both are a measurement of accumulated state.

A process per case removes the contamination: each case gets a fresh crew, a
fresh world and a fresh connection, and a gateway failure in one case cannot be
misreported as a game failure in the next. It also matches the rate limit --
one prompt's worth of tokens per process, spaced, rather than fourteen back to
back against an 8k tokens/min tier.

Usage:
    python _tools/run_tasks.py              # all cases
    python _tools/run_tasks.py build        # one category
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:\Users\vedan\Tools\godot\godot_console.exe"
OUT = r"C:\Users\vedan\kc_refs\task_results.json"

# The categories, in the order they are run. The sentences live in
# scripts/dev/task_test.gd (CASES) so the harness and this stay in step; this
# list only says how many to expect back and how long to allow.
GROUPS = [
    ("meta", 1),          # cheapest: no model call at all
    ("chat", 1),
    ("answer", 3),
    ("refuse", 2),
    ("people", 2),
    ("correction", 1),
    ("question", 1),
    ("build", 3),         # most expensive: a full plan each
]

TONE = {"build": "foreman", "answer": "clerk", "refuse": "clerk",
        "people": "clerk", "chat": "clerk", "meta": "clerk",
        "correction": "foreman", "question": "foreman"}


def run_one(idx, total, case_id, say, timeout_s=200):
    """One case, one process. Returns the parsed [task] line, or a dict
    describing why there wasn't one."""
    env = dict(os.environ)
    cmd = [
        GODOT, "--path", ROOT, "--rendering-driver", "vulkan",
        "--resolution", "800x450", "--",
        "--tasktest", f'--say={say}', "--nofar", "--nosave",
    ]
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout_s, env=env,
            errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "say": say, "cat": case_id, "why_harness":
                "the process outlived its timeout", "line": "", "seconds": 0.0}

    blob = (p.stdout or "") + (p.stderr or "")
    # The user-facing line the harness prints, minus the cat/say columns.
    line = ""
    for m in re.finditer(r"^\[task\]\s+\[(?:ok|FAIL)\]\s+\S+\s+(.*?)\s{2,}"
                         r"([\d.]+)s\s*(.*)$", blob, re.M):
        line = m.group(3).strip()
        break

    # What actually happened underneath, for a failure that came back silent.
    detail = ""
    for pat, tag in [
        (r"http=(\d+)\s*([^\n]*)", "http"),
        (r"rate limit[^\n]{0,90}", "ratelimit"),
        (r"property '(\w+)' is unsupported", "badfield"),
        (r"Nonexistent function '(\w+)'", "missingfn"),
    ]:
        m = re.search(pat, blob, re.I)
        if m:
            detail = f"{tag}: {m.group(0)[:100]}"
            break
    if not detail:
        m = re.search(r"^\[(?!task|delegate|ai)\w+\].{0,90}", blob, re.M)
        if m:
            detail = m.group(0)[:100]

    ok = "[ok]" in blob and "=== PASS ===" in blob
    # A case that returned nothing at all still has a cause underneath, and
    # that cause decides how the page reports it. "no reply, no reason" in the
    # harness output is not the same as a worker that stayed quiet; one is a
    # gateway that never answered, the other is a game that dropped the order.
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
    return {
        "ok": ok, "say": say, "cat": case_id, "line": line,
        "why_harness": detail if not ok else "",
        "cause": cause,
        "seconds": 0.0,
        "tone": TONE.get(case_id, "clerk"),
    }


# A daily budget that is gone does not come back within a run. Once the
# gateway says the day is spent, every later case in the same run is guaranteed
# to fail the same way, so the run stops and says so instead of spending ten
# more 45-second timeouts to learn it ten more times. The daily figure is
# checked before the per-minute one: a per-minute refusal clears in seconds and
# is worth waiting out, a daily one needs tomorrow.
#
# Both wordings are matched. The gateway sends "tokens per day" and the cause
# this file writes is "daily token budget spent", and the first version of this
# matched only the former -- so the run never stopped, which is the one thing
# it exists to do. A unit test covers the pair.
SPENT_FOR_TODAY = re.compile(r"tokens per day|daily token budget", re.I)


def budget_is_spent(cause):
    return bool(cause) and bool(SPENT_FOR_TODAY.search(cause))


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    cases = json.load(open(r"C:\Users\vedan\kc_refs\task_cases.json"))
    results = []
    total = sum(n for _c, n in GROUPS if not only or _c == only)
    n = 0
    for cat, count in GROUPS:
        if only and cat != only:
            continue
        for c in cases:
            if c["cat"] != cat:
                continue
            n += 1
            print(f"  ({n}/{total}) {cat:11s} {c['say'][:44]:46s}", flush=True)
            r = run_one(n, total, cat, c["say"])
            r["why"] = c.get("why", "")
            r["kind"] = c.get("check", "")
            results.append(r)
            mark = "ok  " if r["ok"] else "FAIL"
            tail = r["line"] or r["why_harness"] or "(no reply)"
            print(f"        -> {mark} {tail[:80]}", flush=True)
            # Written after every case, not at the end: the first version of
            # this script lost a four-minute run to a regex error on line 40
            # and had nothing to show for it.
            json.dump(results, open(OUT, "w"), indent=1)

            if budget_is_spent(r.get("cause", "")):
                # Everything still queued is now known to be untestable
                # today, so it is left unrecorded rather than written down
                # as a failure: nothing was tested, and a failure implies
                # the town got something wrong.
                left = len(cases) - len(results)
                print(f"\n  The gateway says today's budget is spent, so "
                      f"the {left} case(s) still queued cannot run today.\n"
                      f"  They are left unrecorded rather than written "
                      f"down as failures.\n"
                      f"  Run retry_blocked.py when it resets.", flush=True)
                break
            # The free tier is 8k tokens/min. A planning prompt is a few
            # thousand of them, so spacing is not politeness, it is the only
            # way the later cases are not all rate-limit failures.
            if cat == "build":
                time.sleep(35)
            else:
                time.sleep(8)

    json.dump(results, open(OUT, "w"), indent=1)
    ok = sum(1 for r in results if r["ok"])
    print(f"\n{ok}/{len(results)} ok -> {OUT}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
