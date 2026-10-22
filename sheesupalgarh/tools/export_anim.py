# Exports Shishupalgarh_RuinsToGlory.glb (the sculpt and its 10 s
# RuinsToGlory animation, from Blender) to ruins.bin for the Ruins node script.
#
#   python3 tools/export_anim.py
#
# The animated GLB has no materials or custom attributes, so materials come
# from object names, and `_IVY`, `_GRASS` and `_PATH` are carried over from
# Shishupalgarh_Export.glb (the same layout) by nearest point. glTF is Y-up.
#
# Every object the animation moves or morphs is its own draw: its vertices in
# its own space, its shape key ("Restored" on the pillars, "Gone" on the ivy,
# bushes and vines) as per-vertex deltas, and its track baked over the window
# in which it changes. Everything else is merged per material in world space.
# Grass, flowers, ivy leaf cards, leaves on the bushes and the tree crowns are
# grown here.
#
# Format (little-endian):
#   header   'SHRN' | version u32 (4) | section count u32
#   section  48 words:
#     0  kind      1-8 merged static (= material), 20-24 templates,
#                  30-36 instances, 40 an object
#     1  count     vertices, or instances
#     2  icount    indices, or for instances the template's kind
#     3-6          vbOffset, vbLength, ibOffset, ibLength
#     7  material  (objects)
#     8-13         bounds min xyz, max xyz (f32; instance tiles)
#     14-15        morph offset, length (objects with a shape key)
#     16-19        track offset, samples, t0, t1 (f32 seconds)
#     20-23        shape key weight offset, samples, t0, t1
#     24-33        rest pose: position xyz, rotation xyzw, scale xyz (f32)
#     34   glows   1 for objects that glow as they are restored (pillars,
#                  fragments)
#   track sample   position xyz, rotation xyzw, scale xyz (10 x f32)
#   weight sample  f32
# Static and object vertices, 20 bytes:
#   position f32x3 | normal snorm8x4 | extra unorm8x4
#   extra: wind weight, random, ivy (stone) or path (ground), grass (ground)
# Morph deltas, 16 bytes: position f32x3 | normal snorm8x4
# Templates, 28 bytes: position f32x3 | normal f32x3 | bend f32
# Instances, 16 bytes:
#   position f16x3, scale f16 | x axis snorm8x3, random | y axis snorm8x3, w
#   w: grass stretch; for ruin-only growth, 1 (it withers at glory = random)
# Kinds: 30 bush clumps, 31 ivy cards, 32 tree crowns, 33 grass, 34 pink
# flowers, 35 bush leaves, 36 crown leaves, 37 sunflowers, 38 daisies.
# Indices are u16.

import json, math, struct
import numpy as np

SRC = 'Shishupalgarh_RuinsToGlory.glb'
ATTRS = 'Shishupalgarh_Export.glb'
OUT = 'ruins.bin'
TEMPLATES_FROM = 'ruins.bin'  # leaf, grass and flower templates (kinds 20-23)
DURATION = 10.0
CELL = 6.0
rng = np.random.default_rng(11)

STONE, ROCK, CLAY, GROUND, GROUND_FAR, BARK, VINE, FLAME = 1, 2, 3, 4, 5, 6, 7, 8
IVY_MESH, BUSH_MESH, THATCH, WOOD = 17, 18, 19, 20
FLOOR, PILLAR = 23, 24


def material_for(name):
    n = name.replace('_RA', '')
    for prefix, m in (('Ground_Far', GROUND_FAR), ('Ground', GROUND), ('Trunks', BARK), ('Vines', VINE),
                      ('Diya', CLAY), ('Flame', FLAME), ('Ivy', IVY_MESH), ('Bush', BUSH_MESH),
                      ('Thatch', THATCH), ('Roof', WOOD), ('Glory_Floor', FLOOR), ('Pillar', PILLAR)):
        if n.startswith(prefix):
            return m
    return STONE


# ---------------------------------------------------------------------------
# GLB reading


class GLB:
    def __init__(self, path):
        self.data = open(path, 'rb').read()
        jlen = struct.unpack_from('<I', self.data, 12)[0]
        self.json = json.loads(self.data[20:20 + jlen])
        self.bin = 20 + jlen + 8
        self.nodes = {n['name']: n for n in self.json['nodes']}

    def accessor(self, i):
        g = self.json
        a = g['accessors'][i]
        v = g['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        dt = np.dtype({5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1', 5122: '<i2', 5120: 'i1'}[a['componentType']])
        start = self.bin + v.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = v.get('byteStride', dt.itemsize * n)
        rows = [np.frombuffer(self.data, dtype=dt, count=n, offset=start + k * stride) for k in range(a['count'])] \
            if stride != dt.itemsize * n else None
        arr = np.array(rows) if rows is not None else np.frombuffer(self.data, dtype=dt, count=a['count'] * n, offset=start).reshape(-1, n)
        arr = arr.astype(np.float64)
        if a.get('normalized'):
            arr /= {5121: 255, 5123: 65535, 5120: 127, 5122: 32767}[a['componentType']]
        return arr

    def mesh(self, node):
        (p,) = self.json['meshes'][node['mesh']]['primitives']
        a = p['attributes']
        pos = self.accessor(a['POSITION'])
        nrm = self.accessor(a['NORMAL'])
        idx = self.accessor(p['indices'])[:, 0].astype(np.int64).reshape(-1, 3)
        attrs = {k: self.accessor(v)[:, 0] for k, v in a.items() if k.startswith('_')}
        morph = None
        if 'targets' in p:
            t = p['targets'][0]
            dp = self.accessor(t['POSITION'])
            dn = self.accessor(t['NORMAL']) if 'NORMAL' in t else np.zeros_like(dp)
            morph = (dp, dn)
        return pos, nrm, idx, attrs, morph


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])


def trs(n):
    return (np.array(n.get('translation', [0, 0, 0]), float), np.array(n.get('rotation', [0, 0, 0, 1]), float),
            np.array(n.get('scale', [1, 1, 1]), float))


def to_world(pos, nrm, n):
    t, q, s = trs(n)
    R = quat_matrix(q)
    nn = (nrm / np.where(s == 0, 1, s)) @ R.T
    nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-12
    return (pos * s) @ R.T + t, nn


src = GLB(SRC)
ref = GLB(ATTRS)

# ---------------------------------------------------------------------------
# Attributes carried over from the export GLB, by nearest point


def nearest(src_pos, dst_pos):
    """Index into src_pos of the nearest point to each of dst_pos."""
    try:
        from scipy.spatial import cKDTree
        return cKDTree(src_pos).query(dst_pos)[1]
    except ImportError:
        sp = src_pos.astype(np.float32)
        out = np.empty(len(dst_pos), dtype=np.int64)
        for i in range(0, len(dst_pos), 64):
            d = ((dst_pos[i:i + 64, None, :].astype(np.float32) - sp[None, :, :]) ** 2).sum(2)
            out[i:i + 64] = d.argmin(1)
        return out


ref_ivy_pos, ref_ivy = [], []
for n in ref.json['nodes']:
    if 'mesh' in n:
        pos, nrm, idx, attrs, _ = ref.mesh(n)
        if '_IVY' in attrs:
            wp, _ = to_world(pos, nrm, n)
            ref_ivy_pos.append(wp)
            ref_ivy.append(attrs['_IVY'])
ref_ivy_pos = np.concatenate(ref_ivy_pos)
ref_ivy = np.concatenate(ref_ivy)
rg_pos, rg_nrm, _, rg_attrs, _ = ref.mesh(ref.nodes['Ground'])

PHASES = rng.uniform(0, math.tau, 8)


def patches(p):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    f = (np.sin(x * 1.9 + PHASES[0]) + np.sin(y * 1.3 + PHASES[1]) + np.sin(z * 2.1 + PHASES[2])
         + np.sin((x + y) * 1.1 + PHASES[3]) + np.sin((y - z) * 1.7 + PHASES[4]) + np.sin((x - z) * 2.6 + PHASES[5]))
    return np.clip(f / 6 * 0.5 + 0.5, 0, 1)


def ivy_for(world_pos):
    """The export's ivy mask at these points, shaped: draping from the tops,
    climbing from the foot, in patches (the raw mask is high everywhere)."""
    near = nearest(ref_ivy_pos, world_pos)
    ivy = ref_ivy[near]
    y = world_pos[:, 1]
    rel = (y - y.min()) / max(y.max() - y.min(), 1e-6)
    tall = y.max() - y.min() > 1.0
    drape = np.clip((rel - 0.6) / 0.4, 0, 1) if tall else np.zeros_like(rel)
    climb = np.clip(1 - (y - y.min()) / 1.4, 0, 1)
    return np.clip(ivy * (0.55 * drape + 0.45 * climb + patches(world_pos) * 0.9 - 0.42) * 1.8, 0, 1)


# ---------------------------------------------------------------------------
# Packing


def snorm(x):
    return np.clip(np.round(np.asarray(x) * 127), -127, 127).astype(np.int8)


def unorm(x):
    return np.clip(np.round(np.asarray(x) * 255), 0, 255).astype(np.uint8)


def vertex_bytes(pos, nrm, wind, seed, a, b):
    v = np.zeros(len(pos), dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('e', 'u1', 4)])
    v['p'] = pos
    v['n'][:, :3] = snorm(nrm)
    v['e'] = np.stack([unorm(wind), np.full(len(pos), unorm(seed)), unorm(a), unorm(b)], 1)
    return v.tobytes()


def morph_bytes(dp, dn):
    v = np.zeros(len(dp), dtype=[('p', '<f4', 3), ('n', 'i1', 4)])
    v['p'] = dp
    v['n'][:, :3] = snorm(np.clip(dn, -1, 1))
    return v.tobytes()


def raised_floor(pos):
    """The glory floor as a raised slab: its top 0.2 m higher, with a
    small overhanging lip and stone sides down into the ground (it rises
    with the floor's track). Same extent and space as the original quad."""
    top = pos[:, 1].max() + 0.2
    ex, ez = np.abs(pos[:, 0]).max(), np.abs(pos[:, 2]).max()
    lip, lip_h, bottom = 0.08, 0.07, top - 1.0
    verts, norms, tris = [], [], []

    def quad(a, b, c, d, n):
        i = len(verts)
        verts.extend([a, b, c, d])
        norms.extend([n] * 4)
        tris.extend([(i, i + 1, i + 2), (i, i + 2, i + 3)])

    X, Z = ex + lip, ez + lip
    quad((-X, top, -Z), (-X, top, Z), (X, top, Z), (X, top, -Z), (0, 1, 0))
    for sx, sz, n in ((1, 0, (1, 0, 0)), (-1, 0, (-1, 0, 0)), (0, 1, (0, 0, 1)), (0, -1, (0, 0, -1))):
        for (hx, hz, y0, y1) in ((X, Z, top - lip_h, top), (ex, ez, bottom, top - lip_h)):
            if sx:
                x = sx * hx
                a, b = (x, y0, -hz * sx), (x, y0, hz * sx)
                c, d = (x, y1, hz * sx), (x, y1, -hz * sx)
            else:
                z = sz * hz
                a, b = (hx * sz, y0, z), (-hx * sz, y0, z)
                c, d = (-hx * sz, y1, z), (hx * sz, y1, z)
            quad(a, b, c, d, n)
        # Under the lip.
        if sx:
            quad((sx * ex, top - lip_h, -Z * sx), (sx * ex, top - lip_h, Z * sx), (sx * X, top - lip_h, Z * sx),
                 (sx * X, top - lip_h, -Z * sx), (0, -1, 0))
        else:
            quad((X * sz, top - lip_h, sz * ez), (-X * sz, top - lip_h, sz * ez), (-X * sz, top - lip_h, sz * Z),
                 (X * sz, top - lip_h, sz * Z), (0, -1, 0))
    pos2, nrm2 = np.array(verts, float), np.array(norms, float)
    idx2 = np.array(tris)
    # Wind each triangle so its face agrees with its normal.
    for t in idx2:
        a, b, c = pos2[t]
        if np.dot(np.cross(b - a, c - a), nrm2[t[0]]) < 0:
            t[1], t[2] = t[2], t[1]
    return pos2, nrm2, idx2


def wind_for(material, y, ymin):
    if material == BARK:
        return np.clip((y - 0.3) / 5.0, 0, 1) ** 2 * 0.35
    if material == BUSH_MESH:
        return np.clip((y - ymin) / 1.2, 0, 1) * 0.12
    if material == IVY_MESH:
        return np.full(len(y), 0.05)
    return np.zeros(len(y))


sections = []


def section(kind, count, icount, vb=b'', ib=b'', **kw):
    s = dict(kind=kind, count=count, icount=icount, vb=vb, ib=ib, material=0, lo=(0, 0, 0), hi=(0, 0, 0),
             morph=b'', track=b'', track_n=0, t0=0, t1=0, weights=b'', w_n=0, w0=0, w1=0,
             rest=(0, 0, 0, 0, 0, 0, 1, 1, 1, 1), glows=0)
    s.update(kw)
    sections.append(s)


# ---------------------------------------------------------------------------
# The animation: per node, its tracks and its shape key weight

anim = src.json['animations'][0]
tracks = {}  # node index -> {path: (times, values)}
for c in anim['channels']:
    smp = anim['samplers'][c['sampler']]
    t = src.accessor(smp['input'])[:, 0]
    v = src.accessor(smp['output'])
    tracks.setdefault(c['target']['node'], {})[c['target']['path']] = (t, v.reshape(len(t), -1))


def window(t, v):
    """First and last key of the span in which the values change."""
    ch = np.abs(np.diff(v, axis=0)).sum(1) > 1e-6
    if not ch.any():
        return None
    return int(np.argmax(ch)), int(len(ch) - np.argmax(ch[::-1]))


def bake_track(node_index, node):
    tr = tracks.get(node_index, {})
    t0, t1 = None, None
    for path in ('translation', 'rotation', 'scale'):
        if path in tr:
            w = window(*tr[path])
            if w:
                t0 = w[0] if t0 is None else min(t0, w[0])
                t1 = w[1] if t1 is None else max(t1, w[1])
    if t0 is None:
        return b'', 0, 0.0, 0.0
    rest_t, rest_q, rest_s = trs(node)
    times = next(iter(tr.values()))[0]
    rows = []
    for k in range(t0, t1 + 1):
        p = tr['translation'][1][k] if 'translation' in tr else rest_t
        q = tr['rotation'][1][k] if 'rotation' in tr else rest_q
        s = tr['scale'][1][k] if 'scale' in tr else rest_s
        rows.append(struct.pack('<10f', *p, *q, *s))
    return b''.join(rows), t1 - t0 + 1, float(times[t0]), float(times[t1])


def bake_weights(node_index):
    tr = tracks.get(node_index, {})
    if 'weights' not in tr:
        return b'', 0, 0.0, 0.0
    t, v = tr['weights']
    w = window(t, v)
    if not w:
        return b'', 0, 0.0, 0.0
    vals = v[w[0]:w[1] + 1, 0]
    return struct.pack(f'<{len(vals)}f', *vals), len(vals), float(t[w[0]]), float(t[w[1]])


# ---------------------------------------------------------------------------
# Static meshes and objects

merged = []
stone_world = []  # standing stone in ruin, for the ivy leaf cards
bush_world = []  # (positions, normals, wither glory or None) for leaves on bushes
for ni, n in enumerate(src.json['nodes']):
    if 'mesh' not in n:
        continue
    name = n['name']
    if name.startswith('Ivy_'):
        # The ivy is the leaf cards grown below (they wither over the same
        # 0-4.5 s as these meshes' "Gone" key); these caps are left out.
        rng.random()  # (keep the random sequence, and so the bushes, as it was)
        continue
    mat = material_for(name)
    pos, nrm, idx, attrs, morph = src.mesh(n)
    if mat == FLOOR:
        pos, nrm, idx = raised_floor(pos)
        attrs, morph = {}, None
    wpos, wnrm = to_world(pos, nrm, n)
    track = bake_track(ni, n)
    weights = bake_weights(ni)
    seed = rng.random()
    a = np.zeros(len(pos))
    b = np.zeros(len(pos))
    if mat in (STONE, PILLAR) and not name.startswith(('Glory', 'Stair', 'Rubble')):
        # Overgrown where it stood in ruin (fragments: where they lie).
        a = ivy_for(wpos)
        if not track[1] and not weights[1] or name.startswith('Pillar'):
            stone_world.append((wpos, wnrm, a))
    if mat == GROUND:
        near = nearest(rg_pos, wpos)
        a = rg_attrs.get('_PATH', np.zeros(len(rg_pos)))[near]
        b = rg_attrs.get('_GRASS', np.ones(len(rg_pos)))[near]
        ground_pos, ground_idx, ground_grass, ground_path = wpos, idx, b, a
    if mat == BARK:
        trunks = wpos
    if mat == BUSH_MESH:
        wither = None
        if weights[1]:
            wither = (weights[2] + weights[3]) / 2 / DURATION
        bush_world.append((wpos, wnrm, idx, wither))
    wind = wind_for(mat, wpos[:, 1], wpos[:, 1].min())
    if track[1] or weights[1]:
        # An object: in its own space, posed by its track.
        t, q, s = trs(n)
        section(40, len(pos), idx.size, vertex_bytes(pos, nrm, wind, seed, a, b), idx.astype('<u2').tobytes(),
                material=mat, morph=morph_bytes(*morph) if morph and weights[1] else b'',
                track=track[0], track_n=track[1], t0=track[2], t1=track[3],
                weights=weights[0], w_n=weights[1], w0=weights[2], w1=weights[3],
                rest=(*t, *q, *s), glows=1 if name.startswith(('Pillar', 'Fragment')) else 0)
        continue
    vb = vertex_bytes(wpos, wnrm, wind, seed, a, b)
    cur = next((c for c in merged if c[0] == mat and c[3] + len(pos) < 65536), None)
    if cur is None:
        cur = [mat, [], [], 0, 0]
        merged.append(cur)
    cur[1].append(vb)
    cur[2].append((idx + cur[3]).astype('<u2').tobytes())
    cur[3] += len(pos)
    cur[4] += len(idx)
for mat, vbs, ibs, nv, nt in merged:
    section(mat, nv, nt * 3, b''.join(vbs), b''.join(ibs))
objects = [s for s in sections if s['kind'] == 40]
print(f'static: {len(merged)} chunks; objects: {len(objects)} '
      f'({sum(1 for s in objects if s["morph"])} with shape keys, {sum(1 for s in objects if s["track_n"])} moving)')

# ---------------------------------------------------------------------------
# Templates: leaf, grass and flower from the previous blob, and the puff

old = open(TEMPLATES_FROM, 'rb').read()
ver = struct.unpack_from('<I', old, 4)[0]
entry = {1: 32, 2: 64, 3: 128, 4: 192}[ver]
for i in range(struct.unpack_from('<I', old, 8)[0]):
    k, c, ic, vo, vl, io, il = struct.unpack_from('<7I', old, 12 + i * entry)
    if 20 <= k < 24:
        section(k, c, ic, old[vo:vo + vl], old[io:io + il])


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
lump = 1 + 0.12 * np.sin(pv[:, 0] * 5.1 + 1) * np.sin(pv[:, 1] * 4.3) * np.sin(pv[:, 2] * 4.7 + 2)
pp = pv * lump[:, None]
pp[:, 1] = np.where(pp[:, 1] < 0, pp[:, 1] * 0.55, pp[:, 1])
tv = np.zeros(len(pp), dtype=[('p', '<f4', 3), ('n', '<f4', 3), ('b', '<f4')])
tv['p'], tv['n'], tv['b'] = pp, pv, (pp[:, 1] + 0.55) / 1.55
section(24, len(pp), len(pf) * 3, tv.tobytes(), pf.astype('<u2').tobytes())



def blossom():
    """A small flower facing up: a crossed-quad stem, a centre disc and 12
    petals, cupped a little. Head radius 0.5, stem 3 tall. bend is the
    distance from the centre (0 to 1; the centre is under 0.25) on the head,
    and below 0 on the stem, so the shader can colour each part."""
    H, R = 3.0, 0.5
    verts, tris = [], []

    def v(p, n, b):
        verts.append((*p, *n, b))
        return len(verts) - 1

    for a in (0, math.pi / 2):  # stem
        dx, dz = math.cos(a) * 0.025, math.sin(a) * 0.025
        n = (-math.sin(a), 0, math.cos(a))
        q = [v((-dx, 0, -dz), n, -1), v((dx, 0, dz), n, -1), v((dx, H, dz), n, -0.05), v((-dx, H, -dz), n, -0.05)]
        tris += [(q[0], q[1], q[2]), (q[0], q[2], q[3])]
    up = (0, 1, 0)
    c = v((0, H + 0.04, 0), up, 0)  # centre disc, domed
    ring = []
    for k in range(10):
        a = k / 10 * math.tau
        ring.append(v((math.cos(a) * R * 0.24, H + 0.01, math.sin(a) * R * 0.24), up, 0.22))
    for k in range(10):
        tris.append((c, ring[(k + 1) % 10], ring[k]))
    for k in range(12):  # petals
        a = (k + 0.5) / 12 * math.tau
        w = math.tau / 12 * 0.42
        r0, r1 = R * 0.22, R
        cup = 0.12
        p0 = v((math.cos(a - w) * r0, H, math.sin(a - w) * r0), up, 0.3)
        p1 = v((math.cos(a + w) * r0, H, math.sin(a + w) * r0), up, 0.3)
        pm0 = v((math.cos(a - w * 1.15) * r1 * 0.6, H + cup * 0.5, math.sin(a - w * 1.15) * r1 * 0.6), up, 0.65)
        pm1 = v((math.cos(a + w * 1.15) * r1 * 0.6, H + cup * 0.5, math.sin(a + w * 1.15) * r1 * 0.6), up, 0.65)
        tip = v((math.cos(a) * r1, H + cup, math.sin(a) * r1), up, 1.0)
        tris += [(p0, p1, pm1), (p0, pm1, pm0), (pm0, pm1, tip)]
    vb = struct.pack(f'<{len(verts) * 7}f', *[x for vv in verts for x in vv])
    ib = struct.pack(f'<{len(tris) * 3}H', *[i for t in tris for i in t])
    return vb, ib, len(verts), len(tris)


bvb, bib, bnv, bnt = blossom()
section(25, bnv, bnt * 3, bvb, bib)

# ---------------------------------------------------------------------------
# Grown: grass, flowers, ivy cards, leaves on the bushes, tree crowns

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


def sample_ground(count, weight):
    tri = ground_idx
    a, b, c = ground_pos[tri[:, 0]], ground_pos[tri[:, 1]], ground_pos[tri[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    w = area * weight(tri)
    pick = rng.choice(len(tri), size=count, p=w / w.sum())
    r1, r2 = rng.random(count), rng.random(count)
    s = np.sqrt(r1)
    return a[pick] * (1 - s)[:, None] + b[pick] * (s * (1 - r2))[:, None] + c[pick] * (s * r2)[:, None]


def meadow(tri, power=1.0):
    g = ground_grass[tri].mean(1) * (1 - ground_path[tri].mean(1)) ** 2
    return np.clip(g, 0, 1) ** power + 1e-4


# Grass and flowers (under the glory floor they sink as it rises; ruins.wgsl).
pts = sample_ground(46000, meadow)
ax, ay = yaw_axes(len(pts), 0.12)
add(33, pts - [0, 0.02, 0], ax, ay, rng.uniform(0.55, 1.05, len(pts)), rng.random(len(pts)), rng.uniform(0.4, 0.6, len(pts)))
pts = sample_ground(16000, lambda tri: meadow(tri, 2.0))
keep = np.sin(pts[:, 0] * 0.55 + 1.3) * np.sin(pts[:, 2] * 0.47) + rng.random(len(pts)) * 0.9 > 0.55
pts = pts[keep]
ax, ay = yaw_axes(len(pts), 0.25)
pts[:, 1] += rng.uniform(0.12, 0.34, len(pts))
add(34, pts, ax, ay, rng.uniform(1.6, 2.4, len(pts)), rng.random(len(pts)), np.zeros(len(pts)))

# Flowers draw from their own random numbers, so adding them leaves the
# rest (the bushes' layout) as it was.
main_rng, flower_rng = rng, np.random.default_rng(29)

# Sunflowers (37) and daisies (38), small, in drifts over the meadow; the
# stem is 6 head radii, so they stand just above the grass.
rng = flower_rng
for kind, count, radius, drift in ((37, 4200, (0.06, 0.09), 0.3), (38, 9000, (0.04, 0.06), 0.45)):
    pts = sample_ground(count, lambda tri: meadow(tri, 1.5))
    f = np.sin(pts[:, 0] * 0.31 + kind) * np.sin(pts[:, 2] * 0.27 + kind * 2) + rng.random(len(pts)) * 0.8
    pts = pts[f > drift]
    ax, ay = yaw_axes(len(pts), 0.22)
    size = rng.uniform(*radius, len(pts)) * 2
    pts[:, 1] -= rng.uniform(0.0, 0.08, len(pts)) * (size / size.max())
    add(kind, pts, ax, ay, size, rng.random(len(pts)), np.zeros(len(pts)))
    print(f'{"sunflowers" if kind == 37 else "daisies"}: {len(pts)}')
rng = main_rng

# Ivy leaf cards where the shaped ivy mask is high; they wither over the
# first 4.5 s, as the ivy meshes do.
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
ax = np.cross(nrm, -tip)
ax /= np.linalg.norm(ax, axis=1, keepdims=True) + 1e-9
add(31, p, ax, nrm, rng.uniform(2.2, 3.4, len(pick)), rng.uniform(0.0, 0.45, len(pick)), np.ones(len(pick)))


def leaves_on(kind, pos_list, per_area, size):
    """Leaf cards scattered over surfaces (positions, normals, triangles),
    facing out, tips down; those with a wither time go then."""
    total = 0
    for wp, wn, idx, wither in pos_list:
        a, b, c = wp[idx[:, 0]], wp[idx[:, 1]], wp[idx[:, 2]]
        cr = np.cross(b - a, c - a)
        area = np.linalg.norm(cr, axis=1) / 2
        up_bias = np.clip((wn[idx].mean(1)[:, 1]) * 0.5 + 0.7, 0.2, 1.2)
        n = int(area.sum() * per_area)
        if n == 0:
            continue
        pick = rng.choice(len(idx), size=n, p=area * up_bias / (area * up_bias).sum())
        r1, r2 = rng.random(n), rng.random(n)
        s = np.sqrt(r1)
        p = a[pick] * (1 - s)[:, None] + b[pick] * (s * (1 - r2))[:, None] + c[pick] * (s * r2)[:, None]
        nrm = cr[pick] / (np.linalg.norm(cr[pick], axis=1, keepdims=True) + 1e-12)
        nrm = nrm + rng.normal(0, 0.45, (n, 3))
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        tip = nrm + np.array([0, -0.6, 0]) + rng.normal(0, 0.5, (n, 3))
        tip -= nrm * (tip * nrm).sum(1, keepdims=True)
        tip /= np.linalg.norm(tip, axis=1, keepdims=True) + 1e-9
        ax = np.cross(nrm, -tip)
        ax /= np.linalg.norm(ax, axis=1, keepdims=True) + 1e-9
        if wither is None:
            add(kind, p + nrm * 0.03, ax, nrm, rng.uniform(2.4, 3.4, n) * size, rng.random(n), np.zeros(n))
        else:
            add(kind, p + nrm * 0.03, ax, nrm, rng.uniform(2.4, 3.4, n) * size,
                np.clip(wither + rng.normal(0, 0.03, n), 0, 1), np.ones(n))
        total += n
    return total


print('leaves on bushes', leaves_on(35, bush_world, 26, 1.0))


def blooms_on(surfaces, per_area):
    """Sunflowers and daisies peeking out of bush surfaces (upper side), on
    short stems; they go with their bush."""
    total = 0
    for wp, wn, idx, wither in surfaces:
        a, b, c = wp[idx[:, 0]], wp[idx[:, 1]], wp[idx[:, 2]]
        cr = np.cross(b - a, c - a)
        area = np.linalg.norm(cr, axis=1) / 2
        nz = cr / (np.linalg.norm(cr, axis=1, keepdims=True) + 1e-12)
        w = area * np.clip(nz[:, 1], 0, None) ** 2
        n = rng.poisson(max(area.sum() * per_area, 0.0))
        if n == 0 or w.sum() == 0:
            continue
        pick = rng.choice(len(idx), size=n, p=w / w.sum())
        r1, r2 = rng.random(n), rng.random(n)
        sq = np.sqrt(r1)
        p = a[pick] * (1 - sq)[:, None] + b[pick] * (sq * (1 - r2))[:, None] + c[pick] * (sq * r2)[:, None]
        up = nz[pick] * 0.5 + np.array([0, 1, 0]) + rng.normal(0, 0.2, (n, 3))
        up /= np.linalg.norm(up, axis=1, keepdims=True)
        x = np.cross(up, rng.normal(0, 1, (n, 3)))
        x /= np.linalg.norm(x, axis=1, keepdims=True) + 1e-9
        sun = rng.random(n) < 0.4
        size = np.where(sun, rng.uniform(0.13, 0.18, n), rng.uniform(0.08, 0.12, n))
        # The stem (3 head radii x 2) mostly inside the bush.
        base = p - up * (size * 2.4)[:, None]
        flag = np.ones(n) if wither is not None else np.zeros(n)
        rand = np.full(n, wither) if wither is not None else rng.random(n)
        for kind, m in ((37, sun), (38, ~sun)):
            if m.any():
                add(kind, base[m], x[m], up[m], size[m], rand[m], flag[m])
        total += n
    return total


rng = flower_rng
print('blooms on bushes', blooms_on(bush_world, 4.0))
rng = main_rng

# Tree crowns (puffs, with leaves) where the trunks' branches end.
high = trunks[trunks[:, 1] > 2.6]
crowns = {}
for p in high:
    crowns.setdefault((round(p[0] / 1.4), round(p[2] / 1.4)), []).append(p)
cpos, cscale = [], []
for group in crowns.values():
    g = np.array(group)
    top = g[g[:, 1].argmax()]
    for _ in range(rng.integers(2, 4)):
        cpos.append(top + [rng.normal(0, 0.45), rng.uniform(0.1, 0.6), rng.normal(0, 0.45)])
        cscale.append(rng.uniform(0.75, 1.15))
cpos, cscale = np.array(cpos), np.array(cscale)
ax, ay = yaw_axes(len(cpos))
add(32, cpos, ax, ay, cscale, rng.random(len(cpos)), np.zeros(len(cpos)))
sphere_tris = []
for c, r in zip(cpos, cscale):
    sphere_tris.append((c + pp * r, pv, pf, None))
print('crown leaves', leaves_on(36, sphere_tris, 6, 1.0))

# Bushes, grown as before the animated GLB (clumps with leaves): along the
# foot of the old plinth and across the meadow. Those where the glory floor
# will be (52.8 x 22 m) wither just before it rises; the rest stay.
PLINTH = (12.75, 5.05)
FLOOR = (26.4, 11.0)
gxz = ground_pos[:, [0, 2]]


def ground_y(x, z):
    d = (gxz[:, 0] - x) ** 2 + (gxz[:, 1] - z) ** 2
    near = np.argpartition(d, 4)[:4]
    w = 1 / (np.sqrt(d[near]) + 1e-3) ** 2
    return float((ground_pos[near, 1] * w).sum() / w.sum())


seeds = []
for _ in range(70):
    side = rng.integers(4)
    u = rng.uniform(-1, 1)
    off = rng.uniform(0.35, 1.3)
    if side < 2:
        x, z = u * (PLINTH[0] + 0.5), (PLINTH[1] + off) * (1 if side == 0 else -1)
    else:
        x, z = (PLINTH[0] + off) * (1 if side == 2 else -1), u * (PLINTH[1] + 0.5)
    if side == 0 and abs(x) < 2.2:
        continue
    seeds.append((x, z, rng.uniform(0.45, 0.85)))
for p in sample_ground(160, lambda tri: meadow(tri, 3.0)):
    if np.hypot(p[0], p[2]) > 8 and not (abs(p[0]) < PLINTH[0] + 1.2 and abs(p[2]) < PLINTH[1] + 1.2):
        seeds.append((p[0], p[2], rng.uniform(0.4, 0.95)))
bpos, bscale, bwither = [], [], []
for x, z, r in seeds:
    y = ground_y(x, z)
    covered = abs(x) < FLOOR[0] + 0.3 and abs(z) < FLOOR[1] + 0.3
    wither = rng.uniform(0.3, 0.43) if covered else None
    for _ in range(rng.integers(3, 6)):
        a = rng.random() * math.tau
        d = r * rng.uniform(0.1, 0.8)
        sz = r * rng.uniform(0.55, 0.85)
        bpos.append((x + math.cos(a) * d, y + sz * 0.35 + rng.uniform(0, r * 0.5), z + math.sin(a) * d))
        bscale.append(sz)
        bwither.append(wither)
bpos = np.array(bpos)
ax, ay = yaw_axes(len(bpos))
rand = np.array([w if w is not None else rng.uniform(0.5, 1) for w in bwither])
add(30, bpos, ax, ay, np.array(bscale), rand, np.array([1.0 if w is not None else 0.0 for w in bwither]))
print(f'bushes: {len(seeds)} ({len(bpos)} clumps, {sum(w is not None for w in bwither)} under the floor)')
print('leaves on grown bushes', leaves_on(35, [(c + pp * r, pv, pf, w) for c, r, w in zip(bpos, bscale, bwither)], 9, 1.0))
rng = flower_rng
print('blooms on grown bushes', blooms_on([(c + pp * r, pv, pf, w) for c, r, w in zip(bpos, bscale, bwither)], 2.4))
rng = main_rng

TEMPLATE = {30: 24, 31: 21, 32: 24, 33: 22, 34: 23, 35: 20, 36: 20, 37: 25, 38: 25}
for (kind, _, _), (rows, lo, hi) in sorted(cells.items()):
    section(kind, len(rows), TEMPLATE[kind], b''.join(rows), lo=tuple(lo), hi=tuple(hi))

# ---------------------------------------------------------------------------
# Write

ENTRY = 192
head = 12 + ENTRY * len(sections)
blob = bytearray()


def put(b):
    off = head + len(blob)
    blob.extend(b)
    blob.extend(b'\0' * (-len(blob) % 4))
    return off


table = bytearray()
for s in sections:
    vbo, ibo = put(s['vb']), put(s['ib'])
    mo = put(s['morph']) if s['morph'] else 0
    to = put(s['track']) if s['track'] else 0
    wo = put(s['weights']) if s['weights'] else 0
    row = struct.pack('<8I', s['kind'], s['count'], s['icount'], vbo, len(s['vb']), ibo, len(s['ib']), s['material'])
    row += struct.pack('<6f', *s['lo'], *s['hi'])
    row += struct.pack('<4I', mo, len(s['morph']), to, s['track_n'])
    row += struct.pack('<2f', s['t0'], s['t1'])
    row += struct.pack('<2I2f', wo, s['w_n'], s['w0'], s['w1'])
    row += struct.pack('<10f', *s['rest'])
    row += struct.pack('<I', s['glows'])
    row += b'\0' * (ENTRY - len(row))
    table += row
with open(OUT, 'wb') as f:
    f.write(b'SHRN' + struct.pack('<2I', 4, len(sections)) + table + blob)
print(f'wrote {OUT}: {(head + len(blob)) / 1e6:.2f} MB, {len(sections)} sections')
