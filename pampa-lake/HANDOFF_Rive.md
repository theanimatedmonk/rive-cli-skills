# Pampa_Sarovar_Scene.glb: hand-off

Scene asset for Rive. Y-up, metres, vertex colours only, no textures, no animation clips, no skins.
Not yet tested in Rive.

- Size: 18.4 MB, 419,274 triangles, 15 meshes.
- Source: `Pampa_Sarovar.blend`.
- Scripts: `scripts/pampa_build.py` builds the scene, `scripts/export.py` writes the GLB.
- Motion shaders: `WATER_ANIMATION_README.md`.

## Meshes (merged per class, one primitive each)

| Mesh | Triangles | Material | `_WIND` group |
| --- | ---: | --- | ---: |
| Canopy | 125,980 | VC_Opaque | 3 |
| Forest_Far | 53,060 | VC_Opaque | 3 |
| Lotus_Pads | 43,116 | VC_DoubleSided | 6 |
| Terrain | 35,912 | VC_Opaque | 0 |
| Hills | 33,232 | VC_Opaque | 0 |
| Trunks | 28,464 | VC_Opaque | 0 |
| Lotus_Flowers | 27,913 | VC_DoubleSided | 6 |
| Bushes | 23,680 | VC_Opaque | 3 |
| Water | 15,942 | Water | 6 |
| Grass | 15,600 | VC_DoubleSided | 5 |
| Fallen_Flowers | 7,225 | VC_DoubleSided | 0 |
| Birds | 6,420 | VC_Opaque | 7 |
| Vines | 1,944 | VC_Opaque | 0 and 4 |
| Water_Ripples | 744 | Water_Ripple | 8 |
| Waterfall_Caves | 42 | VC_Opaque | 0 |

Also exported: camera `Cam_Hero` and directional light `Sun_Key`.
Blender only, not in the GLB: `_Cam_Review`, `Water_Probe` and the `Float` modifiers.

## Materials (new names, tell the exporter)

- `VC_Opaque`: opaque vertex colour.
- `VC_DoubleSided`: same, with backface culling off.
- `Water`: needs a planar reflection, or a fake one in the shader. Reflections are not baked. Blender uses real reflections, and the lake will look flat without them.
- `Water_Ripple`: alpha-blended rings with depth write off.

## Attributes

Every mesh has `POSITION`, `NORMAL`, `COLOR_0` and `_WIND`.
`_WIND` is VEC3: x = weight, y = phase (0 to 1), z = group.

| Group | Used for | x | Motion |
| ---: | --- | --- | --- |
| 0 | Static geometry | 0 | None |
| 3 | Leaves | Sway weight, higher at the top | Wind sway |
| 4 | Hanging vines | 0 at the root, 1 at the tip | Wind sway |
| 5 | Grass | 0 at the base, 1 at the tip | Wind sway |
| 6 | Water, pads, flowers, buds and stems | Ripple strength on `Water`, 1 on the rest | Normal ripples or float |
| 7 | Birds | 1 | Rigid float and drift, per bird |
| 8 | Ripple rings | 0 at the centre, 1 at the rim | Expanding ring in the fragment shader |

Motion is not baked. Amounts and shader code for groups 6, 7 and 8 are in `WATER_ANIMATION_README.md`.

## Colour

- Foliage shading, aerial haze and tree shadows on the terrain are baked into vertex colours.
- Skip fog on top, or the distance will wash out twice. Haze colour: #F7EBCB.
- The sky is not a mesh. Draw a gradient from #FFF9E8 at the horizon to #FBF0D4 above.

## Reference renders

Blender Cycles reference, in `renders/`:

- `Pampa_Hero.png`: hero still.
- `Pampa_Loop_Hero.mp4`: hero view, 3-second loop repeated.
- `Pampa_Loop_Closeup.mp4`: close-up of swans, lotuses and water, 3-second loop repeated.

## Limits

- Built for `Cam_Hero`. Moving far from it will show gaps.
- Drifting petals are not included. Do these in the shader or as particles.
- The waterfall is a static strip with no flow.
