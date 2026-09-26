"""Objective image metrics + contact sheet for game screenshot review.

Metrics chosen to answer "does this look AAA?" without eyeballing:
  detail      mean |laplacian| - surface micro-detail / texture work
  local_var   mean local stddev - material variance, flat-shaded look
  uniq_colors distinct 5-bit-per-channel colors - palette / texture richness
  dark_ratio  fraction of pixels below 8% luma - crushed blacks
  clip_hi     fraction of pixels above 98% luma - blown highlights
  colorfulness Hasler-Susstrunk - if near 0, the frame is effectively grey
  entropy     Shannon entropy of luma - tonal range used
"""
import sys, os, json, math
import numpy as np
from PIL import Image

def load(p):
    im = Image.open(p)
    if im.mode != "RGB":
        im = im.convert("RGB")
    return im

def luma(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]

def metrics(path):
    a = np.asarray(load(path), dtype=np.float32) / 255.0
    y = luma(a)
    # laplacian detail
    k = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]], dtype=np.float32)
    from numpy.lib.stride_tricks import sliding_window_view
    w = sliding_window_view(y, (3, 3))
    lap = np.einsum('ijkl,kl->ij', w, k)
    detail = float(np.abs(lap).mean() * 255)
    # local stddev
    w2 = sliding_window_view(y, (9, 9)).reshape(-1, 81)
    lvar = float(w2.std(axis=1).mean() * 255)
    q = (a * 31).astype(np.int32)
    uniq = len(np.unique(q[..., 0] * 1024 + q[..., 1] * 32 + q[..., 2]))
    dark = float((y < 0.08).mean())
    clip = float((y > 0.98).mean())
    rg = a[..., 0] - a[..., 1]
    yb = 0.5 * (a[..., 0] + a[..., 1]) - a[..., 2]
    colorfulness = float(
        math.sqrt(rg.std() ** 2 + yb.std() ** 2)
        + 0.3 * math.sqrt(rg.mean() ** 2 + yb.mean() ** 2))
    hist = np.histogram(y, bins=64, range=(0, 1))[0].astype(np.float64)
    p = hist / max(hist.sum(), 1)
    ent = float(-(p[p > 0] * np.log2(p[p > 0])).sum())
    return dict(file=os.path.basename(path), res=f"{a.shape[1]}x{a.shape[0]}",
                detail=round(detail, 2), local_var=round(lvar, 2),
                uniq_colors=uniq, dark_ratio=round(dark, 4),
                clip_hi=round(clip, 4), colorfulness=round(colorfulness, 4),
                entropy=round(ent, 3),
                mean_luma=round(float(y.mean()), 4))

def contact_sheet(files, out, cols=2, cell=(760, 428), labels=None):
    cw, ch = cell
    rows = (len(files) + cols - 1) // cols
    pad, lab = 8, 20
    W = cols * cw + pad * (cols + 1)
    H = rows * (ch + lab) + pad * (rows + 1)
    sheet = Image.new("RGB", (W, H), (16, 16, 18))
    from PIL import ImageDraw, ImageFont
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 13)
    except Exception:
        font = ImageFont.load_default()
    for i, f in enumerate(files):
        r, c = divmod(i, cols)
        x = pad + c * (cw + pad)
        y = pad + r * (ch + lab + pad)
        im = load(f).resize((cw, ch), Image.LANCZOS)
        sheet.paste(im, (x, y + lab))
        d.text((x + 2, y + 3), labels[i] if labels else os.path.basename(f),
               fill=(230, 230, 235), font=font)
    sheet.save(out)
    return out

if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "sheet":
        out = args[1]
        files = args[2:]
        print(contact_sheet(files, out))
    else:
        rows = [metrics(p) for p in args]
        print(json.dumps(rows, indent=1))
        keys = ["file", "detail", "local_var", "uniq_colors", "colorfulness",
                "entropy", "dark_ratio", "clip_hi"]
        print(" | ".join(f"{k:>13}" for k in keys))
        for r in rows:
            print(" | ".join(f"{str(r[k]):>13}" for k in keys))
