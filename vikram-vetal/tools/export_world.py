# Exports VikramVetal_Scene.glb (the night scene from Blender) to world.bin
# for the World node script.
#
#   python3 tools/export_world.py [VikramVetal_Scene.glb] [world.bin]
#
# The GLB is low poly: trees, bushes, boulders, bones and the ground, with a
# material per part and painted vertex colours. Every placed object is baked
# into world space and merged per material (the scene is small, so no
# instancing is needed). Grown here: dry grass over the ground and leaf
# cards over the foliage, so silhouettes read leafy. The camera (Cam_Hero)
# and the moon (Moon_Key) are printed, for the scene's defaults.
#
# Format (little-endian), as tools/export_anim.py in sheesupalgarh (v4) but
# with vertex colours in static vertices:
#   header   'SHRN' | version u32 (5) | section count u32
#   section  48 words: kind, count, indexCount, vbOffset, vbLength, ibOffset,
#            ibLength, material | bounds (6 f32) | morph offset, length |
#            track offset, samples, t0, t1 | weights offset, samples, w0, w1 |
#            rest pose (10 f32) | glows | 0...
# Static vertices, 24 bytes:
#   position f32x3 | normal snorm8x4 | extra unorm8x4 (wind weight, random,
#   path, 0; path on the terrain: 1 on the path, 0 off it, blending over a
#   metre and a half either side of its edge) | colour unorm8x4 (rgb, a = 1
#   when painted)
# Templates (kinds 20-24) and instances (30-38) as in sheesupalgarh.
# Kind 50 is the ground's height: count = N, an N x N grid of f32 heights
# (row-major, z then x) over lo..hi (x, z), for whatever walks on it.

import json, math, struct, sys
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else 'VikramVetal_Scene.glb'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'world.bin'
TEMPLATES_FROM = '../sheesupalgarh/ruins.bin'
CELL = 6.0
rng = np.random.default_rng(17)

# Materials drawn (world.wgsl).
STONE, ROCK, GROUND, BARK, VINE = 1, 2, 4, 6, 7
FOLIAGE, MOSS, BONE, SOCKET, GRASS_MESH, ASH = 18, 28, 25, 26, 27, 29

MATERIALS = {
    'Foliage_Jungle': FOLIAGE, 'Foliage_Peepal': FOLIAGE, 'Moss_Hanging': MOSS,
    'Jungle_Trunk': BARK, 'Bark': BARK, 'Vine': VINE, 'Bone': BONE, 'Stone': ROCK,
    'Socket_Dark': SOCKET, 'Grass_Dry': GRASS_MESH, 'Ground_Ash': ASH,
    'Ground_Earth': GROUND, 'Tile_Side': STONE,
}
# Swaying in the wind, by height above the object's own base (metres per
# full sway) and how much. Where the GLB has the wind painted (a _WIND
# attribute: x how much each vertex sways, y a phase, z what it is), the
# painted weight replaces the height.
WIND = {FOLIAGE: (5.0, 0.16), MOSS: (3.0, 0.22), GRASS_MESH: (0.5, 0.18), BARK: (6.0, 0.05), VINE: (4.0, 0.1)}

# ---------------------------------------------------------------------------
# GLB

data = open(SRC, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
BIN = 20 + jlen + 8
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
DTYPE = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1', 5122: '<i2', 5120: 'i1'}
NORM = {5121: 255, 5123: 65535, 5120: 127, 5122: 32767}


def accessor(i):
    a = gltf['accessors'][i]
    v = gltf['bufferViews'][a['bufferView']]
    n = NCOMP[a['type']]
    dt = np.dtype(DTYPE[a['componentType']])
    start = BIN + v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', dt.itemsize * n)
    if stride == dt.itemsize * n:
        arr = np.frombuffer(data, dtype=dt, count=a['count'] * n, offset=start).reshape(-1, n)
    else:
        arr = np.array([np.frombuffer(data, dtype=dt, count=n, offset=start + k * stride) for k in range(a['count'])])
    arr = arr.astype(np.float64)
    if a.get('normalized') or (a['componentType'] in NORM and a['type'] == 'VEC4' and dt.kind != 'f'):
        arr /= NORM.get(a['componentType'], 1)
    return arr


def local_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], float).reshape(4, 4).T
    t = np.array(n.get('translation', [0, 0, 0]), float)
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    s = np.array(n.get('scale', [1, 1, 1]), float)
    R = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])
    M = np.eye(4)
    M[:3, :3] = R * s
    M[:3, 3] = t
    return M


# Walk the scene: every mesh node with its world matrix; the camera and the
# light as they are found.
placed = []  # (node name, mesh index, world matrix)
camera = moon = None


def visit(i, parent):
    global camera, moon
    n = gltf['nodes'][i]
    M = parent @ local_matrix(n)
    if 'mesh' in n:
        placed.append((n['name'], n['mesh'], M))
    if 'camera' in n:
        cam = gltf['cameras'][n['camera']]
        if camera is None or n['name'] == 'Cam_Hero':
            camera = (n['name'], M, cam)
    light = n.get('extensions', {}).get('KHR_lights_punctual')
    if light is not None:
        moon = (n['name'], M, gltf['extensions']['KHR_lights_punctual']['lights'][light['light']])
    for c in n.get('children', []):
        visit(c, M)


for r in gltf['scenes'][gltf.get('scene', 0)]['nodes']:
    visit(r, np.eye(4))

# ---------------------------------------------------------------------------
# Packing


def snorm(x):
    return np.clip(np.round(np.asarray(x) * 127), -127, 127).astype(np.int8)


def unorm(x):
    return np.clip(np.round(np.asarray(x) * 255), 0, 255).astype(np.uint8)


def static_bytes(pos, nrm, wind, seed, col, path=None):
    v = np.zeros(len(pos), dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('e', 'u1', 4), ('c', 'u1', 4)])
    v['p'] = pos
    v['n'][:, :3] = snorm(nrm)
    v['e'][:, 0] = unorm(wind)
    v['e'][:, 1] = unorm(seed)
    if path is not None:
        v['e'][:, 2] = unorm(path)
    v['c'] = unorm(col)
    return v.tobytes()


def path_weight(wp, on_path, reach=1.5):
    """How much of the path each terrain vertex is: 1 a reach inside it, 0
    a reach outside, 0.5 at its edge (distances across the ground), so the
    path and the green blend over a soft band."""
    w = np.zeros(len(wp))
    xz = wp[:, [0, 2]]
    inside, outside = xz[on_path], xz[~on_path]
    if not len(inside) or not len(outside):
        return on_path.astype(float)

    def nearest(a, b):
        d = np.full(len(a), np.inf)
        for lo in range(0, len(b), 2048):
            d = np.minimum(d, np.linalg.norm(a[:, None, :] - b[None, lo:lo + 2048, :], axis=2).min(1))
        return d
    w[~on_path] = 0.5 * np.clip(1 - nearest(outside, inside) / reach, 0, 1)
    w[on_path] = 0.5 + 0.5 * np.clip(nearest(inside, outside) / reach, 0, 1)
    return w


sections = []


def section(kind, count, icount, vb=b'', ib=b'', **kw):
    s = dict(kind=kind, count=count, icount=icount, vb=vb, ib=ib, material=0, lo=(0, 0, 0), hi=(0, 0, 0))
    s.update(kw)
    sections.append(s)


def classify(name, tc, wp, idx):
    """Materials for triangles of the optimised GLB, by mesh name and colour
    (linear RGB, per triangle)."""
    n = name.split('.')[0]
    r, g, b = tc[:, 0], tc[:, 1], tc[:, 2]
    if n.startswith('Peepal_Canopy'):
        return np.full(len(tc), FOLIAGE)
    if n.startswith('Peepal_MossDrapes'):
        return np.full(len(tc), MOSS)
    if n.startswith(('Peepal_Trunk', 'Peepal_AerialRoots')):
        return np.full(len(tc), BARK)
    if n.startswith('Jungle'):
        # Greens are leaves; the browns are trunks.
        return np.where(g > r * 1.3, FOLIAGE, BARK)
    if n.startswith('Props'):
        lum = tc @ np.array([0.3, 0.59, 0.11])
        return np.where(lum > 0.6, BONE, np.where(lum < 0.1, SOCKET, ROCK))
    if n.startswith('Terrain'):
        cr = np.cross(wp[idx[:, 1]] - wp[idx[:, 0]], wp[idx[:, 2]] - wp[idx[:, 0]])
        ny = np.abs(cr[:, 1]) / (np.linalg.norm(cr, axis=1) + 1e-12)
        out = np.where(g > r * 1.15, GRASS_MESH, np.where(r > g * 1.15, GROUND, ASH))
        # Its steep sides (the edge of the world) are earth.
        return np.where((ny < 0.3) & (out != GRASS_MESH), GROUND, out)
    return np.full(len(tc), STONE)


# ---------------------------------------------------------------------------
# Static meshes, merged per material

merged = {}  # material -> list of chunks [vbs, ibs, verts, tris]
ground_tris = []  # the terrain's level triangles (world space), for heights
surfaces = {}  # material -> list of (positions, normals, triangles) for growing
for name, mi, M in placed:
    R = M[:3, :3]
    nrmM = np.linalg.inv(R).T
    seed = rng.random()
    for prim in gltf['meshes'][mi]['primitives']:
        if prim.get('mode', 4) != 4:
            continue
        a = prim['attributes']
        pos = accessor(a['POSITION'])
        nrm = accessor(a['NORMAL']) if 'NORMAL' in a else np.tile([0, 1, 0], (len(pos), 1))
        idx = (accessor(prim['indices'])[:, 0] if 'indices' in prim else np.arange(len(pos))).astype(np.int64).reshape(-1, 3)
        wp = pos @ R.T + M[:3, 3]
        wn = nrm @ nrmM.T
        wn /= np.linalg.norm(wn, axis=1, keepdims=True) + 1e-12
        if np.linalg.det(R) < 0:
            idx = idx[:, [0, 2, 1]]
        mname = gltf['materials'][prim['material']]['name'] if 'material' in prim else ''
        col = np.ones((len(pos), 4))
        col[:, 3] = 0
        if 'COLOR_0' in a:
            c = accessor(a['COLOR_0'])
            col[:, :c.shape[1]] = c[:, :4]
            col[:, 3] = 1
        else:
            # The material's own colour, when it has one, stands in.
            pbr = gltf['materials'][prim['material']].get('pbrMetallicRoughness', {}) if 'material' in prim else {}
            if 'baseColorFactor' in pbr:
                col[:, :3] = np.array(pbr['baseColorFactor'][:3])
                col[:, 3] = 1
        # The material of each triangle: from its material's name when it has
        # a known one; else (the optimised GLB merges everything and colours
        # it by vertex) from the mesh's name and the triangle's colour.
        if mname in MATERIALS:
            tri_mat = np.full(len(idx), MATERIALS[mname])
        else:
            tri_mat = classify(name, col[idx, :3].mean(1), wp, idx)
        path = None
        if name.startswith('Terrain'):
            # The path is the ash; its edge blends into the green.
            on_path = np.zeros(len(wp), bool)
            on_path[np.unique(idx[tri_mat == ASH])] = True
            # (A vertex on both sides of the edge counts as off it.)
            on_path[np.unique(idx[tri_mat != ASH])] = False
            path = path_weight(wp, on_path)
        if name.startswith('Terrain'):
            tri = wp[idx]
            cr = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            up = np.abs(cr[:, 1]) / (np.linalg.norm(cr, axis=1) + 1e-12)
            ground_tris.append(tri[up > 0.5])
        for mat in np.unique(tri_mat):
            sub = idx[tri_mat == mat]
            used = np.unique(sub)
            remap = np.full(len(pos), -1)
            remap[used] = np.arange(len(used))
            sidx = remap[sub]
            sp, sn, sc = wp[used], wn[used], col[used].copy()
            if mat in (FOLIAGE, MOSS) and sc[:, 3].any():
                # The painted greens are very dark; lift them, keeping the hue.
                lum = sc[:, :3] @ np.array([0.3, 0.59, 0.11])
                sc[:, :3] *= np.clip(0.06 / np.maximum(lum, 1e-4), 1, 12)[:, None]
            if name.startswith('Peepal') and sc[:, 3].any():
                # The hero tree: dark brown wood, dark green leaves and moss,
                # keeping the painted light and dark.
                lum = sc[:, :3] @ np.array([0.3, 0.59, 0.11])
                rel = np.clip(lum / max(lum.mean(), 1e-4), 0.6, 1.5)[:, None]
                if mat == BARK:
                    sc[:, :3] = rel * np.array([0.08, 0.045, 0.025])
                elif mat == MOSS:
                    sc[:, :3] = rel * np.array([0.035, 0.065, 0.022])
                elif mat == FOLIAGE:
                    sc[:, :3] = rel * np.array([0.022, 0.055, 0.025])
            if name.startswith('Terrain') and mat == ASH and sc[:, 3].any():
                # The path (painted ash-grey): a light, brownish green,
                # keeping the painted light and dark.
                lum = sc[:, :3] @ np.array([0.3, 0.59, 0.11])
                rel = np.clip(lum / max(lum.mean(), 1e-4), 0.7, 1.4)[:, None]
                sc[:, :3] = rel * np.array([0.15, 0.14, 0.075])
            if name.startswith('Terrain') and mat == GRASS_MESH and sc[:, 3].any():
                # The ground's green is painted for day; at night it is a
                # deep, cool green: half its saturation, a quarter as bright.
                lum = sc[:, :3] @ np.array([0.3, 0.59, 0.11])
                sc[:, :3] = (sc[:, :3] * 0.5 + lum[:, None] * 0.5) * np.array([0.2, 0.25, 0.3])
            wind = np.zeros(len(sp))
            if mat in WIND:
                span, amount = WIND[mat]
                if '_WIND' in a:
                    wind = accessor(a['_WIND'])[used, 0] * amount / 0.25
                else:
                    base = sp[:, 1].min() if mat == GRASS_MESH else (M[1, 3] if abs(M[1, 3]) > 1e-6 else -0.2)
                    wind = np.clip((sp[:, 1] - base) / span, 0, 1) * amount / 0.25
            surfaces.setdefault(int(mat), []).append((sp, sn, sidx))
            chunks = merged.setdefault(int(mat), [])
            for lo in range(0, len(sidx), 20000):
                part = sidx[lo:lo + 20000]
                pu = np.unique(part)
                pr = np.full(len(sp), -1)
                pr[pu] = np.arange(len(pu))
                cur = next((c for c in chunks if c[2] + len(pu) < 65536), None)
                if cur is None:
                    cur = [[], [], 0, 0]
                    chunks.append(cur)
                cur[0].append(static_bytes(sp[pu], sn[pu], np.clip(wind[pu], 0, 1), seed, sc[pu], None if path is None else path[used][pu]))
                cur[1].append((pr[part] + cur[2]).astype('<u2').tobytes())
                cur[2] += len(pu)
                cur[3] += len(part)
for mat, chunks in merged.items():
    for vbs, ibs, nv, nt in chunks:
        # Static meshes are objects (kind 40) with no track, so they can have
        # any material.
        section(40, nv, nt * 3, b''.join(vbs), b''.join(ibs), material=mat)
    print(f'material {mat}: {sum(c[2] for c in chunks)} verts, {sum(c[3] for c in chunks)} tris')

# ---------------------------------------------------------------------------
# Templates from the ruins (leaf, creeper leaf, grass clump, flower, blossom)

old = open(TEMPLATES_FROM, 'rb').read()
ver = struct.unpack_from('<I', old, 4)[0]
entry = {1: 32, 2: 64, 3: 128, 4: 192, 5: 192}[ver]
for i in range(struct.unpack_from('<I', old, 8)[0]):
    k, c, ic, vo, vl, io, il = struct.unpack_from('<7I', old, 12 + i * entry)
    if 20 <= k <= 25:
        section(k, c, ic, old[vo:vo + vl], old[io:io + il])

# ---------------------------------------------------------------------------
# Grown

cells = {}


def add(kind, pos, ax, ay, scale, rand, w):
    for p, x, y, s, r, ww in zip(pos, ax, ay, scale, rand, w):
        key = (kind, math.floor(p[0] / CELL), math.floor(p[2] / CELL))
        c = cells.setdefault(key, [[], np.full(3, 1e9), np.full(3, -1e9)])
        c[0].append(struct.pack('<4e4b4b', p[0], p[1], p[2], s, *snorm(x), snorm(r * 2 - 1), *snorm(y), snorm(ww * 2 - 1)))
        c[1] = np.minimum(c[1], p)
        c[2] = np.maximum(c[2], p + np.array([0, s * 0.5, 0]))


def sample(surfs, count, weight=None):
    """Points on surfaces (positions, normals, triangles), area-weighted and
    favouring faces that look up."""
    P, N, A = [], [], []
    for wp, wn, idx in surfs:
        a, b, c = wp[idx[:, 0]], wp[idx[:, 1]], wp[idx[:, 2]]
        cr = np.cross(b - a, c - a)
        area = np.linalg.norm(cr, axis=1) / 2
        nz = cr / (np.linalg.norm(cr, axis=1, keepdims=True) + 1e-12)
        P.append((a, b, c))
        N.append(nz)
        A.append(area * (weight(nz) if weight else 1))
    if not P:
        return np.zeros((0, 3)), np.zeros((0, 3))
    a = np.concatenate([p[0] for p in P])
    b = np.concatenate([p[1] for p in P])
    c = np.concatenate([p[2] for p in P])
    nz = np.concatenate(N)
    w = np.concatenate(A)
    if w.sum() <= 0:
        return np.zeros((0, 3)), np.zeros((0, 3))
    pick = rng.choice(len(w), size=count, p=w / w.sum())
    r1, r2 = rng.random(count), rng.random(count)
    s = np.sqrt(r1)
    pts = a[pick] * (1 - s)[:, None] + b[pick] * (s * (1 - r2))[:, None] + c[pick] * (s * r2)[:, None]
    return pts, nz[pick]


def yaw_axes(n, tilt=0.0):
    a = rng.random(n) * math.tau
    ax = np.stack([np.cos(a), np.zeros(n), np.sin(a)], 1)
    up = np.stack([rng.normal(0, tilt, n), np.ones(n), rng.normal(0, tilt, n)], 1)
    up -= ax * (up * ax).sum(1, keepdims=True)
    return ax, up / np.linalg.norm(up, axis=1, keepdims=True)


# Dry grass (template 22): thick on the earth, sparse on the ash.
up_only = lambda nz: np.clip(nz[:, 1], 0, None) ** 4
for mat, count in ((GROUND, 42000), (ASH, 5000)):
    pts, _ = sample(surfaces.get(mat, []), count, up_only)
    if len(pts):
        ax, ay = yaw_axes(len(pts), 0.12)
        add(33, pts - [0, 0.02, 0], ax, ay, rng.uniform(0.5, 1.0, len(pts)), rng.random(len(pts)), rng.uniform(0.4, 0.6, len(pts)))
        print(f'grass on {mat}: {len(pts)}')

# Leaf cards (template 20) over the foliage, more on top, facing out.
fol = surfaces.get(FOLIAGE, [])
area = sum((np.linalg.norm(np.cross(wp[i[:, 1]] - wp[i[:, 0]], wp[i[:, 2]] - wp[i[:, 0]]), axis=1) / 2).sum() for wp, wn, i in fol)
n = int(min(area * 14, 60000))
pts, nz = sample(fol, n, lambda nz: 0.4 + np.clip(nz[:, 1], 0, None))
if len(pts):
    nrm = nz + rng.normal(0, 0.45, (len(pts), 3))
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    tip = nrm + np.array([0, -0.6, 0]) + rng.normal(0, 0.5, (len(pts), 3))
    tip -= nrm * (tip * nrm).sum(1, keepdims=True)
    tip /= np.linalg.norm(tip, axis=1, keepdims=True) + 1e-9
    ax = np.cross(nrm, -tip)
    ax /= np.linalg.norm(ax, axis=1, keepdims=True) + 1e-9
    add(35, pts + nrm * 0.03, ax, nrm, rng.uniform(1.4, 2.2, len(pts)), rng.random(len(pts)), np.zeros(len(pts)))
    print(f'leaf cards on foliage: {len(pts)} (foliage area {area:.0f} m2)')

TEMPLATE = {33: 22, 35: 20}
for (kind, _, _), (rows, lo, hi) in sorted(cells.items()):
    section(kind, len(rows), TEMPLATE[kind], b''.join(rows), lo=tuple(lo), hi=tuple(hi))

# ---------------------------------------------------------------------------
# The ground's height, on a grid: the highest level terrain at each point
# (its top, not the slab's underside), holes filled from their neighbours.

HN = 128
if ground_tris:
    gt = np.concatenate(ground_tris)
    glo = gt[:, :, [0, 2]].reshape(-1, 2).min(0)
    ghi = gt[:, :, [0, 2]].reshape(-1, 2).max(0)
    step = (ghi - glo) / (HN - 1)
    H = np.full((HN, HN), -np.inf)
    for a, b, c in gt:
        xs = (np.array([a[0], b[0], c[0]]) - glo[0]) / step[0]
        zs = (np.array([a[2], b[2], c[2]]) - glo[1]) / step[1]
        i0, i1 = int(np.ceil(xs.min())), int(np.floor(xs.max()))
        k0, k1 = int(np.ceil(zs.min())), int(np.floor(zs.max()))
        if i1 < i0 or k1 < k0:
            continue
        gx, gz = np.meshgrid(np.arange(i0, i1 + 1), np.arange(k0, k1 + 1))
        den = (zs[1] - zs[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (zs[0] - zs[2])
        if abs(den) < 1e-12:
            continue
        wa = ((zs[1] - zs[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gz - zs[2])) / den
        wb = ((zs[2] - zs[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gz - zs[2])) / den
        wc = 1 - wa - wb
        m = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
        y = wa * a[1] + wb * b[1] + wc * c[1]
        zz, xx = gz[m], gx[m]
        H[zz, xx] = np.maximum(H[zz, xx], y[m])
    for _ in range(HN):
        hole = ~np.isfinite(H)
        if not hole.any():
            break
        pad = np.pad(H, 1, constant_values=-np.inf)
        nb = np.stack([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]])
        fin = np.isfinite(nb)
        avg = np.where(fin, nb, 0).sum(0) / np.maximum(fin.sum(0), 1)
        fill = hole & fin.any(0)
        H[fill] = avg[fill]
    H[~np.isfinite(H)] = 0
    section(50, HN, 0, H.astype('<f4').tobytes(), lo=(glo[0], 0, glo[1]), hi=(ghi[0], 0, ghi[1]))
    print(f'ground heights: {HN}x{HN} over x {glo[0]:.1f}..{ghi[0]:.1f}, z {glo[1]:.1f}..{ghi[1]:.1f}, y {H.min():.2f}..{H.max():.2f}')

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
    row = struct.pack('<8I', s['kind'], s['count'], s['icount'], vbo, len(s['vb']), ibo, len(s['ib']), s['material'])
    row += struct.pack('<6f', *s['lo'], *s['hi'])
    row += struct.pack('<4I2f2I2f', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    row += struct.pack('<10f', 0, 0, 0, 0, 0, 0, 1, 1, 1, 1)
    row += b'\0' * (ENTRY - len(row))
    table += row
with open(OUT, 'wb') as f:
    f.write(b'SHRN' + struct.pack('<2I', 5, len(sections)) + table + blob)
print(f'wrote {OUT}: {(head + len(blob)) / 1e6:.2f} MB, {len(sections)} sections')

# The camera and the moon, for the scene's defaults (Y up; yaw about Y with
# positive turning left, pitch up).
allp = np.concatenate([s[0] for v in surfaces.values() for s in v])
print('scene bounds', np.round(allp.min(0), 1), np.round(allp.max(0), 1))
# The hero tree: the peepal's trunk, for the fireflies and ghost lights
# that gather round it.
trunk = [(name, M, mi) for name, mi, M in placed if name.startswith('Peepal_Trunk')]
if trunk:
    name, M, mi = trunk[0]
    pts = np.concatenate([accessor(p['attributes']['POSITION']) @ M[:3, :3].T + M[:3, 3] for p in gltf['meshes'][mi]['primitives']])
    low = pts[pts[:, 1] < pts[:, 1].min() + 1.5]
    print(f'hero tree: base {np.round([low[:, 0].mean(), pts[:, 1].min(), low[:, 2].mean()], 2)} '
          f'height {pts[:, 1].max() - pts[:, 1].min():.1f} trunk radius {np.abs(low[:, [0, 2]] - low[:, [0, 2]].mean(0)).max():.1f}')
if camera:
    name, M, cam = camera
    fwd = -M[:3, 2] / np.linalg.norm(M[:3, 2])
    yaw = math.degrees(math.atan2(-fwd[0], -fwd[2]))
    pitch = math.degrees(math.asin(np.clip(fwd[1], -1, 1)))
    fov = math.degrees(cam.get('perspective', {}).get('yfov', 0.8))
    print(f'camera {name}: position {np.round(M[:3, 3], 2)} rotationX {pitch:.1f} rotationY {yaw:.1f} fov {fov:.1f}')
if moon:
    name, M, light = moon
    to_light = M[:3, 2] / np.linalg.norm(M[:3, 2])
    az = math.degrees(math.atan2(to_light[2], to_light[0]))
    el = math.degrees(math.asin(np.clip(to_light[1], -1, 1)))
    print(f'moon {name}: azimuth {az:.1f} elevation {el:.1f} colour {light.get("color")} intensity {light.get("intensity")}')
