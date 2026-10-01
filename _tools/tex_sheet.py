"""Contact sheet of the baked PBR maps (albedo | normal), for eyeballing.

Usage: python _tools/tex_sheet.py [texdir] [out.png] [name,name,...]
"""
import os
import glob
import sys
from PIL import Image, ImageDraw

TEX = sys.argv[1] if len(sys.argv) > 1 else "assets/tex_web"
OUT = sys.argv[2] if len(sys.argv) > 2 else "tex_sheet.png"
ONLY = sys.argv[3].split(",") if len(sys.argv) > 3 else None

names = sorted({os.path.basename(f).rsplit("_", 1)[0]
                for f in glob.glob(os.path.join(TEX, "*_a.png"))})
if ONLY:
    names = [n for n in ONLY if n in names]
if not names:
    print("no textures found")
    sys.exit(1)

CELL, PAD, LAB, COLS = 256, 6, 16, 6
rows = (len(names) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * (CELL + PAD) + PAD, rows * (CELL // 2 + LAB + PAD) + PAD), (18, 18, 20))
d = ImageDraw.Draw(sheet)
for i, nm in enumerate(names):
    r, c = divmod(i, COLS)
    x = PAD + c * (CELL + PAD)
    y = PAD + r * (CELL // 2 + LAB + PAD)
    a = Image.open(os.path.join(TEX, f"{nm}_a.png")).convert("RGB")
    nn = Image.open(os.path.join(TEX, f"{nm}_n.png")).convert("RGB")
    sheet.paste(a.resize((CELL // 2, CELL // 2), Image.LANCZOS), (x, y + LAB))
    sheet.paste(nn.resize((CELL // 2, CELL // 2), Image.LANCZOS), (x + CELL // 2, y + LAB))
    d.text((x + 1, y + 2), nm, fill=(225, 225, 230))
sheet.save(OUT)
print(OUT)
