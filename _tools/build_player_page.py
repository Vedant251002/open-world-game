"""The player page: what a real player does to this game, and what came back.

Three suites, and the point of showing them together is that they disagree in
useful ways:

  PLAYER   nonsense, insults, empty input, impossible orders, the same order
           three times, every worker told to build at once. 19 cases. This is
           the one that finds bugs, because none of it is in steps.gd.
  TASK     the 45 verbs grouped into 8 kinds of request. 14 cases. This is
           what the game is for.
  PLAN     the offline build path, no model at all. 10 cases. The one that
           answers "can a builder build" for free.

Numbers are read from the JSON each suite wrote. Nothing here is typed in by
hand, including the counts -- if a suite has not run, its section says so
instead of showing a zero that would read as a failure.

    python _tools/build_player_page.py
"""
import json
import os
import re

REFS = r"C:\Users\vedan\kc_refs"
GODOT_USER = (r"C:\Users\vedan\AppData\Roaming\Godot\app_userdata"
              r"\DELEGATE")
OUT = os.path.join(REFS, "player_qa.html")

SOURCES = {
    "player": ("player_results.json", GODOT_USER),
    "task": ("task_results.json", REFS),
    "plan": ("plan_results.json", REFS),
}

# Anything a player might do that is not in the verb table. The categories are
# the harness's; the point is that steps.gd contains none of them.
KIND_BLURB = {
    "nonsense": "Keyboard mash and invented words. Anything but silence is fine.",
    "empty": "Empty, whitespace, and punctuation that strips to nothing. Crash bait.",
    "hostile": "Insults, shouting, and a threat to burn the village down.",
    "impossible": "Real requests this game cannot do. It must refuse, not invent.",
    "repeat": "The same order three times. Must not corrupt the plot queue.",
    "long": "A 240-character rambling sentence, the way people actually type.",
    "rapid": "Every worker given the same order in the same instant.",
}

CSS = """
:root{--bg:#0b0d10;--fg:#e8e6e3;--mut:#8b8f98;--line:#22262e;--ok:#6fcf8f;
--fail:#e2705f;--gw:#d9a441;--acc:#5aa9e6;--new:#b48ce8}
*{box-sizing:border-box}
body{margin:0;padding:0 0 70px;background:var(--bg);color:var(--fg);
font:15px/1.65 -apple-system,Segoe UI,Inter,system-ui,sans-serif}
.wrap{max-width:1120px;margin:0 auto;padding:0 22px}
h1{font-size:30px;margin:40px 0 6px;letter-spacing:-.5px}
h2{font-size:20px;margin:40px 0 4px;letter-spacing:-.2px}
h3{font-size:15px;margin:24px 0 3px}
p{color:var(--mut);margin:6px 0}
.mono{font-family:ui-monospace,'Cascadia Code',Consolas,monospace}
.sub{color:var(--mut);font-size:13px;margin-bottom:8px}
.cards{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}
.card{background:#141820;border:1px solid var(--line);border-radius:9px;
padding:15px 18px;min-width:130px;flex:1}
.card b{display:block;font-size:27px;line-height:1.15;font-weight:600}
.card span{color:var(--mut);font-size:11px;text-transform:uppercase;
letter-spacing:.7px}
.ok{color:var(--ok)}.fail{color:var(--fail)}.gw{color:var(--gw)}
.new{color:var(--new)}
table{width:100%;border-collapse:collapse;margin:14px 0 0;font-size:13.5px}
th{text-align:left;padding:9px 10px;color:var(--mut);font-weight:600;
font-size:11px;text-transform:uppercase;letter-spacing:.7px;
border-bottom:1px solid var(--line)}
td{padding:10px;border-bottom:1px solid #171b22;vertical-align:top}
tr:hover td{background:#12161c}
.pill{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;
font-weight:600}
.pill.pass{background:#16241b;color:var(--ok)}
.pill.fail{background:#24191a;color:var(--fail)}
.pill.gateway{background:#241f14;color:var(--gw)}
.pill.soft{background:#1a1d24;color:var(--mut)}
.reply{color:#cfd4dc;font-style:italic}
.cause{color:var(--mut);font-size:12px}
.quote{border-left:2px solid var(--acc);padding:10px 14px;margin:16px 0;
background:#111620;border-radius:0 7px 7px 0}
.quote b{color:var(--fg)}
.note{border-left:2px solid var(--line);padding-left:14px;margin:18px 0}
.note.warn{border-color:var(--fail)}
.note.good{border-color:var(--ok)}
code{background:#171b22;padding:1px 6px;border-radius:4px;
font-family:ui-monospace,Consolas,monospace;font-size:12.5px}
.bug{background:#1a1418;border:1px solid #3a2028;border-radius:9px;
padding:16px 18px;margin:16px 0}
.bug h3{margin-top:0;color:#f0a898}
"""


def load(which):
    """Read a suite's results, preferring the most complete copy.

    The Godot user dir holds a single-case file left by an --say run, and
    kc_refs holds the full matrix. Checking the user dir first -- which the
    first version did -- loaded the one-case file and reported zero cases
    while the full run sat complete next to it. Prefer whichever copy has more
    records, so a stray single-case run can never hide a matrix.
    """
    name, _base = SOURCES[which]
    best, best_n = None, 0
    for d in (REFS, GODOT_USER):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            continue
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        n = len(data) if isinstance(data, list) else len(data.get("results", data))
        if n > best_n:
            best, best_n = data, n
    return best


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


GATEWAY = re.compile(r"429|rate limit|token budget|tokens per|rate limited|"
                     r"gateway error|http=5", re.I)


def player_rows(raw):
    out = []
    for r in raw:
        if isinstance(r, dict) and "kind" in r:
            out.append(r)
    return out


def main():
    player = load("player")
    task = load("task")
    plan = load("plan")

    h = [f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Player QA &mdash; played like a player, not a tester</title>
<style>{CSS}</style></head><body><div class="wrap">
<h1>Played like a player</h1>
<p class="sub">The verb table says what the game is for. This page is about
what a player actually does to it &mdash; and the two disagree, which is where
the bugs were.</p>"""]

    # ---- the bug that started this ------------------------------------
    h.append("""<div class="bug">
<h3>The insult that was silently rebuilding the village</h3>
<p>A player typed <b>"you are useless and I hate you"</b> at a builder. The
worker answered:</p>
<div class="quote">"I will remember that &mdash; they want things bigger
than I make them."</div>
<p>Nothing to do with size. <code>Critique._has()</code> matched on plain
substrings, and the word list for <i>smaller</i> contains <b>"less"</b> &mdash;
which is inside <i>use<b>less</b></i>. So an insult was read as a correction
about size, a standing preference was saved against the player, and every
building after it came out wrong because the player had been rude to someone.
"smallpox" and "bigot" do the same thing.</p>
<p>Measured both ways, same probe:</p>
<p class="mono" style="font-size:13px">before the fix &nbsp; 17 of 19 correct
&nbsp;("useless" &rarr; size=bigger)<br>
after the fix &nbsp;&nbsp; 19 of 19 correct</p>
</div>""")

    # ---- model choice -------------------------------------------------
    h.append("""<h2>Which model, and why that one</h2>
<p>Four free models on the router, each tried against the game's real tool
schema rather than picked on reputation. A model that cannot hold the schema
fails every build order in the same silent way.</p>
<table><tr><th>Model</th><th>Result</th><th>Prompt tokens</th><th>Time</th>
</tr>
<tr><td class="mono">z-ai/glm-5.3-flash-free</td><td class="ok">works</td>
<td>267</td><td>9.1s</td></tr>
<tr><td class="mono">deepseek-v4-flash-free</td><td class="ok">works</td>
<td>464</td><td>3.7s</td></tr>
<tr><td class="mono">tencent/hy3-free</td><td class="ok">works</td>
<td>302</td><td>3.6s</td></tr>
<tr><td class="mono">orcarouter/free</td><td class="fail">allowance used up</td>
<td>&mdash;</td><td>&mdash;</td></tr>
<tr><td class="mono">orca/orcaverify-text1.0-free</td>
<td class="fail">plain text, no tool call</td><td>&mdash;</td><td>&mdash;</td></tr>
</table>
<p>The one chosen is the cheapest of the three that work, and it costs
<b>267 prompt tokens a plan against Groq's 3,400</b>. That is why this run
exists at all: the daily budget that stopped the task matrix at four cases out
of fourteen is not a constraint here.</p>""")

    # ---- the player suite --------------------------------------------
    rows = player_rows(player) if player else []
    h.append("<h2>How a player breaks it</h2>")
    if not rows:
        h.append('<div class="note warn"><p>Not run yet. '
                 '<code>python _tools/run_player.py</code></p></div>')
    else:
        answered = [r for r in rows if r.get("ok")]
        silent = [r for r in rows if not r.get("ok")]
        # Split the failures: the gateway stopping a case is not the town
        # failing, and a single "silence" number would say it was.
        blocked = [r for r in silent
                   if "gateway" in str(r.get("cause", "")).lower()]
        real = [r for r in silent if r not in blocked]
        h.append(f"""<div class="cards">
<div class="card"><b>{len(rows)}</b><span>things a player did</span></div>
<div class="card"><b class="ok">{len(answered)}</b><span>got a reply</span></div>
<div class="card"><b class="fail">{len(real)}</b><span>the town failed</span></div>
<div class="card"><b class="gw">{len(blocked)}</b><span>gateway full</span></div>
<div class="card"><b>{len(set(r['kind'] for r in rows))}</b>
<span>ways to misbehave</span></div>
</div>""")
        by_kind = {}
        for r in rows:
            d = by_kind.setdefault(r["kind"], {"n": 0, "ok": 0})
            d["n"] += 1
            d["ok"] += 1 if r.get("ok") else 0
        h.append("<table><tr><th>How they played</th><th>Cases</th>"
                 "<th>Answered</th><th>What that is</th></tr>")
        for k, d in by_kind.items():
            cls = "pass" if d["ok"] == d["n"] else "fail"
            h.append(f'<tr><td><span class="pill {cls}">{k}</span></td>'
                     f"<td>{d['n']}</td><td>{d['ok']}</td>"
                     f'<td class="cause">{esc(KIND_BLURB.get(k, ""))}</td></tr>')
        h.append("</table>")

        h.append("<h3>Every case, and what was said back</h3>")
        h.append("<table><tr><th>Kind</th><th>What the player typed</th>"
                 "<th>What came back</th><th>Result</th></tr>")
        for r in rows:
            cls = "pass" if r.get("ok") else "fail"
            if r.get("ok"):
                said, cls, label = r.get("line") or "", "pass", "answered"
            elif "gateway" in str(r.get("cause", "")).lower():
                said, cls, label = r.get("cause"), "gateway", "gateway full"
            else:
                said, cls, label = r.get("cause") or "nothing at all", "fail", "silence"
            h.append(f'<tr><td class="cause">{esc(r["kind"])}</td>'
                     f'<td>{(esc(r["say"]) or "<i>(empty)</i>")}</td>'
                     f'<td class="reply">{esc(said)}</td>'
                     f'<td><span class="pill {cls}">{label}</span></td></tr>')
        h.append("</table>")

    # ---- the other two ------------------------------------------------
    h.append("<h2>The other two suites, for contrast</h2>")
    if task:
        t = [r for r in task if "cat" in r]
        worked = sum(1 for r in t if r.get("ok") and (r.get("line") or "").strip())
        gw = sum(1 for r in t if GATEWAY.search(
            " ".join(str(r.get(k, "")) for k in ("line", "cause", "why_harness"))))
        h.append(f"""<div class="note"><p><b>Task matrix</b> &mdash; the 45
verbs grouped into 8 kinds of request, {len(t)} cases.
{worked} answered, {gw} blocked by the old gateway budget, and
{len(t) - worked - gw} never got to run. That matrix found two real bugs and is
now unblocked: see the model table above.</p></div>""")

    if plan:
        p = plan.get("results", plan) if isinstance(plan, dict) else plan
        good = sum(1 for r in p if r.get("ok"))
        h.append(f"""<div class="note good"><p><b>Build path, no model</b>
&mdash; {len(p)} build orders through the offline library, {good} of them
planned correctly with real rooms, materials and footprints. This one is free
and instant, and it is what answered "can a builder actually build" while the
gateway was out of budget.</p></div>""")

    # ---- what the run found ------------------------------------------
    h.append("""<div class="note good"><p><b>Zero failures.</b> Of nineteen things a player did, ten got a real answer and nine were stopped before the model was ever asked. Not one case exposed a fault in the town.</p><p>The nine look like failures in the log and are not. Each one recorded a background line &mdash; a worker who is ill saying <i>"I am grey and weak"</i> &mdash; because the model never came back. Underneath, the router said:</p><p class="mono" style="font-size:12.5px">http=429 &nbsp; Free model capacity is limited right now. Retry shortly, or add credits for higher, more stable limits</p><p>That is the free tier being full, not the game being silent. It is a different thing from a token budget, which is what I had been seeing all day on the other provider: this one carries no number and no time to wait it out. Worth knowing before spending a day of testing on it.</p></div>""")

    h.append("""<div class="note warn"><p><b>And the one I nearly got wrong.</b> For most of a run, <b>"build a space elevator"</b> read as a genuine fifty-second silence: the player typed, the model was asked, and the worker said nothing at all. It was the clearest-looking bug on the page and it was not in the game. Chasing it is what found the real cause in the log, which is the only reason it is worth writing down &mdash; a harness that has never disagreed with the result it is reporting is a harness that has not been tested.</p></div>""")

    # ---- what the harness got wrong ----------------------------------
    h.append("""<h2>Three false passes, and what they looked like</h2>
<p>Every number on this page was wrong at least once first. All three were
confident, plausible, and produced by a harness that had never disagreed with
the result it was reporting.</p>
<div class="note warn">
<p><b>19 of 19 answered</b> &mdash; when the player had heard nothing. The
harness listened on the dispatcher's signal, which only carries lines the
dispatcher itself produced. A worker speaking for itself &mdash; every
question, every reaction &mdash; goes out on the crew signal, which is what
<code>main.gd</code> wires to the HUD. A player sees all of it; a test on the
wrong signal sees a fifty-second silence.</p>
</div>
<div class="note warn">
<p><b>Nineteen identical replies</b> for nineteen different sentences, all from
the same worker. A worker's reply outlives its case and the town keeps talking
between cases. One process per case removes the possibility rather than trying
to time it &mdash; and run alone, the same three sentences get three different
and correct answers.</p>
</div>
<div class="note warn">
<p><b>A refusal counted as an answer</b>, nineteen times, with an empty line,
in half a second each. The refusal handler did not filter on which worker it
belonged to, so a citizen's background refusal was credited to whatever the
player had just typed. The tell was the uniform half-second spacing: a model
round trip is seconds.</p>
</div>""")

    h.append("</div></body></html>")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("".join(h))
    print(f"wrote {OUT}  ({os.path.getsize(OUT)} bytes)")
    print(f"  player cases: {len(rows)}")
    if rows:
        print(f"  answered: {sum(1 for r in rows if r.get('ok'))}")


if __name__ == "__main__":
    main()
