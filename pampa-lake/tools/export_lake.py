# Packs Pampa_Sarovar_Scene.glb into lake.bin, the blob the Lake node script
# draws on the GPU. Plain Python and numpy, no Blender:
#
#   python3 tools/export_lake.py Pampa_Sarovar_Scene.glb lake.bin
#
# The file is a table of sections:
#
#   header   'PMPA' u32 | version u32 (3) | section count u32 | 0
#   section  kind | part << 8, vertexCount, indexCount, vbOffset, vbLength, ibOffset,
#            ibLength, template (8 x u32)
#
# Kinds: 1 the land (every opaque and double-sided mesh, merged), 2 the
# water, 3 the ripple rings. 24 bytes a vertex:
#   position f32x3 | normal snorm8x4 | colour unorm8x4 (sRGB, alpha) |
#   wind unorm8x4 (weight, phase, group / 255, mesh / 255)
# Indices are u16: each mesh is cut into chunks of at most 65535 vertices,
# one section a chunk.
#
# Kind 4 is a template mesh from Shishupalgarh (a leaf, a grass clump, a
# small flower, a leafy clump, a bloom), 28 bytes a vertex:
#   position f32x3 | normal f32x3 | bend f32 (0 at the root, 1 at the tip;
#   below 0 a bloom's stem and leaves)
# with u16 indices. Kind 5 is the instances of one (tools/plant.py), its
# template's id in the last word; vertexCount is how many, 20 bytes each:
#   position f16x3, scale f16 | x axis snorm8x3, random | y axis snorm8x3,
#   random | kind (lake.wgsl), ground light, 0, 0 (unorm8x4)

import json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plant
import terrain_grid

src = sys.argv[1] if len(sys.argv) > 1 else 'Pampa_Sarovar_Scene.glb'
out = sys.argv[2] if len(sys.argv) > 2 else 'lake.bin'

# Mesh ids, for the shader (wind.w * 255).
MESHES = ['Terrain', 'Hills', 'Forest_Far', 'Canopy', 'Trunks', 'Bushes', 'Grass', 'Vines',
          'Fallen_Flowers', 'Lotus_Pads', 'Lotus_Flowers', 'Birds', 'Waterfall_Caves',
          'Water', 'Water_Ripples', 'Water_Glints']
KIND = {'Water': 2, 'Water_Ripples': 3, 'Water_Glints': 3}

data = open(src, 'rb').read()
jlen = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + jlen])
bin_off = 20 + jlen + 8
DT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def accessor(i):
    a = gltf['accessors'][i]
    v = gltf['bufferViews'][a['bufferView']]
    dt = np.dtype(DT[a['componentType']])
    n = WIDTH[a['type']]
    start = bin_off + v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', dt.itemsize * n)
    raw = np.frombuffer(data, np.uint8, count=stride * (a['count'] - 1) + dt.itemsize * n, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, (a['count'], dt.itemsize * n), (stride, 1))
    out = np.ascontiguousarray(rows).view(dt).reshape(a['count'], n).astype(np.float64)
    if a.get('normalized') or (a['componentType'] in (5121, 5123) and n > 1):
        out /= float(np.iinfo(dt).max)
    return out


def node_matrix(n):
    m = np.eye(4)
    if 'matrix' in n:
        return np.array(n['matrix']).reshape(4, 4).T
    t, r, s = n.get('translation', [0, 0, 0]), n.get('rotation', [0, 0, 0, 1]), n.get('scale', [1, 1, 1])
    x, y, z, w = r
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
                  [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
                  [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = R * np.array(s)
    m[:3, 3] = t
    return m


groups = {1: [], 2: [], 3: []}
for node in gltf['nodes']:
    if 'mesh' not in node:
        continue
    mesh = gltf['meshes'][node['mesh']]
    name = mesh['name']
    M = node_matrix(node)
    for prim in mesh['primitives']:
        at = prim['attributes']
        pos = accessor(at['POSITION'])
        nrm = accessor(at['NORMAL'])
        col = accessor(at['COLOR_0'])
        wind = accessor(at['_WIND'])
        idx = accessor(prim['indices'])[:, 0].astype(np.uint32)
        pos = pos @ M[:3, :3].T + M[:3, 3]
        nrm = nrm @ M[:3, :3].T
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        if col.shape[1] == 3:
            col = np.hstack([col, np.ones((len(col), 1))])
        # Linear in the GLB; stored sRGB-ish so the darks keep their steps.
        rgb = np.clip(col[:, :3], 0, None) ** (1 / 2.2)
        groups[KIND.get(name, 1)].append((name, pos, nrm, rgb, col[:, 3], wind, idx))
        print(f'{name:16s} {len(pos):7d} v {len(idx) // 3:7d} tris  wind groups {sorted(set(wind[:, 2].round().astype(int)))}')

CHUNK = 65535


def chunks(idx):
    """Cut one mesh's triangles into runs that use at most CHUNK vertices,
    so each draws with u16 indices: (original vertex ids, local indices)."""
    tris = idx.reshape(-1, 3)
    out, start = [], 0
    while start < len(tris):
        lo, hi = start + 1, len(tris)
        # The longest run from start whose distinct vertices fit.
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if len(np.unique(tris[start:mid])) <= CHUNK:
                lo = mid
            else:
                hi = mid - 1
        used, local = np.unique(tris[start:lo], return_inverse=True)
        out.append((used, local.reshape(-1).astype('<u2')))
        start = lo
    return out


meshes = []  # (kind, count, indexCount, vb, ib, template)
for kind in (1, 2, 3):
    for name, pos, nrm, rgb, alpha, wind, idx in groups[kind]:
        n = len(pos)
        v = np.zeros(n, dtype=[('p', '<f4', 3), ('n', 'i1', 4), ('c', 'u1', 4), ('w', 'u1', 4)])
        v['p'] = pos
        v['n'][:, :3] = np.clip(np.round(nrm * 127), -127, 127)
        v['c'][:, :3] = np.clip(np.round(rgb * 255), 0, 255)
        v['c'][:, 3] = np.clip(np.round(alpha * 255), 0, 255)
        v['w'][:, 0] = np.clip(np.round(wind[:, 0] * 255), 0, 255)
        v['w'][:, 1] = np.clip(np.round((wind[:, 1] % 1.0) * 255), 0, 255)
        v['w'][:, 2] = np.clip(np.round(wind[:, 2]), 0, 255)
        v['w'][:, 3] = MESHES.index(name)
        for used, local in chunks(idx):
            meshes.append((kind, len(used), len(local), v[used].tobytes(), local.tobytes(), 0))

# The meadow's plants.
named = {g[0]: g for k in groups for g in groups[k]}
grid = terrain_grid.build(named['Terrain'], named['Water'])
print('planting')
planted = plant.plant(grid)
extra = []  # (kind, count, indexCount, vb, ib, template)
for tid, (n, ic, vb, ib) in sorted(plant.templates().items()):
    extra.append((4, n, ic, vb, ib, tid))
for kind, tid, count, data in planted:
    extra.append((5, count, 0, data, b'', tid))
# The editor refuses a blob of 10 MB or more, so the sections are packed
# into parts: lake.bin (with the table), then lake2.bin, lake3.bin...
LIMIT = 9_500_000
sections = meshes + extra
header = 16 + 32 * len(sections)
parts, table = [bytearray(header)], []
for kind, n, ic, vb, ib, tid in sections:
    vb, ib = vb + b'\0' * (-len(vb) % 4), ib + b'\0' * (-len(ib) % 4)
    if len(parts[-1]) + len(vb) + len(ib) > LIMIT:
        parts.append(bytearray())
    p = parts[-1]
    table.append((kind | (len(parts) - 1) << 8, n, ic, len(p), len(vb), len(p) + len(vb), len(ib), tid))
    p += vb + ib
parts[0][:header] = b'PMPA' + struct.pack('<3I', 3, len(table), 0) + b''.join(struct.pack('<8I', *t) for t in table)
stem, ext = os.path.splitext(out)
for n, p in enumerate(parts):
    path = out if n == 0 else f'{stem}{n + 1}{ext}'
    open(path, 'wb').write(p)
    print(path, len(p), 'bytes')
