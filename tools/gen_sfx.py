"""Generate placeholder sound effects (WAV) for the prototype.

Usage (from project root):
    python tools/gen_sfx.py

Writes 16-bit mono WAV files (22050 Hz) into assets/audio/.
All sounds are synthesized with the Python standard library only.
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def write_wav(name: str, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.9 / peak
    frames = bytearray()
    for s in samples:
        s = max(-1.0, min(1.0, s * gain))
        frames += struct.pack("<h", int(s * 32767))
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("wrote %s (%.2fs)" % (os.path.normpath(path), len(samples) / SR))


def env_exp(i: int, n: int, k: float) -> float:
    return math.exp(-k * i / n)


def gen_swing() -> list[float]:
    n = int(SR * 0.14)
    out = []
    for i in range(n):
        t = i / SR
        swell = math.sin(math.pi * i / n)
        noise = random.uniform(-1.0, 1.0)
        sweep = math.sin(2.0 * math.pi * (3000.0 * t - 8000.0 * t * t))
        out.append(0.5 * swell * (0.65 * noise + 0.35 * sweep))
    return out


def gen_hit() -> list[float]:
    n = int(SR * 0.16)
    out = []
    for i in range(n):
        t = i / SR
        thump = math.sin(2.0 * math.pi * (95.0 - 40.0 * t) * t)
        noise = random.uniform(-1.0, 1.0) * max(0.0, 1.0 - i / (SR * 0.03))
        out.append((0.9 * thump + 0.5 * noise) * env_exp(i, n, 7.0))
    return out


def gen_pickup() -> list[float]:
    total = int(SR * 0.18)
    out = [0.0] * total
    for f0, delay in ((660.0, 0.0), (990.0, 0.07)):
        n = int(SR * 0.06)
        start = int(SR * delay)
        for i in range(n):
            if start + i >= total:
                break
            out[start + i] += 0.6 * math.sin(2.0 * math.pi * f0 * i / SR) * math.exp(-6.0 * i / n)
    return out


def gen_hurt() -> list[float]:
    n = int(SR * 0.25)
    out = []
    for i in range(n):
        t = i / SR
        f = 240.0 - 360.0 * t
        out.append((0.8 * math.sin(2.0 * math.pi * f * t) + 0.2 * random.uniform(-1.0, 1.0)) * env_exp(i, n, 5.0))
    return out


def gen_zombie_die() -> list[float]:
    n = int(SR * 0.45)
    out = []
    for i in range(n):
        t = i / SR
        f = 150.0 - 220.0 * t
        growl = math.sin(2.0 * math.pi * 18.0 * t)
        s = 0.7 * math.sin(2.0 * math.pi * f * t) + 0.4 * random.uniform(-1.0, 1.0) * growl
        out.append(s * env_exp(i, n, 4.0))
    return out


def main() -> None:
    random.seed(7)
    write_wav("swing.wav", gen_swing())
    write_wav("hit.wav", gen_hit())
    write_wav("pickup.wav", gen_pickup())
    write_wav("hurt.wav", gen_hurt())
    write_wav("zombie_die.wav", gen_zombie_die())


if __name__ == "__main__":
    main()
