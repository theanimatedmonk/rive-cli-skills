// Aleya Lights preview: the River artboard, with sliders for the Mangroves
// node's inputs (speed, fog, mist).
const statusEl = document.getElementById("status");

const riveInstance = new rive.Rive({
  src: "ayela-lights.riv",
  canvas: document.getElementById("scene"),
  artboard: "River",
  stateMachine: "Scene",
  autoplay: true,
  autoBind: true,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    statusEl.hidden = true;
  },
  onLoadError: (error) => {
    statusEl.textContent = "Could not load the scene.";
    console.error(error);
  },
});

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());

// Sliders drive the River view model, which is bound to the Mangroves
// node's inputs.
for (const name of ["speed", "fog", "mist"]) {
  const input = document.getElementById(name);
  const out = document.getElementById(`${name}-out`);
  input.addEventListener("input", () => {
    out.textContent = input.value;
    const prop = riveInstance.viewModelInstance && riveInstance.viewModelInstance.number(name);
    if (prop) {
      prop.value = Number(input.value);
    }
  });
}
