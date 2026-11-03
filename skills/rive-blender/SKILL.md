---
name: rive-blender
description: How to author Blender assets (GLB) that a Rive file renders in real 3D through Luau node scripts and WGSL shaders, and how to hand them off. Covers export settings, naming, rigs and animation clips for games (aim offsets, split shots, hit reactions), helper bones, shape keys, painted per-vertex attributes like _WIND, scene layout conventions, and the brief format between the Blender side and the Rive side. Use when modelling, rigging or animating anything in Blender that will end up in a Rive (.riv) file, when writing a brief for the Blender agent, or when a GLB change didn't come through in Rive as expected.
---

# Blender → Rive: authoring 3D assets for Rive

Learned building **Vikram-Vetal** (a third-person archery game in one Rive file) and the **Shishupalgarh** ruins scene, Sept–Oct 2026. Two Claude chats work as a pair:

- **The Blender side** models, rigs, animates and exports a GLB.
- **The Rive side** runs a Python exporter that turns the GLB into a compact binary (`king.bin`, `world.bin`…), which Luau node scripts read and WGSL shaders draw on the GPU, inside the Rive file.

Rive never imports the GLB itself. That has three consequences:
- **Only what the exporter reads matters.** Materials, modifiers, lights and cameras are just data to it, and anything it doesn't look for is ignored.
- **Names are the interface.** The exporter finds meshes, actions, bones and materials by name. Rename something and it silently drops out.
- **Shading happens in Rive.** Blender materials are mostly labels; what a surface looks like is decided in the shader.

---

## 1. Export settings (every GLB)

| Setting | Value | Why |
| --- | --- | --- |
| Format | glTF Binary (`.glb`), one file per asset | The exporters parse the binary chunk directly |
| Up axis | **+Y up** (glTF default) | Rive-side math assumes Y up, metres |
| Scale | 1 unit = 1 metre, scale applied | Gameplay distances (reach, path width, arrow range) are in metres |
| Modifiers | **Apply** (or "Apply Modifiers" on export) | The exporter sees only final geometry |
| Animations | On, **one action per clip**, exported as separate glTF animations | Each clip is looked up by name |
| Sampling | "Always sample animations" on, same fps for every action (24) | The exporter bakes every sampled key; mixed rates break blending |
| Shape keys | On (as morph targets), plus "shape key normals" | Used for deformations the rig can't make (the drawn bow) |
| Custom attributes | On (e.g. `_WIND`) | glTF needs the leading underscore for custom vertex attributes |
| Selection | One export collection per asset | Keeps stray helpers and reference meshes out |
| Root motion | **None**; the root stays at the origin | The game moves the character; clips play in place |

A rig can sit anywhere in the Blender scene. The exporter takes the root's placement off, so the character stands at the origin. For a prop placed in a scene, it records that placement so the scene can put it back (that's how Vetal hangs from the exact branch he was posed on).

**Textures:** they are embedded in the GLB and re-encoded as JPEG mips by the exporter, capped at 2048 for base colour and 1024 for normal and roughness/metal. Painting larger than that costs nothing on the Rive side, but it doesn't show either. Vertex colours work too: the scene and Vetal use only vertex paint.

---

## 2. Naming is the contract

Use a short prefix per asset and keep it everywhere: `VKK_` for King Vikram, `VTL_` for the Vetal. Before renaming anything, check the brief: every name below is read by code.

**Character (example: `Vikram_King.glb`)**
- Body mesh `VKK_Body_LP`. Bow parts `VKK_BowLimb`, `VKK_BowGold`, `VKK_BowString`, under the object `VKK_Bow`.
- Textures `VKK_basecolor`, `VKK_normal`, `VKK_rm`.
- Actions `VKK_Idle`, `VKK_Walk`, `VKK_Draw`, `VKK_Shoot`, `VKK_AimHold`, `VKK_Release`, `VKK_Aim_Level`, `VKK_Aim_Up`, `VKK_Aim_Down`, `VKK_Hit_Front`, `VKK_Hit_Back`, `VKK_Hit_Left`, `VKK_Hit_Right`, `VKK_Fall`.
- Helper bones `bow_grip`, `bow_nock`.

**Scene (example: `VikramVetal_Scene.glb`)**
- Objects are classified by **name prefix**: `Terrain*`, `Peepal_Trunk*`, `Peepal_Canopy*`, `Peepal_AerialRoots*`, `Peepal_MossDrapes*`, `Jungle*`, `Props*`.
- Materials are classified by **material name**: `Bark`, `Foliage_Peepal`, `Ground_Earth`, `Ground_Ash`, `Grass_Dry`, `Stone`, `Bone`, `Vine`, `Moss_Hanging`… A material with a new name is guessed from the mesh name and vertex colour. Tell the Rive side about any new material.
- Camera `Cam_Hero` and moon light `Moon_Key` (a KHR punctual light). The exporter prints them to use as the scene's defaults.
- Gameplay data is derived from names. The walkable path grid is every `Terrain*` triangle with the `Ground_Ash` material, so painting ash elsewhere makes it walkable. The arrow-stopping wood grid is voxelised from `Peepal_Trunk*`, so renaming the trunk means arrows stop sticking.

---

## 3. Rigs and clips for a game

### Clips play in place and start and end near idle
A hit can land mid-walk and a shot can start mid-step. The game blends any clip from anything, so:
- No root motion. The game moves him and keeps him on the path.
- The first and last frames sit close to `Idle` frame 0, except for clips meant to chain (see below).
- Loops (`Idle`, `Walk`, `AimHold`) have identical first and last frames.

### Split one-shot actions into chainable parts
One long `Shoot` (draw, release, follow-through: 1.8 s) can't be held or aimed. For hold-to-aim and release-to-fire, deliver:
- `Draw`: raise, nock, draw. It **ends** on the full-draw pose.
- `AimHold`: a short loop at full draw (breath, string tension). Its frames match `Draw`'s last frame.
- `Release`: from full draw, let go, follow through, and end on `Idle` frame 0.

Keep the original whole `Shoot` too. Other parts of the file (the story timeline, the astra shot) still use it.

### Aim offsets, not one animation per angle
For aiming anywhere, deliver **three held poses** that differ only in upper-body pitch:
- `Aim_Level` (0°, identical to `AimHold` frame 0)
- `Aim_Up` (+45°)
- `Aim_Down` (−35°)

Rive blends them additively (Up − Level, Down − Level), weighted by the target's pitch. Yaw comes from turning the whole body.

Rules:
- Pitch through the spine, chest, neck, head and both arms together.
- Pelvis, legs and feet are **identical** across the three.
- The arrow line passes through the grip in every pose.
- In every full-draw pose, the arrow points **along the character's forward axis** (the direction `Walk` walks along). If it doesn't, the Rive side carries a fixed correction angle in code. Vikram's hold pose came in 19° off, and his shoot 34° off, and both are corrected in code. Squaring them up in Blender lets those constants go to zero.

### Hit reactions
- One clip per side: `Hit_Front`, `_Back`, `_Left`, `_Right`, 18 frames at 24 fps.
- Timing: brace (f0–1), **impact** (f2), recoil (f3–6), a decaying shudder (f7–12), then settle to idle (f13–17).
- Feet stay planted, the pelvis dips no more than about 8 cm, and props stay in hand.
- A separate `Fall` clip for game over: about 2 s, with the **last frame held by the game**, so it has to read as a still, final pose.

### Event frames: write them in the note, don't rely on markers
Blender **pose markers do not survive glTF export**, and the exporter doesn't read `extras`. Events reach Rive in two ways instead:
- **From animated data.** The let-go is found from the bow's shape key weight. The full draw is where the weight first reaches about its peak, and the let-go is the first key after that where it drops below half. Keep the string's shape key keyed in every bow action, with a sharp drop on the release, and the arrow leaves on the right frame however the clip is retimed.
- **Hard-coded on the Rive side.** The hits' impact is a constant (`HIT_IMPACT = 0.125` s in, about f3 at 24 fps), which drives the red burst and the camera shake.

So list each new action's **frame count** and its **event frame(s)** in the hand-off note, and say when you retime a clip.

---

## 4. Helper bones (joints skinned to nothing)

Give the Rive side exact points instead of estimates. Add bones that deform nothing but are exported as joints of the same skin:

| Bone | Where | Used for |
| --- | --- | --- |
| `bow_grip` | the arrow rest on the grip | arrow's front end; where the string returns on release |
| `bow_nock` | the string's centre, following it as it's drawn | the nocked arrow's tail; together with the grip, the exact arrow line in any pose |

Before `bow_nock` existed, the nock was estimated from the top limb's geometry and came out wrong. The pattern applies widely: a muzzle, a hand socket for a held prop, a head-look target, an effect spawn point.

---

## 5. Deformations: rig vs shape key vs painted attribute

| Need | Use | Notes |
| --- | --- | --- |
| Limbs, body, held props | Bones | Baked per key into skin matrices; Rive only blends matrices |
| A deformation the rig can't make (the bow at full draw) | **One shape key**, driven per action | Same topology as the base mesh. The key's weight is keyed in each action (e.g. string drawn = 1); the exporter bakes that weight track per clip |
| Secondary motion: hair, cloth, leaves, hanging roots | **Paint a `_WIND` vertex attribute** | Procedural in the shader, costs nothing per clip (below) |
| Cloth that should swing as chains | Cloth bones (`drape.0–2`, `sleeve.*`, `sash`, `hem.L/R`) | If cloth is unpainted, its sway is derived from these bones |

### `_WIND`: painted secondary motion
A float4 colour attribute named `_WIND` (exported via custom attributes):
- **x:** how much this vertex sways (0 = pinned, 1 = free). Paint a gradient: 0 at the root, 1 at the tips.
- **y:** a phase (0–1), so neighbouring parts don't move in lockstep. Paint it in patches; near-equal values move together.
- **z:** what it is (character: 0 skin, 0.5 hair, 1 cloth, i.e. kind ÷ 2; Vetal uses kind ÷ 4 for 0 still, 1 hair, 2 and 4 cloth).
- **w:** unused (0).

The game then applies the scene's wind (strength, direction, gusts) on top, with sliders per type (hair, cloth). Painted wind beats any height-based guess. On the peepal, the roots now swing most at their tips, not at the attachment point.

Short, stiff cloth pieces (knee hems) look like flapping slabs at high sway. Paint them low.

---

## 6. Budgets and things that bit us

- **Triangle counts are fine in the tens of thousands.** The peepal trunk is 22.5k triangles, the roots 8.7k, all merged per material. There is no instancing for small scenes.
- **Recolours belong in the exporter.** Darkening the ground and tree was done there, so repainting in Blender still works and nothing in the shaders changes.
- **Repainting a surface can change what grows on it.** Dry grass clumps are scattered only on ground painted reddish-earth. Painting the ground green removed 42,000 clumps.
- **A new piece that dips below the ground shifts the printed bounds,** even though nothing moved. That's harmless, but it's mentioned in the hand-off so nobody panics.
- **A larger rig is fine.** Vetal went from 20 to 36 bones with no change on the Rive side, because joints are read from the skin.
- **Keep one GLB per asset, rebuilt in place under the same filename.** The Rive side re-runs the exporter and bumps a cache-busting `?v=N` on the web pages.
- **Thin limbs and offset shells.** Vetal's glow is a second copy of the body pushed out about 6 cm, and on thin shins it reads as a second edge. Give the Rive side a smooth-normal hint (or avoid razor-thin parts) if a character gets a halo.

---

## 7. The brief: how the two chats talk

The Rive side writes the Blender side a brief in a code block, and the Blender side answers with a hand-off note. Keep both in this shape.

**Brief (Rive → Blender)**
```
<Asset>.glb — <what's being added> (same rig, same GLB, keep everything else)

Context: what the game does with it, and what the game handles itself
(e.g. "the game shoves him back; clips stay in place").

1. <Clips, with exact names, fps, frame counts, and a per-frame timing table>
2. <Pose rules: what moves, what must stay identical, forward axis>
3. <Helper bones / shape keys / attributes, with exact names>
4. Keep: naming style (PREFIX_*), fps, _WIND, existing actions.
5. Deliver: a note with each new action's frame count and event frames,
   and confirm start/end frames match where required.
```

**Hand-off note (Blender → Rive)**
```
<Asset>.glb updated
- New actions: VKK_Hit_Front 18f (impact f2), … VKK_Fall 48f (last frame held)
- Changed: <anything renamed, retimed, re-rigged, or re-painted>
- Helper bones: <added/moved>
- Known deviations from the brief: <e.g. hold pose still ~19° off forward>
- Bone count / triangle count if they changed a lot
```

Be explicit about deviations. The Rive side can usually correct for them in code, but only if it knows.

---

## 8. What the Rive side does with it (for context)

- `tools/export_*.py` reads the GLB (pure numpy). It bakes each clip's skin matrices (posed world × inverse bind) at every key, packs vertices (32 bytes: position, normal, UV, joints, weights), encodes textures, and writes one binary with typed sections.
- A Luau **module** (`Hero.luau`) blends clip matrices and aim offsets. A **node** script (`World.luau`) runs the game: input, camera, arrows, ghosts, HUD, all through a view model. WGSL shaders skin on the GPU and shade.
- That runs identically in the Rive editor and on the web runtime (`@rive-app/webgl2`). Android native can't run the GPU-canvas path; see the `rive-android` skill.
- Each change is checked in Chrome, not the headless CLI, because script time doesn't advance in CLI screenshots. When in doubt, the King artboard renders any single pose (`--data=pose=N`), which is the quickest way to eyeball a new clip.
