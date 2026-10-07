# Tarot Animation — Plan (v1)

This is the spec we iterate on **before** writing RML. `scene.rml` stays empty until this is locked.

v1 replaces v0 (three-card spread). Reference: Daily Divination screens — fan of five backs → one card loading in a gold ring → face reveal → smaller card + content sheet.

---

## Intent

One **daily card** pick, not a three-card reading.

The host app owns chrome (status bar, back, “Daily Divination”, copy). This Rive file owns the **cards, rings, content sheet motion, and 3D flip**.

Every user tap is a **view-model trigger**, not a state-machine-only input. The app can listen for which card was picked, or fire those same triggers itself.

---

## Three animations (user-facing)

| # | Screen | What happens |
| --- | --- | --- |
| **1 — Fan** | Pick a card | Five `TarotCard` instances in an overlapping arc. All show the **back**. They **float**. Clickable. |
| **2 — Select + Load** | Your reading is unfolding | The **tapped** card eases to center. The **other four drop below** (and fade). Gold double-ring appears. Card stays **face-down**. Holds here until the host fires `reveal`. |
| **3 — Reveal + Result** | Hierophant · then smaller card + sheet | On `reveal`: the center card **spins in 3D** and lands on the **front** (bound image). Then it **scales down**, **moves up**, and the **content box slides up** from below the artboard. |

Animation 1 → 2 has **five variants**: which card was tapped. Animation 2 → 3 is **one** path, gated by `reveal`.

```
Fan ──click card N──► SelectN ──clip end──► Loading ──reveal──► Flip ──clip end──► Result
  ▲                                                                                  │
  └──────────────────────────────────── reset (optional, later) ─────────────────────┘
```

---

## Artboards and components

Three reusable components + one host artboard. Changing a component’s source updates every instance.

```
DailyDivination          ← main, 390×844, state machine, VM bound here
  ├── sky, moons, stars
  ├── Ring (gold double circle, hidden until Loading)
  ├── ContentBox (off-stage until Result)
  └── Card1 … Card5      ← five instances of TarotCard
        └── ScriptedDrawable  TarotCard3D.luau
              clones CardBack  (texture, +Z)
              clones CardFront (texture, −Z / other side)

CardBack     isComponent   back design only (no 3D, no VM required)
CardFront    isComponent   face design; VM image `face` bound to the bitmap
TarotCard    isComponent   3D node + hit rect; five of these on the main stage
```

| Artboard | Kind | Size (default) | Why it exists |
| --- | --- | --- | --- |
| `DailyDivination` | main | 390 × 844 | Scene, SM, listeners, ring, content box |
| `CardBack` | component | 160 × 256 | Gold frame, purple fill, diamond, two moons. Edit this to restyle every back. |
| `CardFront` | component | 160 × 256 | Gold frame + **image** fill bound to `CardFront.face`. Edit this to restyle every face chrome. |
| `TarotCard` | component | ~180 × 280 | Holds the 3D node. Origin center. Hit target = the card bounds. |

`TarotCard` does **not** nest `CardBack` / `CardFront` as 2D `NestedArtboard` placements for the flip. Those two are **script inputs** on the 3D node (`Input<Artboard>`). The node `instance()`s them, draws them to offscreen canvases, and maps them onto a 3D slab. That is what makes a real front and back with thickness.

You can still drop a 2D nested `CardBack` on `TarotCard` for Editor authoring; the node is what the runtime shows. Build default: **node only**, so we do not draw the card twice.

---

## Look (match the screens)

**Stage:** deep navy (`#07041A`–`#12082C`), scattered stars, two small moons (upper-right language of the mock). No status bar in Rive.

**Card back (`CardBack`):** rounded rect, purple body (`#2A1A6A` range), **gold stroke**, four-point diamond in the center, crescent above and below. Same source for all five cards.

**Fan layout (idle pose, artboard space, origin top-left):**

Approximate, to iterate in preview:

| Instance | x | y | rotation (deg) | z-order (front = last draw) |
| --- | --- | --- | --- | --- |
| Card1 | 70 | 430 | −32 | 1 |
| Card2 | 115 | 410 | −16 | 2 |
| Card3 | 195 | 400 | 0 | 3 (top of pile) |
| Card4 | 275 | 410 | 16 | 4 |
| Card5 | 320 | 430 | 32 | 5 |

Overlap like the mock: a tight hand, not five separate slots.

**Float (Fan, looping ~3s, phase-offset per card):** Y ±6px, rotation ±1.5°, scale 1.00–1.02. Ease in-out. Not synchronized.

**Loading / Reveal ring:** two concentric gold strokes around the center card, small star ticks on the orbit, slow rotation (~12s/turn). Opacity 0 in Fan; fade in during SelectN.

**Content box:** dark rounded panel (`#12101C` @ ~90%), width ~ artboard − 48px, height ~ 220. Starts **below** the artboard (`y` ≈ 900). Result clip eases it to sit under the shrunk card (~ y 520). **Copy inside the box is host UI in v1** (the mock’s title + body). Rive only moves the empty/placeholder sheet so layout is correct. String binds can be added later.

---

## Animation 1 — Fan

Looping clip `FanIdle` on the five cards (float) + stars twinkle.

**Listeners (click → VM trigger, Fan only in the SM):**

Each `TarotCard` instance has a **click** listener (`listenerTypeValue="click"`, target = that instance). The listener’s action is **not** a state-machine input. It fires the matching **view-model trigger** on `DailyDivination`:

| Click target | VM trigger |
| --- | --- |
| Card1 | `pick1` |
| Card2 | `pick2` |
| Card3 | `pick3` |
| Card4 | `pick4` |
| Card5 | `pick5` |

RML: `ListenerViewModelChange` (or equivalent bind) on that click listener, path = `pickN`.

The state machine does **not** have `pick1`…`pick5` as SM inputs. Fan → SelectN is a **view-model trigger** transition on the same `pickN` the click fired — same pattern as Loading → Flip on `reveal`.

Effects:

- A real tap fires `pickN`; the host can subscribe to it.
- The host can fire `pickN` with no pointer and get the same SelectN clip.
- After leaving Fan, SM transitions no longer listen to `pick*`, so extra taps (and extra host fires) do nothing until a later `reset`.

---

## Animation 2 — Five Select clips + Loading

One shot per tapped card. Same idea, different who is hero.

**`Select1` … `Select5` (~0.7s, ease-out):**

| Role | Motion |
| --- | --- |
| **Chosen card** | x/y/rotation → center of the ring (~ 195, 380), rotation → 0, scale → ~1.15. Draw order to front. |
| **Other four** | y += ~420 (off the bottom), slight extra rotate, opacity → 0. Stagger 30ms so they do not teleport as a block. |
| **Ring** | opacity 0 → 1 in the last 200ms of the clip. |

Then **Loading** (loop): chosen card still **back-out**, gentle float (±3px), ring keeps spinning. Optional pulse on the gold stroke.

This is the wait for the host (network, RNG, whatever). The face image should be assigned **before** `reveal` so the first frame of the flip already has the bitmap.

**Exit:** view-model trigger `reveal` → Flip.

---

## Animation 3 — Flip then Result

### Flip (~1.1s)

The **3D node** `rotationY` is keyed (or mixed from this clip via a bindable number).

**3D-correct “flip 360 then show the face”:**

- At rest, `rotationY = 0` → **back** faces the camera.
- A 360° Y turn (`2π`) returns the **back**.
- To spin once **and** land on the **front**, key **`0 → 3π` (540°)**.

That is one full revolution plus the extra half-turn that reveals the face. If 540° feels long, cut to **`0 → π` (180°)** — same 3D card, no extra spin. Default in this spec: **540°**.

Thickness is visible on the edges during the turn (`depth` on the node).

Front texture = `CardFront` (host `face` image). Back texture = `CardBack`.

### Result (~0.55s, then hold)

After Flip’s last frame:

- Center card **scale** ~1.15 → ~0.72
- Center card **y** up ~40px (leaves room for the sheet)
- Ring scales down slightly with the card (or stays, mock keeps a ring around the smaller card)
- **ContentBox** `y` 900 → ~520, opacity 0 → 1

Hold. Optional later: `reset` trigger back to Fan (cards jump or reverse). **Not in v1 host API** unless we add it.

---

## State machine

One layer on `DailyDivination`. Clips are one-shots except FanIdle, Loading, ResultHold.

```
Entry → Fan

Fan --VM pick1--> Select1
Fan --VM pick2--> Select2
Fan --VM pick3--> Select3
Fan --VM pick4--> Select4
Fan --VM pick5--> Select5

Select1 --on clip end--> Loading
Select2 --on clip end--> Loading
Select3 --on clip end--> Loading
Select4 --on clip end--> Loading
Select5 --on clip end--> Loading

Loading --VM reveal--> Flip
Flip    --on clip end--> Result
```

**No state-machine trigger inputs.** Every trigger the SM cares about lives on the view model.

| VM trigger | Fired by | SM transition |
| --- | --- | --- |
| `pick1` … `pick5` | click listener on that card, **or** the host | Fan → SelectN |
| `reveal` | host (and optional preview click on the loading card) | Loading → Flip |

`pickN` only from Fan. `reveal` only from Loading. A premature fire is ignored.

Mix: FanIdle can mix at 0 once Select starts (or we just leave Fan). Select clips fully pose all five cards so we do not depend on mix from Fan.

---

## View models

### Host — `DailyDivination` (bound to main artboard)

| Property | Type | Role |
| --- | --- | --- |
| `pick1` | trigger | Card 1 chosen. Click listener fires this; host may fire or listen. Fan → Select1. |
| `pick2` | trigger | Card 2. Fan → Select2. |
| `pick3` | trigger | Card 3. Fan → Select3. |
| `pick4` | trigger | Card 4. Fan → Select4. |
| `pick5` | trigger | Card 5. Fan → Select5. |
| `reveal` | trigger | Face is ready. Loading → Flip. |
| `face` | image | Bitmap for `CardFront`. Set **before** `reveal`. |

Click path: pointer down/up on CardN → `click` listener → fire `pickN` → SM sees that VM trigger.

Host path (no tap): `pick3.fire()` → same Select3 clip.

CLI preview: placeholder PNG for `face`. `reveal` via `--data` or a **preview-only** click on the loading card that fires the `reveal` VM trigger (same type as the picks). Remove that extra listener if the app must own the gate.

### Nested — `CardFront`

| Property | Type | Role |
| --- | --- | --- |
| `face` | image | Bound to the Image (or mesh fill) on the front artboard. |

Host `DailyDivination.face` is the source of truth. The 3D node copies it onto the **private** `CardFront` clone (see script). Do not share the nested artboard’s VMI with the clone — the clone would never see updates ([node view-model pattern](https://rive.app/docs/scripting/data-binding)).

### Optional later (not v1)

`title` / `body` strings, `reset` trigger, `upright` boolean.

---

## 3D node script — `tarot_card_3d.luau`

Protocol: **Node** (`ScriptedDrawable` on `TarotCard`).

Rive has no mesh-card primitive. The card is a **thin 3D slab**: perspective (`Mat4.perspective` / `lookAt`), `rotationY` / `rotationX`, **depth** as thickness.

### Inputs

| Input | Type | Role |
| --- | --- | --- |
| `back` | `Input<Artboard>` | `CardBack` source |
| `front` | `Input<Artboard<Data.CardFront>>` | `CardFront` source |
| `viewModelProperty` | `Input<string>` | Nested VM name on the host VM if the front is nested (`face` lives on host; often `""` and we read `ctx:rootViewModel():getImage('face')`) |
| `width` | `Input<number>` | World width of the slab (default 160) |
| `height` | `Input<number>` | World height (default 256) |
| `depth` | `Input<number>` | Thickness (default ~8–12). **This is the depth control.** |
| `rotationY` | `Input<number>` | Radians. Bound / keyed for the flip. 0 = back to camera. |
| `rotationX` | `Input<number>` | Slight tilt (fan can use this; Select zeros it). |
| `rotationZ` | `Input<number>` | In-plane fan angle if we drive tilt in the node instead of the instance. **Prefer instance `rotation` for Fan Z** so the SM can key 2D pose without fighting the node. Node `rotationZ` default 0. |

### Runtime pattern (required)

1. `back:instance()` and `front:instance()` with a **private** VM on the front (`Data.CardFront.new()` or `src:instance()` then `inst.data`). **Do not** pass the nested placement’s VMI into `instance()` — triggers/images get consumed by the 2D nested SM and the clone stays default.
2. Recreate clones **only** when `back` / `front` inputs change.
3. Relay `face` image: `source:getImage('face')` → copy `.value` onto `clone:getImage('face')`, plus `addListener`. Same pattern as booleans in the node-VM skill.
4. Each `advance`: `backInst:advance(seconds)`, `frontInst:advance(seconds)`. Before `draw`, `advance(0)` so a bind that happened between ticks still applies.
5. Draw each face into an offscreen `context:canvas()` (or `GPUCanvas`) sized to the component. `beginFrame` / draw artboard / use `.image` as the texture.
6. GPU pass: textured box (front quad, back quad, four thin edge quads in gold). MVP = `perspective * lookAt * T * Rx * Ry`. `depth` separates front/back along local Z.
7. Composite `canvas.image` with `renderer:drawImage`.

Web runtimes that show this 3D path need **GPU Canvas** (`enableGPUCanvas: true` on `@rive-app/webgl2`). CLI preview is the local window; that path is what we author against.

### Hit testing

The ScriptedDrawable’s layout bounds are the click target (the `TarotCard` component rect). Pointer is **not** perspective-correct in v1; the 2D AABB is enough for a fan.

---

## File layout (when we build)

```
tarot-animation/
  rive.yaml
  PLAN.md
  scene.rml                 DailyDivination + SM + five instances + ring + box
  data/view_models.rml      DailyDivination, CardFront
  components/card_back.rml
  components/card_front.rml
  components/tarot_card.rml
  TarotCard3D.luau          (root: where `rive pull` puts it)
  placeholder-face.png, face-hierophant.jpeg, star.svg, moon.svg
```

`rive.yaml` `main: DailyDivination` once that artboard exists.

---

## Motion rules

- Fan float: slow, overlapping phases.
- Select: 0.7s, ease-out on the hero, slightly snappier drop on the losers.
- Flip: ease-in-out on `rotationY`; no squash-2D fake flip.
- Result: 0.55s ease-out on scale/y and on the sheet.
- Gold `#D4AF37` / `#C9A84C`. Do not bounce.

---

## Host sequence

1. Load file, bind `DailyDivination`, play default SM → Fan.
2. User taps a card → Rive fires `pickN`. Host may listen. SM plays SelectN → Loading.
   - Or the host fires `pickN` itself.
3. Host sets `face`, fires `reveal`.
4. Flip + Result. Host can show title/body on top of or beside the sheet.

---

## Out of scope for v1

- Shuffle / three-card spread (v0, dropped)
- 22 unique back designs
- Copy (title, upright/reversed, fortune text) inside Rive
- App chrome
- `reset` unless we add it while building
- Perspective-accurate pointer on the 3D mesh

---

## Build order (later)

1. `CardBack` + `CardFront` components (2D, front with placeholder image bind).
2. `tarot_card_3d.luau` on `TarotCard`: slab, depth, both textures, `rotationY` scrub.
3. Main artboard: five instances, Fan pose + float, starry bg.
4. SM: five Select clips + Loading; click listeners fire VM `pick1`…`pick5`; Fan→SelectN on those same triggers.
5. `reveal` → Flip 540° + Result (scale/up + content box).
6. Wire host VM `face` through the node; screenshot each state.

Each step must `--verify` and screenshot.

---

## Open questions

Current lean in **bold**. Say if any is wrong.

1. Flip amount: **540° (360 + 180)** vs 180° only vs 360° ending on the back?
2. Content sheet: **empty motion in Rive, copy in the app** vs string binds in Rive?
3. Preview without a host: **tap loading card fires `reveal`** vs wait for `--data` only?
4. Unselected cards: **drop + fade off bottom** vs shrink into a pile at the bottom edge?
5. Artboard size: **390×844** vs square?
6. `reset` in v1? → **no**
7. Ring: **scene-level** (one ring, not per card) → **yes**

---

## Change log

| Version | Notes |
| --- | --- |
| v0 | Three-card Past/Present/Future. Superseded. |
| v1 | Daily Divination: 5-card fan, 5 Select paths, `reveal` + `face`, 3D slab card with `CardBack` / `CardFront` components. |
| v1.1 | `pick1`…`pick5` are view-model triggers. Click listeners fire those VM triggers; the SM has no pick inputs of its own. |
| v1.2 | **Built.** Deviations from the text above: cards are 160×280 (tarot proportions, matches the mocks). The five cards sit in a `Stage` node at the hero pose (195,300); Loading float, Flip scale (1→0.72) and Result move (→ top-left 76,84 @0.42) key `Stage`, so one clip serves every pick (the four others are at opacity 0). Flip scrubs every card's `TarotCard.Flip` via `NestedRemapAnimation` (0→3π, eased on the caller). New `RevealHold` (0.9s) between Flip and Result, matching mock 3. Hero is brought to front with a keyed `DrawRules`. Hit shapes are `isTargetOpaque` so overlapping fan cards fire one pick. 3D slab is CPU-projected and drawn with `drawImageMesh` (no WGSL/GPU canvas needed). `CardFront` needs its own state machine or its `face` bind never applies inside the script's private instance. Preview face = `face-hierophant.jpeg` (Rider-Waite, public domain). |
| v1.3 | Editor round-trip: card back redesigned (SVG diamond and moons), background and Result/RevealHold/ContentBox removed (flow ends on the reveal; the web page owns everything after), fan entrance re-timed. Web fixes: script skips frames while a canvas image is nil, edge-on shading is a dark overlay (`modulateColor` darkens the whole scene on web), preview reveal tap removed (the host fires `reveal`). Ship with `rive . --publish`; web runtimes skip unsigned scripts. `tools/gen_scene.py` retired: the editor is the source of truth. |
