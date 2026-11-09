#!/usr/bin/env python3
"""Writes ../rive/scene.rml: the Titan AI logo and its reveal.

The mark is an Indian star: two four-point stars whose arms are shaped like
Mughal arches (a swelling shoulder, then a fine finial), a lotus at the heart
with a bindu, and rangoli dots between the points.

The reveal: a seed pops, a star-shaped aperture spins open to uncover the tile,
the two star layers counter-rotate and lock into one mark, then a small star
runs along the baseline and the letters rise as it passes. It then rests in
Idle, which is the finished logo with nothing moving.

Processing keeps the logo in place and works inside the tile: the star's two
layers take turns snapping round like clockwork, the lotus spins against them,
a ripple leaves on each beat, and a light runs round the tile's rim.

Plain vector and timeline: no scripts, so it needs no signing. Three triggers
on the Logo view model drive it: `replay`, `idle` and `processing`.

Run: python3 tools/make_scene.py
"""

import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "rive" / "scene.rml"

SIZE = 1000
TILE_HALF = 150.0
TILE_N = 4.6       # superellipse power of the tile
STAR_R = 124.0     # long arm of the star
SHORT = 0.88       # short arm, as a share of the long one
LOGO_START_Y = 500.0
LOGO_END_Y = 386.0
WORD_Y = 660.0     # top of the capitals
WORD_SCALE = 0.9

# Palette (ARGB): soft blue into soft purple.
TILE_A, TILE_B, TILE_C = "FF2F6BF2", "FF1B3FC4", "FF3A2AA6"
STAR_HI, STAR_LO, STAR_FACET = "FFFFFFFF", "FFEEF3FF", "FFD3DFFF"
BACK_HI, BACK_LO, BACK_FACET = "FFB9CCFF", "FF9DB6FF", "FF7F9CF5"
LOTUS = "FF1B3FC4"
INK_A, INK_B = "FF0B1650", "FF17308F"
LINE = "FF7F86EE"


def f(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


_ids = {}
_next = [100]


def nid(name=None):
    _next[0] += 1
    i = f"0:{_next[0]}"
    if name:
        assert name not in _ids, name
        _ids[name] = i
    return i


def ref(name):
    return _ids[name]


# --- Paths -------------------------------------------------------------------
def polar(p):
    return math.atan2(p[1], p[0]), math.hypot(p[0], p[1])


def cubic(p, hin, hout):
    """A vertex with handles given as offsets from it (None for no handle)."""
    ir, id_ = polar(hin) if hin else (0, 0)
    or_, od = polar(hout) if hout else (0, 0)
    return (
        f'<CubicDetachedVertex x="{f(p[0])}" y="{f(p[1])}" inRotation="{f(ir)}" inDistance="{f(id_)}" '
        f'outRotation="{f(or_)}" outDistance="{f(od)}"/>'
    )


def straight(p):
    return f'<StraightVertex x="{f(p[0])}" y="{f(p[1])}"/>'


def path(verts, name="Path", clockwise=True):
    cw = "" if clockwise else ' isClockwise="false"'
    return f'<PointsPath isClosed="true"{cw} name="{name}">' + "".join(verts) + "</PointsPath>"


def rot(p, t):
    c, s = math.cos(t), math.sin(t)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def arm(R, arms, valley, shoulder_u, shoulder_w):
    """Control points of one side of an ogee arm along +x, for the +y side.

    Returns valley, its handle, shoulder, shoulder's handles (toward the valley,
    toward the tip), tip, and the tip's handle.
    """
    a = math.pi / arms
    v = (valley * R * math.cos(a), valley * R * math.sin(a))
    vh = (0.16 * R * math.cos(a), 0.16 * R * math.sin(a))
    b = (shoulder_u * R, shoulder_w * R)
    bin_ = (-0.12 * R, 0.02 * R)
    bout = (0.12 * R, -0.02 * R)
    t = (R, 0.0)
    th = (-0.40 * R, 0.0)
    return v, vh, b, bin_, bout, t, th


def flip(p):
    return (p[0], -p[1])


def star_path(R, arms, phase=0.0, valley=0.2, su=0.40, sw=0.235, name="Path"):
    """A closed star of `arms` ogee arms, running clockwise on screen."""
    v, vh, b, bin_, bout, t, th = arm(R, arms, valley, su, sw)
    verts = []
    step = 2 * math.pi / arms
    for i in range(arms):
        ang = phase + i * step
        # This arm's valley on the -y side: in from the previous arm's +y side,
        # out toward this arm's -y shoulder.
        prev = ang - step
        verts.append(cubic(rot(flip(v), ang), rot(vh, prev), rot(flip(vh), ang)))
        verts.append(cubic(rot(flip(b), ang), rot(flip(bin_), ang), rot(flip(bout), ang)))
        verts.append(cubic(rot(t, ang), rot(flip(th), ang), rot(th, ang)))
        verts.append(cubic(rot(b, ang), rot(bout, ang), rot(bin_, ang)))
    return path(verts, name)


def facet_paths(R, arms, phase=0.0, valley=0.2, su=0.40, sw=0.235):
    """The shaded half of each arm: tip, down the +y side, back through the centre."""
    v, vh, b, bin_, bout, t, th = arm(R, arms, valley, su, sw)
    out = []
    step = 2 * math.pi / arms
    for i in range(arms):
        ang = phase + i * step
        verts = [
            cubic(rot(t, ang), None, rot(th, ang)),
            cubic(rot(b, ang), rot(bout, ang), rot(bin_, ang)),
            cubic(rot(v, ang), rot(vh, ang), None),
            straight((0, 0)),
        ]
        out.append(path(verts, f"Facet{i}"))
    return "".join(out)


def squircle(half, n, count=40):
    """A superellipse, with smooth handles from its tangents."""
    pts = []
    for i in range(count):
        t = 2 * math.pi * i / count - math.pi / 2
        c, s = math.cos(t), math.sin(t)
        pts.append((
            half * math.copysign(abs(c) ** (2 / n), c),
            half * math.copysign(abs(s) ** (2 / n), s),
        ))
    verts = []
    for i, p in enumerate(pts):
        a, b = pts[i - 1], pts[(i + 1) % count]
        tx, ty = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tx, ty) or 1
        tx, ty = tx / length, ty / length
        din = math.hypot(p[0] - a[0], p[1] - a[1]) / 3
        dout = math.hypot(b[0] - p[0], b[1] - p[1]) / 3
        verts.append(cubic(p, (-tx * din, -ty * din), (tx * dout, ty * dout)))
    return path(verts)


def petal(length, width, ang):
    """A pointed lotus petal from the centre outward."""
    base = (length * 0.1, 0)
    tip = (length, 0)
    mid_u = length * 0.62
    verts = [
        cubic(rot(base, ang), None, rot((length * 0.08, -width * 0.62), ang)),
        cubic(rot((mid_u, -width / 2), ang), rot((-length * 0.16, 0), ang), rot((length * 0.14, 0), ang)),
        cubic(rot(tip, ang), rot((-length * 0.14, -width * 0.05), ang), rot((-length * 0.14, width * 0.05), ang)),
        cubic(rot((mid_u, width / 2), ang), rot((length * 0.14, 0), ang), rot((-length * 0.16, 0), ang)),
    ]
    # Close back to the base with its in handle.
    verts[0] = cubic(rot(base, ang), rot((length * 0.08, width * 0.62), ang), rot((length * 0.08, -width * 0.62), ang))
    return path(verts, "Petal")


def poly(points):
    return path([straight(p) for p in points], "Part")


def rect(x0, y0, x1, y1):
    return poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])


# --- Paints ------------------------------------------------------------------
def solid(c):
    return f'<SolidColor colorValue="{c}" name="C"/>'


def fill(c):
    return f'<Fill name="F">{solid(c)}</Fill>'


def linear(x0, y0, x1, y1, stops):
    s = "".join(f'<GradientStop colorValue="{c}" position="{p}" name="S"/>' for c, p in stops)
    return f'<LinearGradient startX="{f(x0)}" startY="{f(y0)}" endX="{f(x1)}" endY="{f(y1)}" name="G">{s}</LinearGradient>'


def gradfill(x0, y0, x1, y1, stops):
    return f'<Fill name="F">{linear(x0, y0, x1, y1, stops)}</Fill>'


def feathered(c, strength, ox=0, oy=0, inner=False, paint=None):
    i = ' inner="true"' if inner else ""
    return (
        f'<Fill fillRule="clockwise" name="Soft">{paint or solid(c)}'
        f'<Feather strength="{f(strength)}" offsetX="{f(ox)}" offsetY="{f(oy)}"{i} name="Feather"/></Fill>'
    )


def ellipse(w, h):
    return f'<Ellipse width="{f(w)}" height="{f(h)}" name="Path"/>'


def shape(name, body, x=0, y=0, extra=""):
    i = nid(name)
    return f'<Shape x="{f(x)}" y="{f(y)}"{extra} name="{name}" id="{i}">{body}</Shape>'


def node(name, body, x=0, y=0, extra=""):
    i = nid(name)
    return f'<Node x="{f(x)}" y="{f(y)}"{extra} name="{name}" id="{i}">{body}</Node>'


# --- The star ----------------------------------------------------------------
def front_layer():
    return (
        shape("FrontFacets", facet_paths(STAR_R, 4) + fill(STAR_FACET))
        + shape("FrontBody", star_path(STAR_R, 4) + gradfill(-90, -90, 90, 90, [(STAR_HI, 0), (STAR_LO, 1)]))
    )


def back_layer():
    r = STAR_R * SHORT
    ph = math.pi / 4
    return (
        shape("BackFacets", facet_paths(r, 4, ph) + fill(BACK_FACET))
        + shape("BackBody", star_path(r, 4, ph) + gradfill(-70, -70, 70, 70, [(BACK_HI, 0), (BACK_LO, 1)]))
        + shape("BackShadow", star_path(r, 4, ph) + feathered("880A1A70", 7, 0, 3))
    )


def lotus():
    petals = "".join(petal(STAR_R * 0.34, 21, i * math.pi / 4) for i in range(8))
    paint = gradfill(-34, -34, 34, 34, [(TILE_A, 0), (LOTUS, 0.5), (TILE_C, 1)])
    core = shape("Core", ellipse(30, 30) + paint)
    return core + shape("Petals", petals + paint)


def rangoli_dots():
    out = []
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        r = STAR_R * 0.99
        out.append(shape(f"Dot{i}", ellipse(9, 9) + fill("FFFFFFFF"), r * math.cos(a), r * math.sin(a)))
    return "".join(out)


def star():
    return node(
        "Star",
        shape("Bindu", ellipse(17, 17) + fill("FFFFFFFF"))
        + node("Lotus", lotus(), extra=' scaleX="0" scaleY="0"')
        + node("Front", front_layer(), extra=' scaleX="0" scaleY="0"')
        + node("Back", back_layer(), extra=' scaleX="0" scaleY="0"')
        + node("Dots", rangoli_dots(), extra=' scaleX="0" scaleY="0"'),
    )


# --- The tile ----------------------------------------------------------------
def tile():
    sq = squircle(TILE_HALF, TILE_N)
    t = TILE_HALF
    grad = linear(-t, -t, t, t, [(TILE_A, 0), (TILE_B, 0.52), (TILE_C, 1)])
    body = (
        sq
        + f'<Fill name="Base">{grad}</Fill>'
        + feathered("660A1466", 18, -8, -12, inner=True)
        + feathered("596FA0FF", 7, 3, 6, inner=True)
    )
    tile_id = nid("TileShape")
    sheen = node(
        "Sheen",
        shape(
            "Band",
            ellipse(46, 560) + feathered("3DFFFFFF", 18),
            extra=' rotation="0.6"',
        )
        + f'<ClippingShape sourceId="{tile_id}" name="ToTile"/>',
    )
    ripple = node(
        "Ripples",
        shape("Ripple", ellipse(300, 300) + stroke("B3FFFFFF", 2.5), extra=' opacity="0"')
        + f'<ClippingShape sourceId="{tile_id}" name="ToTile"/>',
    )
    return node(
        "Tile",
        f'<ClippingShape sourceId="{ref("Aperture")}" name="ToAperture"/>'
        + sheen
        + rim_light()
        + ripple
        + shape("Halo", ellipse(190, 190) + feathered("664F86FF", 38))
        + f'<Shape name="TileShape" id="{tile_id}">{body}</Shape>',
        extra=' opacity="0"',
    )


def rim_light():
    """A short run of light on the tile's edge; its trim offset carries it round."""
    sq = squircle(TILE_HALF - 5, TILE_N)
    def trim(name):
        return f'<TrimPath start="0" end="0.2" offset="0" modeValue="1" name="{name}" id="{nid(name)}"/>'
    crisp = f'<Stroke thickness="3.5" cap="round" name="Crisp">{solid("F2FFFFFF")}{trim("RimTrim")}</Stroke>'
    glow = (
        f'<Stroke thickness="9" cap="round" name="Bloom">{solid("CC9DBBFF")}'
        f'<Feather strength="9" name="Feather"/>{trim("RimTrimGlow")}</Stroke>'
    )
    return shape("RimLight", sq + glow + crisp, extra=' opacity="0"')


# --- The word ----------------------------------------------------------------
CAP = 92.0
STEM = 15.0


def letter_t():
    w = 80.0
    return [rect(0, 0, w, STEM), rect((w - STEM) / 2, 0, (w + STEM) / 2, CAP)], w


def letter_i():
    return [rect(0, 0, STEM, CAP)], STEM


def letter_n():
    w = 84.0
    return [
        rect(0, 0, STEM, CAP),
        rect(w - STEM, 0, w, CAP),
        poly([(0, 0), (STEM + 3, 0), (w, CAP), (w - STEM - 3, CAP)]),
    ], w


def letter_a():
    w = 98.0
    m = w / 2
    leg = 16.0
    apex = -9.0  # the tip reaches a little above the caps, like the star's
    return [
        poly([(m, apex), (m + leg * 0.55, 8), (leg, CAP), (0, CAP)]),
        poly([(m, apex), (w, CAP), (w - leg, CAP), (m - leg * 0.55, 8)]),
        rect(20, 57, w - 20, 57 + 12),
    ], w


WORD = [("T", letter_t), ("I", letter_i), ("T", letter_t), ("A", letter_a), ("N", letter_n), (" ", None), ("A", letter_a), ("I", letter_i)]
TRACK = 21.0
SPACE = 42.0


def layout_word():
    out, x = [], 0.0
    for ch, fn in WORD:
        if fn is None:
            x += SPACE
            continue
        parts, w = fn()
        out.append((ch, parts, x, w))
        x += w + TRACK
    return out, x - TRACK


LETTERS, WORD_W = layout_word()


def word():
    x0 = -WORD_W / 2
    shapes = []
    for i, (ch, parts, x, w) in enumerate(LETTERS):
        paint = gradfill(0, 0, 0, CAP, [(INK_B, 0), (INK_A, 1)])
        shapes.append(shape(f"L{i}", "".join(parts) + paint, x0 + x, 0, ' opacity="0"'))
    return node("Word", "".join(shapes), 500, WORD_Y, f' scaleX="{WORD_SCALE}" scaleY="{WORD_SCALE}"')


def word_star():
    r = 23
    body = star_path(r, 4)
    return node(
        "WordStar",
        shape("WS", body + gradfill(-r, -r, r, r, [("FF2F6BF2", 0), ("FF2A2FB0", 1)]))
        + shape("WSGlow", ellipse(58, 58) + feathered("662F5FF0", 14)),
        500 - WORD_W * WORD_SCALE / 2 - 30,
        WORD_Y + CAP * WORD_SCALE / 2,
        ' scaleX="0" scaleY="0"',
    )


# --- Rings and backdrop ------------------------------------------------------
def arches(r, count, depth):
    """A ring of pointed arches, as on a jali: each a single S-curve up to its tip."""
    verts = []
    step = 2 * math.pi / count
    h = step / 2
    for i in range(count):
        a = i * step
        tip = (r + depth, 0)
        v = rot((r, 0), -h)
        out = rot((depth * 0.75, 0), -h)
        prev_side = rot((depth * 0.75, 0), -h)
        verts.append(cubic(rot(v, a), rot(prev_side, a), rot(out, a)))
        verts.append(cubic(rot(tip, a), rot((-depth * 0.5, 0), a), rot((-depth * 0.5, 0), a)))
    return path(verts, "Arches")


def stroke(c, t):
    return f'<Stroke thickness="{f(t)}" name="S">{solid(c)}</Stroke>'


def mandala():
    dots = "".join(
        shape(
            f"RingDot{i}",
            ellipse(5, 5) + fill("70" + LINE[2:]),
            445 * math.cos(i * math.pi / 12),
            445 * math.sin(i * math.pi / 12),
        )
        for i in range(24)
    )
    return node(
        "Mandala",
        dots
        + shape("Arches", arches(404, 24, 28) + stroke("50" + LINE[2:], 1.5))
        + shape("Rim", ellipse(936, 936) + stroke("40" + LINE[2:], 1.5)),
        500,
        500,
        ' opacity="0"',
    )


def backdrop():
    return (
        shape("BlobViolet", ellipse(760, 620) + feathered("A8CDBBFF", 170), 760, 190)
        + shape("BlobBlue", ellipse(760, 600) + feathered("A8AEC6FF", 170), 240, 170)
        + shape("BlobPink", ellipse(520, 360) + feathered("66E4CCFF", 110), 620, 900)
    )


# --- Keyframes ---------------------------------------------------------------
EASE = {
    "out": (0.16, 1, 0.3, 1),
    "expo": (0.08, 0.82, 0.17, 1),
    "inout": (0.65, 0, 0.35, 1),
    "soft": (0.42, 0, 0.58, 1),
    "back": (0.34, 1.56, 0.64, 1),
    "in": (0.5, 0, 0.9, 0.4),
    "snap": (0.6, -0.28, 0.2, 1.3),  # winds back, whips round, overshoots
}


def keyframe(frame, value, ease):
    if ease is None:
        return f'<KeyFrameDouble value="{f(value)}" frame="{frame}" interpolationType="hold"/>'
    if ease == "linear":
        return f'<KeyFrameDouble value="{f(value)}" frame="{frame}" interpolationType="linear"/>'
    x1, y1, x2, y2 = EASE[ease]
    return (
        f'<KeyFrameDouble value="{f(value)}" frame="{frame}" interpolationType="cubic">'
        f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></KeyFrameDouble>'
    )


class Timeline:
    def __init__(self):
        self.objects = {}

    def key(self, name, prop, keys):
        props = self.objects.setdefault(name, {})
        props[prop] = keys

    def scale(self, name, keys):
        self.key(name, "scaleX", keys)
        self.key(name, "scaleY", keys)

    def xml(self):
        out = []
        for name, props in self.objects.items():
            ps = ""
            for prop, keys in props.items():
                ps += f'<KeyedProperty property="{prop}">' + "".join(keyframe(*k) for k in keys) + "</KeyedProperty>"
            out.append(f'<KeyedObject objectId="{ref(name)}">{ps}</KeyedObject>')
        return "".join(out)


TAU = 2 * math.pi
# Frames of the reveal, at 60 fps.
SEED_IN, BURST, LOCK = 6, 34, 104
RISE_AT, RISE_END = 128, 166
RUN_AT, RUN_END = 150, 214
SHEEN_AT, REVEAL_END = 214, 262


def reveal():
    t = Timeline()
    # The seed: pops, breathes in, and is swallowed by the burst.
    t.scale("Seed", [(0, 0, None), (SEED_IN, 0, "back"), (SEED_IN + 16, 1, "soft"), (BURST - 4, 0.8, "in"), (BURST + 10, 0, None)])

    # The aperture: a star that spins open to uncover the tile.
    t.key("Tile", "opacity", [(0, 0, None), (BURST, 1, None)])
    t.scale("Aperture", [(0, 0, None), (BURST, 0, "out"), (BURST + 34, 1.75, "inout"), (LOCK + 8, 8.4, None)])
    t.key("Aperture", "rotation", [(0, -TAU * 0.9, None), (BURST, -TAU * 0.9, "out"), (LOCK + 8, 0, None)])

    # The star's two layers counter-rotate and lock.
    t.scale("Front", [(0, 0, None), (BURST + 4, 0, "out"), (LOCK - 8, 1.16, "soft"), (LOCK + 8, 0.97, "soft"), (LOCK + 22, 1, None)])
    t.key("Front", "rotation", [(0, TAU, None), (BURST + 4, TAU, "expo"), (LOCK, 0, None)])
    t.scale("Back", [(0, 0, None), (BURST + 8, 0, "out"), (LOCK - 4, 1.2, "soft"), (LOCK + 10, 0.96, "soft"), (LOCK + 24, 1, None)])
    t.key("Back", "rotation", [(0, -TAU, None), (BURST + 8, -TAU, "expo"), (LOCK, 0, None)])
    t.scale("Lotus", [(0, 0, None), (LOCK - 22, 0, "back"), (LOCK + 8, 1, None)])
    t.key("Lotus", "rotation", [(0, -1.6, None), (LOCK - 22, -1.6, "out"), (LOCK + 8, 0, None)])
    t.scale("Bindu", [(0, 0, None), (LOCK - 6, 0, "back"), (LOCK + 8, 1, None)])
    t.scale("Dots", [(0, 0, None), (LOCK - 4, 0, "back"), (LOCK + 14, 1, None)])
    t.key("Star", "rotation", [(0, 0, None)])

    # The lock lands: tile gives, glow blooms, a ring goes out.
    t.scale("TileGroup", [(0, 1, None), (LOCK - 2, 1, "soft"), (LOCK + 6, 1.035, "soft"), (LOCK + 24, 1, None)])
    t.key("Glow", "opacity", [(0, 0, None), (LOCK - 10, 0, "out"), (LOCK + 22, 1, None)])
    t.key("Halo", "opacity", [(0, 1, None)])
    t.scale("Shock", [(0, 0.5, None), (LOCK - 4, 0.5, "out"), (LOCK + 56, 3.1, None)])
    t.key("Shock", "opacity", [(0, 0, None), (LOCK - 4, 0, "linear"), (LOCK + 2, 0.75, "out"), (LOCK + 56, 0, None)])

    # The mandala arrives behind it, turning into place.
    t.key("Mandala", "opacity", [(0, 0, None), (LOCK, 0, "soft"), (LOCK + 66, 1, None)])
    t.key("Mandala", "rotation", [(0, -0.5, None), (LOCK, -0.5, "out"), (LOCK + 90, 0, None)])
    t.scale("Mandala", [(0, 0.9, None), (LOCK, 0.9, "out"), (LOCK + 90, 1, None)])

    # The logo rises to make room for the word.
    t.key("Logo", "y", [(0, LOGO_START_Y, None), (RISE_AT, LOGO_START_Y, "inout"), (RISE_END, LOGO_END_Y, None)])

    # A small star runs the baseline, and letters rise as it passes.
    x0 = 500 - WORD_W * WORD_SCALE / 2 - 30
    x1 = 500 + WORD_W * WORD_SCALE / 2 + 30
    t.key("WordStar", "x", [(0, x0, None), (RUN_AT, x0, "soft"), (RUN_END, x1, None)])
    t.key("WordStar", "rotation", [(0, 0, None), (RUN_AT, 0, "soft"), (RUN_END, TAU * 1.5, None)])
    t.scale("WordStar", [(0, 0, None), (RUN_AT - 8, 0, "back"), (RUN_AT + 8, 1, None), (RUN_END - 12, 1, "in"), (RUN_END + 2, 0, None)])
    for i, (ch, parts, x, w) in enumerate(LETTERS):
        at = RUN_AT + round((RUN_END - RUN_AT) * ((x + w * 0.2) / WORD_W) * 0.92)
        name = f"L{i}"
        t.key(name, "opacity", [(0, 0, None), (at, 0, "out"), (at + 12, 1, None)])
        t.key(name, "y", [(0, 26, None), (at, 26, "back"), (at + 26, 0, None)])

    # A last glint across the tile.
    t.key("Sheen", "x", [(0, -300, None), (SHEEN_AT, -300, "soft"), (REVEAL_END - 4, 300, None)])

    # Everything Processing moves starts from rest.
    t.key("Dots", "rotation", [(0, 0, None)])
    t.key("RimLight", "opacity", [(0, 0, None)])
    t.key("RimTrim", "offset", [(0, 0, None)])
    t.key("RimTrimGlow", "offset", [(0, 0, None)])
    t.key("Ripple", "opacity", [(0, 0, None)])
    t.scale("Ripple", [(0, 0.3, None)])

    pin_backdrop(t)
    return t


def pin_backdrop(t):
    """The backdrop doesn't move; these keep it in place for the Idle pose."""
    for name, (x, y) in {"BlobViolet": (760, 190), "BlobBlue": (240, 170), "BlobPink": (620, 900)}.items():
        t.key(name, "x", [(0, x, None)])
        t.key(name, "y", [(0, y, None)])


def idle(rev):
    """A still: every property the reveal touches, held at its final value."""
    t = Timeline()
    for name, props in rev.objects.items():
        for prop, keys in props.items():
            t.key(name, prop, [(0, keys[-1][1], None)])
    return t


BEAT = 22  # frames for one layer's move; the two layers alternate
PROCESSING = BEAT * 8


def processing():
    t = Timeline()
    quarter = math.pi / 2

    def turns(direction, start):
        """Four snapped quarter turns, one every other beat, starting at `start`."""
        keys = [(0, 0, None)] if start else []
        for i in range(4):
            at = start + i * 2 * BEAT
            keys += [(at, direction * quarter * i, "snap"), (at + BEAT, direction * quarter * (i + 1), None)]
        return keys

    t.key("Front", "rotation", turns(1, 0))
    t.key("Back", "rotation", turns(-1, BEAT))

    def pulse(start, low, high):
        """Each layer draws in as it winds up and stretches as it lands."""
        keys = [(0, 1, None)] if start else []
        for i in range(4):
            at = start + i * 2 * BEAT
            keys += [
                (at, 1, "soft"),
                (at + BEAT // 3, low, "out"),
                (at + BEAT, high, "soft"),
                (at + 2 * BEAT - 2 if start == 0 else min(at + 2 * BEAT - 2, PROCESSING), 1, None),
            ]
        return keys

    t.scale("Front", pulse(0, 0.9, 1.05) + [(PROCESSING, 1, None)])
    t.scale("Back", [k for k in pulse(BEAT, 0.88, 1.08) if k[0] <= PROCESSING])

    t.key("Lotus", "rotation", [(0, 0, "linear"), (PROCESSING, -TAU, None)])
    t.key("Dots", "rotation", [(0, 0, "linear"), (PROCESSING, quarter, None)])
    bindu = []
    for i in range(8):
        bindu += [(i * BEAT, 1, "out"), (i * BEAT + 8, 1.5, "soft")]
    t.scale("Bindu", bindu + [(PROCESSING, 1, None)])

    # A ripple leaves on each landing, clipped to the tile.
    op, sc = [], []
    for i in range(4):
        at = i * 2 * BEAT + BEAT - 4
        op += [(at, 0, "linear"), (at + 3, 0.9, "linear"), (at + 26, 0, None)]
        sc += [(at, 0.3, "out"), (at + 26, 0.94, None)]
    t.key("Ripple", "opacity", [(0, 0, None)] + op)
    t.scale("Ripple", [(0, 0.3, None)] + sc)

    # The rim light runs round twice a loop, so it stays lively but never rushes.
    t.key("RimLight", "opacity", [(0, 1, None)])
    t.key("RimTrim", "offset", [(0, 0, "linear"), (PROCESSING, 2, None)])
    t.key("RimTrimGlow", "offset", [(0, 0, "linear"), (PROCESSING, 2, None)])

    # The tile breathes with it.
    half = PROCESSING // 2
    t.key("Halo", "opacity", [(0, 1, "soft"), (half // 2, 0.55, "soft"), (half, 1, "soft"), (half + half // 2, 0.55, "soft"), (PROCESSING, 1, None)])
    t.key("Glow", "opacity", [(0, 1, "soft"), (half, 0.7, "soft"), (PROCESSING, 1, None)])
    return t


# --- The file ----------------------------------------------------------------
def build():
    art, style, sm, layer = nid("Artboard"), nid(), nid(), nid()
    vm, vm_prop, vm_inst, vm_val = "0:900", "0:901", "0:899", "0:902"
    vm_idle, vm_idle_val = "0:903", "0:904"
    vm_proc, vm_proc_val = "0:905", "0:906"
    rev_anim, idle_anim, rev_state, idle_state = nid(), nid(), nid(), nid()
    proc_anim, proc_state = nid(), nid()

    # The tile's clip names the aperture, so the aperture is made first.
    aperture = shape("Aperture", star_path(100, 8, 0, valley=0.36, su=0.5, sw=0.16), extra=' scaleX="0" scaleY="0"')
    star_xml = star()
    tile_xml = tile()
    tile_group = node("TileGroup", tile_xml)
    glow = shape(
        "Glow",
        squircle(TILE_HALF, TILE_N) + feathered("B02347D8", 46, 0, 30),
        extra=' opacity="0"',
    )
    seed = shape(
        "Seed",
        ellipse(34, 34)
        + gradfill(-17, -17, 17, 17, [("FF2F6BF2", 0), ("FF2A2FB0", 1)]),
        extra=' scaleX="0" scaleY="0"',
    )
    shock = shape("Shock", ellipse(300, 300) + stroke("CC6F93FF", 3), extra=' opacity="0"')
    logo = node("Logo", star_xml + tile_group + aperture + seed + glow + shock, 500, LOGO_START_Y)

    # Everything that needs an id exists now, so the timelines can name them.
    rev = reveal()
    idl = idle(rev)
    proc = processing()

    def on_trigger(prop, state, blend=0):
        return (
            f'<StateTransition stateToId="{state}" duration="{blend}">'
            '<TransitionViewModelCondition opValue="equal"><TransitionPropertyViewModelComparator>'
            f'<BindablePropertyTrigger><DataBindContext sourcePathIds="{vm}-{prop}" propertyKey="686"/></BindablePropertyTrigger>'
            '</TransitionPropertyViewModelComparator><TransitionValueTriggerComparator/></TransitionViewModelCondition>'
            '</StateTransition>'
        )

    trigger = f'<AnyState x="200" y="-120">{on_trigger(vm_prop, rev_state)}{on_trigger(vm_idle, idle_state, 350)}{on_trigger(vm_proc, proc_state, 250)}</AnyState>'
    machine = (
        f'<StateMachine name="Logo" id="{sm}"><StateMachineLayer name="Base" id="{layer}">'
        f'{trigger}<ExitState x="600" y="-120"/>'
        f'<EntryState><StateTransition stateToId="{rev_state}"/></EntryState>'
        f'<AnimationState x="200" animationId="{rev_anim}" reset="true" id="{rev_state}">'
        f'<StateTransition stateToId="{idle_state}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/></AnimationState>'
        f'<AnimationState x="400" animationId="{idle_anim}" id="{idle_state}"/>'
        f'<AnimationState x="400" y="120" animationId="{proc_anim}" reset="true" id="{proc_state}"/>'
        "</StateMachineLayer></StateMachine>"
    )
    back = (
        f'<Fill name="Backdrop">{linear(500, 0, 500, 1000, [("FFE6E7FF", 0), ("FFF1EEFF", 0.55), ("FFF6F4FF", 1)])}</Fill>'
    )
    return f"""<Rive version="1" kind="fragment">
<!-- The Titan AI logo. Written by ../tools/make_scene.py; edit that. -->
<Artboard defaultStateMachineId="{sm}" viewModelId="{vm}" viewModelInstanceId="{vm_inst}" width="{SIZE}" height="{SIZE}" styleId="{style}" name="Logo" id="{art}">
<LayoutComponentStyle name="Logo Style" id="{style}"/>
{word_star()}
{word()}
{logo}
{mandala()}
{backdrop()}
{back}
{machine}
<LinearAnimation fps="60" duration="{REVEAL_END}" name="Reveal" id="{rev_anim}">{rev.xml()}</LinearAnimation>
<LinearAnimation fps="60" duration="1" name="Idle" id="{idle_anim}">{idl.xml()}</LinearAnimation>
<LinearAnimation loopValue="loop" fps="60" duration="{PROCESSING}" name="Processing" id="{proc_anim}">{proc.xml()}</LinearAnimation>
</Artboard>
<ViewModel name="Logo" id="{vm}">
<ViewModelPropertyTrigger name="replay" id="{vm_prop}"/>
<ViewModelPropertyTrigger name="idle" id="{vm_idle}"/>
<ViewModelPropertyTrigger name="processing" id="{vm_proc}"/>
<ViewModelInstance exports="true" name="Default" id="{vm_inst}">
<ViewModelInstanceTrigger viewModelPropertyId="{vm_prop}" id="{vm_val}"/>
<ViewModelInstanceTrigger viewModelPropertyId="{vm_idle}" id="{vm_idle_val}"/>
<ViewModelInstanceTrigger viewModelPropertyId="{vm_proc}" id="{vm_proc_val}"/>
</ViewModelInstance></ViewModel>
</Rive>
"""


if __name__ == "__main__":
    OUT.write_text(build())
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB), word {WORD_W:.0f} wide")
