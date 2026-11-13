// Palm reading: a web port of the app's palm reader
// (com.launcher.android.palm, Horoscope Launcher 1.45.0).
//
// This file is the core: state, the stage router, the people store and the
// Intro screen. Each later stage lives in its own file and registers itself
// with Palm.registerStage():
//   palm-vision.js  camera frames -> hand landmarks (MediaPipe) and palm lines
//   palm-live.js    LIVE: the camera, guidance and auto-capture
//   palm-draw.js    drawing shared by the stages (palm lines, crop transform)
//   palm-scan.js    SCANNING: the scan animation over the captured photo
//   palm-reveal.js  ANALYZING: the archetype card flip
//   palm-engine.js  features and the reading text (palm-content.json)
//   palm-result.js  RESULT: the reading, and sharing it
//
// Stages: intro -> live -> scanning -> analyzing -> result. Stages cross-fade:
// in over 400 ms while the old one fades out over 300 (PalmReaderApp).

(() => {
  const root = document.getElementById("palm");
  const tile = document.getElementById("palm-tile");
  const home = document.getElementById("home-screen");
  if (!root || !tile || !home) {
    return;
  }

  const ZODIAC = [
    ["Aries", "♈︎"], ["Taurus", "♉︎"], ["Gemini", "♊︎"],
    ["Cancer", "♋︎"], ["Leo", "♌︎"], ["Virgo", "♍︎"],
    ["Libra", "♎︎"], ["Scorpio", "♏︎"], ["Sagittarius", "♐︎"],
    ["Capricorn", "♑︎"], ["Aquarius", "♒︎"], ["Pisces", "♓︎"],
  ];
  const MAX_PEOPLE = 10;
  const STORE_KEY = "palm.people.v1";

  const el = (tag, attrs = {}, ...children) => {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (value == null || value === false) continue;
      if (key === "class") node.className = value;
      else if (key === "text") node.textContent = value;
      else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
      else node.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat()) {
      if (child != null && child !== false) node.append(child);
    }
    return node;
  };
  const svg = (markup) => {
    const holder = document.createElement("div");
    holder.innerHTML = markup.trim();
    return holder.firstElementChild;
  };
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));

  // --- People (saved in this browser only, like "Saved on this phone only.")

  function loadPeople() {
    let people = [];
    try {
      const saved = JSON.parse(localStorage.getItem(STORE_KEY) || "null");
      if (saved && Array.isArray(saved.people)) people = saved.people;
    } catch {}
    if (!people.some((p) => p.isMe)) {
      people.unshift({ id: "me", name: "Me", isMe: true, sign: "Aries", dominantHand: null, createdAt: Date.now(), palms: [] });
    }
    return people;
  }

  function savePeople() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify({ version: 1, people: state.people }));
    } catch {}
  }

  // --- State --------------------------------------------------------------

  const state = {
    stage: null,
    people: loadPeople(),
    selectedId: "me",
    dominantHand: null, // "LEFT" | "RIGHT" | null
    lens: "FRONT", // "FRONT" | "BACK"
    prep: { status: "preparing", progress: 0 }, // preparing | failed | ready
    frame: null, // PalmShot: the full captured frame
    closeUp: null, // PalmShot: the 4:5 palm crop
    features: null, // PalmFeatures (palm-engine.js)
    reading: null, // PalmReading (palm-engine.js)
    savedReading: false, // the result shows a saved palm (no photo)
    mismatchName: null,
    generation: 0,
  };

  const selected = () => state.people.find((p) => p.id === state.selectedId) || state.people[0];
  const isMe = () => {
    const person = selected();
    return !person || person.isMe;
  };
  const possessive = () => {
    const person = selected();
    if (!person || person.isMe) return "your";
    return /s$/i.test(person.name) ? `${person.name}'` : `${person.name}'s`;
  };

  function selectPerson(id) {
    const person = state.people.find((p) => p.id === id) || state.people.find((p) => p.isMe);
    state.selectedId = person.id;
    state.dominantHand = person.dominantHand || null;
  }

  function setDominantHand(hand) {
    const person = selected();
    person.dominantHand = hand;
    savePeople();
    selectPerson(person.id);
  }

  function addPerson(name, hand, sign) {
    if (state.people.filter((p) => !p.isMe).length >= MAX_PEOPLE) return null;
    const person = {
      id: (crypto.randomUUID && crypto.randomUUID()) || String(Date.now()),
      name: name.trim(),
      isMe: false,
      sign: sign || null,
      dominantHand: hand,
      createdAt: Date.now(),
      palms: [],
    };
    state.people.push(person);
    savePeople();
    selectPerson(person.id);
    return person;
  }

  function removePerson(id) {
    state.people = state.people.filter((p) => p.isMe || p.id !== id);
    savePeople();
    selectPerson(state.selectedId);
    updateTile();
  }

  // --- Stage router -------------------------------------------------------

  const stages = {};
  let current = null; // { name, el, api }

  const sky = el("div", { class: "palm__sky", "aria-hidden": "true" });
  root.append(sky);

  function setStage(name) {
    if (state.stage === name) return;
    state.stage = name;
    const def = stages[name];
    if (!def) {
      console.warn(`Palm: no stage "${name}"`);
      return;
    }
    const previous = current;
    const stageEl = el("div", { class: `palm-stage palm-stage--${name} is-entering`, "data-stage": name });
    root.append(stageEl);
    const api = def.mount(stageEl, Palm) || {};
    current = { name, el: stageEl, api };
    requestAnimationFrame(() => requestAnimationFrame(() => stageEl.classList.remove("is-entering")));
    if (previous) {
      previous.el.classList.add("is-leaving");
      if (previous.api.unmount) previous.api.unmount();
      setTimeout(() => previous.el.remove(), 320);
    }
  }

  function registerStage(name, def) {
    stages[name] = def;
  }

  // --- Flow actions -------------------------------------------------------

  function reset() {
    state.generation += 1;
    state.frame = null;
    state.closeUp = null;
    state.features = null;
    state.reading = null;
    state.savedReading = false;
    state.mismatchName = null;
  }

  function startScan() {
    reset();
    setStage("live");
  }

  function backToIntro() {
    reset();
    setStage("intro");
  }

  // LIVE hands over the capture: { frame, closeUp, analysis }, where
  // analysis = { shapeFrames: [landmark sets], lineFrames: [PalmShot] } for
  // palm-engine.js. SCANNING starts at once; the reading is worked out
  // meanwhile, and ANALYZING waits for it before it moves on.
  function onCaptured({ frame, closeUp, analysis }) {
    const generation = state.generation;
    state.frame = frame;
    state.closeUp = closeUp;
    setStage("scanning");
    Promise.resolve()
      .then(() => window.PalmEngine.analyze(analysis, frame))
      .then((features) => {
        if (generation !== state.generation) return;
        const person = selected();
        const match = window.PalmEngine.match ? window.PalmEngine.match(person, features) : "unsaved";
        if (match === "different") {
          state.features = features;
          state.mismatchName = person.isMe ? "Me" : person.name;
          showMismatch();
          return;
        }
        acceptFeatures(person, match === "same" || match === "unsure" ? savedFeatures(person, features.hand) || features : features);
      })
      .catch((error) => {
        console.error("Palm: analysis failed", error);
        if (generation === state.generation) {
          reset();
          setStage("live");
        }
      });
  }

  function savedFeatures(person, hand) {
    const palm = person.palms.find((p) => p.hand === hand);
    return palm ? palm.features : null;
  }

  // Saves the palm onto the person (one per hand) and builds the reading.
  function acceptFeatures(person, features) {
    const palms = person.palms.filter((p) => p.hand !== features.hand);
    const previous = person.palms.find((p) => p.hand === features.hand);
    // The palm map (SavedPalm landmarks/lines/aspect): the close-up's, for the
    // result screen's PalmMapHeader when the palm is opened again.
    const shot = state.closeUp;
    const map = shot
      ? { landmarks: shot.landmarks, lines: shot.lines, faint: shot.faint || [], aspect: shot.width / shot.height }
      : previous && previous.map;
    state.features = features;
    state.reading = window.PalmEngine.buildReading(features, person.dominantHand || "RIGHT", person.sign);
    palms.push({
      hand: features.hand,
      features,
      signature: features.signature || null,
      map: map || null,
      archetype: state.reading.archetype,
      headline: state.reading.headline,
      lastScan: Date.now(),
    });
    person.palms = palms;
    savePeople();
    if (shot) shots.set(`${person.id}:${features.hand}`, shot);
    persistLast();
    updateTile();
  }

  // This visit's close-up photos, by person and hand: reopening a palm read
  // in this visit shows its photo; after a reload, the saved palm map.
  const shots = new Map();

  // The most recently read palm, of anyone.
  function latestPalm() {
    let best = null;
    for (const person of state.people) {
      for (const palm of person.palms) {
        if (!best || palm.lastScan > best.palm.lastScan) best = { person, palm };
      }
    }
    return best;
  }

  // The home card has two states: no palm read yet (scan), or the latest
  // reading (open it).
  function updateTile() {
    const latest = latestPalm();
    const set = (id, text) => {
      const node = document.getElementById(id);
      if (node) node.textContent = text;
    };
    const titleEl = document.getElementById("palm-tile-title");
    const icon = document.getElementById("palm-tile-icon");
    const badge = document.getElementById("palm-tile-badge");
    tile.classList.toggle("is-read", Boolean(latest));
    if (badge) badge.hidden = Boolean(latest);
    if (!latest) {
      set("palm-tile-title", "Read your palm");
      set("palm-tile-copy", "Reveal your heart, head and life lines from one photo.");
      set("palm-tile-cta", "Scan palm");
      if (titleEl) titleEl.classList.add("feature__title--nowrap");
      if (icon) icon.hidden = false;
      tile.setAttribute("aria-label", "Palm: scan palm");
      return;
    }
    const { person, palm } = latest;
    const archetype = palm.archetype || "Your palm reading";
    set("palm-tile-title", archetype);
    set("palm-tile-copy", palm.headline || "Your heart, head and life lines, read.");
    set("palm-tile-cta", "See reading");
    if (titleEl) titleEl.classList.remove("feature__title--nowrap");
    if (icon) icon.hidden = true;
    tile.setAttribute("aria-label", `${archetype}: see the palm reading`);
  }

  function persistLast() {
    try {
      localStorage.setItem("palm.last", JSON.stringify({ archetype: state.reading.archetype, headline: state.reading.headline }));
    } catch {}
  }

  function onScanAnimationDone() {
    if (state.stage === "scanning") setStage("analyzing");
  }

  function onRevealDone() {
    if (state.stage === "analyzing" && state.reading) setStage("result");
  }

  // "See your reading": the saved palm, drawn as a map (no photo).
  function openSaved() {
    const person = selected();
    const palm = [...person.palms].sort((a, b) => b.lastScan - a.lastScan)[0];
    if (!palm) return;
    reset();
    state.features = palm.features;
    const shot = shots.get(`${person.id}:${palm.hand}`);
    state.closeUp = shot || null;
    state.savedReading = !shot;
    state.reading = window.PalmEngine.buildReading(palm.features, person.dominantHand || "RIGHT", person.sign);
    setStage("result");
  }

  async function open() {
    state.mismatchName = null;
    const latest = latestPalm();
    if (latest) {
      selectPerson(latest.person.id);
      // The reading text needs the content file, normally loaded long before.
      try {
        await window.PalmEngine.ready;
      } catch {}
    } else {
      selectPerson(state.selectedId);
    }
    root.hidden = false;
    root.classList.add("is-closed");
    state.stage = null;
    if (current) {
      current.el.remove();
      if (current.api.unmount) current.api.unmount();
      current = null;
    }
    if (latest) openSaved();
    else setStage("intro");
    requestAnimationFrame(() => requestAnimationFrame(() => root.classList.remove("is-closed")));
    home.classList.add("is-leaving");
    setTimeout(() => {
      home.hidden = true;
    }, 400);
    prepare();
  }

  function close() {
    reset();
    if (current && current.api.unmount) current.api.unmount();
    home.hidden = false;
    home.classList.add("is-leaving");
    requestAnimationFrame(() => requestAnimationFrame(() => home.classList.remove("is-leaving")));
    setTimeout(() => {
      root.hidden = true;
      if (current) current.el.remove();
      current = null;
      state.stage = null;
    }, 400);
  }

  // Gets hand tracking ready (the app downloads its model the same way):
  // the Scan button reads "Getting ready… N%" until it is.
  function prepare() {
    if (state.prep.status === "ready" || state.prep.running) return;
    state.prep = { status: "preparing", progress: 0, running: true };
    rerender();
    Promise.resolve()
      .then(() =>
        window.PalmVision.prepare((progress) => {
          state.prep.progress = progress;
          rerender();
        })
      )
      .then(() => {
        state.prep = { status: "ready", progress: 1 };
      })
      .catch((error) => {
        console.error("Palm: hand tracking failed to load", error);
        state.prep = { status: "failed", progress: 0 };
      })
      .then(rerender);
  }

  function rerender() {
    if (current && current.api.render) current.api.render();
  }

  tile.addEventListener("click", (event) => {
    event.stopPropagation();
    open();
  });
  updateTile();

  // --- Intro --------------------------------------------------------------

  // The palm outline from the app (n52), in its 250x286 design space. Seen
  // palm up, it is a right hand (thumb on the right); mirrored, a left one.
  const OUTLINE =
    "M58 280C44 250 36 212 38 176L40 107A13 13 0 0 1 66 107L66 150Q70 158 74 150L75 62A15 15 0 0 1 105 62L104 142Q108 150 112 142L113 44A16 16 0 0 1 145 44L144 142Q148 150 152 144L153 70A14 14 0 0 1 181 70L180 172Q182 186 190 190L208 158A13.2 13.2 0 0 1 230.99 171L214 206C204 226 190 246 186 280";

  function handIcon(hand) {
    const flip = hand === "LEFT" ? ' transform="matrix(-1 0 0 1 250 0)"' : "";
    return svg(`<svg class="palm-hand-icon" width="22" height="25" viewBox="0 0 250 286" fill="none" aria-hidden="true">
      <g${flip}>
        <path d="${OUTLINE}" fill="currentColor" fill-opacity=".14" stroke="currentColor" stroke-width="16" stroke-linecap="round" stroke-linejoin="round" />
        <path d="M60 200C95 192 128 198 152 176M70 226C110 214 150 210 182 200" stroke="currentColor" stroke-opacity=".7" stroke-width="12" stroke-linecap="round" />
      </g>
    </svg>`);
  }

  // The same animated illustration as the home screen's palm card
  // (home.css .palm-art): mandala, glowing hand, stars, brackets, scan line.
  function handArt() {
    return svg(`<span class="feature__art palm-art palm-intro__hand" aria-hidden="true">
      <span class="palm-art__glow"></span>
      <span class="palm-art__mandala"><img src="assets/home/palm-mandala.svg" alt="" /></span>
      <span class="palm-intro__flip"><img class="palm-art__hand" src="assets/home/palm-hand.svg" alt="" /></span>
      <img class="palm-art__stars" src="assets/home/palm-stars.svg" alt="" />
      <span class="palm-art__frame"><img src="assets/home/palm-frame.svg" alt="" /></span>
      <span class="palm-art__scan"><i></i></span>
    </span>`);
  }

  // Me: a zodiac medallion with your sign (as on the home screen). Others:
  // their initial on a colour of their own, with their sign as a badge.
  const TINTS = [
    ["#5b3fb8", "#2a1f63"],
    ["#1f6b73", "#123a45"],
    ["#8a3b6e", "#3f1a40"],
    ["#3b5fa8", "#1b2a5a"],
    ["#7a5a1f", "#3a2a0e"],
  ];

  function avatar(person, isSelected) {
    const sign = person.sign && ZODIAC.find(([name]) => name.toLowerCase() === String(person.sign).toLowerCase());
    if (person.isMe) {
      return el(
        "span",
        { class: "palm-avatar palm-avatar--me", "aria-hidden": "true" },
        el("span", { class: "medallion palm-avatar__medallion", text: sign ? sign[1].replace("\uFE0E", "") : "\u2726" }),
        isSelected && el("span", { class: "palm-avatar__check" }, svg(`<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 5.2 4.1 7.2 8 3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>`))
      );
    }
    const index = Math.max(0, state.people.filter((p) => !p.isMe).indexOf(person));
    const [from, to] = TINTS[index % TINTS.length];
    return el(
      "span",
      { class: "palm-avatar", style: `--from:${from};--to:${to}`, "aria-hidden": "true" },
      person.name.charAt(0).toUpperCase(),
      sign && el("span", { class: "palm-avatar__sign", text: sign[1] }),
      isSelected && el("span", { class: "palm-avatar__check" }, svg(`<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 5.2 4.1 7.2 8 3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>`))
    );
  }

  function personButton(person, onPick) {
    const isSelected = person.id === state.selectedId;
    const button = el(
      "button",
      {
        type: "button",
        class: `palm-person${isSelected ? " is-selected" : ""}`,
        "aria-pressed": String(isSelected),
        "aria-label": person.isMe ? "Me" : `${person.name}${person.isMe ? "" : ", hold to remove"}`,
      },
      avatar(person, isSelected),
      el("span", { class: "palm-person__name", text: person.isMe ? "Me" : person.name })
    );
    // Tap selects; holding a person who isn't Me offers to remove them.
    let holdTimer = 0;
    let held = false;
    button.addEventListener("pointerdown", () => {
      held = false;
      if (person.isMe) return;
      holdTimer = setTimeout(() => {
        held = true;
        showRemove(person);
      }, 500);
    });
    for (const type of ["pointerup", "pointerleave", "pointercancel"]) {
      button.addEventListener(type, () => clearTimeout(holdTimer));
    }
    button.addEventListener("contextmenu", (event) => {
      event.preventDefault();
      if (!person.isMe && !held) {
        held = true;
        showRemove(person);
      }
    });
    button.addEventListener("click", () => {
      if (held) return;
      onPick(person.id);
    });
    return button;
  }

  // Left hand / Right hand: two big buttons, each with its hand.
  function handToggle(value, onSelect) {
    const row = el("div", { class: "palm-hands", role: "group", "aria-label": "Writing hand" });
    for (const [hand, label] of [["LEFT", "Left hand"], ["RIGHT", "Right hand"]]) {
      row.append(
        el(
          "button",
          { type: "button", class: "palm-hand", "aria-pressed": String(value === hand), onclick: () => onSelect(hand) },
          el("span", { class: "palm-hand__icon" }, handIcon(hand)),
          label
        )
      );
    }
    return row;
  }

  function goldButton(label, onClick, { disabled = false } = {}) {
    return el("button", { type: "button", class: "palm-gold", disabled, onclick: onClick }, el("span", { class: "palm-gold__label", text: label }));
  }

  function ghostButton(label, onClick) {
    return el("button", { type: "button", class: "palm-ghost", text: label, onclick: onClick });
  }

  // The Scan button follows the hand tracker: "Getting ready… N%", then
  // "Try again" if it failed, else the label.
  function scanButton(label, onReady) {
    const { status, progress } = state.prep;
    const button = el("button", { type: "button", class: "palm-gold" });
    if (status === "preparing") {
      button.classList.add("is-preparing");
      button.setAttribute("aria-disabled", "true");
      if (progress > 0) {
        button.append(el("span", { class: "palm-gold__fill", style: `width:${progress * 100}%` }));
      }
      button.append(el("span", { class: "palm-gold__label", text: progress > 0 ? `Getting ready… ${Math.floor(progress * 100)}%` : "Getting ready…" }));
    } else if (status === "failed") {
      button.append(el("span", { class: "palm-gold__label", text: "Try again" }));
    } else {
      button.append(el("span", { class: "palm-gold__label", text: label }));
    }
    button.addEventListener("click", () => {
      if (state.prep.status === "preparing") return;
      if (state.prep.status === "failed") {
        prepare();
        return;
      }
      onReady();
    });
    return button;
  }

  registerStage("intro", {
    mount(stageEl) {
      let showHint = false;
      const view = el("div", { class: "palm-intro" });
      stageEl.append(view);

      function tryScan() {
        if (!state.dominantHand) {
          showHint = true;
          render();
          return;
        }
        startScan();
      }

      // The hand art is the home card's at up to 1.3x, scaled down to fit the
      // space left between the people and the buttons. It is built once, so
      // its animations run on and the hand can flip between left and right;
      // the parts above and below it re-render around it.
      const artBox = el("div", { class: "palm-intro__art" }, handArt());
      const above = el("div", { class: "palm-intro__part" });
      const below = el("div", { class: "palm-intro__part" });
      view.append(above, artBox, below);
      const fit = new ResizeObserver(() => {
        const hand = artBox.firstElementChild;
        if (hand) hand.style.zoom = String(Math.max(0.6, Math.min(1.3, (artBox.clientHeight - 8) / 140)));
      });
      fit.observe(artBox);

      function render() {
        const person = selected();
        const me = isMe();
        artBox.dataset.hand = state.dominantHand || "LEFT";
        const canAdd = state.people.filter((p) => !p.isMe).length < MAX_PEOPLE;
        const peopleRow = el("div", { class: "palm-people", role: "group", "aria-label": "Whose palm?" });
        for (const p of state.people) {
          peopleRow.append(
            personButton(p, (id) => {
              selectPerson(id);
              showHint = false;
              render();
            })
          );
        }
        if (canAdd) {
          peopleRow.append(
            el(
              "button",
              { type: "button", class: "palm-person palm-person--add", onclick: () => showAddSheet(render) },
              el(
                "span",
                { class: "palm-avatar palm-avatar--add", "aria-hidden": "true" },
                svg(`<svg width="22" height="22" viewBox="0 0 22 22"><path d="M11 4v14M4 11h14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" /></svg>`)
              ),
              el("span", { class: "palm-person__name", text: "Someone new" })
            )
          );
        }

        // One button: scan. A saved reading opens from the home card, and
        // the reading has its own "Read another palm".
        const actions = el("div", { class: "palm-intro__actions" });
        actions.append(scanButton(me ? "Scan your palm" : `Scan ${person.name}'s palm`, tryScan));

        const top = [
          el(
            "div",
            { class: "palm-intro__top" },
            el("span", { text: "Palm Reading" }),
            el("button", { type: "button", class: "palm-close", "aria-label": "Close", text: "✕", onclick: close })
          ),
          el("h1", { class: "palm-intro__title", text: "Your palm holds a story" }),
          el("div", { class: "palm-gap-top" }),
          el("p", { class: "palm-intro__whose", text: "WHOSE PALM?" }),
          peopleRow,
        ];
        const bottom = [
          el("p", { class: "palm-intro__question", text: me ? "Which hand do you write with?" : `Which hand does ${person.name} write with?` }),
          handToggle(state.dominantHand, (hand) => {
            setDominantHand(hand);
            showHint = false;
            render();
          }),
          showHint && el("p", { class: "palm-intro__hint", text: me ? "Choose the hand you write with first" : "Choose the hand they write with first" }),
          actions,
          state.prep.status === "failed" &&
            el("p", { class: "palm-intro__error", text: "Couldn't get palm reading ready. Check your connection and try again." }),
          el("div", { class: "palm-intro__foot" }),
          el("div", { class: "palm-gap-bottom" }),
        ];
        above.replaceChildren(...top.filter(Boolean));
        below.replaceChildren(...bottom.filter(Boolean));
      }

      render();
      return { render, unmount: () => fit.disconnect() };
    },
  });

  // --- Sheet and dialogs --------------------------------------------------

  function overlay(content, { dialog = false, onDismiss } = {}) {
    const scrim = el("div", { class: `palm-scrim${dialog ? " palm-scrim--dialog" : ""}` }, content);
    const dismiss = () => {
      if (scrim.classList.contains("is-leaving")) return;
      scrim.classList.add("is-leaving");
      setTimeout(() => scrim.remove(), 220);
    };
    scrim.addEventListener("click", (event) => {
      if (event.target === scrim) {
        dismiss();
        if (onDismiss) onDismiss();
      }
    });
    root.append(scrim);
    return dismiss;
  }

  function showAddSheet(after) {
    let name = "";
    let hand = null;
    let sign = null;
    const sheet = el("div", { class: "palm-sheet", role: "dialog", "aria-label": "Someone new" });
    const field = el("input", { class: "palm-field", type: "text", placeholder: "First name", autocapitalize: "words", enterkeyhint: "done", maxlength: "30" });
    const handSlot = el("div", { class: "palm-sheet__hands" });
    const signs = el("div", { class: "palm-signs" });
    const submitSlot = el("div", { style: "width:100%" });

    const renderHands = () =>
      handSlot.replaceChildren(
        handToggle(hand, (h) => {
          hand = h;
          renderHands();
          renderSubmit();
        })
      );
    const renderSigns = () =>
      signs.replaceChildren(
        ...ZODIAC.map(([signName, glyph]) =>
          el(
            "button",
            {
              type: "button",
              class: "palm-sign",
              "aria-pressed": String(sign === signName),
              onclick: () => {
                sign = sign === signName ? null : signName;
                renderSigns();
              },
            },
            el("span", { class: "palm-sign__glyph", text: glyph }),
            signName
          )
        )
      );
    // "Add & scan" adds and selects the person; Scan then starts the camera
    // (as in the app).
    const renderSubmit = () =>
      submitSlot.replaceChildren(
        goldButton(name.trim() ? `Scan ${name.trim()}'s palm` : "Add & scan", () => {
          if (!name.trim() || !hand) return;
          dismiss();
          addPerson(name, hand, sign);
          after();
        }, { disabled: !name.trim() || !hand })
      );
    field.addEventListener("input", () => {
      name = field.value;
      renderSubmit();
    });
    field.addEventListener("keydown", (event) => {
      if (event.key === "Enter") field.blur();
    });

    renderHands();
    renderSigns();
    renderSubmit();
    sheet.append(
      el("span", { class: "palm-sheet__handle", "aria-hidden": "true" }),
      el("p", { class: "palm-overline", text: "SOMEONE NEW" }),
      el("h2", { class: "palm-sheet__title", text: "Whose palm are we reading?" }),
      field,
      el("p", { class: "palm-sheet__label", text: "Which hand do they write with?" }),
      handSlot,
      el("p", { class: "palm-sheet__label", text: "Sun sign · optional" }),
      signs,
      submitSlot,
      el("p", { class: "palm-note", text: "Saved on this phone only." })
    );
    const dismiss = overlay(sheet);
  }

  function showRemove(person) {
    const dialog = el(
      "div",
      { class: "palm-dialog", role: "alertdialog", "aria-label": `Remove ${person.name}?` },
      el("h2", { class: "palm-dialog__title", text: `Remove ${person.name}?` }),
      el("p", { class: "palm-dialog__body", text: "Their saved palm reading will be deleted from this phone." }),
      goldButton("Remove", () => {
        dismiss();
        removePerson(person.id);
        rerender();
      }),
      ghostButton("Keep", () => dismiss())
    );
    const dismiss = overlay(dialog, { dialog: true });
  }

  // "A NEW HAND?": the scan doesn't match the person's saved palm.
  function showMismatch() {
    const name = state.mismatchName;
    const me = isMe();
    const generation = state.generation;
    const dialog = el("div", { class: "palm-dialog", role: "alertdialog", "aria-label": "A new hand?" });
    let dismiss = () => {};

    const samePerson = () => {
      dismiss();
      if (generation !== state.generation) return;
      state.mismatchName = null;
      const person = selected();
      acceptFeatures(person, state.features);
    };
    const someoneNew = (newName) => {
      dismiss();
      if (generation !== state.generation) return;
      state.mismatchName = null;
      const previous = selected();
      const person = addPerson(newName, previous.dominantHand, null);
      if (person) {
        acceptFeatures(person, state.features);
      } else {
        state.reading = window.PalmEngine.buildReading(state.features, previous.dominantHand || "RIGHT", previous.sign);
      }
      onRevealDone();
    };

    const renderAsk = () => {
      let newName = "";
      const field = el("input", { class: "palm-field", type: "text", placeholder: "First name", autocapitalize: "words", enterkeyhint: "done", maxlength: "30" });
      const submit = goldButton("See their reading", () => newName.trim() && someoneNew(newName.trim()), { disabled: true });
      field.addEventListener("input", () => {
        newName = field.value;
        submit.disabled = !newName.trim();
      });
      field.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && newName.trim()) someoneNew(newName.trim());
      });
      dialog.replaceChildren(
        el("span", { class: "palm-dialog__emoji", text: "✋", "aria-hidden": "true" }),
        el("p", { class: "palm-overline", text: "A NEW HAND?" }),
        el("h2", { class: "palm-dialog__title", text: "Whose palm is this?" }),
        field,
        submit
      );
      field.focus();
    };

    dialog.append(
      el("span", { class: "palm-dialog__emoji", text: "✋", "aria-hidden": "true" }),
      el("p", { class: "palm-overline", text: "A NEW HAND?" }),
      el("h2", { class: "palm-dialog__title", text: "This looks like a different hand" }),
      el("p", { class: "palm-dialog__body", text: `It doesn't match ${me ? "your" : `${name}'s`} saved palm. Is it someone else's?` }),
      goldButton("Yes, someone new", renderAsk),
      ghostButton(me ? "No, it's mine" : `No, it's ${name}'s`, samePerson)
    );
    // Dismissing counts as "same person", as in the app.
    dismiss = overlay(dialog, { dialog: true, onDismiss: samePerson });
  }

  // --- Public API for the stage files -------------------------------------

  const Palm = {
    root,
    state,
    el,
    svg,
    wait,
    selected,
    isMe,
    possessive,
    registerStage,
    setStage,
    startScan,
    backToIntro,
    onCaptured,
    onScanAnimationDone,
    onRevealDone,
    openSaved,
    close,
    rerender,
  };
  window.Palm = Palm;
})();
