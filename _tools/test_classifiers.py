"""Unit tests for the classifiers that decide what a failure *was*.

These two functions decide whether a number on the QA page means the game is
broken or the gateway ran out of budget. Getting one wrong in either direction
is the failure mode this whole harness keeps hitting, so they are tested
directly rather than inferred from a full run.

    python _tools/test_classifiers.py
"""
import importlib.util
import sys

RUN = r"C:\Users\vedan\Desktop\Projects\kingdom-city\_tools\run_tasks.py"
PAGE = r"C:\Users\vedan\Desktop\Projects\kingdom-city\_tools\build_task_page.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rt = load(RUN, "run_tasks")
pg = load(PAGE, "build_task_page")

# (cause, is_the_daily_budget_gone)
SPENT = [
    ("daily token budget spent", True),
    ("daily token budget spent (http=429)", True),
    ("tokens per day", True),
    ("Rate limit reached ... tokens per day (TPD): Limit 200000", True),
    ("per-minute token budget spent (http=429)", False),
    ("rate limited (http=429)", False),
    ("schema rejected (http=400)", False),
    ("gateway error (http=503)", False),
    ("", False),
    (None, False),
]

# (record, expected status)
VERDICTS = [
    ({"ok": True, "line": "Written down."}, "pass"),
    ({"ok": True, "line": pg.AMBIENT}, "fail"),
    ({"ok": False, "line": "", "cause": "daily token budget spent"}, "gateway"),
    ({"ok": False, "line": "", "cause": "per-minute token budget spent (http=429)"},
     "gateway"),
    ({"ok": False, "line": "", "cause": "schema rejected (http=400)"}, "fail"),
    ({"ok": False, "line": "", "cause": "missingfn: Nonexistent function 'handle'"},
     "fail"),
    ({"ok": False, "line": "", "cause": ""}, "fail"),
    # A pass carrying no visible line is not a pass.
    ({"ok": True, "line": ""}, "fail"),
]

fails = 0
print("budget_is_spent -- did the daily budget run out?")
for cause, want in SPENT:
    got = rt.budget_is_spent(cause)
    ok = got == want
    fails += 0 if ok else 1
    print(f"  [{'OK ' if ok else 'FAIL'}] {str(cause)[:48]:50s} {got}")

print("\nverdict -- what does the page call it?")
for rec, want in VERDICTS:
    got, _why = pg.verdict(rec)
    ok = got == want
    fails += 0 if ok else 1
    label = str(rec.get("cause") or rec.get("line", ""))[:40]
    print(f"  [{'OK ' if ok else 'FAIL'}] {label:42s} {got:8s} want {want}")

print()
print("ALL PASS" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
