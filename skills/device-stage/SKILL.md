---
name: device-stage
description: Wrap a mobile screen flow (the real UI code, not a recording) in a 3D phone (iPhone 17 Pro, iPhone Air, Galaxy S25 Ultra) in an Apple-style studio, and drive the camera and the UI from script for videos (HyperFrames, Playwright). Use when building or showcasing a mobile UI flow in a device, making product shots or app-flow videos of a web or Rive UI, or when a composition needs a phone showing a live screen.
---

# device-stage: live UI in a 3D phone

The package lives in `mockup-devices/` (`@theanimatedmonk/device-stage`); its README is the full reference. How it works:
- The phone's screen is a **real DOM element** at the phone's CSS viewport, placed in 3D with three.js `CSS3DRenderer`.
- A WebGL canvas draws the phone and the studio over it, with a clear hole for the screen.
- The UI keeps running: taps, scrolls, Rive canvases, CSS animations.

Never record the UI to video and paste it onto the phone. Mount the UI itself.

## Wrap a flow

Pick the mount that fits the UI:

- **A whole page or app** (its own CSS and JS, routes): use `src`. It loads in an iframe at the phone's viewport, where `100vh` is the phone.

  ```html
  <device-stage device="iphone17pro" finish="Deep Blue" src="../my-flow/?embed=1" shot="float"></device-stage>
  ```

  Give the page an embed mode (`?embed=1`) that hides any 2D device frame or page chrome and fills the window. If it was designed at a fixed size, zoom its root to the window, as `tarot-frontend-demo/main.js` does.

- **A component or a few screens**: use children. They go on device 1's screen; a child with `screen="2"` or `screen="3"` goes on the second or third device.

  ```html
  <device-stage device="s25ultra" shot="tilt"><div class="app">…</div></device-stage>
  ```

  - Size with `100%` or `cqw` / `cqh`, never `vh` or `vw`.
  - Pad with `var(--ds-safe-top)` and `var(--ds-safe-bottom)` (the island or punch hole, and the home bar).

**Viewports (CSS px):**

| Model | Viewport |
|---|---|
| `iphone17pro` | 402 × 874 |
| `iphoneAir` | 420 × 912 |
| `s25ultra` | 412 × 892 |

Design at those sizes, or zoom to them.

**Setup:** `import { defineDeviceStage } from "…/mockup-devices/src/index.js"; defineDeviceStage();`. Without a bundler, use an import map for `three`, `three/addons/` and `mp4-muxer`; copy the one in `mockup-devices/examples/element.html`.

## Drive it from script

`document.querySelector("device-stage").stage` is the `DeviceStage`.

- `set(patch)` sets any part of the state:
  - `shot`, `duration`, `camera {azimuth, elevation, roll, distance, fov, targetX, targetY}`
  - `device {rotX, rotY, rotZ, x, y, z}`
  - `slots[i] {model, finish, screen}`
  - `look {backdrop, …}`, `output`
- `seek(t)` renders exactly the frame at `t` seconds. Use it with `set({ playing: false })`, so the timeline, not the stage's clock, drives the camera.
- `frameWindow(i)` is the iframe's window, for driving a page: click elements in it, or `postMessage` to it.
- `screen(i)` is the screen element itself, for children.
- `setInteract("screen" | "device")` is the person's pointer lock. It doesn't limit scripts: a script can move the camera and drive the UI at the same time.

**Shots** (`stage.shots`):

| Shot | Notes |
|---|---|
| `reveal`, `float`, `tilt`, `turntable`, `flip`, `macro`, `screen`, `spin`, `orbit` | One device |
| `duo` | Two devices |
| `lineup` | Three devices |
| `custom` | Camera A to B, from `move.a` / `move.b` |
| `manual` | Camera from `camera` |

`tarot` is timed to the tarot demo. For a new flow, copy that shot in `src/shots.js`: it eases the pose and camera through timed keys, and the `track()` helper does the easing.

**Make the flow play itself for filming**, as `tarot-frontend-demo`'s `?auto=1` does:
1. Wait for the app to be ready.
2. Tap with synthetic pointer and mouse events at design coordinates. Rive canvases accept them.
3. Scroll with `scrollTop` over `requestAnimationFrame`.
4. Post `{ <name>: "start" }` to the parent when a run begins, and have the page hosting the stage reset `stage.state.time = 0` on it, so the camera beats line up with the UI.

## Video

Record the page, not the canvas: the live UI isn't in the WebGL canvas.

- **HyperFrames:** embed the stage page in the composition, for example the studio with `?ui=0&play=0&state=<JSON>`, or your own page with `<device-stage paused>`.
  - Step it from the composition's timeline: post `{ mockup: "seek", time }` and await `{ mockup: "reply" }` before the frame is captured.
  - Cut between moves with `{ mockup: "set", state }`.
- **Playwright:** set the state, then screenshot or record the page.

For both, render on a virtual clock so the UI's own animations step with the camera. Playwright's `page.clock.install()` followed by `pause_at()` drives timers and `requestAnimationFrame`. CSS animations aren't driven by that clock: pause them with `document.getAnimations()` and step their `currentTime` each frame.

`stage.exportVideo()` (frame-perfect MP4 via WebCodecs) encodes the canvas alone. Use it only for screens showing a video, an image or the demo.

## The studio page

`mockup-devices/index.html` is a control panel over a stage, for finding a shot by hand. Its **Copy state** button gives the exact JSON a script passes to `set()` or `?state=`. Its `window.mockup` is the stage.

Serve the repo root (`python3 -m http.server 8765`) and open `/mockup-devices/`.
