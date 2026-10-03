# Ten Rings — Plan (v0)

> **Status (built):** steps 1–7 of the build order are done. `rive/TenRings.luau` draws ten rings from the three ring shapes in `shang-chi_rings.glb` in one GPU pass (shared depth, so rings intersect correctly) — open question 5 resolved as "one node". `Atmosphere.luau` + `mist.wgsl` (mist, embers, heat, blast), `Burst.luau` (flash, rays, shockwaves, sparks). State machine: Intro → Orbit ⇄ SummonIn → SummonHold → Unleash/Recall → Orbit, driven by `summon` / `unleash` / `recall` / `tap` triggers; `energyColor` re-themes everything. Web page in `web/` (Summon/Unleash/Recall, Space/Esc, energy swatches). Open questions 1–4 took the defaults: blue energy (swatches offer gold, crimson, violet), implied arm, 1280×720, no sound.

This is the spec we iterate on **before** writing RML. Nothing gets built until this is agreed.

Inspired by the Ten Rings from *Shang-Chi*. Everything here is our own design: no film logos, characters, likenesses or copied artwork.

---

## Intent

An **interactive hero**: ten ancient metal rings floating in a dark, misty space.

- At rest they **orbit and breathe**, and **lean toward the pointer**.
- On **Summon** they converge and **stack into a spinning column** (as if around an unseen forearm), building up energy.
- On **Unleash** they **launch outward** in a wave with a shockwave and sparks.
- On **Recall**, or automatically after the blast, they **drift back** into orbit.

The rings are drawn as **3D-ish objects** by a Luau node: each ring is projected in perspective, so it tilts, catches light and passes in front of or behind the others. Shaders add the energy glow and the misty backdrop.

The host page owns all text and buttons. The Rive file owns the rings, the effects and the sky. Every user action is a **view-model trigger**, so the page can fire `summon`, `unleash` and `recall`, and can listen for them.

---

## Three moments (user-facing)

| # | Name | What happens |
| --- | --- | --- |
| **1 — Orbit** (idle, loops) | The rings hang in a tilted halo, each orbiting at a slightly different speed and height. A soft energy glow pulses. The halo tilts toward the pointer and settles back when the pointer leaves. |
| **2 — Summon** | The rings swing into a vertical stack, nested one above the other, each spinning on its own axis and counter-rotating with its neighbours. The energy brightens and the mist begins to swirl and heat. Holds, humming, until `unleash` or `recall`. |
| **3 — Unleash** | The stack fires: the rings fly outward in a fan, leaving light trails. A shockwave ring and sparks burst from the centre, and the mist is blown back. The rings slow, curve back and return to **Orbit**. |

```
Orbit ──summon──► Summon ──unleash──► Unleash ──clip end──► Orbit
  ▲                 │
  └─────recall──────┘
```

Clicking or tapping the rings themselves does the same as the page buttons: the first click summons, the next unleashes.

---

## How the rings are drawn

One **Luau node** draws all ten rings. Each ring is a torus approximated as a thick ellipse, computed per frame from a 3D position, rotation and radius:

- **Metal:** a darkened bronze body with lighter edges, a specular streak that moves as the ring turns, and engraved tick marks/glyph bands around the outer face (our own pattern).
- **Depth:** the rings are sorted back-to-front each frame, and the near half of a ring is drawn after the rings it passes in front of, so the rings genuinely interlock.
- **Energy:** an inner glow rim in the energy colour, brighter with `power`. In Summon and Unleash, rings leave fading light trails.
- **Pointer:** `pointerMove` tilts the whole formation. The node watches the pointer but never claims it, so clicks still reach the hit area.

Formations are **blends between poses**, not hand-keyed per ring:

| Pose | Ring positions |
| --- | --- |
| `orbit` | Ten rings spaced around a tilted ellipse, slowly orbiting, gently bobbing |
| `stack` | A vertical column, rings nested close together, each spinning about the column axis |
| `launch` | Rings thrown outward along a fan of directions, scaling up and fading as they go |

The state machine keys **numbers** on the node (`formation`, `launch`, `power`), and the script interpolates between poses. This keeps the motion smooth and lets us tune feel in one place.

---

## GLB importer (built)

The ring's look comes from a 3D model rather than procedural drawing. Three files in `rive/` load and render any `.glb`:

| File | Role |
| --- | --- |
| `GLB.luau` | Module. Parses binary glTF 2.0: JSON + BIN chunks, accessors of any component type (incl. quantized/normalized), interleaved views, node hierarchy (matrix or TRS) baked into world space, smooth normals when missing, metal-roughness material factors, embedded images. |
| `GLBModel.luau` | Node. Uploads the mesh to GPU buffers and renders it with depth and 4× MSAA into a GPU canvas, drawn at `width` × `height` centred on the node. Auto-fits the model to the view. |
| `glb_pbr.wgsl` | GGX/Fresnel PBR, a procedural studio environment for reflections, rim light, emissive glow, ACES tone mapping. |

**Using a model:** drop `name.glb` into `rive/`, declare `<BlobAsset file="name.glb" name="name"/>` in `assets.rml`, set the node's `asset` input to `name`.

**Textures on the web:** the web runtime (2.44) can't decode images from a script, so run `python3 tools/glb_textures.py rive/name.glb`, add the PNG as an `ImageAsset` and set `textureImage`. Works in the editor and natively too.

**Inputs (all optional):**

| Group | Inputs |
| --- | --- |
| Model | `asset` (blob name), `textureImage` (image asset name) |
| Canvas | `width`, `height`, `resolution` (pixel density, default 2), `msaa` (1 or 4), `opacity` |
| Transform | `rotationX/Y/Z` (deg), `spinX/Y/Z` (deg/s), `scale` (1 = fits), `offsetX/Y/Z` |
| Camera | `fov` (deg), `cameraDistance` (1 = auto fit) |
| Lighting | `lightAzimuth`, `lightElevation` (deg), `lightIntensity`, `ambient`, `environment`, `exposure` |
| Material | `metallic`, `roughness` (≥ 0 overrides the file), `tint` + `tintAmount`, `emissive` + `emissiveStrength`, `rimColor` + `rimStrength`, `cullBackfaces` |
| Interaction | `interactive` (drag to rotate) |

**Not supported:** `.gltf` with external files, Draco/meshopt compression, sparse accessors, skins, morph targets, glTF animations, normal/occlusion/metal-rough texture maps, texture transforms.

**For the Ten Rings:** ten `GLBModel` nodes (or one multi-ring node, if ten GPU passes cost too much on the web) each driven by the formation maths below, with `emissive`/`rimStrength` keyed for the energy. To be decided once the real asset is in: see open question 5.

---

## Artboards

```
TenRings              ← main, 1280×720 (16:9 hero), state machine, VM bound here
  ├── Backdrop        ScriptedDrawable  backdrop.wgsl   mist, chi field, heat
  ├── Embers          ScriptedDrawable  Embers.luau     drifting sparks / dust
  ├── Rings           ScriptedDrawable  TenRings.luau   the ten rings + trails
  ├── Burst           ScriptedDrawable  Burst.luau      shockwave + sparks on unleash
  └── Hit             invisible circle over the formation, for click/tap
```

One artboard is enough here: the rings aren't separate designs to reuse, they're one procedural object. If we later want the rings editable in the Rive editor, we can move the ring's look into a `Ring` component and have the script texture it, as `TarotCard3D` did.

---

## View model

`TenRings` view model, bound on the main artboard:

| Property | Type | Purpose |
| --- | --- | --- |
| `summon` | trigger | Orbit → Summon |
| `unleash` | trigger | Summon → Unleash |
| `recall` | trigger | Summon → Orbit, without firing |
| `energyColor` | color | Energy glow tint (default electric blue). Lets the page re-theme it, e.g. gold. |
| `power` | number, read-only for the page | 0–1 charge level, so the page can show a meter if it wants |

The click on `Hit` writes `summon` or `unleash` through a listener, depending on the state.

---

## State machine

One layer, `Flow`:

| State | Animation | Notes |
| --- | --- | --- |
| `Intro` | rings fade and drift in from the dark, settling into orbit (~1.2s) | Entry → Intro → Orbit at exit time |
| `Orbit` | loop; `formation` 0, `power` low pulse | |
| `Summon` | ~0.9s into the stack, then a held loop | `power` rises to 1 |
| `Unleash` | ~1.6s launch, shockwave, return | Exit time → Orbit |

**Lesson from the tarot project:** no transition blend on exit-time transitions into a state that listens for triggers. A trigger fired during the blend is swallowed. We'll match the last frame of one animation to the first of the next instead.

---

## Visual direction

- **Palette:** near-black teal backdrop (`#05080c` → `#0b1a22`), bronze metal (`#6e4a26`, highlights `#d9a35b`), energy electric blue (`#3fb6ff`, core `#bfe8ff`). Unleash flashes towards white.
- **Mist:** low, slow fbm fog that swirls with `power` and is pushed outward by the shockwave.
- **Embers:** sparse warm specks drifting upward; they scatter on unleash.
- **Typography / UI:** none in the Rive file. The web page adds a title, a short line and Summon / Unleash buttons.

---

## Web page

`ten-rings/web/` holds a single-page demo, like the tarot demo:

- Full-viewport canvas with the hero centred; `Fit.Cover` on wide screens, `Fit.Contain` on narrow.
- Title and tagline overlaid in HTML.
- Buttons fire `summon` / `unleash` / `recall` through the view model; keys **Space** (summon/unleash) and **Esc** (recall).
- Runtime: `@rive-app/webgl2` pinned, with `enableGPUCanvas: true` for the shaders.
- Deployed with the rest of the repo on GitHub Pages.

---

## Folder layout

```
ten-rings/
  PLAN.md            ← this file
  rive/              ← the CLI project
    rive.yaml
    scene.rml
    data/view_models.rml
    TenRings.luau  Embers.luau  Burst.luau
    backdrop.wgsl  ring_glow.wgsl
  web/
    index.html  style.css  main.js
    ten-rings.riv   ← the signed build
```

---

## Build order

1. **Skeleton:** `rive.yaml`, view model, main artboard, state machine with empty animations. Build passes.
2. **Rings in orbit:** `TenRings.luau` drawing ten static rings in perspective, then orbiting with depth sorting. CLI screenshots to tune.
3. **Pointer tilt.**
4. **Summon pose and Unleash launch**, driven by keyed `formation` / `launch` / `power`.
5. **Backdrop shader and embers**, then the **burst**.
6. **Intro** animation and polish.
7. **Web page**, signed build (`rive . --publish`), Chrome check, push to the Rive editor and GitHub.

Each step ends with a build and a screenshot check.

---

## Testing

- `rive . --screenshot --advance=…` for each state. Triggers are tested with `--pointer` clicks on `Hit`, or a scratch copy whose transitions run on exit time.
- Headless Chrome for the web page, including the shaders (needs the signed build).
- On the web, check performance: ten rings plus trails and particles must hold 60fps on a laptop.

---

## Known gotchas (from the tarot project)

- Scripts only run on the web in a **signed** build (`rive . --publish`).
- `modulateColor` darkens the whole scene on the web; use overlay paths for shading instead.
- GPU canvases can be nil for the first frames; guard every draw.
- Exit-time transitions with a blend can swallow triggers (see State machine).
- `rive pull --yes` overwrites local files; back up first.

---

## Open questions

1. **Energy colour:** electric blue (as above), or gold/amber?
2. **Arm or no arm:** keep the forearm implied (rings stack around empty space), or draw a stylised silhouette?
3. **Size:** 1280×720 landscape hero, or a square/portrait version too for mobile?
4. **Sound:** none, or hooks for the page to play sounds on summon and unleash?
5. **Ten nodes or one:** render each ring with its own `GLBModel` (simplest, ten GPU passes), or extend it to draw ten instances of the mesh in one pass (faster, needs depth sorting across rings for free)? Decide after profiling the real GLB on the web.
