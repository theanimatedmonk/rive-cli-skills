# Plants the meadow round the lake: grass clumps, leafy bushes, sunflowers,
# white daisies and small yellow and white flowers, as GPU instances of
# Shishupalgarh's template meshes (taken from ../sheesupalgarh/ruins.bin).
#
# Placed on the terrain (terrain_grid.py) where it is dry land: off the
# water, off the pale shore path, not too steep, and denser near the hero
# camera (Cam_Hero), whose view the scene is built for.

import os
import struct
import numpy as np

import terrain_grid as tg

RUINS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'sheesupalgarh', 'ruins.bin')
# Template ids, as in ruins.bin: a leaf, a grass clump, a small flower, a
# leafy clump (bushes) and a bloom on its stem (sunflowers and daisies).
TEMPLATES = (20, 22, 23, 24, 25)
# Instance kinds (lake.wgsl), and the template each one draws.
LEAF, GRASS, FLOWER, BUSH, SUNFLOWER, DAISY = 10, 13, 14, 15, 21, 22
TEMPLATE_OF = {LEAF: 20, GRASS: 22, FLOWER: 23, BUSH: 24, SUNFLOWER: 25, DAISY: 25}
HERO = np.array([0.0, 2.4, 6.0])
HERO_YAW = np.radians(-3.06)


def templates():
    d = open(RUINS, 'rb').read()
    n = struct.unpack_from('<I', d, 8)[0]
    out = {}
    for i in range(n):
        k, c, ic, vbo, vbl, ibo, ibl, _ = struct.unpack_from('<8I', d, 12 + i * 192)
        if k in TEMPLATES:
            out[k] = (c, ic, d[vbo:vbo + vbl], d[ibo:ibo + ibl])
    return out


def snorm(x):
    return np.clip(np.round(x * 127), -127, 127).astype(np.int8)


class Field:
    def __init__(self, grid, rng):
        self.g = grid
        self.rng = rng
        h, c, up, wet = grid['height'], grid['color'], grid['up'], grid['water']
        lum = np.nan_to_num(c @ np.array([0.3, 0.59, 0.11]))
        mx, mn = np.nan_to_num(c.max(2)), np.nan_to_num(c.min(2))
        sat = (mx - mn) / np.maximum(mx, 1e-3)
        # Off the water by a margin (a dilation of its mask).
        near_water = wet.copy()
        for _ in range(4):
            n = near_water.copy()
            n[1:] |= near_water[:-1]; n[:-1] |= near_water[1:]
            n[:, 1:] |= near_water[:, :-1]; n[:, :-1] |= near_water[:, 1:]
            near_water = n
        path = (lum > 0.6) & (sat < 0.4)
        self.ok = ~np.isnan(h) & ~near_water & ~path & (np.nan_to_num(up) > 0.8) & (np.nan_to_num(h, nan=-9) > 0.03)
        self.lum = lum
        self.height = np.nan_to_num(h)
        self.up = np.nan_to_num(up, nan=1.0)

    def sample(self, count, max_dist, near=12.0, wedge=75.0, mask=None, min_dist=2.0):
        """Points on the dry land in view of the hero camera, thinning with
        distance; returns positions and the ground's baked light."""
        pts, light = [], []
        tries = 0
        while sum(len(p) for p in pts) < count and tries < 60:
            tries += 1
            m = count * 4
            # Uniform over a disc sector in front of the camera, then thinned.
            ang = HERO_YAW + np.radians(self.rng.uniform(-wedge, wedge, m))
            r = max_dist * np.sqrt(self.rng.uniform((min_dist / max_dist) ** 2, 1, m))
            x = HERO[0] - np.sin(ang) * r
            z = HERO[2] - np.cos(ang) * r
            keep = self.rng.uniform(0, 1, m) < np.clip(near / r, 0.0, 1.0) ** 0.6
            i = np.round((x - tg.X0) / tg.STEP).astype(int)
            j = np.round((z - tg.Z0) / tg.STEP).astype(int)
            inside = (i >= 0) & (i < self.g['nx']) & (j >= 0) & (j < self.g['nz'])
            keep &= inside
            i, j, x, z = i[keep], j[keep], x[keep], z[keep]
            k = self.ok[j, i]
            if mask is not None:
                k &= mask(x, z)
            i, j, x, z = i[k], j[k], x[k], z[k]
            pts.append(np.stack([x, self.height[j, i], z], 1))
            light.append(self.lum[j, i])
        p = np.concatenate(pts)[:count]
        return p, np.concatenate(light)[:len(p)]


def patches(seed, scale, threshold):
    """A mask of soft patches: sums of a few random waves."""
    rng = np.random.default_rng(seed)
    waves = [(rng.uniform(0, 2 * np.pi), rng.uniform(0.6, 1.4) / scale, rng.uniform(0, 2 * np.pi)) for _ in range(5)]

    def mask(x, z):
        v = sum(np.sin((np.cos(a) * x + np.sin(a) * z) * f + p) for a, f, p in waves) / 5
        return v > threshold
    return mask


def pack(kind, pos, scale, ax, ay, r1, r2, light):
    n = len(pos)
    v = np.zeros(n, dtype=[('p', '<f2', 4), ('x', 'i1', 4), ('y', 'i1', 4), ('k', 'u1', 4)])
    v['p'][:, :3] = pos
    v['p'][:, 3] = scale
    v['x'][:, :3] = snorm(ax)
    v['x'][:, 3] = snorm(r1 * 2 - 1)
    v['y'][:, :3] = snorm(ay)
    v['y'][:, 3] = snorm(r2 * 2 - 1)
    v['k'][:, 0] = kind
    v['k'][:, 1] = np.clip(np.round(light / 0.75 * 255), 0, 255)
    return v.tobytes()


def upright(rng, n, tilt, facing=None, spread=np.pi):
    """Axes for n instances: y near up (tilted up to `tilt` rad), z turned
    toward `facing` (xz directions) give or take `spread`, else at random."""
    yaw = rng.uniform(-np.pi, np.pi, n) if facing is None else np.arctan2(facing[:, 0], facing[:, 1]) + rng.uniform(-spread, spread, n)
    az = np.stack([np.sin(yaw), np.zeros(n), np.cos(yaw)], 1)
    t = rng.uniform(0, tilt, n)
    ta = rng.uniform(-np.pi, np.pi, n)
    ay = np.stack([np.sin(t) * np.cos(ta), np.cos(t), np.sin(t) * np.sin(ta)], 1)
    ay /= np.linalg.norm(ay, axis=1, keepdims=True)
    ax = np.cross(ay, az)
    ax /= np.maximum(np.linalg.norm(ax, axis=1, keepdims=True), 1e-6)
    return ax, ay


def plant(grid, seed=11):
    rng = np.random.default_rng(seed)
    f = Field(grid, rng)
    out = []  # (kind, template, count, bytes)

    def add(kind, pos, scale, ax, ay, light):
        out.append((kind, TEMPLATE_OF[kind], len(pos), pack(kind, pos, scale, ax, ay, rng.uniform(0, 1, len(pos)), rng.uniform(0, 1, len(pos)), light)))
        print(f'  {kind:3d} x {len(pos)}')

    # Grass: tufts over all the meadow, thickest near.
    p, l = f.sample(22000, 75, near=10)
    ax, ay = upright(rng, len(p), 0.25)
    add(GRASS, p, rng.uniform(1.0, 1.7, len(p)), ax, ay, l)

    # Bushes: clumps in drifts along the tree lines and the shore.
    p, l = f.sample(300, 110, near=70, wedge=60, mask=patches(3, 9.0, 0.15), min_dist=14)
    s = rng.uniform(0.9, 2.1, len(p))
    p[:, 1] += s * 0.45
    ax, ay = upright(rng, len(p), 0.1)
    add(BUSH, p, s, ax, ay, l)
    # Their leaves, over each clump's surface, facing out.
    reps = 46
    c = np.repeat(p, reps, 0)
    cs = np.repeat(s, reps)
    cl = np.repeat(l, reps)
    d = rng.normal(size=(len(c), 3))
    d[:, 1] = np.abs(d[:, 1]) * 0.9 + 0.1
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    lp = c + d * cs[:, None] * np.array([0.95, 0.85, 0.95])
    tangent = np.cross(d, rng.normal(size=(len(c), 3)))
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-6)
    lax = np.cross(d, tangent)
    add(LEAF, lp, cs * rng.uniform(2.6, 3.6, len(c)), lax, d, cl)

    # Sunflowers: tall patches in the open meadow, heads to the camera.
    p, l = f.sample(700, 70, near=60, wedge=45, mask=patches(5, 3.5, 0.3), min_dist=16)
    toward = HERO[[0, 2]] - p[:, [0, 2]]
    toward /= np.linalg.norm(toward, axis=1, keepdims=True)
    ax, ay = upright(rng, len(p), 0.12, toward, 0.6)
    add(SUNFLOWER, p, rng.uniform(0.42, 0.6, len(p)), ax, ay, l)

    # White daisies: drifts through the grass.
    p, l = f.sample(4200, 70, near=18, mask=patches(8, 6.0, 0.05))
    toward = HERO[[0, 2]] - p[:, [0, 2]]
    toward /= np.linalg.norm(toward, axis=1, keepdims=True)
    ax, ay = upright(rng, len(p), 0.2, toward, 0.9)
    add(DAISY, p, rng.uniform(0.16, 0.24, len(p)), ax, ay, l)

    # Small flowers, yellow and white, scattered low in the grass.
    p, l = f.sample(9000, 60, near=14, mask=patches(13, 5.0, -0.25))
    p[:, 1] += rng.uniform(0.15, 0.35, len(p))
    ax, ay = upright(rng, len(p), 0.5)
    add(FLOWER, p, rng.uniform(6.0, 9.0, len(p)), ax, ay, l)
    return out
