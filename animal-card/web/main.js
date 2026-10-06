// Animal card demo: the Rive card, plus an upload that replaces the front's
// image at runtime through the view model (AnimalCard > front > photo); the
// back shows the same photo as a Madhubani print.
const canvas = document.getElementById("card");
const statusEl = document.getElementById("status");

const riveInstance = new rive.Rive({
  src: "animal-card.riv",
  canvas,
  artboard: "AnimalCard",
  stateMachine: "Card",
  autoplay: true,
  autoBind: true,
  enableGPUCanvas: true,
  layout: new rive.Layout({ fit: rive.Fit.Contain, alignment: rive.Alignment.Center }),
  onLoad: () => riveInstance.resizeDrawingSurfaceToCanvas(),
  onLoadError: (error) => {
    statusEl.textContent = "Could not load the card.";
    console.error(error);
  },
});

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());

function frontImage() {
  const vmi = riveInstance.viewModelInstance;
  return vmi && vmi.viewModel("front") && vmi.viewModel("front").image("photo");
}

document.getElementById("upload").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) {
    return;
  }
  const property = frontImage();
  if (!property) {
    statusEl.textContent = "The card isn't ready yet; try again in a moment.";
    return;
  }
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const image = await rive.decodeImage(bytes);
    property.value = image;
    image.unref();
    statusEl.textContent = `Showing ${file.name}.`;
  } catch (error) {
    statusEl.textContent = "That image couldn't be read.";
    console.error(error);
  }
  event.target.value = "";
});


// The print's palette: a colour-harmony scheme and its base hue, on the
// view model next to the photo (AnimalCard > front > harmony / baseHue).
function frontNumber(name) {
  const vmi = riveInstance.viewModelInstance;
  return vmi && vmi.viewModel("front") && vmi.viewModel("front").number(name);
}

document.getElementById("harmony").addEventListener("change", (event) => {
  const harmony = frontNumber("harmony");
  if (harmony) {
    harmony.value = Number(event.target.value);
  }
});

const hueValue = document.getElementById("hue-value");
document.getElementById("base-hue").addEventListener("input", (event) => {
  hueValue.textContent = `${event.target.value}°`;
  const hue = frontNumber("baseHue");
  if (hue) {
    hue.value = Number(event.target.value);
  }
});

// The front's text: AnimalCard > front > birdName / scientificName.
function frontString(name) {
  const vmi = riveInstance.viewModelInstance;
  return vmi && vmi.viewModel("front") && vmi.viewModel("front").string(name);
}

for (const [inputId, property] of [["bird-name", "birdName"], ["scientific-name", "scientificName"]]) {
  document.getElementById(inputId).addEventListener("input", (event) => {
    const prop = frontString(property);
    if (prop) {
      prop.value = event.target.value;
    }
  });
}
