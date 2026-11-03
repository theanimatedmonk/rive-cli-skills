# Writes rive/scene.rml: the Studio artboard (the Studio node and its
# inputs), the interactive Studio state machine, and the Demo state machine:
# a 10 s product film in five shots, each a timeline keying the node's
# director inputs (the camera, the exploded view, the turntables, focus),
# with a white fade that opens and closes the loop.
#
#   python3 tools/make_scene.py
#
# Retime or reframe a shot in SHOTS below and run it again.

import os

OUT = os.path.join(os.path.dirname(__file__), '..', 'rive', 'scene.rml')
FPS = 60

# Eases (CSS cubic-bezier numbers).
EASE = {
    'io': (0.42, 0, 0.58, 1),       # ease in and out
    'glide': (0.65, 0, 0.35, 1),    # a slower, longer ease in and out
    'out': (0.16, 1, 0.3, 1),       # Apple's long settle
    'in': (0.7, 0, 0.84, 0),        # gathering speed
}

# The products stand at x -0.056 (the birdhouse, turned 18 degrees) and
# 0.058 (the turned birdhouse, z -0.008); the birdhouse's carved panel
# faces about (-0.052, 0.045, 0.017). camTurn 0 looks from the front.
#
# Each track: [(frame, value, ease of the segment that starts here)].
SHOTS = [
    {
        'name': 'Reveal',
        'note': 'Out of white, low and close at the right, the camera eases back and up while the turntables bring both round to face it.',
        'frames': 132,
        'into': ('cut', 0),
        'tracks': {
            'camTurn': [(0, 36, 'out'), (132, 12, None)],
            'camTilt': [(0, 3, 'out'), (132, 11, None)],
            'camDistance': [(0, 0.19, 'out'), (132, 0.34, None)],
            'camX': [(0, 0.03, 'out'), (132, 0.0, None)],
            'camY': [(0, 0.052, 'out'), (132, 0.045, None)],
            'camZ': [(0, 0.0, None)],
            'camFov': [(0, 22, 'out'), (132, 26, None)],
            'turntable': [(0, -28, 'out'), (132, 0, None)],
            'open': [(0, 0, None)],
            'depthOfField': [(0, 0.45, 'out'), (132, 0.25, None)],
            'fade': [(0, 1, 'io'), (42, 0, None)],
        },
    },
    {
        'name': 'Carving',
        'note': 'A cut to macro: the birdhouse\'s carved panel, the camera sliding across its contours, focus shallow.',
        'frames': 108,
        'into': ('cut', 0),
        'tracks': {
            'camTurn': [(0, 52, 'io'), (108, 20, None)],
            'camTilt': [(0, 3, 'io'), (108, 10, None)],
            'camDistance': [(0, 0.115, 'io'), (108, 0.095, None)],
            'camX': [(0, -0.052, None)],
            'camY': [(0, 0.046, 'io'), (108, 0.042, None)],
            'camZ': [(0, 0.017, None)],
            'camFov': [(0, 24, None)],
            'turntable': [(0, 0, None)],
            'open': [(0, 0, None)],
            'depthOfField': [(0, 0.75, None)],
            'fade': [(0, 0, None)],
        },
    },
    {
        'name': 'Explode',
        'note': 'Gliding up and round to a high three-quarter view as both open: the back lid swings out with the electronics, the roof lifts.',
        'frames': 144,
        'into': ('blend', 500),
        'tracks': {
            'camTurn': [(0, -4, 'glide'), (144, 20, None)],
            'camTilt': [(0, 16, 'glide'), (144, 25, None)],
            'camDistance': [(0, 0.40, 'glide'), (144, 0.37, None)],
            'camX': [(0, -0.02, None)],
            'camY': [(0, 0.05, 'glide'), (144, 0.056, None)],
            'camZ': [(0, 0.0, None)],
            'camFov': [(0, 26, None)],
            'turntable': [(0, 0, None)],
            'open': [(0, 0, 'io'), (18, 0, 'glide'), (96, 1, None)],
            'depthOfField': [(0, 0.2, None)],
            'fade': [(0, 0, None)],
        },
    },
    {
        'name': 'Turned',
        'note': 'A cut to a low hero angle on the turned birdhouse, orbiting as its roof settles home.',
        'frames': 102,
        'into': ('cut', 0),
        'tracks': {
            'camTurn': [(0, -50, 'io'), (102, -14, None)],
            'camTilt': [(0, 0, 'io'), (102, 6, None)],
            'camDistance': [(0, 0.19, 'io'), (102, 0.16, None)],
            'camX': [(0, 0.058, None)],
            'camY': [(0, 0.062, 'io'), (102, 0.056, None)],
            'camZ': [(0, -0.008, None)],
            'camFov': [(0, 28, None)],
            'turntable': [(0, 0, None)],
            'open': [(0, 1, None), (8, 1, 'out'), (72, 0, None)],
            'depthOfField': [(0, 0.5, None)],
            'fade': [(0, 0, None)],
        },
    },
    {
        'name': 'Finale',
        'note': 'Easing back to the pair, centred, the turntables turning slowly, then white again.',
        'frames': 100,
        'into': ('blend', 600),
        'tracks': {
            'camTurn': [(0, 6, 'out'), (100, 0, None)],
            'camTilt': [(0, 9, 'out'), (100, 13, None)],
            'camDistance': [(0, 0.30, 'out'), (100, 0.36, None)],
            'camX': [(0, 0.0, None)],
            'camY': [(0, 0.046, None)],
            'camZ': [(0, 0.0, None)],
            'camFov': [(0, 26, None)],
            'turntable': [(0, 0, 'linear'), (100, 16, None)],
            'open': [(0, 0, None)],
            'depthOfField': [(0, 0.25, None)],
            'fade': [(0, 0, None), (72, 0, 'in'), (100, 1, None)],
        },
    },
]

# The node's inputs: (name, id, value, VM property id or None, kind).
INPUTS = [
    ('asset', '0:11', 'birdie', None, 'String'),
    ('width', '0:12', '1280', None, 'Number'),
    ('height', '0:13', '720', None, 'Number'),
    ('resolution', '0:14', '1', None, 'Number'),
    ('msaa', '0:15', '4', None, 'Number'),
    ('navigation', '0:16', 'true', None, 'Boolean'),
    '<!-- The products: the exploded view, the turntables, which to look at. -->',
    ('explode', '0:20', None, '0:501', 'Number'),
    ('spin', '0:22', None, '0:502', 'Number'),
    ('focus', '0:24', None, '0:503', 'Number'),
    '<!-- The view. -->',
    ('turn', '0:26', None, '0:504', 'Number'),
    ('tilt', '0:28', '14', '0:505', 'Number'),
    ('zoom', '0:30', '1', '0:506', 'Number'),
    ('drift', '0:32', '1', None, 'Number'),
    ('resetView', '0:33', None, '0:507', 'Number'),
    ('dragX', '0:35', None, '0:508', 'Number'),
    ('dragY', '0:37', None, '0:509', 'Number'),
    '<!-- The director: the camera and the products as the Demo\'s timelines key them. -->',
    ('director', '0:80', None, None, 'Number'),
    ('camTurn', '0:81', None, None, 'Number'),
    ('camTilt', '0:82', '12', None, 'Number'),
    ('camDistance', '0:83', '0.34', None, 'Number'),
    ('camX', '0:84', None, None, 'Number'),
    ('camY', '0:85', '0.045', None, 'Number'),
    ('camZ', '0:86', None, None, 'Number'),
    ('camFov', '0:87', '26', None, 'Number'),
    ('open', '0:88', None, None, 'Number'),
    ('turntable', '0:89', None, None, 'Number'),
    '<!-- The light. -->',
    ('key', '0:40', '2.1', None, 'Number'),
    ('fill', '0:41', '0.6', None, 'Number'),
    ('rim', '0:42', '1.8', None, 'Number'),
    ('ambient', '0:43', '0.45', None, 'Number'),
    ('softness', '0:44', '3.2', None, 'Number'),
    ('keyColor', '0:45', 'FFFFF6E8', None, 'Color'),
    ('rimColor', '0:46', 'FFFFECD6', None, 'Color'),
    '<!-- The paints: yellow in a dark navy shell; maple cream under a glossy walnut roof. -->',
    ('panelColor', '0:50', 'FFFF8E5B', None, 'Color'),
    ('shellColor', '0:51', 'FF14224B', None, 'Color'),
    ('bodyColor', '0:52', 'FFCEB898', None, 'Color'),
    ('roofColor', '0:53', 'FF342218', None, 'Color'),
    ('plinthColor', '0:55', 'FFE8E4DC', None, 'Color'),
    '<!-- The cove: a bright, seamless studio sweep, leaning toward each product\'s hue. -->',
    ('backdropColor', '0:60', 'FFE9E7E2', None, 'Color'),
    ('horizonColor', '0:61', 'FFF6F5F1', None, 'Color'),
    ('floorColor', '0:62', 'FFFBFAF7', None, 'Color'),
    ('tintLeft', '0:57', 'FFF0F2FF', None, 'Color'),
    ('tintRight', '0:58', 'FFF5ECDE', None, 'Color'),
    ('tint', '0:59', '0.5', None, 'Number'),
    ('floorGloss', '0:63', '0.22', None, 'Number'),
    ('brightness', '0:66', '1.75', None, 'Number'),
    ('shadowDepth', '0:67', '0.5', None, 'Number'),
    ('pool', '0:64', '0.3', None, 'Number'),
    ('halo', '0:65', '0.25', None, 'Number'),
    '<!-- The finish. -->',
    ('depthOfField', '0:70', '0.3', None, 'Number'),
    ('bloom', '0:71', '0.04', None, 'Number'),
    ('glow', '0:72', '0', None, 'Number'),
    ('exposure', '0:73', '1', None, 'Number'),
    ('grain', '0:74', '0.04', None, 'Number'),
    ('vignette', '0:75', '0.08', None, 'Number'),
]
INPUT_IDS = {i[0]: i[1] for i in INPUTS if isinstance(i, tuple)}
FADE_ID = '0:1100'


class Ids:
    def __init__(self, start):
        self.n = start

    def __call__(self):
        self.n += 1
        return f'0:{self.n}'


ids = Ids(3000)


def inputs_xml():
    out = []
    for item in INPUTS:
        if isinstance(item, str):
            out.append(f'            {item}')
            continue
        name, iid, value, vm, kind = item
        attr = f' propertyValue="{value}"' if value is not None else ''
        if vm:
            out.append(f'            <ScriptInput{kind}{attr} name="{name}" id="{iid}">')
            out.append(f'                <DataBindContext sourcePathIds="0:500-{vm}" propertyKey="243" id="0:{int(iid[2:]) + 1}"/>')
            out.append(f'            </ScriptInput{kind}>')
        else:
            out.append(f'            <ScriptInput{kind}{attr} name="{name}" id="{iid}"/>')
    return '\n'.join(out)


def keyframes(track, pad):
    lines = []
    for frame, value, ease in track:
        if ease is None:
            lines.append(f'{pad}<KeyFrameDouble value="{value}" frame="{frame}" id="{ids()}"/>')
        elif ease == 'linear':
            lines.append(f'{pad}<KeyFrameDouble value="{value}" frame="{frame}" interpolationType="linear" id="{ids()}"/>')
        else:
            x1, y1, x2, y2 = EASE[ease]
            lines.append(f'{pad}<KeyFrameDouble value="{value}" frame="{frame}" interpolationType="cubic" id="{ids()}">')
            lines.append(f'{pad}    <CubicEaseInterpolator x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" id="{ids()}"/>')
            lines.append(f'{pad}</KeyFrameDouble>')
    return lines


def shot_xml(shot, aid):
    lines = [f'        <!-- {shot["name"]}: {shot["note"]} -->',
             f'        <LinearAnimation duration="{shot["frames"]}" fps="{FPS}" name="Shot {shot["name"]}" id="{aid}">']
    tracks = dict(shot['tracks'])
    tracks['director'] = [(0, 1, None)]
    for name, track in tracks.items():
        obj, key = (FADE_ID, 18) if name == 'fade' else (INPUT_IDS[name], 243)
        lines.append(f'            <KeyedObject objectId="{obj}" id="{ids()}">')
        lines.append(f'                <KeyedProperty propertyKey="{key}" id="{ids()}">')
        lines += keyframes(track, '                    ')
        lines.append('                </KeyedProperty>')
        lines.append('            </KeyedObject>')
    lines.append('        </LinearAnimation>')
    return '\n'.join(lines)


def demo_xml():
    n = len(SHOTS)
    state_ids = [f'0:{2010 + i}' for i in range(n)]
    anim_ids = [f'0:{2100 + i}' for i in range(n)]
    total = sum(s['frames'] for s in SHOTS) / FPS
    lines = [f'        <!-- The demo: {n} shots, {total:.0f} s, looping. Each shot is a',
             '             timeline keying the director inputs; cuts are instant, blends',
             '             glide from one shot\'s last frame into the next. -->',
             '        <StateMachine name="Demo" id="0:2000">',
             '            <StateMachineLayer name="Shots" id="0:2001">',
             '                <AnyState x="0" y="-160" id="0:2002"/>',
             '                <ExitState x="1400" y="-160" id="0:2003"/>',
             '                <EntryState x="-250" y="0" id="0:2004">',
             f'                    <StateTransition stateToId="{state_ids[0]}" id="0:2005"/>',
             '                </EntryState>']
    for i, shot in enumerate(SHOTS):
        nxt = (i + 1) % n
        kind, ms = SHOTS[nxt]['into']
        dur = f' duration="{ms}"' if kind == 'blend' else ''
        lines.append(f'                <AnimationState x="{i * 280}" y="0" animationId="{anim_ids[i]}" id="{state_ids[i]}">')
        lines.append(f'                    <StateTransition stateToId="{state_ids[nxt]}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"{dur} id="0:{2200 + i}"/>')
        lines.append('                </AnimationState>')
    lines += ['            </StateMachineLayer>', '        </StateMachine>']
    return '\n'.join(lines), [shot_xml(s, anim_ids[i]) for i, s in enumerate(SHOTS)]


demo, shots = demo_xml()
shots_xml = '\n'.join(shots)

scene = f'''<Rive version="1" kind="fragment">
    <!-- Birdie: two form factors of a wildlife tracker, shot as product
         photography on turntables in a bright studio sweep (see
         Studio.luau). Generated by ../tools/make_scene.py. -->
    <Artboard defaultStateMachineId="0:2000" viewModelId="0:500" viewModelInstanceId="0:520" width="1280" height="720" styleId="0:2" name="Studio" id="0:1">
        <LayoutComponentStyle name="Studio Style" id="0:2"/>
        <Fill name="Backdrop" id="0:3">
            <SolidColor colorValue="FFF6F5F1" name="Color" id="0:4"/>
        </Fill>
        <!-- White, for the film to open and close on (first, so it draws on top). -->
        <Shape x="640" y="360" opacity="0" name="Fade" id="{FADE_ID}">
            <Rectangle width="1280" height="720" name="Path" id="0:1101"/>
            <Fill name="Fill" id="0:1102">
                <SolidColor colorValue="FFF6F5F1" name="Color" id="0:1103"/>
            </Fill>
        </Shape>
        <ScriptedDrawable scriptAssetId="0:902" x="640" y="360" name="Studio" id="0:10">
{inputs_xml()}
        </ScriptedDrawable>

{demo}

        <!-- Interactive: drag to orbit, tap a product, driven by the view model. -->
        <StateMachine name="Studio" id="0:100">
            <StateMachineLayer name="Studio" id="0:101">
                <AnyState x="200" y="-120" id="0:102"/>
                <ExitState x="400" y="-120" id="0:103"/>
                <EntryState id="0:104">
                    <StateTransition stateToId="0:105" id="0:106"/>
                </EntryState>
                <AnimationState x="200" animationId="0:110" id="0:105"/>
            </StateMachineLayer>
        </StateMachine>
        <LinearAnimation duration="60" loopValue="1" name="Studio" id="0:110"/>

{shots_xml}
    </Artboard>

    <!-- For a page to drive the interactive Studio state machine: explode
         (0-1), spin (degrees a second), focus (0 both, 1 birdhouse, 2
         turned), the view. -->
    <ViewModel name="Studio" id="0:500">
        <ViewModelPropertyNumber name="explode" id="0:501"/>
        <ViewModelPropertyNumber name="spin" id="0:502"/>
        <ViewModelPropertyNumber name="focus" id="0:503"/>
        <ViewModelPropertyNumber name="turn" id="0:504"/>
        <ViewModelPropertyNumber name="tilt" id="0:505"/>
        <ViewModelPropertyNumber name="zoom" id="0:506"/>
        <ViewModelPropertyNumber name="resetView" id="0:507"/>
        <ViewModelPropertyNumber name="dragX" id="0:508"/>
        <ViewModelPropertyNumber name="dragY" id="0:509"/>
        <ViewModelInstance exports="true" name="Default" id="0:520">
            <ViewModelInstanceNumber viewModelPropertyId="0:501" id="0:1501"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:502" id="0:1502"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:503" id="0:1503"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:504" id="0:1504"/>
            <ViewModelInstanceNumber propertyValue="14" viewModelPropertyId="0:505" id="0:1505"/>
            <ViewModelInstanceNumber propertyValue="1" viewModelPropertyId="0:506" id="0:1506"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:507" id="0:1507"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:508" id="0:1508"/>
            <ViewModelInstanceNumber viewModelPropertyId="0:509" id="0:1509"/>
        </ViewModelInstance>
    </ViewModel>

    <ScriptAsset file="Studio.luau" scriptProtocolValue="1" name="Studio" id="0:902"/>
    <ShaderAsset file="studio.wgsl" name="studio" id="0:903"/>
    <ShaderAsset file="post.wgsl" name="post" id="0:904"/>
    <ShaderAsset file="blur.wgsl" name="blur" id="0:906"/>
    <BlobAsset file="../birdie.bin" name="birdie" id="0:905"/>
</Rive>
'''
with open(OUT, 'w') as f:
    f.write(scene)
print(f'{OUT}: {len(SHOTS)} shots, {sum(s["frames"] for s in SHOTS) / FPS:.1f} s of timelines (the blends add about a quarter second)')
