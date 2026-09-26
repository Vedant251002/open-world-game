"""Bake tileable PBR texture layers for every DELEGATE voxel material.

Run:  python _tools/gen_pbr.py [--size 512] [--out res://assets/tex]

Why generated rather than downloaded: no accounts, no network at build time, no
licence questions, and the palette stays locked to VoxelTypes.PROPS so the
textures cannot drift away from the material table the game already ships.

Every layer is seamless. That matters more than it looks: a voxel face is one
0.25 m quad, the texture repeats across it, and a seam on a wall is a line
running the whole height of a building.

Output per material: <name>_a.png albedo, _n.png normal, _o.png ORM
(R = ambient occlusion, G = roughness, B = metallic).
"""
import argparse
import math
import os
import numpy as np
from PIL import Image

# ---------------------------------------------------------------- noise
# All noise is periodic so the baked tile wraps exactly. Godot's ImageTexture
# default wrap mode is the sampler default, and a non-wrapping tile shows a
# hard seam every 0.25 m of wall.

def _hash2(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393
         + iy.astype(np.int64) * 668265263
         + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / 0x1000000


def value_noise(n, freq, seed):
    """Tileable value noise in [0,1]. freq must be an integer."""
    x = np.arange(n, dtype=np.float64) * freq / n
    xi = np.floor(x).astype(np.int64)
    xf = x - xi
    u = xf * xf * (3 - 2 * xf)
    ix = xi[:, None]
    iy = xi[None, :]
    v = u[:, None]
    a = _hash2(ix, iy, seed)
    b = _hash2(ix + 1, iy, seed)
    c = _hash2(ix, iy + 1, seed)
    d = _hash2(ix + 1, iy + 1, seed)
    top = a * (1 - v) + b * v
    bot = c * (1 - v) + d * v
    return top * (1 - v.T) + bot * v.T


def fbm(n, freq, octaves, seed, gain=0.5):
    total = np.zeros((n, n))
    amp = 1.0
    norm = 0.0
    f = freq
    for i in range(octaves):
        total += amp * value_noise(n, f, seed + i * 977)
        norm += amp
        amp *= gain
        f *= 2
    return total / norm


def worley(n, cells, seed, jitter=0.85):
    """Tileable Worley/Voronoi. Returns (f1, cell_id, f2)."""
    x = np.arange(n, dtype=np.float64) * cells / n
    xi = np.floor(x).astype(np.int64)
    xf = (x - xi)[:, None]
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    cid = np.zeros((n, n), dtype=np.int64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx = xi[None, :] + dx
            cy = xi[:, None] + dy
            px = cx + 0.5 + (_hash2(cx, cy, seed) - 0.5) * jitter
            py = cy + 0.5 + (_hash2(cx, cy, seed + 313) - 0.5) * jitter
            d = np.sqrt((xf - px.T) ** 2 + (xf.T - py) ** 2)
            cell = _hash2(cx, cy, seed + 771)
            m = d < f1
            f2 = np.where(m, f1, np.minimum(f2, d))
            cid = np.where(m, (cell * 1e6).astype(np.int64), cid)
            f1 = np.where(m, d, f1)
    return f1, cid % 997, f2


def norm01(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo) if hi > lo else np.zeros_like(a)


# ---------------------------------------------------------------- helpers

def height_to_normal(height, strength=1.0):
    """Sobel over a wrapping height field -> tangent-space normal map."""
    h = height.astype(np.float64)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength * 8.0
    ny = -dy * strength * 8.0
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    return np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], axis=-1)


def _boxblur(a, radius):
    """Wrapped separable box blur, exact same size in / out.

    Cumulative sums rather than np.apply_along_axis + convolve: the latter is
    O(n^2 * radius) in interpreted per-row calls and took minutes per material.
    """
    n0, n1 = a.shape
    r = max(int(radius), 1)
    # centre the kernel: odd widths are exact, even widths are handled by
    # averaging the two nearest centred windows
    def blur1(m):
        m = np.asarray(m, dtype=np.float64)
        ext = np.concatenate([m, m, m], axis=0)
        z = np.zeros((1,) + m.shape[1:], dtype=np.float64)
        c = np.cumsum(np.concatenate([z, ext, z], axis=0), axis=0)
        w = 2 * r
        starts = np.arange(len(m)) + r
        return (c[starts + w] - c[starts]) / w
    if r % 2 == 1:
        return blur1(blur1(a.T).T)
    a1 = blur1(blur1(a.T).T)
    b = np.roll(a, 1, axis=0)
    b1 = blur1(blur1(b.T).T)
    a2 = blur1(blur1(np.roll(a, 1, axis=1).T).T)
    return (a1 + b1 + a2) / 3.0


def cavity_ao(height, radius=7):
    """Crevice darkening: how far below the locally-blurred surface a point is."""
    h = height
    blur = _boxblur(h, radius)
    ao = norm01((h - blur) * 0.5 + 0.5)
    return np.clip(0.35 + 0.65 * ao, 0.0, 1.0)


def hexcol(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def tint(base, mul):
    """base rgb in 0..1, mul an (n,n) or (n,n,3) multiplier. Returns (n,n,3)."""
    b = base.reshape(1, 1, 3) if base.ndim == 1 else base
    m = np.asarray(mul, dtype=np.float64)
    if m.ndim == 2:
        m = m[..., None]
    if m.ndim == 4:
        m = m[0]
    return np.clip(b * m, 0.0, 1.0)


# ---------------------------------------------------------------- patterns
# Each returns (albedo[n,n,3], height[n,n], rough_mul[n,n], metal[n,n]).

def p_brick(n, base):
    rows, cols = 12, 6
    bh, bw = n / rows, n / cols
    y = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    row = np.floor(y / bh)
    off = np.where(row % 2 > 0.5, 0.5, 0.0)
    col_id = np.floor(x / bw + off)
    fy = (y / bh) % 1.0
    fx = (x / bw + off) % 1.0
    mortar = 0.055
    # fy is (n,1) and fx is (1,n); every combination must be built out of place
    # or the broadcast result cannot be assigned back to the narrow operand.
    jy = np.clip((fy - mortar) / 0.10, 0, 1) * np.clip((1 - fy - mortar) / 0.10, 0, 1)
    jx = np.clip((fx - mortar) / 0.09, 0, 1) * np.clip((1 - fx - mortar) / 0.09, 0, 1)
    joint = jy * jx
    # per-brick tone: some bricks much darker, some much paler than the base
    t = _hash2(col_id.astype(np.int64), row.astype(np.int64), 4242)
    tone = 0.70 + t * 0.62
    grit = fbm(n, 128, 3, 91)
    pit = norm01(value_noise(n, 96, 517))
    face = tone * (0.80 + grit * 0.30) * (0.92 + pit * 0.16)
    mortar_col = tint(np.array([0.62, 0.58, 0.52]), 0.9 + grit * 0.3)
    # Firing variance: bricks from different kilns land anywhere from a
    # burnt purple-brown to an over-fired near-black, and a wall of identically
    # coloured bricks reads as a photo of a wall rather than a wall.
    fire = _hash2(col_id.astype(np.int64) // 3, row.astype(np.int64) // 5, 881)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (fire - 0.5) * 0.44
    hue[..., 1] = 1.0 - (fire - 0.5) * 0.14 + (grit - 0.5) * 0.10
    hue[..., 2] = 1.0 - (fire - 0.5) * 0.30 + (grit - 0.5) * 0.14
    alb = np.where(joint[..., None] > 0.5,
                   tint(base, face[..., None]) * hue, mortar_col)
    h = joint * (0.55 + grit * 0.25) + fbm(n, 8, 3, 12) * 0.10
    rough = 0.92 + grit * 0.10
    return alb, h, rough, np.zeros_like(h)


def p_stone(n, base, cells=9, rough_base=0.88):
    f1, cid, f2 = worley(n, cells, 71, 0.9)
    edge = np.clip((f2 - f1) * cells * 1.5, 0, 1)      # 0 at the joint
    dome = np.sqrt(np.clip(1.0 - (f1 * cells) ** 2, 0, 1))
    # cell id packed into an int; split it so the hash has two dimensions
    tone = 0.74 + _hash2(cid // 1000, cid, 313) * 0.55
    grain = fbm(n, 64, 4, 909)
    speck = norm01(value_noise(n, 200, 55))
    shade = tone * (0.82 + grain * 0.30) * (0.94 + speck * 0.12)
    # Stone is a mix of minerals, not one grey. Feldspar goes pink, mica goes
    # near-black, quartz goes pale — a brightness ramp alone gives 33 distinct
    # colours and reads as painted concrete.
    cast = _hash2(cid // 1000, cid, 331) * 2.0 - 1.0
    alb = tint(base, shade[..., None])
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + cast * 0.20 + (grain - 0.5) * 0.16
    hue[..., 1] = 1.0 + cast * 0.06 + (grain - 0.5) * 0.08
    hue[..., 2] = 1.0 - cast * 0.16 + (grain - 0.5) * 0.14
    alb = alb * hue
    h = edge * (0.5 + dome * 0.5) + grain * 0.18
    return alb, h, rough_base + grain * 0.08, np.zeros_like(h)


def p_wood(n, base, boards=5):
    bh = n / boards
    y = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    row = np.floor(y / bh)
    fy = (y / bh) % 1.0
    seam = np.clip((fy - 0.06) / 0.08, 0, 1) * np.clip((1 - fy - 0.06) / 0.08, 0, 1)
    tone = np.broadcast_to(
        0.76 + _hash2(row.astype(np.int64), np.zeros((1, n), np.int64), 21) * 0.46,
        (n, n)).copy()
    # grain runs along the board: low frequency along it, high across it
    rings = np.abs(np.sin((y / bh * 3.0 + fbm(n, 16, 4, 6) * 5.0) * math.pi))
    streak = fbm(n, 64, 4, 8)
    figure = fbm(n, 12, 4, 9)
    shade = tone * (0.74 + figure * 0.26 + streak * 0.22) * (0.80 + rings * 0.30)
    shade = np.where(seam > 0.5, shade * 0.55, shade)
    alb = tint(base, shade[..., None])
    # Board-to-board colour, not just tone: sawn softwood greys unevenly, and
    # heartwood next to sapwood is a visible step in hue on the same board.
    cast = _hash2(np.broadcast_to(row.astype(np.int64), (n, n)),
                  np.full((n, n), 17, np.int64), 903) * 2.0 - 1.0
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + cast * 0.26 + (streak - 0.5) * 0.10
    hue[..., 1] = 1.0 + cast * 0.10 + (streak - 0.5) * 0.06
    hue[..., 2] = 1.0 - cast * 0.22 + (streak - 0.5) * 0.10
    alb = alb * hue
    h = seam * 0.7 + streak * 0.22 + rings * 0.10
    rough = 0.86 + streak * 0.12
    return alb, h, rough, np.zeros_like(h)


def p_thatch(n, base):
    straw = fbm(n, 8, 3, 3)
    strand = fbm(n, 256, 2, 44)
    # long thin fibres: hash on heavily anisotropic coordinates
    fib = np.zeros((n, n))
    u0 = np.arange(n)[:, None].astype(np.float64)
    v0 = np.arange(n)[None, :].astype(np.float64)
    for s in range(6):
        ang = s * math.pi / 3 + 0.4
        u = (u0 * math.cos(ang) * 26).astype(np.int64)
        v = (v0 * math.sin(ang) * 260).astype(np.int64)
        fib += _hash2(u, v, s * 17 + 3) * 0.16
    clump = fbm(n, 6, 4, 88)
    shade = 0.52 + clump * 0.42 + strand * 0.26 + fib
    alb = tint(base, shade[..., None])
    # Weathered thatch is grey-gold where the sun has bleached it and green-grey
    # where it has not, with new growth still green at the base of each layer.
    age = fbm(n, 4, 4, 223)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (age - 0.5) * 0.30
    hue[..., 1] = 1.0 + (age - 0.5) * 0.14
    hue[..., 2] = 1.0 - (age - 0.5) * 0.30 + (clump - 0.5) * 0.12
    alb = alb * hue
    h = fib * 1.4 + clump * 0.35 + strand * 0.2
    return alb, np.clip(h, 0, 1), 0.97 + strand * 0.03, np.zeros((n, n))


def p_asphalt(n, base):
    """Road surface: grey aggregate set in black tar.

    Not p_soil: asphalt's colour comes from exposed chips of pale stone in a
    dark binder, and a smooth noise ramp on a single dark hue is what left it
    at a colorfulness of 0.019 and reading as a flat lid.
    """
    binder = fbm(n, 10, 4, 331)
    chip_n = fbm(n, 44, 3, 337)
    chips = norm01(value_noise(n, 96, 341))
    shade = 0.46 + binder * 0.26 + chip_n * 0.24
    alb = tint(base, np.clip(shade, 0, 1.5)[..., None])
    # Asphalt's base colour is very dark (#37393c), and a multiplicative hue
    # shift on a dark base barely moves it: +30% of 0.21 is 0.06, which is
    # invisible and leaves the colorfulness at 0.012. The hue has to be applied
    # around the pixel's own luminance rather than around 1.0, so a dark texel
    # gets a proportionally larger swing than a bright one.
    pale = np.clip((chips - 0.40) * 2.6, 0, 1)
    luma = alb.mean(axis=2)
    # target: exposed aggregate is genuinely pale grey stone, the binder
    # between the chips stays near-black. The chips have to get most of the way
    # to real aggregate brightness, or the whole road stays a black lid.
    target = np.empty((n, n, 3))
    target[..., 0] = 0.09 + pale * 0.62
    target[..., 1] = 0.10 + pale * 0.64
    target[..., 2] = 0.12 + pale * 0.66
    alb = np.clip(alb + (target - luma[..., None]) * 0.95, 0.0, 1.0)
    h = chip_n * 0.5 + binder * 0.4 + pale * 0.2
    return alb, h, 0.93 + chip_n * 0.06, np.zeros((n, n))


def p_grass(n, base):
    blades = np.zeros((n, n))
    u0 = np.arange(n)[:, None].astype(np.float64)
    v0 = np.arange(n)[None, :].astype(np.float64)
    for s in range(10):
        ang = s * 0.63 + 0.2
        u = (u0 * math.cos(ang) * 90).astype(np.int64)
        v = (v0 * math.sin(ang) * 220).astype(np.int64)
        blades += _hash2(u, v, s * 31 + 5) * 0.10
    clump = fbm(n, 10, 4, 12)
    patch = fbm(n, 3, 3, 19)
    fine = fbm(n, 96, 3, 23)
    # Dry, dying blades and fresh wet growth are different pigments, not
    # different brightness. The first bake's grass held 61 distinct colours
    # because everything was one green scaled up and down; a meadow is
    # yellow-green through to blue-green, and that spread is most of why a
    # field of grass stops reading as a painted plane.
    dry = fbm(n, 5, 4, 27)
    lush = fbm(n, 8, 3, 29)
    shade = 0.44 + clump * 0.40 + patch * 0.30 + fine * 0.20 + blades
    alb = tint(base, shade[..., None])
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (dry - 0.5) * 0.52 + (lush - 0.5) * 0.10
    hue[..., 1] = 1.0 + (dry - 0.5) * 0.16 + (lush - 0.5) * 0.20
    hue[..., 2] = 1.0 - (dry - 0.5) * 0.46 + (lush - 0.5) * 0.34
    alb = np.broadcast_to(alb, (n, n, 3)) * hue
    h = blades * 1.6 + clump * 0.5 + fine * 0.25
    return alb, np.clip(h, 0, 1), 0.95 + fine * 0.05, np.zeros((n, n))


def p_soil(n, base, clumpy=0.6, gravel=False):
    """Soil, sand, asphalt, clay.

    The important part is that `shade` is not a scalar. Multiplying one hue by a
    brightness ramp keeps every texel on the same line through RGB, which is why
    the first bake gave dirt 21 distinct colours and gravel a colourfulness of
    0.009 — a texture that reads as a flat tinted surface no matter how much
    noise is in it. Real dirt is a mixture: iron-stained, pale silica, damp
    patches. So the base hue is perturbed per texel on two axes before the
    brightness ramp is applied.
    """
    lumps = fbm(n, 14, 5, 61)
    fine = fbm(n, 110, 3, 67)
    spec = norm01(value_noise(n, 150, 71))
    # Two independent slow fields decide which mineral shows through.
    warm = fbm(n, 6, 4, 73)
    cool = fbm(n, 11, 4, 79)
    shade = 0.52 + lumps * clumpy + fine * 0.30
    h = lumps * 0.9 + fine * 0.3

    # per-texel hue drift, centred on the material's own colour
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (warm - 0.5) * 0.55
    hue[..., 1] = 1.0 + (warm - 0.5) * 0.16 + (cool - 0.5) * 0.20
    hue[..., 2] = 1.0 + (cool - 0.5) * 0.55

    if gravel:
        f1, cid, f2 = worley(n, 46, 83, 1.0)
        dome = np.sqrt(np.clip(1.0 - (f1 * 46) ** 2, 0, 1))
        tone = 0.70 + _hash2(cid // 1000, cid, 97) * 0.6
        shade = 0.40 + dome * tone * 0.75 + fine * 0.2
        h = dome * 0.8 + lumps * 0.3
        # Each stone gets its own cast, which is most of what gravel is.
        cast = _hash2(cid // 1000, cid, 151) * 2.0 - 1.0
        stone = _hash2(cid // 1000, cid, 157) * 2.0 - 1.0
        hue[..., 0] = 1.0 + cast * 0.60 + stone * 0.24
        hue[..., 1] = 1.0 + cast * 0.34 + stone * 0.10
        hue[..., 2] = 1.0 - cast * 0.52 - stone * 0.18
    alb = tint(base, np.clip(shade, 0, 1.4)[..., None]) * hue
    return alb, h, 0.96 + fine * 0.05, np.zeros((n, n))


def p_plaster(n, base, pores=True):
    mottle = fbm(n, 7, 4, 41)
    fine = fbm(n, 90, 3, 47)
    shade = 0.86 + mottle * 0.20 + fine * 0.12
    h = mottle * 0.4 + fine * 0.25
    # Concrete is never neutral: it picks up the sky's blue on the exposed
    # faces and a faint warm stain where water has run. A true grey texture
    # measured a colorfulness of 0.008 and read as untextured plastic.
    stain = fbm(n, 3, 4, 181)
    damp = fbm(n, 7, 4, 187)
    alb = tint(base, shade[..., None])
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (stain - 0.5) * 0.44
    hue[..., 1] = 1.0 + (stain - 0.5) * 0.20 + (damp - 0.5) * 0.10
    hue[..., 2] = 1.0 + (0.5 - stain) * 0.34 + (damp - 0.5) * 0.16
    alb = alb * hue
    if pores:
        p = norm01(value_noise(n, 128, 53))
        pits = np.clip((p - 0.86) * 8, 0, 1)
        shade = shade * (1 - pits * 0.35)
        h = h - pits * 0.5
    return alb, h, 0.90 + fine * 0.08, np.zeros((n, n))


def p_metal(n, base, brushed=True, rough=0.34, metal=0.85):
    streak = fbm(n, 4, 2, 29)
    brush = fbm(n, 200, 2, 31)
    patina = fbm(n, 12, 4, 37)
    shade = 0.80 + streak * 0.20 + (brush * 0.16 if brushed else fine_rand(n, 0.12, 43))
    h = (brush * 0.5 + patina * 0.3) if brushed else fine_rand(n, 0.3, 47)
    alb = tint(base, shade[..., None])
    # Bare steel is never neutral either: oxide bloom goes warm orange, the
    # clean roll goes faintly blue. A perfectly grey metal measured a
    # colorfulness of 0.012 and lost every hint of being a real material.
    oxide = fbm(n, 7, 4, 191)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (oxide - 0.5) * 0.30
    hue[..., 1] = 1.0 + (oxide - 0.5) * 0.10
    hue[..., 2] = 1.0 - (oxide - 0.5) * 0.22 + (streak - 0.5) * 0.10
    alb = alb * hue
    return alb, h, np.full((n, n), rough) + brush * 0.10, np.full((n, n), metal)


def fine_rand(n, amp, seed):
    return (fbm(n, 64, 3, seed) - 0.5) * amp


def p_ribbed(n, base, period=8):
    x = np.arange(n)
    ridge = np.abs(np.sin(x / n * math.pi * period))
    dirt = fbm(n, 20, 4, 63)
    shade = 0.62 + ridge * 0.44 - dirt * 0.22
    h = ridge * 0.9 + dirt * 0.15
    alb = tint(base, np.clip(shade, 0.05, 1.4)[..., None])
    return alb, h, 0.46 + dirt * 0.20, np.full((n, n), 0.78)


def p_corrugated(n, base, period=6, along='y'):
    a = np.arange(n)[:, None] if along == 'y' else np.arange(n)[None, :]
    wave = (np.sin(a / n * math.pi * period) * 0.5 + 0.5)
    dirt = fbm(n, 18, 4, 73)
    shade = 0.58 + wave * 0.48 - dirt * 0.20
    h = wave * 0.95 + dirt * 0.12
    alb = tint(base, np.clip(shade, 0.05, 1.4)[..., None])
    # Galvanised sheet is famously blotchy: the spangle pattern is large, high
    # contrast, and drifts from near-white to a dull blue-grey. That mottle is
    # the whole character of the material and it was absent.
    spangle = fbm(n, 4, 4, 293)
    rust = np.clip((fbm(n, 6, 4, 307) - 0.55) * 3.0, 0, 1)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (spangle - 0.5) * 0.30 + rust * 0.55
    hue[..., 1] = 1.0 + (spangle - 0.5) * 0.26 + rust * 0.22
    hue[..., 2] = 1.0 - (spangle - 0.5) * 0.30 - rust * 0.30
    alb = alb * hue
    return alb, h, 0.48 + dirt * 0.18, np.full((n, n), 0.72)


def p_tiles(n, base, rows=9):
    y = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    rh = n / rows
    cw = rh * 1.1
    row = np.floor(y / rh)
    off = np.where(row % 2 > 0.5, 0.5, 0.0)
    col = np.floor(x / cw + off)
    fy = (y / rh) % 1.0
    fx = (x / cw + off) % 1.0
    # rounded lower lip of each course; grooves between tiles in a course
    lip = np.clip(fy / 0.30, 0, 1) * np.clip((1.0 - fy) / 0.06, 0, 1)
    groove = np.clip((fx - 0.03) / 0.06, 0, 1) * np.clip((1 - fx - 0.03) / 0.06, 0, 1)
    tone = 0.72 + _hash2(np.broadcast_to(col.astype(np.int64), (n, n)),
                        np.broadcast_to(row.astype(np.int64), (n, n)), 15) * 0.5
    wear = fbm(n, 30, 4, 17)
    shade = tone * (0.78 + wear * 0.3) * (0.45 + 0.55 * lip) * (0.7 + 0.3 * groove)
    alb = tint(base, np.clip(shade, 0.03, 1.4)[..., None])
    h = lip * groove * 0.8 + wear * 0.2
    return alb, h, 0.80 + wear * 0.14, np.zeros((n, n))


def p_shingle(n, base, rows=10):
    y = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    rh = n / rows
    cw = rh * 1.5
    row = np.floor(y / rh)
    off = np.where(row % 2 > 0.5, 0.5, 0.0)
    col = np.floor(x / cw + off)
    fy = (y / rh) % 1.0
    fx = (x / cw + off) % 1.0
    tab = np.clip((fy - 0.12) / 0.10, 0, 1)
    slit = np.clip((fx - 0.02) / 0.05, 0, 1) * np.clip((1 - fx - 0.02) / 0.05, 0, 1)
    tone = 0.70 + _hash2(np.broadcast_to(col.astype(np.int64), (n, n)),
                        np.broadcast_to(row.astype(np.int64), (n, n)), 27) * 0.5
    grit = fbm(n, 140, 3, 29)
    shade = tone * (0.8 + grit * 0.3) * (0.4 + 0.6 * tab) * (0.72 + 0.28 * slit)
    alb = tint(base, np.clip(shade, 0.03, 1.4)[..., None])
    # Roofing granules are not grey: they are slate blue, brown and mica green
    # mixed together, and at cf=0.003 this read as a solid black lid.
    gran = _hash2(np.broadcast_to(col.astype(np.int64), (n, n)),
                  np.broadcast_to(row.astype(np.int64), (n, n)), 233) * 2.0 - 1.0
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + gran * 0.34
    hue[..., 1] = 1.0 + gran * 0.16
    hue[..., 2] = 1.0 - gran * 0.26
    alb = alb * hue
    h = tab * slit * 0.7 + grit * 0.3
    return alb, h, 0.94 + grit * 0.06, np.zeros((n, n))


def p_panel(n, base, rivets=True, rough=0.5, metal=0.2):
    f1, cid, f2 = worley(n, 4, 55, 0.0)     # panel grid
    gx = np.abs(np.sin(np.arange(n)[:, None] / n * math.pi * 4))
    seam = np.clip((gx - 0.90) / 0.06, 0, 1)
    brush = fbm(n, 256, 2, 59)
    shade = 0.84 + brush * 0.16
    h = brush * 0.4
    if rivets:
        rx = np.arange(n)[:, None] / n * 4
        ry = np.arange(n)[None, :] / n * 4
        fx = (rx % 1) - 0.12
        fy = (ry % 1) - 0.12
        d = np.sqrt(fx * fx + fy * fy)
        riv = np.clip(1.0 - d / 0.045, 0, 1)
        h = h + riv * 0.9
        shade = shade + riv * 0.14
    alb = tint(base, np.clip(shade, 0, 1.5)[..., None])
    # Powder coat chalks and yellows at different rates across a panel, and
    # this material had almost no colour spread at all.
    fade = fbm(n, 4, 4, 277)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (fade - 0.5) * 0.22
    hue[..., 1] = 1.0 + (fade - 0.5) * 0.10
    hue[..., 2] = 1.0 - (fade - 0.5) * 0.20 + (brush - 0.5) * 0.08
    alb = alb * hue
    return alb, np.clip(h, 0, 1.4), np.full((n, n), rough) + brush * 0.08, np.full((n, n), metal)


def p_painted(n, base, rough=0.55):
    orange = fbm(n, 30, 4, 87)      # paint peel / uneven coat
    fine = fbm(n, 120, 2, 89)
    under = (orange > 0.62).astype(np.float64)
    shade = 0.90 + orange * 0.16 + fine * 0.08
    alb = tint(base, shade[..., None])
    alb = alb * (1 - under[..., None] * 0.55) + np.array([0.35, 0.33, 0.31]) * under[..., None]
    h = orange * 0.35 + fine * 0.15
    r = rough + fine * 0.1 + under * 0.3
    return alb, h, r, np.zeros((n, n))


def p_glass(n, base, rough=0.06, metal=0.0):
    smear = fbm(n, 4, 3, 93)
    streak = fbm(n, 120, 2, 97)
    shade = 0.94 + smear * 0.12 + streak * 0.06
    h = smear * 0.2 + streak * 0.1
    alb = tint(base, shade[..., None])
    # Glass seen through picks up whatever is behind it, so the pane itself is
    # very slightly green in transmission and warmer at the surface.
    pane = fbm(n, 6, 3, 251)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 - (pane - 0.5) * 0.10
    hue[..., 1] = 1.0 + (pane - 0.5) * 0.08
    hue[..., 2] = 1.0 + (pane - 0.5) * 0.12
    alb = alb * hue
    return alb, h, np.full((n, n), rough) + smear * 0.06, np.full((n, n), metal)


def p_carbon(n, base):
    x = np.arange(n)[:, None]
    y = np.arange(n)[None, :]
    w = ((x // 6 + y // 6) % 2).astype(np.float64)
    fine = fbm(n, 200, 2, 101)
    shade = 0.80 + w * 0.22 + fine * 0.14
    h = w * 0.5 + fine * 0.2
    alb = tint(base, shade[..., None])
    # The clear-coat resin over carbon weave is what stops it reading as grey
    # graphitic paper: it picks up a faint warm sheen along the tow direction.
    tow = fbm(n, 9, 3, 197)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (tow - 0.5) * 0.26
    hue[..., 1] = 1.0 + (tow - 0.5) * 0.10
    hue[..., 2] = 1.0 - (tow - 0.5) * 0.14
    alb = alb * hue
    return alb, h, 0.30 + fine * 0.10, np.full((n, n), 0.35)


def p_solar(n, base):
    c = n // 3
    x = np.arange(n)[:, None]
    y = np.arange(n)[None, :]
    grid = (np.minimum(x % c, c - 1 - x % c) < 2) | (np.minimum(y % c, c - 1 - y % c) < 2)
    fine = fbm(n, 180, 2, 103)
    shade = np.where(grid, 1.0, 0.82 + fine * 0.2)
    h = np.where(grid, 0.0, fine * 0.3)
    alb = tint(base, shade[..., None])
    # Silver busbars and the anti-reflective coating's blue cast. Without it
    # the whole panel is one colour at a colorfulness of 0.051.
    bus = norm01(value_noise(n, 48, 211))
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 - (bus - 0.5) * 0.10
    hue[..., 1] = 1.0 + (bus - 0.5) * 0.16
    hue[..., 2] = 1.0 + (bus - 0.5) * 0.30
    alb = alb * hue
    return alb, h, np.where(grid, 0.55, 0.10), np.where(grid, 0.0, 0.45)


def p_ore(n, base):
    f1, cid, f2 = worley(n, 11, 109, 1.0)
    dome = np.sqrt(np.clip(1.0 - (f1 * 11) ** 2, 0, 1))
    rust = fbm(n, 20, 4, 111)
    stone = fbm(n, 60, 3, 113)
    # ore blobs: warm metallic against grey host rock
    ore = np.clip((dome - 0.55) * 3.0, 0, 1)
    # The host rock is cold grey-blue, the ore is iron-red; that hue
    # opposition is what makes a vein read as a vein. Brightness alone left
    # the whole material at a colorfulness of 0.019.
    host = tint(np.array([0.40, 0.40, 0.42]), (0.8 + stone * 0.35)[..., None])
    metal_part = tint(np.array([0.62, 0.30, 0.14]), (0.7 + rust * 0.6)[..., None])
    alb = host * (1 - ore[..., None]) + metal_part * ore[..., None]
    band = fbm(n, 9, 4, 311)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (band - 0.5) * 0.34
    hue[..., 1] = 1.0 + (band - 0.5) * 0.12
    hue[..., 2] = 1.0 - (band - 0.5) * 0.30
    alb = alb * hue
    h = dome * 0.7 + stone * 0.25
    return alb, h, 0.80 - ore * 0.30 + stone * 0.1, ore * 0.55


def p_flat(n, base, rough, metal=0.0, amp=0.06):
    """Matte trim / emissive / water: low relief, but never one flat colour.

    A brightness-only ramp on a single hue is what made water measure 10
    distinct colours and look like painted plastic. Even a surface this smooth
    picks up a slow colour drift across it — water reads as depth, an emissive
    strip as a gradient along its length, trim as whatever light falls on it.
    """
    f = fine_rand(n, amp, 107)
    m = fbm(n, 6, 3, 109)
    slow = fbm(n, 3, 3, 263)
    alb = tint(base, (0.95 + m * 0.1 + f)[..., None])
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (slow - 0.5) * 0.34
    hue[..., 1] = 1.0 + (slow - 0.5) * 0.16
    hue[..., 2] = 1.0 + (m - 0.5) * 0.20 + (0.5 - slow) * 0.18
    alb = alb * hue
    h = f * 0.4 + m * 0.2
    return alb, h, np.full((n, n), rough) + m * 0.05, np.full((n, n), metal)


# ---------------------------------------------------------------- table
# name -> (builder, base colour, bump strength)
# Colours mirror VoxelTypes.PROPS exactly.

def build_all(n, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    S = lambda h: hexcol(h)
    SPECS = {
        "timber":           (lambda: p_wood(n, S("#7d5a3c"), 4), 0.7),
        "plank":            (lambda: p_wood(n, S("#a8804f"), 5), 0.7),
        "dark_oak":         (lambda: p_wood(n, S("#4a3524"), 4), 0.7),
        "bark":             (lambda: p_wood(n, S("#4f3b28"), 3), 1.0),
        "brick":            (lambda: p_brick(n, S("#98462f")), 1.0),
        "sandstone":        (lambda: p_stone(n, S("#c9ac7c"), 7, 0.92), 0.9),
        "granite":          (lambda: p_stone(n, S("#5e5b58"), 13, 0.72), 0.9),
        "cobble":           (lambda: p_stone(n, S("#66625c"), 8, 0.88), 1.1),
        "stone":            (lambda: p_stone(n, S("#55524f"), 10, 0.93), 0.9),
        "rock":             (lambda: p_stone(n, S("#6a6560"), 5, 0.95), 1.2),
        "concrete":         (lambda: p_plaster(n, S("#9d9c98")), 0.6),
        "rebar_concrete":   (lambda: p_rebar(n, S("#88898a")), 0.8),
        "concrete_slab":    (lambda: p_slab(n, S("#807f79")), 0.6),
        "steel_frame":      (lambda: p_metal(n, S("#5a6068"), True, 0.45, 0.85), 0.6),
        "corrugated_steel": (lambda: p_corrugated(n, S("#7e878e"), 6), 1.3),
        "sheet_metal":      (lambda: p_panel(n, S("#8b949b"), False, 0.40, 0.80), 0.6),
        "plastic_panel":    (lambda: p_panel(n, S("#d8d4c8"), True, 0.55, 0.0), 0.6),
        "carbon_composite": (lambda: p_carbon(n, S("#2c2f34")), 0.7),
        "solar_panel":      (lambda: p_solar(n, S("#1a2a4a")), 0.5),
        "thatch":           (lambda: p_thatch(n, S("#b39152")), 1.4),
        "clay_tile":        (lambda: p_tiles(n, S("#8f4630"), 9), 1.1),
        "asphalt_shingle":  (lambda: p_shingle(n, S("#40403f"), 10), 1.0),
        "dirt":             (lambda: p_soil(n, S("#6b533a"), 0.6), 0.8),
        "gravel":           (lambda: p_soil(n, S("#736e63"), 0.4, True), 1.1),
        "farmland":         (lambda: p_farm(n, S("#6a4c2f")), 0.9),
        "wet_farmland":     (lambda: p_farm(n, S("#43301d"), wet=True), 0.8),
        "asphalt":          (lambda: p_asphalt(n, S("#37393c")), 0.6),
        "grass":            (lambda: p_grass(n, S("#496f38")), 1.2),
        "sand":             (lambda: p_sand(n, S("#c0aa7d")), 0.7),
        "leaf":             (lambda: p_leaf(n, S("#3f6b30")), 1.3),
        "clay":             (lambda: p_soil(n, S("#9c6a4e"), 0.45), 0.7),
        "iron_ore":         (lambda: p_ore(n, S("#8a6a52")), 1.0),
        "painted_white":    (lambda: p_painted(n, S("#e6e3da"), 0.72), 0.5),
        "painted_red":      (lambda: p_painted(n, S("#a3352c"), 0.72), 0.5),
        "chrome":           (lambda: p_metal(n, S("#c6cbd0"), True, 0.12, 1.0), 0.5),
        "matte_black":      (lambda: p_flat(n, S("#1f2124"), 0.86, 0.10, 0.30), 0.4),
        "neon_strip":       (lambda: p_flat(n, S("#63e8ff"), 0.30, 0.0, 0.03), 0.3),
        "ember":            (lambda: p_flat(n, S("#ff7a2a"), 0.90, 0.0, 0.25), 0.8),
        "glass":            (lambda: p_glass(n, S("#a9d4de"), 0.06), 0.3),
        "reinforced_glass": (lambda: p_glass(n, S("#9ec4d0"), 0.10), 0.3),
        "water":            (lambda: p_flat(n, S("#27536b"), 0.04, 0.0, 0.10), 0.5),
    }
    names = []
    for name, (fn, bump) in SPECS.items():
        alb, h, rough, metal = fn()
        # Builders work in whatever broadcast shape is convenient (many use
        # (n,1)/(1,n) rows and columns); everything downstream wants (n,n).
        h = np.broadcast_to(np.asarray(h, dtype=np.float64), (n, n))
        rough = np.broadcast_to(np.asarray(rough, dtype=np.float64), (n, n))
        metal = np.broadcast_to(np.asarray(metal, dtype=np.float64), (n, n))
        alb = np.broadcast_to(np.asarray(alb, dtype=np.float64), (n, n, 3))
        ao = cavity_ao(h)
        nrm = height_to_normal(h, bump)
        orm = np.stack([ao, np.clip(rough, 0.02, 1.0), np.clip(metal, 0.0, 1.0)], axis=-1)
        # albedo carries the material's own AO so crevices read dark even before
        # the light does
        alb = np.clip(alb * (0.55 + 0.45 * ao[..., None]), 0, 1)
        for suffix, arr in (("a", alb), ("n", nrm), ("o", orm)):
            img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")
            img.save(os.path.join(out_dir, f"{name}_{suffix}.png"), optimize=True)
        names.append(name)
        print(f"  {name}", flush=True)

    # layer order == the table order, so the shader can use one index per
    # material and never consult a map at runtime
    with open(os.path.join(out_dir, "layers.txt"), "w", encoding="utf-8") as fh:
        for i, n in enumerate(names):
            fh.write(f"{i} {n}\n")
    print(f"baked {len(names)} materials -> {out_dir}")


# ---------------------------------------------------------------- late binds
def p_rebar(n, base):
    f1, cid, f2 = worley(n, 6, 55, 0.0)
    x = np.arange(n)[:, None] / n
    y = np.arange(n)[None, :] / n
    bar = np.clip(1.0 - np.abs(np.sin(y * math.pi * 6)) * 6.0, 0, 1)
    rust = fbm(n, 16, 4, 115)
    grit = fbm(n, 110, 3, 117)
    shade = 0.86 + grit * 0.18 + rust * 0.16
    alb = tint(base, shade[..., None])
    steel = np.array([0.45, 0.36, 0.30])
    alb = np.where(bar[..., None] > 0.5, steel * (0.7 + rust[..., None] * 0.6), alb)
    # The pour around the rebar is stained orange where the rust has run down
    # it, which is the only colour the material has and it was being lost.
    bleed = np.clip((fbm(n, 8, 4, 269) - 0.45) * 2.4, 0, 1) * (1.0 - bar)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + bleed * 0.42
    hue[..., 1] = 1.0 + bleed * 0.18
    hue[..., 2] = 1.0 - bleed * 0.24
    alb = alb * hue
    h = bar * 0.8 + grit * 0.25
    return alb, np.clip(h, 0, 1.2), 0.86 + grit * 0.1, bar * 0.45


def p_slab(n, base):
    bh = n / 2
    y = np.arange(n)[:, None]
    x = np.arange(n)[None, :]
    fy = y % bh
    # build out of place: y is (n,1) and x is (1,n), so *= cannot broadcast back
    jy = np.clip((fy - 0.02) / 0.05, 0, 1) * np.clip((bh - fy - 0.02) / 0.05, 0, 1)
    jx = np.clip((x - 0.02) / 0.05, 0, 1) * np.clip((n - x - 0.02) / 0.05, 0, 1)
    joint = jy * jx
    mottle = fbm(n, 9, 4, 119)
    grit = fbm(n, 120, 3, 121)
    pits = norm01(value_noise(n, 140, 123))
    shade = 0.84 + mottle * 0.22 + grit * 0.14
    shade = shade * (1 - np.clip((pits - 0.88) * 9, 0, 1) * 0.3)
    alb = tint(base, (shade * (0.55 + 0.45 * (1 - joint)))[..., None])
    stain = fbm(n, 3, 4, 239)
    damp = fbm(n, 6, 3, 241)
    # Same luminance-relative trick as asphalt: a mid-grey base means a
    # multiplicative shift around 1.0 is too small to register, and the slab was
    # the second-least colourful material in the set at 0.012.
    luma = alb.mean(axis=2)          # (n,n) — mean over channels, not keepdims
    target = np.empty((n, n, 3))
    warm = (stain - 0.5) * 2.0
    cool = (damp - 0.5) * 2.0
    target[..., 0] = luma + warm * 0.16 + cool * 0.05
    target[..., 1] = luma + warm * 0.07 + cool * 0.05
    target[..., 2] = luma - warm * 0.12 - cool * 0.07
    alb = np.clip(alb + (target - luma[..., None]) * 0.9, 0.0, 1.0)
    h = (1 - joint) * 0.5 + mottle * 0.3 + grit * 0.2
    return alb, h, 0.90 + grit * 0.08, np.zeros((n, n))


def p_farm(n, base, wet=False):
    bh = n / 7
    y = np.arange(n)[:, None]
    furrow = np.sin(y / bh * math.pi) * 0.5 + 0.5
    soil = fbm(n, 22, 5, 127)
    clod = fbm(n, 70, 3, 129)
    shade = 0.50 + furrow * 0.42 + clod * 0.24
    alb = tint(base, shade[..., None])
    # Ploughed earth is redder in the furrow where the subsoil is turned up and
    # greyer on the crust, and it was measuring 13 distinct colours.
    turned = fbm(n, 5, 4, 283)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + (turned - 0.5) * 0.36
    hue[..., 1] = 1.0 + (turned - 0.5) * 0.12
    hue[..., 2] = 1.0 - (turned - 0.5) * 0.30
    alb = alb * hue
    h = furrow * 0.7 + clod * 0.4
    r = 0.94 if not wet else 0.62
    if wet:
        alb = alb * 0.9
    return alb, h, np.full((n, n), r) - clod * 0.06, np.zeros((n, n))


def p_sand(n, base):
    dune = fbm(n, 6, 4, 131)
    ripple = np.abs(np.sin((np.arange(n)[:, None] / n * 22 + dune * 2.4) * math.pi))
    grain = fbm(n, 180, 3, 133)
    # Sand is not one colour: heavy minerals make the dark grains, and the
    # pale ones are almost quartz. Both are hue shifts, not brightness shifts.
    dark = norm01(value_noise(n, 240, 137))
    shade = 0.74 + dune * 0.28 + ripple * 0.16 + grain * 0.12
    alb = tint(base, np.clip(shade, 0, 1.4)[..., None])
    hue = np.empty((n, n, 3))
    tint_amt = (dune - 0.5) * 0.30
    hue[..., 0] = 1.0 + tint_amt + (dark - 0.5) * 0.18
    hue[..., 1] = 1.0 + tint_amt * 0.5 + (dark - 0.5) * 0.10
    hue[..., 2] = 1.0 - tint_amt * 0.8 + (dark - 0.5) * 0.22
    alb = alb * hue
    h = ripple * 0.5 + dune * 0.3 + grain * 0.2
    return alb, h, 0.98 + grain * 0.02, np.zeros((n, n))


def p_leaf(n, base):
    f1, cid, f2 = worley(n, 14, 137, 1.0)
    dome = np.sqrt(np.clip(1.0 - (f1 * 14) ** 2, 0, 1))
    tone = 0.62 + _hash2(cid // 1000, cid, 139) * 0.7
    vein = fbm(n, 70, 3, 141)
    shade = tone * (0.7 + vein * 0.45) * (0.5 + 0.5 * dome)
    alb = tint(base, shade[..., None])
    # Foliage has the widest hue range of anything in the world: new growth is
    # yellow-green, shaded interior leaves go blue-green, and stressed leaves
    # turn ochre. All three in one texture is what stops a canopy reading as
    # a single green mass.
    age = _hash2(cid // 1000, cid, 313) * 2.0 - 1.0
    light = fbm(n, 8, 3, 317)
    hue = np.empty((n, n, 3))
    hue[..., 0] = 1.0 + age * 0.30 + (light - 0.5) * 0.18
    hue[..., 1] = 1.0 + age * 0.12 + (light - 0.5) * 0.22
    hue[..., 2] = 1.0 - age * 0.26 - (light - 0.5) * 0.20
    alb = alb * hue
    h = dome * 0.7 + vein * 0.4
    return alb, h, 0.95 + vein * 0.05, np.zeros((n, n))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out", default="assets/tex")
    a = ap.parse_args()
    build_all(a.size, a.out)
