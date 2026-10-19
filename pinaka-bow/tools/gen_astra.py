# Generates pinaka-bow/rive/astra.rml: the Astra artboard.
#
#   python3 tools/gen_astra.py rive/astra.rml   (from pinaka-bow/)
#
# Edit the artboard here, not in astra.rml, then regenerate and
# `rive rive --verify`. Edits made in the Rive editor need copying back here.
import itertools, sys
out_path = sys.argv[1]
ids = itertools.count(1000)
def nid(): return f"2:{next(ids)}"

NUM, COL = 243, 836
GOLD = dict(aura="FFFFB040", imprint="FFFFD28C", arrow="FFFFC060", tint="00000000", style=0)
ASTRAS = [
    ("Brahmashirsha", "pullBrahmashirsha", GOLD),
    ("Parjanyastra", "pullParjanyastra", dict(aura="FF1E9BFF", imprint="FF9AD8FF", arrow="FF35B6FF", tint="FF1C7CFF", style=1)),
    ("Nagastra", "pullNagastra", dict(aura="FF2CFF6A", imprint="FFB0FFC4", arrow="FF3DFF7A", tint="FF19E05A", style=2)),
    ("Vajrastra", "pullVajrastra", dict(aura="FFB040FF", imprint="FFE2B0FF", arrow="FFC060FF", tint="FF9B30FF", style=3)),
    ("Agneyastra", "pullAgneyastra", dict(aura="FFFF5A1E", imprint="FFFFC08A", arrow="FFFF7A2A", tint="FFFF4A12", style=4)),
    # Shiva's own astra: the trident arrow, neon purple blended with neon pink.
    ("Pashupatastra", "pullPashupatastra", dict(aura="FF7A2BFF", accent="FFFF2BD6", imprint="FFE9B8FF", arrow="FFC77BFF", tint="FFA02BE0", style=5, trident=1, omen="FFFF1F2E", spread=55)),
]

# Inputs that animations key, by node.
BOW = dict(stretch="2:420", charge="2:421", release="2:422", arrow="2:423", flight="2:424",
           auraColor="2:430", imprintColor="2:431", arrowColor="2:432", auraStyle="2:433", astraFade="2:434", trident="2:435", accentColor="2:436")
SKY = dict(heat="2:82", blast="2:84", speed="2:90", tint="2:91", omen="2:92", omenColor="2:93", spread="2:94", complement="2:97", hueA="2:98", hueB="2:99")
FXF = dict(charge="2:21", burst="2:22", tint="2:24")
FXB = dict(charge="2:61", burst="2:62", tint="2:64")

def kf_num(frame, value, ease=None):
    v = f' value="{value}"' if value else ''
    fr = f' frame="{frame}"' if frame else ''
    if ease:
        return f'<KeyFrameDouble{v} interpolationType="2"{fr} id="{nid()}"><CubicEaseInterpolator x1="{ease[0]}" y1="{ease[1]}" x2="{ease[2]}" y2="{ease[3]}" id="{nid()}"/></KeyFrameDouble>'
    return f'<KeyFrameDouble{v} interpolationType="1"{fr} id="{nid()}"/>'

def kf_col(frame, value):
    fr = f' frame="{frame}"' if frame else ''
    return f'<KeyFrameColor value="{value}" interpolationType="1"{fr} id="{nid()}"/>'

def keyed(obj, prop, frames):
    body = "\n".join("                    " + f for f in frames)
    return (f'            <KeyedObject objectId="{obj}" id="{nid()}">\n'
            f'                <KeyedProperty propertyKey="{prop}" id="{nid()}">\n{body}\n'
            f'                </KeyedProperty>\n            </KeyedObject>')

def anim(name, aid, duration, keys, loop=False, comment=""):
    lp = ' loopValue="1"' if loop else ''
    c = f'        <!-- {comment} -->\n' if comment else ''
    return (f'{c}        <LinearAnimation duration="{duration}"{lp} name="{name}" id="{aid}">\n'
            + "\n".join(keys) + '\n        </LinearAnimation>')

EASE_PULL = (0.33, 0, 0.2, 1)
EASE_CHARGE = (0.6, 0, 0.3, 1)
EASE_OUT = (0.15, 0.5, 0.35, 1)

anims = []
# Idle
anims.append(anim("Idle", "2:110", 60, [
    keyed(BOW["stretch"], NUM, [kf_num(0, 0)]),
    keyed(BOW["charge"], NUM, [kf_num(0, 0)]),
    keyed(BOW["release"], NUM, [kf_num(0, 0)]),
    keyed(BOW["arrow"], NUM, [kf_num(0, 0)]),
    keyed(BOW["flight"], NUM, [kf_num(0, 0)]),
    keyed(BOW["astraFade"], NUM, [kf_num(0, 0)]),
    keyed(SKY["heat"], NUM, [kf_num(0, 0)]),
    keyed(SKY["blast"], NUM, [kf_num(0, 0)]),
    keyed(SKY["speed"], NUM, [kf_num(0, 0)]),
    keyed(SKY["omen"], NUM, [kf_num(0, 0)]),
    keyed(FXF["charge"], NUM, [kf_num(0, 0)]), keyed(FXF["burst"], NUM, [kf_num(0, 0)]),
    keyed(FXB["charge"], NUM, [kf_num(0, 0)]), keyed(FXB["burst"], NUM, [kf_num(0, 0)]),
], loop=True, comment="Idle: the bow at rest, no arrow, the sky still."))

# The string-drawing sound (scene.rml's `bowPull` audio asset, 0:910).
DRAW_SOUND = "2:96"

pull_ids = {}
for i, (name, trig, c) in enumerate(ASTRAS):
    aid = f"2:{111 + i}"
    pull_ids[name] = aid
    anims.append(anim(f"Pull{name}", aid, 114, [
        keyed(BOW["arrow"], NUM, [kf_num(0, 0, (0.4, 0, 0.4, 1)), kf_num(45, 1)]),
        keyed(BOW["stretch"], NUM, [kf_num(0, 0), kf_num(30, 0, EASE_PULL), kf_num(114, 10)]),
        keyed(BOW["charge"], NUM, [kf_num(0, 0), kf_num(30, 0, EASE_CHARGE), kf_num(114, 1)]),
        keyed(BOW["release"], NUM, [kf_num(0, 0)]),
        keyed(BOW["flight"], NUM, [kf_num(0, 0)]),
        keyed(BOW["auraColor"], COL, [kf_col(0, c["aura"])]),
        keyed(BOW["imprintColor"], COL, [kf_col(0, c["imprint"])]),
        keyed(BOW["astraFade"], NUM, [kf_num(0, 0, (0.4, 0, 0.6, 1)), kf_num(40, 1)]),
        keyed(BOW["arrowColor"], COL, [kf_col(0, c["arrow"])]),
        keyed(BOW["auraStyle"], NUM, [kf_num(0, c["style"])]),
        keyed(BOW["trident"], NUM, [kf_num(0, c.get("trident", 0))]),
        keyed(BOW["accentColor"], COL, [kf_col(0, c.get("accent", "00000000"))]),
        keyed(SKY["heat"], NUM, [kf_num(0, 0), kf_num(30, 0, EASE_CHARGE), kf_num(114, 0.6)]),
        keyed(SKY["speed"], NUM, [kf_num(0, 0)]),
        keyed(SKY["blast"], NUM, [kf_num(0, 0)]),
        keyed(SKY["tint"], COL, [kf_col(0, c["tint"])]),
        keyed(SKY["omenColor"], COL, [kf_col(0, c.get("omen", "00000000"))]),
        keyed(SKY["spread"], NUM, [kf_num(0, c.get("spread", 0))]),
        keyed(SKY["complement"], NUM, [kf_num(0, c.get("complement", 0))]),
        keyed(SKY["hueA"], NUM, [kf_num(0, c.get("harmony", (130, 130))[0])]),
        keyed(SKY["hueB"], NUM, [kf_num(0, c.get("harmony", (130, 130))[1])]),
        keyed(FXF["charge"], NUM, [kf_num(0, 0)]), keyed(FXF["burst"], NUM, [kf_num(0, 0)]),
        keyed(FXB["charge"], NUM, [kf_num(0, 0)]), keyed(FXB["burst"], NUM, [kf_num(0, 0)]),
        keyed(FXF["tint"], COL, [kf_col(0, c["tint"])]),
        keyed(FXB["tint"], COL, [kf_col(0, c["tint"])]),
        # The stretch sound, as the string starts to draw.
        f'            <KeyedObject objectId="{DRAW_SOUND}" id="{nid()}">\n'
        f'                <KeyedProperty propertyKey="395" id="{nid()}">\n'
        f'                    <KeyFrameCallback frame="30" id="{nid()}"/>\n'
        f'                </KeyedProperty>\n            </KeyedObject>',
    ], comment=f"Pull{name}: the arrow forms on the string out of light, then the bow draws over 1.4s and holds, charged" + ("" if c["style"] == 0 else f", in {name}'s colour and aura (" + ["", "mist", "pollen", "lightning", "fire", "fine pollen, purple and pink, the trident"][c["style"]] + ")") + "."))

EVENT = "2:95"
anims.append(anim("Flight", "2:120", 140, [
    keyed(BOW["stretch"], NUM, [kf_num(0, 10), kf_num(1, 0)]),
    keyed(BOW["release"], NUM, [kf_num(0, 0), kf_num(108, 1)]),
    keyed(BOW["charge"], NUM, [kf_num(0, 1, EASE_OUT), kf_num(40, 0)]),
    keyed(BOW["flight"], NUM, [kf_num(0, 0), kf_num(48, 1)]),
    keyed(BOW["arrow"], NUM, [kf_num(0, 1)]),
    keyed(SKY["speed"], NUM, [kf_num(0, 0, (0.5, 0, 0.3, 1)), kf_num(50, 0.8)]),
    keyed(SKY["heat"], NUM, [kf_num(0, 0.6, EASE_OUT), kf_num(40, 0.35)]),
    f'            <KeyedObject objectId="{EVENT}" id="{nid()}">\n'
    f'                <KeyedProperty propertyKey="395" id="{nid()}">\n'
    f'                    <KeyFrameCallback frame="120" id="{nid()}"/>\n'
    f'                </KeyedProperty>\n            </KeyedObject>',
], comment="Flight: the arrow is loosed and streaks up to stand in the sky, the bow falling away below; the stars streak past (the clouds stay). At 2s the `blast` event fires (a listener turns it into the `blast` trigger)."))

anims.append(anim("Blast", "2:130", 210, [
    keyed(BOW["arrow"], NUM, [kf_num(0, 1), kf_num(56, 1, (0.5, 0, 0.7, 1)), kf_num(64, 0)]),
    keyed(BOW["flight"], NUM, [kf_num(0, 1), kf_num(150, 1, (0.4, 0, 0.2, 1)), kf_num(200, 0)]),
    keyed(BOW["stretch"], NUM, [kf_num(0, 0)]),
    keyed(BOW["charge"], NUM, [kf_num(0, 0)]),
    # Back to the resting gold once the arrow is gone, while the bow is
    # still below the frame.
    keyed(BOW["astraFade"], NUM, [kf_num(0, 1), kf_num(64, 1), kf_num(76, 0)]),
    keyed(SKY["speed"], NUM, [kf_num(0, 0.8, (0.2, 0.6, 0.4, 1)), kf_num(54, 0)]),
    keyed(SKY["heat"], NUM, [kf_num(0, 0.35, (0.5, 0, 0.5, 1)), kf_num(54, 0.8, (0.3, 0, 0.5, 1)), kf_num(190, 0)]),
    keyed(SKY["blast"], NUM, [kf_num(0, 0), kf_num(54, 0, (0.1, 0.7, 0.3, 1)), kf_num(86, 1, (0.4, 0, 0.6, 1)), kf_num(200, 0)]),
    # The astra's omen (if it has one) flushes the clouds as the stars
    # encircle the tip, and clears after the burst.
    keyed(SKY["omen"], NUM, [kf_num(0, 0, (0.4, 0, 0.6, 1)), kf_num(50, 1), kf_num(62, 1, (0.4, 0, 0.6, 1)), kf_num(120, 0)]),
    *[keyed(fx["charge"], NUM, [kf_num(0, 0, (0.5, 0, 0.5, 1)), kf_num(54, 1), kf_num(140, 1), kf_num(150, 0)]) for fx in (FXF, FXB)],
    # The burst ends at 1 (drawing nothing) and stays there: dropping it
    # back to 0 a frame later replays mid-explosion in between. Idle resets it.
    *[keyed(fx["burst"], NUM, [kf_num(0, 0), kf_num(54, 0), kf_num(150, 1)]) for fx in (FXF, FXB)],
], comment="Blast: the sky slows and stars encircle the arrow's tip (0.9s), then it bursts: flash, rays, shockwave, sparks, the clouds blown back; the bow rises back into place."))

def trig_cond(prop):
    return (f'<TransitionViewModelCondition id="{nid()}">\n'
            f'                            <TransitionPropertyViewModelComparator id="{nid()}">\n'
            f'                                <BindablePropertyTrigger id="{nid()}">\n'
            f'                                    <DataBindContext sourcePathIds="2:500-{prop}" propertyKey="686" id="{nid()}"/>\n'
            f'                                </BindablePropertyTrigger>\n'
            f'                            </TransitionPropertyViewModelComparator>\n'
            f'                            <TransitionValueTriggerComparator id="{nid()}"/>\n'
            f'                        </TransitionViewModelCondition>')

VM_TRIG = {"pullBrahmashirsha": "2:501", "pullParjanyastra": "2:502", "pullNagastra": "2:503", "pullVajrastra": "2:504", "pullAgneyastra": "2:508", "pullPashupatastra": "2:509", "fire": "2:505", "blast": "2:506"}

PULL_STATE = {name: f"2:{141 + i}" for i, (name, _, _) in enumerate(ASTRAS)}
any_trans = "\n".join(
    f'                    <StateTransition stateToId="{PULL_STATE[name]}" id="{nid()}">\n'
    f'                        {trig_cond(VM_TRIG[trig])}\n'
    f'                    </StateTransition>' for name, trig, _ in ASTRAS)
pull_states = "\n".join(
    f'                <!-- Pulled{name}. -->\n'
    f'                <AnimationState x="{-150 + 200 * i}" y="160" animationId="{pull_ids[name]}" id="{PULL_STATE[name]}">\n'
    f'                    <StateTransition stateToId="2:150" id="{nid()}">\n'
    f'                        {trig_cond(VM_TRIG["fire"])}\n'
    f'                    </StateTransition>\n'
    f'                </AnimationState>' for i, (name, _, _) in enumerate(ASTRAS))

def sin(name, iid, value=None, bind=None):
    v = f' propertyValue="{value}"' if value is not None else ''
    if bind:
        return (f'            <ScriptInputNumber{v} name="{name}" id="{iid}">\n'
                f'                <DataBindContext sourcePathIds="2:500-{bind}" propertyKey="243" id="{nid()}"/>\n'
                f'            </ScriptInputNumber>')
    return f'            <ScriptInputNumber{v} name="{name}" id="{iid}"/>'
def sic(name, iid, value): return f'            <ScriptInputColor propertyValue="{value}" name="{name}" id="{iid}"/>'

def fx(name, nodeid, layer, ids_):
    return (f'        <ScriptedDrawable scriptAssetId="2:907" x="640" y="190" scaleX="1.4" scaleY="1.4" name="{name}" id="{nodeid}">\n'
            + "\n".join([sin("charge", ids_["charge"]), sin("burst", ids_["burst"]), sin("layer", nid(), layer),
                         sic("tint", ids_["tint"], "00000000")]) + '\n        </ScriptedDrawable>')

bow_inputs = "\n".join([
    f'            <ScriptInputString propertyValue="pinaka" name="asset" id="{nid()}"/>',
    sin("width", nid(), 1280), sin("height", nid(), 720), sin("resolution", nid(), 1.25), sin("msaa", nid(), 4),
    sin("power", nid()), sin("aura", nid(), 1, bind="2:507"), sin("sway", nid(), 5),
    sin("rotationX", nid(), -10), sin("rotationY", nid()), sin("rotationZ", nid()),
    sin("spinX", nid()), sin("spinY", nid()), sin("spinZ", nid()),
    f'            <ScriptInputBoolean name="showArrow" id="{nid()}"/>',
    sin("zoom", nid(), 1.2), sin("offsetY", nid(), 65), sin("drawDepth", nid(), 1), sin("flightTipY", nid(), -170),
    sin("stretch", BOW["stretch"]), sin("charge", BOW["charge"]), sin("release", BOW["release"]),
    sin("arrow", BOW["arrow"]), sin("flight", BOW["flight"]),
    sic("goldColor", nid(), "FFC4A058"), sic("woodColor", nid(), "FF452014"),
    sic("auraColor", BOW["auraColor"], GOLD["aura"]), sic("imprintColor", BOW["imprintColor"], GOLD["imprint"]),
    sic("arrowColor", BOW["arrowColor"], GOLD["arrow"]),
    sic("accentColor", BOW["accentColor"], "00000000"),
    sin("auraStyle", BOW["auraStyle"]),
    sin("astraFade", BOW["astraFade"]),
    sin("trident", BOW["trident"]),
])
sky_inputs = "\n".join([
    sin("width", nid(), 1280), sin("height", nid(), 720), sin("heat", SKY["heat"]), sin("focusY", nid(), 190),
    sin("blast", SKY["blast"]), sin("grain", nid(), 1), sin("mist", nid(), 1),
    sin("cursorRadius", nid(), 180), sin("cursorStrength", nid(), 0.5), sin("speed", SKY["speed"]),
    sic("tint", SKY["tint"], "00000000"),
    sin("omen", SKY["omen"]), sic("omenColor", SKY["omenColor"], "00000000"),
    sin("tintSpread", SKY["spread"]), sin("tintComplement", SKY["complement"]),
    sin("harmonyA", SKY["hueA"], 130), sin("harmonyB", SKY["hueB"], 130),
])

listener_change = (f'            <ListenerViewModelChange id="{nid()}">\n'
                   f'                <BindablePropertyTrigger propertyValue="1" id="{nid()}">\n'
                   f'                    <DataBindContext sourcePathIds="2:500-2:506" propertyKey="686" direction="true" id="{nid()}"/>\n'
                   f'                </BindablePropertyTrigger>\n'
                   f'            </ListenerViewModelChange>')

vm_props = "\n".join(f'        <ViewModelPropertyTrigger name="{n}" id="{i}"/>' for n, i in VM_TRIG.items())
vm_inst = "\n".join(f'            <ViewModelInstanceTrigger viewModelPropertyId="{i}" id="{nid()}"/>' for i in VM_TRIG.values())

rml = f'''<Rive version="1" kind="fragment">
    <!-- Astra: the Pinaka looses an astra. The bow lies level, belly up, in
         the lower part of the frame; a pull trigger (pullBrahmashirsha,
         pullParjanyastra, pullNagastra, pullVajrastra, pullAgneyastra,
         pullPashupatastra)
         forms the arrow on the string and draws it, the aura and arrow in
         that astra's colour; `fire` looses it into the sky; 2s later the
         `blast` event fires the `blast` trigger, stars encircle the arrow's
         tip and it bursts, and the bow rises back to rest. -->
    <Artboard defaultStateMachineId="2:100" viewModelId="2:500" viewModelInstanceId="2:510" x="1480" width="1280" height="720" styleId="2:2" name="Astra" id="2:1">
        <LayoutComponentStyle name="Astra Style" id="2:2"/>
        <!-- The burst around the arrow's tip: in front of the arrow... -->
{fx("BurstFront", "2:20", 1, FXF)}
        <ScriptedDrawable scriptAssetId="0:902" x="640" y="360" name="Bow" id="2:40">
{bow_inputs}
        </ScriptedDrawable>
        <!-- ...and behind it. -->
{fx("BurstBack", "2:60", 0, FXB)}
        <!-- The celestial sky. -->
        <ScriptedDrawable scriptAssetId="0:905" name="Sky" id="2:80">
{sky_inputs}
        </ScriptedDrawable>
        <Event name="blast" id="{EVENT}"/>
        <AudioEvent assetId="0:910" name="draw" id="{DRAW_SOUND}"/>
        <Fill name="Night" id="2:3">
            <RadialGradient name="Vignette" id="2:4" startX="640" startY="360" endX="1400" endY="360">
                <GradientStop colorValue="FF0C0A18" name="Centre" id="2:5"/>
                <GradientStop colorValue="FF020208" position="1" name="Edge" id="2:6"/>
            </RadialGradient>
        </Fill>
        <StateMachine name="Astra" id="2:100">
            <StateMachineLayer name="Flow" id="2:101">
                <!-- Any of the four pulls, from anywhere. -->
                <AnyState x="300" y="-120" id="2:102">
{any_trans}
                </AnyState>
                <ExitState x="600" y="-120" id="2:103"/>
                <EntryState id="2:104">
                    <StateTransition stateToId="2:105" id="{nid()}"/>
                </EntryState>
                <AnimationState x="100" animationId="2:110" id="2:105"/>
{pull_states}
                <!-- Flight: `fire` from any pulled state. -->
                <AnimationState x="300" y="320" animationId="2:120" id="2:150">
                    <StateTransition stateToId="2:160" id="{nid()}">
                        {trig_cond(VM_TRIG["blast"])}
                    </StateTransition>
                </AnimationState>
                <!-- Blast, then back to rest. -->
                <AnimationState x="300" y="460" animationId="2:130" id="2:160">
                    <StateTransition stateToId="2:105" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100" id="{nid()}"/>
                </AnimationState>
            </StateMachineLayer>
            <!-- The Flight animation's `blast` event fires the `blast` trigger. -->
            <StateMachineListenerSingle targetId="2:1" listenerTypeValue="event" eventId="{EVENT}" name="Blast on event" id="{nid()}">
{listener_change}
            </StateMachineListenerSingle>
        </StateMachine>
{chr(10).join(anims)}
    </Artboard>

    <ViewModel name="Astra" id="2:500">
{vm_props}
        <ViewModelPropertyNumber name="aura" id="2:507"/>
        <ViewModelInstance exports="true" name="Default" id="2:510">
{vm_inst}
            <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="2:507" id="{nid()}"/>
        </ViewModelInstance>
    </ViewModel>

    <ScriptAsset file="CosmicFX.luau" scriptProtocolValue="1" name="CosmicFX" id="2:907"/>
</Rive>
'''
open(out_path, "w").write(rml)
print("wrote", out_path)
