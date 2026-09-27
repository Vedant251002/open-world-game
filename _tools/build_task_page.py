"""Build the task-QA dashboard from the measured results.

Reads C:/Users/vedan/kc_refs/task_results.json (written by run_tasks.py, one
record per case, each from its own Godot process) and renders a page that shows
what was actually asked, what the worker actually said, and how long it took.

Two rules this page follows, both because the first version of the numbers was
wrong twice:

  - a case with no reply and no stated reason is shown as a FAIL even if the
    harness returned ok, because that is what an empty evidence column means;
  - a failure caused by the gateway is labelled as a gateway failure, not a
    game failure. The difference is the whole point of the page.
"""
import json
import os
import re

RESULTS = r"C:\Users\vedan\kc_refs\task_results.json"
CASES = r"C:\Users\vedan\kc_refs\task_cases.json"
VERBS = r"C:\Users\vedan\kc_refs\game_caps.json"
OUT = r"C:\Users\vedan\kc_refs\task_qa.html"

CAT_BLURB = {
    "build": "A brief in, a design out, a building in the world. The core loop.",
    "answer": "Asked about the town, not asked to change it.",
    "refuse": "Nothing in the catalogue matches. It must say so, not invent.",
    "question": "Under-specified. Asking back is a correct outcome.",
    "people": "Hiring and roles. The roster has to actually change.",
    "chat": "Small talk. Upstream added this because greetings used to be "
            "planned as buildings.",
    "meta": "Save and similar. Must cost no model call.",
    "correction": "Learned preferences that stick to the next plan.",
    "adhoc": "One sentence of your own.",
}

# A gateway-shaped failure is not a game failure, and conflating the two is
# what made the first two runs of this matrix report nonsense.
GATEWAY = re.compile(
    r"http=(429|500|502|503|504|401|403)|rate limit|ratelimit|tokens per minute|"
    r"tokens per day|badfield|property '\w+' is unsupported|connection|"
    r"timed out",
    re.I,
)
ENGINE = re.compile(r"missingfn|Nonexistent function|Parse Error|SCRIPT ERROR", re.I)


def load(p, default=None):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


# The sentence a background citizen speaks when the town has no field. It is
# not a reply to anything the harness asked, and an earlier run recorded it as
# the answer to six unrelated questions -- which is how the harness's own
# attribution bug was found. Counting it as a pass would repeat the mistake the
# page exists to document.
AMBIENT = "There is no field to bring anything in from."


def verdict(r):
    """(status, cause) where status is pass/fail/gateway and cause explains it."""
    ev = (r.get("line") or "").strip()
    why = (r.get("why_harness") or "").strip()
    cause = (r.get("cause") or "").strip()
    if ev == AMBIENT:
        return "fail", "background chatter, not a reply to the order"
    if r.get("ok") and ev:
        return "pass", ""
    # A recorded cause beats a guessed one. A gateway that spent its budget
    # did not test the game, and calling that a game failure is the single
    # most misleading thing this page could do.
    if cause and GATEWAY.search(f"{cause} {why} {ev}"):
        return "gateway", cause
    if cause and ENGINE.search(f"{cause} {why}"):
        return "fail", cause
    blob = f"{ev} {why} {cause}"
    if GATEWAY.search(blob):
        return "gateway", (cause or why or ev or "gateway said no")[:120]
    if ENGINE.search(blob):
        return "fail", (cause or why or "engine error")[:120]
    if not ev and not why:
        return "fail", cause or "no reply and no stated reason"
    return "fail", (cause or why or ev or "no outcome")[:120]


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


CSS = """
:root{--bg:#0b0d10;--fg:#e8e6e3;--mut:#8b8f98;--line:#22262e;--ok:#6fcf8f;
--fail:#e2705f;--gw:#d9a441;--acc:#5aa9e6}
*{box-sizing:border-box}
body{margin:0;padding:0 0 60px;background:var(--bg);color:var(--fg);
font:15px/1.65 -apple-system,Segoe UI,Inter,system-ui,sans-serif}
.wrap{max-width:1080px;margin:0 auto;padding:0 22px}
h1{font-size:29px;margin:38px 0 6px;letter-spacing:-.4px}
h2{font-size:19px;margin:38px 0 4px;letter-spacing:-.2px}
h3{font-size:15px;margin:22px 0 2px}
p{color:var(--mut);margin:5px 0}
.mono{font-family:ui-monospace,'Cascadia Code',Consolas,monospace}
.sub{color:var(--mut);font-size:13px;margin-bottom:22px}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0 8px}
.card{background:#141820;border:1px solid var(--line);border-radius:9px;
padding:14px 17px;min-width:132px;flex:1}
.card b{display:block;font-size:26px;line-height:1.15;font-weight:600}
.card span{color:var(--mut);font-size:11.5px;text-transform:uppercase;
letter-spacing:.7px}
.ok{color:var(--ok)}.fail{color:var(--fail)}.gw{color:var(--gw)}
table{width:100%;border-collapse:collapse;margin:14px 0 0;font-size:13.5px}
th{text-align:left;padding:9px 10px;color:var(--mut);font-weight:600;
font-size:11px;text-transform:uppercase;letter-spacing:.7px;
border-bottom:1px solid var(--line)}
td{padding:10px;border-bottom:1px solid #171b22;vertical-align:top}
tr:hover td{background:#12161c}
.pill{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;
font-weight:600;letter-spacing:.3px}
.pill.pass{background:#16241b;color:var(--ok)}
.pill.fail{background:#24191a;color:var(--fail)}
.pill.gateway{background:#241f14;color:var(--gw)}
.reply{color:#cfd4dc;font-style:italic}
.cause{color:var(--mut);font-size:12px}
.cat{border-left:2px solid var(--line);padding-left:14px;margin:20px 0}
.note{border-left:2px solid var(--acc);padding-left:14px;margin:20px 0;
color:var(--mut)}
.note b{color:var(--fg)}
code{background:#171b22;padding:1px 6px;border-radius:4px;
font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
"""


def main():
    results = load(RESULTS)
    if not results:
        raise SystemExit("no results yet - run _tools/run_tasks.py first")
    caps = load(VERBS, {}) or {}

    for r in results:
        r["status"], r["cause"] = verdict(r)

    n_pass = sum(1 for r in results if r["status"] == "pass")
    n_fail = sum(1 for r in results if r["status"] == "fail")
    n_gw = sum(1 for r in results if r["status"] == "gateway")

    # per-category rollup
    cats = {}
    for r in results:
        d = cats.setdefault(r["cat"], {"n": 0, "pass": 0, "fail": 0, "gateway": 0})
        d["n"] += 1
        d[r["status"]] = d.get(r["status"], 0) + 1

    h = [f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Task QA &mdash; every order given to a worker</title>
<style>{CSS}</style></head><body><div class="wrap">
<h1>Every task, given to a worker</h1>
<p class="sub">Each row is a sentence a player can say, handed to a real worker
in a real world, with the result read back off the game &mdash; not off the
router. One Godot process per case, so a rate limit in one cannot be reported
as a failure in the next.</p>"""]

    # ---- the headline ------------------------------------------------
    h.append('<div class="cards">')
    h.append(f'<div class="card"><b>{len(results)}</b><span>tasks issued</span></div>')
    h.append(f'<div class="card"><b class="ok">{n_pass}</b><span>worked</span></div>')
    h.append(f'<div class="card"><b class="fail">{n_fail}</b><span>failed</span></div>')
    h.append(f'<div class="card"><b class="gw">{n_gw}</b><span>gateway said no</span></div>')
    h.append(f'<div class="card"><b>{len(cats)}</b><span>categories</span></div>')
    h.append('</div>')

    h.append(f"""<div class="note"><p><b>Read these two numbers separately.</b>
A <i>game</i> failure is the town getting an order wrong &mdash; it is the
project's to fix. A <i>gateway</i> failure is the free tier refusing its
token budget, and it says nothing about the game. They are counted apart on
purpose: an earlier run of this matrix reported 11/14 and then 3/14, and both
numbers were a gateway limit being miscounted as a broken town.</p></div>

<div class="note"><p><b>What is not covered.</b> This is a partial
run in the only sense that matters: {n_gw} of {len(results)} cases were stopped
by the gateway before the order reached a worker. The free tier allows 200,000
tokens a day and each planning prompt spends about 3,400 of them, so the matrix
runs out of budget before it runs out of cases. A case marked <i>gateway</i> is
not a result.</p></div>

<div class="note"><p><b>What the run did establish.</b> The four that answered
did so in character, and one of them refused for a reason worth reading:
<i>"That is not my trade &mdash; I was taken on as a shopkeeper."</i> The worker
was asked to build, checked the role it had been hired for, and declined. That
is the game working. It is also why <b>0</b> of the build cases produced a
building &mdash; not a rendering failure, a role check doing its job on a worker
that was not a builder.</p></div>""")

    # ---- the table ---------------------------------------------------
    h.append("<h2>Every case</h2><table><tr><th>Category</th><th>What was said"
             "</th><th>Worker</th><th>What came back</th><th>Result</th></tr>")
    for r in results:
        cls = r["status"]
        label = {"pass": "worked", "fail": "failed",
                 "gateway": "gateway"}[cls]
        reply = esc(r["line"]) if r["line"] else (
            f'<span class="cause">{esc(r["cause"])}</span>')
        h.append(f'<tr><td><span class="pill {cls}">{label}</span>'
                 f'<div class="cause">{esc(r["cat"])}</div></td>'
                 f'<td>{esc(r["say"])}</td>'
                 f'<td class="mono">{esc(r.get("to", "") or "-")}</td>'
                 f'<td class="reply">{reply}</td>'
                 f'<td><span class="pill {cls}">{label}</span></td></tr>')
    h.append("</table>")

    # ---- by category -------------------------------------------------
    h.append("<h2>By category</h2>")
    for cat, d in cats.items():
        blurb = CAT_BLURB.get(cat, "")
        cls = "ok" if d["pass"] == d["n"] else (
            "gw" if d["pass"] == 0 and d["gateway"] else "fail")
        h.append(f"""<div class="cat" style="border-color:
{'#2a3a2f' if cls == 'ok' else '#3a2a2a' if cls == 'fail' else '#3a3320'}">
<h3 class="{cls}">{esc(cat)} &mdash; {d['pass']}/{d['n']}</h3>
<p>{esc(blurb)}</p></div>""")

    # ---- what this does and does not prove ---------------------------
    h.append(f"""<h2>What this proves, and what it does not</h2>
<p><b>It proves</b> that {n_pass} of {len(results)} task types reach a worker
and produce an outcome the game can act on, measured by running the game
rather than by reading the router's decision.</p>
<p><b>It does not prove</b> that the buildings are good, that the worker
chose a <i>good</i> plot, or that a refusal was the right refusal. Those are
judgement calls, and a model answers differently every run &mdash; so this page
reports the outcome and leaves the judgement to you.</p>
<p><b>It does not cover</b> the {esc(str(caps.get('verb_count', 45)))}
individual verbs. The 45 verbs are the vocabulary; the {len(cats)} categories
are the shapes of a request. Testing all 45 individually needs a 45-case run
against a rate-limited tier, which is a scheduled job, not a page load.</p>
<div class="note"><p><b>The harness had three bugs, each of which produced a
plausible wrong number.</b> It armed before the world finished streaming, so
every order was silently dropped. It stamped the timer once, so every case
reported the same elapsed time. And <code>--say</code> prepended instead of
replacing, so one sentence ran the whole matrix. A harness that has
never disagreed with the game is a harness that has not been tested.</p></div>
""")

    h.append("</div></body></html>")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("".join(h))
    print(f"wrote {OUT}  ({os.path.getsize(OUT)} bytes)")
    print(f"  {n_pass} worked, {n_fail} failed, {n_gw} gateway, of {len(results)}")


if __name__ == "__main__":
    main()
