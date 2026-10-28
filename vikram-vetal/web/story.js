// Vikram and Vetal: the story. The teaser is played by Rive (the Story
// artboard's state machine, one keyed timeline per chapter); this page lets
// the viewer jump to a chapter, from a folded menu, by firing the Story view
// model's triggers, and marks the chapter playing.
const SRC = "vikram-vetal.riv?v=50";

// The chapters, by their state's (timeline's) name in the state machine.
const CHAPTERS = ["Peepal", "Vikram", "Astra"];

// The menu follows the state machine's chapters by its state changes.
rive.Rive.suppressDeprecationWarnings = ["state-change-events"];

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");
const buttons = document.querySelectorAll(".chapter");

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Story",
  stateMachine: "Story",
  autoplay: true,
  autoBind: true,
  // The scene is drawn with WGSL shaders on GPU canvases.
  enableGPUCanvas: true,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    statusEl.hidden = true;
    show("Peepal");
  },
  onLoadError: (error) => {
    statusEl.textContent = "Could not load the story.";
    console.error(error);
  },
  onStateChange: (event) => {
    for (const name of event.data || []) {
      if (CHAPTERS.includes(name)) {
        show(name);
      }
    }
  },
});

let current = "";
function show(name) {
  if (name === current) {
    return;
  }
  current = name;
  for (const button of buttons) {
    button.classList.toggle("is-active", button.dataset.state === name);
  }
}

for (const button of buttons) {
  button.addEventListener("click", () => {
    const vm = riveInstance.viewModelInstance;
    const trigger = vm && vm.trigger(button.dataset.trigger);
    if (trigger) {
      trigger.trigger();
    }
    setMenu(false);
  });
}

// The menu: folded by default; opens upward from its button, closes on
// Escape or a click elsewhere.
const menu = document.getElementById("story-menu");
const menuPanel = document.getElementById("story-menu-panel");
const menuToggle = document.getElementById("story-menu-toggle");
function setMenu(open) {
  menuPanel.hidden = !open;
  menuToggle.setAttribute("aria-expanded", String(open));
  menu.classList.toggle("is-open", open);
}
menuToggle.addEventListener("click", () => setMenu(menuPanel.hidden));
document.addEventListener("click", (event) => {
  if (!menu.contains(event.target)) {
    setMenu(false);
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    setMenu(false);
  }
});

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());
