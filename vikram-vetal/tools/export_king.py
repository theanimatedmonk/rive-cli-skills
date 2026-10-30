# Exports Vikram_King.glb (King Vikram, rigged in Blender) to king.bin for
# the King node script (../king/King.luau).
#
#   python3 tools/export_king.py [Vikram_King.glb] [king.bin]
#
# The GLB is his skinned body (VKK_Body_LP) with a painted texture set (base
# colour, normal, roughness/metal), his bow (VKK_Bow: limbs, gold fittings
# and the string, on bow bones of the same rig, with a shape key for the
# drawn string) and four in-place clips, VKK_Idle, VKK_Walk, VKK_Draw and
# VKK_Shoot (the draw, the loose and the follow-through, played once); for
# the game, the shot in parts: VKK_AimHold (a loop at full draw) and
# VKK_Release (the loose and the follow-through), and three held full-draw
# poses that differ only in how the upper body pitches, VKK_Aim_Level,
# VKK_Aim_Up (+45 degrees) and VKK_Aim_Down (-35), for aiming.
# The skinning is baked here: for every key of each loop, each bone's skin
# matrix (its posed world matrix times its inverse bind), so the script only
# blends matrices and the GPU skins. The rig may be placed anywhere in the
# Blender scene; that placement is taken off, so he stands at the origin.
#
# Format (little-endian):
#   header   'VKNG' | version u32 (1) | section count u32 | joint count u32
#   section  8 words: kind u32, offset u32, length u32, a u32, b u32,
#            c f32, d f32, e u32
#     1  vertices      a = count
#     2  indices u16   a = count
#     3  a loop        a = frames, b = loop index (0 idle, 1 walk, 2 draw, 3 shoot),
#                      c = keys per second; per frame, per joint, the skin
#                      matrix's top three rows (12 f32)
#     5  shape key     per vertex, 20 bytes: position delta f32x3, normal
#                      delta / 2 snorm8x4 (zero but for the bow); then the
#                      wind painted on the body (its _WIND attribute) as
#                      unorm8x4: how much it sways, its phase, what it is
#                      / 2 (0 skin, 1 hair, 2 cloth), 0
#     6  a loop's key  a = frames, b = loop index; per frame the bow's shape
#                      key weight (f32): how far the string is drawn
#     7  the bow       a = samples; per sample 14 f32 (bind position, shape
#                      key delta, joints, weights): points along the limbs
#                      from the lower tip to the upper, then the nock (the
#                      string's middle); then the limbs' axis (origin xyz,
#                      direction xyz, length), and the grip's and the
#                      nock's joints (for the release: the string returns to
#                      the grip)
#     4  the head      a = head joint; 21 f32: the eyes' centres (left,
#                      right), the irises' centres, the earrings' gems (all
#                      in bind pose), and the eyelids' colour (linear rgb)
#     10+t  a mip of texture t (0 base colour, 1 normal, 2 roughness/metal)
#                      as a JPEG: a = width, b = height, e = mip level
# Vertices, 32 bytes:
#   position f32x3 | normal snorm8x4 | uv f32x2 | joints u8x4 |
#   weights unorm8x4
# The earrings (made here: gold jhumkas with a gem drop, on the head bone)
# follow the body's vertices, marked by uv.x = -1 (uv.y: 0 gold, 1 gem);
# then the bow, marked by uv.x = -2 (uv.y: 0 limbs, 1 gold, 2 string).

import io, json, struct, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else 'Vikram_King.glb'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'king.bin'
LOOPS = ['VKK_Idle', 'VKK_Walk', 'VKK_Draw', 'VKK_Shoot', 'VKK_AimHold', 'VKK_Release',
         'VKK_Aim_Level', 'VKK_Aim_Up', 'VKK_Aim_Down']
BOW_PARTS = {'VKK_BowLimb': 0, 'VKK_BowGold': 1, 'VKK_BowString': 2}
BOW_SAMPLES = 13
# Where his face is, in bind pose (metres; measured off the textured head).
# The eyes: the almond's centre, and the iris's.
EYES = [(-0.0428, 1.831, 0.112), (0.0329, 1.830, 0.112)]
IRISES = [(-0.0447, 1.8319, 0.114), (0.0310, 1.8324, 0.114)]
# The ear lobes, where the earrings hang from.
LOBES = [(-0.087, 1.787, 0.012), (0.082, 1.787, 0.012)]
# Texture sizes shipped (at most; never larger than the GLB's): the base
# colour carries the face and the trims, the others only shading.
TEXTURES = [('VKK_basecolor', 2048, 88), ('VKK_normal', 1024, 90), ('VKK_rm', 1024, 85)]

data = open(SRC, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
BIN = 20 + jlen + 8
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
DTYPE = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}


def accessor(i):
    a = gltf['accessors'][i]
    bv = gltf['bufferViews'][a['bufferView']]
    n = NCOMP[a['type']]
    off = BIN + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    arr = np.frombuffer(data, DTYPE[a['componentType']], a['count'] * n, off)
    return arr.reshape(a['count'], n)


# ---------------------------------------------------------------------------
# Skeleton

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
ibm = accessor(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)


def rest_world(i):
    m = trs(*rest(i))
    return rest_world(parent[i]) @ m if i in parent else m


# The rig's placement in the scene (the root above the bones), taken off so
# he stands at the origin: skin matrices become R^-1 world IBM R, and the
# bind pose is brought into the rig's own space by R^-1.
root = joints[0]
while root in parent:
    root = parent[root]
R = rest_world(root)
Rinv = np.linalg.inv(R)
print(f'rig root {nodes[root]["name"]}: placed at {R[:3, 3].round(3)}, taken off')
bow_node = next((i for i, n in enumerate(nodes) if n.get('name') == 'VKK_Bow'), None)

# ---------------------------------------------------------------------------
# Loops: every key, each joint's skin matrix

loops = []
for name in LOOPS:
    anim = next(a for a in gltf['animations'] if a['name'] == name)
    channels = []
    weight_track = None
    times = set()
    for c in anim['channels']:
        s = anim['samplers'][c['sampler']]
        t = accessor(s['input'])[:, 0]
        v = accessor(s['output']).astype(float)
        if c['target']['path'] == 'weights':
            if c['target']['node'] == bow_node:
                weight_track = (t, v[:, 0])
            continue
        channels.append((c['target']['node'], c['target']['path'], s.get('interpolation', 'LINEAR'), t, v))
        times.update(np.round(t, 5).tolist())
    times = sorted(times)
    fps = (len(times) - 1) / (times[-1] - times[0])
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
    if weight_track is not None:
        keyw = np.interp(times, weight_track[0], weight_track[1]).astype('<f4')
    else:
        keyw = np.zeros(len(times), '<f4')
    loops.append((np.stack(frames), fps, keyw))
    print(f'{name}: {len(frames)} keys at {fps:.2f}/s ({times[-1] - times[0]:.2f}s)')

# ---------------------------------------------------------------------------
# The body



def local_points(p):
    return (p @ Rinv[:3, :3].T + Rinv[:3, 3]).astype('<f4')


def local_dirs(n):
    return n @ Rinv[:3, :3].T


body = next(n for n in nodes if 'mesh' in n and 'skin' in n and 'Body' in n.get('name', ''))
prim = gltf['meshes'][body['mesh']]['primitives'][0]
at = prim['attributes']
pos = local_points(accessor(at['POSITION']).astype(float))
nrm = local_dirs(accessor(at['NORMAL']).astype(float))
uv = accessor(at['TEXCOORD_0']).astype(float)
jnt = accessor(at['JOINTS_0']).astype('u1')
wts = accessor(at['WEIGHTS_0']).astype(float)
idx = accessor(prim['indices'])[:, 0].astype('<u2')
nv_body_tris = len(idx)
assert len(pos) < 65536

wts = wts / np.maximum(wts.sum(1, keepdims=True), 1e-6)
w8 = np.round(wts * 255).astype(int)
# Keep each vertex's weights summing to exactly 255: the rounding error goes
# to its heaviest bone.
w8[np.arange(len(w8)), w8.argmax(1)] += 255 - w8.sum(1)
nrm = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)

nv = len(pos)
vb = np.zeros(nv, dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('uv', '<f4', 2), ('j', 'u1', 4), ('w', 'u1', 4)])
vb['p'] = pos
vb['n'][:, :3] = np.round(nrm * 127)
vb['uv'] = uv
vb['j'] = jnt
vb['w'] = np.clip(w8, 0, 255)

# The earrings: a stud at the lobe, a bell (a jhumka) under it and a gem
# hanging from the bell, turned on a lathe; all on the head.
head_joint = next(k for k, j in enumerate(joints) if nodes[j]['name'] == 'DEF-spine.006')
SEGMENTS = 18
# Heroic, larger than life: the profile below, times this.
EAR_SCALE = 1.5
# Profile from the top: (drop below the lobe, radius) in metres.
STUD = [(0.0, 0.0), (-0.002, 0.0028), (-0.0045, 0.0034), (-0.007, 0.0025), (-0.0085, 0.0012)]
BELL = [(-0.0085, 0.0012), (-0.010, 0.0035), (-0.013, 0.0075), (-0.017, 0.0105), (-0.0205, 0.0125),
        (-0.0225, 0.013), (-0.0228, 0.0105), (-0.0215, 0.006), (-0.0215, 0.0015)]
GEM = [(-0.0215, 0.0), (-0.0235, 0.0032), (-0.0265, 0.0048), (-0.0295, 0.0042), (-0.032, 0.002), (-0.0335, 0.0)]


def lathe(profile, at, part):
    pts = np.array(profile, float) * EAR_SCALE
    # Normals of the profile: perpendicular to each segment, averaged.
    tang = np.gradient(pts, axis=0)
    pn = np.stack([-tang[:, 0], tang[:, 1]], 1)  # (radial, up): outward
    pn /= np.maximum(np.linalg.norm(pn, axis=1, keepdims=True), 1e-9)
    verts, norms, tris = [], [], []
    for k in range(SEGMENTS):
        a = 2 * np.pi * k / SEGMENTS
        ca, sa = np.cos(a), np.sin(a)
        for (y, r), (nr, ny) in zip(pts, pn):
            verts.append((at[0] + r * ca, at[1] + y, at[2] + r * sa))
            norms.append((nr * ca, ny, nr * sa))
    n = len(pts)
    for k in range(SEGMENTS):
        k2 = (k + 1) % SEGMENTS
        for i in range(n - 1):
            a, b, c, d = k * n + i, k2 * n + i, k2 * n + i + 1, k * n + i + 1
            tris += [(a, b, c), (a, c, d)]
    return np.array(verts), np.array(norms), np.array(tris), part


ear_parts = []
gems = []
for lobe in LOBES:
    ear_parts += [lathe(STUD, lobe, 0), lathe(BELL, lobe, 0), lathe(GEM, lobe, 1)]
    gems.append((lobe[0], lobe[1] - 0.028 * EAR_SCALE, lobe[2]))
ear_vb = []
ear_ib = []
base = nv
for verts, norms, tris, part in ear_parts:
    e = np.zeros(len(verts), dtype=vb.dtype)
    e['p'] = verts
    norms = norms / np.maximum(np.linalg.norm(norms, axis=1, keepdims=True), 1e-9)
    e['n'][:, :3] = np.round(norms * 127)
    e['uv'] = (-1.0, float(part))
    e['j'][:, 0] = head_joint
    e['w'][:, 0] = 255
    # Counter-clockwise from outside, as the body's triangles are.
    ear_ib.append((tris + base).ravel())
    ear_vb.append(e)
    base += len(verts)
vb = np.concatenate([vb] + ear_vb)
idx = np.concatenate([idx] + [i.astype('<u2') for i in ear_ib]).astype('<u2')
assert len(vb) < 65536
head_info = EYES + IRISES + gems
print(f'earrings: {base - nv} vertices on {nodes[joints[head_joint]]["name"]}')
for lobe in LOBES:
    print(f'  lobe {lobe}: nearest skin {np.linalg.norm(pos - np.array(lobe), axis=1).min() * 1000:.1f} mm')


def weights8(w):
    w = w / np.maximum(w.sum(1, keepdims=True), 1e-6)
    q = np.round(w * 255).astype(int)
    q[np.arange(len(q)), q.argmax(1)] += 255 - q.sum(1)
    return np.clip(q, 0, 255)


# The bow: its parts after the earrings, with the drawn string's shape key.
morph = np.zeros(len(vb), dtype=[('d', '<f4', 3), ('n', 'i1', 4), ('wind', 'u1', 4)])
if '_WIND' in at:
    wind = accessor(at['_WIND']).astype(float)
    morph['wind'][:nv, 0] = np.round(np.clip(wind[:, 0], 0, 1) * 255)
    morph['wind'][:nv, 1] = np.round(np.clip(wind[:, 1], 0, 1) * 255)
    morph['wind'][:nv, 2] = np.round(np.clip(wind[:, 2] / 2, 0, 1) * 255)
    for rid, what in ((1, 'hair'), (2, 'cloth')):
        m = np.isclose(wind[:, 2], rid, atol=0.3)
        print(f'wind: {what} {m.sum()} vertices, sway up to {wind[m, 0].max():.2f}')
bow_vb, bow_ib, bow_morph = [], [], []
limb_pts, limb_delta, limb_j, limb_w = [], [], [], []
string_pts = None
if bow_node is not None:
    for bp in gltf['meshes'][nodes[bow_node]['mesh']]['primitives']:
        ba = bp['attributes']
        part = BOW_PARTS.get(gltf['materials'][bp['material']]['name'], 0)
        p = local_points(accessor(ba['POSITION']).astype(float))
        n = local_dirs(accessor(ba['NORMAL']).astype(float))
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
        tg = bp.get('targets', [{}])[0]
        dp = local_dirs(accessor(tg['POSITION']).astype(float)) if 'POSITION' in tg else np.zeros_like(p)
        dn = local_dirs(accessor(tg['NORMAL']).astype(float)) if 'NORMAL' in tg else np.zeros_like(p)
        jj = accessor(ba['JOINTS_0']).astype('u1')
        ww = accessor(ba['WEIGHTS_0']).astype(float)
        e = np.zeros(len(p), dtype=vb.dtype)
        e['p'] = p
        e['n'][:, :3] = np.round(n * 127)
        e['uv'] = (-2.0, float(part))
        e['j'] = jj
        e['w'] = weights8(ww)
        m = np.zeros(len(p), dtype=morph.dtype)
        m['d'] = dp
        m['n'][:, :3] = np.round(np.clip(dn / 2, -1, 1) * 127)
        bow_vb.append(e)
        bow_morph.append(m)
        bow_ib.append(accessor(bp['indices'])[:, 0].astype(np.int64) + base)
        base += len(p)
        if part == 2:
            string_pts = (p, dp, jj, ww)
        else:
            limb_pts.append(p)
            limb_delta.append(dp)
            limb_j.append(jj)
            limb_w.append(ww)
    vb = np.concatenate([vb] + bow_vb)
    morph = np.concatenate([morph] + bow_morph)
    idx = np.concatenate([idx] + [i.astype('<u2') for i in bow_ib]).astype('<u2')
    assert len(vb) < 65536
    print(f'bow: {sum(len(e) for e in bow_vb)} vertices in {len(bow_vb)} parts')

# Points along the bow, for its aura: the limbs' centre line in bins along
# their axis (lower tip to upper), then the nock.
bow_info = np.zeros(0, '<f4')
if limb_pts:
    lp = np.concatenate(limb_pts)
    ld = np.concatenate(limb_delta)
    lj = np.concatenate(limb_j)
    lw = np.concatenate(limb_w)
    centre = lp.mean(0)
    _, _, vt = np.linalg.svd(lp - centre, full_matrices=False)
    axis = vt[0] if vt[0][1] >= 0 else -vt[0]
    t = (lp - centre) @ axis
    lo_t, hi_t = t.min(), t.max()
    rows = []
    edges = np.linspace(lo_t, hi_t, BOW_SAMPLES + 1)
    for k in range(BOW_SAMPLES):
        m = (t >= edges[k]) & (t <= edges[k + 1])
        c = lp[m].mean(0)
        near = np.argmin(np.linalg.norm(lp[m] - c, axis=1))
        jw = lw[m][near] / max(lw[m][near].sum(), 1e-6)
        rows.append(np.concatenate([c, ld[m].mean(0), lj[m][near].astype(float), jw]))
    jnames = [nodes[j]['name'] for j in joints]
    grip_j = jnames.index('bow_grip') if 'bow_grip' in jnames else -1
    nock_j = jnames.index('bow_nock') if 'bow_nock' in jnames else -1
    if nock_j >= 0:
        # The nock is its own bone (at the string's middle): where it is in
        # the bind pose, moved wholly by it.
        at = (Rinv @ np.linalg.inv(ibm[nock_j]) @ np.array([0, 0, 0, 1.0]))[:3]
        rows.append(np.concatenate([at, np.zeros(3), [nock_j, 0, 0, 0], [1, 0, 0, 0]]))
    elif string_pts is not None:
        sp, sd, sj, sw = string_pts
        nock = np.argmax(np.linalg.norm(sd, axis=1))
        rows.append(np.concatenate([sp[nock], sd[nock], sj[nock].astype(float), sw[nock] / max(sw[nock].sum(), 1e-6)]))
    else:
        rows.append(rows[BOW_SAMPLES // 2])
    origin = centre + axis * lo_t
    bow_info = np.concatenate([np.array(rows).ravel(), origin, axis, [hi_t - lo_t, grip_j, nock_j]]).astype('<f4')
    print(f'bow axis: {axis.round(3)}, {hi_t - lo_t:.2f} m long, grip at {centre.round(3)}')

lo, hi = pos.min(0), pos.max(0)
print(f'body: {nv} vertices, {len(idx) // 3} triangles, {len(joints)} bones; '
      f'x {lo[0]:.2f}..{hi[0]:.2f}, y {lo[1]:.2f}..{hi[1]:.2f}, z {lo[2]:.2f}..{hi[2]:.2f}')

# ---------------------------------------------------------------------------
# Textures: a mip chain of JPEGs each

images = {im['name']: im for im in gltf['images']}
textures = []
for name, size, quality in TEXTURES:
    bv = gltf['bufferViews'][images[name]['bufferView']]
    raw = data[BIN + bv.get('byteOffset', 0):BIN + bv.get('byteOffset', 0) + bv['byteLength']]
    if name == 'VKK_basecolor':
        raw_base = raw
    img = Image.open(io.BytesIO(raw)).convert('RGB')
    size = min(size, img.size[0])
    img = img.resize((size, size), Image.LANCZOS)
    mips = []
    level = 0
    while True:
        out = io.BytesIO()
        img.save(out, 'JPEG', quality=quality, optimize=True)
        mips.append((img.size[0], img.size[1], level, out.getvalue()))
        if img.size[0] == 1:
            break
        img = img.resize((max(1, img.size[0] // 2), max(1, img.size[1] // 2)), Image.LANCZOS)
        level += 1
    textures.append(mips)
    print(f'{name}: {size}px, {len(mips)} mips, {sum(len(m[3]) for m in mips) / 1024:.0f} KB')

# ---------------------------------------------------------------------------
# Write

blobs = []
sections = []


def add(kind, payload, a=0, b=0, c=0.0, d=0.0, e=0):
    blobs.append(payload)
    sections.append([kind, len(payload), a, b, c, d, e])


add(1, vb.tobytes(), len(vb))
add(2, idx.tobytes(), len(idx))
for k, (frames, fps, keyw) in enumerate(loops):
    add(3, frames.tobytes(), len(frames), k, fps)
    add(6, keyw.tobytes(), len(keyw), k)
add(5, morph.tobytes(), len(morph))
if len(bow_info):
    add(7, bow_info.tobytes(), BOW_SAMPLES + 1)
# The eyelids' colour, for when he blinks: the painted skin just under each
# eye (above it, the lid is only lashes and the brow's shadow), sampled
# across the triangles there.
base_tex = np.asarray(Image.open(io.BytesIO(raw_base)).convert('RGB'), float) / 255
rng = np.random.default_rng(3)
tri = idx[:nv_body_tris].reshape(-1, 3)
samples = []
for _ in range(16):
    a, b = rng.random(len(tri)), rng.random(len(tri))
    flip = a + b > 1
    a[flip], b[flip] = 1 - a[flip], 1 - b[flip]
    w = np.stack([a, b, 1 - a - b], 1)
    p = (pos[tri] * w[:, :, None]).sum(1)
    t = (uv[tri] * w[:, :, None]).sum(1)
    for ex, ey, ez in EYES:
        m = (np.abs(p[:, 0] - ex) < 0.012) & (p[:, 1] > ey - 0.014) & (p[:, 1] < ey - 0.008) & (p[:, 2] > 0.08)
        px = np.clip((t[m] * (base_tex.shape[0] - 1)).astype(int), 0, base_tex.shape[0] - 1)
        samples.append(base_tex[px[:, 1], px[:, 0]])
lid = np.median(np.concatenate(samples), 0) ** 2.2
print(f'eyelids: linear {lid.round(3)}')
head_info = np.array(head_info + [tuple(lid)], '<f4').ravel()
add(4, head_info.tobytes(), head_joint)
for t, mips in enumerate(textures):
    for w, h, level, jpg in mips:
        add(10 + t, jpg, w, h, 0.0, 0.0, level)

HEADER = 16
ENTRY = 32
offset = HEADER + ENTRY * len(sections)
out = bytearray(struct.pack('<4sIII', b'VKNG', 1, len(sections), len(joints)))
body_bytes = bytearray()
for (kind, length, a, b, c, d, e), payload in zip(sections, blobs):
    pad = (-offset - len(body_bytes)) % 4
    body_bytes += b'\0' * pad
    out += struct.pack('<IIIIIffI', kind, offset + len(body_bytes), length, a, b, c, d, e)
    body_bytes += payload
out += body_bytes
open(OUT, 'wb').write(out)
print(f'{OUT}: {len(out) / 1e6:.2f} MB, {len(sections)} sections')
