"""Convert the downloaded shader-pack references to PNG so they can be measured
with the same metrics as the game's own screenshots (and shown to the user)."""
import os
import glob
from PIL import Image

OUT = "_ref/mc_full"
os.makedirs(OUT, exist_ok=True)

for f in sorted(glob.glob("_ref/mc_*.webp")) + sorted(glob.glob("_ref/mc_*.jpg")):
    base = os.path.basename(f)
    stem = base.rsplit(".", 1)[0]
    if stem.startswith("mc_fx_"):
        continue                      # effect crops, not full frames
    try:
        im = Image.open(f).convert("RGB")
    except Exception as e:
        print("SKIP", base, e)
        continue
    out = os.path.join(OUT, stem.replace("mc_", "ref_") + ".png")
    im.save(out, optimize=True)
    print(f"{out} {im.size}")
