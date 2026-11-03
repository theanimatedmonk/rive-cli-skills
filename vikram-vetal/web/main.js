// Vikram and Vetal preview: the night scene full-bleed, with sliders for the
// camera (position and axes), the wind and the air. Each slider sets a
// number on the Scene view model, which is bound to the Ruins node's inputs.
const SRC = "vikram-vetal.riv?v=54";

// The file's defaults (the Scene view model's Default instance).
const DEFAULTS = {
  cameraX: -7.33,
  cameraY: 1.69,
  cameraZ: 8.92,
  rotationX: 9.5,
  rotationY: -33.5,
  rotationZ: 0,
  fov: 56,
  windStrength: 1,
  windSpeed: 1,
  windDirection: 30,
  haze: 2.2,
  fireflies: 750,
  focusDistance: 14,
  ghostLights: 8,
  moon: 0.3,
};

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");
const values = { ...DEFAULTS };

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Night",
  stateMachine: "Scene",
  autoplay: true,
  autoBind: true,
  // The scene is drawn with WGSL shaders on GPU canvases.
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
    statusEl.textContent = "Could not load the scene.";
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

// Viewport navigation, as in Blender: the file orbits on drag, pans with two
// fingers, zooms on pinch and resets on double-tap. Here the mouse and
// trackpad add the rest, also as in Blender:
//   trackpad two-finger drag   orbit (tilt and turn); with Shift, pan
//   trackpad pinch             zoom (the browser sends it as Ctrl+wheel)
//   mouse wheel                zoom
//   Shift+drag / Ctrl+drag     pan / zoom
let zoom = 1;
let resetCount = 0;
let dragX = 0;
let dragY = 0;
function zoomBy(factor) {
  zoom = Math.min(Math.max(zoom * factor, 0.15), 4);
  setNumber("zoom", zoom);
}
// A mouse wheel moves in whole notches with no sideways part; a trackpad
// scrolls in small, fractional, two-axis steps.
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
      // The scene follows the fingers, like dragging it.
      syncMode(event);
      dragX -= event.deltaX;
      dragY -= event.deltaY;
      setNumber("dragX", dragX);
      setNumber("dragY", dragY);
    }
  },
  { passive: false },
);
function syncMode(event) {
  setNumber("navMode", event.shiftKey ? 1 : (event.ctrlKey || event.metaKey) && event.type !== "wheel" ? 2 : 0);
}
window.addEventListener("keydown", syncMode);
window.addEventListener("keyup", syncMode);
canvas.addEventListener("pointerdown", syncMode);
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
