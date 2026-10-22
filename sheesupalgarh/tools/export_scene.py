# Exports Shishupalgarh_Ruins.blend to ruins.bin, the blob the Ruins node
# script draws on the GPU.
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b Shishupalgarh_Ruins.blend \
#       --python tools/export_scene.py -- ruins.bin
#
# Everything is converted to Y-up (x, z, -y). The file is a table of sections:
#
#   header   'SHRN' u32 | version u32 (2) | section count u32
#   section  kind, count, indexCount, vbOffset, vbLength, ibOffset, ibLength, 0
#            (8 x u32), then its bounds min xyz, max xyz and 2 x 0 (8 x f32)
#
# Static meshes (kinds 1-8), 20 bytes a vertex:
#   position f32x3 | normal snorm8x4 | extra unorm8x4 (wind weight, random, path, grass)
# Templates (kinds 20-23), 28 bytes a vertex, drawn instanced:
#   position f32x3 | normal f32x3 | bend f32 (0 at the root, 1 at the tip)
# Leaf templates are simplified to a folded 7-vertex leaf shaped like the
# Blender one. Instances (kinds 30-36) come in sections per CELL x CELL
# metre tile, so the script can skip the tiles out of view; 16 bytes each:
#   position f16x3, scale f16 | x axis snorm8x3, random | y axis snorm8x3, random
# Indices are u16; static kinds come in chunks under 65536 vertices.

import bpy, bmesh, struct, sys, math, random
from mathutils import Matrix, Vector

out = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'ruins.bin'

STATIC = {1: 'stone', 2: 'rock', 3: 'clay', 4: 'ground', 5: 'groundFar', 6: 'bark', 7: 'vine', 8: 'flame'}
TEMPLATES = {20: 'Leaf_Bush', 21: 'Leaf_Creeper', 22: 'GrassClump', 23: 'Flower'}
# kind: (GN object, template kind, fraction kept)
INSTANCES = {
    30: ('Bush_Leaves', 20, 0.42),
    31: ('Creeper_Leaves', 21, 0.36),
    32: ('Tree_Leaves', 20, 0.55),
    33: ('Ground', 22, 0.8),
    34: ('Meadow_Flowers', 23, 1.0),
    35: ('Creeper_Flowers', 23, 1.0),
    36: ('Bush_Flowers', 23, 1.0),
}
CELL = 6.0
DECIMATE = {'Pillar': 0.55, 'Trunks': 0.45, 'Vines': 0.4, 'Ground': 0.4}

C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender Z-up -> Y-up
CI = C.inverted()


def yup(v):
    return (v[0], v[2], -v[1])


def snorm(x):
    return max(-127, min(127, round(x * 127)))


def unorm(x):
    return max(0, min(255, round(x * 255)))


def static_kind(o):
    n = o.name
    if n.startswith(('Pillar', 'Block')):
        return 1
    if n.startswith('Rock'):
        return 2
    if n.startswith(('Pot', 'Diya')):
        return 3
    if n == 'Ground':
        return 4
    if n == 'Ground_Far':
        return 5
    if n == 'Trunks':
        return 6
    if n == 'Vines':
        return 7
    if n == 'Flame':
        return 8
    return None


def evaluated_mesh(o, depsgraph):
    """World-space mesh of o after its modifiers, decimated if listed."""
    ratio = next((r for k, r in DECIMATE.items() if o.name.startswith(k) and o.name != 'Ground_Far'), None)
    ev = o.evaluated_get(depsgraph)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=depsgraph)
    me.transform(o.matrix_world)
    if ratio:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        tmp = bpy.data.objects.new('tmp', me)
        bpy.context.scene.collection.objects.link(tmp)
        mod = tmp.modifiers.new('dec', 'DECIMATE')
        mod.ratio = ratio
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        bpy.data.objects.remove(tmp)
        me = me2
    return me


def mesh_buffers(me, extra_fn, local=False, bend_fn=None):
    """Splits corners by normal; returns (vertex bytes, index bytes, count, tris)."""
    me.calc_loop_triangles()
    normals = me.corner_normals
    verts = {}
    vb = bytearray()
    ib = bytearray()
    for tri in me.loop_triangles:
        ids = []
        for li in tri.loops:
            vi = me.loops[li].vertex_index
            n = normals[li].vector if local else me.vertices[vi].normal
            key = (vi, round(n.x, 2), round(n.y, 2), round(n.z, 2)) if local else vi
            idx = verts.get(key)
            if idx is None:
                idx = len(verts)
                verts[key] = idx
                p = yup(me.vertices[vi].co)
                nn = yup(n)
                if local:
                    vb += struct.pack('<7f', *p, *nn, bend_fn(me.vertices[vi].co))
                else:
                    e = extra_fn(vi, me.vertices[vi].co)
                    vb += struct.pack('<3f4b4B', *p, snorm(nn[0]), snorm(nn[1]), snorm(nn[2]), 0, *e)
            ids.append(idx)
        # Blender's winding stays front-facing after the proper rotation.
        ib += struct.pack('<3H', *ids)
    return bytes(vb), bytes(ib), len(verts), len(me.loop_triangles)


depsgraph = bpy.context.evaluated_depsgraph_get()
rng = random.Random(7)
sections = []  # (kind, count, indexCount, vb, ib)

# --- static meshes, merged per kind ------------------------------------------
merged = []  # [kind, vb, ib, verts, tris], each under 65536 vertices
for o in bpy.context.scene.objects:
    if o.type not in ('MESH', 'CURVE'):
        continue
    kind = static_kind(o)
    if kind is None:
        continue
    me = evaluated_mesh(o, depsgraph)
    seed = rng.random()
    attrs = me.attributes
    path = attrs.get('path')
    grass = attrs.get('grass')
    zmin = min((v.co.z for v in me.vertices), default=0)
    zmax = max((v.co.z for v in me.vertices), default=1)

    def extra(vi, co, kind=kind, seed=seed, path=path, grass=grass, zmin=zmin, zmax=zmax):
        wind = 0.0
        if kind == 6:  # trunks bend a little with height
            wind = max(0.0, min(1.0, (co.z - 0.3) / 5.0)) ** 2 * 0.35
        p = path.data[vi].value if path else 0.0
        g = grass.data[vi].value if grass else 0.0
        return (unorm(wind), unorm(seed), unorm(p), unorm(g))

    vb, ib, n, t = mesh_buffers(me, extra)
    assert n < 65536, o.name
    m = next((m for m in merged if m[0] == kind and m[3] + n < 65536), None)
    if m is None:
        m = [kind, bytearray(), bytearray(), 0, 0]
        merged.append(m)
    base = m[3]
    m[1] += vb
    m[2] += b''.join(struct.pack('<H', i + base) for i in struct.unpack(f'<{len(ib)//2}H', ib))
    m[3] += n
    m[4] += t
    bpy.data.meshes.remove(me)
for kind, vb, ib, n, t in merged:
    sections.append((kind, n, t * 3, bytes(vb), bytes(ib)))
    print(f'static {STATIC[kind]:10s} verts={n:7d} tris={t:7d}')

# --- templates ---------------------------------------------------------------
def simple_leaf(me):
    """A folded 7-vertex leaf with the outline of `me` (Y-up, tip toward -Z)."""
    pts = [yup(v.co) for v in me.vertices]
    length = -min(p[2] for p in pts)

    def band(t):
        near = [p for p in pts if abs(-p[2] / length - t) < 0.12] or pts
        return max(abs(p[0]) for p in near), sum(p[1] for p in near) / len(near)

    w1, y1 = band(0.35)
    w2, y2 = band(0.7)
    _, ytip = band(1.0)
    fold = length * 0.08
    verts = [
        (0, 0, 0), (-w1, y1, -0.35 * length), (w1, y1, -0.35 * length),
        (-w2 * 0.9, y2, -0.7 * length), (w2 * 0.9, y2, -0.7 * length),
        (0, ytip, -length), (0, (y1 + y2) / 2 + fold, -0.5 * length),
    ]
    normals = [(0, 1, 0), (-0.35, 0.94, 0), (0.35, 0.94, 0), (-0.35, 0.94, 0), (0.35, 0.94, 0), (0, 1, 0), (0, 1, 0)]
    tris = [(0, 1, 6), (0, 6, 2), (1, 3, 6), (6, 4, 2), (3, 5, 6), (6, 5, 4)]
    vb = bytearray()
    for v, n in zip(verts, normals):
        vb += struct.pack('<7f', *v, *n, math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) / length)
    ib = bytearray()
    for a, b, c in tris:
        e1 = Vector(verts[b]) - Vector(verts[a])
        e2 = Vector(verts[c]) - Vector(verts[a])
        if e1.cross(e2).y < 0:
            b, c = c, b
        ib += struct.pack('<3H', a, b, c)
    return bytes(vb), bytes(ib), len(verts), len(tris)


for kind, name in TEMPLATES.items():
    o = bpy.data.objects[name]
    me = o.data
    if name.startswith('Leaf'):
        vb, ib, n, t = simple_leaf(me)
        sections.append((kind, n, t * 3, vb, ib))
        print(f'template {name:12s} verts={n} tris={t} (simplified)')
        continue
    cos = [v.co for v in me.vertices]
    if name == 'GrassClump':
        top = max(c.z for c in cos) or 1
        bend = lambda co, top=top: max(0.0, co.z / top)
    else:
        far = max(c.length for c in cos) or 1
        bend = lambda co, far=far: co.length / far
    vb, ib, n, t = mesh_buffers(me, None, local=True, bend_fn=bend)
    sections.append((kind, n, t * 3, vb, ib))
    print(f'template {name:12s} verts={n} tris={t} dims={tuple(round(d,3) for d in o.dimensions)}')

# --- instances ---------------------------------------------------------------
cells = {}  # (kind, i, j) -> [data, count, min, max]
parent_kind = {v[0]: k for k, v in INSTANCES.items()}
for inst in depsgraph.object_instances:
    if not inst.is_instance or inst.parent is None:
        continue
    kind = parent_kind.get(inst.parent.name)
    if kind is None:
        continue
    keep = INSTANCES[kind][2]
    r = (inst.random_id & 0xFFFFFFFF) / 0xFFFFFFFF
    r2 = ((inst.random_id * 2654435761) & 0xFFFFFFFF) / 0xFFFFFFFF
    if r2 > keep:
        continue
    M = inst.matrix_world
    B = C @ M.to_3x3() @ CI
    cx, cy, cz = B.col[0], B.col[1], B.col[2]
    sx, sy, sz = cx.length, cy.length, cz.length
    s = (sx + sz) / 2 * keep ** -0.45
    if sx == 0 or sy == 0:
        continue
    ax = cx / sx
    ay = cy / sy
    p = yup(M.translation)
    stretch = max(0.0, min(1.0, (sy / max(sx, 1e-6)) / 2))
    key = (kind, math.floor(p[0] / CELL), math.floor(p[2] / CELL))
    cell = cells.setdefault(key, [bytearray(), 0, [1e9] * 3, [-1e9] * 3])
    for a in range(3):
        cell[2][a] = min(cell[2][a], p[a])
        cell[3][a] = max(cell[3][a], p[a])
    cell[0] += struct.pack('<4e4b4b', p[0], p[1], p[2], s,
                                   snorm(ax.x), snorm(ax.y), snorm(ax.z), snorm(r * 2 - 1),
                                   snorm(ay.x), snorm(ay.y), snorm(ay.z), snorm(stretch * 2 - 1))
    cell[1] += 1
totals = {}
for (kind, _, _), (data, count, lo, hi) in sorted(cells.items()):
    sections.append((kind, count, INSTANCES[kind][1], bytes(data), b'', lo, hi))
    totals[kind] = totals.get(kind, 0) + count
for kind, total in totals.items():
    print(f'instances {INSTANCES[kind][0]:16s} {total:7d} in {sum(1 for k in cells if k[0] == kind)} cells')

# --- write -------------------------------------------------------------------
head = 12 + 64 * len(sections)
blob = bytearray()
table = bytearray()
for kind, count, icount, vb, ib, *bounds in sections:
    lo, hi = bounds if bounds else ([0] * 3, [0] * 3)
    vbo = head + len(blob)
    blob += vb
    blob += b'\0' * (-len(blob) % 4)
    ibo = head + len(blob)
    blob += ib
    table += struct.pack('<8I8f', kind, count, icount, vbo, len(vb), ibo, len(ib), 0, *lo, *hi, 0, 0)
with open(out, 'wb') as f:
    f.write(b'SHRN' + struct.pack('<2I', 2, len(sections)) + table + blob)
print(f'wrote {out}: {(head + len(blob)) / 1e6:.2f} MB')

cam = bpy.data.objects['Camera']
fwd = C @ (cam.matrix_world.to_3x3() @ Vector((0, 0, -1)))
print('camera', yup(cam.location), 'forward', tuple(fwd), 'lens', cam.data.lens)
sun = bpy.data.objects['Sun']
print('sun dir (to light)', tuple(C @ (sun.matrix_world.to_3x3() @ Vector((0, 0, 1)))))
