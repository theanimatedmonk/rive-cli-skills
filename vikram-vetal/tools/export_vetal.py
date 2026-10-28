# Exports Vetal.glb (the Vetal, rigged in Blender, hanging upside down from
# the peepal) to vetal.bin for the Spirit module (../vetal/Spirit.luau).
#
#   python3 tools/export_vetal.py [Vetal.glb] [vetal.bin]
#
# The GLB is his skinned body (Vetal_Body), painted by vertex (no textures):
# skin and cloth (Vetal_VC), his hair (Vetal_VC_DoubleSided) and his eyes
# (Vetal_Eyes_Glow, emissive); the wind painted on him (a _WIND attribute:
# how much each vertex sways, its phase, what it is: 0 still, 1 hair, 2 and
# 4 cloth); and one loop, VTL_Hang. The rig hangs from its root, the point
# on the branch: that placement in the scene is taken off (so he hangs from
# the origin) and written down, so the scene can hang him there again.
#
# Format (little-endian):
#   header   'VVTL' | version u32 (1) | section count u32 | joint count u32
#   section  8 words: kind u32, offset u32, length u32, a u32, b u32,
#            c f32, d f32, e u32
#     1  vertices      a = count; per vertex 32 bytes: position f32x3,
#                      normal snorm8x4 (w: the smooth normal's octahedral
#                      u), colour unorm8x4 (sRGB; a = what it is: 0 body,
#                      0.5 hair, 1 the glowing eyes), joints u8x4, weights
#                      unorm8x4, wind unorm8x4 (sway, phase, what it is / 4,
#                      the smooth normal's octahedral v as 0.5 + v / 2). The
#                      smooth normal (shared by every vertex at a position,
#                      across the low-poly mesh's hard edges) is what his
#                      aura swells along.
#     2  indices u16   a = count
#     3  a loop        a = frames, b = loop index (0 hang), c = keys per
#                      second; per frame, per joint, the skin matrix's top
#                      three rows (12 f32)
#     4  placement     where the rig hangs in the scene: x, y, z (metres),
#                      its turn about Y (degrees); then the eyes' glow
#                      (linear rgb) and its strength

import json, math, struct, sys
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else 'Vetal.glb'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'vetal.bin'
LOOPS = ['VTL_Hang']
PARTS = {'Vetal_VC': 0.0, 'Vetal_VC_DoubleSided': 0.5, 'Vetal_Eyes_Glow': 1.0}
# His cloth, by the bones it hangs from: how freely each sways (more down
# each chain). Where the wind isn't painted, a vertex weighted to these is
# cloth, swaying as its bones say.
CLOTH_BONES = {'drape.0': 0.35, 'drape.1': 0.65, 'drape.2': 1.0, 'sleeve.0': 0.45, 'sleeve.1': 0.85,
               'sash': 0.75, 'hem.L': 0.6, 'hem.R': 0.6}

data = open(SRC, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
BIN = 20 + jlen + 8
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
DTYPE = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}
NORM = {5121: 255.0, 5123: 65535.0}


def accessor(i):
    a = gltf['accessors'][i]
    bv = gltf['bufferViews'][a['bufferView']]
    n = NCOMP[a['type']]
    off = BIN + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    arr = np.frombuffer(data, DTYPE[a['componentType']], a['count'] * n, off).reshape(a['count'], n)
    if a.get('normalized') and a['componentType'] in NORM:
        return arr.astype(float) / NORM[a['componentType']]
    return arr


# ---------------------------------------------------------------------------
# Skeleton (as in export_king.py)

nodes = gltf['nodes']
parent = {}
for i, n in enumerate(nodes):
    for c in n.get('children', []):
        parent[c] = i


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def trs(t, r, s):
    m = np.eye(4)
    m[:3, :3] = quat_mat(r) * np.asarray(s)[None, :]
    m[:3, 3] = t
    return m


def rest(i):
    n = nodes[i]
    return [np.array(n.get('translation', [0, 0, 0]), float),
            np.array(n.get('rotation', [0, 0, 0, 1]), float),
            np.array(n.get('scale', [1, 1, 1]), float)]


def slerp(a, b, k):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        q = a + (b - a) * k
    else:
        th = np.arccos(d)
        q = (np.sin((1 - k) * th) * a + np.sin(k * th) * b) / np.sin(th)
    return q / np.linalg.norm(q)


skin = gltf['skins'][0]
joints = skin['joints']
ibm = accessor(skin['inverseBindMatrices']).astype(float).reshape(-1, 4, 4).transpose(0, 2, 1)


def rest_world(i):
    m = trs(*rest(i))
    return rest_world(parent[i]) @ m if i in parent else m


# The rig's placement (where he hangs from the branch), taken off.
root = joints[0]
while root in parent:
    root = parent[root]
R = rest_world(root)
Rinv = np.linalg.inv(R)
turn = math.degrees(math.atan2(R[0, 2], R[2, 2]))
print(f'rig root {nodes[root]["name"]}: hangs at {R[:3, 3].round(3)}, turned {turn:.1f} deg; taken off')

# ---------------------------------------------------------------------------
# Loops: every key, each joint's skin matrix

loops = []
for name in LOOPS:
    anim = next(a for a in gltf['animations'] if a['name'] == name)
    channels = []
    times = set()
    for c in anim['channels']:
        s = anim['samplers'][c['sampler']]
        if c['target']['path'] == 'weights':
            continue
        t = accessor(s['input'])[:, 0].astype(float)
        v = accessor(s['output']).astype(float)
        interp = s.get('interpolation', 'LINEAR')
        if interp == 'CUBICSPLINE':
            # In-tangent, value, out-tangent per key: the values, resampled
            # below on a smooth curve through them (the keys are sparse).
            v = v.reshape(len(t), 3, -1)[:, 1]
            interp = 'SMOOTH'
        if c['target']['path'] == 'rotation':
            # Each key on the same side as the one before, so the curve
            # takes the short way round.
            for k in range(1, len(v)):
                if np.dot(v[k], v[k - 1]) < 0:
                    v[k] = -v[k]
        channels.append((c['target']['node'], c['target']['path'], interp, t, v))
        times.update(np.round(t, 5).tolist())
    span = (min(times), max(times))
    fps = 24.0
    times = list(np.linspace(span[0], span[1], int(round((span[1] - span[0]) * fps)) + 1))
    frames = []
    for time in times:
        local = {i: rest(i) for i in range(len(nodes))}
        for node, path, interp, t, v in channels:
            slot = {'translation': 0, 'rotation': 1, 'scale': 2}[path]
            if time <= t[0]:
                val = v[0]
            elif time >= t[-1]:
                val = v[-1]
            else:
                k = int(np.searchsorted(t, time, side='right')) - 1
                f = (time - t[k]) / (t[k + 1] - t[k])
                if interp == 'STEP':
                    val = v[k]
                elif interp == 'SMOOTH':
                    # Catmull-Rom through the keys either side.
                    p0, p1 = v[max(k - 1, 0)], v[k]
                    p2, p3 = v[k + 1], v[min(k + 2, len(v) - 1)]
                    val = 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                                 + (3 * p1 - p0 - 3 * p2 + p3) * f ** 3)
                    if path == 'rotation':
                        val = val / np.linalg.norm(val)
                elif path == 'rotation':
                    val = slerp(v[k], v[k + 1], f)
                else:
                    val = v[k] + (v[k + 1] - v[k]) * f
            local[node][slot] = np.array(val, float)
        world = {}

        def world_of(i):
            if i not in world:
                m = trs(*local[i])
                world[i] = world_of(parent[i]) @ m if i in parent else m
            return world[i]
        mats = np.stack([Rinv @ world_of(j) @ ibm[k] @ R for k, j in enumerate(joints)])
        frames.append(mats[:, :3, :].astype('<f4'))
    loops.append((np.stack(frames), fps))
    print(f'{name}: {len(frames)} keys at {fps:.2f}/s ({times[-1] - times[0]:.2f}s)')

# ---------------------------------------------------------------------------
# The body: every part in one vertex buffer

body = next(n for n in nodes if 'mesh' in n and 'skin' in n)
vbs, ibs = [], []
base = 0
eye_glow = (1.0, 0.06, 0.02, 4.0)
for prim in gltf['meshes'][body['mesh']]['primitives']:
    at = prim['attributes']
    mat = gltf['materials'][prim['material']]
    part = PARTS.get(mat['name'], 0.0)
    pos = accessor(at['POSITION']).astype(float)
    nrm = accessor(at['NORMAL']).astype(float)
    n = len(pos)
    p = (pos @ Rinv[:3, :3].T + Rinv[:3, 3]).astype('<f4')
    d = nrm @ Rinv[:3, :3].T
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
    col = accessor(at['COLOR_0']).astype(float)[:, :3] if 'COLOR_0' in at else np.ones((n, 3))
    if part == 1.0:
        e = mat.get('emissiveFactor', [1, 0.06, 0.02])
        strength = mat.get('extensions', {}).get('KHR_materials_emissive_strength', {}).get('emissiveStrength', 1.0)
        eye_glow = (e[0], e[1], e[2], strength)
        col = np.tile(np.array(e, float), (n, 1))
    wts = accessor(at['WEIGHTS_0']).astype(float)
    if wts.max() > 1.5:
        wts /= 255.0
    wts /= np.maximum(wts.sum(1, keepdims=True), 1e-6)
    w8 = np.round(wts * 255).astype(int)
    # Each vertex's weights sum to exactly 255: the rounding goes to its
    # heaviest bone.
    w8[np.arange(n), w8.argmax(1)] += 255 - w8.sum(1)
    wind = accessor(at['_WIND']).astype(float) if '_WIND' in at else np.zeros((n, 3))
    # Cloth the paint left still: swaying as its cloth bones say.
    names = [nodes[j]['name'] for j in joints]
    level = np.array([CLOTH_BONES.get(nm, 0.0) for nm in names])
    jj = accessor(at['JOINTS_0']).astype(int)
    cloth = (wts * level[np.clip(jj, 0, len(level) - 1)]).sum(1)
    free = (wind[:, 0] <= 0.01) & (cloth > 0.05) & (part < 1.0)
    wind[free, 0] = np.clip(cloth[free], 0, 1)
    wind[free, 2] = 2
    if free.any():
        print(f'  cloth from its bones: {free.sum()} vertices, sway up to {cloth[free].max():.2f}')
    vb = np.zeros(n, dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('c', 'u1', 4), ('j', 'u1', 4), ('w', 'u1', 4), ('wind', 'u1', 4)])
    vb['p'] = p
    vb['n'][:, :3] = np.round(d * 127)
    vb['c'][:, :3] = np.round(np.clip(col, 0, 1) ** (1 / 2.2) * 255)
    vb['c'][:, 3] = round(part * 255)
    vb['j'] = accessor(at['JOINTS_0']).astype('u1')
    vb['w'] = np.clip(w8, 0, 255)
    vb['wind'][:, 0] = np.round(np.clip(wind[:, 0], 0, 1) * 255)
    vb['wind'][:, 1] = np.round(np.clip(wind[:, 1], 0, 1) * 255)
    vb['wind'][:, 2] = np.round(np.clip(wind[:, 2] / 4, 0, 1) * 255)
    vbs.append(vb)
    ibs.append(accessor(prim['indices'])[:, 0].astype(np.int64) + base)
    base += n
    print(f'{mat["name"]}: {n} vertices, {len(ibs[-1]) // 3} triangles')
vb = np.concatenate(vbs)
idx = np.concatenate(ibs).astype('<u2')

# The smooth normal: every vertex at a position (to the millimetre) shares
# their normals' average; where they cancel (both sides of a hair card),
# the vertex keeps its own.
_, weld = np.unique(np.round(vb['p'], 3), axis=0, return_inverse=True)
weld = weld.reshape(-1)
own = vb['n'][:, :3].astype(float) / 127
acc = np.zeros((weld.max() + 1, 3))
np.add.at(acc, weld, own)
smooth = acc[weld]
length = np.linalg.norm(smooth, axis=1, keepdims=True)
smooth = np.where(length > 0.3, smooth / np.maximum(length, 1e-6), own)
# Octahedral encoding, two numbers in -1..1.
o = smooth / np.maximum(np.abs(smooth).sum(1, keepdims=True), 1e-6)
ou, ov = o[:, 0].copy(), o[:, 2].copy()
low = o[:, 1] < 0
ou[low], ov[low] = (1 - np.abs(o[low, 2])) * np.sign(o[low, 0] + 1e-9), (1 - np.abs(o[low, 0])) * np.sign(o[low, 2] + 1e-9)
vb['n'][:, 3] = np.round(np.clip(ou, -1, 1) * 127)
vb['wind'][:, 3] = np.round((np.clip(ov, -1, 1) * 0.5 + 0.5) * 255)
print(f'smooth normals: {len(acc)} positions for {len(vb)} vertices')
assert len(vb) < 65536
lo, hi = vb['p'].min(0), vb['p'].max(0)
print(f'body: {len(vb)} vertices, {len(idx) // 3} triangles, {len(joints)} bones; '
      f'x {lo[0]:.2f}..{hi[0]:.2f}, y {lo[1]:.2f}..{hi[1]:.2f}, z {lo[2]:.2f}..{hi[2]:.2f}')

# ---------------------------------------------------------------------------
# Write

blobs = []
sections = []


def add(kind, payload, a=0, b=0, c=0.0, d=0.0, e=0):
    blobs.append(payload)
    sections.append([kind, len(payload), a, b, c, d, e])


add(1, vb.tobytes(), len(vb))
add(2, idx.tobytes(), len(idx))
for k, (frames, fps) in enumerate(loops):
    add(3, frames.tobytes(), len(frames), k, fps)
place = np.array([*R[:3, 3], turn, *eye_glow], '<f4')
add(4, place.tobytes())

HEADER = 16
ENTRY = 32
offset = HEADER + ENTRY * len(sections)
out = bytearray(struct.pack('<4sIII', b'VVTL', 1, len(sections), len(joints)))
body_bytes = bytearray()
for (kind, length, a, b, c, d, e), payload in zip(sections, blobs):
    pad = (-offset - len(body_bytes)) % 4
    body_bytes += b'\0' * pad
    out += struct.pack('<IIIIIffI', kind, offset + len(body_bytes), length, a, b, c, d, e)
    body_bytes += payload
out += body_bytes
open(OUT, 'wb').write(out)
print(f'{OUT}: {len(out) / 1e6:.2f} MB, {len(sections)} sections')
