#!/usr/bin/env python3
"""
Synthesize a techno x hip-hop one-shot drum kit (909/808 flavored) as 16-bit
mono WAV files, using only the Python standard library. Output goes into
samples/ next to this file, which is where create_hiphop_techno.lua loads them
into ReaSamplOmatic5000 from.
"""
import math, os, struct, wave, random

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")
os.makedirs(OUT, exist_ok=True)
random.seed(7)

# ---------- primitives -------------------------------------------------------
def buf(seconds):
    return [0.0] * int(SR * seconds)

def env_exp(n, decay, attack=0.0005):
    """attack then exponential decay envelope, length n samples."""
    out = []
    a = max(1, int(attack * SR))
    for i in range(n):
        t = i / SR
        amp = math.exp(-t / decay)
        if i < a:
            amp *= i / a
        out.append(amp)
    return out

def add_sine(b, freq_fn, amp_fn, phase0=0.0):
    ph = phase0
    for i in range(len(b)):
        f = freq_fn(i / SR) if callable(freq_fn) else freq_fn
        ph += 2 * math.pi * f / SR
        a = amp_fn[i] if isinstance(amp_fn, list) else amp_fn
        b[i] += math.sin(ph) * a

def add_noise(b, amp_fn):
    for i in range(len(b)):
        a = amp_fn[i] if isinstance(amp_fn, list) else amp_fn
        b[i] += (random.random() * 2 - 1) * a

def highpass(b, fc):
    rc = 1.0 / (2 * math.pi * fc); dt = 1.0 / SR
    a = rc / (rc + dt)
    out = [0.0] * len(b); prev_x = 0.0; prev_y = 0.0
    for i, x in enumerate(b):
        y = a * (prev_y + x - prev_x)
        out[i] = y; prev_x = x; prev_y = y
    return out

def lowpass(b, fc):
    rc = 1.0 / (2 * math.pi * fc); dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out = [0.0] * len(b); prev = 0.0
    for i, x in enumerate(b):
        prev = prev + alpha * (x - prev); out[i] = prev
    return out

def tanh_drive(b, k):
    return [math.tanh(x * k) for x in b]

def normalize(b, peak=0.92):
    m = max(1e-9, max(abs(x) for x in b))
    g = peak / m
    return [x * g for x in b]

def save(name, b):
    b = normalize(b)
    # tiny fade-out to avoid clicks
    fo = min(200, len(b))
    for i in range(fo):
        b[len(b) - 1 - i] *= i / fo
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in b))
    print(f"  {name:16s} {len(b)/SR:.3f}s")

# ---------- voices -----------------------------------------------------------
def kick():
    b = buf(0.45); n = len(b)
    amp = env_exp(n, 0.30)
    add_sine(b, lambda t: 48 + (155 - 48) * math.exp(-t / 0.028), amp)
    click = env_exp(int(SR * 0.006), 0.0018)
    for i in range(len(click)):
        b[i] += (random.random() * 2 - 1) * click[i] * 0.6
    return tanh_drive(b, 1.6)

def snare():
    b = buf(0.20); n = len(b)
    body = env_exp(n, 0.085)
    add_sine(b, 185, [x * 0.5 for x in body])
    add_sine(b, 278, [x * 0.35 for x in body])
    nz = buf(0.20); add_noise(nz, env_exp(n, 0.13))
    nz = highpass(nz, 1400)
    for i in range(n): b[i] += nz[i] * 0.85
    return tanh_drive(b, 1.2)

def clap():
    b = buf(0.22); n = len(b)
    # three sharp bursts then a diffuse tail
    for off in (0.0, 0.009, 0.018):
        s = int(off * SR)
        e = env_exp(int(SR * 0.02), 0.006)
        for i in range(len(e)):
            if s + i < n: b[s + i] += (random.random() * 2 - 1) * e[i]
    tail = buf(0.22); add_noise(tail, env_exp(n, 0.10))
    for i in range(n): b[i] += tail[i] * 0.5
    b = highpass(b, 1100); b = lowpass(b, 9000)
    return b

def rim():
    b = buf(0.05); n = len(b)
    amp = env_exp(n, 0.007)
    add_sine(b, 1750, amp)
    add_noise(b, [x * 0.6 for x in amp])
    return highpass(b, 1200)

def hat_closed():
    b = buf(0.06); add_noise(b, env_exp(len(b), 0.022))
    b = highpass(b, 7500)
    return b

def hat_open():
    b = buf(0.40); add_noise(b, env_exp(len(b), 0.18))
    b = highpass(b, 7000)
    return b

def crash():
    b = buf(1.30); n = len(b)
    amp = env_exp(n, 0.55)
    add_noise(b, amp)
    for f in (5200, 7100, 9300, 11500):  # metallic shimmer
        add_sine(b, f, [x * 0.05 for x in amp])
    b = highpass(b, 3000)
    return b

def tom():  # mid tom, played pitched by the sampler for low/mid/hi
    b = buf(0.35); n = len(b)
    amp = env_exp(n, 0.22)
    add_sine(b, lambda t: 120 + 70 * math.exp(-t / 0.05), amp)
    return tanh_drive(b, 1.2)

def cowbell():
    b = buf(0.25); n = len(b)
    amp = env_exp(n, 0.16)
    for f in (540, 800):  # classic 808-ish two-tone
        sq = buf(0.25); add_sine(sq, f, amp); add_sine(sq, f * 3, [x * 0.3 for x in amp])
        for i in range(n): b[i] += sq[i]
    b = lowpass(b, 6000); b = highpass(b, 400)
    return tanh_drive(b, 1.1)

def shaker():
    b = buf(0.09); add_noise(b, env_exp(len(b), 0.035, attack=0.004))
    b = highpass(b, 5500); b = lowpass(b, 12000)
    return b

def conga(base=220):  # base pitch in Hz: ~220 high conga, ~160 low conga
    b = buf(0.26); n = len(b)
    amp = env_exp(n, 0.16)
    add_sine(b, lambda t: base + 90 * math.exp(-t / 0.04), amp)
    return tanh_drive(b, 1.1)

def clave():
    b = buf(0.05); add_sine(b, 2500, env_exp(len(b), 0.013))
    return b

# ---------- render -----------------------------------------------------------
print(f"Writing kit to: {OUT}")
# file names match the addDrum() calls in create_hiphop_techno.lua
# (rim/crash/tom/cowbell are extras the script doesn't load yet)
voices = {
    "kick.wav": kick, "snare.wav": snare, "clap.wav": clap, "rim.wav": rim,
    "hatc.wav": hat_closed, "hato.wav": hat_open, "crash.wav": crash,
    "tom.wav": tom, "cowbell.wav": cowbell, "shaker.wav": shaker,
    "congah.wav": conga, "congal.wav": lambda: conga(160), "clave.wav": clave,
}
for name, fn in voices.items():
    save(name, fn())
print("DONE")
