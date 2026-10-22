# Exports Shishupalgarh_Export.glb (the optimised sculpt from Blender) to
# ruins.bin, the blob the Ruins node script draws on the GPU.
#
#   python3 tools/export_glb.py [Shishupalgarh_Export.glb] [ruins.bin]
#
# The GLB has only the sculpt: pillars, pedestals, plinth, fallen fragments,
# rubble, ground, trunks and vines, with an `_IVY` mask on the stone and
# `_GRASS` / `_PATH` on the ground. Everything green is grown here instead:
# grass and flowers from `_GRASS`, ivy leaf cards from `_IVY`, bushes and
# tree crowns as soft clumps ("puffs"). glTF is already Y-up.
#
# The fallen fragments are the broken pillars' missing tops (Fragment_NN
# belongs on Pillar_NN). Each is exported in its own space with two poses:
# where it lies (ruins) and on top of its pillar (glory).
#
# Format (little-endian):
#   header   'SHRN' | version u32 (3) | section count u32
#   section  32 words: kind, count, indexCount, vbOffset, vbLength, ibOffset,
#            ibLength, flags | bounds min xyz, max xyz (f32), 2 x 0 |
#            ruin position xyz, rotation xyzw | glory position xyz,
#            rotation xyzw | stagger (0-1), 0
# Static meshes (kinds 1-9), 20 bytes a vertex:
#   position f32x3 | normal snorm8x4 | extra unorm8x4
#   extra: wind weight, random, ivy (stone) or path (ground), grass (ground)
#   Kind 9 is a fragment: its vertices are in its own space.
# Templates (kinds 20-24), 28 bytes a vertex, drawn instanced:
#   position f32x3 | normal f32x3 | bend f32 (0 at the root, 1 at the tip)
# Instances (kinds 30-36) in sections per CELL x CELL metre tile, 16 bytes:
#   position f16x3, scale f16 | x axis snorm8x3, random | y axis snorm8x3, w
#   w: grass stretch; for puffs and ivy, 1 when it grows only on the ruins
# Indices are u16.

import json, math, struct, sys
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else 'Shishupalgarh_Export.glb'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'ruins.bin'
OLD = 'ruins.bin'  # the previous blob, for its leaf, grass and flower templates
CELL = 6.0
rng = np.random.default_rng(11)

MATERIAL_KIND = {
    'Stone_Stylized': 1, 'Rock_Stylized': 2, 'Clay_Stylized': 3, 'Ground': 4,
    'Ground_Far': 5, 'Bark': 6, 'Vine_Stem': 7, 'Flame': 8,
}

# ---------------------------------------------------------------------------
# GLB

data = open(SRC, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
bin_off = 20 + jlen + 8
COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def accessor(i):
    a = gltf['accessors'][i]
    v = gltf['bufferViews'][a['bufferView']]
    dt = np.dtype(COMP[a['componentType']])
    n = NCOMP[a['type']]
    start = bin_off + v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', dt.itemsize * n)
    raw = np.frombuffer(data, dtype=np.uint8, count=stride * (a['count'] - 1) + dt.itemsize * n, offset=start)
    out = np.lib.stride_tricks.as_strided(raw, shape=(a['count'], dt.itemsize * n), strides=(stride, 1))
    return np.ascontiguousarray(out).view(dt).reshape(a['count'], n).astype(np.float64 if dt == np.float32 else np.int64)


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])


def node_trs(n):
    t = np.array(n.get('translation', [0, 0, 0]), float)
    q = np.array(n.get('rotation', [0, 0, 0, 1]), float)
    s = np.array(n.get('scale', [1, 1, 1]), float)
    return t, q, s


class Mesh:
    def __init__(self, pos, nrm, idx, attrs, material):
        self.pos, self.nrm, self.idx, self.attrs, self.material = pos, nrm, idx, attrs, material


def node_meshes(n, world=True):
    """The node's primitives, in world space (or its own when world=False)."""
    t, q, s = node_trs(n)
    R = quat_matrix(q)
    out = []
    for p in gltf['meshes'][n['mesh']]['primitives']:
        a = p['attributes']
        pos = accessor(a['POSITION']) * s
        nrm = accessor(a['NORMAL']) / s
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
        if world:
            pos = pos @ R.T + t
            nrm = nrm @ R.T
        idx = accessor(p['indices'])[:, 0] if 'indices' in p else np.arange(len(pos))
        attrs = {k: accessor(v)[:, 0] for k, v in a.items() if k.startswith('_')}
        mat = gltf['materials'][p['material']]['name'] if 'material' in p else 'Stone_Stylized'
        out.append(Mesh(pos, nrm, idx.reshape(-1, 3), attrs, mat))
    return out


nodes = {n['name']: n for n in gltf['nodes']}

# ---------------------------------------------------------------------------
# Packing


def snorm(x):
    return np.clip(np.round(np.asarray(x) * 127), -127, 127).astype(np.int8)


def unorm(x):
    return np.clip(np.round(np.asarray(x) * 255), 0, 255).astype(np.uint8)


PHASES = rng.uniform(0, math.tau, 8)


def patches(p):
    """Smooth 0-1 blotches about a metre across, for breaking up the ivy."""
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    f = (np.sin(x * 1.9 + PHASES[0]) + np.sin(y * 1.3 + PHASES[1]) + np.sin(z * 2.1 + PHASES[2])
         + np.sin((x + y) * 1.1 + PHASES[3]) + np.sin((y - z) * 1.7 + PHASES[4]) + np.sin((x - z) * 2.6 + PHASES[5]))
    return np.clip(f / 6 * 0.5 + 0.5, 0, 1)


def shape_ivy(m):
    """The mask from Blender is high almost everywhere; keep it where ivy
    would be: draping from the top, climbing from the foot, in patches."""
    ivy = m.attrs['_IVY']
    y = m.pos[:, 1]
    rel = (y - y.min()) / max(y.max() - y.min(), 1e-6)
    tall = y.max() - y.min() > 1.0
    drape = np.clip((rel - 0.6) / 0.4, 0, 1) if tall else np.zeros_like(rel)
    climb = np.clip(1 - (y - y.min()) / 1.4, 0, 1)
    patch = patches(m.pos)
    m.attrs['_IVY'] = np.clip(ivy * (0.55 * drape + 0.45 * climb + patch * 0.9 - 0.42) * 1.8, 0, 1)


def static_bytes(m, kind, seed):
    n = len(m.pos)
    v = np.zeros(n, dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('e', 'u1', 4)])
    v['p'] = m.pos
    v['n'][:, :3] = snorm(m.nrm)
    wind = np.zeros(n)
    if kind == 6:  # trunks bend a little with height
        wind = np.clip((m.pos[:, 1] - 0.3) / 5.0, 0, 1) ** 2 * 0.35
    a = m.attrs.get('_IVY', m.attrs.get('_PATH', np.zeros(n)))
    b = m.attrs.get('_GRASS', np.zeros(n))
    v['e'] = np.stack([unorm(wind), np.full(n, unorm(seed)), unorm(a), unorm(b)], 1)
    return v.tobytes()


sections = []  # dicts


def section(kind, count, icount, vb, ib=b'', **extra):
    s = dict(kind=kind, count=count, icount=icount, vb=vb, ib=ib, flags=0,
             lo=(0, 0, 0), hi=(0, 0, 0), ruin=(0, 0, 0, 0, 0, 0, 1), glory=(0, 0, 0, 0, 0, 0, 1), stagger=0)
    s.update(extra)
    sections.append(s)


# ---------------------------------------------------------------------------
# Static meshes, merged per material in chunks under 65536 vertices

merged = []  # [kind, [vb], [ib], verts, tris]
fragments = []
stone_world = []  # (pos, nrm, ivy) of the standing stone, for the ivy cards
pillar_top = {}
for n in gltf['nodes']:
    if 'mesh' not in n:
        continue
    name = n['name']
    if name.startswith('Fragment_'):
        fragments.append(n)
        continue
    for m in node_meshes(n):
        kind = MATERIAL_KIND.get(m.material, 1)
        if '_IVY' in m.attrs:
            shape_ivy(m)
        if name.startswith('Pillar_'):
            pillar_top[name[7:]] = n
        if kind == 1 and '_IVY' in m.attrs:
            stone_world.append((m.pos, m.nrm, m.attrs['_IVY'], m.idx))
        vb = static_bytes(m, kind, rng.random())
        nv = len(m.pos)
        assert nv < 65536, name
        cur = next((c for c in merged if c[0] == kind and c[3] + nv < 65536), None)
        if cur is None:
            cur = [kind, [], [], 0, 0]
            merged.append(cur)
        cur[1].append(vb)
        cur[2].append((m.idx + cur[3]).astype('<u2').tobytes())
        cur[3] += nv
        cur[4] += len(m.idx)
for kind, vbs, ibs, nv, nt in merged:
    section(kind, nv, nt * 3, b''.join(vbs), b''.join(ibs))
    print(f'static kind {kind}: verts={nv} tris={nt}')

# ---------------------------------------------------------------------------
# Fragments: lying in the grass (ruins) and back on their pillars (glory)

order = sorted(fragments, key=lambda f: nodes['Pillar_' + f['name'][9:]]['translation'][0])
for i, f in enumerate(order):
    num = f['name'][9:]
    pillar = nodes['Pillar_' + num]
    (m,) = node_meshes(f, world=False)
    shape_ivy(m)
    t, q, _ = node_trs(f)
    pt, pq, ps = node_trs(pillar)
    pm = node_meshes(pillar, world=False)[0]
    top = pm.pos[:, 1].max() * ps[1]
    # Its long axis is local Y; stand it on the break, on the pillar's axis.
    lift = -m.pos[:, 1].min()
    gpos = pt + quat_matrix(pq) @ np.array([0, top + lift - 0.02, 0])
    vb = static_bytes(m, 9, rng.random())
    lo, hi = m.pos.min(0), m.pos.max(0)
    section(9, len(m.pos), len(m.idx) * 3, vb, m.idx.astype('<u2').tobytes(), flags=int(num),
            lo=tuple(lo), hi=tuple(hi), ruin=(*t, *q), glory=(*gpos, *pq),
            stagger=i / max(len(order) - 1, 1))
    print(f'fragment {num}: lies at {np.round(t, 2)}, goes to {np.round(gpos, 2)}')

# ---------------------------------------------------------------------------
# Templates: the leaf, grass and flower from the previous blob, and a puff

old = open(OLD, 'rb').read()
ver = struct.unpack_from('<I', old, 4)[0]
entry = {1: 32, 2: 64, 3: 128}[ver]
for i in range(struct.unpack_from('<I', old, 8)[0]):
    k, c, ic, vo, vl, io, il, _ = struct.unpack_from('<8I', old, 12 + i * entry)
    if 20 <= k < 24:
        section(k, c, ic, old[vo:vo + vl], old[io:io + il])
        print(f'template {k}: verts={c}')


def icosphere(sub):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    v = [np.array(p) / np.linalg.norm(p) for p in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    for _ in range(sub):
        cache = {}

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                p = v[a] + v[b]
                v.append(p / np.linalg.norm(p))
                cache[key] = len(v) - 1
            return cache[key]

        nf = []
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return np.array(v), np.array(f)


pv, pf = icosphere(2)
# A little lumpy, and flattened underneath.
lump = 1 + 0.12 * np.sin(pv[:, 0] * 5.1 + 1) * np.sin(pv[:, 1] * 4.3) * np.sin(pv[:, 2] * 4.7 + 2)
pp = pv * lump[:, None]
pp[:, 1] = np.where(pp[:, 1] < 0, pp[:, 1] * 0.55, pp[:, 1])
tv = np.zeros(len(pp), dtype=[('p', '<f4', 3), ('n', '<f4', 3), ('b', '<f4')])
tv['p'], tv['n'], tv['b'] = pp, pv, (pp[:, 1] + 0.55) / 1.55
section(24, len(pp), len(pf) * 3, tv.tobytes(), pf.astype('<u2').tobytes())
print(f'template 24 (puff): verts={len(pp)} tris={len(pf)}')

# ---------------------------------------------------------------------------
# Instances

ground = next(m for m in node_meshes(nodes['Ground']))
gp = ground.pos
PLINTH = (12.75, 5.05)  # half extents of the plinth, which no grass grows through


def on_plinth(x, z, margin=0.0):
    return (np.abs(x) < PLINTH[0] + margin) & (np.abs(z) < PLINTH[1] + margin)


# Ground height by inverse-distance weighting of the nearest ground vertices.
cell_index = {}
for i, (x, z) in enumerate(gp[:, [0, 2]]):
    cell_index.setdefault((int(math.floor(x)), int(math.floor(z))), []).append(i)


def ground_y(x, z):
    ids = []
    cx, cz = int(math.floor(x)), int(math.floor(z))
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            ids += cell_index.get((cx + dx, cz + dz), [])
    if not ids:
        return 0.0
    p = gp[ids]
    d = np.hypot(p[:, 0] - x, p[:, 2] - z) + 1e-3
    w = 1 / d ** 2
    return float((p[:, 1] * w).sum() / w.sum())


def sample_ground(count, weight):
    """Points on the ground, area- and `weight`-weighted (per triangle)."""
    tri = ground.idx
    a, b, c = gp[tri[:, 0]], gp[tri[:, 1]], gp[tri[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    w = area * weight(tri)
    pick = rng.choice(len(tri), size=count, p=w / w.sum())
    r1, r2 = rng.random(count), rng.random(count)
    s = np.sqrt(r1)
    pts = a[pick] * (1 - s)[:, None] + b[pick] * (s * (1 - r2))[:, None] + c[pick] * (s * r2)[:, None]
    return pts


cells = {}


def add(kind, pos, ax, ay, scale, rand, w):
    for p, x, y, s, r, ww in zip(pos, ax, ay, scale, rand, w):
        key = (kind, math.floor(p[0] / CELL), math.floor(p[2] / CELL))
        c = cells.setdefault(key, [[], np.full(3, 1e9), np.full(3, -1e9)])
        c[0].append(struct.pack('<4e4b4b', p[0], p[1], p[2], s, *snorm(x), snorm(r * 2 - 1), *snorm(y), snorm(ww * 2 - 1)))
        c[1] = np.minimum(c[1], p)
        c[2] = np.maximum(c[2], p + np.array([0, s * 0.5, 0]))


def yaw_axes(n, tilt=0.0):
    a = rng.random(n) * math.tau
    ax = np.stack([np.cos(a), np.zeros(n), np.sin(a)], 1)
    up = np.stack([rng.normal(0, tilt, n), np.ones(n), rng.normal(0, tilt, n)], 1)
    up -= ax * (up * ax).sum(1, keepdims=True)
    return ax, up / np.linalg.norm(up, axis=1, keepdims=True)


grass_attr = ground.attrs.get('_GRASS', np.ones(len(gp)))
path_attr = ground.attrs.get('_PATH', np.zeros(len(gp)))


def meadow(tri, power=1.0):
    g = grass_attr[tri].mean(1) * (1 - path_attr[tri].mean(1)) ** 2
    cx, cz = gp[tri, 0].mean(1), gp[tri, 2].mean(1)
    return np.clip(g, 0, 1) ** power * ~on_plinth(cx, cz, 0.1)


# Grass (template 22): dense over the meadow, none on the plinth or path.
pts = sample_ground(46000, meadow)
ax, ay = yaw_axes(len(pts), 0.12)
add(33, pts - [0, 0.02, 0], ax, ay, rng.uniform(0.55, 1.05, len(pts)), rng.random(len(pts)), rng.uniform(0.4, 0.6, len(pts)))

# Meadow flowers (template 23): in drifts, held up on the grass.
pts = sample_ground(16000, lambda tri: meadow(tri, 2.0))
keep = np.sin(pts[:, 0] * 0.55 + 1.3) * np.sin(pts[:, 2] * 0.47) + rng.random(len(pts)) * 0.9 > 0.55
pts = pts[keep]
ax, ay = yaw_axes(len(pts), 0.25)
pts[:, 1] += rng.uniform(0.12, 0.34, len(pts))
add(34, pts, ax, ay, rng.uniform(1.6, 2.4, len(pts)), rng.random(len(pts)), np.zeros(len(pts)))

# Bushes (puffs): along the foot of the plinth, scattered over the meadow,
# and a few growing on the ruined plinth itself (these go in glory).
seeds = []
for _ in range(70):  # around the plinth
    side = rng.integers(4)
    u = rng.uniform(-1, 1)
    off = rng.uniform(0.35, 1.3)
    if side < 2:
        x, z = u * (PLINTH[0] + 0.5), (PLINTH[1] + off) * (1 if side == 0 else -1)
    else:
        x, z = (PLINTH[0] + off) * (1 if side == 2 else -1), u * (PLINTH[1] + 0.5)
    if side == 0 and abs(x) < 2.2:  # keep the steps clear
        continue
    seeds.append((x, z, rng.uniform(0.45, 0.85), 0))
for p in sample_ground(140, lambda tri: meadow(tri, 3.0)):  # the meadow
    if np.hypot(p[0], p[2]) > 8 and not on_plinth(p[0], p[2], 1.2):
        seeds.append((p[0], p[2], rng.uniform(0.4, 0.95), 0))
for _ in range(16):  # on the plinth, between the pillars
    x, z = rng.uniform(-12, 12), rng.choice([-1, 1]) * rng.uniform(0.5, 4.6)
    seeds.append((x, z, rng.uniform(0.3, 0.55), 1))
bpos, bscale, bw = [], [], []
for x, z, r, ruin in seeds:
    y = 0.4 if on_plinth(x, z) else ground_y(x, z)
    for k in range(rng.integers(3, 6)):
        a = rng.random() * math.tau
        d = r * rng.uniform(0.1, 0.8)
        s = r * rng.uniform(0.55, 0.85)
        bpos.append((x + math.cos(a) * d, y + s * 0.35 + rng.uniform(0, r * 0.5), z + math.sin(a) * d))
        bscale.append(s)
        bw.append(ruin)
bpos = np.array(bpos)
ax, ay = yaw_axes(len(bpos), 0.0)
add(30, bpos, ax, ay, np.array(bscale), rng.random(len(bpos)), np.array(bw, float))
print(f'bushes: {len(seeds)} ({len(bpos)} puffs)')

# Tree crowns (puffs): where the trunks' branches end.
tr = node_meshes(nodes['Trunks'])[0].pos
high = tr[tr[:, 1] > 2.6]
crowns = {}
for p in high:
    crowns.setdefault((round(p[0] / 1.4), round(p[2] / 1.4)), []).append(p)
cpos, cscale = [], []
for pts_ in crowns.values():
    c = np.array(pts_)
    top = c[c[:, 1].argmax()]
    for k in range(rng.integers(2, 4)):
        s = rng.uniform(0.75, 1.15)
        cpos.append(top + [rng.normal(0, 0.45), rng.uniform(0.1, 0.6), rng.normal(0, 0.45)])
        cscale.append(s)
cpos = np.array(cpos)
ax, ay = yaw_axes(len(cpos), 0.0)
add(32, cpos, ax, ay, np.array(cscale), rng.random(len(cpos)), np.zeros(len(cpos)))
print(f'tree crowns: {len(crowns)} ({len(cpos)} puffs)')

# Ivy leaf cards (template 21) where the stone's _IVY mask is high,
# hanging down the faces; density follows the mask.
P = np.concatenate([s[0] for s in stone_world])
N = np.concatenate([s[1] for s in stone_world])
I = np.concatenate([s[2] for s in stone_world])
w = np.clip(I - 0.25, 0, None) ** 1.5
pick = rng.choice(len(P), size=7000, p=w / w.sum())
p = P[pick] + N[pick] * 0.025 + rng.normal(0, 0.05, (len(pick), 3))
nrm = N[pick] + rng.normal(0, 0.35, (len(pick), 3))
nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
down = np.array([0, -1, 0]) + rng.normal(0, 0.6, (len(pick), 3))
tip = down - nrm * (down * nrm).sum(1, keepdims=True)
tip /= np.linalg.norm(tip, axis=1, keepdims=True) + 1e-9
az = -tip
ax = np.cross(nrm, az)
ax /= np.linalg.norm(ax, axis=1, keepdims=True) + 1e-9
add(31, p, ax, nrm, rng.uniform(2.2, 3.4, len(pick)), rng.random(len(pick)), np.ones(len(pick)))


def puff_leaves(kind, centres, scales, ruin, per_area):
    """Leaf cards over the clumps' surfaces (more on top), so their
    silhouettes are leafy; the clump itself is the shadowed core."""
    pos, ax_, ay_, sc, ww = [], [], [], [], []
    for c, r, w in zip(centres, scales, ruin):
        n = int(per_area * r * r) + 4
        d = rng.normal(0, 1, (n, 3))
        d[:, 1] = np.abs(d[:, 1]) * 1.2 + d[:, 1] * 0.4
        d /= np.linalg.norm(d, axis=1, keepdims=True)
        pos.append(c + d * r * rng.uniform(0.85, 1.05, (n, 1)))
        # Leaves face out, tips pointing away from the clump and a little down.
        tip = d + np.array([0, -0.6, 0]) + rng.normal(0, 0.5, (n, 3))
        up = d + rng.normal(0, 0.45, (n, 3))
        up /= np.linalg.norm(up, axis=1, keepdims=True)
        tip -= up * (tip * up).sum(1, keepdims=True)
        tip /= np.linalg.norm(tip, axis=1, keepdims=True) + 1e-9
        x = np.cross(up, -tip)
        x /= np.linalg.norm(x, axis=1, keepdims=True) + 1e-9
        ax_.append(x)
        ay_.append(up)
        sc.append(rng.uniform(2.6, 3.6, n) * (0.8 + 0.4 * r))
        ww.append(np.full(n, w))
    pos, ax_, ay_ = np.concatenate(pos), np.concatenate(ax_), np.concatenate(ay_)
    add(kind, pos, ax_, ay_, np.concatenate(sc), rng.random(len(pos)), np.concatenate(ww))
    return len(pos)


print('bush leaves', puff_leaves(35, bpos, bscale, bw, 70))
print('crown leaves', puff_leaves(36, cpos, cscale, np.zeros(len(cpos)), 70))

TEMPLATE = {30: 24, 31: 21, 32: 24, 33: 22, 34: 23, 35: 20, 36: 20}
totals = {}
for (kind, _, _), (rows, lo, hi) in sorted(cells.items()):
    section(kind, len(rows), TEMPLATE[kind], b''.join(rows), lo=tuple(lo), hi=tuple(hi))
    totals[kind] = totals.get(kind, 0) + len(rows)
print('instances', totals)

# ---------------------------------------------------------------------------
# Write

head = 12 + 128 * len(sections)
blob = bytearray()
table = bytearray()
for s in sections:
    vbo = head + len(blob)
    blob += s['vb']
    blob += b'\0' * (-len(blob) % 4)
    ibo = head + len(blob)
    blob += s['ib']
    blob += b'\0' * (-len(blob) % 4)
    table += struct.pack('<8I', s['kind'], s['count'], s['icount'], vbo, len(s['vb']), ibo, len(s['ib']), s['flags'])
    table += struct.pack('<8f', *s['lo'], *s['hi'], 0, 0)
    table += struct.pack('<16f', *s['ruin'], *s['glory'], s['stagger'], 0)
with open(OUT, 'wb') as f:
    f.write(b'SHRN' + struct.pack('<2I', 3, len(sections)) + table + blob)
print(f'wrote {OUT}: {(head + len(blob)) / 1e6:.2f} MB, {len(sections)} sections')
