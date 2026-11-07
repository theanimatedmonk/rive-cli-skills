// Mockup devices: phones in a studio, for shooting app flows.
//
// Everything on screen comes from one JSON state (DEFAULTS below). The
// control panel edits it, and so can a script:
//   - the URL: ?state=<JSON> (and ?ui=0 to hide the panel, ?play=0 to hold
//     the clock for a script to drive)
//   - window.mockup: get(), set(patch), seek(t), play(), pause(),
//     setScreen(slot, url), snapshot(), exportVideo()
//   - postMessage from a parent page: { mockup: "set", state },
//     { mockup: "seek", time }, { mockup: "get" }
// See README.md.

import * as THREE from "three";
import { DEVICES, buildDevice } from "./devices.js";
import { studioEnvironment, BACKDROPS, backdropTexture, ContactShadows } from "./studio.js";
import { DemoScreen, MediaScreen, coverFit } from "./screen.js";
import { SHOTS } from "./shots.js";
import { exportMp4, download } from "./exporter.js";
import { buildUI } from "./ui.js";

export const DEFAULTS = {
  shot: "float", // a shot id (see window.mockup.shots), or "manual"
  time: 0, // seconds into the shot
  duration: 8, // the shot's length in seconds
  playing: true,
  speed: 1,
  layout: 1, // devices shown in "manual": 1, 2 or 3
  slots: [
    { model: "iphone17pro", finish: "Cosmic Orange", screen: "" },
    { model: "s25ultra", finish: "Titanium Silverblue", screen: "" },
    { model: "iphoneAir", finish: "Sky Blue", screen: "" },
  ],
  // The camera in "manual": an orbit round the target, in degrees and cm.
  camera: { azimuth: -6, elevation: 3, distance: 44, fov: 28, roll: 0, targetX: 0, targetY: 0 },
  // The device pose: added on top of any shot; in "manual" it is the pose.
  device: { rotX: 0, rotY: 0, rotZ: 0, x: 0, y: 0, z: 0, float: 1 },
  // "Your move": the camera glides from A to B.
  move: {
    a: { azimuth: -32, elevation: 12, distance: 52, fov: 28, roll: 0, targetX: 0, targetY: 0 },
    b: { azimuth: 18, elevation: -4, distance: 34, fov: 28, roll: 0, targetX: 0, targetY: 0.5 },
  },
  look: {
    backdrop: "Studio", inner: "#fbfbfd", outer: "#e3e4e9",
    shadow: 0.55, reflections: 1, exposure: 1, glare: 1, screen: 1,
  },
  output: { aspect: "16:9", height: 1080, fps: 60 },
};

export const ASPECTS = { "16:9": 16 / 9, "9:16": 9 / 16, "1:1": 1, "4:5": 4 / 5 };
const SHOT_BY_ID = Object.fromEntries(SHOTS.map((s) => [s.id, s]));
const TAU = Math.PI * 2;
const rad = THREE.MathUtils.degToRad;
const deg = THREE.MathUtils.radToDeg;
const clone = (o) => JSON.parse(JSON.stringify(o));

function merge(target, patch) {
  for (const [k, v] of Object.entries(patch || {})) {
    if (Array.isArray(v) && Array.isArray(target[k])) {
      v.forEach((item, i) => {
        if (item && typeof item === "object" && target[k][i] && typeof target[k][i] === "object") merge(target[k][i], item);
        else if (item !== undefined && item !== null) target[k][i] = item;
      });
    } else if (v && typeof v === "object" && target[k] && typeof target[k] === "object") {
      merge(target[k], v);
    } else if (v !== undefined) {
      target[k] = v;
    }
  }
  return target;
}

// ---------------------------------------------------------------------------
// State, from the defaults and the URL.

const params = new URLSearchParams(location.search);
const state = clone(DEFAULTS);
try {
  if (params.get("state")) merge(state, JSON.parse(params.get("state")));
} catch (e) {
  console.warn("mockup: ?state= is not valid JSON", e);
}
if (params.get("shot")) state.shot = params.get("shot");
if (params.has("t")) state.time = Number(params.get("t")) || 0;
if (params.get("play") === "0") state.playing = false;
if (!params.get("state")?.includes('"duration"') && SHOT_BY_ID[state.shot]) state.duration = SHOT_BY_ID[state.shot].dur;
const showUI = params.get("ui") !== "0";

// ---------------------------------------------------------------------------
// Renderer, studio, devices.

const canvas = document.getElementById("view");
const stage = document.getElementById("stage");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
const scene = new THREE.Scene();
scene.environment = studioEnvironment(renderer);
const camera = new THREE.PerspectiveCamera(28, 16 / 9, 1.5, 600);
const key = new THREE.DirectionalLight(0xffffff, 0.6);
key.position.set(6, 12, 10);
scene.add(key);
const shadows = new ContactShadows(renderer, scene);

const demos = { ios: new DemoScreen(false), android: new DemoScreen(true) };
const slots = [0, 1, 2].map(() => ({ dev: null, model: null, media: null, mediaKey: "" }));
let lastCam = null;

function applyScreen(i) {
  const s = slots[i];
  if (!s.dev) return;
  const mat = s.dev.screen.material;
  if (s.media?.texture) {
    coverFit(s.media.texture, s.media.aspect, s.dev.screen.userData.aspect);
    mat.map = s.media.texture;
  } else {
    mat.map = (DEVICES[s.model].cutout === "punch" ? demos.android : demos.ios).texture;
  }
  mat.color.setScalar(state.look.screen);
  mat.needsUpdate = true;
  s.dev.glass.material.envMapIntensity = state.look.glare;
}

async function loadMedia(i, media) {
  const s = slots[i];
  s.media?.dispose();
  s.media = null;
  s.mediaKey = media.url;
  state.slots[i].screen = media.url;
  applyScreen(i);
  try {
    await media.load();
  } catch (e) {
    toast(e.message);
    return;
  }
  if (s.mediaKey !== media.url) {
    media.dispose();
    return;
  }
  s.media = media;
  if (!state.playing) await media.seek(state.time);
  applyScreen(i);
}

function syncSlot(i) {
  const want = state.slots[i];
  const s = slots[i];
  if (!DEVICES[want.model]) want.model = DEFAULTS.slots[i].model;
  if (s.model !== want.model) {
    if (s.dev) scene.remove(s.dev.group);
    s.dev = buildDevice(want.model, want.finish);
    s.dev.group.rotation.order = "YXZ";
    s.dev.group.visible = false;
    s.model = want.model;
    scene.add(s.dev.group);
  }
  s.dev.setFinish(want.finish);
  want.finish = s.dev.group.userData.finish;
  const screenKey = want.screen || "";
  if (screenKey !== s.mediaKey) {
    if (screenKey) loadMedia(i, new MediaScreen(screenKey));
    else {
      s.media?.dispose();
      s.media = null;
      s.mediaKey = "";
    }
  }
  applyScreen(i);
}

let backdropKey = "";
function syncLook() {
  const L = state.look;
  const colors = L.backdrop === "Custom" ? [L.inner, L.outer] : BACKDROPS[L.backdrop] || BACKDROPS.Studio;
  if (colors.join() !== backdropKey) {
    backdropKey = colors.join();
    scene.background?.dispose?.();
    scene.background = backdropTexture(colors[0], colors[1]);
  }
  renderer.toneMappingExposure = L.exposure;
  scene.environmentIntensity = L.reflections;
  shadows.opacity = L.shadow;
  slots.forEach((_, i) => applyScreen(i));
}

function syncAll() {
  slots.forEach((_, i) => syncSlot(i));
  syncLook();
  layout();
}

// ---------------------------------------------------------------------------
// Shots and poses.

function orbitCamera(c) {
  const az = rad(c.azimuth), el = rad(c.elevation);
  return {
    pos: [c.targetX + c.distance * Math.sin(az) * Math.cos(el), c.targetY + c.distance * Math.sin(el), c.distance * Math.cos(az) * Math.cos(el)],
    target: [c.targetX, c.targetY, 0],
    fov: c.fov,
    roll: rad(c.roll),
  };
}

const MANUAL_LAYOUTS = {
  1: [[0, [0, 0, 0], 0]],
  2: [[0, [-4.7, 0, 1.5], 0.32], [1, [4.7, 0, -2.5], -0.38]],
  3: [[1, [-9.8, 0, -1], 0.38], [0, [0, 0, 1.5], 0], [2, [9.8, 0, -1], -0.38]],
};

const ctx = {
  spec: (slot) => DEVICES[state.slots[slot].model],
  get custom() {
    return { a: orbitCamera(state.move.a), b: orbitCamera(state.move.b) };
  },
};

function frameAt(t) {
  const shot = SHOT_BY_ID[state.shot];
  if (shot) {
    const dur = Math.max(state.duration, 0.1);
    const p = shot.loop ? (((t % dur) + dur) % dur) / dur : Math.min(Math.max(t / dur, 0), 1);
    return shot.fn(p, ctx);
  }
  const f = state.device.float;
  const items = (MANUAL_LAYOUTS[state.layout] || MANUAL_LAYOUTS[1]).map(([slot, pos, turn], n) => {
    const a = TAU * (t / 8) + n * 2.1;
    return {
      slot,
      pos: [pos[0], pos[1] + 0.45 * f * Math.sin(a), pos[2]],
      rot: [0.04 * f * Math.sin(2 * a + 1), turn + 0.18 * f * Math.sin(a), 0.03 * f * Math.sin(a + 0.6)],
    };
  });
  return { items, cam: orbitCamera(state.camera), fitWidth: state.layout > 1 ? (state.layout === 2 ? 23 : 36) : 0 };
}

function apply(t) {
  const r = frameAt(t);
  for (const s of slots) if (s.dev) s.dev.group.visible = false;
  const D = state.device;
  for (const it of r.items) {
    const g = slots[it.slot]?.dev?.group;
    if (!g) continue;
    g.visible = true;
    g.position.set(it.pos[0] + D.x, it.pos[1] + D.y, it.pos[2] + D.z);
    g.rotation.set(it.rot[0] + rad(D.rotX), it.rot[1] + rad(D.rotY), it.rot[2] + rad(D.rotZ));
  }
  const c = r.cam;
  camera.position.set(...c.pos);
  camera.up.set(0, 1, 0);
  camera.lookAt(...c.target);
  if (c.roll) camera.rotateZ(c.roll);
  let fov = c.fov;
  if (r.fitWidth) {
    const dist = camera.position.distanceTo(new THREE.Vector3(...c.target));
    fov = Math.max(fov, deg(2 * Math.atan(r.fitWidth / 2 / dist / camera.aspect)));
  }
  camera.fov = fov;
  camera.updateProjectionMatrix();
  lastCam = { pos: [...c.pos], target: [...c.target], fov };
  demos.ios.update(t);
  demos.android.update(t);
}

function render() {
  shadows.update();
  renderer.render(scene, camera);
}

// The current shot's camera, handed to the sliders ("manual" from here).
function takeOver() {
  if (!lastCam || state.shot === "manual") return;
  const [px, py, pz] = lastCam.pos, [tx, ty, tz] = lastCam.target;
  const dx = px - tx, dy = py - ty, dz = pz - tz;
  const d = Math.hypot(dx, dy, dz);
  const shot = SHOT_BY_ID[state.shot];
  state.camera = {
    azimuth: +deg(Math.atan2(dx, dz)).toFixed(1),
    elevation: +deg(Math.asin(dy / d)).toFixed(1),
    distance: +d.toFixed(1),
    fov: +lastCam.fov.toFixed(1),
    roll: 0,
    targetX: +tx.toFixed(2),
    targetY: +ty.toFixed(2),
  };
  state.layout = shot?.count || 1;
  state.shot = "manual";
}

// ---------------------------------------------------------------------------
// Sizing: the stage keeps the output's shape inside the window.

function outputSize() {
  const a = ASPECTS[state.output.aspect] || 16 / 9;
  const short = state.output.height;
  return a >= 1
    ? { width: Math.round((short * a) / 2) * 2, height: short }
    : { width: short, height: Math.round(short / a / 2) * 2 };
}

let laidOut = "";
function layout(force = false) {
  const a = ASPECTS[state.output.aspect] || 16 / 9;
  const wrap = stage.parentElement;
  const W = wrap.clientWidth, H = wrap.clientHeight;
  const w = Math.min(W, H * a), h = w / a;
  const k = `${w}x${h}`;
  if (k === laidOut && !force) return;
  laidOut = k;
  stage.style.width = `${w}px`;
  stage.style.height = `${h}px`;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(w, h, false);
  camera.aspect = a;
}
new ResizeObserver(() => layout()).observe(stage.parentElement);

// ---------------------------------------------------------------------------
// The clock.

let exporting = false;
let last = performance.now();
function tick(now) {
  requestAnimationFrame(tick);
  const dt = Math.min((now - last) / 1000, 0.1);
  last = now;
  if (exporting) return;
  if (state.playing) {
    state.time += dt * state.speed;
    const shot = SHOT_BY_ID[state.shot];
    // A one-way shot holds its last frame a moment, then starts again.
    if (shot && !shot.loop && state.time > state.duration + 1.2) state.time = 0;
    for (const s of slots) s.media?.update();
  }
  apply(state.time);
  render();
  ui?.tick(state);
}

async function seek(t) {
  state.time = t;
  await Promise.all(slots.map((s) => s.media?.seek(t)));
  apply(t);
  render();
}

function setPlaying(on) {
  state.playing = on;
  if (on) slots.forEach((s) => s.media?.resume());
  else slots.forEach((s) => s.media?.video?.pause());
}

// ---------------------------------------------------------------------------
// Output: video and stills.

async function renderAt(width, height, fn) {
  exporting = true;
  const wasPlaying = state.playing;
  setPlaying(false);
  renderer.setPixelRatio(1);
  renderer.setSize(width, height, false);
  camera.aspect = width / height;
  try {
    return await fn();
  } finally {
    layout(true);
    exporting = false;
    if (wasPlaying) setPlaying(true);
  }
}

let cancelExport = false;
async function exportVideo({ onProgress } = {}) {
  const { width, height } = outputSize();
  const fps = state.output.fps;
  const duration = state.duration;
  const start = state.time;
  cancelExport = false;
  const blob = await renderAt(width, height, () =>
    exportMp4({
      canvas, width, height, fps, duration,
      drawFrame: (t) => seek(t),
      onProgress,
      isCancelled: () => cancelExport,
    }),
  );
  state.time = start;
  if (blob) download(blob, `mockup-${state.shot}-${width}x${height}-${fps}fps.mp4`);
  return blob;
}

async function snapshot({ transparent = false, save = true } = {}) {
  const { width, height } = outputSize();
  const blob = await renderAt(width, height, async () => {
    await seek(state.time);
    if (transparent) {
      const bg = scene.background;
      scene.background = null;
      renderer.setClearColor(0x000000, 0);
      render();
      scene.background = bg;
    }
    return new Promise((ok) => canvas.toBlob(ok, "image/png"));
  });
  if (save) download(blob, `mockup-${state.shot}-${width}x${height}${transparent ? "-alpha" : ""}.png`);
  return blob;
}

// ---------------------------------------------------------------------------
// The API, for the panel and for scripts.

function get() {
  const s = clone(state);
  // A dropped file's blob: URL means nothing outside this page.
  s.slots.forEach((slot) => {
    if (slot.screen.startsWith("blob:")) slot.screen = "";
  });
  return s;
}

function set(patch = {}) {
  const shotChanged = patch.shot && patch.shot !== state.shot;
  merge(state, patch);
  if (shotChanged && patch.duration === undefined && SHOT_BY_ID[state.shot]) state.duration = SHOT_BY_ID[state.shot].dur;
  if (shotChanged && patch.time === undefined) state.time = 0;
  if (patch.playing !== undefined) setPlaying(state.playing);
  syncAll();
  ui?.refresh(state);
  return get();
}

function setScreen(slot, source) {
  if (!source) return set({ slots: Object.assign([], { [slot]: { screen: "" } }) });
  loadMedia(slot, new MediaScreen(source));
  ui?.refresh(state);
}

function stateUrl() {
  const u = new URL(location.href);
  u.search = "";
  u.searchParams.set("state", JSON.stringify(get()));
  return u.toString();
}

function toast(text) {
  const el = document.getElementById("toast");
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (el.hidden = true), 2600);
}

let readyResolve;
const api = {
  version: 1,
  get, set, seek, setScreen, snapshot, exportVideo, stateUrl, takeOver,
  play: () => set({ playing: true }),
  pause: () => set({ playing: false }),
  cancelExport: () => (cancelExport = true),
  outputSize,
  toast,
  shots: [...SHOTS.map(({ id, name, count, dur, loop }) => ({ id, name, devices: count, duration: dur, loop })), { id: "manual", name: "Manual (sliders, drag to orbit)", devices: "layout", duration: null, loop: true }],
  devices: Object.entries(DEVICES).map(([id, d]) => ({ id, name: d.name, finishes: Object.keys(d.finishes), sizeCm: [d.w, d.h, d.d] })),
  backdrops: [...Object.keys(BACKDROPS), "Custom"],
  ready: new Promise((r) => (readyResolve = r)),
};
window.mockup = api;
window.mockupDefaults = DEFAULTS;

// From a parent page (e.g. a video composition embedding this in a frame).
window.addEventListener("message", async (e) => {
  const m = e.data;
  if (!m || typeof m !== "object" || !m.mockup) return;
  const reply = (data) => e.source?.postMessage({ mockup: "reply", id: m.id, ...data }, "*");
  if (m.mockup === "set") reply({ state: set(m.state) });
  else if (m.mockup === "seek") {
    await seek(m.time);
    reply({ time: m.time });
  } else if (m.mockup === "get") reply({ state: get() });
});

// ---------------------------------------------------------------------------
// Pointer: drag to orbit, wheel to dolly (switches to manual).

let drag = null;
canvas.addEventListener("pointerdown", (e) => {
  drag = { x: e.clientX, y: e.clientY };
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener("pointermove", (e) => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  if (Math.abs(dx) + Math.abs(dy) < 2) return;
  drag = { x: e.clientX, y: e.clientY };
  takeOver();
  state.camera.azimuth = +(state.camera.azimuth - dx * 0.3).toFixed(1);
  state.camera.elevation = +Math.min(Math.max(state.camera.elevation + dy * 0.2, -60), 75).toFixed(1);
  ui?.refresh(state);
});
canvas.addEventListener("pointerup", () => (drag = null));
canvas.addEventListener(
  "wheel",
  (e) => {
    e.preventDefault();
    takeOver();
    state.camera.distance = +Math.min(Math.max(state.camera.distance * Math.exp(e.deltaY * 0.001), 8), 160).toFixed(1);
    ui?.refresh(state);
  },
  { passive: false },
);

// Drop a screen recording or screenshot onto the page: it goes on device 1.
window.addEventListener("dragover", (e) => e.preventDefault());
window.addEventListener("drop", (e) => {
  e.preventDefault();
  const file = [...(e.dataTransfer?.files || [])].find((f) => /^(video|image)\//.test(f.type));
  if (!file) return;
  loadMedia(0, new MediaScreen(file));
  toast(`${file.name} is on device 1`);
  ui?.refresh(state);
});

window.addEventListener("keydown", (e) => {
  if (e.target.closest("input, select, textarea")) return;
  if (e.code === "Space") {
    e.preventDefault();
    set({ playing: !state.playing });
  } else if (e.key === "h") ui?.togglePanel();
});

// ---------------------------------------------------------------------------

const ui = showUI ? buildUI(api, state, { DEVICES, BACKDROPS, ASPECTS, loadFile: (i, file) => loadMedia(i, new MediaScreen(file)) }) : null;
if (!showUI) document.body.classList.add("bare");
syncAll();
ui?.refresh(state);
apply(state.time);
render();
requestAnimationFrame(tick);
readyResolve(api);
if (window.parent !== window) window.parent.postMessage({ mockup: "ready" }, "*");
