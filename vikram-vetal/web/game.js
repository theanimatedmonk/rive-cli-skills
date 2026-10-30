// Vikram and Vetal: the game. The Game artboard (World.luau in play mode)
// walks King Vikram along the path to the peepal; this page hands it the
// keys, holding each Game view model number at 1 while its key is down, and
// the touchpad's looking round. The file draws the target circle and looses
// the arrows.
// (The file's own keyboard listeners write the same numbers wherever the
// runtime passes it the keys.)
const SRC = "vikram-vetal.riv?v=75";

// The keys, by KeyboardEvent.code: the arrows walk him, the keypad (or the
// number row's 8 4 6 2, or W A S D) turns and tilts the camera, and Space,
// held, draws an arrow and looses it when let go (a click on the scene is the
// astra, in the file).
const KEYS = {
  ArrowUp: "keyUp",
  ArrowDown: "keyDown",
  ArrowLeft: "keyLeft",
  ArrowRight: "keyRight",
  Numpad8: "lookUp",
  Numpad2: "lookDown",
  Numpad4: "lookLeft",
  Numpad6: "lookRight",
  Digit8: "lookUp",
  Digit2: "lookDown",
  Digit4: "lookLeft",
  Digit6: "lookRight",
  KeyW: "lookUp",
  KeyS: "lookDown",
  KeyA: "lookLeft",
  KeyD: "lookRight",
  Space: "fire",
};

const canvas = document.getElementById("scene");
const statusEl = document.getElementById("status");

const riveInstance = new rive.Rive({
  src: SRC,
  canvas,
  artboard: "Game",
  stateMachine: "Game",
  autoplay: true,
  autoBind: true,
  // The scene is drawn with WGSL shaders on GPU canvases.
  enableGPUCanvas: true,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    statusEl.hidden = true;
    canvas.focus();
  },
  onLoadError: (error) => {
    statusEl.textContent = "Could not load the game.";
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

// What is held now: each key (by code) or turn button, and the number it
// holds at 1. Two can hold the same number (a look key and its twin, a key
// and a button); it stays 1 while either is held.
const held = new Map();

function hold(source, name, down) {
  if (down) {
    held.set(source, name);
  } else {
    held.delete(source);
  }
  setNumber(name, [...held.values()].includes(name) ? 1 : 0);
}

function update(event) {
  const name = KEYS[event.code];
  if (!name || event.metaKey || event.ctrlKey || event.altKey) {
    return;
  }
  event.preventDefault();
  hold(event.code, name, event.type === "keydown");
}

window.addEventListener("keydown", update);
window.addEventListener("keyup", update);
// Away from the page, everything is let go.
window.addEventListener("blur", () => {
  for (const [source, name] of [...held]) {
    hold(source, name, false);
  }
});

// The panel's turn buttons: held down, the view turns.
for (const button of document.querySelectorAll("[data-look]")) {
  const name = button.dataset.look;
  const source = "button:" + name;
  button.addEventListener("pointerdown", (event) => {
    button.setPointerCapture(event.pointerId);
    hold(source, name, true);
  });
  for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) {
    button.addEventListener(type, () => hold(source, name, false));
  }
}

// The panel folds into its button (open to start with, so the keys are seen).
const menu = document.getElementById("game-menu");
const menuPanel = document.getElementById("game-menu-panel");
const menuToggle = document.getElementById("game-menu-toggle");
menuToggle.addEventListener("click", () => {
  const open = menuPanel.hidden;
  menuPanel.hidden = !open;
  menuToggle.setAttribute("aria-expanded", String(open));
  menu.classList.toggle("is-open", open);
});

// Looking with the touchpad: a two-finger swipe moves the Game view model's
// running totals, dragX / dragY, by the pixels the fingers travel.
let lookX = 0;
let lookY = 0;
function look(dx, dy) {
  lookX += dx;
  lookY += dy;
  setNumber("dragX", lookX);
  setNumber("dragY", lookY);
}

// The view follows the fingers: right turns right, up looks up (the
// scroll's deltas run the other way, with natural scrolling).
canvas.addEventListener(
  "wheel",
  (event) => {
    event.preventDefault();
    const scale = event.deltaMode === 1 ? 16 : 1;
    look(-event.deltaX * scale, -event.deltaY * scale);
  },
  { passive: false },
);

function fitCanvas() {
  riveInstance.resizeDrawingSurfaceToCanvas();
}
window.addEventListener("resize", fitCanvas);
