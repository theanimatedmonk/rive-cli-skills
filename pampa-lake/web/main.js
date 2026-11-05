// Pampa Sarovar preview: the lake scene full-bleed, with sliders for the
// camera (position, axes, lens), the sun, the meadow, the wind, the water,
// the air and the pollen. Each slider sets a number on the Scene view model, which is
// bound to the Lake node's inputs.
const SRC = "pampa_lake.riv?v=16";

// The file's defaults (the Scene view model's Default instance); the camera
// is the GLB's Cam_Hero.
const DEFAULTS = {
  cameraX: -6.6,
  cameraY: 4.1,
  cameraZ: -36.7,
  rotationX: 4.05,
  rotationY: -3.06,
  rotationZ: 0,
  fov: 42.55,
  drift: 1,
  tour: 1,
  tourSpeed: 1,
  focusDistance: 11,
  depthOfField: 0.26,
  exposure: 0.54,
  paint: 0.59,
  brush: 12,
  edges: 0,
  paper: 1.7,
  sunAzimuth: -81,
  sunElevation: 8,
  sunIntensity: 0.4,
  shading: 0.36,
  windStrength: 0.05,
  windSpeed: 0,
  windDirection: 200,
  reflection: 1,
  ripples: 2.45,
  mist: 0.35,
  wisps: 14,
  wispOpacity: 0.23,
  haze: 0,
  clouds: 0,
  pollenAmount: 1600,
  greens: 0.42,
  plants: 1,
};

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");
const values = { ...DEFAULTS };

// The sliders are remembered in this browser between visits.
const STORE = "pampa-lake-settings";
try {
  const saved = JSON.parse(localStorage.getItem(STORE) || "{}");
  for (const name of Object.keys(DEFAULTS)) {
    if (typeof saved[name] === "number") {
      values[name] = saved[name];
    }
  }
} catch (error) {
  // No storage here (a private window): start from the defaults.
}
function remember() {
  try {
    localStorage.setItem(STORE, JSON.stringify(values));
  } catch (error) {
    // Not remembered; the sliders still work.
  }
}

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Pampa Sarovar",
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
    statusEl.textContent = "Could not load the lake.";
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
    remember();
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
  try {
    localStorage.removeItem(STORE);
  } catch (error) {
    // Nothing stored.
  }
  values.tour = DEFAULTS.tour;
  setNumber("tour", values.tour);
  showTour();
  resetView();
});

// The camera move: play or pause (the camera sliders take over).
const tourButton = document.getElementById("tour");
function showTour() {
  const on = values.tour > 0.5;
  tourButton.textContent = on ? "Pause the camera move" : "Play the camera move";
  tourButton.setAttribute("aria-pressed", String(on));
}
tourButton.addEventListener("click", () => {
  values.tour = values.tour > 0.5 ? 0 : 1;
  setNumber("tour", values.tour);
  showTour();
  remember();
});
showTour();

// Copy the sliders' values, as JSON, to paste anywhere. Where the page
// can't reach the clipboard (opened as a file, or permission denied), the
// JSON is shown selected instead, for Cmd+C.
const copyButton = document.getElementById("copy");
const settingsBox = document.getElementById("settings");
copyButton.addEventListener("click", async () => {
  const text = JSON.stringify(values, null, 2);
  try {
    await navigator.clipboard.writeText(text);
    settingsBox.hidden = true;
    copyButton.textContent = "Copied";
    setTimeout(() => (copyButton.textContent = "Copy settings"), 1500);
  } catch (error) {
    settingsBox.value = text;
    settingsBox.hidden = false;
    settingsBox.focus();
    settingsBox.select();
    copyButton.textContent = "Select and copy";
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
  zoom = Math.min(Math.max(zoom * factor, 0.1), 4);
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
function resetView() {
  zoom = 1;
  setNumber("zoom", zoom);
  setNumber("resetView", ++resetCount);
}
document.getElementById("reset-view").addEventListener("click", resetView);

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
