#!/usr/bin/env python3
# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : gen_textures.py
# Copyright : (c) Zex Interactive. All rights reserved.

"""Generates the seamless terrain albedo tiles in assets/map/tex/ (numpy + PIL). Run: python3 tools/gen_textures.py"""
import numpy as np
from PIL import Image
import os
S = 512
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "tex")
os.makedirs(OUT, exist_ok=True)


def fnoise(beta=2.0, seed=None, aniso=(1.0, 1.0)):
    r = np.random.default_rng(seed)
    f = np.fft.fftfreq(S)
    fx, fy = np.meshgrid(f * aniso[0], f * aniso[1])
    amp = 1.0 / np.maximum(np.sqrt(fx ** 2 + fy ** 2), 1.0 / S) ** beta
    amp[0, 0] = 0
    ph = np.exp(2j * np.pi * r.random((S, S)))
    n = np.real(np.fft.ifft2(amp * ph))
    n -= n.min()
    return n / n.max()


def voronoi(cells, seed, jitter=0.9):
    r = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1) + 0.5 + (r.random((cells, cells, 2)) - 0.5) * jitter) / cells
    ys, xs = np.mgrid[0:S, 0:S] / S
    d1 = np.full((S, S), 9.0)
    d2 = np.full((S, S), 9.0)
    ids = np.zeros((S, S), int)
    for j in range(cells):
        for i in range(cells):
            px, py = pts[j, i]
            dx = np.abs(xs - px); dx = np.minimum(dx, 1 - dx)
            dy = np.abs(ys - py); dy = np.minimum(dy, 1 - dy)
            d = np.sqrt(dx * dx + dy * dy)
            m = d < d1
            d2 = np.where(m, d1, np.minimum(d2, d))
            ids = np.where(m, j * cells + i, ids)
            d1 = np.where(m, d, d1)
    return d1, d2, ids


def relief(h, strength=3.0):
    gx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    gy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    return np.clip(0.5 + (-gx - gy) * strength, 0, 1)


def save(name, rgb):
    img = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, name))
    print("wrote", name)


def mix(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


# ---------------------------------------------------------------- extra starter materials
def tone(c0, c1, t):
    return mix(np.array(c0), np.array(c1), np.clip(t, 0, 1))

# sand
n = fnoise(2.2, 21); r = fnoise(1.2, 22, aniso=(1.0, 0.35)); g = fnoise(0.5, 23)
sand = tone((0.62, 0.52, 0.34), (0.80, 0.70, 0.50), n * 1.1) * (0.82 + 0.25 * relief(r, 2.5) + 0.12 * g)[..., None]
save("sand.png", sand)

# snow
n = fnoise(2.4, 31); g = fnoise(0.7, 32)
snow = tone((0.80, 0.84, 0.90), (0.97, 0.98, 1.0), n) * (0.93 + 0.1 * g)[..., None]
save("snow.png", snow)

# gravel (voronoi stones)
d1, d2, ids = voronoi(26, 41)
rr = np.random.default_rng(42).random(26 * 26)
stone = np.array([0.30, 0.28, 0.26]) + rr[ids][..., None] * np.array([0.30, 0.26, 0.22])
edge = np.clip((d2 - d1) * 26 * 1.8, 0, 1)
gravel = stone * (0.45 + 0.55 * edge)[..., None] * (0.85 + 0.3 * fnoise(0.8, 43))[..., None]
save("gravel.png", gravel)

# mud
n = fnoise(2.6, 51); m = fnoise(1.4, 52); g = fnoise(0.7, 53)
mud = tone((0.17, 0.11, 0.07), (0.34, 0.24, 0.15), n * 1.2) * (0.78 + 0.35 * relief(m, 3.0) + 0.1 * g)[..., None]
save("mud.png", mud)

# railway ballast (small angular stones, grey)
d1, d2, ids = voronoi(48, 61, 1.0)
rr = np.random.default_rng(62).random(48 * 48)
st = (0.28 + rr[ids] * 0.34)[..., None] * np.array([1.0, 0.98, 0.95])
edge = np.clip((d2 - d1) * 48 * 1.6, 0, 1)
ballast = st * (0.4 + 0.6 * edge)[..., None]
save("ballast.png", ballast)

# dry cracked earth
d1, d2, ids = voronoi(10, 71, 0.8)
rr = np.random.default_rng(72).random(100)
plate = tone((0.50, 0.38, 0.25), (0.66, 0.52, 0.36), rr[ids] * 0.9 + 0.1 * fnoise(1.5, 73))
crack = np.clip((d2 - d1) * 10 * 6, 0, 1)
dry = plate * (0.35 + 0.65 * crack)[..., None]
save("dry_earth.png", dry)

# asphalt (dark grey, fine grain, faint cracks)
g1 = fnoise(0.4, 81); g2 = fnoise(1.6, 82); g3 = fnoise(2.4, 83)
base = 0.17 + 0.07 * g1 + 0.05 * g2 + 0.03 * g3
d1, d2, ids = voronoi(7, 84, 1.0)
crack = np.clip((d2 - d1) * 7 * 14, 0, 1)
asph = (base * (0.80 + 0.2 * crack))[..., None] * np.array([1.0, 1.0, 1.04])
save("asphalt.png", asph)
