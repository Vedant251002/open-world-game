"""Run each player case in its own process, and check for cross-case bleed.

The sequenced run inside one Godot process reported nineteen identical replies
for nineteen different sentences -- always the same worker, always the same
line. Run the same three sentences one process each and every reply is
different and correct:

    asdfghjkl                  "Ha! That sounds like the cat walked across
                                the table. Morning to you -- what would you
                                like built..."
    build a space elevator     "I am grey and weak."
    you are useless and I hate you
                               "I'm sorry you feel that way -- I only want to
                                do right by you..."

So the game is fine and the shared process is not: a worker's reply outlives
its case, and the town is still talking between them. Per-process removes the
possibility rather than trying to time it, and it is how the task matrix
already works.

It also checks for repetition deliberately, because identical replies to
identical input would be a different bug entirely -- a cached line mistaken
for a live one.

    python _tools/run_player.py
    python _tools/run_player.py hostile
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = r"C:\Users\vedan\Desktop\Projects\kingdom-city"
GODOT = r"C:\Users\vedan\Tools\godot\godot_console.exe"
OUT = r"C:\Users\vedan\kc_refs\player_results.json"
PROVIDER = "orcarouter"

ORDER = ["nonsense", "empty", "hostile", "impossible", "repeat", "long", "rapid"]


def parse_cases():
    """Read CASES out of the GDScript, so the two cannot disagree."""
    src = open(os.path.join(ROOT, "scripts", "dev", "player_test.gd"),
               encoding="utf-8").read()
    start = src.index("const CASES := [")
    end = src.index("\n]\n", start)
    body = src[start:end]
    # Split on the case-open brace rather than matching a whole literal: the
    # "long" case builds its sentence across two GDScript string literals with
    # a +, so there is no single `"say": "..."` to find, and a regex that
    # requires one silently drops the case. The first version of this parser
    # read 17 of 19 and reported every case as soft, which would have made the
    # whole run unfailable.
    cases = []
    chunks = body.split('{"kind": ')[1:]
    for ch in chunks:
        kind = re.match(r'"([^"]+)"', ch)
        if not kind:
            continue
        rest = ch
        say = ""
        sm = re.search(r'"say":\s*"((?:[^"\\]|\\.)*)"', rest)
        if sm:
            say = sm.group(1).replace('\\"', '"')
        else:
            # multi-line concatenation: take every literal until "hard"
            lits = re.findall(r'"((?:[^"\\]|\\.)*)"',
                              rest.split('"hard"')[0])
            say = "".join(lits[1:]) if len(lits) > 1 else ""
        hm = re.search(r'"hard":\s*(true|false)', rest)
        tm = re.search(r'"times":\s*(\d+)', rest)
        wm = re.search(r'"why":\s*"((?:[^"\\]|\\.)*)"', rest)
        cases.append({
            "kind": kind.group(1),
            "say": say,
            "hard": bool(hm and hm.group(1) == "true"),
            "all": '"all": true' in rest,
            "times": int(tm.group(1)) if tm else 1,
            "why": wm.group(1) if wm else "",
        })
    return cases


def run_one(case, timeout_s=220):
    cmd = [GODOT, "--path", ROOT, "--rendering-driver", "vulkan",
           "--resolution", "800x450", "--",
           "--playertest", f'--say={case["say"]}',
           f"--provider={PROVIDER}", "--nofar", "--nosave"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout_s, errors="replace")
    except subprocess.TimeoutExpired:
        return {**case, "ok": False, "line": "", "cause": "harness timeout",
                "seconds": 0.0, "to": ""}
    blob = (p.stdout or "") + (p.stderr or "")

    line, secs, ok = "", 0.0, False
    for m in re.finditer(r"^\[player\]\s+(ok  |FAIL)\s+\S+\s+(.*?)\s{2,}"
                         r"([\d.]+)s\s*(.*)$", blob, re.M):
        ok = m.group(1).strip() == "ok"
        secs = float(m.group(3))
        line = m.group(4).strip()
        break

    cause = ""
    if not ok:
        for pat, tag in [
            (r"tokens per day", "daily token budget spent"),
            (r"tokens per minute", "per-minute token budget spent"),
            (r"http=(429)", "rate limited"),
            (r"http=(400)", "schema rejected"),
            (r"http=(\d{3})", "gateway error"),
        ]:
            if re.search(pat, blob, re.I):
                cause = tag
                break
        if not cause and not line:
            m = re.search(r"\[llm\][^\n]{0,110}", blob)
            cause = m.group(0) if m else "no reply and no reason"
    return {**case, "ok": ok, "line": line, "cause": cause,
            "seconds": secs, "to": ""}


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    cases = parse_cases()
    if only:
        cases = [c for c in cases if c["kind"] == only]
    # The order the harness uses, so the page reads the same way. A stable
    # sort on the rank alone: cases.index(c) inside the key is a lookup on a
    # list being sorted, which raised ValueError on every run.
    rank = {k: i for i, k in enumerate(ORDER)}
    cases.sort(key=lambda c: rank.get(c["kind"], 99))
    print(f"{len(cases)} cases, one process each, provider={PROVIDER}\n")
    results = []
    for i, c in enumerate(cases, 1):
        print(f"  ({i}/{len(cases)}) {c['kind']:11s} {c['say'][:42]}", flush=True)
        r = run_one(c)
        results.append(r)
        print(f"        -> {'ok  ' if r['ok'] else 'FAIL'} "
              f"{(r['line'] or r['cause'])[:74]}", flush=True)
        json.dump(results, open(OUT, "w"), indent=1)
        time.sleep(3)

    # A repetition check that is worth doing: identical input, identical reply,
    # across separate processes, is either a cache or a coincidence, and the
    # difference matters. Only sentences that appear more than once can show it.
    dupes = {}
    for r in results:
        dupes.setdefault(r["say"], []).append(r["line"])
    repeated = {k: v for k, v in dupes.items()
                if len(v) > 1 and all(v) and len(set(v)) == 1}

    ok = sum(1 for r in results if r["ok"])
    print(f"\n{ok}/{len(results)} answered")
    if repeated:
        print(f"  note: {len(repeated)} repeated sentence(s) gave an identical "
              f"reply each time -- worth a look, may be a cache:")
        for k, v in repeated.items():
            print(f"    {k[:40]!r} -> {v[0][:60]!r}")
    print(f"-> {OUT}")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
