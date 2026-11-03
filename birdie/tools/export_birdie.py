# Exports WildlifeTracker_FormFactors.glb (three form factors of the Birdie
# wildlife tracker, from Blender) to birdie.bin for the Studio node script
# (../rive/Studio.luau).
#
#   python3 tools/export_birdie.py [WildlifeTracker_FormFactors.glb] [birdie.bin]
#
# The GLB has three products, each a root node: Birdhouse_XIAO (a black
# shell, a mustard front panel carved in contour rings, a perch, and a back
# lid carrying the electronics), TurnedBirdhouse (an ash body turned on a
# lathe, a walnut pagoda roof) and iPodBox (left out: not in the studio).
# Their lids are posed opened in the file; here every lid is put back (its
# own transform taken off), so the script assembles them at rest and opens
# them itself for the exploded view.
#
# Each vertex is in its frame: 0/1 the birdhouse's body/back lid, 2/3 the
# turned birdhouse's body/roof; a product's
# frames have its root's scale but not its placement (the script lays the
# three out on turntables). Each product gets a turntable plinth (made
# here) under it, in its body frame, from y = -PLINTH_H to 0.
#
# Format (little-endian):
#   header   'BRDI' | version u32 (2) | vertex count u32 | index count u32 |
#            product count u32 | 0 u32 x3; then per product 12 f32: bounds min xyz, max xyz (its body
#            frame, without the plinth), plinth radius, plinth height, and
#            its footprint on the plinth (what touches it): centre x, z,
#            half width x, z
#   vertices 20 bytes: position f32x3 | normal snorm8x4 (w: cavity, -1
#            ridge .. 1 groove; on the mustard panel how deep the carving
#            is) | material, frame, product, 0 (u8x4)
#   indices  u32 (after the vertices)
# Materials are the GLB's, in its order (0 PH_LiPo_Blue .. 11 Wire_Red),
# then 12 for the plinths.

import json, struct, sys
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else 'WildlifeTracker_FormFactors.glb'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'birdie.bin'
PRODUCTS = ['Birdhouse_XIAO', 'TurnedBirdhouse']
LIDS = {'BackLid_XIAO', 'TB_Roof'}
PANEL = 'FrontPanel_XIAO'
PLINTH_MAT = 12
PLINTH_H = 0.007
PLINTH_MARGIN = 1.35

data = open(SRC, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
BIN = 20 + jlen + 8
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
DTYPE = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}
nodes = gltf['nodes']
MATS = [m['name'] for m in gltf['materials']]


def accessor(i):
    a = gltf['accessors'][i]
    bv = gltf['bufferViews'][a['bufferView']]
    n = NCOMP[a['type']]
    off = BIN + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(data, DTYPE[a['componentType']], a['count'] * n, off).reshape(a['count'], n)


def local(n):
    x, y, z, w = n.get('rotation', [0, 0, 0, 1])
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m = np.eye(4)
    m[:3, :3] = r * np.array(n.get('scale', [1, 1, 1]))[None, :]
    m[:3, 3] = n.get('translation', [0, 0, 0])
    return m


def cavity(pos, nrm, idx):
    """Per vertex, how far its neighbours rise above its tangent plane (the
    mean sine): positive in grooves and creases, negative on ridges and
    edges. Split vertices (hard edges) are welded for it."""
    key = np.round(pos / 1e-6).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    nw = weld.max() + 1
    wp = np.zeros((nw, 3))
    wp[weld] = pos
    wn = np.zeros((nw, 3))
    np.add.at(wn, weld, nrm)
    wn /= np.linalg.norm(wn, axis=1, keepdims=True) + 1e-12
    t = weld[idx]
    e = np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    d = wp[e[:, 1]] - wp[e[:, 0]]
    s = np.einsum('ij,ij->i', d, wn[e[:, 0]]) / (np.linalg.norm(d, axis=1) + 1e-12)
    acc = np.zeros(nw)
    cnt = np.zeros(nw)
    np.add.at(acc, e[:, 0], s)
    np.add.at(cnt, e[:, 0], 1)
    return np.clip(acc / np.maximum(cnt, 1) * 4, -1, 1)[weld]


def plinth(radius, h, seg=96):
    """A turntable disc: a short cylinder with a rounded top edge."""
    f = 0.0016
    prof = [(0.0, 0.0, 0, 1), (radius - f, 0.0, 0, 1)]
    for k in range(1, 7):
        a = k / 6 * np.pi / 2
        prof.append((radius - f + np.sin(a) * f, -f + np.cos(a) * f, np.sin(a), np.cos(a)))
    prof += [(radius, -h, 1, 0), (radius * 0.97, -h, 0, -1), (0.0, -h, 0, -1)]
    pos, nrm, idx = [], [], []
    for i, (r, y, nr, ny) in enumerate(prof):
        for s in range(seg + 1):
            a = s / seg * 2 * np.pi
            pos.append((r * np.cos(a), y, r * np.sin(a)))
            nrm.append((nr * np.cos(a), ny, nr * np.sin(a)))
    w = seg + 1
    for i in range(len(prof) - 1):
        for s in range(seg):
            a, b, c, d = i * w + s, i * w + s + 1, (i + 1) * w + s, (i + 1) * w + s + 1
            idx += [(a, c, b), (b, c, d)]
    return np.array(pos), np.array(nrm, float), np.array(idx)


verts, tris = [], []
count = 0
bounds = []


def add(pos, nrm, cav, idx, mat, frame, product):
    global count
    nrm = nrm / (np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12)
    v = np.zeros(len(pos), [('p', '<f4', 3), ('n', 'i1', 4), ('id', 'u1', 4)])
    v['p'] = pos
    v['n'][:, :3] = np.round(np.clip(nrm, -1, 1) * 127)
    v['n'][:, 3] = np.round(np.clip(cav, -1, 1) * 127)
    v['id'] = np.array([mat, frame, product, 0])[None, :]
    verts.append(v)
    tris.append(idx + count)
    count += len(pos)


for p, pname in enumerate(PRODUCTS):
    root = next(i for i, n in enumerate(nodes) if n.get('name') == pname)
    S = np.diag(list(nodes[root].get('scale', [1, 1, 1])) + [1])
    body_pts = []

    def walk(i, M, frame):
        n = nodes[i]
        name = n.get('name', '')
        if name in LIDS:
            frame = 2 * p + 1
            m = M  # the lid put back: its own transform left off
        else:
            m = M @ local(n)
        if 'mesh' in n:
            for prim in gltf['meshes'][n['mesh']]['primitives']:
                at = prim['attributes']
                pos = accessor(at['POSITION']).astype(float) @ m[:3, :3].T + m[:3, 3]
                nm = np.linalg.inv(m[:3, :3]).T
                nrm = accessor(at['NORMAL']).astype(float) @ nm.T
                idx = accessor(prim['indices'])[:, 0].astype(np.int64).reshape(-1, 3)
                if name == PANEL:
                    # The carving: depth into the panel (its front is +z).
                    z = pos[:, 2]
                    cav = 1 - 2 * (z - z.min()) / max(z.max() - z.min(), 1e-9)
                else:
                    cav = cavity(pos, nrm, idx)
                add(pos, nrm, cav, idx, prim.get('material', 0), frame, p)
                if frame == 2 * p and not name.startswith('PH_'):
                    body_pts.append(pos)
                print(f'  {name:30s} {MATS[prim.get("material", 0)]:18s} frame {frame} tris {len(idx)}')
        for c in n.get('children', []):
            walk(c, m, frame)

    print(pname)
    for c in nodes[root].get('children', []):
        walk(c, S, 2 * p)
    pts = np.concatenate(body_pts)
    lo, hi = pts.min(0), pts.max(0)
    radius = float(np.sqrt((pts[:, [0, 2]] ** 2).sum(1)).max()) * PLINTH_MARGIN
    radius = max(radius, 0.038)
    pp, pn, pi = plinth(radius, PLINTH_H)
    add(pp, pn, np.zeros(len(pp)), pi, PLINTH_MAT, 2 * p, p)
    low = pts[pts[:, 1] < 0.003]
    flo, fhi = low[:, [0, 2]].min(0), low[:, [0, 2]].max(0)
    bounds.append(list(lo) + list(hi) + [radius, PLINTH_H] + list((flo + fhi) / 2) + list((fhi - flo) / 2))
    print(f'  bounds {np.round(lo, 4)} .. {np.round(hi, 4)}, plinth r {radius:.4f}')

V = np.concatenate(verts)
I = np.concatenate(tris).astype('<u4').reshape(-1)
head = b'BRDI' + struct.pack('<7I', 2, len(V), len(I), len(PRODUCTS), 0, 0, 0)
for b in bounds:
    head += struct.pack('<12f', *b)
assert len(head) == 32 + 48 * len(PRODUCTS)
with open(OUT, 'wb') as f:
    f.write(head + V.tobytes() + I.tobytes())
print(f'{OUT}: {len(V)} vertices, {len(I) // 3} triangles, {(len(head) + V.nbytes + I.nbytes) / 1e6:.1f} MB')
