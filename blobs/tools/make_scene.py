#!/usr/bin/env python3
"""Writes ../rive/scene.rml: the blob character.

Two artboards:

  BlobRig  the rig: bones, a skinned body, and a face on the crown bone. It is drawn in *material colours*, not final ones;
           the Jelly script renders it to a texture and the shader
           (jelly.wgsl) paints the jelly from it. The channels, divided by
           alpha:
             R  0.5 is body; above 0.5 is blush (1 = full blush)
             B  1 is ink: eyes, mouth (with G = 0)
             G and B both 1 is a catchlight
           Alpha is coverage.
  Blob     the character as shown: a soft backdrop and the Jelly node.

Run: python3 tools/make_scene.py
"""

import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "rive" / "scene.rml"

SIZE = 512
BASE = (256.0, 452.0)  # the blob's base, centre of where it sits

# Body: a soft mochi. A round dome on a softly rounded, slightly sagging
# bottom, centred CENTER_H above the base. No points anywhere.
HALF_W = 176.0
TOP_H = 150.0      # centre to top
BOTTOM_H = 92.0    # centre to bottom (the base)
N_TOP = 2.0
N_BOTTOM = 2.7
CENTER_H = BOTTOM_H
SAG = 0.07         # how much wider the lower body is, as if settling

BODY_LEN = CENTER_H            # Body bone: base to centre
CROWN_LEN = TOP_H              # Crown bone: centre to top
SIDE_LEN = HALF_W              # SideL / SideR: centre to each side

# The eyes: diameter, and distance from the centre line.
EYE_D = 46.0
EYE_X = 64.0

# Material colours (ARGB).
BODY = "FF800000"
BLUSH = "FFFF0000"
INK = "FF8000FF"
CATCH = "FF80FFFF"


# --- 2D affine maths, as Rive's Mat2D: (xx, xy, yx, yy, tx, ty) -----------
def mat(rot=0.0, x=0.0, y=0.0):
    c, s = math.cos(rot), math.sin(rot)
    return (c, s, -s, c, x, y)


def mul(a, b):
    return (
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
    )


def apply(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


def f(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# --- Ids -------------------------------------------------------------------
_next = [100]


def nid():
    _next[0] += 1
    return f"0:{_next[0]}"


# --- Bones (world transforms, for the tendons' bind pose) ------------------
HALF_PI = math.pi / 2
blob_m = mat(0, *BASE)
body_m = mul(blob_m, mat(-HALF_PI))                    # RootBone at the base, pointing up
crown_m = mul(body_m, mat(0, BODY_LEN, 0))             # Bone: starts at the Body's tip
# Side bones from the centre, pointing out: they bulge and jiggle the sides.
side_l_m = mul(blob_m, mat(math.pi, 0, -CENTER_H))
side_r_m = mul(blob_m, mat(0, 0, -CENTER_H))


def tendon(bone_id, m, name):
    return (f'<Tendon boneId="{bone_id}" xx="{f(m[0])}" xy="{f(m[1])}" yx="{f(m[2])}" '
            f'yy="{f(m[3])}" tx="{f(m[4])}" ty="{f(m[5])}" name="{name}"/>')


def weight(pairs):
    """pairs: [(tendon_index_0_based, w 0..1)] -> Weight element."""
    pairs = [(i, w) for i, w in pairs if w > 1e-4]
    tot = sum(w for _, w in pairs)
    vals = [round(255 * w / tot) for _, w in pairs]
    vals[0] += 255 - sum(vals)
    idx = 0
    val = 0
    for slot, ((i, _), v) in enumerate(zip(pairs, vals)):
        idx |= (i + 1) << (8 * slot)
        val |= v << (8 * slot)
    return f'<Weight values="{val}" indices="{idx}"/>'


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# --- Body outline (world) --------------------------------------------------
def body_points(n=96):
    cx, cy = BASE[0], BASE[1] - CENTER_H
    pts = []
    for i in range(n):
        th = 2 * math.pi * i / n
        c, s = math.cos(th), math.sin(th)
        top = s < 0
        nn = N_TOP if top else N_BOTTOM
        b = TOP_H if top else BOTTOM_H
        x = HALF_W * math.copysign(abs(c) ** (2 / nn), c)
        y = b * math.copysign(abs(s) ** (2 / nn), s)
        # Settle: the lower body spreads a little.
        x *= 1 + SAG * math.exp(-((y / BOTTOM_H - 0.45) / 0.45) ** 2)
        pts.append((cx + x, cy + y))
    return pts


# --- Writing ---------------------------------------------------------------
def ellipse_shape(name, x, y, w, h, color, extra="", sid=None):
    sid = f' id="{sid}"' if sid else ""
    return (f'<Shape x="{f(x)}" y="{f(y)}" name="{name}"{sid}>'
            f'<Ellipse width="{f(w)}" height="{f(h)}" name="Path"/>'
            f'<Fill{extra}><SolidColor colorValue="{color}" name="C"/>'
            f'{{FEATHER}}</Fill></Shape>')


def rig_artboard():
    ids = {k: nid() for k in ("ab", "style", "blob", "jelly", "body", "crown", "head",
                             "eyes", "sideL", "sideR", "sm", "layer", "idle", "idleState")}
    L = []
    a = L.append
    a(f'<Artboard defaultStateMachineId="{ids["sm"]}" isComponent="true" width="{SIZE}" height="{SIZE}" '
      f'styleId="{ids["style"]}" x="600" name="BlobRig" id="{ids["ab"]}">')
    a(f'<LayoutComponentStyle name="BlobRig Style" id="{ids["style"]}"/>')

    # The skeleton, with the face riding on the crown. Declared first, so the
    # face draws over the body.
    a(f'<Node x="{f(BASE[0])}" y="{f(BASE[1])}" name="Blob" id="{ids["blob"]}">')
    a(f'<Node name="Jelly" id="{ids["jelly"]}">')
    a(f'<RootBone rotation="{f(-HALF_PI)}" length="{f(BODY_LEN)}" name="Body" id="{ids["body"]}">')
    a(f'<Bone length="{f(CROWN_LEN)}" name="Crown" id="{ids["crown"]}">')
    # The face, screen-aligned, origin at the body's centre. The script
    # drives Look (gaze), Open / Happy (which eyes), the mouths and the
    # blush, by position and scale; the rig's Idle animation blinks Eyes.
    a(f'<Node rotation="{f(HALF_PI)}" name="Head" id="{ids["head"]}">')
    a('<Node name="Look">')
    a(f'<Node y="-2" name="Eyes" id="{ids["eyes"]}">')
    a('<Node name="Open">')
    # Big, round, watery eyes: a large glint and a small one up top, and a
    # soft reflection low on the other side (a faint catchlight).
    for side, nm in ((-1, "L"), (1, "R")):
        ex = side * EYE_X
        a(ellipse_shape(f"Glint{nm}", ex - 9, -10, 14, 12, CATCH).replace("{FEATHER}", ""))
        a(ellipse_shape(f"Dot{nm}", ex + 3, -16, 6, 6, CATCH).replace("{FEATHER}", ""))
        a(f'<Shape x="{f(ex + 9)}" y="10" opacity="0.32" name="Wet{nm}"><Ellipse width="13" height="11" name="Path"/>'
          f'<Fill fillRule="clockwise" name="C"><SolidColor colorValue="{CATCH}" name="C"/>'
          f'<Feather strength="3" name="Soft"/></Fill></Shape>')
        a(ellipse_shape(f"Eye{nm}", ex, 0, EYE_D, EYE_D, INK).replace("{FEATHER}", ""))
    a('</Node>')
    # Happy eyes: ^ ^
    a('<Node scaleX="0" scaleY="0" name="Happy">')
    for side, nm in ((-1, "L"), (1, "R")):
        a(f'<Shape x="{side * EYE_X}" y="2" name="Arc{nm}"><PointsPath name="Path">')
        for i in range(13):
            t = -1 + 2 * i / 12
            a(f'<StraightVertex x="{f(t * 17)}" y="{f(-12 * math.cos(t * math.pi / 2) + 4)}"/>')
        a(f'</PointsPath><Stroke thickness="5.5" cap="round" join="round" name="Ink">'
          f'<SolidColor colorValue="{INK}" name="C"/></Stroke></Shape>')
    a('</Node>')
    a('</Node>')  # Eyes
    a('</Node>')  # Look
    # Mouths: one shows at a time, by scale.
    a('<Node name="Mouths">')
    smile = []
    for i in range(17):
        t = -1 + 2 * i / 16
        smile.append((t * 17, 24 + 8 * (1 - t * t)))
    a('<Shape name="Smile"><PointsPath name="Path">')
    for x, y in smile:
        a(f'<StraightVertex x="{f(x)}" y="{f(y)}"/>')
    a(f'</PointsPath><Stroke thickness="4.5" cap="round" join="round" name="Ink">'
      f'<SolidColor colorValue="{INK}" name="C"/></Stroke></Shape>')
    # A small "o": wondering.
    a(f'<Shape x="0" y="32" scaleX="0" scaleY="0" name="Ooh"><Ellipse width="11" height="13" name="Path"/>'
      f'<Fill name="Ink"><SolidColor colorValue="{INK}" name="C"/></Fill></Shape>')
    # A short level line: concentrating.
    a(f'<Shape x="0" y="30" scaleX="0" scaleY="0" name="Flat"><PointsPath name="Path">'
      f'<StraightVertex x="-8" y="0"/><StraightVertex x="0" y="1.2"/><StraightVertex x="8" y="0"/></PointsPath>'
      f'<Stroke thickness="4.5" cap="round" join="round" name="Ink"><SolidColor colorValue="{INK}" name="C"/></Stroke></Shape>')
    # A big open grin, with a tongue (blush) in it.
    a('<Node x="0" y="24" scaleX="0" scaleY="0" name="Grin">')
    a(f'<Shape y="9" name="Tongue"><Ellipse width="16" height="9" name="Path"/>'
      f'<Fill name="Pink"><SolidColor colorValue="{BLUSH}" name="C"/></Fill></Shape>')
    a('<Shape name="Mouth"><PointsPath isClosed="true" name="Path">')
    for i in range(21):
        t = i / 20
        ang = math.pi * t
        a(f'<StraightVertex x="{f(-17 * math.cos(ang))}" y="{f(15 * math.sin(ang))}"/>')
    a(f'</PointsPath><Fill name="Ink"><SolidColor colorValue="{INK}" name="C"/></Fill></Shape>')
    a('</Node>')
    a('</Node>')  # Mouths
    a('<Node name="Blush">')
    for side, nm in ((-1, "L"), (1, "R")):
        a(ellipse_shape(f"Blush{nm}", side * 100, 30, 44, 20, BLUSH, ' fillRule="clockwise"')
          .replace("{FEATHER}", '<Feather strength="8" name="Soft"/>'))
    a('</Node>')
    a('</Node>')  # Head
    a('</Bone></RootBone>')
    a(f'<RootBone y="{f(-CENTER_H)}" rotation="{f(math.pi)}" length="{f(SIDE_LEN)}" name="SideL" id="{ids["sideL"]}"/>')
    a(f'<RootBone y="{f(-CENTER_H)}" length="{f(SIDE_LEN)}" name="SideR" id="{ids["sideR"]}"/>')
    a('</Node></Node>')

    # The body, skinned to Body (bottom), Crown (top) and the two sides.
    a('<Shape name="Body"><PointsPath isClosed="true" name="Path">')
    for x, y in body_points():
        h = BASE[1] - y
        wc = smoothstep(50, 215, h)
        dx = (x - BASE[0]) / HALF_W
        ws = smoothstep(0.3, 1.0, abs(dx)) * 0.75
        side = 2 if dx < 0 else 3
        a(f'<StraightVertex x="{f(x)}" y="{f(y)}">'
          f'{weight([(0, (1 - wc) * (1 - ws)), (1, wc * (1 - ws)), (side, ws)])}</StraightVertex>')
    a('<Skin name="Skin">')
    a(tendon(ids["body"], body_m, "Body"))
    a(tendon(ids["crown"], crown_m, "Crown"))
    a(tendon(ids["sideL"], side_l_m, "SideL"))
    a(tendon(ids["sideR"], side_r_m, "SideR"))
    a('</Skin></PointsPath>')
    a(f'<Fill name="Material"><SolidColor colorValue="{BODY}" name="C"/></Fill></Shape>')

    # Idle: a blink every four seconds.
    a(f'<StateMachine name="Rig" id="{ids["sm"]}"><StateMachineLayer name="Face">'
      f'<EntryState><StateTransition stateToId="{ids["idleState"]}"/></EntryState>'
      f'<AnimationState x="200" animationId="{ids["idle"]}" id="{ids["idleState"]}"/>'
      f'</StateMachineLayer></StateMachine>')
    a(f'<LinearAnimation loopValue="loop" fps="60" duration="240" name="Idle" id="{ids["idle"]}">'
      f'<KeyedObject objectId="{ids["eyes"]}"><KeyedProperty property="scaleY">'
      f'<KeyFrameDouble value="1" frame="0" interpolationType="hold"/>'
      f'<KeyFrameDouble value="1" frame="200" interpolationType="cubic"><CubicEaseInterpolator x1="0.5" y1="0" x2="0.9" y2="0.6"/></KeyFrameDouble>'
      f'<KeyFrameDouble value="0.08" frame="205" interpolationType="cubic"><CubicEaseInterpolator x1="0.2" y1="0.4" x2="0.4" y2="1"/></KeyFrameDouble>'
      f'<KeyFrameDouble value="1" frame="213" interpolationType="hold"/>'
      f'</KeyedProperty></KeyedObject></LinearAnimation>')
    a('</Artboard>')
    return ids, L


VM = "0:900"
VMI = "0:899"
VM_PROPS = {"state": "0:901", "wobble": "0:902"}
VM_KINDS = {"state": "Number", "wobble": "Number"}
BIND_KEY = {"Number": 243, "Boolean": 245}

INPUTS = [
    # name, type, default
    ("state", "Number", "0"),
    ("width", "Number", "512"),
    ("height", "Number", "512"),
    ("resolution", "Number", "1"),
    ("bodyColor", "Color", "FF4F9BFF"),
    ("deepColor", "Color", "FF1B4AA8"),
    ("glowColor", "Color", "FF8EE3FF"),
    ("inkColor", "Color", "FF0A1838"),
    ("blushColor", "Color", "FFFF8DB5"),
    ("backdropColor", "Color", "FFF3F7FF"),
    ("gloss", "Number", "1"),
    ("translucency", "Number", "1"),
    ("glow", "Number", "1"),
    ("rim", "Number", "1"),
    ("outline", "Number", "0.6"),
    ("paint", "Number", "0.3"),
    ("wobble", "Number", "1"),
    ("shadow", "Number", "1"),
]


def main_artboard(rig_id):
    ids = {k: nid() for k in ("ab", "style", "jelly", "script", "sm", "anim", "st")}
    L = []
    a = L.append
    a(f'<Artboard defaultStateMachineId="{ids["sm"]}" viewModelId="{VM}" viewModelInstanceId="{VMI}" '
      f'width="{SIZE}" height="{SIZE}" styleId="{ids["style"]}" name="Blob" id="{ids["ab"]}">')
    a(f'<LayoutComponentStyle name="Blob Style" id="{ids["style"]}"/>')
    a(f'<ScriptedDrawable scriptAssetId="{{SCRIPT}}" x="{SIZE // 2}" y="{SIZE // 2}" name="Jelly" id="{ids["jelly"]}">')
    a(f'<ScriptInputArtboard artboardId="{rig_id}" name="rig" id="{nid()}"/>')
    for name, kind, val in INPUTS:
        if name in VM_PROPS:
            a(f'<ScriptInput{kind} propertyValue="{val}" name="{name}" id="{nid()}">'
              f'<DataBindContext sourcePathIds="{VM}-{VM_PROPS[name]}" propertyKey="{BIND_KEY[kind]}" id="{nid()}"/>'
              f'</ScriptInput{kind}>')
        else:
            a(f'<ScriptInput{kind} propertyValue="{val}" name="{name}" id="{nid()}"/>')
    a('</ScriptedDrawable>')
    # The backdrop: a soft warm studio.
    a(f'<Fill name="Backdrop"><RadialGradient startX="{SIZE * 0.5}" startY="{SIZE * 0.42}" '
      f'endX="{SIZE * 0.5}" endY="{SIZE * 1.15}" name="G">'
      f'<GradientStop colorValue="FFFBFDFF" position="0" name="Inner"/>'
      f'<GradientStop colorValue="FFE2EAF7" position="1" name="Outer"/></RadialGradient></Fill>')
    a(f'<StateMachine name="Blob" id="{ids["sm"]}"><StateMachineLayer name="Base">'
      f'<EntryState><StateTransition stateToId="{ids["st"]}"/></EntryState>'
      f'<AnimationState x="200" animationId="{ids["anim"]}" id="{ids["st"]}"/>'
      f'</StateMachineLayer></StateMachine>')
    a(f'<LinearAnimation loopValue="loop" duration="60" name="Still" id="{ids["anim"]}"/>')
    a('</Artboard>')
    return ids, L


def view_model():
    """The Blob view model: what a page sets. `state`: 0 idle, 1 thinking,
    2 retrieving, 3 executing, 4 planning, 5 done (happy)."""
    L = [f'<ViewModel name="Blob" id="{VM}">']
    for name, pid in VM_PROPS.items():
        L.append(f'<ViewModelProperty{VM_KINDS[name]} name="{name}" id="{pid}"/>')
    L.append(f'<ViewModelInstance exports="true" name="Default" id="{VMI}">')
    defaults = {n: v for n, _, v in INPUTS}
    for name, pid in VM_PROPS.items():
        L.append(f'<ViewModelInstance{VM_KINDS[name]} propertyValue="{defaults[name]}" viewModelPropertyId="{pid}" id="{nid()}"/>')
    L.append('</ViewModelInstance></ViewModel>')
    return L


def main():
    rig_ids, rig = rig_artboard()
    main_ids, blob = main_artboard(rig_ids["ab"])
    script_id, comp_id, shader_id = nid(), nid(), nid()
    out = ['<Rive version="1" kind="fragment">',
           '<!-- The blob character. Written by ../tools/make_scene.py; edit that. -->']
    out += [line.replace("{SCRIPT}", script_id) for line in blob]
    out += rig
    out += view_model()
    out.append(f'<ComponentAsset artboardId="{rig_ids["ab"]}" name="BlobRig" id="{comp_id}"/>')
    out.append(f'<ScriptAsset file="Jelly.luau" scriptProtocolValue="1" name="Jelly" id="{script_id}"/>')
    out.append(f'<ShaderAsset file="jelly.wgsl" name="jelly" id="{shader_id}"/>')
    out.append('</Rive>')
    OUT.write_text("\n".join(out) + "\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
