// Pinaka preview: a side panel with a tab per artboard.
//   The Bow      (artboard Pinaka, state machine Scene): Pull String / Test
//                Fire, aura and power sliders.
//   Astra        (artboard Astra, state machine Astra): five pulls (one per
//                astra), then
//                Fire; the blast follows on its own (an event in the file
//                fires it).
//   Play use case (artboard Reload, state machine Reload): an inbox on a
//                phone. Dragging down draws the bow live over it (`pull`),
//                letting go past the threshold fires (`fire`); the file's
//                `reload` event brings in new mail and `done` hands the
//                screen back. Each pull uses the next astra.
const SRC = "pinaka-bow.riv?v=24";

const SCENES = {
  bow: { artboard: "Pinaka", stateMachine: "Scene", width: 1280, height: 1280, canvas: "scene" },
  astra: { artboard: "Astra", stateMachine: "Astra", width: 1280, height: 720, canvas: "scene" },
  usecase: { artboard: "Reload", stateMachine: "Reload", width: 390, height: 844, canvas: "phone-scene" },
};

const stage = document.getElementById("stage");
const statusEl = document.getElementById("status");
let riveInstance = null;
let loaded = false;

function load(name) {
  const scene = SCENES[name];
  if (riveInstance) {
    riveInstance.cleanup();
    riveInstance = null;
  }
  loaded = false;
  // A fresh canvas per scene: the GPU canvas the bow renders into is tied
  // to the canvas it was created on.
  const old = document.getElementById(scene.canvas);
  const canvas = old.cloneNode(false);
  canvas.width = scene.width;
  canvas.height = scene.height;
  old.replaceWith(canvas);
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
      loaded = true;
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
  instance.on(rive.EventType.RiveEvent, (event) => onRiveEvent(event.data && event.data.name));
  riveInstance = instance;
}

function viewModel() {
  return riveInstance && riveInstance.viewModelInstance;
}

function setNumber(name, value) {
  const prop = viewModel() && viewModel().number(name);
  if (prop) {
    prop.value = value;
  }
}

// A colour as 0xAARRGGBB.
function setColor(name, argb) {
  const prop = viewModel() && viewModel().color(name);
  if (prop) {
    prop.argb((argb >>> 24) & 255, (argb >>> 16) & 255, (argb >>> 8) & 255, argb & 255);
  }
}

function fire(name) {
  const trigger = viewModel() && viewModel().trigger(name);
  if (trigger) {
    trigger.trigger();
  }
}

// Tabs. The URL hash (#bow, #astra, #usecase) picks the opening tab.
const tabs = document.querySelectorAll(".tab");
function select(name) {
  for (const tab of tabs) {
    const on = tab.dataset.scene === name;
    tab.setAttribute("aria-selected", String(on));
    document.getElementById(tab.getAttribute("aria-controls")).hidden = !on;
  }
  history.replaceState(null, "", `#${name}`);
  resetUseCase();
  load(name);
}
for (const tab of tabs) {
  tab.addEventListener("click", () => {
    if (stage.dataset.scene !== tab.dataset.scene || !riveInstance) {
      select(tab.dataset.scene);
    }
  });
}

// Trigger buttons, in the Bow and Astra panels.
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

// ---------------------------------------------------------------------------
// Play use case: pull to refresh

// Each pull uses the next astra; its look goes to the Reload view model.
const ASTRAS = [
  { name: "Brahmashirsha", aura: 0xffffb040, imprint: 0xffffd28c, arrow: 0xffffc060, tint: 0x00000000, style: 0 },
  { name: "Parjanyastra", aura: 0xff1e9bff, imprint: 0xff9ad8ff, arrow: 0xff35b6ff, tint: 0xff1c7cff, style: 1 },
  { name: "Nagastra", aura: 0xff2cff6a, imprint: 0xffb0ffc4, arrow: 0xff3dff7a, tint: 0xff19e05a, style: 2 },
  { name: "Vajrastra", aura: 0xffb040ff, imprint: 0xffe2b0ff, arrow: 0xffc060ff, tint: 0xff9b30ff, style: 3 },
  { name: "Agneyastra", aura: 0xffff5a1e, imprint: 0xffffc08a, arrow: 0xffff7a2a, tint: 0xffff4a12, style: 4 },
];
let astraIndex = 0;

function showNextAstra() {
  for (const item of document.querySelectorAll("#astra-cycle li")) {
    item.classList.toggle("is-next", Number(item.dataset.astra) === astraIndex);
  }
}

function applyAstra(astra) {
  setColor("aura", astra.aura);
  setColor("imprint", astra.imprint);
  setColor("arrow", astra.arrow);
  setColor("tint", astra.tint);
  setNumber("style", astra.style);
}

// The inbox. Fictional mail for the demo.
const INBOX = [
  { from: "Design Weekly", subject: "Ten motion trends for the new year", preview: "From springy UIs to shader backgrounds…", time: "9:12", color: "#7c5cff", unread: true },
  { from: "Maya (Studio)", subject: "Re: bow animation review", preview: "Loved the draw. Can the release be snappier?", time: "8:47", color: "#e8710a", unread: true },
  { from: "Calendar", subject: "Stand-up moved to 10:30", preview: "Your event has been updated.", time: "8:30", color: "#1a73e8" },
  { from: "Rive Community", subject: "Your file was featured", preview: "Congrats! The celestial bow is on the front page.", time: "Yesterday", color: "#111827" },
  { from: "Build bot", subject: "Deploy succeeded: web-preview", preview: "All checks passed in 2m 14s.", time: "Yesterday", color: "#0f9d58" },
  { from: "Arjun", subject: "Lunch on Friday?", preview: "There's a new place near the office…", time: "Tue", color: "#d93025" },
  { from: "Newsletter", subject: "The archer's paradox, explained", preview: "Why an arrow flexes as it leaves the bow.", time: "Mon", color: "#5f6368" },
  { from: "Ops", subject: "Weekly report", preview: "Uptime 99.98%. Two incidents, both resolved.", time: "Mon", color: "#9334e6" },
];
const NEW_MAIL = [
  { from: "Agni Labs", subject: "Agneyastra is live", preview: "The flames are toned just right now.", color: "#ff5a1e" },
  { from: "Maya (Studio)", subject: "Pull to refresh is magic", preview: "Shipping this in the app. Great work.", color: "#e8710a" },
  { from: "Sky Team", subject: "New nebula palettes", preview: "Blue mist, green pollen and violet storms.", color: "#1e9bff" },
  { from: "Release notes", subject: "v2.4: smoother blasts", preview: "No more glitch after the explosion.", color: "#0f9d58" },
  { from: "Design Weekly", subject: "Celestial UIs, a field guide", preview: "Stars that streak, clouds that stay calm…", color: "#7c5cff" },
];
let newMailIndex = 0;

const list = document.getElementById("mail-list");

function mailItem(mail, fresh) {
  const li = document.createElement("li");
  li.className = "mail__item" + (mail.unread || fresh ? " is-unread" : "") + (fresh ? " is-fresh" : "");
  const avatar = document.createElement("span");
  avatar.className = "mail__avatar";
  avatar.style.background = mail.color;
  avatar.textContent = mail.from.charAt(0);
  const from = document.createElement("span");
  from.className = "mail__from";
  from.textContent = mail.from;
  const time = document.createElement("span");
  time.className = "mail__time";
  time.textContent = mail.time || "Now";
  const subject = document.createElement("span");
  subject.className = "mail__subject";
  subject.textContent = mail.subject;
  const preview = document.createElement("span");
  preview.className = "mail__preview";
  preview.textContent = mail.preview;
  li.append(avatar, from, time, subject, preview);
  return li;
}

function renderInbox() {
  list.replaceChildren(...INBOX.map((mail) => mailItem(mail, false)));
}

// New mail lands: two fresh messages at the top, highlighted, then settle.
function refreshInbox() {
  for (let i = 0; i < 2; i++) {
    const mail = NEW_MAIL[newMailIndex % NEW_MAIL.length];
    newMailIndex++;
    list.prepend(mailItem(mail, true));
  }
  while (list.children.length > 12) {
    list.lastElementChild.remove();
  }
  setTimeout(() => {
    for (const item of list.querySelectorAll(".is-fresh")) {
      item.classList.remove("is-fresh");
    }
  }, 1800);
}

// The gesture.
const phoneScreen = document.getElementById("phone-screen");
const PULL_DISTANCE = 300; // screen px (390-wide phone) for a full draw
const FIRE_AT = 0.6; // let go past this much draw to fire
let drag = null;
let busy = false;
let fallback = 0;

function overlay() {
  return document.getElementById("phone-scene");
}

function phoneScale() {
  return phoneScreen.clientWidth / 390;
}

function resetUseCase() {
  drag = null;
  busy = false;
  clearTimeout(fallback);
  list.classList.remove("is-live");
  list.style.transform = "";
  const canvas = overlay();
  canvas.classList.remove("is-live");
  canvas.style.opacity = "";
}

phoneScreen.addEventListener("pointerdown", (event) => {
  if (busy || !loaded || stage.dataset.scene !== "usecase") {
    return;
  }
  drag = { y0: event.clientY, pull: 0 };
  phoneScreen.setPointerCapture(event.pointerId);
  applyAstra(ASTRAS[astraIndex]);
  list.classList.add("is-live");
  overlay().classList.add("is-live");
});

phoneScreen.addEventListener("pointermove", (event) => {
  if (!drag) {
    return;
  }
  const dy = Math.max(0, (event.clientY - drag.y0) / phoneScale());
  drag.pull = Math.min(1, dy / PULL_DISTANCE);
  setNumber("pull", drag.pull * 100);
  // The list gives with resistance; the sky takes over as you pull.
  list.style.transform = `translateY(${Math.min(dy * 0.35, 110) * phoneScale()}px)`;
  overlay().style.opacity = String(Math.min(1, dy / 70));
});

function endDrag() {
  if (!drag) {
    return;
  }
  const pulled = drag.pull;
  drag = null;
  list.classList.remove("is-live");
  if (pulled >= FIRE_AT) {
    // Loose it: the file plays the flight and the blast, then reports
    // `reload` and `done`.
    busy = true;
    overlay().style.opacity = "1";
    fire("fire");
    setTimeout(() => setNumber("pull", 0), 150);
    // If the events never come (no GPU, say), hand the screen back anyway.
    fallback = setTimeout(() => onRiveEvent("done"), 5000);
  } else {
    // Not far enough: spring back.
    overlay().classList.remove("is-live");
    overlay().style.opacity = "0";
    list.style.transform = "";
    springPullBack(pulled);
  }
}
phoneScreen.addEventListener("pointerup", endDrag);
phoneScreen.addEventListener("pointercancel", endDrag);

function springPullBack(from) {
  const start = performance.now();
  const step = (now) => {
    const t = Math.min(1, (now - start) / 260);
    setNumber("pull", from * (1 - t) * (1 - t) * 100);
    if (t < 1 && !drag && !busy) {
      requestAnimationFrame(step);
    }
  };
  requestAnimationFrame(step);
}

function onRiveEvent(name) {
  if (stage.dataset.scene !== "usecase") {
    return;
  }
  if (name === "reload") {
    refreshInbox();
  } else if (name === "done" && busy) {
    clearTimeout(fallback);
    overlay().classList.remove("is-live");
    overlay().style.opacity = "0";
    list.style.transform = "";
    busy = false;
    astraIndex = (astraIndex + 1) % ASTRAS.length;
    showNextAstra();
  }
}

renderInbox();
showNextAstra();
select(SCENES[location.hash.slice(1)] ? location.hash.slice(1) : "bow");
