const canvas = document.getElementById("rings");
const buttons = {
  summon: document.getElementById("summon"),
  unleash: document.getElementById("unleash"),
  recall: document.getElementById("recall"),
};

let vmi = null;
// Which state the rings are in, from the state machine's own state changes.
let phase = "intro";

// Animation name -> what the page allows.
const PHASES = {
  Intro: "intro",
  Orbit: "orbit",
  SummonIn: "summoning",
  SummonHold: "summoned",
  Unleash: "unleashing",
  Recall: "recalling",
};

function syncButtons() {
  buttons.summon.disabled = phase !== "orbit";
  buttons.unleash.disabled = phase !== "summoned";
  buttons.recall.disabled = phase !== "summoned";
}

function fire(name) {
  const trigger = vmi && vmi.trigger(name);
  if (trigger) {
    trigger.trigger();
  }
}

// Sets a colour property on the view model from a swatch.
function setColor(property, hex, group) {
  const value = parseInt(hex, 16);
  const r = (value >> 16) & 255;
  const g = (value >> 8) & 255;
  const b = value & 255;
  const color = vmi && vmi.color(property);
  if (color) {
    color.rgb(r, g, b);
  }
  if (property === "energyColor") {
    document.documentElement.style.setProperty("--energy-rgb", `${r}, ${g}, ${b}`);
  }
  group.querySelectorAll(".swatch").forEach((s) => s.setAttribute("aria-pressed", String(s.dataset.color === hex)));
  const custom = group.querySelector(".swatch--custom");
  if (custom) {
    custom.setAttribute("aria-pressed", String(custom.dataset.color === hex));
  }
}

const riveInstance = new rive.Rive({
  src: "ten-rings.riv",
  canvas,
  artboard: "TenRings",
  stateMachines: "Flow",
  autoplay: true,
  autoBind: true,
  enableGPUCanvas: true,
  // Fill the viewport; on narrow screens keep the whole stage in view.
  layout: new rive.Layout({
    fit: window.innerWidth / window.innerHeight < 1 ? rive.Fit.Contain : rive.Fit.Cover,
    alignment: rive.Alignment.Center,
  }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    vmi = riveInstance.viewModelInstance;
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

buttons.summon.addEventListener("click", () => fire("summon"));
buttons.unleash.addEventListener("click", () => fire("unleash"));
buttons.recall.addEventListener("click", () => fire("recall"));
document.querySelectorAll(".swatches").forEach((group) => {
  group.querySelectorAll("button.swatch").forEach((s) =>
    s.addEventListener("click", () => setColor(group.dataset.property, s.dataset.color, group)),
  );
  // Custom colour: updates live while dragging in the picker.
  const custom = group.querySelector(".swatch--custom");
  const picker = custom && custom.querySelector(".swatch__picker");
  if (picker) {
    picker.addEventListener("input", () => {
      const hex = picker.value.slice(1).toLowerCase();
      custom.dataset.color = hex;
      custom.style.setProperty("--c", picker.value);
      setColor(group.dataset.property, hex, group);
    });
  }
});

// Space: summon, then unleash. Esc: recall.
window.addEventListener("keydown", (event) => {
  if (event.code === "Space") {
    event.preventDefault();
    if (phase === "orbit") fire("summon");
    else if (phase === "summoned") fire("unleash");
  } else if (event.code === "Escape" && phase === "summoned") {
    fire("recall");
  }
});

window.addEventListener("resize", () => {
  riveInstance.layout = new rive.Layout({
    fit: window.innerWidth / window.innerHeight < 1 ? rive.Fit.Contain : rive.Fit.Cover,
    alignment: rive.Alignment.Center,
  });
  riveInstance.resizeDrawingSurfaceToCanvas();
});

syncButtons();
