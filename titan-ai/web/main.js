// The Titan AI logo. It plays its reveal on load, then rests with nothing moving.
// Three triggers on the Logo view model: `replay` runs the reveal, `processing`
// loops the star working inside the tile, `idle` rests on the finished logo.

const canvas = document.getElementById("logo");

const logo = new rive.Rive({
  src: "logo.riv?v=7",
  canvas,
  artboard: "Logo",
  stateMachines: "Logo",
  autoplay: true,
  autoBind: true,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: fitCanvas,
  onLoadError: (error) => console.error(error),
});

function fire(name) {
  logo.viewModelInstance?.trigger(name)?.trigger();
}

const replay = () => fire("replay");

document.getElementById("replay").addEventListener("click", replay);
document.getElementById("idle").addEventListener("click", () => fire("idle"));
document.getElementById("processing").addEventListener("click", () => fire("processing"));
canvas.addEventListener("click", replay);

function fitCanvas() {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.round(rect.width * dpr);
  const h = Math.round(rect.height * dpr);
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  logo.resizeDrawingSurfaceToCanvas();
}

new ResizeObserver(fitCanvas).observe(canvas);
