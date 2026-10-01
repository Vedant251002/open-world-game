#!/usr/bin/env python3
"""Synthesises every sound in assets/audio/ from scratch (numpy only).

Nothing here is a recording and nothing is downloaded: ambience loops are
spectrally shaped noise (built in the frequency domain so they loop with no
seam), birds and animals are additive/formant synthesis, plucks and pads are
additive with per-partial decay, impacts are modal resonators.

    python3 _tools/gen_audio.py            # writes assets/audio/*.wav
    python3 _tools/gen_audio.py --only rain_loop,wind_loop

Files are mono 16-bit WAV at a rate chosen per sound (11-22 kHz: low rates for
rumbles and pads, which have no top end to lose). The whole set stays under
3 MB. Everything is seeded, so the output is reproducible.
"""
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "audio")
TAU = 2.0 * np.pi


# ------------------------------------------------------------------- helpers

def rng_for(name):
    return np.random.default_rng(abs(hash_str(name)) % (2 ** 32))


def hash_str(s):
    h = 2166136261
    for ch in s.encode():
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return h


def write(name, x, sr, peak=0.85, edge_ms=None):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    if edge_ms is not None:  # one-shots: no clicks at either end
        n_in = max(int(sr * 0.0004), 1)
        n_out = min(max(int(sr * edge_ms / 1000.0), 1), len(x) // 2)
        x[:n_in] *= np.linspace(0, 1, n_in)
        x[-n_out:] *= np.linspace(1, 0, n_out) ** 2
    pcm = np.clip(x * 32767.0, -32768, 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    return os.path.getsize(path)


def tvec(dur, sr):
    return np.arange(int(dur * sr)) / sr


def hp_gain(f, fc, order=2):
    r = (f / fc) ** order
    return r / np.sqrt(1.0 + r * r)


def lp_gain(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def bp_gain(f, lo, hi, order=2):
    return hp_gain(f, lo, order) * lp_gain(f, hi, order)


def fft_noise(n, sr, gain_fn, rng):
    """Noise with the given magnitude response, exactly periodic over n samples."""
    f = np.fft.rfftfreq(n, 1.0 / sr)
    mag = gain_fn(np.maximum(f, 1e-3))
    ph = rng.uniform(0, TAU, len(f))
    spec = mag * np.exp(1j * ph)
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.sqrt(np.mean(x * x)) + 1e-12)


def filt(x, sr, gain_fn, pad=0.25):
    """Zero-phase FFT filter for one-shots (zero padded so it does not wrap)."""
    n = len(x)
    m = n + int(n * pad) + 64
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1.0 / sr)
    return np.fft.irfft(X * gain_fn(np.maximum(f, 1e-3)), m)[:n]


def white(n, rng):
    return rng.normal(0, 1, n)


def verb(x, sr, rt=0.5, wet=0.2, rng=None, damp=3500.0, keep=None):
    """A small room: exponentially decaying, darkened noise as the impulse."""
    rng = rng or np.random.default_rng(1)
    n_ir = int(rt * sr)
    t = np.arange(n_ir) / sr
    ir = rng.normal(0, 1, n_ir) * np.exp(-6.9 * t / rt)
    ir = filt(ir, sr, lambda f: lp_gain(f, damp, 1), pad=0.1)
    ir[:int(0.004 * sr)] *= np.linspace(0, 1, int(0.004 * sr))
    ir /= np.sqrt(np.sum(ir * ir)) + 1e-9
    n = len(x) + n_ir
    m = 1 << int(np.ceil(np.log2(n)))
    n_keep = n if keep is None else min(n, len(x) + int(keep * sr))
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]
    out = np.zeros(n)
    out[:len(x)] = x
    r = out * (1 - wet * 0.5) + y * wet * np.sqrt(np.mean(x * x) / (np.mean(y * y) + 1e-12)) * 1.0
    return r[:n_keep]


def place(buf, seg, at):
    """Adds seg into buf at sample `at`, wrapping round the end (for loops)."""
    n = len(buf)
    idx = (np.arange(len(seg)) + at) % n
    np.add.at(buf, idx, seg)


def note_hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def smooth_noise(n, sr, rate, rng):
    """Slow random wobble in -1..1, around `rate` Hz."""
    k = max(int(n * rate / sr) + 4, 4)
    pts = rng.uniform(-1, 1, k)
    xs = np.linspace(0, k - 1, n)
    return np.interp(xs, np.arange(k), pts)


def tone(dur, sr, f_of_u, harm=(1.0,), amp_pow=1.0, attack=0.0, vib=None):
    """A voiced note. f_of_u maps 0..1 to Hz; the envelope is a raised sine."""
    t = tvec(dur, sr)
    u = t / dur
    f = f_of_u(u)
    if vib is not None:
        f = f * (1 + vib[1] * np.sin(TAU * vib[0] * t))
    ph = TAU * np.cumsum(f) / sr
    y = np.zeros_like(t)
    for k, h in enumerate(harm, start=1):
        y += h * np.sin(k * ph)
    env = np.sin(np.pi * np.clip(u, 0, 1)) ** amp_pow
    if attack > 0:
        env *= np.clip(t / attack, 0, 1)
    return y * env


# ----------------------------------------------------------- formant voices

def formant_amp(fk, formants):
    """Magnitude of a bank of resonances at frequency array fk."""
    a = np.zeros_like(fk)
    for (F, bw, g) in formants:
        a += g / (1.0 + ((fk - F) / (bw * 0.5)) ** 2)
    return a


def voice(f0, formants_fn, sr, tilt=1.0, nmax=70, jitter=0.004, rng=None, breath=0.0):
    """Additive source-filter voice.

    f0: per-sample fundamental array. formants_fn(i) -> list of (F, bw, gain)
    where F may be a per-sample array (so vowels can glide). Each harmonic's
    amplitude is the vocal-tract response at its own frequency: the same
    machinery makes a man's murmur, a hen's cluck, a sheep's bleat and a cow's
    moo, just with different tracts.
    """
    rng = rng or np.random.default_rng(3)
    n = len(f0)
    f0 = f0 * (1 + jitter * smooth_noise(n, sr, 60.0, rng))
    ph = TAU * np.cumsum(f0) / sr
    formants = formants_fn()
    y = np.zeros(n)
    for k in range(1, nmax + 1):
        fk = k * f0
        live = fk < 0.45 * sr
        if not np.any(live):
            break
        a = formant_amp(fk, formants) * (k ** -tilt) * live
        y += a * np.sin(k * ph + k * 0.7)
    if breath > 0:
        nz = white(n, rng)
        nz = filt(nz, sr, lambda f: bp_gain(f, 800, 3500, 1), pad=0.05)
        y = y / (np.max(np.abs(y)) + 1e-9) + breath * nz / (np.max(np.abs(nz)) + 1e-9)
    return y


# --------------------------------------------------------------- ambience

def gen_wind(sr=11025, T=8.0):
    rng = rng_for("wind")
    n = int(sr * T)
    t = np.arange(n) / sr
    low = fft_noise(n, sr, lambda f: lp_gain(f, 140, 2) * hp_gain(f, 25, 2), rng)
    mid = fft_noise(n, sr, lambda f: bp_gain(f, 180, 900, 2), rng)
    air = fft_noise(n, sr, lambda f: bp_gain(f, 900, 2600, 2) * (900 / np.maximum(f, 900)), rng)
    # Slow swells that repeat exactly over the loop (integer cycles in T).
    g1 = 0.55 + 0.45 * np.sin(TAU * 1 * t / T + 0.6)
    g2 = 0.6 + 0.4 * np.sin(TAU * 2 * t / T + 2.1)
    g3 = 0.7 + 0.3 * np.sin(TAU * 3 * t / T + 4.0)
    x = 0.5 * low * (0.6 + 0.4 * g1) + 0.8 * mid * g1 * g2 + 0.18 * air * g2 * g3
    return write("wind_loop", x, sr, 0.8)


def gen_rain(sr=16000, T=5.0):
    rng = rng_for("rain")
    n = int(sr * T)
    # A bed of soft hiss, tilted to sound like water on leaves and thatch...
    bed = fft_noise(n, sr, lambda f: bp_gain(f, 700, 6500, 1) * (1500 / np.maximum(f, 1500)) ** 0.3, rng)
    # ...with individual drops on top, which is what makes it rain and not a vent.
    drops = np.zeros(n)
    for _ in range(int(T * 150)):
        L = int(sr * rng.uniform(0.002, 0.007))
        k = np.arange(L) / sr
        f = rng.uniform(1500, 5200)
        seg = np.sin(TAU * f * k) * np.exp(-k / rng.uniform(0.0008, 0.002)) * rng.uniform(0.1, 0.6) ** 2
        place(drops, seg, int(rng.integers(0, n)))
    low = fft_noise(n, sr, lambda f: bp_gain(f, 120, 500, 2), rng)
    x = bed * 0.9 + drops * 1.3 + low * 0.12
    return write("rain_loop", x, sr, 0.8)


def gen_water(sr=11025, T=6.0):
    rng = rng_for("water")
    n = int(sr * T)
    wash = fft_noise(n, sr, lambda f: bp_gain(f, 180, 2200, 2), rng)
    env = np.zeros(n)
    k = 4
    centres = (np.arange(k) + rng.uniform(-0.15, 0.15, k)) / k * T
    t = np.arange(n) / sr
    for c in centres:
        d = ((t - c + T / 2) % T) - T / 2  # signed, wrapped
        swell = np.where(d < 0, np.exp(-(d / 0.7) ** 2), np.exp(-(d / 1.1) ** 2))
        env += swell * rng.uniform(0.7, 1.0)
    x = wash * (0.25 + 0.75 * env / env.max())
    # small trickles and plips
    for _ in range(26):
        L = int(sr * rng.uniform(0.02, 0.05))
        k2 = np.arange(L) / sr
        f0 = rng.uniform(500, 1100)
        f = f0 * (1 + 2.2 * k2 / k2[-1])
        seg = np.sin(TAU * np.cumsum(f) / sr) * np.exp(-k2 / 0.012) * rng.uniform(0.06, 0.25)
        place(x, seg, int(rng.integers(0, n)))
    return write("water_loop", x, sr, 0.8)


VOWELS = {
    "a": [(730, 110, 1.0), (1090, 120, 0.6), (2440, 160, 0.25)],
    "e": [(530, 100, 1.0), (1840, 130, 0.5), (2480, 160, 0.2)],
    "i": [(300, 80, 1.0), (2200, 140, 0.4), (2900, 180, 0.15)],
    "o": [(570, 100, 1.0), (840, 110, 0.6), (2410, 160, 0.15)],
    "u": [(330, 80, 1.0), (870, 100, 0.5), (2240, 160, 0.1)],
}


def gen_murmur(sr=11025, T=7.0):
    """A handful of people talking at a distance: voiced syllables with
    wandering vowels, in phrases with pauses. No words, nothing to parse."""
    rng = rng_for("murmur")
    n = int(sr * T)
    mix = np.zeros(n)
    for v in range(5):
        f0_base = rng.choice([110, 128, 150, 190, 215]) * rng.uniform(0.95, 1.05)
        t = 0.0 + rng.uniform(0, 1.0)
        while t < T:
            # a phrase
            nsyl = int(rng.integers(4, 10))
            for s in range(nsyl):
                dur = rng.uniform(0.11, 0.24)
                L = int(sr * dur)
                vow = rng.choice(list(VOWELS))
                nxt = rng.choice(list(VOWELS))
                a = VOWELS[vow]
                b = VOWELS[nxt]
                u = np.linspace(0, 1, L)
                f0 = f0_base * (1 + 0.12 * np.sin(np.pi * u) * (1 if s % 2 else 0.5)) * (1 - 0.04 * s / nsyl)
                fmts = [(a[i][0] + (b[i][0] - a[i][0]) * u, a[i][1], a[i][2]) for i in range(3)]
                seg = voice(f0, lambda: fmts, sr, tilt=1.1, nmax=40, rng=rng, breath=0.08)
                seg *= np.sin(np.pi * u) ** 0.8
                place(mix, seg * rng.uniform(0.5, 1.0), int((t % T) * sr))
                t += dur + rng.uniform(0.01, 0.07)
            t += rng.uniform(0.6, 2.2)
    mix = filt(mix, sr, lambda f: lp_gain(f, 2400, 2) * hp_gain(f, 120, 2), pad=0.0)
    # soften: share of room tone so it reads as a crowd, not as individuals
    room = fft_noise(n, sr, lambda f: bp_gain(f, 200, 1800, 2), rng)
    x = mix / np.max(np.abs(mix)) * 0.8 + room * 0.10
    return write("murmur_loop", x, sr, 0.8)


def gen_crickets(sr=22050, T=3.0):
    rng = rng_for("crickets")
    n = int(sr * T)
    x = np.zeros(n)
    voices = [(4350, 7, 0.00), (4720, 6, 0.31), (5050, 8, 0.57), (4150, 5, 0.13), (4520, 9, 0.77)]
    for f, per_loop, off in voices:
        period = T / per_loop
        pulse_len = int(sr * 0.016)
        k = np.arange(pulse_len) / sr
        pulse = np.sin(TAU * f * k) * np.sin(np.pi * k / k[-1]) ** 2
        # tiny second resonance, as a real stridulating wing has
        pulse += 0.25 * np.sin(TAU * f * 2.01 * k) * np.sin(np.pi * k / k[-1]) ** 2
        for c in range(per_loop):
            base = (c * period + off * period) % T
            npulse = 4
            for p in range(npulse):
                at = int((base + p * 0.027) * sr)
                place(x, pulse * (0.75 + 0.25 * (p == 1 or p == 2)) * rng.uniform(0.9, 1.0), at)
    # the faintest bed of night air
    x += fft_noise(n, sr, lambda f: bp_gain(f, 2500, 6500, 2), rng) * 0.015 * np.max(np.abs(x))
    return write("crickets_loop", x, sr, 0.7)


def gen_thunder(idx, sr=11025, T=5.5):
    rng = rng_for("thunder%d" % idx)
    n = int(sr * T)
    t = np.arange(n) / sr
    crack_n = int(sr * 0.5)
    crack = white(crack_n, rng)
    crack = filt(crack, sr, lambda f: bp_gain(f, 300, 3500, 2), pad=0.1)
    crack *= np.exp(-np.arange(crack_n) / sr / (0.05 + 0.03 * idx))
    rumble = fft_noise(n, sr, lambda f: lp_gain(f, 90 + 40 * idx, 2) * hp_gain(f, 18, 2), rng)
    env = np.zeros(n)
    for i in range(6 + idx):
        at = rng.uniform(0.0, 2.2 + idx * 0.5)
        env += rng.uniform(0.3, 1.0) * np.where(t > at, np.exp(-(t - at) / rng.uniform(0.5, 1.1)), 0) * np.clip((t - at) / 0.08, 0, 1)
    env *= np.exp(-t / 3.2)
    x = rumble * env / env.max()
    x[:crack_n] += crack * 0.55 / (np.max(np.abs(crack)) + 1e-9)
    # smooth the head so the crack is not a click
    return write("thunder_%d" % (idx + 1), x, sr, 0.9, edge_ms=900)


# ------------------------------------------------------------------ birds

def bird_buf(dur, sr):
    return np.zeros(int(dur * sr))


def put(buf, seg, t, sr):
    a = int(t * sr)
    b = min(a + len(seg), len(buf))
    if b > a:
        buf[a:b] += seg[:b - a]


def finish_bird(name, x, sr, rt=0.4, wet=0.22, peak=0.8):
    rng = rng_for(name)
    x = filt(x, sr, lambda f: hp_gain(f, 400, 2), pad=0.05)
    x = verb(x, sr, rt, wet, rng, damp=5000, keep=0.25)
    return write(name, x, sr, peak, edge_ms=120)


def gen_tweet(i, sr=16000):
    rng = rng_for("tweet%d" % i)
    buf = bird_buf(1.0, sr)
    t = 0.02
    f0 = rng.uniform(3300, 4600)
    for k in range(int(rng.integers(2, 4))):
        d = rng.uniform(0.06, 0.1)
        up = rng.random() < 0.5
        fa, fb = (f0, f0 * rng.uniform(1.15, 1.35)) if up else (f0 * 1.25, f0)
        seg = tone(d, sr, lambda u, fa=fa, fb=fb: fa + (fb - fa) * u ** 1.3, harm=(1, 0.18, 0.05), amp_pow=0.9)
        put(buf, seg, t, sr)
        t += d + rng.uniform(0.05, 0.11)
    return finish_bird("bird_tweet_%d" % (i + 1), buf[:int((t + 0.1) * sr)], sr)


def gen_trill(i, sr=16000):
    rng = rng_for("trill%d" % i)
    n_p = int(rng.integers(14, 24))
    rate = rng.uniform(15, 22)
    dur = n_p / rate + 0.06
    buf = bird_buf(dur, sr)
    f_hi = rng.uniform(3600, 4900)
    for p in range(n_p):
        u = p / n_p
        a = np.sin(np.pi * u) ** 0.7
        seg = tone(0.04, sr, lambda v, fh=f_hi: fh * (1.0 - 0.28 * v), harm=(1, 0.2), amp_pow=1.0)
        put(buf, seg * a, 0.015 + p / rate, sr)
    return finish_bird("bird_trill_%d" % (i + 1), buf, sr)


def gen_warble(i, sr=16000):
    rng = rng_for("warble%d" % i)
    notes = int(rng.integers(7, 12))
    buf = bird_buf(2.0, sr)
    t = 0.03
    f = rng.uniform(2800, 3800)
    for k in range(notes):
        d = rng.uniform(0.05, 0.14)
        f2 = float(np.clip(f * rng.uniform(0.72, 1.4), 2200, 5400))
        seg = tone(d, sr, lambda u, a=f, b=f2: a + (b - a) * np.sin(u * np.pi * 0.5) ** 2, harm=(1, 0.12), amp_pow=1.3)
        put(buf, seg * rng.uniform(0.55, 1.0), t, sr)
        t += d + rng.uniform(0.015, 0.07)
        f = f2
    return finish_bird("bird_warble_%d" % (i + 1), buf[:int((t + 0.15) * sr)], sr)


def gen_thrush(i, sr=16000):
    """Pure whistled phrases, each given twice, like a song thrush."""
    rng = rng_for("thrush%d" % i)
    buf = bird_buf(2.0, sr)
    t = 0.05
    for phrase in range(2):
        fa = rng.uniform(2100, 3300)
        shape = [fa * rng.uniform(0.8, 1.6) for _ in range(3)]
        reps = 2
        for r in range(reps):
            tt = t
            for fnote in shape:
                d = rng.uniform(0.07, 0.15)
                seg = tone(d, sr, lambda u, a=fnote: a * (1 + 0.25 * np.sin(np.pi * u) - 0.1 * u), harm=(1, 0.05), amp_pow=1.1)
                put(buf, seg, tt, sr)
                tt += d + 0.015
            t = tt + 0.05
        t += rng.uniform(0.2, 0.35)
    return finish_bird("bird_thrush_%d" % (i + 1), buf[:int((t + 0.1) * sr)], sr, rt=0.5, wet=0.28)


def gen_cuckoo(sr=16000):
    buf = bird_buf(1.2, sr)
    for t, f, d in [(0.05, 760, 0.2), (0.34, 600, 0.32)]:
        seg = tone(d, sr, lambda u, f=f: f * (1.04 - 0.05 * u), harm=(1, 0.28, 0.07), amp_pow=0.8, attack=0.02)
        put(buf, seg, t, sr)
    return finish_bird("bird_cuckoo", buf[:int(0.8 * sr)], sr, rt=0.6, wet=0.35)


def gen_dove(sr=16000):
    buf = bird_buf(2.0, sr)
    t = 0.05
    for d, f, amp in [(0.22, 440, 0.6), (0.5, 470, 1.0), (0.2, 430, 0.55), (0.38, 450, 0.8)]:
        seg = tone(d, sr, lambda u, f=f: f * (1.05 - 0.12 * u ** 2), harm=(1, 0.4, 0.12), amp_pow=0.7, attack=0.05, vib=(26, 0.012))
        put(buf, seg * amp, t, sr)
        t += d + 0.07
    x = buf[:int((t + 0.1) * sr)]
    x = filt(x, sr, lambda f: lp_gain(f, 2500, 2))
    x = verb(x, sr, 0.7, 0.3, rng_for("dove"), damp=3000, keep=0.3)
    return write("bird_dove", x, sr, 0.75, edge_ms=100)


def gen_owl(i, sr=16000):
    rng = rng_for("owl%d" % i)
    base = [410, 372][i]
    buf = bird_buf(2.4, sr)
    seg1 = tone(0.2, sr, lambda u: base * (1.08 - 0.08 * u), harm=(1, 0.5, 0.2), amp_pow=0.8, attack=0.04)
    put(buf, seg1 * 0.6, 0.05, sr)
    seg2 = tone(1.2, sr, lambda u: base * (1.02 - 0.06 * u ** 2), harm=(1, 0.45, 0.18), amp_pow=0.55, attack=0.12,
                vib=(6.5, 0.02))
    put(buf, seg2, 0.42, sr)
    n = len(buf)
    breath = filt(white(n, rng), sr, lambda f: bp_gain(f, 300, 1400, 1)) * 0.03
    env = np.zeros(n)
    env[int(0.05 * sr):int(1.7 * sr)] = 1
    x = buf + breath * env
    x = filt(x, sr, lambda f: lp_gain(f, 2200, 2))
    x = verb(x[:int(1.8 * sr)], sr, 0.9, 0.38, rng, damp=2500, keep=0.3)
    return write("owl_%d" % (i + 1), x, sr, 0.8, edge_ms=200)


# ---------------------------------------------------------------- animals

def gen_hen(i, sr=22050):
    rng = rng_for("hen%d" % i)
    spec = [(1, 0.17), (2, 0.2), (4, 0.15)][i]
    count, gap = spec
    buf = bird_buf(1.4, sr)
    t = 0.02
    for c in range(count):
        d = rng.uniform(0.07, 0.11) if c < count - 1 else rng.uniform(0.12, 0.2)
        L = int(sr * d)
        u = np.linspace(0, 1, L)
        f0 = (420 - 90 * u) * (1 + 0.05 * c)
        f1 = 600 + 350 * u
        f2 = 1500 + 300 * u
        seg = voice(f0, lambda: [(f1, 160, 1.0), (f2, 260, 0.6), (3000, 600, 0.12)], sr, tilt=0.7, nmax=40, rng=rng, breath=0.18)
        seg *= np.sin(np.pi * u) ** 0.6 * np.exp(-2.0 * u)
        put(buf, seg * (1.0 - 0.1 * c), t, sr)
        t += d + gap * rng.uniform(0.8, 1.2)
    x = buf[:int((t + 0.05) * sr)]
    x = verb(x, sr, 0.3, 0.15, rng, damp=5000, keep=0.12)
    return write("hen_%d" % (i + 1), x, sr, 0.75, edge_ms=30)


def gen_sheep(i, sr=22050):
    rng = rng_for("sheep%d" % i)
    d = [0.95, 0.7][i]
    base = [360, 470][i]
    n = int(sr * d)
    u = np.linspace(0, 1, n)
    t = u * d
    # the bleat's tremble is a fast pitch and amplitude wobble
    f0 = base * (1 + 0.1 * np.sin(np.pi * u) - 0.14 * u ** 2) * (1 + 0.035 * np.sin(TAU * 31 * t))
    f1 = 780 + 160 * np.sin(np.pi * u)
    f2 = 1250 + 250 * u
    y = voice(f0, lambda: [(f1, 150, 1.0), (f2, 220, 0.75), (2500, 400, 0.25), (350, 80, 0.5)], sr, tilt=0.55, nmax=50, rng=rng, breath=0.12)
    y *= (0.72 + 0.28 * np.sin(TAU * 31 * t + 1.0)) * np.clip(u / 0.08, 0, 1) * np.clip((1 - u) / 0.15, 0, 1)
    y = verb(y, sr, 0.4, 0.15, rng, damp=4500, keep=0.15)
    return write("sheep_%d" % (i + 1), y, sr, 0.75, edge_ms=60)


def gen_cow(i, sr=16000):
    rng = rng_for("cow%d" % i)
    d = [1.9, 1.5][i]
    base = [112, 128][i]
    n = int(sr * d)
    u = np.linspace(0, 1, n)
    t = u * d
    # "mm-OOOO-uh": starts closed (nasal), opens, swells in pitch, then drops.
    f0 = base * (0.85 + 0.25 * np.clip(u * 2.2, 0, 1) - 0.32 * np.clip((u - 0.62) / 0.38, 0, 1) ** 1.5) * (1 + 0.012 * np.sin(TAU * 5.5 * t))
    open_ = np.clip((u - 0.04) / 0.22, 0, 1)
    f1 = 280 + 230 * open_ - 60 * np.clip((u - 0.8) / 0.2, 0, 1)
    f2 = 760 + 200 * open_
    y = voice(f0, lambda: [(f1, 90, 1.0), (f2, 130, 0.55), (1800, 300, 0.08)], sr, tilt=0.9, nmax=45, rng=rng, breath=0.05)
    amp = np.clip(u / 0.12, 0, 1) ** 0.7 * np.clip((1 - u) / 0.2, 0, 1) * (0.55 + 0.45 * np.clip(u * 3, 0, 1))
    y *= amp
    y = filt(y, sr, lambda f: lp_gain(f, 2600, 2))
    y = verb(y, sr, 0.6, 0.2, rng, damp=3000, keep=0.25)
    return write("cow_%d" % (i + 1), y, sr, 0.8, edge_ms=120)


# --------------------------------------------------------------- impacts

def modal(sr, dur, modes, rng=None, click=0.0, click_band=(1500, 6000)):
    t = tvec(dur, sr)
    y = np.zeros_like(t)
    for (f, tau, a) in modes:
        y += a * np.sin(TAU * f * t + (rng.uniform(0, 1) if rng is not None else 0)) * np.exp(-t / tau)
    if click > 0:
        rng = rng or np.random.default_rng(2)
        L = int(sr * 0.006)
        c = filt(white(L, rng), sr, lambda f: bp_gain(f, *click_band, 1), pad=0.1)
        c *= np.exp(-np.arange(L) / sr / 0.0015)
        y[:L] += click * c / (np.max(np.abs(c)) + 1e-9)
    return y


def gen_hammer(i, sr=22050):
    rng = rng_for("hammer%d" % i)
    s = [1.0, 1.09, 0.93][i]
    y = modal(sr, 0.4, [(150 * s, 0.07, 1.0), (520 * s, 0.05, 0.7), (1190 * s, 0.035, 0.45),
                        (1910 * s, 0.022, 0.3), (2700 * s, 0.012, 0.15)], rng, click=1.1, click_band=(2000, 7000))
    y = verb(y, sr, 0.3, 0.18, rng, damp=4500, keep=0.1)
    return write("hammer_%d" % (i + 1), y, sr, 0.8, edge_ms=40)


def gen_chisel(i, sr=22050):
    rng = rng_for("chisel%d" % i)
    s = [1.0, 1.22][i]
    y = modal(sr, 0.45, [(2200 * s, 0.14, 1.0), (3350 * s, 0.09, 0.6), (5100 * s, 0.05, 0.3),
                         (900 * s, 0.05, 0.4)], rng, click=0.9, click_band=(3000, 9000))
    y = verb(y, sr, 0.3, 0.16, rng, damp=6000, keep=0.1)
    return write("stone_%d" % (i + 1), y, sr, 0.75, edge_ms=60)


def gen_saw(i, sr=16000):
    rng = rng_for("saw%d" % i)
    dur = 1.7
    n = int(sr * dur)
    t = np.arange(n) / sr
    tooth = 150 + 12 * i
    body = filt(white(n, rng), sr, lambda f: bp_gain(f, 900, 5200, 2), pad=0.05)
    res = filt(white(n, rng), sr, lambda f: bp_gain(f, 1600, 2100, 3), pad=0.05) * 1.4
    teeth = 0.55 + 0.45 * np.abs(np.sin(np.pi * tooth * t + 0.4 * np.sin(TAU * 3 * t)))
    # push (loud, long) then pull (quieter, shorter)
    u = t / dur
    stroke = np.where(u < 0.58, np.abs(np.sin(np.pi * u / 0.58)) ** 0.8, 0.55 * np.abs(np.sin(np.pi * (u - 0.58) / 0.42)) ** 0.8)
    x = (body * 0.8 + res) * teeth * stroke
    x = verb(x, sr, 0.25, 0.12, rng, damp=4000, keep=0.1)
    return write("saw_%d" % (i + 1), x, sr, 0.7, edge_ms=60)


def step_variant(kind, i, sr=16000):
    rng = rng_for("step_%s%d" % (kind, i))
    s = rng.uniform(0.92, 1.1)
    if kind == "grass":
        L = int(sr * 0.2)
        nz = filt(white(L, rng), sr, lambda f: bp_gain(f, 350, 2600, 2))
        env = np.sin(np.pi * np.linspace(0, 1, L) ** 0.6) ** 1.5
        y = nz * env
        y += 0.6 * modal(sr, 0.2, [(85 * s, 0.05, 1.0)])[:L]
    elif kind == "dirt":
        L = int(sr * 0.2)
        y = np.zeros(L)
        for g in range(int(rng.integers(6, 11))):
            at = int(abs(rng.normal(0, 0.035)) * sr)
            gl = int(sr * rng.uniform(0.004, 0.012))
            seg = filt(white(gl, rng), sr, lambda f: bp_gain(f, 900, 5000, 1), pad=0.1) * np.hanning(gl) * rng.uniform(0.3, 1.0)
            if at + gl < L:
                y[at:at + gl] += seg
        y += 0.8 * modal(sr, 0.2, [(95 * s, 0.045, 1.0)])[:L]
    elif kind == "sand":
        L = int(sr * 0.24)
        nz = filt(white(L, rng), sr, lambda f: bp_gain(f, 250, 1800, 2))
        y = nz * np.sin(np.pi * np.linspace(0, 1, L)) ** 2 * 0.9
        y += 0.4 * modal(sr, 0.24, [(70 * s, 0.05, 1.0)])[:L]
    elif kind == "stone":
        y = modal(sr, 0.22, [(110 * s, 0.05, 0.8), (780 * s, 0.03, 0.5), (1650 * s, 0.018, 0.35)], rng,
                  click=0.9, click_band=(1400, 5000))
    elif kind == "wood":
        y = modal(sr, 0.25, [(130 * s, 0.07, 0.8), (240 * s, 0.06, 0.8), (470 * s, 0.05, 0.6), (790 * s, 0.03, 0.35)],
                  rng, click=0.55, click_band=(1000, 4000))
    elif kind == "splash":
        L = int(sr * 0.42)
        nz = filt(white(L, rng), sr, lambda f: bp_gain(f, 300, 3500, 2))
        env = np.sin(np.pi * np.linspace(0, 1, L) ** 0.5) ** 2
        y = nz * env
        for b in range(7):
            gl = int(sr * rng.uniform(0.02, 0.04))
            k2 = np.arange(gl) / sr
            f = rng.uniform(500, 900) * (1 + 2.0 * k2 / k2[-1])
            seg = np.sin(TAU * np.cumsum(f) / sr) * np.exp(-k2 / 0.012) * 0.35
            at = int(rng.uniform(0.02, 0.3) * sr)
            if at + gl < L:
                y[at:at + gl] += seg
    else:
        raise ValueError(kind)
    return write("step_%s_%d" % (kind, i + 1), y, sr, 0.7, edge_ms=40)


# ---------------------------------------------------------------------- UI

def bell(f, dur, sr, bright=1.0, rng=None):
    """A small struck bell / music-box tine: slightly inharmonic partials."""
    t = tvec(dur, sr)
    parts = [(1.0, 1.0, 0.9), (2.0, 0.5 * bright, 0.55), (2.76, 0.28 * bright, 0.35), (5.4, 0.1 * bright, 0.15), (0.5, 0.15, 1.2)]
    y = np.zeros_like(t)
    for (r, a, tau) in parts:
        y += a * np.sin(TAU * f * r * t) * np.exp(-t / (tau * dur / 1.6))
    y *= np.clip(t / 0.003, 0, 1)
    return y


def seq_notes(notes, sr, dur, gain_shape=None, rng=None, tine_dur=1.5, bright=1.0):
    buf = np.zeros(int(dur * sr))
    for (t, m, a) in notes:
        seg = bell(note_hz(m), tine_dur, sr, bright) * a
        put(buf, seg, t, sr)
    return buf


def gen_ui(sr=22050):
    rng = rng_for("ui")
    sizes = {}
    # click: a soft wooden tick
    y = modal(sr, 0.09, [(1250, 0.012, 1.0), (2300, 0.007, 0.35), (420, 0.02, 0.5)], rng, click=0.3, click_band=(2000, 6000))
    sizes["ui_click"] = write("ui_click", y, sr, 0.55, edge_ms=15)
    y = modal(sr, 0.05, [(1900, 0.006, 1.0), (3100, 0.004, 0.3)], rng, click=0.1)
    sizes["ui_hover"] = write("ui_hover", y, sr, 0.3, edge_ms=10)
    # notification: two soft bell notes, a fifth apart
    y = seq_notes([(0.0, 81, 0.8), (0.14, 88, 1.0)], sr, 1.1, bright=0.7, tine_dur=1.0)
    y = verb(y, sr, 0.6, 0.25, rng, damp=6000, keep=0.2)
    sizes["ui_chime"] = write("ui_chime", y, sr, 0.6, edge_ms=300)
    # milestone: a rising D major arpeggio that lingers
    y = seq_notes([(0.0, 74, 0.7), (0.13, 78, 0.75), (0.26, 81, 0.8), (0.4, 86, 1.0), (0.4, 78, 0.35)], sr, 1.8, bright=0.8, tine_dur=1.5)
    y = verb(y, sr, 0.9, 0.3, rng, damp=5500, keep=0.3)
    sizes["ui_milestone"] = write("ui_milestone", y, sr, 0.65, edge_ms=500)
    # building complete: warm marimba-ish three notes
    buf = np.zeros(int(1.4 * sr))
    for (tt, m, a) in [(0.0, 62, 0.8), (0.17, 66, 0.85), (0.34, 69, 1.0)]:
        tt_ = tvec(1.2, sr)
        seg = (np.sin(TAU * note_hz(m) * tt_) + 0.45 * np.sin(TAU * note_hz(m) * 4.0 * tt_) * np.exp(-tt_ / 0.05)
               + 0.12 * np.sin(TAU * note_hz(m) * 2 * tt_)) * np.exp(-tt_ / 0.38) * np.clip(tt_ / 0.004, 0, 1)
        put(buf, seg * a, tt, sr)
    buf = verb(buf, sr, 0.7, 0.28, rng, damp=4500, keep=0.2)
    sizes["ui_built"] = write("ui_built", buf, sr, 0.65, edge_ms=400)
    # alert: two low, soft descending notes (a horn heard through a wall)
    buf = np.zeros(int(1.3 * sr))
    for (tt, m, d) in [(0.0, 57, 0.5), (0.45, 50, 0.9)]:
        seg = tone(d, sr, lambda u, m=m: note_hz(m) * (1 + 0.0 * u), harm=(1, 0.6, 0.35, 0.15), amp_pow=0.6, attack=0.06)
        put(buf, seg, tt, sr)
    buf = filt(buf, sr, lambda f: lp_gain(f, 1400, 2))
    buf = verb(buf, sr, 0.6, 0.25, rng, damp=2500, keep=0.2)
    sizes["ui_alert"] = write("ui_alert", buf, sr, 0.6, edge_ms=300)
    # page turn: a paper sweep with a small catch at the start
    n = int(sr * 0.55)
    t = np.arange(n) / sr
    nz = white(n, rng)
    sweep = np.sin(np.pi * np.clip((t - 0.02) / 0.4, 0, 1)) ** 2
    lo = 1500 + 3500 * np.clip(t / 0.4, 0, 1)
    a = filt(nz, sr, lambda f: bp_gain(f, 1200, 4000, 1))
    b = filt(nz, sr, lambda f: bp_gain(f, 3500, 8000, 1))
    mix = a * (1 - np.clip(t / 0.4, 0, 1)) + b * np.clip(t / 0.4, 0, 1)
    # rustle: fast random amplitude flutter
    flutter = 0.6 + 0.4 * np.abs(smooth_noise(n, sr, 90.0, rng))
    y = mix * sweep * flutter
    y += 0.5 * np.exp(-t / 0.01) * filt(white(n, rng), sr, lambda f: bp_gain(f, 400, 2500, 1))
    sizes["ui_page"] = write("ui_page", y, sr, 0.5, edge_ms=60)
    return sizes


# ------------------------------------------------------------------ music

def pluck(m, sr=16000, dur=1.15):
    f = note_hz(m)
    t = tvec(dur, sr)
    y = np.zeros_like(t)
    nh = int(min(14, (sr * 0.45) / f))
    for k in range(1, nh + 1):
        # sharp pluck: every partial starts together, the high ones die first
        tau = 1.25 / (1.0 + 0.75 * (k - 1)) * (1.0 if f > 200 else 1.25)
        a = k ** -1.25
        fk = f * k * (1 + 0.0004 * k * k)  # a little stiffness, like a real string
        y += a * np.sin(TAU * fk * t + k) * np.exp(-t / tau)
    y *= np.clip(t / 0.002, 0, 1)
    rng = np.random.default_rng(int(m))
    L = int(sr * 0.012)
    c = filt(white(L, rng), sr, lambda g: bp_gain(g, 600, 3500, 1), pad=0.1) * np.exp(-np.arange(L) / sr / 0.003)
    y[:L] += 0.25 * c / (np.max(np.abs(c)) + 1e-9) * np.max(np.abs(y))
    y = verb(y, sr, 0.5, 0.18, rng, damp=3000, keep=0.1)
    return y


def flute(m, sr=16000, dur=1.5):
    rng = np.random.default_rng(int(m) * 7)
    f = note_hz(m)
    t = tvec(dur, sr)
    vib_amt = np.clip((t - 0.35) / 0.5, 0, 1) * 0.006
    ff = f * (1 + vib_amt * np.sin(TAU * 5.1 * t) + 0.012 * np.exp(-t / 0.05))  # a small scoop in
    ph = TAU * np.cumsum(ff) / sr
    y = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    env = np.clip(t / 0.09, 0, 1) ** 1.5 * np.exp(-np.maximum(t - 0.5, 0) / 0.9) * np.clip((dur - t) / 0.35, 0, 1)
    breath = filt(white(len(t), rng), sr, lambda g: bp_gain(g, f * 1.2, f * 3.2, 1), pad=0.05)
    br_env = np.exp(-t / 0.25) * 0.5 + 0.06
    y = y * env + breath / (np.max(np.abs(breath)) + 1e-9) * br_env * env.max() * 0.22 * np.clip((dur - t) / 0.35, 0, 1)
    y = verb(y, sr, 0.7, 0.3, rng, damp=3500, keep=0.2)
    return y


def gen_music():
    sizes = {}
    pl = [50, 54, 57, 59, 62, 64, 66, 69, 71, 74, 76, 78]
    for m in pl:
        sizes["pluck_%d" % m] = write("pluck_%d" % m, pluck(m), 16000, 0.8, edge_ms=250)
    for m in [69, 71, 74, 76, 78, 81]:
        sizes["flute_%d" % m] = write("flute_%d" % m, flute(m), 16000, 0.7, edge_ms=300)
    return sizes


def gen_pad(name, midis, sr=11025, T=6.0, seed=0):
    rng = np.random.default_rng(100 + seed)
    n = int(sr * T)
    t = np.arange(n) / sr
    x = np.zeros(n)
    for j, m in enumerate(midis):
        f0 = note_hz(m)
        for d in (-1.0, 0.0, 1.0):
            # frequencies snapped to whole cycles per loop so it joins seamlessly
            f = round((f0 * (1 + d * 0.0012)) * T) / T
            ph = rng.uniform(0, TAU)
            v = np.sin(TAU * f * t + ph) + 0.28 * np.sin(TAU * 2 * f * t + ph * 1.3) + 0.08 * np.sin(TAU * 3 * f * t)
            cyc = 1 + (j + int(d + 1)) % 3
            swell = 0.65 + 0.35 * np.sin(TAU * cyc * t / T + rng.uniform(0, TAU))
            x += v * swell * (0.6 if m < 55 else 1.0)
    x += fft_noise(n, sr, lambda f: bp_gain(f, 200, 1200, 2), rng) * 0.05 * np.max(np.abs(x)) / 3
    return write(name, x, sr, 0.7)


def gen_pads():
    s = {}
    s["pad_day"] = gen_pad("pad_day", [50, 57, 64, 66], seed=1)      # D  A  E  F#   (Dadd9)
    s["pad_eve"] = gen_pad("pad_eve", [55, 59, 62, 69], seed=2)      # G  B  D  A    (Gmaj9-ish)
    s["pad_night"] = gen_pad("pad_night", [47, 54, 57, 62], seed=3)  # B  F# A  D    (Bm7)
    return s


# ------------------------------------------------------------------- main

def main():
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a[7:].split(","))
        elif a == "--only" and len(sys.argv) > sys.argv.index(a) + 1:
            only = set(sys.argv[sys.argv.index(a) + 1].split(","))

    jobs = {
        "wind_loop": gen_wind, "rain_loop": gen_rain, "water_loop": gen_water,
        "murmur_loop": gen_murmur, "crickets_loop": gen_crickets,
        "thunder": lambda: {"thunder_%d" % i: gen_thunder(i) for i in range(2)},
        "birds": lambda: {**{"tweet%d" % i: gen_tweet(i) for i in range(3)},
                          **{"trill%d" % i: gen_trill(i) for i in range(2)},
                          **{"warble%d" % i: gen_warble(i) for i in range(3)},
                          **{"thrush%d" % i: gen_thrush(i) for i in range(2)},
                          "cuckoo": gen_cuckoo(), "dove": gen_dove(),
                          "owl0": gen_owl(0), "owl1": gen_owl(1)},
        "animals": lambda: {**{"hen%d" % i: gen_hen(i) for i in range(3)},
                            **{"sheep%d" % i: gen_sheep(i) for i in range(2)},
                            **{"cow%d" % i: gen_cow(i) for i in range(2)}},
        "work": lambda: {**{"hammer%d" % i: gen_hammer(i) for i in range(3)},
                         **{"stone%d" % i: gen_chisel(i) for i in range(2)},
                         **{"saw%d" % i: gen_saw(i) for i in range(2)}},
        "steps": lambda: {"%s%d" % (k, i): step_variant(k, i)
                          for k, c in [("grass", 3), ("dirt", 3), ("stone", 3), ("wood", 3), ("sand", 2), ("splash", 2)]
                          for i in range(c)},
        "ui": gen_ui, "music": gen_music, "pads": gen_pads,
    }
    total = 0
    for name, fn in jobs.items():
        if only and name not in only:
            continue
        r = fn()
        sz = sum(r.values()) if isinstance(r, dict) else r
        total += sz
        print("%-14s %7.1f KB" % (name, sz / 1024.0))
    tot = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".wav"))
    print("assets/audio total: %.2f MB in %d files" % (tot / 1048576.0, len([f for f in os.listdir(OUT) if f.endswith('.wav')])))


if __name__ == "__main__":
    main()
