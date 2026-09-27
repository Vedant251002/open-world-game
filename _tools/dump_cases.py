"""Dump CASES from scripts/dev/task_test.gd to JSON.

The sentences live in GDScript because the engine needs them; this reads them
out so _tools/run_tasks.py can drive one process per case without the two
lists drifting apart. Parsed rather than hand-copied on purpose -- a hand copy
is a second source of truth that will disagree with the harness the first time
someone edits a sentence.

The categories are the real ones: the five groups the 45 verbs fall into in
steps.gd, plus the four kinds of reply the model can give and the meta order
that never touches a model. The counts are checked against CASES so a mismatch
fails loudly instead of quietly testing fewer things than it claims.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "scripts", "dev", "task_test.gd")
# kc_refs is C:/Users/vedan/kc_refs, not a sibling of the project.
OUT = r"C:\Users\vedan\kc_refs\task_cases.json"

text = open(SRC, encoding="utf-8").read()
start = text.index("const CASES := [")
end = text.index("\n]\n", start)
body = text[start:end]

# Each case is a dict literal spanning lines; grab the fields by name.
cases = []
for m in re.finditer(
    r'\{\s*"cat":\s*"([^"]+)",\s*"say":\s*"([^"]+)"(.*?)\},(?=\s*\n|$)',
    body, re.S,
):
    cat, say, rest = m.group(1), m.group(2), m.group(3)

    def field(name, default=""):
        mm = re.search(rf'"{name}":\s*"([^"]*)"', rest)
        return mm.group(1) if mm else default

    cases.append({
        "cat": cat, "say": say,
        "want": field("want", "any"),
        "check": field("check", "spoke_any"),
        "why": field("why"),
    })

# "why" is the one field allowed to continue with `+ "..."`, which the
# per-case regex above stops before. Re-join those.
for m in re.finditer(r'"why":\s*"([^"]*)"\s*\n\s*\+\s*"([^"]*)"', body):
    joined = m.group(1) + m.group(2)
    for c in cases:
        if c["why"] and c["why"] in m.group(1) and c["why"] != joined:
            c["why"] = joined

if not cases:
    raise SystemExit("no cases parsed -- the CASES shape in task_test.gd changed")

json.dump(cases, open(OUT, "w"), indent=1)

by_cat = {}
for c in cases:
    by_cat.setdefault(c["cat"], []).append(c["say"])
print(f"{len(cases)} cases -> {OUT}")
for k, v in by_cat.items():
    print(f"  {k:11s} {len(v)}")
