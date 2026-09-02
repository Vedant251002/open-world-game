"""Analyze autocap PNGs with pure stdlib: brightness, variance, colorfulness.
Detects black screens / flat renders / missing scene content."""
import zlib, struct, os, sys, glob

def decode_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not png"
    pos = 8
    width = height = None
    bitdepth = colortype = None
    idat = b""
    palette = None
    trns = None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"PLTE":
            palette = chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    assert bitdepth == 8, f"bitdepth {bitdepth}"
    stride = width * channels
    # unfilter
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    pos2 = 0
    for y in range(height):
        f = raw[pos2]; pos2 += 1
        line = bytearray(raw[pos2:pos2+stride]); pos2 += stride
        if f == 0:
            pass
        elif f == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i-channels]) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # Average
            for i in range(stride):
                a = line[i-channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                a = line[i-channels] if i >= channels else 0
                b = prev[i]
                c = prev[i-channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y*stride:(y+1)*stride] = line
        prev = line
    return width, height, channels, bytes(out)

def stats(path):
    w, h, ch, px = decode_png(path)
    n = len(px) // ch
    step = max(1, n // 40000)  # sample ~40k pixels
    rs = gs = bs = 0
    cnt = 0
    mins = [255, 255, 255]; maxs = [0, 0, 0]
    colors = set()
    for i in range(0, n, step):
        o = i * ch
        r, g, b = px[o], px[o+1], px[o+2]
        rs += r; gs += g; bs += b; cnt += 1
        mins[0] = min(mins[0], r); maxs[0] = max(maxs[0], r)
        mins[1] = min(mins[1], g); maxs[1] = max(maxs[1], g)
        mins[2] = min(mins[2], b); maxs[2] = max(maxs[2], b)
        colors.add((r >> 4, g >> 4, b >> 4))  # 4-bit quantized
    avg = (rs/cnt, gs/cnt, bs/cnt)
    # variance sample
    var = 0.0
    for i in range(0, n, step):
        o = i * ch
        lum = 0.299*px[o] + 0.587*px[o+1] + 0.114*px[o+2]
        var += (lum - (0.299*avg[0] + 0.587*avg[1] + 0.114*avg[2])) ** 2
    var = (var / cnt) ** 0.5
    return {
        "size": f"{w}x{h}", "avg_rgb": [round(a) for a in avg],
        "luma_std": round(var, 1),
        "range": [mins, maxs],
        "uniq_colors_12bit": len(colors),
        "kb": round(os.path.getsize(path)/1024),
    }

d = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\vedan\AppData\Roaming\Godot\app_userdata\Neon Bay City\autocap"
files = sorted(glob.glob(os.path.join(d, "*.png")))
print(f"{len(files)} screenshots in {d}\n")
bad = []
for f in files:
    try:
        s = stats(f)
        flag = ""
        if s["luma_std"] < 6 or s["uniq_colors_12bit"] < 12:
            flag = "  <-- SUSPECT (flat/black)"
            bad.append(os.path.basename(f))
        print(f"{os.path.basename(f):28s} {s['size']}  avgRGB={s['avg_rgb']}  lumaStd={s['luma_std']}  colors={s['uniq_colors_12bit']}  {s['kb']}KB{flag}")
    except Exception as e:
        print(f"{os.path.basename(f):28s} DECODE ERROR: {e}")
        bad.append(os.path.basename(f))
print()
print("SUSPECT_COUNT:", len(bad), bad)
