// The studio: the device stage with a control panel, for designing shots.
// The phones run the live tarot flow (../tarot-frontend-demo) by default.
//
// Scripts reach the same stage as the panel:
//   - the URL: ?state=<JSON> (any part of the state), ?ui=0 (the stage
//     alone), ?play=0 (hold the clock for a script)
//   - window.mockup: the DeviceStage (get, set, seek, play, pause, screen,
//     setScreen, setInteract, frameWindow, exportVideo, snapshot)
//   - postMessage from a parent page: { mockup: "set", state },
//     { mockup: "seek", time }, { mockup: "get" }
// See README.md.

import { DeviceStage, DEFAULTS, ASPECTS, merge } from "./stage.js";
import { DEVICES } from "./devices.js";
import { BACKDROPS } from "./studio.js";
import { buildUI } from "./ui.js";

// "tarot": the tarot demo, embedded and playing itself, with each
// platform's status bar.
const SCREENS = {
  tarot: (model, spec) => `../tarot-frontend-demo/?embed=1&auto=1&frame=${spec.cutout === "punch" ? "android" : "iphone"}`,
};

const STUDIO = merge(JSON.parse(JSON.stringify(DEFAULTS)), {
  shot: "tarot",
  duration: 22,
  slots: [
    { model: "iphone17pro", finish: "Cosmic Orange", screen: "tarot" },
    { model: "s25ultra", finish: "Titanium Silverblue", screen: "tarot" },
    { model: "iphoneAir", finish: "Sky Blue", screen: "tarot" },
  ],
  output: { aspect: "16:9" },
});

const params = new URLSearchParams(location.search);
const initial = JSON.parse(JSON.stringify(STUDIO));
try {
  if (params.get("state")) merge(initial, JSON.parse(params.get("state")));
} catch (e) {
  console.warn("mockup: ?state= is not valid JSON", e);
}
if (params.get("shot")) initial.shot = params.get("shot");
// A shot chosen without a length gets its own.
if (initial.shot !== STUDIO.shot && !params.get("state")?.includes('"duration"')) delete initial.duration;
if (params.has("t")) initial.time = Number(params.get("t")) || 0;
if (params.get("play") === "0") initial.playing = false;
const showUI = params.get("ui") !== "0";

const stage = new DeviceStage(document.getElementById("stage-wrap"), { state: initial, screens: SCREENS });
stage.ready = Promise.resolve(stage);

function toast(text) {
  const el = document.getElementById("toast");
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (el.hidden = true), 3200);
}
stage.toast = toast;
stage.stateUrl = () => {
  const u = new URL(location.href);
  u.search = "";
  u.searchParams.set("state", JSON.stringify(stage.get()));
  return u.toString();
};
stage.defaults = STUDIO;
window.mockup = stage;

// The tarot flow tells us when each run starts: the tarot shot starts with it.
window.addEventListener("message", async (e) => {
  const m = e.data;
  if (!m || typeof m !== "object") return;
  if (m.tarot === "start" && e.source === stage.frameWindow(0) && stage.state.shot === "tarot" && stage.state.playing) {
    stage.state.time = 0;
    return;
  }
  if (!m.mockup) return;
  const reply = (data) => e.source?.postMessage({ mockup: "reply", id: m.id, ...data }, "*");
  if (m.mockup === "set") reply({ state: stage.set(m.state) });
  else if (m.mockup === "seek") {
    await stage.seek(m.time);
    reply({ time: m.time });
  } else if (m.mockup === "get") reply({ state: stage.get() });
});

// Drop a screen recording or screenshot on the page: it goes on device 1.
window.addEventListener("dragover", (e) => e.preventDefault());
window.addEventListener("drop", (e) => {
  e.preventDefault();
  const file = [...(e.dataTransfer?.files || [])].find((f) => /^(video|image)\//.test(f.type));
  if (!file) return;
  stage.setScreen(0, file);
  toast(`${file.name} is on device 1`);
});

window.addEventListener("keydown", (e) => {
  if (e.target.closest("input, select, textarea")) return;
  if (e.code === "Space") {
    e.preventDefault();
    stage.set({ playing: !stage.state.playing });
  } else if (e.key === "h") ui?.togglePanel();
  else if (e.key === "l") stage.setInteract(stage.state.interact === "screen" ? "device" : "screen");
});

const ui = showUI ? buildUI(stage, stage.state, { DEVICES, BACKDROPS, ASPECTS, loadFile: (i, file) => stage.setScreen(i, file) }) : null;
if (!showUI) document.body.classList.add("bare");
if (ui) {
  stage.on((s) => ui.refresh(s));
  stage.onFrame = (s) => ui.tick(s);
  ui.refresh(stage.state);
}
if (window.parent !== window) window.parent.postMessage({ mockup: "ready" }, "*");
