# Aleya Lights: plan

The Aleya lights (আলেয়া): the ghostly lights that fishermen of the Sundarbans see drifting over the mangrove creeks at night. The story goes that they lure boats off course, toward the swamp.

A 3D night scene in Rive, built up scene by scene. Mood: the two reference images. That means:
- a still, dark river through the mangroves
- deep teal and green night air
- mist on the water
- warm gold-green orbs, mirrored in the water

## How it's 3D

Everything in the world (mangroves, banks, water, mist) has a 3D position. A node script projects it through a perspective camera each frame, so depth, convergence and parallax are real.
- **Camera:** sits just behind and above the boat, and glides forward at the boat's speed. The world streams past.
- **Depth:** draw order is back to front, and fog grows with distance.
- **Drawing:** vector paths with feathering only, with no WGSL, GPU canvas or blend modes. The same file runs on the web and on the native Android runtime (see `skills/rive-android`).

## Scenes

| # | Scene | What happens | Status |
| --- | --- | --- | --- |
| 1 | **The River** | Night. A river runs through the middle of the mangrove forest. Stilt-rooted trees line both banks, with breathing roots poking out of the mud, reflections in the water, mist drifting low and a moon glow in the haze. A small wooden boat moves slowly forward, seen from behind. | **Built** |
| 2 | **First Light** | Deep in the trees ahead, a single pale gold-green orb appears. It flickers, hangs over the water, and its reflection trembles. | Next |
| 3 | **The Lure** | More orbs rise and drift ahead of the boat, weaving between the trees. The boat slows, then turns to follow them off the main channel. | |
| 4 | **Vanish** | The lights flare, scatter and go out together. Mist closes in. The boat sits alone in the dark. | |

Scenes 2–4 reuse the same world. They are states of the same state machine, plus a lights node script, so the river never stops moving.

## Structure

```
River (main artboard, 1280×720)
  ├── Mangroves   ScriptedDrawable  Mangroves.luau   sky, water, banks, trees, mist (3D)
  ├── Reflection  NestedArtboard    Boat, flipped and dimmed in the water
  └── Boat        NestedArtboard    the boat component
Boat (component artboard)
  └── hull, ribs, bench, wake ripples; its own loop bobs and rocks the boat
```

**Inputs on Mangroves:**
- `speed`: boat speed, in world metres per second
- `fog`
- `moonX`
- `mist`
