"""Bake tileable PBR texture layers for every DELEGATE voxel material.

Run:  python _tools/gen_pbr.py [--size 512] [--out assets/tex_web]

Why generated rather than downloaded: no accounts, no network at build time, no
licence questions, and the palette stays locked to the material table.

Every layer is seamless (all noise hashes wrap on the tile period, all stamped
strokes wrap around the edges). A voxel face is a 0.25 m quad, so a seam on a
wall is a line running the whole height of a building.

Output per material: <name>_a.png albedo, _n.png normal, _o.png ORM
(R = ambient occlusion, G = roughness, B = metallic).

Albedo PNGs are authored in sRGB, the way a painter picks colours. The shader
decodes them to linear light (voxel_common.gdshaderinc), so a value here of
0.30 on a channel is a real-world reflectance of about 0.07. Keep mean values
mid-range: realistic surfaces are 0.2-0.6 linear, never near white.

The look targets a realistic PBR resource pack: individual stones with mortar
and crevice AO, painted grass blades and leaf clusters, straw bundles, boards
with grain and butt joints. Shapes come from wrapped Worley cells and from
stamped strokes (blades, straws, leaves) rather than from plain noise, which is
what makes a texture read as an object instead of as a smudge.
"""
import argparse
import math
import os
import numpy as np
from PIL import Image

# ---------------------------------------------------------------- noise

def _hash2(ix, iy, seed):
    h = (np.asarray(ix).astype(np.int64) * 374761393
         + np.asarray(iy).astype(np.int64) * 668265263
         + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / 0x1000000


def _grid(n):
    y, x = np.mgrid[0:n, 0:n]
    return x / n, y / n


def noise2(n, fx, fy, seed):
    """Tileable value noise in [0,1] with independent integer frequencies.

    The lattice hash wraps at fx / fy, so the tile repeats exactly; unequal
    frequencies give the streaks (wood grain, straw, bark) isotropic noise
    cannot.
    """
    X, Y = _grid(n)
    u = X * fx
    v = Y * fy
    iu = np.floor(u).astype(np.int64)
    iv = np.floor(v).astype(np.int64)
    fu = u - iu
    fv = v - iv
    fu = fu * fu * fu * (fu * (fu * 6 - 15) + 10)
    fv = fv * fv * fv * (fv * (fv * 6 - 15) + 10)
    i0 = iu % fx
    i1 = (iu + 1) % fx
    j0 = iv % fy
    j1 = (iv + 1) % fy
    a = _hash2(i0, j0, seed)
    b = _hash2(i1, j0, seed)
    c = _hash2(i0, j1, seed)
    d = _hash2(i1, j1, seed)
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def value_noise(n, freq, seed):
    return noise2(n, freq, freq, seed)


def fbm(n, freq, octaves, seed, gain=0.5):
    total = np.zeros((n, n))
    amp = 1.0
    norm = 0.0
    f = freq
    for i in range(octaves):
        total += amp * noise2(n, f, f, seed + i * 977)
        norm += amp
        amp *= gain
        f *= 2
    return total / norm


def worley(n, cells, seed, jitter=0.9, warp=0.0):
    """Tileable, optionally domain-warped Worley/Voronoi.

    Returns a dict: f1, f2 (in cell units), id (0..1 per cell) and dx, dy (the
    offset from the nearest feature point, for tilting each stone's facet).
    """
    X, Y = _grid(n)
    U = X * cells
    V = Y * cells
    if warp > 0:
        U = U + (fbm(n, 5, 3, seed + 11) - 0.5) * 2.0 * warp
        V = V + (fbm(n, 5, 3, seed + 23) - 0.5) * 2.0 * warp
    iu = np.floor(U).astype(np.int64)
    iv = np.floor(V).astype(np.int64)
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    cid = np.zeros((n, n))
    ox = np.zeros((n, n))
    oy = np.zeros((n, n))
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            cx = iu + dx
            cy = iv + dy
            hx = _hash2(cx % cells, cy % cells, seed)
            hy = _hash2(cx % cells, cy % cells, seed + 313)
            px = cx + 0.5 + (hx - 0.5) * jitter
            py = cy + 0.5 + (hy - 0.5) * jitter
            d = np.sqrt((U - px) ** 2 + (V - py) ** 2)
            m = d < f1
            f2 = np.where(m, f1, np.minimum(f2, d))
            cid = np.where(m, _hash2(cx % cells, cy % cells, seed + 771), cid)
            ox = np.where(m, U - px, ox)
            oy = np.where(m, V - py, oy)
            f1 = np.where(m, d, f1)
    return dict(f1=f1, f2=f2, id=cid, dx=ox, dy=oy)


def norm01(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo) if hi > lo else np.zeros_like(a)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- helpers

def hexcol(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def C(*v):
    return np.array(v, dtype=np.float64)


def pick(palette, t):
    """Choose a palette colour per texel from a 0..1 field. Returns (n,n,3)."""
    p = np.asarray(palette)
    idx = np.minimum((t * len(p)).astype(np.int64), len(p) - 1)
    return p[idx]


def mixc(a, b, t):
    t = np.asarray(t)[..., None]
    return a * (1 - t) + b * t


def _boxblur(a, radius):
    """Wrapped separable box blur (cumulative sums), same size in and out."""
    r = max(int(radius), 1)

    def blur1(m):
        ext = np.concatenate([m, m, m], axis=0)
        z = np.zeros((1,) + m.shape[1:])
        c = np.cumsum(np.concatenate([z, ext, z], axis=0), axis=0)
        w = 2 * r + 1
        starts = np.arange(len(m)) + len(m) - r
        return (c[starts + w] - c[starts]) / w

    return blur1(blur1(a.T).T)


def height_to_normal(height, strength=1.0):
    """Central differences over a wrapping height field -> tangent-space normal."""
    h = height.astype(np.float64)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength * 10.0
    ny = -dy * strength * 10.0
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], axis=-1)


def cavity_ao(height, radius=6):
    """Crevice darkening: how far a texel sits below its blurred neighbourhood."""
    h = height
    c = (h - _boxblur(h, radius)) / (h.std() + 1e-6)
    ao = 1.0 + 0.30 * np.minimum(c, 0.0) + 0.04 * np.maximum(c, 0.0)
    # deep slots (mortar, grout, fissures) fall well below the local mean
    ao = ao * (0.75 + 0.25 * sstep(0.0, 0.25, h - h.min()))
    return np.clip(ao, 0.5, 1.0)


def paint_stroke(canvas, hmap, n, cx, cy, ang, length, width, col0, col1,
                 height, taper=0.7, leaf=False, rib=None):
    """Stamp one blade / straw / leaf onto the wrapped canvases (painter's order)."""
    half = int(length + width) + 2
    ys = np.arange(int(cy) - half, int(cy) + half + 1)
    xs = np.arange(int(cx) - half, int(cx) + half + 1)
    YY, XX = np.meshgrid(ys, xs, indexing="ij")
    dx = XX - cx
    dy = YY - cy
    ca, sa = math.cos(ang), math.sin(ang)
    t = dx * ca + dy * sa
    d = -dx * sa + dy * ca
    tt = t / length
    inside = (tt >= 0) & (tt <= 1)
    if leaf:
        hw = width * 0.5 * np.sin(np.clip(tt, 0, 1) * math.pi) ** 0.75
    else:
        hw = width * 0.5 * (1.0 - taper * np.clip(tt, 0, 1))
    a = np.clip(hw + 0.6 - np.abs(d), 0.0, 1.0) * inside
    if not a.any():
        return
    col = col0[None, None, :] * (1 - np.clip(tt, 0, 1))[..., None] \
        + col1[None, None, :] * np.clip(tt, 0, 1)[..., None]
    if rib is not None:
        line = np.clip(1.0 - np.abs(d) / 0.9, 0, 1) * inside
        col = col * (1 - line[..., None] * rib) + col * 0 + line[..., None] * rib * col * 1.25
    iy = YY % n
    ix = XX % n
    a3 = a[..., None]
    canvas[iy, ix] = canvas[iy, ix] * (1 - a3) + col * a3
    hh = height * (0.55 + 0.45 * np.sin(np.clip(tt, 0, 1) * math.pi * 0.5 + 0.2))
    if leaf:
        hh = height * (0.55 + 0.45 * (1.0 - np.abs(d) / (hw + 1e-3)))
    hmap[iy, ix] = hmap[iy, ix] * (1 - a) + hh * a


# ---------------------------------------------------------------- patterns
# Each returns (albedo[n,n,3] sRGB, height[n,n], rough[n,n], metal[n,n]).

def p_stones(n, palette, cells, seed, jitter=0.85, warp=0.4, grout=None,
             grout_w=0.07, shoulder=0.30, grain_amp=0.10, moss=0.0,
             tilt=0.10):
    """Irregular stones set in mortar or soil: cobble, flagstone, rock, granite."""
    w = worley(n, cells, seed, jitter, warp)
    e = (w["f2"] - w["f1"]) * 1.0          # cell units, 0 on the joint
    body = sstep(grout_w * 0.6, grout_w + shoulder, e)
    inner = e > grout_w * 0.9
    tone = 0.86 + 0.28 * _hash2(w["id"] * 997, w["id"] * 331, seed + 5)
    grain = fbm(n, 48, 4, seed + 31)
    fleck = noise2(n, 220, 220, seed + 41)
    base = pick(palette, w["id"])
    stone = base * (tone * (0.86 + grain_amp * 2.4 * (grain - 0.5) + 0.14))[..., None]
    stone = stone * (0.90 + 0.14 * fleck)[..., None]
    # rounded shoulder darkens toward the joint, as if the stone rolls away
    stone = stone * (0.76 + 0.24 * body)[..., None]
    # weathering: patches of paler dust and darker wet on each stone
    weather = fbm(n, 9, 4, seed + 57)
    stone = stone * (0.92 + 0.18 * weather)[..., None]
    if grout is None:
        grout = C(0.30, 0.27, 0.22)
    gr = fbm(n, 90, 3, seed + 67)
    grout_col = grout[None, None, :] * (0.7 + 0.6 * gr)[..., None]
    alb = np.where(inner[..., None], stone, grout_col)
    alb = mixc(grout_col, alb, sstep(grout_w * 0.5, grout_w * 1.4, e))
    if moss > 0:
        m = sstep(0.55, 0.75, fbm(n, 6, 4, seed + 77)) * moss * (1 - body)
        alb = mixc(alb, C(0.20, 0.34, 0.12) * (0.8 + 0.4 * gr)[..., None], m)
    facet = (w["dx"] * math.cos(w["id"].mean() * 6.28 + 1.0)
             + w["dy"] * math.sin(w["id"].mean() * 6.28 + 1.0)) * tilt
    facet = tilt * (w["dx"] * (_hash2(w["id"] * 9973, 3, seed) - 0.5)
                    + w["dy"] * (_hash2(w["id"] * 7919, 5, seed) - 0.5)) * 2.0
    h = body * 0.75 + facet + (grain - 0.5) * 0.10 * body + fleck * 0.02
    rough = np.where(inner, 0.86 + grain * 0.10, 0.98)
    return alb, h, rough, np.zeros((n, n))


def p_coursed(n, palette, rows, cols, seed, mortar_col, joint=0.06,
              tone_var=0.28, hue_var=0.0, strata=0.0, pit=0.12, stagger=0.5,
              chamfer=0.10, round_h=0.55):
    """Staggered rectangular units in mortar: brick, sandstone blocks."""
    y = np.arange(n)[:, None].astype(np.float64)
    x = np.arange(n)[None, :].astype(np.float64)
    bh, bw = n / rows, n / cols
    row = np.floor(y / bh)
    off = np.where(row % 2 > 0.5, stagger, 0.0)
    col = np.floor(x / bw + off)
    fy = (y / bh) % 1.0
    fx = (x / bw + off) % 1.0
    ri = np.broadcast_to(row.astype(np.int64), (n, n))
    ci = np.broadcast_to((col % cols).astype(np.int64), (n, n))
    # distance to the unit's own edge, in unit-relative terms
    dy_ = np.minimum(fy, 1 - fy) * bh / n * rows
    dx_ = np.minimum(fx, 1 - fx) * bw / n * cols
    ed = np.minimum(dy_ * (rows / cols), dx_)   # roughly isotropic
    dist_px = np.minimum(np.minimum(fy, 1 - fy) * bh, np.minimum(fx, 1 - fx) * bw)
    jp = joint * n / 12.0 * 1.6                  # joint half-width in pixels
    body = sstep(jp * 0.6, jp + chamfer * n / 12.0 * 2.2, dist_px)
    inner = dist_px > jp * 0.8
    t = _hash2(ci, ri, seed)
    tone = 1.0 + (t - 0.5) * 2.0 * tone_var
    grit = fbm(n, 96, 4, seed + 9)
    fine = noise2(n, 200, 200, seed + 13)
    base = pick(palette, _hash2(ci, ri, seed + 3))
    face = base * (tone * (0.86 + 0.28 * grit) * (0.94 + 0.12 * fine))[..., None]
    if hue_var:
        fire = _hash2(ci // 2, ri // 3, seed + 21) - 0.5
        face = face * np.stack([1 + fire * hue_var, 1 - fire * hue_var * 0.3,
                                1 - fire * hue_var * 0.8], axis=-1)
    if strata:
        s = np.sin((y / n * rows * 5.0 + fbm(n, 4, 3, seed + 33) * 4.0) * math.pi)
        face = face * (1 + s * strata)[..., None]
    face = face * (0.80 + 0.20 * body)[..., None]
    # pits and pores
    p = norm01(noise2(n, 150, 150, seed + 17))
    pits = sstep(1 - pit, 1.0, p)
    face = face * (1 - 0.35 * pits)[..., None]
    mgr = fbm(n, 110, 3, seed + 19)
    mort = mortar_col[None, None, :] * (0.72 + 0.5 * mgr)[..., None]
    alb = np.where(inner[..., None], face, mort)
    alb = mixc(mort, alb, sstep(jp * 0.5, jp * 1.3, dist_px))
    h = body * round_h + grit * 0.10 - pits * 0.12
    return alb, h, np.where(inner, 0.90 + grit * 0.08, 0.98), np.zeros((n, n))


def p_planks(n, boards, palette, seed, grain_contrast=1.0, knots=True,
             gap=0.05, rough_base=0.82, weather=0.0):
    """Horizontal boards with staggered butt joints, growth rings and knots."""
    y = np.arange(n)[:, None].astype(np.float64)
    x = np.arange(n)[None, :].astype(np.float64)
    bh = n / boards
    row = np.floor(y / bh).astype(np.int64)
    fy = (y / bh) % 1.0
    rowb = np.broadcast_to(row, (n, n))
    # butt joints: each board is split in two at a random x
    split = (_hash2(np.arange(boards), np.zeros(boards, np.int64), seed + 2) * 0.7
             + 0.15) * n
    sp = split[rowb]
    seg = (x > sp).astype(np.int64)
    dj = np.abs(x - sp)
    dj = np.minimum(dj, np.minimum(np.abs(x - sp - n), np.abs(x - sp + n)))
    joint = 1.0 - sstep(0.5, 3.0, dj) * 1.0
    bid = rowb * 2 + seg
    tone = 0.82 + 0.36 * _hash2(bid, np.zeros_like(bid), seed + 5)
    base = pick(palette, _hash2(bid, np.ones_like(bid), seed + 6))
    # growth rings drawn as stretched sinusoids bent by low-frequency noise;
    # the local coordinate across the board is what runs them
    bend = fbm(n, 5, 3, seed + 8) * 2.4 + noise2(n, 3, boards * 3, seed + 12) * 3.0
    cross = fy * 5.0 + bend + _hash2(bid, 7, seed + 14) * 10
    rings = 0.5 + 0.5 * np.sin(cross * math.pi * 2)
    rings = rings ** 1.5
    streak = noise2(n, 6, n // 3, seed + 16)
    fibre = noise2(n, 3, n // 2, seed + 18)
    shade = tone * (0.80 + (0.16 * rings + 0.14 * streak + 0.06 * fibre) * grain_contrast)
    alb = base * shade[..., None]
    if knots:
        kn = np.zeros((n, n))
        for k in range(boards * 1):
            r = np.random.default_rng(seed * 31 + k)
            if r.random() < 0.6:
                kx = r.random() * n
                ky = (k + 0.3 + r.random() * 0.4) * bh
                dxk = np.minimum(np.abs(x - kx), n - np.abs(x - kx))
                dyk = np.minimum(np.abs(y - ky), n - np.abs(y - ky))
                d = np.sqrt((dxk / 2.6) ** 2 + (dyk / 1.2) ** 2) / (n / 90.0)
                kn = np.maximum(kn, np.clip(1 - d / 6.0, 0, 1))
                kn = np.maximum(kn, 0.0)
        ringk = 0.5 + 0.5 * np.sin(kn * 22.0)
        alb = alb * (1 - 0.35 * (kn > 0.02) * (0.5 + 0.5 * ringk))[..., None]
    seam = np.clip(1.0 - sstep(gap * 0.4, gap + 0.08, np.minimum(fy, 1 - fy)), 0, 1)
    alb = alb * (1 - 0.68 * seam)[..., None]
    alb = alb * (1 - 0.55 * joint)[..., None]
    if weather:
        gr = fbm(n, 7, 4, seed + 40)
        alb = mixc(alb, np.mean(alb, axis=2, keepdims=True) * C(1.0, 0.98, 0.92), weather * gr)
    h = (1 - seam) * 0.55 + (1 - joint) * 0.2 + rings * 0.10 * grain_contrast + streak * 0.08
    rough = rough_base + streak * 0.10
    return alb, h, rough, np.zeros((n, n))


def p_bark(n, seed=3):
    """Deep vertical fissures with scaly plates."""
    warp = fbm(n, 4, 3, seed + 5) * 1.6
    ridge = noise2(n, 22, 4, seed) * 0.6 + noise2(n, 44, 9, seed + 1) * 0.4
    r = np.abs(np.sin((ridge * 6.0 + warp) * math.pi)) ** 0.7
    plate = noise2(n, 10, 30, seed + 2)
    fine = noise2(n, 140, 140, seed + 3)
    shade = 0.45 + 0.55 * r
    pal = [C(0.30, 0.22, 0.15), C(0.36, 0.27, 0.18), C(0.26, 0.20, 0.15), C(0.33, 0.26, 0.19)]
    base = pick(pal, plate)
    alb = base * (shade * (0.85 + 0.3 * fine))[..., None]
    lichen = sstep(0.70, 0.85, fbm(n, 6, 4, seed + 9))
    alb = mixc(alb, C(0.32, 0.36, 0.22) * (0.8 + 0.4 * fine)[..., None], lichen * 0.45 * r)
    h = r * 0.85 + fine * 0.08
    return alb, h, 0.95 - 0.06 * r, np.zeros((n, n))


def p_thatch(n, seed=7):
    """Layered courses of straw bundles, each strand painted."""
    rng = np.random.default_rng(seed)
    canvas = np.tile(C(0.20, 0.15, 0.08), (n, n, 1))
    hmap = np.zeros((n, n))
    courses = 6
    ch = n / courses
    pal = [C(0.72, 0.56, 0.28), C(0.64, 0.49, 0.24), C(0.80, 0.66, 0.36),
           C(0.55, 0.42, 0.20), C(0.70, 0.60, 0.38), C(0.60, 0.50, 0.30)]
    for c in range(courses):
        cy0 = c * ch
        bundle_w = n / 12
        for i in range(int(n * 0.95)):
            bx = rng.random() * n
            ang = math.pi / 2 + (rng.random() - 0.5) * 0.28
            # strands start a little above the course and hang below it
            cy = cy0 - ch * 0.15 + rng.random() * ch * 0.35
            L = ch * (0.95 + rng.random() * 0.55)
            g = 0.75 + 0.5 * math.sin((bx / bundle_w) * 2.4 + c) * 0.5
            col1 = pal[rng.integers(len(pal))] * (0.85 + rng.random() * 0.35) * g
            col0 = col1 * 0.55
            paint_stroke(canvas, hmap, n, bx, cy, ang, L, 1.5 + rng.random() * 1.6,
                         col0, col1, 0.25 + c / courses * 0.25 + rng.random() * 0.2, taper=0.5)
    # course overlap shadow: dark band just under each ragged edge
    ys = (np.arange(n)[:, None] % ch) / ch
    ragged = noise2(n, 40, courses, seed + 1) * 0.08
    canvas = canvas * (0.60 + 0.40 * np.clip(ys * 3.0, 0, 1))[..., None]
    age = fbm(n, 4, 3, seed + 3)
    canvas = canvas * np.stack([1 + (age - 0.5) * 0.18, np.ones_like(age), 1 - (age - 0.5) * 0.26], axis=-1)
    return canvas, hmap + (1 - ys) * 0.0 + np.clip(ys * 2.0, 0, 1) * 0.25, \
        0.95 + 0.04 * noise2(n, 30, 30, seed), np.zeros((n, n))


def p_tiles(n, base, rows=8, seed=15):
    """Overlapping curved clay roof tiles."""
    y = np.arange(n)[:, None].astype(np.float64)
    x = np.arange(n)[None, :].astype(np.float64)
    rh = n / rows
    cw = rh * 0.95
    cols = int(round(n / cw))
    cw = n / cols
    row = np.floor(y / rh)
    off = np.where(row % 2 > 0.5, 0.5, 0.0)
    colf = x / cw + off
    col = np.floor(colf)
    fy = (y / rh) % 1.0
    fx = colf % 1.0
    ri = np.broadcast_to(row.astype(np.int64), (n, n))
    ci = np.broadcast_to((col % cols).astype(np.int64), (n, n))
    # each tile is a half-round barrel: cross-section lit on one flank
    barrel = np.sin(fx * math.pi)
    slope = np.cos(fx * math.pi)
    lip = sstep(0.0, 0.7, fy) * (1 - sstep(0.90, 1.0, fy) * 0.9)
    t = _hash2(ci, ri, seed)
    pal = [C(0.55, 0.30, 0.22), C(0.61, 0.34, 0.25), C(0.49, 0.27, 0.20),
           C(0.59, 0.38, 0.28), C(0.45, 0.26, 0.20)]
    baseg = pick(pal, _hash2(ci, ri, seed + 4))
    wear = fbm(n, 30, 4, seed + 2)
    alb = baseg * ((0.80 + 0.26 * t) * (0.86 + 0.28 * wear) * (0.52 + 0.48 * lip)
                   * (0.80 + 0.20 * barrel) * (1 + 0.10 * slope))[..., None]
    moss = sstep(0.62, 0.8, fbm(n, 8, 4, seed + 7)) * (1 - lip * 0.6)
    alb = mixc(alb, C(0.25, 0.33, 0.15) * (0.8 + 0.4 * wear)[..., None], moss * 0.5)
    groove = sstep(0.0, 0.10, np.minimum(fx, 1 - fx))
    alb = alb * (0.62 + 0.38 * groove)[..., None]
    h = barrel * 0.5 * lip + lip * 0.4 + wear * 0.08
    return alb, h, 0.82 + wear * 0.12, np.zeros((n, n))


def p_shingle(n, seed=27, rows=8):
    """Slate-grey roofing shingles, each a separate tab."""
    y = np.arange(n)[:, None].astype(np.float64)
    x = np.arange(n)[None, :].astype(np.float64)
    rh = n / rows
    cw = rh * 1.5
    cols = int(round(n / cw))
    cw = n / cols
    row = np.floor(y / rh)
    off = np.where(row % 2 > 0.5, 0.5, 0.0)
    colf = x / cw + off
    col = np.floor(colf)
    fy = (y / rh) % 1.0
    fx = colf % 1.0
    ri = np.broadcast_to(row.astype(np.int64), (n, n))
    ci = np.broadcast_to((col % cols).astype(np.int64), (n, n))
    tab = sstep(0.0, 0.75, fy) * (1 - 0.8 * sstep(0.9, 1.0, fy))
    slit = sstep(0.0, 0.05, np.minimum(fx, 1 - fx))
    pal = [C(0.26, 0.28, 0.32), C(0.32, 0.30, 0.30), C(0.24, 0.27, 0.27),
           C(0.36, 0.32, 0.30), C(0.22, 0.24, 0.29)]
    baseg = pick(pal, _hash2(ci, ri, seed))
    grit = fbm(n, 140, 3, seed + 2)
    tone = 0.85 + 0.30 * _hash2(ci, ri, seed + 6)
    alb = baseg * (tone * (0.82 + 0.3 * grit) * (0.5 + 0.5 * tab) * (0.7 + 0.3 * slit))[..., None]
    h = tab * slit * 0.7 + grit * 0.2
    return alb, h, 0.92 + grit * 0.06, np.zeros((n, n))


def p_grass(n, seed=19):
    """Blades painted over a dark, dense undergrowth."""
    rng = np.random.default_rng(seed)
    bgc = fbm(n, 6, 4, seed + 1)
    canvas = mixc(C(0.10, 0.20, 0.06), C(0.14, 0.26, 0.07), bgc)
    hmap = np.zeros((n, n))
    pal = [C(0.26, 0.48, 0.13), C(0.34, 0.57, 0.17), C(0.22, 0.42, 0.11),
           C(0.42, 0.62, 0.21), C(0.30, 0.50, 0.12), C(0.48, 0.60, 0.20),
           C(0.20, 0.38, 0.12), C(0.36, 0.55, 0.15)]
    patch = fbm(n, 4, 4, seed + 2)
    for i in range(int(n * n / 55)):
        cx = rng.random() * n
        cy = rng.random() * n
        ang = rng.random() * 2 * math.pi
        L = (0.05 + rng.random() * 0.055) * n
        pn = patch[int(cy) % n, int(cx) % n]
        col1 = pal[rng.integers(len(pal))] * (0.82 + rng.random() * 0.4)
        # meadow patches drift toward yellow-green or blue-green
        col1 = col1 * np.array([1 + (pn - 0.5) * 0.45, 1.0, 1 - (pn - 0.5) * 0.5])
        col0 = col1 * 0.42
        paint_stroke(canvas, hmap, n, cx, cy, ang, L, 1.6 + rng.random() * 1.6,
                     col0, col1, i / (n * n / 55) * 0.7 + rng.random() * 0.2, taper=0.85)
    big = fbm(n, 3, 3, seed + 4)
    canvas = canvas * (0.88 + 0.24 * big)[..., None]
    return canvas, hmap, 0.93 + 0.05 * noise2(n, 40, 40, seed), np.zeros((n, n))


def p_leaf(n, seed=37):
    """Overlapping leaf clusters, darker inside and lighter on top."""
    rng = np.random.default_rng(seed)
    canvas = np.tile(C(0.12, 0.24, 0.08), (n, n, 1))
    hmap = np.zeros((n, n))
    pal = [C(0.20, 0.38, 0.12), C(0.26, 0.44, 0.14), C(0.15, 0.31, 0.10),
           C(0.31, 0.47, 0.16), C(0.22, 0.40, 0.11), C(0.37, 0.48, 0.17),
           C(0.13, 0.28, 0.10), C(0.42, 0.47, 0.15)]
    total = int(n * n / 260)
    for i in range(total):
        cx = rng.random() * n
        cy = rng.random() * n
        ang = rng.random() * 2 * math.pi
        L = (0.055 + rng.random() * 0.045) * n
        depth = i / total
        col1 = pal[rng.integers(len(pal))] * (0.78 + 0.34 * depth + rng.random() * 0.12)
        col0 = col1 * 0.82
        paint_stroke(canvas, hmap, n, cx, cy, ang, L, L * 0.55, col0, col1,
                     depth * 0.9 + 0.05, leaf=True, rib=0.2)
    # rare turning leaves
    m = sstep(0.72, 0.86, fbm(n, 5, 3, seed + 2))
    canvas = mixc(canvas, canvas * np.array([1.5, 1.05, 0.55]), m * 0.5)
    return canvas, hmap, 0.90 + 0.06 * noise2(n, 30, 30, seed), np.zeros((n, n))


def p_dirt(n, seed=61):
    lumps = fbm(n, 9, 5, seed)
    fine = noise2(n, 160, 160, seed + 1)
    w = worley(n, 30, seed + 3, 1.0)
    peb = sstep(0.0, 0.32, 0.5 - w["f1"]) * (w["id"] > 0.72)
    pal = [C(0.42, 0.30, 0.20), C(0.36, 0.26, 0.17), C(0.47, 0.34, 0.22), C(0.33, 0.25, 0.18)]
    base = pick(pal, fbm(n, 12, 3, seed + 5))
    alb = base * (0.72 + 0.44 * lumps + 0.16 * fine)[..., None]
    pebc = mixc(C(0.50, 0.44, 0.36), C(0.36, 0.34, 0.32), w["id"])
    alb = mixc(alb, pebc * (0.8 + 0.3 * fine)[..., None], peb)
    damp = sstep(0.55, 0.8, fbm(n, 5, 4, seed + 9))
    alb = alb * (1 - 0.25 * damp)[..., None]
    h = lumps * 0.5 + fine * 0.15 + peb * 0.5
    return alb, h, 0.96 + fine * 0.04, np.zeros((n, n))


def p_gravel(n, seed=83):
    w = worley(n, 20, seed, 1.0, 0.25)
    e = w["f2"] - w["f1"]
    dome = sstep(0.03, 0.30, e)
    pal = [C(0.46, 0.44, 0.40), C(0.58, 0.55, 0.48), C(0.38, 0.37, 0.36),
           C(0.55, 0.47, 0.36), C(0.64, 0.62, 0.58), C(0.42, 0.40, 0.44),
           C(0.50, 0.42, 0.32)]
    base = pick(pal, w["id"])
    tone = 0.75 + 0.5 * _hash2(w["id"] * 555, 4, seed)
    fine = noise2(n, 200, 200, seed + 4)
    alb = base * (tone * (0.55 + 0.45 * dome) * (0.9 + 0.2 * fine))[..., None]
    gap = C(0.16, 0.13, 0.10)
    alb = mixc(gap[None, None, :] * (0.8 + 0.4 * fine)[..., None], alb, sstep(0.0, 0.10, e))
    h = dome * 0.85 + fine * 0.05
    return alb, h, 0.90 + fine * 0.06, np.zeros((n, n))


def p_sand(n, seed=131):
    dune = fbm(n, 4, 4, seed)
    ripple = 0.5 + 0.5 * np.sin((np.arange(n)[:, None] / n * 14 + dune * 3.0) * math.pi * 2)
    grain = noise2(n, 256, 256, seed + 1)
    dark = sstep(0.82, 0.95, noise2(n, 200, 200, seed + 2))
    pal = [C(0.66, 0.55, 0.38), C(0.62, 0.51, 0.35), C(0.70, 0.59, 0.42)]
    base = pick(pal, fbm(n, 5, 3, seed + 3))
    alb = base * (0.86 + 0.12 * dune + 0.025 * ripple + 0.10 * grain)[..., None]
    alb = alb * (1 - 0.35 * dark)[..., None]
    h = dune * 0.2 + ripple * 0.10 + grain * 0.10
    return alb, h, 0.97 + grain * 0.03, np.zeros((n, n))


def p_farm(n, wet=False, seed=127):
    y = np.arange(n)[:, None].astype(np.float64)
    furrows = 6
    furrow = 0.5 + 0.5 * np.sin(y / n * furrows * 2 * math.pi + fbm(n, 3, 3, seed) * 1.2)
    furrow = np.broadcast_to(furrow, (n, n))
    clod = fbm(n, 24, 5, seed + 1)
    fine = noise2(n, 180, 180, seed + 2)
    pal = [C(0.34, 0.23, 0.14), C(0.30, 0.21, 0.13), C(0.38, 0.26, 0.16)]
    base = pick(pal, fbm(n, 7, 3, seed + 3))
    alb = base * (0.55 + 0.35 * furrow + 0.35 * clod + 0.1 * fine)[..., None]
    if wet:
        alb = alb * 0.62
    h = furrow * 0.7 + clod * 0.35 + fine * 0.05
    r = 0.96 if not wet else 0.55
    return alb, h, r - clod * 0.08, np.zeros((n, n))


def p_clay(n, seed=45):
    w = worley(n, 5, seed, 1.0, 0.6)
    crack = 1.0 - sstep(0.0, 0.05, w["f2"] - w["f1"])
    mott = fbm(n, 7, 5, seed + 1)
    fine = noise2(n, 150, 150, seed + 2)
    pal = [C(0.62, 0.40, 0.28), C(0.56, 0.36, 0.26), C(0.68, 0.45, 0.31)]
    base = pick(pal, fbm(n, 4, 3, seed + 4))
    alb = base * (0.80 + 0.28 * mott + 0.06 * fine)[..., None]
    alb = alb * (1 - 0.6 * crack)[..., None]
    h = mott * 0.25 - crack * 0.6 + fine * 0.04
    return alb, h, 0.88 + mott * 0.08, np.zeros((n, n))


def p_asphalt(n, seed=331):
    binder = fbm(n, 12, 5, seed)
    w = worley(n, 60, seed + 1, 1.0)
    chip = sstep(0.05, 0.25, 0.5 - w["f1"]) * (w["id"] > 0.5)
    pal = [C(0.42, 0.42, 0.42), C(0.34, 0.34, 0.35), C(0.50, 0.48, 0.46), C(0.28, 0.28, 0.30)]
    chipc = pick(pal, _hash2(w["id"] * 700, 9, seed))
    fine = noise2(n, 220, 220, seed + 2)
    alb = C(0.17, 0.17, 0.18)[None, None, :] * (0.7 + 0.6 * binder + 0.2 * fine)[..., None]
    alb = mixc(alb, chipc * (0.8 + 0.4 * fine)[..., None], chip * 0.85)
    wear = sstep(0.55, 0.8, fbm(n, 4, 4, seed + 4))
    alb = alb * (1 + 0.3 * wear)[..., None]
    crack = 1.0 - sstep(0.0, 0.015, np.abs(fbm(n, 5, 5, seed + 6) - 0.5))
    alb = alb * (1 - 0.6 * crack)[..., None]
    h = binder * 0.2 + chip * 0.5 + fine * 0.05 - crack * 0.5
    return alb, h, 0.90 + fine * 0.05, np.zeros((n, n))


def p_plaster(n, base, seed=41, stain_amt=0.3):
    """Poured concrete: soft mottle, form marks, pores, water stains."""
    mott = fbm(n, 6, 5, seed)
    fine = noise2(n, 200, 200, seed + 1)
    stain = fbm(n, 3, 4, seed + 3)
    streak = noise2(n, 16, 2, seed + 5)
    alb = base[None, None, :] * (0.86 + 0.24 * mott + 0.06 * fine + 0.08 * streak * stain)[..., None]
    p = norm01(noise2(n, 140, 140, seed + 7))
    pits = sstep(0.88, 0.97, p)
    alb = alb * (1 - 0.35 * pits)[..., None]
    alb = alb * np.stack([1 + (stain - 0.5) * stain_amt, 1 + (stain - 0.5) * stain_amt * 0.4,
                          1 - (stain - 0.5) * stain_amt * 0.5], axis=-1)
    h = mott * 0.25 + fine * 0.08 - pits * 0.6
    return alb, h, 0.90 + fine * 0.06, np.zeros((n, n))


def p_rebar(n, base, seed=115):
    alb, h, r, m = p_plaster(n, base, seed, 0.2)
    y = np.arange(n)[:, None] / n
    bar = np.clip(1.0 - np.abs(np.sin(y * math.pi * 4)) * 5.0, 0, 1)
    bar = np.broadcast_to(bar, (n, n))
    rust = fbm(n, 16, 4, seed + 1)
    alb = mixc(alb, C(0.36, 0.22, 0.14) * (0.7 + 0.6 * rust)[..., None], bar)
    bleed = sstep(0.5, 0.75, fbm(n, 6, 4, seed + 3)) * (1 - bar)
    alb = alb * np.stack([1 + bleed * 0.3, 1 + bleed * 0.05, 1 - bleed * 0.25], axis=-1)
    return alb, h + bar * 0.5, np.where(bar > 0.5, 0.6, r), bar * 0.4


def p_slab(n, base, seed=119):
    alb, h, r, m = p_plaster(n, base, seed, 0.25)
    y = np.arange(n)[:, None].astype(np.float64)
    x = np.arange(n)[None, :].astype(np.float64)
    half = n / 2
    dj = np.minimum(np.minimum(y % half, half - y % half), np.minimum(x % half, half - x % half))
    joint = 1.0 - sstep(1.0, 4.5, dj)
    alb = alb * (1 - 0.62 * joint)[..., None]
    tone = 0.88 + 0.2 * _hash2((y // half).astype(np.int64), (x // half).astype(np.int64), seed)
    return alb * tone[..., None], h - joint * 0.5, r, m


def p_metal(n, base, seed, rough, metal, brushed=True, rivets=False, grid=0, oxide_amt=0.25):
    brush = noise2(n, 4, 220, seed) * 0.6 + noise2(n, 3, 340, seed + 1) * 0.4
    patina = fbm(n, 8, 4, seed + 2)
    oxide = sstep(0.55, 0.8, fbm(n, 7, 5, seed + 3))
    alb = base[None, None, :] * (0.78 + 0.30 * brush + 0.14 * patina)[..., None]
    alb = mixc(alb, C(0.42, 0.24, 0.13) * (0.7 + 0.5 * patina)[..., None], oxide * oxide_amt)
    h = brush * 0.25
    if grid:
        y = np.arange(n)[:, None].astype(np.float64)
        x = np.arange(n)[None, :].astype(np.float64)
        cell = n / grid
        dj = np.minimum(np.minimum(y % cell, cell - y % cell), np.minimum(x % cell, cell - x % cell))
        seam = 1.0 - sstep(0.8, 3.5, dj)
        alb = alb * (1 - 0.5 * seam)[..., None]
        h = h - seam * 0.5
    if rivets:
        c = n / max(grid, 1) if grid else n / 4
        yy = np.arange(n)[:, None] % c
        xx = np.arange(n)[None, :] % c
        d = np.sqrt((yy - c * 0.12) ** 2 + (xx - c * 0.12) ** 2)
        riv = np.clip(1.0 - d / (n / 90.0), 0, 1)
        h = h + riv * 0.8
        alb = alb * (1 + 0.25 * riv)[..., None]
    return alb, h, rough + brush * 0.14 + oxide * 0.3, np.full((n, n), metal) * (1 - oxide * 0.5)


def p_corrugated(n, base, seed=73, period=6):
    a = np.arange(n)[:, None] / n
    wave = np.broadcast_to(0.5 + 0.5 * np.sin(a * math.pi * 2 * period), (n, n))
    dirt = fbm(n, 18, 4, seed)
    rust = sstep(0.55, 0.78, fbm(n, 6, 5, seed + 2))
    spangle = fbm(n, 5, 4, seed + 1)
    alb = base[None, None, :] * (0.62 + 0.42 * wave)[..., None] * (0.86 + 0.24 * spangle)[..., None]
    alb = alb * (1 - 0.25 * dirt)[..., None]
    alb = mixc(alb, C(0.48, 0.26, 0.14) * (0.7 + 0.6 * dirt)[..., None], rust * 0.55)
    h = wave * 0.95 + dirt * 0.1
    return alb, h, 0.50 + dirt * 0.18 + rust * 0.4, np.full((n, n), 0.75) * (1 - rust * 0.7)


def p_panel(n, base, seed, rough, metal, rivets=True, oxide_amt=0.0):
    return p_metal(n, base, seed, rough, metal, True, rivets, 4, oxide_amt)


def p_painted(n, base, seed, rough=0.6):
    brush = noise2(n, 3, 60, seed) * 0.5 + noise2(n, 90, 5, seed + 1) * 0.5
    fine = noise2(n, 160, 160, seed + 2)
    chip = sstep(0.80, 0.92, fbm(n, 30, 4, seed + 3))
    alb = base[None, None, :] * (0.92 + 0.10 * brush + 0.06 * fine)[..., None]
    alb = mixc(alb, C(0.32, 0.28, 0.24) * (0.8 + 0.4 * fine)[..., None], chip * 0.3)
    h = brush * 0.15 + fine * 0.05 - chip * 0.15
    return alb, h, rough + fine * 0.08 + chip * 0.25, np.zeros((n, n))


def p_carbon(n, base, seed=101):
    x = np.arange(n)[:, None]
    y = np.arange(n)[None, :]
    c = 12
    cx = (x // c) % 2
    cy = (y // c) % 2
    tow = np.where((cx + cy) % 2 == 0, (x % c) / c, (y % c) / c)
    fine = noise2(n, 240, 240, seed)
    alb = base[None, None, :] * (0.6 + 0.6 * np.abs(tow - 0.5) + 0.3 * fine)[..., None]
    h = np.abs(tow - 0.5) * 0.6 + fine * 0.1
    return alb, h, 0.30 + fine * 0.10, np.full((n, n), 0.35)


def p_solar(n, base, seed=103):
    c = n // 3
    x = np.arange(n)[:, None]
    y = np.arange(n)[None, :]
    gx = np.minimum(x % c, c - 1 - x % c)
    gy = np.minimum(y % c, c - 1 - y % c)
    gridm = (gx < 3) | (gy < 3)
    bus = ((y % (c // 4)) < 1) & ~gridm
    fine = noise2(n, 180, 180, seed)
    cell = base[None, None, :] * (0.8 + 0.4 * fine)[..., None] * 1.3
    alb = np.where(gridm[..., None], C(0.62, 0.64, 0.70), cell)
    alb = np.where(bus[..., None], C(0.55, 0.55, 0.60), alb)
    h = np.where(gridm, 0.0, 0.3 + fine * 0.05)
    return alb, h, np.where(gridm, 0.55, 0.12), np.where(gridm, 0.0, 0.45)


def p_ore(n, seed=109):
    host = p_stones(n, [C(0.36, 0.36, 0.37), C(0.42, 0.40, 0.39), C(0.32, 0.32, 0.34)], 6, seed, 0.8, 0.5)
    alb, h, r, m = host
    w = worley(n, 9, seed + 5, 1.0, 0.5)
    ore = sstep(0.1, 0.45, 0.5 - w["f1"]) * (w["id"] > 0.45)
    rust = fbm(n, 20, 4, seed + 7)
    oc = C(0.64, 0.34, 0.16)[None, None, :] * (0.7 + 0.6 * rust)[..., None]
    alb = mixc(alb, oc, ore)
    return alb, h + ore * 0.15, r - ore * 0.35, ore * 0.55


def p_emit(n, base, seed, rough, lava=False):
    f = fbm(n, 6, 4, seed)
    fine = noise2(n, 90, 90, seed + 1)
    if lava:
        w = worley(n, 7, seed + 2, 1.0, 0.6)
        crack = 1.0 - sstep(0.0, 0.22, w["f2"] - w["f1"])
        crust = C(0.14, 0.09, 0.07)[None, None, :] * (0.7 + 0.6 * fine)[..., None]
        glow = base[None, None, :] * (0.7 + 0.5 * f)[..., None]
        alb = mixc(crust, glow, crack)
        return alb, (1 - crack) * 0.6 + fine * 0.1, np.full((n, n), rough) - crack * 0.3, np.zeros((n, n))
    y = np.arange(n)[:, None] / n
    band = np.broadcast_to(0.85 + 0.15 * np.cos((y - 0.5) * math.pi * 2), (n, n))
    alb = base[None, None, :] * (band * (0.92 + 0.14 * f))[..., None]
    return alb, fine * 0.05, np.full((n, n), rough), np.zeros((n, n))


def p_matte(n, base, seed=107):
    f = fbm(n, 6, 3, seed)
    fine = noise2(n, 140, 140, seed + 1)
    alb = base[None, None, :] * (0.85 + 0.3 * f + 0.15 * fine)[..., None]
    return alb, f * 0.2 + fine * 0.1, 0.80 + fine * 0.1, np.full((n, n), 0.08)


def p_glass(n, base, rough, seed=93):
    smear = fbm(n, 4, 3, seed)
    streak = noise2(n, 3, 200, seed + 1)
    alb = base[None, None, :] * (0.92 + 0.12 * smear + 0.06 * streak)[..., None]
    return alb, smear * 0.1, np.full((n, n), rough) + smear * 0.05, np.zeros((n, n))


def p_water(n, seed=53):
    f = fbm(n, 6, 4, seed)
    alb = C(0.13, 0.36, 0.44)[None, None, :] * (0.9 + 0.2 * f)[..., None]
    return alb, f * 0.05, np.full((n, n), 0.04), np.zeros((n, n))


# ---------------------------------------------------------------- table

def build_all(n, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    S = hexcol
    cobble_pal = [C(0.47, 0.45, 0.42), C(0.43, 0.42, 0.40), C(0.50, 0.47, 0.42),
                  C(0.40, 0.39, 0.38), C(0.49, 0.45, 0.39), C(0.45, 0.44, 0.42)]
    stone_pal = [C(0.40, 0.39, 0.38), C(0.44, 0.43, 0.42), C(0.36, 0.36, 0.37), C(0.47, 0.44, 0.40)]
    rock_pal = [C(0.44, 0.42, 0.40), C(0.38, 0.37, 0.36), C(0.50, 0.46, 0.41), C(0.35, 0.35, 0.36)]
    granite_pal = [C(0.46, 0.43, 0.41), C(0.40, 0.38, 0.38), C(0.52, 0.47, 0.44)]
    wood_light = [C(0.60, 0.44, 0.27), C(0.56, 0.40, 0.25), C(0.64, 0.48, 0.30), C(0.52, 0.38, 0.24)]
    wood_mid = [C(0.44, 0.31, 0.19), C(0.40, 0.28, 0.17), C(0.48, 0.34, 0.21), C(0.36, 0.26, 0.17)]
    wood_dark = [C(0.24, 0.17, 0.11), C(0.21, 0.15, 0.10), C(0.27, 0.19, 0.12)]
    brick_pal = [C(0.58, 0.29, 0.21), C(0.64, 0.33, 0.24), C(0.52, 0.26, 0.20),
                 C(0.69, 0.39, 0.28), C(0.56, 0.30, 0.24)]
    sand_pal = [C(0.66, 0.57, 0.43), C(0.62, 0.53, 0.40), C(0.70, 0.60, 0.46)]
    # name -> (builder, bump strength)
    SPECS = {
        "timber":           (lambda: p_planks(n, 4, wood_mid, 4, 1.1, True, 0.05, 0.84, 0.3), 0.9),
        "plank":            (lambda: p_planks(n, 5, wood_light, 5, 1.0, True, 0.05, 0.80), 0.9),
        "dark_oak":         (lambda: p_planks(n, 4, wood_dark, 6, 1.0, True, 0.05, 0.80), 0.9),
        "bark":             (lambda: p_bark(n), 1.5),
        "brick":            (lambda: p_coursed(n, brick_pal, 16, 6, 42, C(0.62, 0.58, 0.50),
                                               0.055, 0.22, 0.22, 0.0, 0.14), 1.3),
        "sandstone":        (lambda: p_coursed(n, sand_pal, 6, 3, 44, C(0.62, 0.55, 0.42),
                                               0.035, 0.14, 0.06, 0.05, 0.08, 0.5, 0.12), 1.0),
        "granite":          (lambda: p_stones(n, granite_pal, 9, 71, 0.8, 0.5, C(0.20, 0.19, 0.18), 0.03, 0.2, 0.14), 1.0),
        "cobble":           (lambda: p_stones(n, cobble_pal, 7, 73, 0.82, 0.45, C(0.30, 0.27, 0.22), 0.08, 0.34, 0.08, 0.25), 1.6),
        "stone":            (lambda: p_stones(n, stone_pal, 5, 79, 0.85, 0.5, C(0.18, 0.17, 0.16), 0.05, 0.28, 0.10, 0.12), 1.4),
        "rock":             (lambda: p_stones(n, rock_pal, 3, 83, 0.9, 0.5, C(0.20, 0.19, 0.18), 0.04, 0.4, 0.16, 0.08, 0.16), 1.6),
        "concrete":         (lambda: p_plaster(n, C(0.56, 0.55, 0.53)), 0.7),
        "rebar_concrete":   (lambda: p_rebar(n, C(0.50, 0.50, 0.50)), 0.9),
        "concrete_slab":    (lambda: p_slab(n, C(0.50, 0.49, 0.47)), 0.7),
        "steel_frame":      (lambda: p_metal(n, C(0.34, 0.37, 0.41), 21, 0.45, 0.85, True, True, 2), 0.7),
        "corrugated_steel": (lambda: p_corrugated(n, C(0.58, 0.62, 0.65)), 1.4),
        "sheet_metal":      (lambda: p_panel(n, C(0.60, 0.63, 0.66), 23, 0.40, 0.80, False), 0.7),
        "plastic_panel":    (lambda: p_panel(n, C(0.78, 0.76, 0.70), 25, 0.55, 0.0), 0.7),
        "carbon_composite": (lambda: p_carbon(n, C(0.15, 0.16, 0.18)), 0.7),
        "solar_panel":      (lambda: p_solar(n, C(0.08, 0.14, 0.28)), 0.5),
        "thatch":           (lambda: p_thatch(n), 1.6),
        "clay_tile":        (lambda: p_tiles(n, None, 8), 0.8),
        "asphalt_shingle":  (lambda: p_shingle(n), 1.1),
        "dirt":             (lambda: p_dirt(n), 1.0),
        "gravel":           (lambda: p_gravel(n), 1.4),
        "farmland":         (lambda: p_farm(n), 1.1),
        "wet_farmland":     (lambda: p_farm(n, True), 0.9),
        "asphalt":          (lambda: p_asphalt(n), 0.7),
        "grass":            (lambda: p_grass(n), 1.4),
        "sand":             (lambda: p_sand(n), 0.8),
        "leaf":             (lambda: p_leaf(n), 1.6),
        "clay":             (lambda: p_clay(n), 0.9),
        "iron_ore":         (lambda: p_ore(n), 1.2),
        "painted_white":    (lambda: p_painted(n, C(0.82, 0.80, 0.75), 27, 0.65), 0.5),
        "painted_red":      (lambda: p_painted(n, C(0.62, 0.20, 0.17), 29, 0.65), 0.5),
        "chrome":           (lambda: p_metal(n, C(0.78, 0.80, 0.82), 31, 0.12, 1.0, True, False, 0, 0.0), 0.4),
        "matte_black":      (lambda: p_matte(n, C(0.13, 0.13, 0.15)), 0.4),
        "neon_strip":       (lambda: p_emit(n, C(0.39, 0.91, 1.0), 33, 0.30), 0.3),
        "ember":            (lambda: p_emit(n, C(1.0, 0.48, 0.16), 35, 0.9, True), 1.0),
        "glass":            (lambda: p_glass(n, C(0.66, 0.83, 0.87), 0.05), 0.3),
        "reinforced_glass": (lambda: p_glass(n, C(0.62, 0.77, 0.82), 0.10, 95), 0.3),
        "water":            (lambda: p_water(n), 0.5),
    }
    names = []
    for name, (fn, bump) in SPECS.items():
        alb, h, rough, metal = fn()
        h = np.broadcast_to(np.asarray(h, dtype=np.float64), (n, n))
        rough = np.broadcast_to(np.asarray(rough, dtype=np.float64), (n, n))
        metal = np.broadcast_to(np.asarray(metal, dtype=np.float64), (n, n))
        alb = np.broadcast_to(np.asarray(alb, dtype=np.float64), (n, n, 3))
        ao = cavity_ao(h)
        # a light blur before differentiation removes the single-pixel stair
        # steps that otherwise catch the sun as sparkle at distance
        nrm = height_to_normal(_boxblur(h, 1) * 0.5 + h * 0.5, bump)
        orm = np.stack([ao, np.clip(rough, 0.02, 1.0), np.clip(metal, 0.0, 1.0)], axis=-1)
        alb = np.clip(alb * (0.82 + 0.18 * ao[..., None]), 0, 1)
        for suffix, arr in (("a", alb), ("n", nrm), ("o", orm)):
            img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
            img.save(os.path.join(out_dir, f"{name}_{suffix}.png"), optimize=True)
        names.append(name)
        print(f"  {name}", flush=True)

    with open(os.path.join(out_dir, "layers.txt"), "w", encoding="utf-8") as fh:
        for i, nm in enumerate(names):
            fh.write(f"{i} {nm}\n")
    print(f"baked {len(names)} materials -> {out_dir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out", default="assets/tex_web")
    a = ap.parse_args()
    build_all(a.size, a.out)
