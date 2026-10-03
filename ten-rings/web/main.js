// Wielders: each sets the colour of the runes (carved imprints and aura)
// and of the energy (waves, mist, burst).
import { startVisionGestures } from "./gestures.js";

const WIELDERS = [
  { id: "shangchi", name: "Shang-Chi", runes: "ff7a2e", energy: "ff8a2e" },
  { id: "wenwu", name: "Wenwu", runes: "a45bff", energy: "8f4dff" },
];

const canvas = document.getElementById("rings");
const buttons = {
  summon: document.getElementById("summon"),
  unleash: document.getElementById("unleash"),
  recall: document.getElementById("recall"),
};
const toggle = document.getElementById("wielders");

let vmi = null;
let wielder = WIELDERS[0];
// Which state the rings are in, from the state machine's own state changes.
let phase = "rest";

// Animation name -> what the page allows.
const PHASES = {
  Rest: "rest",
  Awaken: "awakening",
  Orbit: "orbit",
  SummonIn: "summoning",
  SummonHold: "summoned",
  Unleash: "unleashing",
  Recall: "recalling",
};

function syncButtons() {
  // Before the rings are awakened, the first button awakens them.
  buttons.summon.textContent = phase === "rest" || phase === "awakening" ? "Awaken" : "Summon";
  buttons.summon.disabled = phase !== "orbit" && phase !== "rest";
  buttons.unleash.disabled = phase !== "summoned";
  buttons.recall.disabled = phase !== "summoned";
}

function fire(name) {
  const trigger = vmi && vmi.trigger(name);
  if (trigger) {
    trigger.trigger();
  }
}

function rgbOf(hex) {
  const v = parseInt(hex, 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

function setVmColor(property, hex) {
  const color = vmi && vmi.color(property);
  if (color) {
    color.rgb(...rgbOf(hex));
  }
}

function applyWielder(next) {
  wielder = next;
  setVmColor("imprintColor", next.runes);
  setVmColor("energyColor", next.energy);
  document.documentElement.style.setProperty("--accent", rgbOf(next.runes).join(", "));
  toggle.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.id === next.id)));
}

for (const w of WIELDERS) {
  const b = document.createElement("button");
  b.type = "button";
  b.dataset.id = w.id;
  b.textContent = w.name;
  b.addEventListener("click", () => applyWielder(w));
  toggle.appendChild(b);
}

function layoutFor() {
  return new rive.Layout({
    fit: window.innerWidth / window.innerHeight < 1 ? rive.Fit.Contain : rive.Fit.Cover,
    alignment: rive.Alignment.Center,
  });
}

const riveInstance = new rive.Rive({
  src: "ten-rings.riv",
  canvas,
  artboard: "TenRings",
  stateMachines: "Flow",
  autoplay: true,
  autoBind: true,
  enableGPUCanvas: true,
  layout: layoutFor(),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    vmi = riveInstance.viewModelInstance;
    applyWielder(wielder);
  },
  onStateChange: (event) => {
    for (const name of event.data || []) {
      if (PHASES[name]) {
        phase = PHASES[name];
        syncButtons();
      }
    }
  },
  onLoadError: (error) => console.error("Failed to load ten-rings.riv", error),
});

buttons.summon.addEventListener("click", () => fire(phase === "rest" ? "awaken" : "summon"));
buttons.unleash.addEventListener("click", () => fire("unleash"));
buttons.recall.addEventListener("click", () => fire("recall"));

// Space: awaken, summon, then unleash. Esc: recall.
window.addEventListener("keydown", (event) => {
  if (event.code === "Space") {
    event.preventDefault();
    if (phase === "rest") fire("awaken");
    else if (phase === "orbit") fire("summon");
    else if (phase === "summoned") fire("unleash");
  } else if (event.code === "Escape" && phase === "summoned") {
    fire("recall");
  }
});

window.addEventListener("resize", () => {
  riveInstance.layout = layoutFor();
  riveInstance.resizeDrawingSurfaceToCanvas();
});

applyWielder(wielder);
syncButtons();

// Hand follow: the rings' Orbit chain follows the tracked palm instead of
// the cursor. The camera point (0..1 of the viewport, mirrored) is mapped
// into the artboard through the same fit the canvas uses.
const ARTBOARD = { width: 1280, height: 720 };

function setFollow(point) {
  if (!vmi) return;
  const active = vmi.boolean("followActive");
  if (!point) {
    if (active) active.value = false;
    return;
  }
  const W = window.innerWidth;
  const H = window.innerHeight;
  const cover = W / H >= 1;
  const scale = cover
    ? Math.max(W / ARTBOARD.width, H / ARTBOARD.height)
    : Math.min(W / ARTBOARD.width, H / ARTBOARD.height);
  const w = ARTBOARD.width * scale;
  const h = ARTBOARD.height * scale;
  const fx = vmi.number("followX");
  const fy = vmi.number("followY");
  if (fx) fx.value = (point.x * W - (W - w) / 2) / w;
  if (fy) fy.value = (point.y * H - (H - h) / 2) / h;
  if (active) active.value = true;
}

startVisionGestures({
  getPhase: () => phase,
  fire,
  onHand: setFollow,
});

// Exposed for testing from the console: tenRings.follow({ x: 0.3, y: 0.4 }).
window.tenRings = { follow: setFollow };
