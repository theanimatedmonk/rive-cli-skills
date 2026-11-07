// DeviceStage: real phones in a studio, with your live UI on their screens.
//
// Each phone's screen is a real DOM element at the phone's CSS viewport
// (402 x 874 on an iPhone 17 Pro): your own elements, or an <iframe> of a
// page. It is placed in 3D with three.js's CSS3DRenderer, under a WebGL
// canvas that draws the phones, the studio and the glass, with a clear hole
// where each screen is. So the UI is the real thing, running and tappable,
// and the glass, the Dynamic Island and the reflections sit over it.
//
//   const stage = new DeviceStage(container, { state: { shot: "float" } });
//   stage.screen(0).append(myApp);                  // or:
//   stage.set({ slots: [{ screen: "flow.html" }] });  // a page, in an iframe
//
// Everything comes from one JSON state (DEFAULTS). set(patch) changes it,
// seek(t) renders the frame at t seconds, get() reads it.
//
// Interaction: `interact` is "screen" (your pointer uses the app; the 3D
// view is locked) or "device" (the app is locked; drag to orbit, scroll to
// zoom). It only filters the pointer: a script can always do both.

import * as THREE from "three";
import { CSS3DRenderer, CSS3DObject } from "three/addons/renderers/CSS3DRenderer.js";
import { DEVICES, buildDevice } from "./devices.js";
import { studioEnvironment, BACKDROPS, backdropTexture, ContactShadows } from "./studio.js";
import { DemoScreen, MediaScreen, coverFit } from "./screen.js";
import { SHOTS } from "./shots.js";
import { exportMp4, download } from "./exporter.js";

export const DEFAULTS = {
  shot: "float", // a shot id (stage.shots), or "manual"
  time: 0, // seconds into the shot
  duration: 8, // the shot's length in seconds
  playing: true,
  speed: 1,
  interact: "screen", // "screen": use the app; "device": move the camera
  layout: 1, // devices shown in "manual": 1, 2 or 3
  slots: [
    // screen: "" the demo app; "dom" your elements (stage.screen(i));
    // a page URL (an iframe); a video or image URL; or a named screen.
    { model: "iphone17pro", finish: "Deep Blue", screen: "" },
    { model: "s25ultra", finish: "Titanium Silverblue", screen: "" },
    { model: "iphoneAir", finish: "Sky Blue", screen: "" },
  ],
  // The camera in "manual": an orbit round the target, in degrees and cm.
  camera: { azimuth: -6, elevation: 3, distance: 44, fov: 28, roll: 0, targetX: 0, targetY: 0 },
  // The device pose: added on top of any shot; in "manual" it is the pose.
  device: { rotX: 0, rotY: 0, rotZ: 0, x: 0, y: 0, z: 0, float: 1 },
  // The "custom" shot glides the camera from A to B.
  move: {
    a: { azimuth: -32, elevation: 12, distance: 52, fov: 28, roll: 0, targetX: 0, targetY: 0 },
    b: { azimuth: 18, elevation: -4, distance: 34, fov: 28, roll: 0, targetX: 0, targetY: 0.5 },
  },
  look: {
    backdrop: "Studio", inner: "#fbfbfd", outer: "#e3e4e9",
    shadow: 0.55, reflections: 1, exposure: 1, glare: 1, screen: 1,
  },
  // aspect: "fill" (the container's shape), "16:9", "9:16", "1:1", "4:5".
  output: { aspect: "fill", height: 1080, fps: 60 },
};

export const ASPECTS = { "16:9": 16 / 9, "9:16": 9 / 16, "1:1": 1, "4:5": 4 / 5 };
const SHOT_BY_ID = Object.fromEntries(SHOTS.map((s) => [s.id, s]));
const TAU = Math.PI * 2;
const rad = THREE.MathUtils.degToRad;
const deg = THREE.MathUtils.radToDeg;
const clone = (o) => JSON.parse(JSON.stringify(o));
const VIDEO = /\.(mp4|webm|mov|m4v)(\?|#|$)/i;
const IMAGE = /\.(png|jpe?g|webp|gif|avif|svg)(\?|#|$)/i;

// The CSS viewport of each model, and its safe areas (CSS px).
const VIEWPORT = {
  iphone17pro: { width: 402, top: 62, bottom: 34 },
  iphoneAir: { width: 420, top: 68, bottom: 34 },
  s25ultra: { width: 412, top: 36, bottom: 24 },
};

export function merge(target, patch) {
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

const STYLE = `
.ds-root { position: relative; display: grid; place-items: center; overflow: hidden; }
.ds-stage { position: relative; overflow: hidden; }
.ds-css, .ds-gl { position: absolute; inset: 0; width: 100%; height: 100%; }
.ds-gl { pointer-events: none; display: block; }
.ds-root[data-interact="device"] .ds-css, .ds-root[data-interact="device"] .ds-screen { pointer-events: none !important; }
.ds-root[data-interact="device"] .ds-stage { cursor: grab; touch-action: none; }
.ds-root[data-interact="device"] .ds-stage:active { cursor: grabbing; }
.ds-screen { overflow: hidden; background: #000; backface-visibility: hidden; container-type: size; }
.ds-screen > iframe { display: block; width: 100%; height: 100%; border: 0; background: #000; }
.ds-lock { position: absolute; left: 12px; top: 12px; z-index: 2; display: inline-flex; padding: 3px; gap: 2px; border-radius: 999px;
  background: rgba(30, 30, 32, 0.55); backdrop-filter: blur(14px) saturate(1.4); font: 600 12px/1 Inter, -apple-system, system-ui, sans-serif; }
.ds-lock button { border: 0; background: none; color: rgba(255, 255, 255, 0.75); padding: 7px 11px; border-radius: 999px; cursor: pointer; font: inherit; }
.ds-lock button[aria-pressed="true"] { background: #fff; color: #1d1d1f; }
`;
let styled = false;

export class DeviceStage {
  constructor(container, { state = {}, screens = {}, lockToggle = true } = {}) {
    if (!styled) {
      const s = document.createElement("style");
      s.textContent = STYLE;
      document.head.append(s);
      styled = true;
    }
    this.container = container;
    this.namedScreens = screens;
    this.state = merge(clone(DEFAULTS), state);
    if (state.duration === undefined && SHOT_BY_ID[this.state.shot]) this.state.duration = SHOT_BY_ID[this.state.shot].dur;
    this.listeners = new Set();
    this.exporting = false;

    container.classList.add("ds-root");
    this.stageEl = document.createElement("div");
    this.stageEl.className = "ds-stage";
    this.cssEl = document.createElement("div");
    this.cssEl.className = "ds-css";
    this.canvas = document.createElement("canvas");
    this.canvas.className = "ds-gl";
    this.stageEl.append(this.cssEl, this.canvas);
    container.append(this.stageEl);
    if (lockToggle) this.stageEl.append(this.buildLock());

    // Renderers: WebGL over CSS 3D, one camera.
    const renderer = (this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, alpha: true, preserveDrawingBuffer: true }));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.NeutralToneMapping;
    this.css = new CSS3DRenderer({ element: this.cssEl });
    this.scene = new THREE.Scene();
    this.cssScene = new THREE.Scene();
    this.scene.environment = studioEnvironment(renderer);
    this.camera = new THREE.PerspectiveCamera(28, 16 / 9, 1.5, 600);
    const key = new THREE.DirectionalLight(0xffffff, 0.6);
    key.position.set(6, 12, 10);
    this.scene.add(key);
    this.shadows = new ContactShadows(renderer, this.scene);

    // Where a screen shows live DOM, the canvas is clear: the mesh writes
    // transparent black, and the DOM below shows through.
    this.holeMaterial = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, blending: THREE.NoBlending });

    this.demos = { ios: new DemoScreen(false), android: new DemoScreen(true) };
    // The CSS renderer's camera element: screens live in it from the start
    // (hidden until shown), so your UI is in the document right away.
    const cameraEl = this.cssEl.firstElementChild.firstElementChild;
    this.slots = [0, 1, 2].map(() => {
      const el = document.createElement("div");
      el.className = "ds-screen";
      el.style.display = "none";
      cameraEl.append(el);
      const object = new CSS3DObject(el);
      object.matrixAutoUpdate = false;
      object.visible = false;
      this.cssScene.add(object);
      return { dev: null, model: null, media: null, mediaKey: "", el, object, frame: null, live: false };
    });

    this.ctx = {
      spec: (slot) => DEVICES[this.state.slots[slot].model],
      custom: null,
    };
    Object.defineProperty(this.ctx, "custom", {
      get: () => ({ a: this.orbitCamera(this.state.move.a), b: this.orbitCamera(this.state.move.b) }),
    });

    this.bindPointer();
    this.resizeObserver = new ResizeObserver(() => this.layout());
    this.resizeObserver.observe(container);
    this.syncAll();
    this.apply(this.state.time);
    this.render();
    this.last = performance.now();
    this.raf = requestAnimationFrame((t) => this.tick(t));
  }

  // --- Lists, for panels and scripts ---------------------------------------
  get shots() {
    return [...SHOTS.map(({ id, name, count, dur, loop }) => ({ id, name, devices: count, duration: dur, loop })), { id: "manual", name: "Manual (sliders, drag to orbit)", devices: "layout", duration: null, loop: true }];
  }
  get devices() {
    return Object.entries(DEVICES).map(([id, d]) => ({ id, name: d.name, finishes: Object.keys(d.finishes), viewport: this.viewport(id) }));
  }
  get backdrops() {
    return [...Object.keys(BACKDROPS), "Custom"];
  }

  // The CSS viewport of a model: { width, height, safeTop, safeBottom }.
  viewport(model) {
    const v = VIEWPORT[model];
    const spec = DEVICES[model];
    const glassInset = spec.edge * 0.45;
    const aspect = (spec.w - 2 * glassInset - 2 * spec.bezel) / (spec.h - 2 * glassInset - 2 * spec.bezel);
    return { width: v.width, height: Math.round(v.width / aspect), safeTop: v.top, safeBottom: v.bottom };
  }

  // The element a device's screen shows: put your UI in it.
  screen(i = 0) {
    const s = this.slots[i];
    if (this.state.slots[i].screen !== "dom") this.set({ slots: Object.assign([], { [i]: { screen: "dom" } }) });
    return s.el;
  }

  // The window of a screen's iframe, if it shows a page.
  frameWindow(i = 0) {
    return this.slots[i].frame?.contentWindow || null;
  }

  // --- State ----------------------------------------------------------------
  get() {
    const s = clone(this.state);
    s.slots.forEach((slot) => {
      if (slot.screen.startsWith("blob:")) slot.screen = "";
    });
    return s;
  }

  set(patch = {}) {
    const state = this.state;
    const shotChanged = patch.shot && patch.shot !== state.shot;
    merge(state, patch);
    if (shotChanged && patch.duration === undefined && SHOT_BY_ID[state.shot]) state.duration = SHOT_BY_ID[state.shot].dur;
    if (shotChanged && patch.time === undefined) state.time = 0;
    if (patch.playing !== undefined) this.setPlaying(state.playing);
    this.syncAll();
    this.emit();
    return this.get();
  }

  on(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
  emit() {
    for (const fn of this.listeners) fn(this.state);
  }

  play() {
    return this.set({ playing: true });
  }
  pause() {
    return this.set({ playing: false });
  }

  setInteract(mode) {
    return this.set({ interact: mode === "device" ? "device" : "screen" });
  }

  // A dropped file, or a URL, on a screen.
  setScreen(i, source) {
    if (!source) return this.set({ slots: Object.assign([], { [i]: { screen: "" } }) });
    if (typeof source !== "string") {
      this.loadMedia(i, new MediaScreen(source));
      this.emit();
      return this.get();
    }
    return this.set({ slots: Object.assign([], { [i]: { screen: source } }) });
  }

  // --- Syncing devices, screens and the look ---------------------------------
  resolveScreen(screen, model) {
    const named = this.namedScreens[screen];
    return named ? (typeof named === "function" ? named(model, DEVICES[model]) : named) : screen || "";
  }

  async loadMedia(i, media, name = media.url) {
    const s = this.slots[i];
    s.media?.dispose();
    s.media = null;
    s.mediaKey = media.url;
    this.state.slots[i].screen = name;
    this.applyScreen(i);
    try {
      await media.load();
    } catch (e) {
      console.warn(e.message);
      return;
    }
    if (s.mediaKey !== media.url) {
      media.dispose();
      return;
    }
    s.media = media;
    if (!this.state.playing) await media.seek(this.mediaTime(this.state.time));
    this.applyScreen(i);
  }

  syncSlot(i) {
    const want = this.state.slots[i];
    const s = this.slots[i];
    if (!DEVICES[want.model]) want.model = DEFAULTS.slots[i].model;
    if (s.model !== want.model) {
      if (s.dev) this.scene.remove(s.dev.group);
      s.dev = buildDevice(want.model, want.finish);
      s.dev.group.rotation.order = "YXZ";
      s.dev.group.visible = false;
      s.model = want.model;
      this.scene.add(s.dev.group);
      const v = this.viewport(want.model);
      Object.assign(s.el.style, { width: `${v.width}px`, height: `${v.height}px` });
      s.el.style.setProperty("--ds-safe-top", `${v.safeTop}px`);
      s.el.style.setProperty("--ds-safe-bottom", `${v.safeBottom}px`);
      s.dev.screen.geometry.computeBoundingBox();
      const bb = s.dev.screen.geometry.boundingBox;
      s.scale = (bb.max.x - bb.min.x) / v.width;
    }
    s.dev.setFinish(want.finish);
    want.finish = s.dev.group.userData.finish;

    // What the screen shows.
    const url = want.screen === "dom" ? "dom" : this.resolveScreen(want.screen, want.model);
    if (url !== s.mediaKey) {
      s.media?.dispose();
      s.media = null;
      s.mediaKey = url;
      if (s.frame) {
        s.frame.remove();
        s.frame = null;
      }
      if (!url || url === "dom") {
        // The demo, or the elements already in the screen.
      } else if (VIDEO.test(url) || IMAGE.test(url) || url.startsWith("blob:")) {
        this.loadMedia(i, new MediaScreen(url), want.screen);
      } else {
        const frame = document.createElement("iframe");
        frame.src = url;
        frame.allow = "autoplay; clipboard-write";
        frame.title = `Screen of device ${i + 1}`;
        s.el.replaceChildren(frame);
        s.frame = frame;
      }
    }
    s.live = url === "dom" || !!s.frame;
    this.applyScreen(i);
  }

  applyScreen(i) {
    const s = this.slots[i];
    if (!s.dev) return;
    const screen = s.dev.screen;
    if (s.live) {
      screen.material = this.holeMaterial;
    } else {
      if (!s.texMaterial) s.texMaterial = new THREE.MeshBasicMaterial({ color: "#ffffff", toneMapped: false });
      const mat = s.texMaterial;
      if (s.media?.texture) {
        coverFit(s.media.texture, s.media.aspect, screen.userData.aspect);
        mat.map = s.media.texture;
      } else {
        mat.map = (DEVICES[s.model].cutout === "punch" ? this.demos.android : this.demos.ios).texture;
      }
      mat.color.setScalar(this.state.look.screen);
      mat.needsUpdate = true;
      screen.material = mat;
    }
    s.el.style.filter = this.state.look.screen === 1 ? "" : `brightness(${this.state.look.screen})`;
    s.dev.glass.material.envMapIntensity = this.state.look.glare;
  }

  syncLook() {
    const L = this.state.look;
    const colors = L.backdrop === "Custom" ? [L.inner, L.outer] : BACKDROPS[L.backdrop] || BACKDROPS.Studio;
    if (colors.join() !== this.backdropKey) {
      this.backdropKey = colors.join();
      this.scene.background?.dispose?.();
      this.scene.background = backdropTexture(colors[0], colors[1]);
    }
    this.renderer.toneMappingExposure = L.exposure;
    this.scene.environmentIntensity = L.reflections;
    this.shadows.opacity = L.shadow;
  }

  syncAll() {
    this.slots.forEach((_, i) => this.syncSlot(i));
    this.syncLook();
    this.container.dataset.interact = this.state.interact;
    this.lockButtons?.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.mode === this.state.interact)));
    this.layout();
  }

  // --- Shots and poses -------------------------------------------------------
  orbitCamera(c) {
    const az = rad(c.azimuth), el = rad(c.elevation);
    return {
      pos: [c.targetX + c.distance * Math.sin(az) * Math.cos(el), c.targetY + c.distance * Math.sin(el), c.distance * Math.cos(az) * Math.cos(el)],
      target: [c.targetX, c.targetY, 0],
      fov: c.fov,
      roll: rad(c.roll),
    };
  }

  frameAt(t) {
    const state = this.state;
    const shot = SHOT_BY_ID[state.shot];
    if (shot) {
      const dur = Math.max(state.duration, 0.1);
      const p = shot.loop ? (((t % dur) + dur) % dur) / dur : Math.min(Math.max(t / dur, 0), 1);
      return shot.fn(p, this.ctx);
    }
    const f = state.device.float;
    const layouts = {
      1: [[0, [0, 0, 0], 0]],
      2: [[0, [-4.7, 0, 1.5], 0.32], [1, [4.7, 0, -2.5], -0.38]],
      3: [[1, [-9.8, 0, -1], 0.38], [0, [0, 0, 1.5], 0], [2, [9.8, 0, -1], -0.38]],
    };
    const items = (layouts[state.layout] || layouts[1]).map(([slot, pos, turn], n) => {
      const a = TAU * (t / 8) + n * 2.1;
      return {
        slot,
        pos: [pos[0], pos[1] + 0.45 * f * Math.sin(a), pos[2]],
        rot: [0.04 * f * Math.sin(2 * a + 1), turn + 0.18 * f * Math.sin(a), 0.03 * f * Math.sin(a + 0.6)],
      };
    });
    return { items, cam: this.orbitCamera(state.camera), fitWidth: state.layout > 1 ? (state.layout === 2 ? 23 : 36) : 0 };
  }

  apply(t) {
    const r = this.frameAt(t);
    for (const s of this.slots) {
      if (s.dev) s.dev.group.visible = false;
      s.object.visible = false;
    }
    const D = this.state.device;
    for (const it of r.items) {
      const s = this.slots[it.slot];
      const g = s?.dev?.group;
      if (!g) continue;
      g.visible = true;
      g.position.set(it.pos[0] + D.x, it.pos[1] + D.y, it.pos[2] + D.z);
      g.rotation.set(it.rot[0] + rad(D.rotX), it.rot[1] + rad(D.rotY), it.rot[2] + rad(D.rotZ));
      if (s.live) {
        // The DOM screen follows the screen mesh, scaled from CSS px to cm.
        g.updateMatrixWorld(true);
        s.object.matrix.copy(s.dev.screen.matrixWorld).multiply(new THREE.Matrix4().makeScale(s.scale, s.scale, s.scale));
        s.object.visible = true;
      }
    }
    const c = r.cam;
    const camera = this.camera;
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
    this.lastCam = { pos: [...c.pos], target: [...c.target], fov };
    this.demos.ios.update(t);
    this.demos.android.update(t);
  }

  render() {
    this.shadows.update();
    this.renderer.render(this.scene, this.camera);
    this.cssScene.updateMatrixWorld(true);
    this.css.render(this.cssScene, this.camera);
  }

  // The current shot's camera, handed to the manual controls.
  takeOver() {
    if (!this.lastCam || this.state.shot === "manual") return;
    const [px, py, pz] = this.lastCam.pos, [tx, ty, tz] = this.lastCam.target;
    const dx = px - tx, dy = py - ty, dz = pz - tz;
    const d = Math.hypot(dx, dy, dz);
    const shot = SHOT_BY_ID[this.state.shot];
    this.state.camera = {
      azimuth: +deg(Math.atan2(dx, dz)).toFixed(1),
      elevation: +deg(Math.asin(dy / d)).toFixed(1),
      distance: +d.toFixed(1),
      fov: +this.lastCam.fov.toFixed(1),
      roll: 0,
      targetX: +tx.toFixed(2),
      targetY: +ty.toFixed(2),
    };
    this.state.layout = shot?.count || 1;
    this.state.shot = "manual";
  }

  // --- Size ------------------------------------------------------------------
  aspect() {
    const a = ASPECTS[this.state.output.aspect];
    return a || Math.max(this.container.clientWidth, 1) / Math.max(this.container.clientHeight, 1);
  }

  outputSize() {
    const a = this.aspect();
    const short = this.state.output.height;
    return a >= 1
      ? { width: Math.round((short * a) / 2) * 2, height: short }
      : { width: short, height: Math.round(short / a / 2) * 2 };
  }

  layout(force = false) {
    const a = this.aspect();
    const W = this.container.clientWidth, H = this.container.clientHeight;
    if (!W || !H) return;
    const w = Math.floor(Math.min(W, H * a)), h = Math.floor(w / a);
    const k = `${w}x${h}`;
    if (k === this.laidOut && !force) return;
    this.laidOut = k;
    this.stageEl.style.width = `${w}px`;
    this.stageEl.style.height = `${h}px`;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(w, h, false);
    this.css.setSize(w, h);
    this.camera.aspect = w / h;
  }

  // --- The clock -------------------------------------------------------------
  mediaTime(t) {
    const shot = SHOT_BY_ID[this.state.shot];
    return shot && !shot.loop ? Math.min(t, this.state.duration - 0.02) : t;
  }

  tick(now) {
    this.raf = requestAnimationFrame((t) => this.tick(t));
    const dt = Math.min((now - this.last) / 1000, 0.1);
    this.last = now;
    if (this.exporting) return;
    const state = this.state;
    if (state.playing) {
      state.time += dt * state.speed;
      const shot = SHOT_BY_ID[state.shot];
      if (shot && !shot.loop && state.time > state.duration + 1.2) state.time = 0;
      for (const s of this.slots) s.media?.update(this.mediaTime(state.time), state.speed);
    }
    this.apply(state.time);
    this.render();
    this.onFrame?.(state);
  }

  async seek(t) {
    this.state.time = t;
    await Promise.all(this.slots.map((s) => s.media?.seek(this.mediaTime(t))));
    this.apply(t);
    this.render();
  }

  setPlaying(on) {
    this.state.playing = on;
    for (const s of this.slots) {
      if (on) s.media?.resume();
      else s.media?.video?.pause();
    }
  }

  // --- Output: from the canvas, so only for screens that aren't live DOM ----
  liveScreensInView() {
    return this.frameAt(this.state.time).items.some((it) => this.slots[it.slot].live);
  }

  async renderAt(width, height, fn) {
    this.exporting = true;
    const wasPlaying = this.state.playing;
    this.setPlaying(false);
    this.renderer.setPixelRatio(1);
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    try {
      return await fn();
    } finally {
      this.layout(true);
      this.exporting = false;
      if (wasPlaying) this.setPlaying(true);
    }
  }

  async exportVideo({ onProgress } = {}) {
    if (this.liveScreensInView()) {
      throw new Error("Live screens are real web pages, which the canvas can't encode. Record this with HyperFrames or a screen recorder, or put a video or image on the screens.");
    }
    const { width, height } = this.outputSize();
    const fps = this.state.output.fps;
    const start = this.state.time;
    this.cancelled = false;
    const blob = await this.renderAt(width, height, () =>
      exportMp4({ canvas: this.canvas, width, height, fps, duration: this.state.duration, drawFrame: (t) => this.seek(t), onProgress, isCancelled: () => this.cancelled }),
    );
    this.state.time = start;
    if (blob) download(blob, `device-stage-${this.state.shot}-${width}x${height}-${fps}fps.mp4`);
    return blob;
  }

  cancelExport() {
    this.cancelled = true;
  }

  async snapshot({ transparent = false, save = true } = {}) {
    if (this.liveScreensInView()) {
      throw new Error("Live screens are real web pages, which the canvas can't capture. Take a screenshot of the page instead.");
    }
    const { width, height } = this.outputSize();
    const blob = await this.renderAt(width, height, async () => {
      await this.seek(this.state.time);
      if (transparent) {
        const bg = this.scene.background;
        this.scene.background = null;
        this.renderer.setClearColor(0x000000, 0);
        this.render();
        this.scene.background = bg;
      }
      return new Promise((ok) => this.canvas.toBlob(ok, "image/png"));
    });
    if (save) download(blob, `device-stage-${this.state.shot}-${width}x${height}${transparent ? "-alpha" : ""}.png`);
    return blob;
  }

  // --- Pointer ----------------------------------------------------------------
  buildLock() {
    const wrap = document.createElement("div");
    wrap.className = "ds-lock";
    wrap.setAttribute("role", "group");
    wrap.setAttribute("aria-label", "What the pointer controls");
    this.lockButtons = [["screen", "Use the app"], ["device", "Move the device"]].map(([mode, label]) => {
      const b = document.createElement("button");
      b.type = "button";
      b.dataset.mode = mode;
      b.textContent = label;
      b.title = mode === "screen" ? "Taps and scrolls go to the screen; the 3D view is locked (L)" : "Drag to orbit, scroll to zoom; the screen is locked (L)";
      b.addEventListener("click", () => this.setInteract(mode));
      wrap.append(b);
      return b;
    });
    return wrap;
  }

  bindPointer() {
    const el = this.stageEl;
    let drag = null;
    const active = (e) => this.state.interact === "device" && !e.target.closest?.(".ds-lock");
    el.addEventListener("pointerdown", (e) => {
      if (!active(e)) return;
      drag = { x: e.clientX, y: e.clientY };
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener("pointermove", (e) => {
      if (!drag) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (Math.abs(dx) + Math.abs(dy) < 2) return;
      drag = { x: e.clientX, y: e.clientY };
      this.takeOver();
      const c = this.state.camera;
      c.azimuth = +(c.azimuth - dx * 0.3).toFixed(1);
      c.elevation = +Math.min(Math.max(c.elevation + dy * 0.2, -60), 75).toFixed(1);
      this.emit();
    });
    el.addEventListener("pointerup", () => (drag = null));
    el.addEventListener(
      "wheel",
      (e) => {
        if (!active(e)) return;
        e.preventDefault();
        this.takeOver();
        const c = this.state.camera;
        c.distance = +Math.min(Math.max(c.distance * Math.exp(e.deltaY * 0.001), 8), 160).toFixed(1);
        this.emit();
      },
      { passive: false },
    );
  }

  destroy() {
    cancelAnimationFrame(this.raf);
    this.resizeObserver.disconnect();
    this.renderer.dispose();
    this.stageEl.remove();
    this.container.classList.remove("ds-root");
  }
}
