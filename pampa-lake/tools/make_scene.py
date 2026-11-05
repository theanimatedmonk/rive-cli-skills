# Writes rive/scene.rml: the Pampa Sarovar artboard, its Lake node and its
# inputs, and the Scene view model that a page or the editor can drive.
#
#   python3 tools/make_scene.py

import os

# (name, kind, value, bound to the view model)
INPUTS = [
    ('asset', 'String', 'lake', False),
    ('width', 'Number', 1280, False),
    ('height', 'Number', 720, False),
    ('resolution', 'Number', 1, False),
    ('msaa', 'Number', 4, False),
    # The camera: the GLB's Cam_Hero.
    ('cameraX', 'Number', 0, True),
    ('cameraY', 'Number', 2.4, True),
    ('cameraZ', 'Number', 6, True),
    ('rotationX', 'Number', 4.05, True),
    ('rotationY', 'Number', -3.06, True),
    ('rotationZ', 'Number', 0, True),
    ('fov', 'Number', 42.55, True),
    ('drift', 'Number', 1, True),
    ('focusDistance', 'Number', 11, True),
    ('depthOfField', 'Number', 0.25, True),
    # Viewport navigation (drag, pinch, double-tap); a page maps its mouse
    # wheel and Shift/Ctrl through these.
    ('navigation', 'Boolean', True, False),
    ('navMode', 'Number', 0, True),
    ('zoom', 'Number', 1, True),
    ('resetView', 'Number', 0, True),
    ('dragX', 'Number', 0, True),
    ('dragY', 'Number', 0, True),
    # The sun.
    ('sunAzimuth', 'Number', -81, True),
    ('sunElevation', 'Number', 8, True),
    ('sunIntensity', 'Number', 0.4, True),
    ('lightLeak', 'Number', 0.2, False),
    ('shafts', 'Number', 0, False),
    # Wind.
    ('windStrength', 'Number', 0.05, True),
    ('windSpeed', 'Number', 0, True),
    ('windDirection', 'Number', 200, True),
    ('gustiness', 'Number', 0.6, False),
    ('flutter', 'Number', 1, False),
    # Water.
    ('reflection', 'Number', 1, True),
    ('ripples', 'Number', 2.45, True),
    ('glints', 'Number', 1.4, False),
    ('ringSpeed', 'Number', 1, False),
    ('rings', 'Number', 0.7, False),
    ('swans', 'Number', 1, False),
    ('lotusBob', 'Number', 1, False),
    # Mist.
    ('mist', 'Number', 0.6, True),
    ('mistHeight', 'Number', 3, False),
    ('mistSpeed', 'Number', 1, False),
    ('wisps', 'Number', 14, True),
    ('wispOpacity', 'Number', 0.23, True),
    ('haze', 'Number', 0, True),
    # Pollen.
    ('pollenAmount', 'Number', 1600, True),
    ('pollenSize', 'Number', 0.035, False),
    ('pollenSpeed', 'Number', 1, False),
    ('petals', 'Number', 0.15, False),
    # Look.
    ('bloom', 'Number', 0.35, False),
    ('glow', 'Number', 0.1, False),
    ('exposure', 'Number', 0.83, True),
    # Watercolour.
    ('paint', 'Number', 1, True),
    ('paper', 'Number', 1.7, True),
    ('brush', 'Number', 2.5, True),
    ('edges', 'Number', 0, True),
    ('pollenColor', 'Color', 'FFFFDE8C', False),
    ('petalColor', 'Color', 'FFFAA832', False),
    ('sunColor', 'Color', 'FFFFD696', False),
    ('skyColor', 'Color', 'FFF7ECD0', False),
    ('horizonColor', 'Color', 'FFFCE4C4', False),
    ('mistColor', 'Color', 'FFD6BEDE', False),
    ('shadowColor', 'Color', 'FF7892A8', False),
    ('shading', 'Number', 1, True),
    ('greens', 'Number', 0.51, True),
    ('plants', 'Number', 1, True),
    ('clouds', 'Number', 0.27, True),
    ('skyMidColor', 'Color', 'FFF6E2D2', False),
    ('mountainColor', 'Color', 'FF9684AC', False),
    ('waterColor', 'Color', 'FF96E4CD', False),
]


def fmt(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float):
        return ('%.4f' % v).rstrip('0').rstrip('.')
    return str(v)


inputs, props, values = [], [], []
nid = 10
pid = 501
for name, kind, value, bound in INPUTS:
    attr = '' if value in (0, '', False) and kind != 'Boolean' else f' propertyValue="{fmt(value)}"'
    if kind == 'Boolean':
        attr = f' propertyValue="{fmt(value)}"' if value else ''
    if bound:
        inputs.append(f'            <ScriptInput{kind}{attr} name="{name}" id="0:{nid}">\n'
                      f'                <DataBindContext sourcePathIds="0:500-0:{pid}" propertyKey="243" id="0:{nid + 1}"/>\n'
                      f'            </ScriptInput{kind}>')
        props.append(f'        <ViewModelPropertyNumber name="{name}" id="0:{pid}"/>')
        vattr = '' if value == 0 else f' propertyValue="{fmt(value)}"'
        values.append(f'            <ViewModelInstanceNumber{vattr} viewModelPropertyId="0:{pid}" id="0:{pid + 200}"/>')
        pid += 1
    else:
        inputs.append(f'            <ScriptInput{kind}{attr} name="{name}" id="0:{nid}"/>')
    nid += 2

nl = '\n'
rml = f'''<Rive version="1" kind="fragment">
    <!-- Pampa Sarovar: a lotus lake in a misty, sunlit forest. The Lake node
         draws the whole 3D scene (see Lake.luau); it sits at the artboard's
         centre. Written by ../tools/make_scene.py. -->
    <Artboard defaultStateMachineId="0:2000" viewModelId="0:500" viewModelInstanceId="0:499" width="1280" height="720" styleId="0:2" name="Pampa Sarovar" id="0:1">
        <LayoutComponentStyle name="Pampa Sarovar Style" id="0:2"/>
        <ScriptedDrawable scriptAssetId="0:902" x="640" y="360" name="Lake" id="0:9">
{nl.join(inputs)}
        </ScriptedDrawable>
        <Fill name="Mist" id="0:3">
            <SolidColor colorValue="FFF7ECD0" name="Color" id="0:4"/>
        </Fill>
        <StateMachine name="Scene" id="0:2000">
            <StateMachineLayer name="Idle" id="0:2001">
                <AnyState x="200" y="-120" id="0:2002"/>
                <ExitState x="400" y="-120" id="0:2003"/>
                <EntryState id="0:2004">
                    <StateTransition stateToId="0:2005" id="0:2006"/>
                </EntryState>
                <AnimationState x="200" animationId="0:2010" id="0:2005"/>
            </StateMachineLayer>
        </StateMachine>
        <LinearAnimation duration="60" loopValue="1" name="Idle" id="0:2010"/>
    </Artboard>

    <!-- The camera, the light, the wind, the water, the mist and the pollen,
         for a page or later states to drive. -->
    <ViewModel name="Scene" id="0:500">
{nl.join(props)}
        <ViewModelInstance exports="true" name="Default" id="0:499">
{nl.join(values)}
        </ViewModelInstance>
    </ViewModel>

    <ScriptAsset file="Lake.luau" scriptProtocolValue="1" name="Lake" id="0:902" codeFileId="0:2012"/>
    <ShaderAsset file="lake.wgsl" name="lake" id="0:903" codeFileId="0:44861"/>
    <ShaderAsset file="post.wgsl" name="post" id="0:904" codeFileId="0:87777"/>
    <ShaderAsset file="blur.wgsl" name="blur" id="0:906" codeFileId="0:96613"/>
    <!-- Written by ../tools/export_lake.py from Pampa_Sarovar_Scene.glb. -->
    <BlobAsset file="../lake.bin" name="lake" id="0:905"/>
    <BlobAsset file="../lake2.bin" name="lake2" id="0:907"/>
</Rive>
'''
here = os.path.dirname(os.path.abspath(__file__))
open(os.path.join(here, '..', 'rive', 'scene.rml'), 'w').write(rml)
print('wrote rive/scene.rml', nid, pid)
