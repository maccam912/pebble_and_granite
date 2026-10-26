#!/usr/bin/env python3
"""Bake our original, seamless curling-pebble material (requires NumPy/Pillow).

Run from the repository root. RG stores shallow surface normals, B frosted-bank
coverage and A nipped-top coverage, all linear data. No photographs are sampled.
The 50 cm tile has 40,000 scattered droplets/m², with 2-6 mm base diameters.
"""
from pathlib import Path
import math
import random

import numpy as np
from PIL import Image


def generate() -> Image.Image:
    size, metres = 1024, 0.5
    rng = random.Random(2601026)
    height = np.zeros((size, size), dtype=np.float32)
    packed = np.zeros((size, size, 4), dtype=np.float32)
    packed[:, :, :2] = 0.5
    for _ in range(10000):
        cx, cy = rng.random() * size, rng.random() * size
        radius = rng.uniform(0.001, 0.003) * size / metres
        top_radius = rng.uniform(0.24, 0.38)
        aspect = rng.uniform(0.85, 1.15)
        angle, phase = rng.random() * math.tau, rng.random() * math.tau
        cosine, sine = math.cos(angle), math.sin(angle)
        frosting = rng.uniform(0.45, 0.90)
        # A shallow spherical segment: about 0.12 mm tall at 4 mm diameter.
        uncut_height = radius * 0.066
        reach = int(np.ceil(radius * max(aspect, 1.0 / aspect) + 1))
        x = np.arange(int(cx) - reach, int(cx) + reach + 1)
        y = np.arange(int(cy) - reach, int(cy) + reach + 1)
        dx, dy = np.meshgrid((x - cx) / radius, (y - cy) / radius)
        u, v = (dx * cosine + dy * sine) / aspect, (-dx * sine + dy * cosine) * aspect
        distance = np.sqrt(u * u + v * v)
        cap = np.maximum(1.0 - distance * distance, 0.0)
        top_height = 1.0 - top_radius * top_radius
        segment = np.minimum(cap, top_height) * uncut_height
        iy, ix = np.meshgrid(y % size, x % size, indexing="ij")
        visible = segment > height[iy, ix]
        height[iy, ix] = np.maximum(segment, height[iy, ix])
        edge = np.clip((1.0 - distance) * radius, 0.0, 1.0)
        top = np.clip((top_radius - distance) * radius + 0.5, 0.0, 1.0)
        slope = 0.132 * edge * (1.0 - top)
        nx = (u / aspect * cosine - v * aspect * sine) * slope
        ny = (u / aspect * sine + v * aspect * cosine) * slope
        normal_length = np.sqrt(1.0 + nx * nx + ny * ny)
        # Freeze patterns vary around each bank instead of outlining every
        # droplet with an identical white ring.
        frost = edge * (1.0 - top) * frosting * (0.75 + 0.25 * np.sin(u * 8 + phase) * np.sin(v * 9 + phase))
        material = np.stack((0.5 + nx / normal_length * 0.5,
                             0.5 + ny / normal_length * 0.5, frost, top), axis=-1)
        packed[iy, ix] = np.where(visible[:, :, None], material, packed[iy, ix])
    return Image.fromarray(np.round(np.clip(packed, 0, 1) * 255).astype(np.uint8))


if __name__ == "__main__":
    destination = Path(__file__).resolve().parents[1] / "assets/textures/curling-pebble.png"
    generate().save(destination, optimize=True)
    print(f"ICE_PEBBLE_MATERIAL_OK {destination}")
