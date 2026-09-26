"""Contact sheet of the baked PBR maps, so they can be eyeballed and compared.

Also reports the objective detail metrics on the albedo of each material, which
is the number that has to rise for the game to stop looking flat.
"""
import os
import glob
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

TEX = "assets/tex"
OUT = "C:/Users/vedan/Desktop/kingdom_city_TEXTURES.jpg"

names = sorted({os.path.basename(f).rsplit("_", 1)[0]
                for f in glob.glob(os.path.join(TEX, "*_a.png"))})
if not names:
    print("no textures found")
    sys.exit(1)

CELL = 150
PAD = 6
LAB = 16
COLS = 7
rows = (len(names) + COLS - 1) // COLS
W = COLS * (CELL + PAD) + PAD
H = rows * (CELL + LAB + PAD) + PAD
sheet = Image.new("RGB", (W, H), (18, 18, 20))
d = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 11)
except Exception:
    font = ImageFont.load_default()

stats = []
for i, nm in enumerate(names):
    r, c = divmod(i, COLS)
    x = PAD + c * (CELL + PAD)
    y = PAD + r * (CELL + LAB + PAD)
    try:
        a = Image.open(os.path.join(TEX, f"{nm}_a.png")).convert("RGB")
        nn = Image.open(os.path.join(TEX, f"{nm}_n.png")).convert("RGB")
    except Exception as e:
        d.text((x, y), f"{nm} ERR", fill=(255, 80, 80), font=font)
        continue
    arr = np.asarray(a, dtype=np.float64)
    stats.append((nm, float(arr.std())))
    # albedo on the left, normal on the right, so the pair can be compared
    sheet.paste(a.resize((CELL // 2, CELL // 2), Image.LANCZOS), (x, y + LAB))
    sheet.paste(nn.resize((CELL // 2, CELL // 2), Image.LANCZOS),
                (x + CELL // 2, y + LAB))
    d.text((x + 1, y + 2), f"{nm}", fill=(225, 225, 230), font=font)

sheet.save(OUT, quality=92)
print(OUT)
print(f"{len(stats)} materials, mean albedo std = "
      f"{np.mean([s for _, s in stats]):.2f}")
worst = sorted(stats, key=lambda t: t[1])[:6]
print("flattest:", ", ".join(f"{n}={s:.1f}" for n, s in worst))
