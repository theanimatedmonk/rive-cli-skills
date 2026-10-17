// Pinaka preview: a side panel with a tab per artboard.
//   The Bow  (artboard Pinaka, state machine Scene): Pull String / Test Fire,
//            aura and power sliders.
//   Astra    (artboard Astra, state machine Astra): four pulls, then Fire;
//            the blast follows on its own (an event in the file fires it).
const SRC = "pinaka-bow.riv?v=19";

const SCENES = {
  bow: { artboard: "Pinaka", stateMachine: "Scene", width: 1280, height: 1280 },
  astra: { artboard: "Astra", stateMachine: "Astra", width: 1280, height: 720 },
};

const stage = document.getElementById("stage");
const statusEl = document.getElementById("status");
let canvas = document.getElementById("scene");
let riveInstance = null;

function load(name) {
  const scene = SCENES[name];
  if (riveInstance) {
    riveInstance.cleanup();
    riveInstance = null;
  }
  // A fresh canvas per scene: the GPU canvas the bow renders into is tied
  // to the canvas it was created on.
  const fresh = canvas.cloneNode(false);
  fresh.width = scene.width;
  fresh.height = scene.height;
  canvas.replaceWith(fresh);
  canvas = fresh;
  stage.dataset.scene = name;
  statusEl.textContent = "Loading…";
  statusEl.hidden = false;

  const instance = new rive.Rive({
    src: SRC,
    canvas,
    artboard: scene.artboard,
    stateMachines: scene.stateMachine,
    autoplay: true,
    autoBind: true,
    // The bow is rendered with a WGSL shader on a GPU canvas.
    enableGPUCanvas: true,
    layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
    onLoad: () => {
      instance.resizeDrawingSurfaceToCanvas();
      statusEl.hidden = true;
      if (name === "bow") {
        // Re-apply the sliders to the fresh view model.
        for (const id of ["aura", "power"]) {
          setNumber(id, Number(document.getElementById(id).value));
        }
      }
    },
    onLoadError: (error) => {
      statusEl.textContent = "Could not load the scene.";
      console.error(error);
    },
  });
  riveInstance = instance;
}

function setNumber(name, value) {
  const prop = riveInstance && riveInstance.viewModelInstance && riveInstance.viewModelInstance.number(name);
  if (prop) {
    prop.value = value;
  }
}

function fire(name) {
  const trigger = riveInstance && riveInstance.viewModelInstance && riveInstance.viewModelInstance.trigger(name);
  if (trigger) {
    trigger.trigger();
  }
}

// Tabs. The URL hash (#bow, #astra) picks the opening tab.
const tabs = document.querySelectorAll(".tab");
function select(name) {
  for (const tab of tabs) {
    const on = tab.dataset.scene === name;
    tab.setAttribute("aria-selected", String(on));
    document.getElementById(tab.getAttribute("aria-controls")).hidden = !on;
  }
  history.replaceState(null, "", `#${name}`);
  load(name);
}
for (const tab of tabs) {
  tab.addEventListener("click", () => {
    if (stage.dataset.scene !== tab.dataset.scene || !riveInstance) {
      select(tab.dataset.scene);
    }
  });
}

// Trigger buttons, in both panels.
for (const button of document.querySelectorAll("[data-trigger]")) {
  button.addEventListener("click", () => fire(button.dataset.trigger));
}

// The bow's sliders.
for (const name of ["aura", "power"]) {
  const input = document.getElementById(name);
  const out = document.getElementById(`${name}-out`);
  input.addEventListener("input", () => {
    out.textContent = input.value;
    setNumber(name, Number(input.value));
  });
}

window.addEventListener("resize", () => riveInstance && riveInstance.resizeDrawingSurfaceToCanvas());

select(SCENES[location.hash.slice(1)] ? location.hash.slice(1) : "bow");
