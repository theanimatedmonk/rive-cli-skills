const RIV_URL = "tarot-animation.riv";
const ARTBOARD = "DailyDivination";
const STATE_MACHINE = "Divination";
const PICKS = ["pick1", "pick2", "pick3", "pick4", "pick5"];
const REVEAL_DELAY_MS = 800;
// From `reveal` to the card landing face-up in the .riv: Charge (1.7s of
// comets and shaking) plus RevealBurst up to the landing (~1.05s). The
// result copy waits for it.
const REVEAL_ANIMATION_MS = 2800;
const HEADING_FADE_MS = 500;
const INTERPRETING_MS = 2000;
// Matches the .phone.is-leaving fade in style.css.
const LEAVE_FADE_MS = 600;
const ORIENTATION = "Upright";

const phoneEl = document.querySelector(".phone");
const canvas = document.getElementById("rive-canvas");
const titleEl = document.getElementById("title");
const subtitleEl = document.getElementById("subtitle");
const introEl = document.querySelector(".intro");
const resultEl = document.getElementById("result");
const resultCopyEl = document.getElementById("result-copy");
const interpretButton = document.getElementById("start-interpreting");
const readingEl = document.getElementById("reading");
const homeButton = document.getElementById("home");

let vmi = null;
let picked = false;
let persona = null;

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// `?card=5` forces a persona (index into TAROT_PERSONAS); otherwise random.
function choosePersona() {
  const forced = Number.parseInt(new URLSearchParams(location.search).get("card"), 10);
  if (forced >= 0 && forced < TAROT_PERSONAS.length) {
    return TAROT_PERSONAS[forced];
  }
  return TAROT_PERSONAS[Math.floor(Math.random() * TAROT_PERSONAS.length)];
}

// Decode the persona's image and bind it to the view model's `face`, which
// the card's 3D script copies onto its front.
async function setFace(card) {
  const faceProperty = vmi && vmi.image("face");
  if (!faceProperty) {
    console.warn("No `face` image property on the view model");
    return;
  }
  const response = await fetch(card.image);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const image = await rive.decodeImage(bytes);
  faceProperty.value = image;
  image.unref();
}

async function onPicked(name) {
  if (picked) {
    return;
  }
  picked = true;
  persona = choosePersona();
  titleEl.textContent = "Your reading is unfolding";
  subtitleEl.textContent = "Take a breath while the card reveals itself.";
  console.log(`fired: ${name} -> ${persona.name}`);

  // The face must be bound before the flip starts.
  await Promise.all([
    setFace(persona).catch((error) => console.error("Could not load card face", error)),
    wait(REVEAL_DELAY_MS),
  ]);
  const reveal = vmi && vmi.trigger("reveal");
  if (reveal) {
    reveal.trigger();
  }
}

async function onRevealed() {
  await wait(REVEAL_ANIMATION_MS);
  introEl.classList.add("is-fading");
  await wait(HEADING_FADE_MS);
  titleEl.textContent = persona.name;
  subtitleEl.textContent = `- ${ORIENTATION} -`;
  introEl.classList.add("is-revealed");
  introEl.classList.remove("is-fading");
  resultEl.classList.remove("is-hidden");
}

async function onStartInterpreting() {
  interpretButton.disabled = true;
  resultEl.classList.add("is-unfolding");
  resultCopyEl.textContent = "Your reading is unfolding..";
  // Fill the reading while the copy shows, so the card image is decoded
  // before the screen fades in.
  const cardReady = fillReading();
  await Promise.all([wait(INTERPRETING_MS), cardReady]);
  await showReading();
}

function fillReading() {
  const cardEl = document.getElementById("reading-card");
  cardEl.src = persona.image;
  cardEl.alt = persona.name;
  document.getElementById("reading-name").textContent = persona.name;
  document.getElementById("reading-orientation").textContent = `- ${ORIENTATION} -`;
  document.getElementById("reading-panel-title").textContent = ORIENTATION;
  document.getElementById("reading-description").textContent = persona.description;
  return cardEl.decode().catch(() => {});
}

// Crossfade from the Rive reveal to the plain HTML reading: the reading
// starts rising in halfway through the reveal fading out.
async function showReading() {
  phoneEl.classList.add("is-leaving");
  await wait(LEAVE_FADE_MS / 2);

  readingEl.classList.add("is-entering");
  readingEl.hidden = false;
  // Let the hidden state paint before transitioning in.
  requestAnimationFrame(() => {
    requestAnimationFrame(() => readingEl.classList.remove("is-entering"));
  });
  await wait(LEAVE_FADE_MS / 2);

  // The final screen is plain HTML; stop the animation behind it.
  riveInstance.stop();
  phoneEl.classList.add("is-reading");
}

const riveInstance = new rive.Rive({
  src: RIV_URL,
  canvas,
  artboard: ARTBOARD,
  stateMachine: STATE_MACHINE,
  autoplay: true,
  autoBind: true,
  enableGPUCanvas: true,
  useOffscreenRenderer: false,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    vmi = riveInstance.viewModelInstance;
    if (!vmi) {
      console.warn("No view model instance is bound to DailyDivination");
      return;
    }
    for (const name of PICKS) {
      const trigger = vmi.trigger(name);
      if (trigger) {
        trigger.on(() => onPicked(name));
      }
    }
    const reveal = vmi.trigger("reveal");
    if (reveal) {
      reveal.on(onRevealed);
    }
  },
  onLoadError: (error) => console.error("Failed to load tarot-animation.riv", error),
});

interpretButton.addEventListener("click", onStartInterpreting);
homeButton.addEventListener("click", () => location.reload());

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());
