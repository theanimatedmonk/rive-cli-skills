# Mockup Devices

Phones in an Apple-style studio, for shooting app flows: iPhone 17 Pro, iPhone Air and Galaxy S25 Ultra, built in code at their real sizes. Each screen shows a built-in demo app or your own screen recording. A library of camera moves exports frame-perfect MP4 at up to 4K 60 fps.

Serve the folder and open it (the page uses ES modules):

```sh
python3 -m http.server 8765   # from the repo root
open http://localhost:8765/mockup-devices/
```

- **Drag** on the view to orbit and **scroll** to dolly. Either one switches the camera to Manual.
- Press **Space** to play or pause, and **H** to hide the controls.
- **Drop** a video or image anywhere on the page to put it on device 1's screen.
- **Export MP4** renders every frame on its own, so the video never stutters. Exports come out at the Output panel's size, frame rate and the shot's length. It needs WebCodecs, which Chrome, Edge and Safari have.

## One state drives everything

The page draws from a single JSON state. The control panel edits it, and a script can set the same state. In the panel, **For scripts → Copy state** copies the current state, ready to paste into a script.

```jsonc
{
  "shot": "tilt",            // a shot id (below), or "manual"
  "time": 0,                 // seconds into the shot
  "duration": 7,             // the shot's length (s); set to the shot's own when the shot changes
  "playing": true,
  "speed": 1,
  "layout": 1,               // devices shown in "manual": 1, 2 or 3
  "slots": [                 // device 1 (hero), 2 (duo, line-up), 3 (line-up)
    { "model": "iphone17pro", "finish": "Cosmic Orange", "screen": "flows/onboarding.mp4" },
    { "model": "s25ultra", "finish": "Titanium Black", "screen": "" },
    { "model": "iphoneAir", "finish": "Sky Blue", "screen": "" }
  ],
  "camera": {                // used in "manual": an orbit round the target
    "azimuth": -6,           // degrees about the Y axis
    "elevation": 3,          // degrees up (X axis)
    "roll": 0,               // degrees about the view (Z axis)
    "distance": 44,          // cm
    "fov": 28,               // vertical field of view, degrees
    "targetX": 0, "targetY": 0
  },
  "device": {                // added on top of every shot; in "manual" it is the pose
    "rotX": 0, "rotY": 0, "rotZ": 0,   // degrees
    "x": 0, "y": 0, "z": 0,            // cm
    "float": 1                         // the bob and sway in "manual"
  },
  "move": { "a": { /* camera */ }, "b": { /* camera */ } },   // the "custom" shot glides A → B
  "look": {
    "backdrop": "Studio",    // Studio, White, Blush, Graphite, Black, Midnight, or Custom
    "inner": "#fbfbfd", "outer": "#e3e4e9",                // Custom's colours
    "shadow": 0.55, "reflections": 1, "exposure": 1, "glare": 1, "screen": 1
  },
  "output": { "aspect": "16:9", "height": 1080, "fps": 60 }  // aspect: 16:9, 9:16, 1:1, 4:5; height is the short side
}
```

**Models and finishes**

| Model | Finishes |
|---|---|
| `iphone17pro` | Cosmic Orange, Deep Blue, Silver |
| `iphoneAir` | Sky Blue, Light Gold, Cloud White, Space Black |
| `s25ultra` | Titanium Silverblue, Titanium Black, Titanium Gray, Titanium Whitesilver |

**Shots**

| Id | Devices | Shape |
|---|---|---|
| `reveal` | 1 | Turns from side-on to the front |
| `float` | 1 | Loops |
| `tilt` | 1 | Low side angle, the phone leaning back |
| `turntable` | 1 | Loops, a full 360° |
| `flip` | 1 | Loops: screen, then back, then screen |
| `macro` | 1 | The camera module, close up |
| `screen` | 1 | Loops; the screen fills the frame, for app flows |
| `spin` | 1 | Spins in from above |
| `orbit` | 1 | Orbits from high to low |
| `duo` | 2 | Loops |
| `lineup` | 3 | Loops |
| `custom` | 1 | Glides from camera A to camera B |
| `manual` | 1–3 | No set move: the camera and pose come from the state |

`window.mockup.shots` and `window.mockup.devices` list the same at run time.

## Setting it from a script

**From the URL.** These parameters work in any combination:
- `?state=<URL-encoded JSON>`: any part of the state; anything missing keeps its default.
- `?ui=0`: only the stage, edge to edge.
- `?play=0`: holds the clock, for a script to drive.
- `?shot=` and `?t=`: shortcuts for the shot and the time.

```
index.html?ui=0&play=0&state={"shot":"tilt","slots":[{"model":"s25ultra","finish":"Titanium Black"}],"look":{"backdrop":"Black"}}
```

**In the page** (Playwright, or the console):

```js
await mockup.ready;
mockup.set({ shot: "manual", camera: { azimuth: 30, elevation: 8, roll: -6, distance: 38 }, device: { rotY: -20 } });
await mockup.seek(2.5);            // render exactly the frame at 2.5 s (videos on screens seek too)
mockup.get();                      // the state now
mockup.setScreen(0, "flows/checkout.mp4");
const png = await mockup.snapshot({ transparent: true, save: false });   // a Blob
const mp4 = await mockup.exportVideo();                                   // a Blob, and a download
```

**From a parent page** (the page embedded in a frame):

```js
frame.contentWindow.postMessage({ mockup: "set", id: 1, state: { shot: "flip" } }, "*");
frame.contentWindow.postMessage({ mockup: "seek", id: 2, time: 3.2 }, "*");
// The page answers { mockup: "reply", id, state | time }. On load it posts { mockup: "ready" }.
```

## With Claude Code and HyperFrames

There are two ways in.

1. **Render the clip here, then cut it into the composition.**
   - Claude Code opens the page with Playwright.
   - It sets the state (devices, finishes, screen recordings, camera, backdrop, size) and calls `exportVideo()`.
   - That gives a frame-perfect MP4, which goes into the HyperFrames timeline like any other clip.

   This is the most robust route, and it keeps the 3D rendering out of the composition's own render.

2. **Embed the page live in a composition.**
   - Load it in an iframe with `?ui=0&play=0` at the composition's size.
   - Drive it from the composition's timeline: on each frame, post `{ mockup: "seek", time }` and wait for the reply before the frame is captured.
   - Post `set` on cues to cut between camera moves, devices or screens.

Either way, design the shot in the panel first, then use **Copy state** or **Copy link**. The JSON it copies is exactly what the script sets.

Screen recordings referenced by `screen` URLs must be served from the same origin (or allow CORS), so the GPU can read them.
