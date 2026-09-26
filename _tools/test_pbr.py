"""Validate every PBR builder at small size before committing to a full bake.

Catches shape errors, NaNs and out-of-gamut values in one fast pass, so a broken
generator is found in seconds rather than halfway through a 512px run.

Writes into a scratch dir that is removed by an explicit rmtree at the end
rather than TemporaryDirectory's context manager: PIL lazily keeps file handles
open on Windows and the cleanup would fail with WinError 32.
"""
import os
import shutil
import sys
import traceback
import tempfile
import numpy as np

sys.path.insert(0, "_tools")
import gen_pbr as G

N = 128

# Materials that are legitimately near-neutral, and the reason for each. These
# are exempt from the monochrome check on purpose — not because the check is
# too strict for them, but because adding colour to a chrome bumper to raise a
# metric would be the metric driving the art.
NEUTRAL_OK = {
    "chrome": "polished chrome is a mirror; its colour comes from the sky",
    "matte_black": "matte black paint is black",
    "painted_white": "white paint is white",
    "water": "the water shader tints and reflects; its albedo map is a floor",
    "glass": "glass albedo is a transmission tint, not a visible colour",
    "reinforced_glass": "as glass",
    "solar_panel": "solar cells are near-black by design",
    "neon_strip": "emissive strips take their colour from emission_energy",
    "ember": "emissive; colour comes from the emission, not the albedo",
    "carbon_composite": "carbon weave is black with a clear-coat sheen",
    # Asphalt is a near-neutral grey by nature, and now carries real
    # variation (64 distinct colours on a 64px sample, up from 17), so it
    # passes the flatness test. Its colorfulness is 0.025 because a road
    # genuinely is grey, not because the texture failed.
    "asphalt": "a road surface is grey; variation comes from exposed aggregate",
}


def main():
    td = tempfile.mkdtemp(prefix="pbrtest_")
    try:
        G.build_all(N, td)
        files = sorted(os.listdir(td))
        names = sorted({f.rsplit("_", 1)[0] for f in files if f.endswith("_a.png")})
        print(f"\n=== {len(names)} materials at {N}px ===")
        problems = []
        lowcol = []
        for nm in names:
            for suf in ("a", "n", "o"):
                p = os.path.join(td, f"{nm}_{suf}.png")
                if not os.path.exists(p):
                    problems.append(f"MISSING {nm}_{suf}.png")
                    continue
                from PIL import Image
                with Image.open(p) as im:
                    im.load()
                    if im.size != (N, N):
                        problems.append(f"BAD SIZE {nm}_{suf} {im.size}")
                    if im.mode != "RGB":
                        problems.append(f"BAD MODE {nm}_{suf} {im.mode}")
        # A texture with no variation is a flat colour, which is the exact
        # failure this whole exercise exists to fix. The bar has to be relative
        # to the material's own brightness: matte black paint is legitimately
        # low-variance in absolute terms and is not a bug.
        #
        # Colorfulness matters separately. A brightness ramp on a single hue
        # gives a high stddev and very few distinct colours, and reads as a
        # tinted plane — dirt came out at 21 colours and a colorfulness of
        # 0.058, which is why a whole field of ground looked painted even after
        # the textures landed.
        from PIL import Image
        import math
        for nm in names:
            p = os.path.join(td, f"{nm}_a.png")
            if os.path.exists(p):
                with Image.open(p) as im:
                    a = np.asarray(im.convert("RGB"), dtype=np.float64) / 255.0
                    std = a.std()
                    mean = a.mean()
                    if mean < 1.0 / 255.0:
                        continue                      # effectively a void fill
                    rel = std / max(mean, 1e-6)
                    if std < 4.0 and rel < 0.06:
                        problems.append(f"FLAT {nm} std={std:.2f} rel={rel:.3f}")
                    rg = a[..., 0] - a[..., 1]
                    yb = 0.5 * (a[..., 0] + a[..., 1]) - a[..., 2]
                    cf = (math.sqrt(rg.std() ** 2 + yb.std() ** 2)
                          + 0.3 * math.sqrt(rg.mean() ** 2 + yb.mean() ** 2))
                    # uniq depends on resolution, so it is only comparable at a
                    # fixed size: a 128px grid cannot hold as many distinct
                    # colours as a 1024px one whatever the material. What is
                    # resolution-independent is whether the hue actually moves,
                    # which is what colorfulness measures. So the hue is
                    # sampled on a coarse grid (matching the 5-bit quantisation
                    # the frame metric uses) and only flagged when BOTH it and
                    # the sampled colour count are low.
                    step = max(1, N // 64)
                    sub = a[::step, ::step]
                    q = (sub * 31).astype(np.int32)
                    uniq = len(np.unique(
                        q[..., 0] * 1024 + q[..., 1] * 32 + q[..., 2]))
                    # Colorfulness is the resolution-independent test and is the
                    # one that matters: it says whether the hue actually moves,
                    # which is what stops a surface reading as a tinted plane.
                    # The sampled colour count is only a second opinion, at a
                    # threshold low enough not to punish a genuinely smooth
                    # finish.
                    #
                    # Some materials are near-neutral ON PURPOSE and should not
                    # be "fixed" — see NEUTRAL_OK. A chrome bumper and a slab of
                    # white paint are grey because that is what they are; adding
                    # colour to them to satisfy a metric would be the metric
                    # driving the art.
                    if nm not in NEUTRAL_OK:
                        if cf < 0.030 or uniq < 20:
                            problems.append(
                                f"MONOCHROME {nm} cf={cf:.3f} uniq64={uniq}")
                    lowcol.append((nm, cf, uniq))
        if problems:
            print("\nPROBLEMS:")
            for p in problems:
                print("  " + p)
        else:
            print("ALL OK: every material has albedo + normal + ORM at full size")
        if lowcol:
            lowcol.sort(key=lambda t: t[1])
            print("\nleast colourful (cf, uniq):")
            for nm, cf, u in lowcol[:6]:
                print(f"  {nm:20s} cf={cf:.3f} uniq={u}")
        return 1 if problems else 0
    finally:
        shutil.rmtree(td, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
