#!/usr/bin/env python3
"""Generates scene.rml (DailyDivination main artboard + SM).

Usage, from the project root:  python3 tools/gen_scene.py scene.rml
Fan pose, stage/result positions and clip lengths are the constants below."""
import math, random, sys

OUT = sys.argv[1]
W, H = 390, 844
GOLD = "FFD4AF37"
GOLD2 = "FFC9A84C"

# Stage: the hero pose origin. Cards are children placed relative to it.
SX, SY = 195, 300          # loading / reveal card center
FAN_C = (195, 350)         # fan ring center
FAN_SCALE = 0.54
REVEAL_SCALE = 0.72
RESULT = (76, 84, 0.42)    # stage x, y, scale in Result
BOX_TOP, BOX_H = 196, 372
BOX_W = W - 48

# Fan pose, artboard space: x, y, rotation(deg). Card5 draws on top.
FAN = [
    (86, 382, -38),
    (138, 356, -19),
    (195, 346, 0),
    (252, 356, 19),
    (304, 382, 38),
]

EASE_OUT = "0:0:0.58:1"
EASE_IN = "0.42:0:1:1"
EASE_IO = "0.42:0:0.58:1"
EASE_SOFT = "0.33:0:0.2:1"

ids = {"n": 1000}
def nid():
    ids["n"] += 1
    return f"7:{ids['n']}"

interps = {}
def interp(curve):
    if curve not in interps:
        interps[curve] = nid()
    return interps[curve]

def kf(frame, value, curve=None, kind="Double"):
    if curve is None:
        return f'<KeyFrame{kind} value="{value}" interpolationType="linear" frame="{frame}"/>'
    if curve == "hold":
        return f'<KeyFrame{kind} value="{value}" interpolationType="hold" frame="{frame}"/>'
    x1, y1, x2, y2 = curve.split(":")
    return (f'<KeyFrame{kind} value="{value}" interpolationType="cubic" frame="{frame}">'
            f'<CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"/></KeyFrame{kind}>')

def fmt(v):
    return f"{v:.4f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)

class Anim:
    def __init__(self, name, frames, loop=False):
        self.name, self.frames, self.loop = name, frames, loop
        self.id = nid()
        self.keys = {}  # (obj, prop) -> list of xml
    def key(self, obj, prop, frame, value, curve=None, kind="Double"):
        self.keys.setdefault((obj, prop), []).append(
            (frame, kf(frame, fmt(value) if kind == "Double" else value, curve, kind)))
    def tween(self, obj, prop, f0, v0, f1, v1, curve=EASE_OUT):
        self.key(obj, prop, f0, v0, curve)
        self.key(obj, prop, f1, v1, curve)
    def hold(self, obj, prop, value):
        self.key(obj, prop, 0, value)
    def xml(self):
        loop = ' loopValue="loop"' if self.loop else ""
        out = [f'        <LinearAnimation duration="{self.frames}"{loop} name="{self.name}" id="{self.id}">']
        byobj = {}
        for (obj, prop), ks in self.keys.items():
            byobj.setdefault(obj, []).append((prop, ks))
        for obj, props in byobj.items():
            out.append(f'            <KeyedObject objectId="{obj}">')
            for prop, ks in props:
                out.append(f'                <KeyedProperty propertyKey="{prop}">')
                seen = set()
                for frame, x in sorted(ks, key=lambda t: t[0]):
                    if frame in seen:
                        continue
                    seen.add(frame)
                    out.append("                    " + x)
                out.append("                </KeyedProperty>")
            out.append("            </KeyedObject>")
        out.append("        </LinearAnimation>")
        return "\n".join(out)

X, Y, ROT, SCX, SCY, OPA = 13, 14, 15, 16, 17, 18
REMAP_TIME = 202
DRAW_TARGET = 121

rad = math.radians

# ---------------------------------------------------------------- objects
card = {}
for i in range(1, 6):
    b = i * 100
    card[i] = dict(node=f"6:{b}", hit=f"6:{b+1}", nested=f"6:{b+2}", remap=f"6:{b+3}",
                   glow=f"6:{b+4}", rules=f"6:{b+5}", target=f"6:{b+6}")
STAGE, ANCHOR = "5:20", "5:21"
RING, RING_SPIN = "5:30", "5:31"
ORBITS, ORBIT_SPIN = "5:40", "5:41"
FANRING, FANRING_SPIN = "5:50", "5:51"
BOX = "5:60"
REVEAL_TAP = "5:80"

def fan_rel(i):
    x, y, r = FAN[i - 1]
    return x - SX, y - SY, rad(r)

def star_shape(name, x, y, size, color, inner=0.28, sid=None):
    ida = f' id="{sid}"' if sid else ""
    return f'''<Shape x="{x}" y="{y}" name="{name}"{ida}>
    <Star originX="0.5" originY="0.5" width="{size}" height="{size}" points="4" innerRadius="{inner}" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="{color}" name="Color"/></Fill>
</Shape>'''

def indent(s, n):
    pad = " " * n
    return "\n".join(pad + l if l.strip() else l for l in s.splitlines())

parts = []

# ContentBox: host puts copy on top. Top of draw order.
parts.append(f'''<Node x="{SX}" y="{H + 40 + BOX_H / 2}" opacity="0" name="ContentBox" id="{BOX}">
    <Shape name="Sheet">
        <Rectangle originX="0.5" originY="0.5" width="{BOX_W}" height="{BOX_H}" cornerRadiusTL="18" name="Path"/>
        <Fill name="Fill">
            <LinearGradient startX="0" startY="{-BOX_H / 2}" endX="0" endY="{BOX_H / 2}" name="Body">
                <GradientStop colorValue="E61B1830" position="0"/>
                <GradientStop colorValue="E612101C" position="1"/>
            </LinearGradient>
        </Fill>
        <Stroke thickness="1" name="Edge">
            <SolidColor colorValue="33D4AF37" name="Color"/>
        </Stroke>
    </Shape>
</Node>''')

# Preview-only tap on the loading card: fires `reveal`.
parts.append(f'''<Shape x="{SX}" y="{SY}" name="PreviewRevealTap" id="{REVEAL_TAP}">
    <Rectangle originX="0.5" originY="0.5" width="160" height="280" name="Path"/>
</Shape>''')

# Stage with the five cards. Card5 first = drawn on top in the fan.
cards_xml = []
for i in range(5, 0, -1):
    c = card[i]
    x, y, r = fan_rel(i)
    cards_xml.append(f'''<Node x="{fmt(x)}" y="{fmt(y)}" rotation="{fmt(r)}" scaleX="{FAN_SCALE}" scaleY="{FAN_SCALE}" name="Card{i}" id="{c['node']}">
    <DrawRules name="BringToFront" id="{c['rules']}">
        <DrawTarget drawableId="{ANCHOR}" placementValue="before" name="AboveAll" id="{c['target']}"/>
    </DrawRules>
    <Shape isTargetOpaque="true" name="Hit" id="{c['hit']}">
        <Rectangle originX="0.5" originY="0.5" width="160" height="280" name="Path"/>
    </Shape>
    <NestedArtboard artboardId="40:1" x="-80" y="-140" name="TarotCard" id="{c['nested']}">
        <NestedRemapAnimation animationId="40:13" time="0" name="Flip" id="{c['remap']}"/>
    </NestedArtboard>
    <Shape opacity="0" name="Glow" id="{c['glow']}">
        <Rectangle originX="0.5" originY="0.5" width="166" height="286" cornerRadiusTL="14" name="Path"/>
        <Stroke thickness="10" name="Halo">
            <SolidColor colorValue="B3E8C45A" name="Color"/>
            <Feather strength="22" name="Feather"/>
        </Stroke>
        <Stroke thickness="2" name="Rim">
            <SolidColor colorValue="99F3D98A" name="Color"/>
            <Feather strength="4" name="Feather"/>
        </Stroke>
    </Shape>
</Node>''')

parts.append(f'''<Node x="{SX}" y="{SY}" name="Stage" id="{STAGE}">
    <Shape name="FrontAnchor" id="{ANCHOR}">
        <Rectangle originX="0.5" originY="0.5" width="0" height="0" name="Path"/>
    </Shape>
{indent(chr(10).join(cards_xml), 4)}
</Node>''')

# Reveal ring: bright double gold ring + ticks, around the revealed card.
def ring_ticks(r, size, color):
    out = []
    for k, ang in enumerate([-90, 90, 200, -20]):
        a = rad(ang)
        s = size if k < 2 else size * 0.6
        out.append(star_shape(f"Tick{k+1}", fmt(r * math.cos(a)), fmt(r * math.sin(a)), fmt(s), color, 0.22))
    return "\n".join(out)

parts.append(f'''<Node x="{SX}" y="{SY}" opacity="0" name="Ring" id="{RING}">
    <Node name="Spin" id="{RING_SPIN}">
{indent(ring_ticks(150, 16, "FFF3D98A"), 8)}
        <Shape name="Outer">
            <Ellipse originX="0.5" originY="0.5" width="300" height="300" name="Path"/>
            <Stroke thickness="6" name="Glow">
                <SolidColor colorValue="80D4AF37" name="Color"/>
                <Feather strength="10" name="Feather"/>
            </Stroke>
            <Stroke thickness="1.6" name="Line">
                <SolidColor colorValue="{GOLD}" name="Color"/>
            </Stroke>
        </Shape>
        <Shape name="Inner">
            <Ellipse originX="0.5" originY="0.5" width="284" height="284" name="Path"/>
            <Stroke thickness="0.8" name="Line">
                <SolidColor colorValue="66D4AF37" name="Color"/>
            </Stroke>
        </Shape>
    </Node>
    <Shape name="Disc">
        <Ellipse originX="0.5" originY="0.5" width="270" height="270" name="Path"/>
        <Fill name="Fill">
            <RadialGradient startX="0" startY="0" endX="135" endY="0" name="Shade">
                <GradientStop colorValue="CC1C1636" position="0"/>
                <GradientStop colorValue="B3151027" position="0.85"/>
                <GradientStop colorValue="00151027" position="1"/>
            </RadialGradient>
        </Fill>
    </Shape>
</Node>''')

# Loading orbits: faint, large, slowly turning.
parts.append(f'''<Node x="{SX}" y="{SY}" opacity="0" name="Orbits" id="{ORBITS}">
    <Node name="Spin" id="{ORBIT_SPIN}">
{indent(star_shape("Spark1", fmt(178 * math.cos(rad(-35))), fmt(178 * math.sin(rad(-35))), 9, "CCF3D98A"), 8)}
{indent(star_shape("Spark2", fmt(178 * math.cos(rad(160))), fmt(178 * math.sin(rad(160))), 7, "99F3D98A"), 8)}
{indent(star_shape("Spark3", fmt(205 * math.cos(rad(70))), fmt(205 * math.sin(rad(70))), 6, "80F3D98A"), 8)}
        <Shape name="OrbitA">
            <Ellipse originX="0.5" originY="0.5" width="356" height="356" name="Path"/>
            <Stroke thickness="1" name="Line">
                <SolidColor colorValue="40D4AF37" name="Color"/>
                <DashPath name="Dashes">
                    <Dash length="140" name="On"/>
                    <Dash length="40" name="Off"/>
                </DashPath>
            </Stroke>
        </Shape>
        <Shape name="OrbitB">
            <Ellipse originX="0.5" originY="0.5" width="410" height="410" name="Path"/>
            <Stroke thickness="1" name="Line">
                <SolidColor colorValue="26B8A2E8" name="Color"/>
            </Stroke>
        </Shape>
    </Node>
    <Shape name="Aura">
        <Ellipse originX="0.5" originY="0.5" width="420" height="420" name="Path"/>
        <Fill name="Fill">
            <RadialGradient startX="0" startY="0" endX="210" endY="0" name="Shade">
                <GradientStop colorValue="402A1C66" position="0"/>
                <GradientStop colorValue="002A1C66" position="1"/>
            </RadialGradient>
        </Fill>
    </Shape>
</Node>''')

# Fan ring: gold circle behind the hand, ticks top and bottom.
fx, fy = FAN_C
parts.append(f'''<Node x="{fx}" y="{fy}" name="FanRing" id="{FANRING}">
    <Node name="Spin" id="{FANRING_SPIN}">
{indent(star_shape("TickTop", 0, -136, 14, "FFF3D98A", 0.22), 8)}
{indent(star_shape("TickBottom", 0, 136, 14, "FFF3D98A", 0.22), 8)}
        <Shape name="Outer">
            <Ellipse originX="0.5" originY="0.5" width="272" height="272" name="Path"/>
            <Stroke thickness="1.4" name="Line">
                <SolidColor colorValue="E6D4AF37" name="Color"/>
            </Stroke>
        </Shape>
        <Shape name="Inner">
            <Ellipse originX="0.5" originY="0.5" width="252" height="252" name="Path"/>
            <Stroke thickness="0.8" name="Line">
                <SolidColor colorValue="4DD4AF37" name="Color"/>
            </Stroke>
        </Shape>
    </Node>
    <Shape name="Disc">
        <Ellipse originX="0.5" originY="0.5" width="250" height="250" name="Path"/>
        <Fill name="Fill">
            <RadialGradient startX="0" startY="0" endX="125" endY="0" name="Shade">
                <GradientStop colorValue="99130E26" position="0"/>
                <GradientStop colorValue="66130E26" position="0.8"/>
                <GradientStop colorValue="00130E26" position="1"/>
            </RadialGradient>
        </Fill>
    </Shape>
</Node>''')

# Stars: scattered, a subset twinkles.
random.seed(7)
stars = []
twinkle_ids = []
for k in range(34):
    x = round(random.uniform(10, W - 10))
    y = round(random.uniform(10, H - 10))
    big = k % 6 == 0
    size = random.choice([7, 9, 11]) if big else random.choice([2, 2.5, 3])
    alpha = random.choice(["FF", "CC", "99", "66"])
    sid = f"5:{200 + k}"
    if big:
        stars.append(star_shape(f"Star{k}", x, y, size, alpha + "F3E3B0", 0.18, sid))
    else:
        stars.append(f'''<Shape x="{x}" y="{y}" name="Dot{k}" id="{sid}">
    <Ellipse originX="0.5" originY="0.5" width="{size}" height="{size}" name="Path"/>
    <Fill name="Fill"><SolidColor colorValue="{alpha}E8E0FF" name="Color"/></Fill>
</Shape>''')
    if k % 3 == 0:
        twinkle_ids.append(sid)
parts.append(f'''<Node name="Stars">
{indent(chr(10).join(stars), 4)}
</Node>''')

# Nebula: soft purple clouds.
neb = []
for k, (x, y, r, c) in enumerate([(60, 180, 240, "402B1A6E"), (340, 520, 280, "38301C78"),
                                 (120, 760, 260, "30231560"), (300, 60, 200, "2C3A2280")]):
    neb.append(f'''<Shape x="{x}" y="{y}" name="Cloud{k+1}">
    <Ellipse originX="0.5" originY="0.5" width="{r*2}" height="{r*1.5}" name="Path"/>
    <Fill name="Fill">
        <RadialGradient startX="0" startY="0" endX="{r}" endY="0" name="Shade">
            <GradientStop colorValue="{c}" position="0"/>
            <GradientStop colorValue="{c[:0]}00{c[2:]}" position="1"/>
        </RadialGradient>
    </Fill>
</Shape>''')
parts.append(f'''<Node name="Nebula">
{indent(chr(10).join(neb), 4)}
</Node>''')

parts.append(f'''<Shape x="{W/2}" y="{H/2}" name="Sky">
    <Rectangle originX="0.5" originY="0.5" width="{W}" height="{H}" name="Path"/>
    <Fill name="Fill">
        <LinearGradient startX="0" startY="{-H/2}" endX="0" endY="{H/2}" name="Depth">
            <GradientStop colorValue="FF0B0624" position="0"/>
            <GradientStop colorValue="FF120A2E" position="0.55"/>
            <GradientStop colorValue="FF07041A" position="1"/>
        </LinearGradient>
    </Fill>
</Shape>''')

# ---------------------------------------------------------------- animations
anims = []

# Ambient (own layer, always running): stars twinkle, rings turn.
amb = Anim("Ambient", 720, loop=True)  # 12s
amb.tween(RING_SPIN, ROT, 0, 0, 720, 2 * math.pi, None)
amb.tween(ORBIT_SPIN, ROT, 0, 0, 720, -2 * math.pi, None)
for k, sid in enumerate(twinkle_ids):
    ph = (k * 97) % 720
    period = 240
    for f in range(0, 721, 60):
        v = 0.55 + 0.45 * math.cos(2 * math.pi * (f + ph) / period)
        amb.key(sid, OPA, f, round(v, 3))
anims.append(amb)

# FanIdle: each card floats, out of phase.
fan = Anim("FanIdle", 180, loop=True)
for i in range(1, 6):
    x, y, r = fan_rel(i)
    ph = [0, 0.37, 0.71, 0.18, 0.55][i - 1]
    n = fan_node = card[i]["node"]
    for f in range(0, 181, 15):
        t = 2 * math.pi * (f / 180 + ph)
        fan.key(n, Y, f, round(y + 6 * math.sin(t), 3))
        fan.key(n, ROT, f, round(r + rad(1.5) * math.sin(t + 1.1), 5))
        s = FAN_SCALE * (1.01 + 0.01 * math.sin(t + 2.0))
        fan.key(n, SCX, f, round(s, 4))
        fan.key(n, SCY, f, round(s, 4))
    fan.hold(n, X, round(x, 3))
    fan.hold(n, OPA, 1)
    fan.hold(card[i]["glow"], OPA, 0)
    fan.hold(card[i]["remap"], REMAP_TIME, 0)
fan.hold(FANRING, OPA, 1)
fan.hold(ORBITS, OPA, 0)
fan.hold(RING, OPA, 0)
fan.hold(STAGE, X, SX); fan.hold(STAGE, Y, SY)
fan.hold(STAGE, SCX, 1); fan.hold(STAGE, SCY, 1)
anims.append(fan)

# Select1..5: hero to center, the rest drop away.
SEL = 42
selects = {}
for hero in range(1, 6):
    a = Anim(f"Select{hero}", SEL)
    a.key(card[hero]["rules"], DRAW_TARGET, 0, card[hero]["target"], "hold", "Id")
    order = 0
    for i in range(1, 6):
        c = card[i]
        x, y, r = fan_rel(i)
        if i == hero:
            a.tween(c["node"], X, 0, x, SEL, 0, EASE_OUT)
            a.tween(c["node"], Y, 0, y, SEL, 0, EASE_OUT)
            a.tween(c["node"], ROT, 0, r, SEL, 0, EASE_OUT)
            a.tween(c["node"], SCX, 0, FAN_SCALE, SEL, 1, EASE_OUT)
            a.tween(c["node"], SCY, 0, FAN_SCALE, SEL, 1, EASE_OUT)
            a.hold(c["node"], OPA, 1)
            a.tween(c["glow"], OPA, 18, 0, SEL, 1, EASE_OUT)
            a.key(c["glow"], OPA, 0, 0)
        else:
            start = 2 * order
            order += 1
            end = start + 26
            side = -1 if i < hero else 1
            a.key(c["node"], X, 0, x)
            a.tween(c["node"], X, start, x, end, x + side * 30, EASE_IN)
            a.key(c["node"], Y, 0, y)
            a.tween(c["node"], Y, start, y, end, y + 460, EASE_IN)
            a.key(c["node"], ROT, 0, r)
            a.tween(c["node"], ROT, start, r, end, r + side * rad(14), EASE_IN)
            a.hold(c["node"], SCX, FAN_SCALE)
            a.hold(c["node"], SCY, FAN_SCALE)
            a.key(c["node"], OPA, 0, 1)
            a.tween(c["node"], OPA, start + 4, 1, end, 0, EASE_IN)
            a.hold(c["glow"], OPA, 0)
        a.hold(c["remap"], REMAP_TIME, 0)
    a.tween(FANRING, OPA, 0, 1, 16, 0, EASE_OUT)
    a.tween(FANRING, SCX, 0, 1, 16, 1.15, EASE_OUT)
    a.tween(FANRING, SCY, 0, 1, 16, 1.15, EASE_OUT)
    a.tween(ORBITS, OPA, SEL - 14, 0, SEL, 1, EASE_OUT)
    a.hold(RING, OPA, 0)
    a.hold(STAGE, X, SX); a.hold(STAGE, Y, SY)
    a.hold(STAGE, SCX, 1); a.hold(STAGE, SCY, 1)
    selects[hero] = a
    anims.append(a)

# Loading: hero breathes, glow pulses, orbits stay up.
load = Anim("Loading", 150, loop=True)
for f, dy, g in [(0, 0, 1), (75, -4, 0.55), (150, 0, 1)]:
    load.key(STAGE, Y, f, SY + dy, EASE_IO)
    for i in range(1, 6):
        load.key(card[i]["glow"], OPA, f, g, EASE_IO)
load.hold(ORBITS, OPA, 1)
load.hold(FANRING, OPA, 0)
load.hold(RING, OPA, 0)
anims.append(load)

# Flip: 3pi turn on every card's slab (only the hero is visible), card
# settles smaller as the gold ring comes in.
FLIP = 72
flip = Anim("Flip", FLIP)
for i in range(1, 6):
    flip.tween(card[i]["remap"], REMAP_TIME, 0, 0, FLIP, 1, EASE_IO)
    flip.tween(card[i]["glow"], OPA, 0, 1, 10, 0, EASE_OUT)
flip.tween(STAGE, Y, 0, SY, FLIP, SY, EASE_IO)
flip.tween(STAGE, SCX, 0, 1, FLIP, REVEAL_SCALE, EASE_IO)
flip.tween(STAGE, SCY, 0, 1, FLIP, REVEAL_SCALE, EASE_IO)
flip.tween(ORBITS, OPA, 0, 1, 30, 0, EASE_OUT)
flip.tween(RING, OPA, 24, 0, FLIP, 1, EASE_OUT)
flip.tween(RING, SCX, 24, 0.86, FLIP, 1, EASE_OUT)
flip.tween(RING, SCY, 24, 0.86, FLIP, 1, EASE_OUT)
flip.key(RING, OPA, 0, 0)
anims.append(flip)

# Reveal hold: the face sits in the ring for a beat before the result.
reveal_hold = Anim("RevealHold", 54)
reveal_hold.hold(RING, OPA, 1)
reveal_hold.hold(STAGE, SCX, REVEAL_SCALE)
reveal_hold.hold(STAGE, SCY, REVEAL_SCALE)
anims.append(reveal_hold)

# Result: card up to the corner, ring out, sheet up.
RES = 33
res = Anim("Result", RES)
rx, ry, rs = RESULT
res.tween(STAGE, X, 0, SX, RES, rx, EASE_OUT)
res.tween(STAGE, Y, 0, SY, RES, ry, EASE_OUT)
res.tween(STAGE, SCX, 0, REVEAL_SCALE, RES, rs, EASE_OUT)
res.tween(STAGE, SCY, 0, REVEAL_SCALE, RES, rs, EASE_OUT)
res.tween(RING, OPA, 0, 1, 16, 0, EASE_OUT)
res.tween(RING, SCX, 0, 1, RES, 0.7, EASE_OUT)
res.tween(RING, SCY, 0, 1, RES, 0.7, EASE_OUT)
res.tween(BOX, Y, 4, H + 40 + BOX_H / 2, RES, BOX_TOP + BOX_H / 2, EASE_OUT)
res.key(BOX, Y, 0, H + 40 + BOX_H / 2)
res.tween(BOX, OPA, 4, 0, RES, 1, EASE_OUT)
res.key(BOX, OPA, 0, 0)
anims.append(res)

# ---------------------------------------------------------------- state machine
def vm_trigger_cond(prop):
    return f'''<TransitionViewModelCondition opValue="equal">
    <TransitionPropertyViewModelComparator>
        <BindablePropertyTrigger>
            <DataBindContext sourcePathIds="10:1-{prop}" propertyKey="686"/>
        </BindablePropertyTrigger>
    </TransitionPropertyViewModelComparator>
    <TransitionValueTriggerComparator/>
</TransitionViewModelCondition>'''

PICK = {1: "10:2", 2: "10:3", 3: "10:4", 4: "10:5", 5: "10:6"}
REVEAL = "10:7"

S_FAN, S_LOAD, S_FLIP, S_HOLD, S_RES = "8:10", "8:20", "8:30", "8:31", "8:40"
S_SEL = {i: f"8:{10 + i}" for i in range(1, 6)}

fan_out = "\n".join(
    f'''<StateTransition stateToId="{S_SEL[i]}" duration="120">
{indent(vm_trigger_cond(PICK[i]), 4)}
</StateTransition>''' for i in range(1, 6))

sel_states = "\n".join(
    f'''<AnimationState animationId="{selects[i].id}" x="{120 * (i - 1)}" y="160" id="{S_SEL[i]}">
    <StateTransition stateToId="{S_LOAD}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
</AnimationState>''' for i in range(1, 6))

sm = f'''<StateMachine name="Divination" id="8:1">
    <StateMachineLayer name="Flow" id="8:2">
        <AnyState x="-240" y="0"/>
        <ExitState x="760" y="640"/>
        <EntryState x="240" y="-120">
            <StateTransition stateToId="{S_FAN}"/>
        </EntryState>
        <AnimationState animationId="{fan.id}" x="240" y="0" id="{S_FAN}">
{indent(fan_out, 12)}
        </AnimationState>
{indent(sel_states, 8)}
        <AnimationState animationId="{load.id}" x="240" y="320" id="{S_LOAD}">
            <StateTransition stateToId="{S_FLIP}">
{indent(vm_trigger_cond(REVEAL), 16)}
            </StateTransition>
        </AnimationState>
        <AnimationState animationId="{flip.id}" x="240" y="440" id="{S_FLIP}">
            <StateTransition stateToId="{S_HOLD}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
        </AnimationState>
        <AnimationState animationId="{reveal_hold.id}" x="240" y="540" id="{S_HOLD}">
            <StateTransition stateToId="{S_RES}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
        </AnimationState>
        <AnimationState animationId="{res.id}" x="240" y="640" id="{S_RES}"/>
    </StateMachineLayer>
    <StateMachineLayer name="Ambient" id="8:3">
        <AnyState x="-240" y="0"/>
        <ExitState x="400" y="0"/>
        <EntryState x="0" y="-120">
            <StateTransition stateToId="8:4"/>
        </EntryState>
        <AnimationState animationId="{amb.id}" x="0" y="0" id="8:4"/>
    </StateMachineLayer>
'''

def listener(i):
    return f'''<StateMachineListenerSingle targetId="{card[i]['hit']}" listenerTypeValue="click" name="Tap Card{i}">
    <ListenerViewModelChange>
        <BindablePropertyTrigger propertyValue="1">
            <DataBindContext sourcePathIds="10:1-{PICK[i]}" propertyKey="686" direction="true"/>
        </BindablePropertyTrigger>
    </ListenerViewModelChange>
</StateMachineListenerSingle>'''

sm += indent("\n".join(listener(i) for i in range(1, 6)), 4) + "\n"
sm += f'''    <!-- Preview only: tap the loading card to reveal. Remove if the app owns the gate. -->
    <StateMachineListenerSingle targetId="{REVEAL_TAP}" listenerTypeValue="click" name="Preview Reveal">
        <ListenerViewModelChange>
            <BindablePropertyTrigger propertyValue="1">
                <DataBindContext sourcePathIds="10:1-{REVEAL}" propertyKey="686" direction="true"/>
            </BindablePropertyTrigger>
        </ListenerViewModelChange>
    </StateMachineListenerSingle>
</StateMachine>'''

interp_xml = "\n".join(
    f'<CubicEaseInterpolator x1="{c.split(":")[0]}" y1="{c.split(":")[1]}" x2="{c.split(":")[2]}" y2="{c.split(":")[3]}" id="{i}"/>'
    for c, i in interps.items())

doc = f'''<Rive version="1" kind="fragment">
    <!-- Generated layout; see PLAN.md. First declared draws on top. -->
    <Artboard defaultStateMachineId="8:1" viewModelId="10:1" viewModelInstanceId="10:9" x="700" y="0" width="{W}" height="{H}" name="DailyDivination" id="50:1" styleId="50:2">
        <LayoutComponentStyle name="DailyDivination Style" id="50:2"/>
{indent(interp_xml, 8)}

{indent(chr(10).join(parts), 8)}

{indent(sm, 8)}

{chr(10).join(a.xml() for a in anims)}
    </Artboard>
</Rive>
'''
open(OUT, "w").write(doc)
print("wrote", OUT, len(doc))
