// The Vetal preview: the spirit on his own, full-bleed, hanging from the
// branch, with his eyes and spirit light, the wind, the light and the 2D-3D
// style as controls. Each control sets a number on the Vetal view model,
// bound to the Vetal node's inputs.
const SRC = "vikram-vetal-spirit.riv?v=16";

// The file's defaults (the Vetal view model's Default instance).
const DEFAULTS = {
  autoTurn: 0,
  tilt: 4,
  speed: 1,
  moon: 0.45,
  fire: 0.6,
  mist: 1,
  fireflies: 40,
  paint: 0.75,
  bands: 3,
  outline: 2.2,
  inkDetail: 0.6,
  hatching: 0.5,
  eyeGlow: 1.5,
  spirit: 0,
  windStrength: 1,
  windSpeed: 1,
  windDirection: 160,
  gustiness: 0.6,
  hairWind: 1,
  clothWind: 1,
};

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");
const values = { ...DEFAULTS };

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Vetal",
  stateMachine: "Vetal",
  autoplay: true,
  autoBind: true,
  // He is drawn with WGSL shaders on GPU canvases.
  enableGPUCanvas: true,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    fitCanvas();
    statusEl.hidden = true;
    for (const [name, value] of Object.entries(values)) {
      setNumber(name, value);
    }
  },
  onLoadError: (error) => {
    statusEl.textContent = "Could not load the Vetal.";
    console.error(error);
  },
});

function setNumber(name, value) {
  const vm = riveInstance.viewModelInstance;
  const prop = vm && vm.number(name);
  if (prop) {
    prop.value = value;
  }
}

// The spirit light's colour.
document.getElementById("spirit-color").addEventListener("input", (event) => {
  const vm = riveInstance.viewModelInstance;
  const prop = vm && vm.color("spiritColor");
  if (prop) {
    const hex = event.target.value;
    prop.rgb(parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16));
  }
});

// Sliders, built from the data attributes in the markup.
const sliders = [];
for (const slot of document.querySelectorAll("[data-slider]")) {
  const name = slot.dataset.slider;
  const label = document.createElement("label");
  label.className = "slider";
  const text = document.createElement("span");
  text.textContent = slot.dataset.label;
  const out = document.createElement("output");
  const input = document.createElement("input");
  input.type = "range";
  input.min = slot.dataset.min;
  input.max = slot.dataset.max;
  input.step = slot.dataset.step;
  input.value = String(values[name]);
  out.textContent = input.value;
  input.addEventListener("input", () => {
    values[name] = Number(input.value);
    out.textContent = input.value;
    setNumber(name, values[name]);
  });
  label.append(text, out, input);
  slot.replaceWith(label);
  sliders.push({ name, input, out });
}

document.getElementById("reset").addEventListener("click", () => {
  for (const { name, input, out } of sliders) {
    values[name] = DEFAULTS[name];
    input.value = String(DEFAULTS[name]);
    out.textContent = input.value;
    setNumber(name, values[name]);
  }
});

// The file turns him on drag, zooms on pinch and resets on double-tap; here
// the mouse wheel and trackpad add zoom, and a two-finger swipe turns him.
let zoom = 1;
let resetCount = 0;
let dragX = 0;
let dragY = 0;
function zoomBy(factor) {
  zoom = Math.min(Math.max(zoom * factor, 0.35), 2.5);
  setNumber("zoom", zoom);
}
function isMouseWheel(event) {
  return event.deltaX === 0 && Number.isInteger(event.deltaY) && Math.abs(event.deltaY) >= 50;
}
canvas.addEventListener(
  "wheel",
  (event) => {
    event.preventDefault();
    if (event.ctrlKey) {
      zoomBy(Math.exp(event.deltaY * 0.01));
    } else if (isMouseWheel(event)) {
      zoomBy(Math.exp(event.deltaY * 0.0015));
    } else {
      dragX -= event.deltaX;
      dragY -= event.deltaY;
      setNumber("dragX", dragX);
      setNumber("dragY", dragY);
    }
  },
  { passive: false },
);
document.getElementById("reset-view").addEventListener("click", () => {
  zoom = 1;
  setNumber("zoom", zoom);
  setNumber("resetView", ++resetCount);
});

const panel = document.getElementById("panel");
const toggle = document.getElementById("toggle");
toggle.addEventListener("click", () => {
  const open = panel.classList.toggle("is-collapsed") === false;
  toggle.setAttribute("aria-expanded", String(open));
  toggle.textContent = open ? "Hide controls" : "Show controls";
});

// Keep the drawing surface at the canvas's on-screen size.
function fitCanvas() {
  riveInstance.resizeDrawingSurfaceToCanvas();
}
window.addEventListener("resize", fitCanvas);
