"""Extract every player-facing capability from the game, straight from source.

Nothing here is written from memory: the verb table, the quick-intent patterns,
the realm systems and the debug flags are all parsed out of the actual files, so
the list cannot drift from what the game implements.
"""
import json
import os
import re

ROOT = r"C:\Users\vedan\Desktop\Projects\kingdom-city"
S = lambda *p: os.path.join(ROOT, *p)


def read(p):
    with open(S(*p.split("/")), encoding="utf8") as f:
        return f.read()


# ---------------------------------------------------------------- verbs
steps = read("scripts/gen/steps.gd")
verbs = []
# Each verb is a top-level entry in the VERBS table with a description line.
for m in re.finditer(
        r'^\t"([a-z_]+)":\s*\{\n(.*?)^\t\},', steps, re.S | re.M):
    name, body = m.group(1), m.group(2)
    d = re.search(r'"what":\s*"([^"]*)"', body)
    orc = re.search(r'"orcar":\s*"([^"]*)"', body)
    fields = re.findall(r'^\t\t"([a-z_]+)":\s*\{', body, re.M)
    inst = "instant" in body and 'instant' in body
    verbs.append({
        "verb": name,
        "what": (d.group(1) if d else "").strip(),
        "fields": fields,
        "source": "scripts/gen/steps.gd",
    })

# ---------------------------------------------------------------- categories
# Grouped by the module that owns them, which is how a new player meets them.
CATS = [
    ("Building & land", ["build", "enclose", "demolish", "decorate", "pave",
                         "level", "plant_tree", "water"]),
    ("Farming & food", ["sow", "gather", "harvest", "collect", "tend",
                        "cook", "craft", "fish", "hunt"]),
    ("People & work", ["recruit", "hire", "dismiss", "define_role", "learn",
                       "teach", "delegate", "report", "arm", "drill",
                       "enlist", "forge", "attack", "defend"]),
    ("Movement & orders", ["go", "follow", "wait", "station", "patrol",
                           "scout", "trade", "stock", "speak", "rest"]),
    ("Standing & goals", ["standing", "goal", "save", "restart"]),
]

# ---------------------------------------------------------------- realm systems
realm = ""
if os.path.exists(S("scripts/realm/realm.gd")):
    realm = read("scripts/realm/realm.gd")
# Systems load from a SYSTEM_PATHS constant, not from preloads, so the
# directory listing is the honest source of "what a kingdom can do".
sysdir = S("scripts/realm")
systems = sorted(f[:-3] for f in os.listdir(sysdir)
                 if f.endswith(".gd") and not f.endswith(".uid"))

# ---------------------------------------------------------------- debug flags
main = read("scripts/main.gd")
flags = sorted(set(re.findall(r'"(--[a-z]+)"', main)))
flags = [f for f in flags if f not in ("--",)]

# ---------------------------------------------------------------- controls
pro = read("project.godot")
inp = ""
if "[input]" in pro:
    # The input block runs to the next top-level section, which is [physics]
    # here; splitting on "[" alone truncates at the first nested key.
    inp = pro.split("[input]")[1].split("\n[")[0]
keys = re.findall(r'^([a-z_]+)=\{', inp, re.M)

# ---------------------------------------------------------------- emit
out = {
    "verbs": {v["verb"]: v for v in verbs},
    "verb_count": len(verbs),
    "categories": {c: [v for v in vs if v in {x["verb"] for x in verbs}]
                   for c, vs in CATS},
    "realm_systems": systems,
    "debug_flags": flags,
    "input_actions": keys,
}
with open(r"C:\Users\vedan\kc_refs\game_caps.json", "w", encoding="utf8") as f:
    json.dump(out, f, indent=1)

print(f"VERBS: {len(verbs)}")
for c, vs in out["categories"].items():
    print(f"  {c:22s} {len(vs):2d}  {' '.join(vs)}")
print(f"\nREALM SYSTEMS ({len(systems)}): {' '.join(systems)}")
print(f"DEBUG FLAGS ({len(flags)}): {' '.join(flags)}")
print(f"INPUT ACTIONS ({len(keys)}): {' '.join(keys)}")
