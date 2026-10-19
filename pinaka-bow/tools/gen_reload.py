# Generates pinaka-bow/rive/reload.rml: the Reload artboard, the Pinaka as a
# pull-to-refresh on a phone.
#
#   python3 tools/gen_reload.py rive/reload.rml   (from pinaka-bow/)
#
# The host page drives it through the `Reload` view model:
#   pull   0-100, how far the finger has dragged down; poses the bow live
#   fire   trigger, on release past the threshold
#   aura, accent, imprint, arrow, tint, omen (colours), style (0-5),
#          trident (0/1):
#          the astra for this pull, set before the drag starts
# and listens for two events as the blast clears: `reload` (bring in the new
# mail) and `done` (fade the sky away to the inbox).
import itertools, sys

out_path = sys.argv[1]
ids = itertools.count(1000)
def nid(): return f"3:{next(ids)}"

NUM, COL = 243, 836
W, H = 390, 844
TIP_Y = 232          # where the arrow's tip stands in flight, and the blast

BOW = dict(stretch="3:420", charge="3:421", release="3:422", arrow="3:423", flight="3:424", astraFade="3:425")
SKY = dict(heat="3:82", blast="3:84", speed="3:90", omen="3:92")
FXF = dict(charge="3:21", burst="3:22")
FXB = dict(charge="3:61", burst="3:62")
VM = dict(pull="3:501", fire="3:502", blast="3:503", aura="3:504", imprint="3:505", arrow="3:506", tint="3:507", style="3:508", trident="3:509", accent="3:511", omen="3:512", spread="3:513", complement="3:514", hueA="3:515", hueB="3:516")
EVENTS = dict(blast="3:95", reload="3:96", done="3:97")

def kf(frame, value, ease=None):
    v = f' value="{value}"' if value else ''
    fr = f' frame="{frame}"' if frame else ''
    if ease:
        return f'<KeyFrameDouble{v} interpolationType="2"{fr} id="{nid()}"><CubicEaseInterpolator x1="{ease[0]}" y1="{ease[1]}" x2="{ease[2]}" y2="{ease[3]}" id="{nid()}"/></KeyFrameDouble>'
    return f'<KeyFrameDouble{v} interpolationType="1"{fr} id="{nid()}"/>'

def keyed(obj, frames, prop=NUM):
    body = "\n".join("                    " + f for f in frames)
    return (f'            <KeyedObject objectId="{obj}" id="{nid()}">\n'
            f'                <KeyedProperty propertyKey="{prop}" id="{nid()}">\n{body}\n'
            f'                </KeyedProperty>\n            </KeyedObject>')

def event_key(event, frame):
    return (f'            <KeyedObject objectId="{event}" id="{nid()}">\n'
            f'                <KeyedProperty propertyKey="395" id="{nid()}">\n'
            f'                    <KeyFrameCallback frame="{frame}" id="{nid()}"/>\n'
            f'                </KeyedProperty>\n            </KeyedObject>')

def anim(name, aid, duration, keys, comment):
    return (f'        <!-- {comment} -->\n'
            f'        <LinearAnimation duration="{duration}" name="{name}" id="{aid}">\n'
            + "\n".join(keys) + '\n        </LinearAnimation>')

EASE_OUT = (0.15, 0.5, 0.35, 1)
EASE_IO = (0.4, 0, 0.2, 1)

# The drag's three poses: every one keys the same properties, so the blend
# mixes rather than jumps.
def pose(name, aid, v, comment):
    return anim(name, aid, 1, [
        keyed(BOW["stretch"], [kf(0, v["stretch"])]),
        keyed(BOW["charge"], [kf(0, v["charge"])]),
        keyed(BOW["arrow"], [kf(0, v["arrow"])]),
        keyed(BOW["astraFade"], [kf(0, v["fade"])]),
        keyed(BOW["release"], [kf(0, 0)]),
        keyed(BOW["flight"], [kf(0, 0)]),
        keyed(SKY["heat"], [kf(0, v["heat"])]),
        keyed(SKY["speed"], [kf(0, 0)]),
        keyed(SKY["blast"], [kf(0, 0)]),
        keyed(SKY["omen"], [kf(0, 0)]),
        *[keyed(fx[p], [kf(0, 0)]) for fx in (FXF, FXB) for p in ("charge", "burst")],
    ], comment)

anims = [
    pose("DragRest", "3:110", dict(stretch=0, charge=0, arrow=0, fade=0, heat=0),
         "DragRest (pull 0): the bow at rest, no arrow."),
    pose("DragNock", "3:111", dict(stretch=1.5, charge=0.2, arrow=1, fade=1, heat=0.15),
         "DragNock (pull 30): the arrow has formed on the string in the astra's light."),
    pose("DragFull", "3:112", dict(stretch=10, charge=1, arrow=1, fade=1, heat=0.6),
         "DragFull (pull 100): fully drawn and charged."),
    anim("Fly", "3:120", 50, [
        keyed(BOW["stretch"], [kf(0, 10), kf(1, 0)]),
        keyed(BOW["release"], [kf(0, 0), kf(48, 1)]),
        keyed(BOW["charge"], [kf(0, 1, EASE_OUT), kf(30, 0)]),
        keyed(BOW["flight"], [kf(0, 0), kf(36, 1)]),
        keyed(BOW["arrow"], [kf(0, 1)]),
        keyed(BOW["astraFade"], [kf(0, 1)]),
        keyed(SKY["speed"], [kf(0, 0, (0.5, 0, 0.3, 1)), kf(30, 0.8)]),
        keyed(SKY["heat"], [kf(0, 0.6, EASE_OUT), kf(36, 0.4)]),
        event_key(EVENTS["blast"], 48),
    ], "Fly: released, the arrow snaps off and streaks up the screen, the bow falling away; at 0.8s the `blast` event fires the `blast` trigger."),
    anim("Blast", "3:130", 120, [
        keyed(BOW["arrow"], [kf(0, 1), kf(22, 1, (0.5, 0, 0.7, 1)), kf(30, 0)]),
        # The bow stays gone: the page hands the screen back to the inbox.
        keyed(BOW["flight"], [kf(0, 1)]),
        keyed(BOW["stretch"], [kf(0, 0)]),
        keyed(BOW["charge"], [kf(0, 0)]),
        keyed(BOW["astraFade"], [kf(0, 1), kf(30, 1), kf(40, 0)]),
        keyed(SKY["speed"], [kf(0, 0.8, (0.2, 0.6, 0.4, 1)), kf(22, 0)]),
        keyed(SKY["heat"], [kf(0, 0.4, (0.5, 0, 0.5, 1)), kf(22, 0.8, (0.3, 0, 0.5, 1)), kf(96, 0)]),
        keyed(SKY["blast"], [kf(0, 0), kf(22, 0, (0.1, 0.7, 0.3, 1)), kf(44, 1, (0.4, 0, 0.6, 1)), kf(110, 0)]),
        # The astra's omen (if it has one) flushes the clouds in the build-up.
        keyed(SKY["omen"], [kf(0, 0, (0.4, 0, 0.6, 1)), kf(20, 1), kf(28, 1, (0.4, 0, 0.6, 1)), kf(76, 0)]),
        *[keyed(fx["charge"], [kf(0, 0, (0.5, 0, 0.5, 1)), kf(22, 1), kf(60, 1), kf(66, 0)]) for fx in (FXF, FXB)],
        # The burst ends at 1 and stays (the drag's poses reset it).
        *[keyed(fx["burst"], [kf(0, 0), kf(22, 0), kf(90, 1)]) for fx in (FXF, FXB)],
        # As the blast clears: `reload` (the page adds the new mail) and
        # `done` (it fades the sky away to the inbox). The animation runs on
        # past them so the reset to rest happens unseen.
        event_key(EVENTS["reload"], 82),
        event_key(EVENTS["done"], 84),
    ], "Blast: stars encircle the tip (0.35s), then it bursts; as it clears, `reload` and `done` fire and the page brings the inbox back. The bow does not return."),
]

def trig_cond(prop):
    return (f'<TransitionViewModelCondition id="{nid()}">\n'
            f'                            <TransitionPropertyViewModelComparator id="{nid()}">\n'
            f'                                <BindablePropertyTrigger id="{nid()}">\n'
            f'                                    <DataBindContext sourcePathIds="3:500-{prop}" propertyKey="686" id="{nid()}"/>\n'
            f'                                </BindablePropertyTrigger>\n'
            f'                            </TransitionPropertyViewModelComparator>\n'
            f'                            <TransitionValueTriggerComparator id="{nid()}"/>\n'
            f'                        </TransitionViewModelCondition>')

def bind(prop, key):
    return f'<DataBindContext sourcePathIds="3:500-{prop}" propertyKey="{key}" id="{nid()}"/>'

def sin(name, iid, value=None):
    v = f' propertyValue="{value}"' if value is not None else ''
    return f'            <ScriptInputNumber{v} name="{name}" id="{iid}"/>'

def sin_bound(name, iid, prop):
    return (f'            <ScriptInputNumber name="{name}" id="{iid}">\n'
            f'                {bind(prop, NUM)}\n'
            f'            </ScriptInputNumber>')

def sic(name, iid, value):
    return f'            <ScriptInputColor propertyValue="{value}" name="{name}" id="{iid}"/>'

def sic_bound(name, iid, prop, value):
    return (f'            <ScriptInputColor propertyValue="{value}" name="{name}" id="{iid}">\n'
            f'                {bind(prop, COL)}\n'
            f'            </ScriptInputColor>')

def fx(name, nodeid, layer, ids_):
    return (f'        <ScriptedDrawable scriptAssetId="2:907" x="{W / 2:g}" y="{TIP_Y}" name="{name}" id="{nodeid}">\n'
            + "\n".join([sin("charge", ids_["charge"]), sin("burst", ids_["burst"]), sin("layer", nid(), layer),
                         sic_bound("tint", nid(), VM["tint"], "00000000")]) + '\n        </ScriptedDrawable>')

GOLD = dict(aura="FFFFB040", imprint="FFFFD28C", arrow="FFFFC060")
bow_inputs = "\n".join([
    f'            <ScriptInputString propertyValue="pinaka" name="asset" id="{nid()}"/>',
    sin("width", nid(), W), sin("height", nid(), H), sin("resolution", nid(), 2), sin("msaa", nid(), 4),
    sin("power", nid()), sin("aura", nid(), 1), sin("sway", nid(), 4),
    sin("rotationX", nid(), -10), sin("rotationY", nid()), sin("rotationZ", nid()),
    sin("spinX", nid()), sin("spinY", nid()), sin("spinZ", nid()),
    f'            <ScriptInputBoolean name="showArrow" id="{nid()}"/>',
    sin("zoom", nid(), 0.45), sin("offsetY", nid(), 60), sin("drawDepth", nid(), 1),
    sin("flightTipY", nid(), TIP_Y - H // 2),
    sin("stretch", BOW["stretch"]), sin("charge", BOW["charge"]), sin("release", BOW["release"]),
    sin("arrow", BOW["arrow"]), sin("flight", BOW["flight"]), sin("astraFade", BOW["astraFade"]),
    sin_bound("auraStyle", nid(), VM["style"]),
    sin_bound("trident", nid(), VM["trident"]),
    sic("goldColor", nid(), "FFC4A058"), sic("woodColor", nid(), "FF452014"),
    sic_bound("auraColor", nid(), VM["aura"], GOLD["aura"]),
    sic_bound("imprintColor", nid(), VM["imprint"], GOLD["imprint"]),
    sic_bound("arrowColor", nid(), VM["arrow"], GOLD["arrow"]),
    sic_bound("accentColor", nid(), VM["accent"], "00000000"),
])
sky_inputs = "\n".join([
    sin("width", nid(), W), sin("height", nid(), H), sin("heat", SKY["heat"]), sin("focusY", nid(), TIP_Y),
    sin("blast", SKY["blast"]), sin("grain", nid(), 1), sin("mist", nid(), 1),
    sin("cursorRadius", nid(), 80), sin("cursorStrength", nid(), 0), sin("speed", SKY["speed"]),
    sic_bound("tint", nid(), VM["tint"], "00000000"),
    sin("omen", SKY["omen"]), sic_bound("omenColor", nid(), VM["omen"], "00000000"),
    sin_bound("tintSpread", nid(), VM["spread"]),
    sin_bound("tintComplement", nid(), VM["complement"]),
    sin_bound("harmonyA", nid(), VM["hueA"]),
    sin_bound("harmonyB", nid(), VM["hueB"]),
])

rml = f'''<Rive version="1" kind="fragment">
    <!-- Reload: the Pinaka as a pull-to-refresh on a phone (390x844). The
         page drags `pull` (0-100) to draw the bow live, fires `fire` on
         release, and listens for the `reload` and `done` events. Generated
         by tools/gen_reload.py. -->
    <Artboard defaultStateMachineId="3:100" viewModelId="3:500" viewModelInstanceId="3:510" x="2960" width="{W}" height="{H}" styleId="3:2" name="Reload" id="3:1">
        <LayoutComponentStyle name="Reload Style" id="3:2"/>
{fx("BurstFront", "3:20", 1, FXF)}
        <ScriptedDrawable scriptAssetId="0:902" x="{W / 2:g}" y="{H / 2:g}" name="Bow" id="3:40">
{bow_inputs}
        </ScriptedDrawable>
{fx("BurstBack", "3:60", 0, FXB)}
        <ScriptedDrawable scriptAssetId="0:905" name="Sky" id="3:80">
{sky_inputs}
        </ScriptedDrawable>
        <Event name="blast" id="{EVENTS["blast"]}"/>
        <Event name="reload" id="{EVENTS["reload"]}"/>
        <Event name="done" id="{EVENTS["done"]}"/>
        <Fill name="Night" id="3:3">
            <RadialGradient name="Vignette" id="3:4" startX="{W / 2:g}" startY="{TIP_Y}" endX="{W / 2:g}" endY="{H}">
                <GradientStop colorValue="FF0C0A18" name="Centre" id="3:5"/>
                <GradientStop colorValue="FF020208" position="1" name="Edge" id="3:6"/>
            </RadialGradient>
        </Fill>
        <StateMachine name="Reload" id="3:100">
            <StateMachineLayer name="Flow" id="3:101">
                <AnyState x="300" y="-120" id="3:102"/>
                <ExitState x="600" y="-120" id="3:103"/>
                <EntryState id="3:104">
                    <StateTransition stateToId="3:105" id="{nid()}"/>
                </EntryState>
                <!-- Drag: `pull` poses the bow live; `fire` looses it. -->
                <BlendState1DViewModel x="100" id="3:105">
                    <BindablePropertyNumber id="{nid()}">
                        {bind(VM["pull"], 636)}
                    </BindablePropertyNumber>
                    <BlendAnimation1D animationId="3:110" value="0" id="{nid()}"/>
                    <BlendAnimation1D animationId="3:111" value="30" id="{nid()}"/>
                    <BlendAnimation1D animationId="3:112" value="100" id="{nid()}"/>
                    <BlendStateTransition stateToId="3:150" id="{nid()}">
                        {trig_cond(VM["fire"])}
                    </BlendStateTransition>
                </BlendState1DViewModel>
                <AnimationState x="100" y="160" animationId="3:120" id="3:150">
                    <StateTransition stateToId="3:160" id="{nid()}">
                        {trig_cond(VM["blast"])}
                    </StateTransition>
                </AnimationState>
                <AnimationState x="100" y="300" animationId="3:130" id="3:160">
                    <StateTransition stateToId="3:105" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100" id="{nid()}"/>
                </AnimationState>
            </StateMachineLayer>
            <!-- The Fly animation's `blast` event fires the `blast` trigger. -->
            <StateMachineListenerSingle targetId="3:1" listenerTypeValue="event" eventId="{EVENTS["blast"]}" name="Blast on event" id="{nid()}">
                <ListenerViewModelChange id="{nid()}">
                    <BindablePropertyTrigger propertyValue="1" id="{nid()}">
                        <DataBindContext sourcePathIds="3:500-{VM["blast"]}" propertyKey="686" direction="true" id="{nid()}"/>
                    </BindablePropertyTrigger>
                </ListenerViewModelChange>
            </StateMachineListenerSingle>
        </StateMachine>
{chr(10).join(anims)}
    </Artboard>

    <ViewModel name="Reload" id="3:500">
        <ViewModelPropertyNumber name="pull" id="{VM["pull"]}"/>
        <ViewModelPropertyTrigger name="fire" id="{VM["fire"]}"/>
        <ViewModelPropertyTrigger name="blast" id="{VM["blast"]}"/>
        <ViewModelPropertyColor name="aura" id="{VM["aura"]}"/>
        <ViewModelPropertyColor name="imprint" id="{VM["imprint"]}"/>
        <ViewModelPropertyColor name="arrow" id="{VM["arrow"]}"/>
        <ViewModelPropertyColor name="tint" id="{VM["tint"]}"/>
        <ViewModelPropertyColor name="accent" id="{VM["accent"]}"/>
        <ViewModelPropertyColor name="omen" id="{VM["omen"]}"/>
        <ViewModelPropertyNumber name="spread" id="{VM["spread"]}"/>
        <ViewModelPropertyNumber name="complement" id="{VM["complement"]}"/>
        <ViewModelPropertyNumber name="hueA" id="{VM["hueA"]}"/>
        <ViewModelPropertyNumber name="hueB" id="{VM["hueB"]}"/>
        <ViewModelPropertyNumber name="style" id="{VM["style"]}"/>
        <ViewModelPropertyNumber name="trident" id="{VM["trident"]}"/>
        <ViewModelInstance exports="true" name="Default" id="3:510">
            <ViewModelInstanceNumber viewModelPropertyId="{VM["pull"]}" id="{nid()}"/>
            <ViewModelInstanceTrigger viewModelPropertyId="{VM["fire"]}" id="{nid()}"/>
            <ViewModelInstanceTrigger viewModelPropertyId="{VM["blast"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="{GOLD["aura"]}" viewModelPropertyId="{VM["aura"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="{GOLD["imprint"]}" viewModelPropertyId="{VM["imprint"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="{GOLD["arrow"]}" viewModelPropertyId="{VM["arrow"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="00000000" viewModelPropertyId="{VM["tint"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="00000000" viewModelPropertyId="{VM["accent"]}" id="{nid()}"/>
            <ViewModelInstanceColor propertyValue="00000000" viewModelPropertyId="{VM["omen"]}" id="{nid()}"/>
            <ViewModelInstanceNumber viewModelPropertyId="{VM["spread"]}" id="{nid()}"/>
            <ViewModelInstanceNumber viewModelPropertyId="{VM["complement"]}" id="{nid()}"/>
            <ViewModelInstanceNumber propertyValue="130" viewModelPropertyId="{VM["hueA"]}" id="{nid()}"/>
            <ViewModelInstanceNumber propertyValue="130" viewModelPropertyId="{VM["hueB"]}" id="{nid()}"/>
            <ViewModelInstanceNumber viewModelPropertyId="{VM["style"]}" id="{nid()}"/>
            <ViewModelInstanceNumber viewModelPropertyId="{VM["trident"]}" id="{nid()}"/>
        </ViewModelInstance>
    </ViewModel>
</Rive>
'''
open(out_path, "w").write(rml)
print("wrote", out_path)
