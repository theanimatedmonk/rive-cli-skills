---
name: rive-android
description: How to ship a Rive (.riv) animation in an Android app, choosing between the WebView route (Rive web runtime in a WebView, optionally inside Capacitor) and the native route (rive-android with a .riv authored without WGSL shaders or GPU canvases). Use when putting a Rive file into an Android app, when a .riv renders blank, partly blank or with wrong colours on Android, or when a file uses Luau scripts with gpuCanvas, WGSL shaders, offscreen canvases or blend modes and must run on Android.
---

# Rive on Android: two routes that work

Verified on 2026-10-07 with the Rive Android runtime **11.13.0** (`app.rive:rive-android`) and the Rive web runtime **@rive-app/webgl2 2.43.1**, on a Pixel 7 emulator (API 34, `-gpu host`) and a real phone. Re-check the version notes before relying on these limits: the native runtime's GPU support is moving quickly.

## Pick a route

| | WebView route | Native route |
| --- | --- | --- |
| Runtime | Rive web runtime (WebGL2) in an Android WebView | `rive-android` on Vulkan or OpenGL |
| WGSL shaders, GPU canvases (`context:gpuCanvas`) | **Work** | **Do not render** |
| Plain node scripts (paths, `Paint.feather`) | Work | Work |
| The `.riv` | Use it as it is | Needs a vector-only version (see the authoring rules) |
| Startup and memory | A WebView plus WASM: heavier, slower first frame | Lightest, native frame pacing |
| App size (debug, all ABIs) | About 10–18 MB | About 40 MB (rive-android's native libraries; split ABIs for release) |
| Data binding from Kotlin | Through a JS bridge | Direct: `ViewModelInstance` APIs |
| Best for | Shader-heavy files you don't want to rework; reusing a web demo | Production apps; files you can author for native |

Rule of thumb: if the file's look depends on WGSL shaders or GPU canvases, use the WebView route now, or author a native version. Otherwise go native.

You can mix them: keep the app's screens in Jetpack Compose and use a WebView only for the Rive moment (see the Hybrid section).

---

## What breaks on the native runtime (rive-android 11.13)

| Content | Native result | What to do instead |
| --- | --- | --- |
| Luau scripts that render through `context:gpuCanvas()` plus a WGSL `ShaderAsset` | Nothing drawn. This happens with the deferred worker on Vulkan (the documented GPU Canvas path), the standard worker on Vulkan, and OpenGL, on the emulator and on a real phone. The `.riv` does contain SPIR-V, GLSL and MSL, so it isn't a missing export. | Vector drawing in plain node scripts (see the authoring rules) |
| Scripts that render artboards into an offscreen `context:canvas()` and texture them with `drawImageMesh` (fake 3D cards) | Did not render in the file tested. It was mixed with a shader, so this wasn't isolated; treat it as unsupported | Timeline animation (for example a scaleX flip) |
| `blendMode = 'screen'` (in scripts or as `blendModeValue` on shapes) combined with large feathering | Renders hot magenta on Vulkan, though it looks right in the editor, in the CLI renderer and on OpenGL | Normal (srcOver) blending with translucent colours |

What works natively, on both Vulkan and OpenGL:
- artboards, state machines, nested artboards and remapped animations
- listeners (`click`)
- view-model triggers, numbers and strings, and image binding at runtime
- node scripts that draw paths, with `Paint.feather` for softness
- feathered strokes and fills on shapes, and gradients

To prove a GPU problem quickly, load a tiny test file: one panel draws an image directly, a second runs a one-line shader on it through a GPU canvas. If only the direct panel shows, GPU canvases don't render on that device.

---

## Native route

### 1. Author the .riv for native

Keep every artboard, state machine, state, trigger and view-model property name the same as the original, so app code and remapped animations keep working. Replace only the effects.

- **No WGSL or GPU canvases.** Remove the `ShaderAsset`s and any `gpuCanvas` code.
- **No offscreen canvas tricks.** Don't use `context:canvas()` with `drawImageMesh` for fake 3D.
- **No blend modes.** Use srcOver with translucent colours everywhere: script paints and shape `blendModeValue`.
- **Shader clouds or nebulae:** large ellipses drawn in a node script with heavy `Paint.feather` (about 0.9 × radius) and low alpha, drifting slowly. Add a few dark feathered patches for depth.
- **Shader grain or noise:** a field of thousands of tiny dots (0.35–1.3 px squares), placed by rejection sampling against a fractal value noise so they clump into wisps. **Build them once** into a few static `Path`s, bucketed by tint and twinkle group (for example 4 × 3 = 12 paths). Each frame, only transform and recolour those paths: a dozen draw calls, not thousands.
- **3D card flip:** a timeline animation instead of a script. Key the faces group's `scaleX` 1 → 0 → 1 for each half-turn, and swap front and back visibility (opacity, with hold interpolation) at each edge-on frame. Add a feathered gradient shine band, clipped to the card, that sweeps across as it lands.
- **Keep the script inputs the state machine keys.** For example, a Nebula script's `heat`, `blast`, `mist` and `grain` stay; only the drawing changes.
- **Binds need a running state machine.** Every artboard whose bindings or scripts must run needs a state machine, even an idle one.

Build a signed file, because native runtimes run only signed scripts:

```sh
rive . --verify
rive . --publish          # writes build/<name>.riv (signed)
```

### 2. App setup

`app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("app.rive:rive-android:11.13.0")
    // Compose BOM, activity-compose, material3, ...
}
android {
    androidResources { noCompress += "riv" }   // keep the .riv uncompressed
}
```

Put the signed `.riv` in `res/raw/`.

Initialise once, before any worker exists (otherwise: "No implementation found for … RenderContext… cppConstructor"):

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    app.rive.runtime.kotlin.core.Rive.init(this)
    app.rive.RiveLog.logger = app.rive.RiveLog.LogcatLogger()   // debug builds: Rive's own log
    setContent { App() }
}
```

### 3. Compose: load once, render, bind

Create one worker and one file for the whole app, so screens reopen instantly. `RiveWorker` lives in `app.rive.core`.

```kotlin
val worker = rememberRiveWorker(renderBackend = RenderBackend.Vulkan)   // falls back to OpenGL by itself
val file = rememberRiveFile(RiveFileSource.RawRes.from(R.raw.my_file), worker)   // Result<RiveFile>

// In the screen:
val artboard = rememberArtboard(file, "MainArtboard")
val stateMachine = rememberStateMachine(artboard, "MainStateMachine")
val vmi = rememberViewModelInstanceResult(
    file, ViewModelSource.DefaultForArtboard(artboard).defaultInstance(),
)
if (vmi is Result.Success) {
    Rive(
        file = file, artboard = artboard, stateMachine = stateMachine,
        viewModelInstance = vmi.value, fit = Fit.Cover(), modifier = Modifier.fillMaxSize(),
    )
}
```

The view-model calls you'll use:

```kotlin
vmi.getTriggerFlow("pick1")                 // Flow<Unit>; merge() several, then .first()
vmi.fireTrigger("reveal")
vmi.setString("birdName", "Osprey")
vmi.setNumber("harmony", 3f)
// Images: decode, bind, and close when done.
val image = ImageAsset.fromBytes(worker, bytes)           // suspend, returns Result<ImageAsset>
if (image is Result.Success) vmi.setImage("face", image.value)
```

`rememberDeferredRiveWorker(renderBackend = RenderBackend.Vulkan)` (marked `@ExperimentalDeferredRendering`) is the documented GPU Canvas mode, but GPU canvas content still didn't render in our tests. Use the standard worker unless a newer release says otherwise.

### 4. Gate taps until the state machine can take them

The Compose API exposes no state-change events. If a state only accepts triggers after an intro animation and blend (for example Layout → FanIdle), a tap during the intro fires a trigger that the state machine swallows, and your flow then waits forever. Put a transparent layer over `Rive` that consumes pointer events until the intro has finished. The intro length is the animation length ÷ speed + blend + a margin. Keep it in a named constant, with a comment saying where the number came from:

```kotlin
if (!ready) Box(Modifier.fillMaxSize().pointerInput(Unit) {
    awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } }
})
```

---

## WebView route

Use the Rive **web** runtime with GPU Canvas enabled. It renders WGSL shaders in Android's WebView, since WebView is Chrome-based and runs them on WebGL2.

### Essentials

1. **Bundle the runtime locally.** Ship `rive.js`, `rive.wasm` and `rive_fallback.wasm` from `@rive-app/webgl2`, and point the loader at them before creating Rive:
   ```html
   <script src="vendor/rive.js"></script>
   <script>rive.RuntimeLoader.setWasmUrl("vendor/rive.wasm");</script>
   ```
   ```js
   new rive.Rive({ src: "my.riv", canvas, stateMachines: "Main", autoplay: true,
                   autoBind: true, enableGPUCanvas: true, /* ... */ });
   ```
2. **Use the signed `.riv`** (`rive . --publish`). Web runtimes reject unsigned scripts.
3. **Serve over https, not `file://`.** `fetch()` of the `.riv`, the WASM and images fails on `file://`. In a plain WebView, use `androidx.webkit:webkit` and `WebViewAssetLoader` with an `AssetsPathHandler`, then load `https://appassets.androidplatform.net/assets/web/index.html`. Capacitor does this for you (`https://localhost/`).
4. **Bridge events to Kotlin** with `addJavascriptInterface(obj, "Bridge")`. Methods run on a WebView thread, so post them to the main thread. Call them from JS, for example `window.Bridge.openReading(index)`.
5. **Don't put the WebView in an animated Compose container** (`AnimatedContent` or `Crossfade`). Inside a fading graphics layer it draws blank. Switch screens with a plain `when`.
6. **Position fixed-size stages in pixels from JavaScript.** Percentage positions can resolve against a zero-height WebView at first layout. Compute the scale and offset from `innerWidth` and `innerHeight` and set `transform: translate(x, y) scale(s)`.
7. **Debug builds:** call `WebView.setWebContentsDebuggingEnabled(true)`, then inspect with `chrome://inspect` or over DevTools: `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`.

### Capacitor (a whole web app as the APK)

```sh
npm i @capacitor/core @capacitor/android @rive-app/webgl2 && npm i -D @capacitor/cli
npx cap init "App Name" com.example.app --web-dir www
npx cap add android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" npx cap sync android
cd android && ./gradlew assembleDebug        # or: npx cap run android / npx cap open android
```

- **Use Android Studio's bundled JDK** (21). A newer system Java (for example 25) makes the Android Gradle plugin step fail.
- **Generate `www/` with a sync script** from the web project, so the web project stays the single source. The script copies the files, swaps the CDN `<script>` for the bundled runtime, and injects app-only CSS (hide web-only chrome, fit the stage to the screen).

### Hybrid: native screens, WebView only for Rive

Compose handles navigation and the screens before and after the animation. A WebView page holds only the Rive stage, its overlays and the bridge calls. Share data, for example a JSON file generated from the web project, between the page and Kotlin.

---

## Testing on Android

- **Emulator:** `emulator -avd <name> -gpu host`. On Apple Silicon this gives Vulkan through gfxstream (`ro.hardware.vulkan=ranchu`). Run one emulator at a time: a second instance shuts down if one is already running (for example one launched from Android Studio).
- **Drive it:** use `adb shell am start -W …`, `adb shell input tap X Y`, and `adb exec-out screencap -p > shot.png`.
- **Unexpected taps:** `adb shell input` taps don't appear in `adb shell getevent -lt`; touches from the emulator window or a device screen do. Record `getevent` during a test to tell whether unexpected picks came from someone else touching the device.
- **Logs:** `adb logcat` with `RiveLog.LogcatLogger()` on. A Vulkan failure logs "falling back to OpenGL".
- **Compare backends:** compare a capture on Vulkan with the CLI render (`rive . --screenshot --advance=3s`). Colour or blend problems show up only on the device.
- **Side-by-side tests:** debug launch switches help, for example `--ez deferred false --es backend opengl` read from the intent.

## Checklist

- [ ] Route chosen: does the look depend on WGSL or GPU canvases?
- [ ] Native: no `gpuCanvas`, no `ShaderAsset`, no `canvas()` + `drawImageMesh`, no blend modes; artboards that bind have a state machine
- [ ] Signed `.riv` (`rive . --publish`), uncompressed in the APK
- [ ] `Rive.init(context)` before any worker
- [ ] One worker and one file, reused
- [ ] Taps gated until the state machine accepts triggers
- [ ] WebView: local runtime and WASM, https asset loader, no animated container around it, pixel positioning
- [ ] Checked on Vulkan and OpenGL, and on a real device
