const RIV_URL = "tarot-animation.riv?v=2";
const PICKS = ["pick1", "pick2", "pick3", "pick4", "pick5"];
const ARTBOARD = "DailyDivination";
const STATE_MACHINE = "Divination";
const REVEAL_DELAY_MS = 800;
// From `reveal` to the card landing face-up in the .riv: Charge (1.7s of
// comets and shaking) plus RevealBurst up to the landing (~1.05s), both
// played at 0.75x speed in the editor. The result copy waits for it.
const REVEAL_ANIMATION_MS = 3700;
const HEADING_FADE_MS = 500;
const INTERPRETING_MS = 2000;
// Matches the .phone.is-leaving fade in style.css.
const LEAVE_FADE_MS = 600;
const ORIENTATION = "Upright";
// The blend on the .riv's Layout -> FanIdle transition (200ms) plus a
// margin. The state machine reports FanIdle when that blend starts.
const FAN_BLEND_MS = 250;

const phoneEl = document.querySelector(".phone");
const canvas = document.getElementById("rive-canvas");
const titleEl = document.getElementById("title");
const subtitleEl = document.getElementById("subtitle");
const introEl = document.querySelector(".intro");
const resultEl = document.getElementById("result");
const resultCopyEl = document.getElementById("result-copy");
const interpretButton = document.getElementById("start-interpreting");
const readingEl = document.getElementById("reading");

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
  resultCopyEl.textContent = "Your reading is taking shape...";
  // Fill the reading while the copy shows, so the card image is decoded
  // before the screen fades in.
  const cardReady = fillReading();
  await Promise.all([wait(INTERPRETING_MS), cardReady]);
  await showReading();
}

const TOPICS = {
  love: { title: "Love", color: "var(--love)" },
  career: { title: "Career", color: "var(--career)" },
  finance: { title: "Money", color: "var(--finance)" },
};
// Reading order: the cards left to right, the paragraphs top to bottom.
const TOPIC_ORDER = ["love", "career", "finance"];
const ROMAN = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
  "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI"];

const toastEl = document.getElementById("reading-toast");
let toastTimer = 0;

function showShareToast() {
  toastEl.textContent = "Share sheet opens here";
  toastEl.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toastEl.hidden = true;
  }, 1800);
}

// The reading box: a fixed heading over the scrolling paragraphs. As a
// topic's paragraph scrolls into the box, the heading switches to it and its
// card lights up; cards already passed stay lit, and scrolling back reverses
// it all.
const scrollEl = document.getElementById("reading-scroll");
const headingEl = document.getElementById("reading-heading");
const headingTextEl = document.getElementById("reading-heading-text");
const headingIcons = headingEl.querySelectorAll(".reading__icon");
const sectionEls = [...scrollEl.querySelectorAll(".reading__section")];
const cardEls = [...document.querySelectorAll(".topic-card")];
// A topic becomes current once its paragraph's top passes this far down the
// box, i.e. as it is about to take over the visible text.
const SWITCH_AT = 0.6;
let activeIndex = -1;

function setActiveTopic(index, animate = true) {
  if (index === activeIndex) {
    return;
  }
  activeIndex = index;
  const topic = TOPIC_ORDER[index];
  headingTextEl.textContent = TOPICS[topic].title;
  headingEl.style.setProperty("--c", TOPICS[topic].color);
  // SVG elements have no `hidden` property; toggle the attribute.
  headingIcons.forEach((icon) => icon.toggleAttribute("hidden", icon.dataset.topic !== topic));
  cardEls.forEach((card) => {
    const i = TOPIC_ORDER.indexOf(card.dataset.topic);
    card.classList.toggle("is-lit", i <= index);
    card.classList.toggle("is-active", i === index);
    card.setAttribute("aria-current", String(i === index));
  });
  if (animate) {
    headingEl.classList.remove("is-switching");
    void headingEl.offsetWidth; // restart the fade
    headingEl.classList.add("is-switching");
  }
}

function syncReading() {
  const top = scrollEl.scrollTop;
  const height = scrollEl.clientHeight;
  let index = 0;
  sectionEls.forEach((section, i) => {
    if (section.offsetTop - top <= height * SWITCH_AT) {
      index = i;
    }
  });
  // At the very bottom the last topic is current, however short it is.
  if (top + height >= scrollEl.scrollHeight - 2) {
    index = sectionEls.length - 1;
  }
  setActiveTopic(index);
}

scrollEl.addEventListener("scroll", syncReading, { passive: true });

// Tapping a card scrolls to its paragraph.
cardEls.forEach((card) => {
  card.addEventListener("click", () => {
    // Land on the paragraph itself, past the ✦ divider that opens each
    // section, so its first line sits right under the heading.
    const paragraph = sectionEls[TOPIC_ORDER.indexOf(card.dataset.topic)].querySelector("p");
    const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    scrollEl.scrollTo({ top: paragraph.offsetTop - 4, behavior: smooth ? "smooth" : "auto" });
  });
});

function fillReading() {
  const cardEl = document.getElementById("reading-card");
  cardEl.src = persona.image;
  cardEl.alt = persona.name;
  const number = ROMAN[TAROT_PERSONAS.indexOf(persona)];
  document.getElementById("reading-eyebrow").textContent = `Today's card · ${number}`;
  document.getElementById("reading-name").textContent = persona.name;
  for (const topic of TOPIC_ORDER) {
    document.getElementById(`reading-${topic}`).textContent = persona[topic];
  }
  scrollEl.scrollTop = 0;
  activeIndex = -1;
  setActiveTopic(0, false);
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

let riveLoaded = false;
// "fresh": the home screen opens the card picker. "drawn": today's card is
// drawn, so the home screen's promo opens the reading again. Nothing is
// stored, so a refresh starts fresh.
let homeMode = "fresh";
const homeEl = document.getElementById("home-screen");
const HOME_FADE_MS = 400;

function hideHome() {
  homeEl.classList.add("is-leaving");
  setTimeout(() => {
    homeEl.hidden = true;
  }, HOME_FADE_MS);
}

homeEl.addEventListener("click", () => {
  if (homeEl.classList.contains("is-leaving")) {
    return;
  }
  if (homeMode === "fresh") {
    // Home -> card picker: start the deal-out.
    homeMode = "picking";
    if (riveLoaded) {
      riveInstance.play(STATE_MACHINE);
    }
    hideHome();
  } else if (homeMode === "drawn") {
    // Home -> the reading, which is still behind the home screen.
    hideHome();
  }
});

// Final screen -> home, with the promo showing the card that was drawn.
function returnHome() {
  const promoCard = document.getElementById("promo-card");
  promoCard.src = persona.image;
  promoCard.alt = persona.name;
  document.getElementById("promo-copy").textContent = persona.name;
  document.getElementById("promo-cta").textContent = "Read More";
  document.getElementById("home-promo").classList.add("is-drawn");
  homeMode = "drawn";

  homeEl.classList.add("is-leaving");
  homeEl.hidden = false;
  requestAnimationFrame(() => {
    requestAnimationFrame(() => homeEl.classList.remove("is-leaving"));
  });
}

const riveInstance = new rive.Rive({
  src: RIV_URL,
  canvas,
  artboard: ARTBOARD,
  stateMachine: STATE_MACHINE,
  // Waits behind the home screen; starts when it is tapped.
  autoplay: false,
  autoBind: true,
  enableGPUCanvas: true,
  useOffscreenRenderer: false,
  layout: new rive.Layout({ fit: rive.Fit.Cover, alignment: rive.Alignment.Center }),
  onLoad: () => {
    riveInstance.resizeDrawingSurfaceToCanvas();
    riveLoaded = true;
    if (homeMode !== "fresh") {
      riveInstance.play(STATE_MACHINE);
    }
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
  // Taps reach the canvas only once the fan has settled into FanIdle: the
  // state machine can't act on a pick before then, so a pick trigger fired
  // during the Layout deal-out or its blend would be lost.
  onStateChange: (event) => {
    if (event.data.includes("FanIdle") && !picked) {
      setTimeout(() => canvas.classList.add("is-ready"), FAN_BLEND_MS);
    } else if (event.data.some((state) => state !== "FanIdle")) {
      canvas.classList.remove("is-ready");
    }
  },
  onLoadError: (error) => console.error("Failed to load tarot-animation.riv", error),
});

interpretButton.addEventListener("click", onStartInterpreting);
// Close returns to the home screen, where Read More reopens this reading.
document.getElementById("reading-close").addEventListener("click", returnHome);
// Share is a placeholder for now.
document.getElementById("share").addEventListener("click", showShareToast);

window.addEventListener("resize", () => riveInstance.resizeDrawingSurfaceToCanvas());

// Device frame: Android or iPhone, from ?frame=, else the last choice.
(() => {
  const device = document.getElementById("device");
  const buttons = document.querySelectorAll(".frame-switch [data-frame]");
  const setFrame = (frame) => {
    device.classList.toggle("is-iphone", frame === "iphone");
    buttons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.frame === frame)));
    try {
      localStorage.setItem("frame", frame);
    } catch {}
  };
  let saved = null;
  try {
    saved = localStorage.getItem("frame");
  } catch {}
  setFrame(new URLSearchParams(location.search).get("frame") || saved || "android");
  buttons.forEach((b) => b.addEventListener("click", () => setFrame(b.dataset.frame)));
})();
