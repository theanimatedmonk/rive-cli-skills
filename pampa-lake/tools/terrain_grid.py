# The ground under the lake scene as a grid seen from above: its height,
# its baked colour and slope, and where the water is. The vegetation is
# planted from it (see export_lake.py).

import numpy as np

STEP = 0.5
X0, X1 = -80.0, 140.0
Z0, Z1 = -220.0, 30.0


def rasterize(pos, idx, values, nx, nz):
    """Barycentric fill of triangles (xz) into a grid; returns (filled, values)."""
    out = np.full((nz, nx, values.shape[1]), np.nan)
    tris = idx.reshape(-1, 3)
    P = pos[tris]  # t, 3, 3
    gx = (P[:, :, 0] - X0) / STEP
    gz = (P[:, :, 2] - Z0) / STEP
    for t in range(len(tris)):
        x, z = gx[t], gz[t]
        i0, i1 = int(max(np.floor(x.min()), 0)), int(min(np.ceil(x.max()), nx - 1))
        j0, j1 = int(max(np.floor(z.min()), 0)), int(min(np.ceil(z.max()), nz - 1))
        if i1 < i0 or j1 < j0:
            continue
        ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1))
        px, pz = ii.ravel() + 0.0, jj.ravel() + 0.0
        d = (z[1] - z[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (z[0] - z[2])
        if abs(d) < 1e-9:
            continue
        a = ((z[1] - z[2]) * (px - x[2]) + (x[2] - x[1]) * (pz - z[2])) / d
        b = ((z[2] - z[0]) * (px - x[2]) + (x[0] - x[2]) * (pz - z[2])) / d
        c = 1 - a - b
        inside = (a >= -1e-4) & (b >= -1e-4) & (c >= -1e-4)
        if not inside.any():
            continue
        v = values[tris[t]]
        vals = a[inside, None] * v[0] + b[inside, None] * v[1] + c[inside, None] * v[2]
        ji, ii_ = jj.ravel()[inside], ii.ravel()[inside]
        # Keep the highest surface (overhangs are rare; the bed is lower).
        old = out[ji, ii_, 0]
        take = np.isnan(old) | (vals[:, 0] > old)
        out[ji[take], ii_[take]] = vals[take]
    return out


def build(terrain, water):
    nx = int((X1 - X0) / STEP) + 1
    nz = int((Z1 - Z0) / STEP) + 1
    _, pos, nrm, rgb, _, _, idx = terrain
    lin = rgb ** 2.2
    vals = np.hstack([pos[:, 1:2], lin, nrm[:, 1:2]])
    g = rasterize(pos, idx, vals, nx, nz)
    wpos, widx = water[1], water[6]
    wg = rasterize(wpos, widx, np.ones((len(wpos), 1)), nx, nz)
    wet = ~np.isnan(wg[:, :, 0])
    return {
        'nx': nx, 'nz': nz,
        'height': g[:, :, 0], 'color': g[:, :, 1:4], 'up': g[:, :, 4], 'water': wet,
    }
