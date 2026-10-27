// Vikram and Vetal: the story. The teaser is played by Rive (the Story
// artboard's state machine, one keyed timeline per chapter); this page
// shows each chapter's caption as it begins and lets the viewer jump to a
// chapter by firing the Story view model's triggers.
const SRC = "vikram-vetal.riv?v=16";

// The chapters, by their state's (timeline's) name in the state machine.
const CHAPTERS = {
  Peepal: {
    title: "I · The peepal",
    line: "Amavas. No moon. In the cremation ground the old peepal stands, and lights that are not fireflies circle it.",
  },
  Vikram: {
    title: "II · The king",
    line: "King Vikram walks the path alone, to the tree where the Vetal hangs.",
  },
  Astra: {
    title: "III · The astra",
    line: "He draws his bow — and the night itself bends to the string.",
  },
};

// The captions follow the state machine's chapters by its state changes.
rive.Rive.suppressDeprecationWarnings = ["state-change-events"];

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");
const chapterEl = document.getElementById("chapter");
const lineEl = document.getElementById("line");
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
      if (CHAPTERS[name]) {
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
  const chapter = CHAPTERS[name];
  chapterEl.textContent = chapter.title;
  lineEl.textContent = chapter.line;
  // Let the caption fade in again.
  for (const el of [chapterEl, lineEl]) {
    el.classList.remove("is-in");
    void el.offsetWidth;
    el.classList.add("is-in");
  }
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
  });
}

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());
