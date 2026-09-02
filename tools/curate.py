"""Curate ~65 needed GLBs from assets_raw into kingdom-city/assets/ with canonical names."""
import os, shutil, json, re

SRC = r"C:\Users\vedan\Desktop\Projects\kingdom-city\assets_raw"
DST = r"C:\Users\vedan\Desktop\Projects\kingdom-city\assets"

def walk_glbs(sub):
    out = []
    base = os.path.join(SRC, sub)
    for r, _, fs in os.walk(base):
        for f in fs:
            if f.lower().endswith(".glb"):
                out.append(os.path.join(r, f))
    return sorted(out)

def cp(src, sub, name):
    d = os.path.join(DST, sub)
    os.makedirs(d, exist_ok=True)
    dst = os.path.join(d, name)
    shutil.copy2(src, dst)
    return dst

manifest = {}

# --- cars ---
car_excl = re.compile(r"debris|box|cone|wheel|window|armor|frame|door|bumper|hood|trunk|roof|engine|mudguard|towbar|trailer|shadow", re.I)
car_pref = ["sedan", "police", "taxi", "ambulance", "van", "truck", "race", "bus", "pickup", "jeep", "muscle", "suv", "sport", "hatchback", "car"]
cars = [p for p in walk_glbs("kenney_car-kit") if not car_excl.search(os.path.basename(p))]
picked = []
for pref in car_pref:
    for c in cars:
        if pref in os.path.basename(c).lower() and c not in picked:
            picked.append(c)
    if len(picked) >= 8:
        break
for c in cars:
    if len(picked) >= 8:
        break
    if c not in picked:
        picked.append(c)
manifest["cars"] = []
for i, c in enumerate(picked[:8]):
    cp(c, "cars", f"car_{i+1}.glb")
    manifest["cars"].append([os.path.basename(c), f"car_{i+1}.glb"])

# --- buildings ---
comm = walk_glbs("kenney_city-kit-commercial")
bldgs = [b for b in comm if re.match(r"building-[a-z]\.glb$", os.path.basename(b), re.I)]
skys = [b for b in comm if "skyscraper" in os.path.basename(b).lower()]
ind = [b for b in walk_glbs("kenney_city-kit-industrial") if os.path.basename(b).lower().startswith("building-")]
manifest["buildings"] = []
for i, b in enumerate(bldgs[:16]):
    cp(b, "buildings", f"bldg_{i+1}.glb"); manifest["buildings"].append([os.path.basename(b), f"bldg_{i+1}.glb"])
for i, b in enumerate(skys[:3]):
    cp(b, "buildings", f"sky_{i+1}.glb"); manifest["buildings"].append([os.path.basename(b), f"sky_{i+1}.glb"])
for i, b in enumerate(ind[:6]):
    cp(b, "buildings", f"ind_{i+1}.glb"); manifest["buildings"].append([os.path.basename(b), f"ind_{i+1}.glb"])

# --- palms ---
palms = [p for p in walk_glbs("kenney_nature-kit") if "palm" in os.path.basename(p).lower()]
manifest["palms"] = []
for i, p in enumerate(palms[:5]):
    cp(p, "palms", f"palm_{i+1}.glb"); manifest["palms"].append([os.path.basename(p), f"palm_{i+1}.glb"])

# --- characters ---
chars = walk_glbs("kaykit_adventurers")
manifest["chars"] = []
for i, c in enumerate(chars[:5]):
    cp(c, "chars", f"char_{i+1}.glb"); manifest["chars"].append([os.path.basename(c), f"char_{i+1}.glb"])

# --- props ---
def cp_first(sub, needle, name):
    for p in walk_glbs(sub):
        if needle.lower() in os.path.basename(p).lower():
            cp(p, "props", name)
            manifest.setdefault("props", []).append([os.path.basename(p), name])
            return True
    return False

cp_first("kenney_city-kit-roads", "light-curved.glb", "lamp.glb")
cp_first("kenney_city-kit-roads", "traffic-light-object-vertical.glb", "traffic_light.glb")

# --- furniture ---
furn_pref = ["bench", "chairSimple", "chair", "tableRound", "tableSmall", "table", "kitchenCounter",
             "counter", "bookcaseOpen", "bookcaseClosed", "couchCorner", "couch", "cabinetTelevision",
             "television", "bedSingle", "floorLamp", "plantLarge", "refrigerator", "stove", "sink",
             "deskOffice", "desk", "stool", "shelf"]
allfurn = walk_glbs("kenney_furniture-kit")
picked_f = []
for pref in furn_pref:
    for f in allfurn:
        bn = os.path.basename(f).lower()
        if pref.lower() in bn and f not in picked_f:
            picked_f.append(f)
    if len(picked_f) >= 14:
        break
manifest["furniture"] = []
for i, f in enumerate(picked_f[:14]):
    cp(f, "furniture", f"furn_{i+1}.glb"); manifest["furniture"].append([os.path.basename(f), f"furn_{i+1}.glb"])

with open(os.path.join(DST, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=1)

total = sum(len(v) for v in manifest.values())
size = sum(os.path.getsize(os.path.join(r, x)) for r, _, fs in os.walk(DST) for x in fs)
print(f"CURATED {total} files, {size/1e6:.1f} MB -> {DST}")
for k, v in manifest.items():
    print(f"  {k}: {len(v)}")
