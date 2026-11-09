// Blob: one number drives it. `state` on the Blob view model:
//   0 idle, 1 thinking, 2 retrieving, 3 executing, 4 planning, 5 done.

const SRC = "blob.riv?v=13";

const STATES = [
  { name: "Idle", caption: "Hi! Ask me anything." },
  { name: "Thinking", caption: "Thinking…" },
  { name: "Retrieving", caption: "Looking through your sources…" },
  { name: "Executing", caption: "Running it…" },
  { name: "Planning", caption: "Working out a plan…" },
  { name: "Done", caption: "All done!" },
];

// A full run of an answer being generated: state, and how long it holds.
const RUN = [
  { state: 1, hold: 2600 },
  { state: 4, hold: 3600 },
  { state: 2, hold: 3800 },
  { state: 3, hold: 3800 },
  { state: 5, hold: 3600 },
  { state: 0, hold: 2400 },
];

const canvas = document.getElementById("blob");
const statusEl = document.getElementById("status");
const captionEl = document.getElementById("caption");
const playBtn = document.getElementById("play");
const playLabel = document.getElementById("play-label");
const stepsEl = document.getElementById("steps");
const buttons = [...document.querySelectorAll("[data-state]")];

let current = 0;
let ready = false;

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Blob",
  stateMachine: "Blob",
  autoplay: true,
  autoBind: true,
  // The jelly is drawn with WGSL shaders on GPU canvases.
  enableGPUCanvas: true,
  layout: new rive.Layout({ fit: rive.Fit.Contain, alignment: rive.Alignment.Center }),
  onLoad: () => {
    ready = true;
    fitCanvas();
    statusEl.hidden = true;
    setState(current);
  },
  onLoadError: (error) => {
    statusEl.textContent = "Blob couldn't load here. It needs WebGL 2.";
    console.error(error);
  },
});

function setState(n, { fromRun = false } = {}) {
  current = n;
  if (!fromRun) stopRun();
  const vm = ready && riveInstance.viewModelInstance;
  const prop = vm && vm.number("state");
  if (prop) prop.value = n;
  for (const b of buttons) {
    b.setAttribute("aria-pressed", String(Number(b.dataset.state) === n));
  }
  captionEl.textContent = STATES[n].caption;
  captionEl.classList.remove("caption--in");
  void captionEl.offsetWidth; // restart the fade
  captionEl.classList.add("caption--in");
}

for (const b of buttons) {
  b.addEventListener("click", () => setState(Number(b.dataset.state)));
}

window.addEventListener("keydown", (e) => {
  if (e.target.closest("input, textarea")) return;
  const n = Number(e.key) - 1;
  if (n >= 0 && n < STATES.length) setState(n);
  else if (e.key === " " && e.target === document.body) {
    e.preventDefault();
    toggleRun();
  }
});

// --- The full run ------------------------------------------------------------

for (const step of RUN) {
  const li = document.createElement("li");
  li.textContent = STATES[step.state].name;
  stepsEl.append(li);
}
const stepEls = [...stepsEl.children];

let runTimer = 0;
let runIndex = -1;

function showStep(i) {
  stepEls.forEach((el, j) => {
    el.classList.toggle("is-current", j === i);
    el.classList.toggle("is-done", i >= 0 && j < i);
  });
}

function runStep() {
  runIndex = (runIndex + 1) % RUN.length;
  const step = RUN[runIndex];
  setState(step.state, { fromRun: true });
  showStep(runIndex);
  runTimer = setTimeout(runStep, step.hold);
}

function startRun() {
  playBtn.setAttribute("aria-pressed", "true");
  playLabel.textContent = "Stop the run";
  runIndex = -1;
  runStep();
}

function stopRun() {
  if (playBtn.getAttribute("aria-pressed") !== "true") return;
  clearTimeout(runTimer);
  playBtn.setAttribute("aria-pressed", "false");
  playLabel.textContent = "Play a full run";
  showStep(-1);
}

function toggleRun() {
  if (playBtn.getAttribute("aria-pressed") === "true") stopRun();
  else startRun();
}

playBtn.addEventListener("click", toggleRun);

// --- Sizing: sharp on every screen -------------------------------------------

function fitCanvas() {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.round(rect.width * dpr);
  const h = Math.round(rect.height * dpr);
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  if (ready) riveInstance.resizeDrawingSurfaceToCanvas();
}

new ResizeObserver(fitCanvas).observe(canvas);
