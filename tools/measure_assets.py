"""Measure bounding boxes of GLB assets (parse glTF accessors, decode POSITION)."""
import json, struct, sys, os

BASE = r"C:\Users\vedan\Desktop\Projects\kingdom-city\assets_raw"

def glb_dims(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "not glb"
    js_len = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20+js_len])
    # binary chunk starts after JSON chunk (4-byte len + type) — find BIN offset
    off = 20 + js_len
    # chunks are 8-byte aligned
    if off % 4: off += 4 - (off % 4)
    bin_len = struct.unpack("<I", data[off:off+4])[0]
    bin_start = off + 8
    blob = data[bin_start:bin_start+bin_len]

    minv = None; maxv = None
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            pos_idx = prim.get("attributes", {}).get("POSITION")
            if pos_idx is None: continue
            acc = js["accessors"][pos_idx]
            if "min" in acc and "max" in acc:
                mn, mx = acc["min"], acc["max"]
            else:
                bv = js["bufferViews"][acc["bufferView"]]
                start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
                count = acc["count"]
                stride = bv.get("byteStride", 12)
                pts = []
                for i in range(count):
                    o = start + i * stride
                    pts.append(struct.unpack("<fff", blob[o:o+12]))
                xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; zs = [p[2] for p in pts]
                mn, mx = [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]
            if minv is None:
                minv, maxv = mn[:], mx[:]
            else:
                minv = [min(minv[i], mn[i]) for i in range(3)]
                maxv = [max(maxv[i], mx[i]) for i in range(3)]
    if minv is None: return None
    size = [maxv[i]-minv[i] for i in range(3)]
    return size, minv, maxv

targets = {
    "road_straight": r"kenney_city-kit-roads\Models\GLB format\road-straight.glb",
    "road_crossroad": r"kenney_city-kit-roads\Models\GLB format\road-crossroad.glb",
    "road_crossing": r"kenney_city-kit-roads\Models\GLB format\road-crossing.glb",
    "building_a": r"kenney_city-kit-commercial\Models\GLB format\building-a.glb",
    "building_b": r"kenney_city-kit-commercial\Models\GLB format\building-b.glb",
    "building_skyscraper": r"kenney_city-kit-commercial\Models\GLB format\building-skyscraper-a.glb",
    "building_tall": r"kenney_city-kit-commercial\Models\GLB format\building-tall-a.glb",
    "sedan": r"kenney_car-kit\Models\GLB format\sedan.glb",
    "police": r"kenney_car-kit\Models\GLB format\police.glb",
    "palm": r"kenney_nature-kit\Models\GLB format\tree_palm.glb",
    "palm_tall": r"kenney_nature-kit\Models\GLB format\tree_palmDetailedTall.glb",
    "traffic_light": r"kenney_city-kit-roads\Models\GLB format\traffic-light-object-vertical.glb",
    "street_light": r"kenney_city-kit-roads\Models\GLB format\light-curved.glb",
    "bench": r"kenney_furniture-kit\Models\GLB format\bench.glb",
    "hydrant": r"kenney_city-kit-roads\Models\GLB format\fire-hydrant.glb",
    "kaykit_char": r"kaykit_adventurers\addons\kaykit_character_pack_adventures\Characters\gltf\Barbarian.glb",
}
out = {}
for name, rel in targets.items():
    p = os.path.join(BASE, rel)
    if not os.path.exists(p):
        # try to find by basename anywhere
        base = os.path.basename(rel)
        found = None
        for root, _, files in os.walk(BASE):
            if base in files:
                found = os.path.join(root, base); break
        p = found
    if p is None:
        out[name] = {"error": "not found"}
        continue
    try:
        r = glb_dims(p)
        if r is None:
            out[name] = {"error": "no mesh"}
        else:
            size, mn, mx = r
            out[name] = {"size": [round(s,3) for s in size], "min_y": round(mn[1],3), "file": p}
    except Exception as e:
        out[name] = {"error": str(e)}

for k, v in out.items():
    print(k, "->", v)
