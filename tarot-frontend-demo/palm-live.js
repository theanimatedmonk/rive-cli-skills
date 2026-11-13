// Palm reading: the LIVE stage (LiveScanScreen + the ScanViewModel parts that
// drive it). The camera, the overlay, the guidance pill, the lock ring, tips,
// "Read my palm now", the permission and camera-error screens, and the
// stabilizer that auto-captures after ~1.6 s of a good palm.
//
// Dev hook: ?palmfake=<image url> feeds a still photo through the same
// pipeline instead of the camera (the image must allow CORS).

(() => {
  const Palm = window.Palm;
  if (!Palm) return;
  const { el, svg } = Palm;

  const FAKE = new URLSearchParams(location.search).get("palmfake");

  const GUIDANCE = {
    NO_HAND: "Hold your open palm inside the outline",
    SHOW_PALM: "Turn your hand so your palm faces the camera",
    NO_LINES: "Can't see palm lines — show the inside of your hand in good light",
    OPEN_FINGERS: "Open your hand and spread your fingers",
    MOVE_CLOSER: "Bring your palm a little closer",
    MOVE_BACK: "Move back so your whole hand is visible",
    HOLD_STILL: "Hold still…",
    ADJUSTING_LIGHT: "Adjusting for the light — keep holding",
    TOO_DARK: "Too dark to read your palm — move to brighter light",
    PERFECT: "Perfect — keep holding",
  };
  const GOOD = new Set(["PERFECT", "HOLD_STILL", "ADJUSTING_LIGHT"]);
  const UNUSABLE = new Set(["NO_HAND", "SHOW_PALM", "OPEN_FINGERS"]);
  const TIPS = ["Find bright, even light", "Hold your palm flat, fingers spread", "Keep your whole hand in the frame", "Try the other camera"];

  const LOCK_MS = 1600;
  const COLORS = { bg: "14, 12, 36", gold: "#E8C27A", mint: "#8FD6C4" };
  // The app draws its overlay in raw device pixels on a ~3x phone.
  const DP = 1 / 3;

  const BONES = [
    [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11],
    [11, 12], [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
  ];

  // The no-hand outline (n52.f) in its 250 x 286 design box.
  const OUTLINE = new Path2D(
    "M58 280C44 250 36 212 38 176L40 107A13 13 0 0 1 66 107L66 150Q70 158 74 150L75 62A15 15 0 0 1 105 62L104 142Q108 150 112 142L113 44A16 16 0 0 1 145 44L144 142Q148 150 152 144L153 70A14 14 0 0 1 181 70L180 172Q182 186 190 190L208 158A13.2 13.2 0 0 1 230.99 171L214 206C204 226 190 246 186 280"
  );

  const ICON_BACK = `<svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7.825 13L13.425 18.6L12 20L4 12L12 4L13.425 5.4L7.825 11H20V13H7.825Z"/></svg>`;
  const ICON_FLIP = `<svg width="28" height="28" viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M16,7h-1l-1,-1h-4L9,7H8C6.9,7 6,7.9 6,9v6c0,1.1 0.9,2 2,2h8c1.1,0 2,-0.9 2,-2V9C18,7.9 17.1,7 16,7zM12,14c-1.1,0 -2,-0.9 -2,-2c0,-1.1 0.9,-2 2,-2s2,0.9 2,2C14,13.1 13.1,14 12,14z"/><path d="M8.57,0.51l4.48,4.48V2.04c4.72,0.47 8.48,4.23 8.95,8.95h2C23.34,5.02 18.18,0 12,0C10.91,0 9.72,0.18 8.57,0.51z"/><path d="M10.95,21.96C6.23,21.49 2.47,17.73 2,13.01H0C0.66,18.98 5.82,24 12,24c1.09,0 2.28,-0.18 3.43,-0.51l-4.48,-4.48V21.96z"/></svg>`;

  // FastOutSlowIn = cubic-bezier(0.4, 0, 0.2, 1).
  function bezier(x1, y1, x2, y2) {
    const at = (a, b, t) => 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t;
    return (x) => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let lo = 0, hi = 1, t = x;
      for (let i = 0; i < 24; i++) {
        t = (lo + hi) / 2;
        if (at(x1, x2, t) < x) lo = t;
        else hi = t;
      }
      return at(y1, y2, t);
    };
  }
  const fastOutSlowIn = bezier(0.4, 0, 0.2, 1);

  // --- Stabilizer (ef5) ---------------------------------------------------

  function makeStabilizer() {
    let acc = 0, prevTs = -1, prevCentroid = null, motion = 0, darkMs = 0;
    const dist = (p, q, a) => Math.hypot((p.x - q.x) * a, p.y - q.y);
    const angle = (u, v) => {
      const lu = Math.hypot(u[0], u[1], u[2]);
      const lv = Math.hypot(v[0], v[1], v[2]);
      if (lu < 1e-9 || lv < 1e-9) return 0;
      const c = (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / (lu * lv);
      return (Math.acos(Math.max(-1, Math.min(1, c))) * 180) / Math.PI;
    };

    function evaluate(hand) {
      const p = hand.landmarks;
      const a = hand.aspect;
      if (p.length < 21) return "NO_HAND";
      // Palm facing the camera: the winding of wrist -> index -> pinky.
      const v5 = { x: p[5].x - p[0].x, y: p[5].y - p[0].y };
      const v17 = { x: p[17].x - p[0].x, y: p[17].y - p[0].y };
      let B = v5.x * a * v17.y - v5.y * (v17.x * a);
      if (hand.mirrored) B = -B;
      if (hand.hand === "RIGHT" ? B >= 0 : B <= 0) return "SHOW_PALM";
      // Edge-on.
      if (dist(p[5], p[17], a) / Math.max(dist(p[0], p[9], a), 1e-6) < 0.45) return "SHOW_PALM";
      // Fingers extended.
      let extended = 0;
      for (const [tip, pip] of [[8, 6], [12, 10], [16, 14], [20, 18]]) {
        if (dist(p[0], p[tip], a) > dist(p[0], p[pip], a) * 1.06) extended++;
      }
      if (extended < 4) return "OPEN_FINGERS";
      // Fingers straight (world 3-D when there is one).
      const w = hand.world && hand.world.length >= 21 ? hand.world : null;
      const vec = (i, j) =>
        w ? [w[j].x - w[i].x, w[j].y - w[i].y, w[j].z - w[i].z] : [(p[j].x - p[i].x) * a, p[j].y - p[i].y, 0];
      let straight = 0;
      for (const m of [5, 9, 13, 17]) {
        const b1 = vec(m, m + 1), b2 = vec(m + 1, m + 2), b3 = vec(m + 2, m + 3);
        if (angle(b1, b2) < 55 && angle(b2, b3) < 55) straight++;
      }
      if (straight < 4) return "OPEN_FINGERS";
      // Framing.
      let minX = 1, minY = 1, maxX = 0, maxY = 0;
      for (const q of p) {
        minX = Math.min(minX, q.x); maxX = Math.max(maxX, q.x);
        minY = Math.min(minY, q.y); maxY = Math.max(maxY, q.y);
      }
      if (minX < 0.015 || minY < 0.015 || maxX > 0.985 || maxY > 0.985) return "MOVE_BACK";
      if (Math.max(maxY - minY, (maxX - minX) / a) < 0.25) return "MOVE_CLOSER";
      return "PERFECT";
    }

    function update(hand, ts, luma) {
      const dt = prevTs < 0 ? 0 : Math.min(ts - prevTs, 400);
      prevTs = ts;
      if (!hand) {
        prevCentroid = null;
        acc = Math.max(0, acc - 2 * dt);
        return { guidance: "NO_HAND", progress: Math.min(1, acc / LOCK_MS), locked: false, motion: 0 };
      }
      let result = evaluate(hand);
      const p = hand.landmarks;
      if (p.length >= 21) {
        const ids = [0, 5, 9, 13, 17];
        const c = { x: ids.reduce((s, i) => s + p[i].x, 0) / 5, y: ids.reduce((s, i) => s + p[i].y, 0) / 5 };
        if (prevCentroid) {
          motion = 0.4 * Math.hypot(c.x - prevCentroid.x, c.y - prevCentroid.y) * (33 / Math.max(dt, 1)) + 0.6 * motion;
        }
        prevCentroid = c;
      }
      if (result === "PERFECT" && motion > 0.035) result = "HOLD_STILL";
      if (result === "PERFECT" && luma != null && luma < 70) {
        darkMs += dt;
        result = darkMs > 2000 ? "TOO_DARK" : "ADJUSTING_LIGHT";
      } else if (luma == null || luma >= 70) {
        darkMs = 0;
      }
      if (result === "PERFECT") acc += dt;
      else if (result !== "ADJUSTING_LIGHT") acc = Math.max(0, acc - 1.5 * dt);
      return { guidance: result, progress: Math.min(1, acc / LOCK_MS), locked: acc >= LOCK_MS, motion };
    }

    function reset() {
      acc = 0; prevTs = -1; prevCentroid = null; motion = 0; darkMs = 0;
    }

    return { update, reset };
  }

  // --- Frames and shots ---------------------------------------------------

  function copyCanvas(source) {
    const c = document.createElement("canvas");
    c.width = source.width;
    c.height = source.height;
    c.getContext("2d").drawImage(source, 0, 0);
    return c;
  }

  // Mean luma of a 6x6 lattice in the palm triangle (ef6.f).
  function palmLuma(ctx, W, H, hand) {
    if (!hand || hand.landmarks.length < 21) return null;
    const [p0, p5, p17] = [hand.landmarks[0], hand.landmarks[5], hand.landmarks[17]];
    const pts = [];
    for (let i = 1; i <= 6; i++) {
      for (let j = 1; j <= 6; j++) {
        const u = i / 7, v = j / 7;
        if (u + v > 1.1) continue;
        pts.push({
          x: (p0.x + (p5.x - p0.x) * u + (p17.x - p0.x) * v) * W,
          y: (p0.y + (p5.y - p0.y) * u + (p17.y - p0.y) * v) * H,
        });
      }
    }
    const inside = pts.filter((p) => p.x >= 0 && p.y >= 0 && p.x < W && p.y < H);
    if (!inside.length) return null;
    const x0 = Math.floor(Math.min(...inside.map((p) => p.x)));
    const y0 = Math.floor(Math.min(...inside.map((p) => p.y)));
    const x1 = Math.floor(Math.max(...inside.map((p) => p.x)));
    const y1 = Math.floor(Math.max(...inside.map((p) => p.y)));
    const bw = x1 - x0 + 1;
    const data = ctx.getImageData(x0, y0, bw, y1 - y0 + 1).data;
    let sum = 0;
    for (const p of inside) {
      const k = ((Math.floor(p.y) - y0) * bw + (Math.floor(p.x) - x0)) * 4;
      sum += (77 * data[k] + 150 * data[k + 1] + 29 * data[k + 2]) >> 8;
    }
    return sum / inside.length;
  }

  // The 4:5 close-up crop around the hand (ef6.c), in normalized units.
  function cropRect(hand) {
    const a = hand.aspect;
    let minX = 1, minY = 1, maxX = 0, maxY = 0;
    for (const p of hand.landmarks) {
      minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
      minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
    }
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;
    let w = (maxX - minX) * a * 1.24;
    let h = (maxY - minY) * 1.24;
    if (w / h < 0.8) w = 0.8 * h;
    else h = w / 0.8;
    const hx = w / a / 2;
    const hy = h / 2;
    const s = Math.min(1, 0.5 / hx, 0.5 / hy);
    const hx2 = Math.min(0.5, hx * s);
    const hy2 = Math.min(0.5, hy * s);
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    const left = clamp(cx - hx2, 0, Math.max(0, 1 - 2 * hx2));
    const top = clamp(cy - hy2, 0, Math.max(0, 1 - 2 * hy2));
    return { left, top, right: left + 2 * hx2, bottom: top + 2 * hy2 };
  }

  function buildShots(canvas, hand, detection) {
    const W = canvas.width;
    const H = canvas.height;
    const frame = {
      image: canvas,
      width: W,
      height: H,
      landmarks: hand.landmarks,
      lines: detection.lines,
      faint: detection.faint,
      aspect: W / H,
    };
    const r = cropRect(hand);
    const sx = Math.trunc(W * r.left);
    const sy = Math.trunc(H * r.top);
    const sw = Math.max(1, Math.trunc((r.right - r.left) * W));
    const sh = Math.max(1, Math.trunc((r.bottom - r.top) * H));
    const crop = document.createElement("canvas");
    crop.width = sw;
    crop.height = sh;
    crop.getContext("2d").drawImage(canvas, sx, sy, sw, sh, 0, 0, sw, sh);
    const remap = (p) => ({ x: (p.x - r.left) / (r.right - r.left), y: (p.y - r.top) / (r.bottom - r.top) });
    const lines = {};
    for (const [key, pts] of Object.entries(detection.lines)) lines[key] = pts.map(remap);
    const closeUp = {
      image: crop,
      width: sw,
      height: sh,
      landmarks: hand.landmarks.map(remap),
      lines,
      faint: [...detection.faint],
      aspect: sw / sh,
    };
    return { frame, closeUp };
  }

  // --- Dev hook: ?palmfake=<image url> ------------------------------------
  // Turns a photo into a still "camera frame" like the app's analysis frames
  // (portrait 3:4, 960 x 1280), framed on the hand so that it sits inside the
  // part of the frame the screen shows. The frame then runs through the same
  // mirroring, tracking, guidance and capture as camera frames.
  let fakeCache = null;
  async function fakeCamera(url, screenAspect) {
    if (fakeCache && fakeCache.url === url) return copyCanvas(fakeCache.canvas);
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.src = url;
    await img.decode();
    const iw = img.naturalWidth;
    const ih = img.naturalHeight;
    const photo = document.createElement("canvas");
    photo.width = iw;
    photo.height = ih;
    photo.getContext("2d").drawImage(img, 0, 0);
    const FW = 960, FH = 1280, FA = FW / FH;
    let win; // the photo window (px) shown as the frame
    // Find the hand (the photo may only be found one way round).
    let hand = null;
    let flipped = false;
    try {
      hand = window.PalmVision.detect(photo, performance.now());
      if (!hand) {
        const mirror = document.createElement("canvas");
        mirror.width = iw;
        mirror.height = ih;
        const mctx = mirror.getContext("2d");
        mctx.translate(iw, 0);
        mctx.scale(-1, 1);
        mctx.drawImage(photo, 0, 0);
        hand = window.PalmVision.detect(mirror, performance.now());
        flipped = Boolean(hand);
      }
      // Drop the tracking state left by those looks at the raw photo.
      const blank = document.createElement("canvas");
      blank.width = 64;
      blank.height = 64;
      blank.getContext("2d").fillRect(0, 0, 64, 64);
      window.PalmVision.detect(blank, performance.now());
    } catch {}
    if (hand) {
      const xs = hand.landmarks.map((p) => (flipped ? 1 - p.x : p.x) * iw);
      const ys = hand.landmarks.map((p) => p.y * ih);
      const bw = Math.max(...xs) - Math.min(...xs);
      const bh = Math.max(...ys) - Math.min(...ys);
      const cx = (Math.max(...xs) + Math.min(...xs)) / 2;
      const cy = (Math.max(...ys) + Math.min(...ys)) / 2;
      // The share of the frame's width the screen shows (cover fit).
      const visible = Math.min(1, screenAspect / FA);
      // Never zoom in past the photo's own height, so a small hand stays small.
      const h = Math.max(bh * 1.3, (bw * 1.3) / (FA * visible), Math.min(ih, iw / FA));
      win = { x: cx - (h * FA) / 2, y: cy - h / 2, w: h * FA, h };
    } else {
      const h = Math.min(ih, iw / FA);
      win = { x: (iw - h * FA) / 2, y: (ih - h) / 2, w: h * FA, h };
    }
    const canvas = document.createElement("canvas");
    canvas.width = FW;
    canvas.height = FH;
    const ctx = canvas.getContext("2d");
    // Past the photo's edges: a blurred cover-fit copy of it.
    const cover = Math.max(FW / iw, FH / ih);
    ctx.filter = "blur(24px) brightness(0.7)";
    ctx.drawImage(photo, (FW - iw * cover) / 2, (FH - ih * cover) / 2, iw * cover, ih * cover);
    ctx.filter = "none";
    const k = FW / win.w;
    ctx.drawImage(photo, -win.x * k, -win.y * k, iw * k, ih * k);
    fakeCache = { url, canvas };
    return copyCanvas(canvas);
  }

  // --- The stage ----------------------------------------------------------

  Palm.registerStage("live", {
    mount(stageEl) {
      const state = Palm.state;
      const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const generation = state.generation;
      let dead = false;

      // Camera / permission
      let granted = false;
      let asked = false;
      let bindFailed = false;
      let showSettingsHelp = false;
      let stream = null;
      let cameraKey = 0;
      let source = null; // the <video> or <img> being read
      let permissionStatus = null;

      // Session (ScanViewModel)
      const stabilizer = makeStabilizer();
      let session = 0;
      let scanStart = performance.now();
      let live = defaultLive();
      let lastUsable = null; // { canvas, hand }
      let usableMs = 0;
      let prevTs = -1;
      let rejectUntil = -1;
      let shapes = []; // TrackedHands while PERFECT (≤ 60)
      let kept = []; // { canvas, hand } every ≥ 300 ms while PERFECT (≤ 4)
      let lastKeptTs = -1;
      let capturing = false;
      let lastDetectAt = 0;
      let lastVideoTime = -1;

      const frameCanvas = document.createElement("canvas");
      const frameCtx = frameCanvas.getContext("2d", { willReadFrequently: true });
      const usableCanvas = document.createElement("canvas");

      function defaultLive() {
        return { hand: null, guidance: "NO_HAND", progress: 0, showTip: false, canReadNow: false, palmLuma: null };
      }

      function resetSession() {
        session += 1;
        stabilizer.reset();
        lastUsable = null;
        usableMs = 0;
        prevTs = -1;
        rejectUntil = -1;
        shapes = [];
        kept = [];
        lastKeptTs = -1;
        capturing = false;
        scanStart = performance.now();
        live = defaultLive();
      }

      // --- DOM
      const media = el("div", { class: "palm-live__media" });
      const overlay = el("canvas", { class: "palm-live__overlay", "aria-hidden": "true" });
      const panel = el("div", { class: "palm-live__panel-slot" });

      const back = el(
        "button",
        { type: "button", class: "palm-live__back", "aria-label": "Back", onclick: () => Palm.backToIntro() },
        svg(ICON_BACK)
      );
      const pill = el("p", { class: "palm-live__pill", role: "status", "aria-live": "polite" });
      const tipBox = el("div", { class: "palm-live__tip" });
      const ringArc = svg(
        `<svg class="palm-live__ring-svg" width="84" height="84" viewBox="0 0 84 84" aria-hidden="true">
          <circle cx="42" cy="42" r="42" fill="rgba(${COLORS.bg}, .6)" />
          <circle cx="42" cy="42" r="42" fill="none" stroke="rgba(217, 212, 236, .25)" stroke-width="${6 * DP}" />
          <circle class="palm-live__ring-arc" cx="42" cy="42" r="42" fill="none" stroke="${COLORS.gold}" stroke-width="${8 * DP}" stroke-linecap="round" transform="rotate(-90 42 42)" />
        </svg>`
      );
      const arc = ringArc.querySelector(".palm-live__ring-arc");
      const ARC_LEN = 2 * Math.PI * 42;
      const ringText = el("span", { class: "palm-live__ring-text" });
      const ring = el("div", { class: "palm-live__ring", role: "progressbar", "aria-label": "Palm lock", "aria-valuemin": "0", "aria-valuemax": "100" }, ringArc, ringText);
      const flip = el("button", { type: "button", class: "palm-live__flip", onclick: flipCamera }, svg(ICON_FLIP));
      const readNow = el("button", { type: "button", class: "palm-live__read", text: "Read my palm now", onclick: readNowAction });
      const readSlot = el("div", { class: "palm-live__read-slot" }, readNow);
      const cameraUi = el(
        "div",
        { class: "palm-live__camera-ui" },
        pill,
        el("div", { class: "palm-live__spacer" }),
        tipBox,
        el("div", { class: "palm-live__bottom" }, ring, flip),
        readSlot
      );
      const controls = el("div", { class: "palm-live__controls" }, el("div", { class: "palm-live__top" }, back), cameraUi);
      const view = el("div", { class: "palm-live" }, media, overlay, panel, controls);
      stageEl.append(view);

      // --- Tips: index 0 each time they appear, next one every 4 s.
      let tipShown = false;
      let tipTimer = 0;
      let tipIndex = 0;
      function setTipVisible(visible) {
        if (visible === tipShown) return;
        tipShown = visible;
        tipBox.classList.toggle("is-visible", visible);
        clearInterval(tipTimer);
        if (visible) {
          tipIndex = 0;
          tipBox.replaceChildren(el("span", { class: "palm-live__tip-text is-in", text: `Tip · ${TIPS[0]}` }));
          tipTimer = setInterval(() => {
            tipIndex = (tipIndex + 1) % TIPS.length;
            for (const old of tipBox.children) {
              old.classList.remove("is-in");
              setTimeout(() => old.remove(), 520);
            }
            const next = el("span", { class: "palm-live__tip-text", text: `Tip · ${TIPS[tipIndex]}` });
            tipBox.append(next);
            requestAnimationFrame(() => requestAnimationFrame(() => next.classList.add("is-in")));
          }, 4000);
        }
      }

      // --- Panels (permission rationale, camera error)
      function render() {
        if (dead) return;
        view.classList.toggle("is-granted", granted);
        view.classList.toggle("is-front", state.lens === "FRONT");
        cameraUi.hidden = !granted;
        flip.setAttribute("aria-label", state.lens === "BACK" ? "Switch to front camera" : "Switch to back camera");
        if (granted && bindFailed) {
          panel.replaceChildren(
            el(
              "div",
              { class: "palm-live__panel palm-live__panel--error", role: "alert" },
              el("h2", { class: "palm-live__title", text: "Couldn't open the camera" }),
              el("p", { class: "palm-live__body", text: "Another app may be using it. Close it and try again." }),
              el("button", { type: "button", class: "palm-live__btn", text: "Try again", onclick: () => startCamera() })
            )
          );
        } else if (!granted && asked) {
          panel.replaceChildren(
            el(
              "div",
              { class: "palm-live__panel" },
              el("h2", { class: "palm-live__title", text: "The camera is needed to see your palm" }),
              el("p", { class: "palm-live__body", text: "Frames are processed on your device and never leave it." }),
              el("button", { type: "button", class: "palm-live__btn", text: "Allow camera", onclick: () => startCamera() }),
              el("button", {
                type: "button",
                class: "palm-live__btn palm-live__btn--outlined",
                text: "Open settings",
                onclick: () => {
                  showSettingsHelp = true;
                  render();
                },
              }),
              showSettingsHelp &&
                el("p", {
                  class: "palm-live__help",
                  text: "Allow the camera for this site from the camera or lock icon in your browser's address bar, then tap Allow camera.",
                })
            )
          );
        } else {
          panel.replaceChildren();
        }
        paintControls();
      }

      // --- Camera
      function stopCamera(keepView = false) {
        if (stream) for (const track of stream.getTracks()) track.stop();
        stream = null;
        source = null;
        if (!keepView) media.replaceChildren();
      }

      async function startCamera() {
        cameraKey += 1;
        const key = cameraKey;
        stopCamera();
        bindFailed = false;
        lastVideoTime = -1;
        if (!window.PalmVision.isReady()) {
          try {
            await window.PalmVision.prepare();
          } catch (error) {
            console.error("Palm: hand tracking failed to load", error);
          }
        }
        if (dead || key !== cameraKey) return;

        if (FAKE) {
          granted = true;
          asked = true;
          let still;
          try {
            still = await fakeCamera(FAKE, view.clientWidth / Math.max(1, view.clientHeight));
          } catch (error) {
            console.error("Palm: ?palmfake image failed to load", error);
            if (dead || key !== cameraKey) return;
            bindFailed = true;
            render();
            return;
          }
          if (dead || key !== cameraKey) return;
          still.className = "palm-live__preview";
          media.replaceChildren(still);
          source = still;
          render();
          return;
        }

        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          granted = true;
          bindFailed = true;
          render();
          return;
        }
        try {
          const facing = state.lens === "FRONT" ? "user" : "environment";
          const s = await navigator.mediaDevices.getUserMedia({
            audio: false,
            video: { facingMode: { ideal: facing }, width: { ideal: 1280 }, height: { ideal: 960 }, aspectRatio: { ideal: 4 / 3 } },
          });
          if (dead || key !== cameraKey) {
            for (const track of s.getTracks()) track.stop();
            return;
          }
          stream = s;
          granted = true;
          asked = true;
          const settings = (s.getVideoTracks()[0] && s.getVideoTracks()[0].getSettings()) || {};
          // The other lens is used when the asked-for one is missing.
          if (settings.facingMode === "user" && state.lens !== "FRONT") state.lens = "FRONT";
          if (settings.facingMode === "environment" && state.lens !== "BACK") state.lens = "BACK";
          const video = el("video", { class: "palm-live__preview", playsinline: true, muted: true, autoplay: true });
          video.muted = true;
          video.srcObject = s;
          media.replaceChildren(video);
          source = video;
          render();
          try {
            await video.play();
          } catch {}
        } catch (error) {
          if (dead || key !== cameraKey) return;
          if (error && (error.name === "NotAllowedError" || error.name === "SecurityError" || error.name === "PermissionDeniedError")) {
            granted = false;
            asked = true;
          } else {
            console.warn("Palm: camera failed", error);
            granted = true;
            bindFailed = true;
          }
          render();
        }
      }

      // Re-check the permission when it changes or the page comes back.
      function recheck() {
        if (dead || FAKE || granted || !asked) return;
        if (permissionStatus && permissionStatus.state === "granted") startCamera();
      }
      if (!FAKE && navigator.permissions && navigator.permissions.query) {
        navigator.permissions
          .query({ name: "camera" })
          .then((status) => {
            if (dead) return;
            permissionStatus = status;
            status.addEventListener("change", recheck);
          })
          .catch(() => {});
      }
      const onVisible = () => {
        if (document.visibilityState === "visible") recheck();
      };
      document.addEventListener("visibilitychange", onVisible);

      function flipCamera() {
        resetSession();
        state.lens = state.lens === "BACK" ? "FRONT" : "BACK";
        render();
        startCamera();
      }

      function readNowAction() {
        if (state.stage !== "live" || capturing || !lastUsable || !lastUsable.hand) return;
        capture(copyCanvas(lastUsable.canvas), lastUsable.hand);
      }

      // --- Per frame (ScanViewModel.onFrame)
      function grabFrame() {
        if (!source) return false;
        let w, h;
        if (source.tagName === "VIDEO") {
          if (source.readyState < 2 || !source.videoWidth) return false;
          if (source.currentTime === lastVideoTime) return false;
          lastVideoTime = source.currentTime;
          w = source.videoWidth;
          h = source.videoHeight;
        } else {
          // The ?palmfake still (already a 960 x 1280 camera frame).
          w = source.width;
          h = source.height;
        }
        if (frameCanvas.width !== w || frameCanvas.height !== h) {
          frameCanvas.width = w;
          frameCanvas.height = h;
        }
        frameCtx.save();
        if (state.lens === "FRONT") {
          frameCtx.translate(w, 0);
          frameCtx.scale(-1, 1);
        }
        frameCtx.drawImage(source, 0, 0, w, h);
        frameCtx.restore();
        return true;
      }

      function onFrame(hand, ts) {
        if (state.stage !== "live" || capturing) return;
        const luma = palmLuma(frameCtx, frameCanvas.width, frameCanvas.height, hand);
        let st = stabilizer.update(hand, ts, luma);
        if (rejectUntil >= 0 && ts < rejectUntil) st = { guidance: "NO_LINES", progress: 0, locked: false, motion: st.motion };
        const dtUsable = prevTs < 0 ? 0 : Math.min(400, Math.max(0, ts - prevTs));
        prevTs = ts;
        if (!UNUSABLE.has(st.guidance)) {
          if (usableCanvas.width !== frameCanvas.width || usableCanvas.height !== frameCanvas.height) {
            usableCanvas.width = frameCanvas.width;
            usableCanvas.height = frameCanvas.height;
          }
          usableCanvas.getContext("2d").drawImage(frameCanvas, 0, 0);
          lastUsable = { canvas: usableCanvas, hand };
          usableMs += dtUsable;
        }
        if (st.guidance === "PERFECT" && hand) {
          shapes.push(hand);
          if (shapes.length > 60) shapes.shift();
          if (lastKeptTs < 0 || ts - lastKeptTs >= 300) {
            kept.push({ canvas: copyCanvas(frameCanvas), hand });
            if (kept.length > 4) kept.shift();
            lastKeptTs = ts;
          }
        } else if (st.guidance === "NO_HAND") {
          shapes = [];
          kept = [];
        }
        live = {
          hand,
          guidance: st.guidance,
          progress: st.progress,
          showTip: performance.now() - scanStart > 12000 && st.progress < 0.3,
          canReadNow: usableMs > 5000,
          palmLuma: luma,
        };
        if (st.locked && hand) capture(copyCanvas(frameCanvas), hand);
      }

      // --- Capture (ef6.m): lines, then the shots, then SCANNING
      function capture(canvas, hand) {
        capturing = true;
        live = { ...live, guidance: "PERFECT", progress: 1 };
        const mySession = session;
        const extras = kept.filter((k) => k.hand && k.canvas !== canvas);
        const picks = [];
        for (const k of [extras[extras.length - 1], extras[Math.floor(extras.length / 2)]]) {
          if (k && !picks.includes(k)) picks.push(k);
        }
        const shapeFrames = [...shapes.slice(-60), hand];
        // Let the ring paint 100% before the detector runs.
        setTimeout(() => {
          if (dead || mySession !== session || generation !== state.generation || state.stage !== "live") return;
          let detection;
          try {
            detection = window.PalmVision.detectLines(canvas, hand);
          } catch (error) {
            console.error("Palm: line detection failed", error);
            stabilizer.reset();
            capturing = false;
            return;
          }
          if (!detection.isPalm) {
            // "Can't see palm lines…" for 2.5 s, and start the lock over.
            stabilizer.reset();
            rejectUntil = performance.now() + 2500;
            capturing = false;
            live = { ...live, guidance: "NO_LINES", progress: 0 };
            return;
          }
          const { frame, closeUp } = buildShots(canvas, hand, detection);
          const lineFrames = [{ landmarks: hand.landmarks, lines: detection.lines, faint: detection.faint, aspect: hand.aspect }];
          for (const k of picks) {
            try {
              const d = window.PalmVision.detectLines(k.canvas, k.hand);
              lineFrames.push({ landmarks: k.hand.landmarks, lines: d.lines, faint: d.faint, aspect: k.hand.aspect });
            } catch {}
          }
          stopLoop();
          Palm.onCaptured({ frame, closeUp, analysis: { shapeFrames, lineFrames } });
        }, 60);
      }

      // --- Exposure and focus (PalmExposure), best effort
      let exposureIndex = 0;
      const exposureTimer = setInterval(() => {
        const track = stream && stream.getVideoTracks()[0];
        if (!track || live.palmLuma == null || !track.getCapabilities) return;
        const caps = track.getCapabilities();
        const range = caps.exposureCompensation;
        if (!range) return;
        const step = range.step || 1;
        const upper = Math.round((range.max - 0) / step);
        let next = exposureIndex;
        if (live.palmLuma < 95 && exposureIndex < upper) next += 1;
        else if (live.palmLuma > 200 && exposureIndex > 0) next -= 1;
        if (next === exposureIndex) return;
        exposureIndex = next;
        track.applyConstraints({ advanced: [{ exposureCompensation: Math.min(range.max, next * step) }] }).catch(() => {});
      }, 500);
      const focusTimer = setInterval(() => {
        const track = stream && stream.getVideoTracks()[0];
        const hand = live.hand;
        if (!track || !hand || !track.getCapabilities) return;
        const caps = track.getCapabilities();
        if (!("pointsOfInterest" in caps) && !caps.focusMode) return;
        const ids = [0, 5, 9, 13, 17];
        const c = { x: ids.reduce((s, i) => s + hand.landmarks[i].x, 0) / 5, y: ids.reduce((s, i) => s + hand.landmarks[i].y, 0) / 5 };
        // The camera sees the unmirrored image.
        const x = hand.mirrored ? 1 - c.x : c.x;
        const advanced = [{ pointsOfInterest: [{ x, y: c.y }] }];
        if (caps.focusMode && caps.focusMode.includes("single-shot")) advanced.push({ focusMode: "single-shot" });
        track.applyConstraints({ advanced }).catch(() => {});
      }, 2500);

      // --- Drawing
      let ringShown = 0;
      let ringFrom = 0;
      let ringTarget = 0;
      let ringStart = 0;
      let pillText = "";
      let pillPerfect = null;
      const t0 = performance.now();

      function paintControls(now = performance.now()) {
        // Pill
        if (pillText !== live.guidance) {
          pillText = live.guidance;
          pill.textContent = GUIDANCE[live.guidance];
        }
        const perfect = live.guidance === "PERFECT";
        if (pillPerfect !== perfect) {
          pillPerfect = perfect;
          pill.classList.toggle("is-perfect", perfect);
        }
        // Lock ring: animateFloatAsState(tween 120 ms).
        // A new target restarts the tween from the value shown right now.
        const ringAt = (t) => ringFrom + (ringTarget - ringFrom) * fastOutSlowIn(Math.max(0, Math.min(1, (t - ringStart) / 120)));
        if (live.progress !== ringTarget) {
          ringFrom = ringAt(now);
          ringTarget = live.progress;
          ringStart = now;
        }
        ringShown = ringAt(now);
        const p = ringShown;
        arc.style.strokeDasharray = `${p * ARC_LEN} ${ARC_LEN}`;
        arc.style.opacity = p > 0.001 ? "1" : "0";
        const label = p > 0.02 ? `${Math.floor(p * 100)}%` : "✋";
        if (ringText.textContent !== label) {
          ringText.textContent = label;
          ringText.classList.toggle("is-hand", p <= 0.02);
        }
        ring.setAttribute("aria-valuenow", String(Math.floor(p * 100)));
        setTipVisible(granted && live.showTip);
        readSlot.classList.toggle("is-visible", granted && live.canReadNow && live.progress < 1);
      }

      function paintOverlay(now) {
        const W = overlay.clientWidth;
        const H = overlay.clientHeight;
        if (!W || !H) return;
        const dpr = window.devicePixelRatio || 1;
        if (overlay.width !== Math.round(W * dpr) || overlay.height !== Math.round(H * dpr)) {
          overlay.width = Math.round(W * dpr);
          overlay.height = Math.round(H * dpr);
        }
        const ctx = overlay.getContext("2d");
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, W, H);
        if (!granted) return;

        // Infinite transitions: pulse 0.45<->1 (1100 ms, reverse), dash 0->68 (1400 ms).
        const t = now - t0;
        const cycle = (t % 2200) / 1100;
        const pulse = reduced ? 1 : 0.45 + 0.55 * fastOutSlowIn(cycle <= 1 ? cycle : 2 - cycle);
        const phase = reduced ? 0 : 68 * fastOutSlowIn((t % 1400) / 1400);

        // (a) vignette
        const R = 0.7 * Math.max(W, H);
        const g = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, R);
        g.addColorStop(0, `rgba(${COLORS.bg}, 0)`);
        g.addColorStop(1, `rgba(${COLORS.bg}, .65)`);
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, W, H);

        const hand = live.hand;
        if (!hand) {
          // (b) dashed palm outline
          const w = 0.66 * W;
          const h = 1.3 * w;
          const left = (W - w) / 2;
          const top = (H - h) / 2 + 0.03 * H;
          const s = Math.min(w / 250, h / 286);
          const ox = left + (w - 250 * s) / 2;
          const oy = top + (h - 286 * s) / 2;
          const isLeft = state.dominantHand === "LEFT";
          const isFront = state.lens === "FRONT";
          ctx.save();
          if (isLeft !== isFront) {
            const cx = left + w / 2;
            ctx.translate(cx, 0);
            ctx.scale(-1, 1);
            ctx.translate(-cx, 0);
          }
          ctx.translate(ox, oy);
          ctx.scale(s, s);
          ctx.strokeStyle = `rgba(255, 255, 255, ${pulse * 0.85})`;
          ctx.lineWidth = (4 * DP) / s;
          ctx.lineCap = "butt";
          ctx.setLineDash([(22 * DP) / s, (12 * DP) / s]);
          ctx.lineDashOffset = (phase * DP) / s;
          ctx.stroke(OUTLINE);
          ctx.restore();
          return;
        }

        // (c) skeleton + corner brackets, cover-fitted
        const a = hand.aspect;
        const scale = Math.max(W / a, H);
        const dw = a * scale;
        const dh = scale;
        const offX = (W - dw) / 2;
        const offY = (H - dh) / 2;
        const pts = hand.landmarks.map((p) => ({ x: p.x * dw + offX, y: p.y * dh + offY }));
        const good = GOOD.has(live.guidance);
        const color = good ? COLORS.gold : COLORS.mint;
        ctx.setLineDash([]);
        if (pts.length >= 21) {
          ctx.strokeStyle = color;
          ctx.globalAlpha = good ? 0.85 : 0.55;
          ctx.lineWidth = 3 * DP;
          ctx.lineCap = "round";
          ctx.beginPath();
          for (const [i, j] of BONES) {
            ctx.moveTo(pts[i].x, pts[i].y);
            ctx.lineTo(pts[j].x, pts[j].y);
          }
          ctx.stroke();
          for (const p of pts) {
            ctx.globalAlpha = 0.3;
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(p.x, p.y, 11 * DP, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
            ctx.fillStyle = "#fff";
            ctx.beginPath();
            ctx.arc(p.x, p.y, 5 * DP, 0, Math.PI * 2);
            ctx.fill();
          }
        }
        const pad = 28 * DP;
        const arm = 46 * DP;
        const L = Math.min(...pts.map((p) => p.x)) - pad;
        const T = Math.min(...pts.map((p) => p.y)) - pad;
        const Rr = Math.max(...pts.map((p) => p.x)) + pad;
        const B = Math.max(...pts.map((p) => p.y)) + pad;
        ctx.globalAlpha = pulse;
        ctx.strokeStyle = color;
        ctx.lineWidth = 6 * DP;
        ctx.lineCap = "round";
        ctx.beginPath();
        for (const [x, y, sx, sy] of [[L, T, 1, 1], [Rr, T, -1, 1], [L, B, 1, -1], [Rr, B, -1, -1]]) {
          ctx.moveTo(x, y);
          ctx.lineTo(x + sx * arm, y);
          ctx.moveTo(x, y);
          ctx.lineTo(x, y + sy * arm);
        }
        ctx.stroke();
        ctx.globalAlpha = 1;
      }

      let raf = 0;
      function loop(now) {
        raf = requestAnimationFrame(loop);
        if (dead) return;
        // Analysis runs at most ~30 times a second, like the camera stream.
        if (granted && !bindFailed && source && !capturing && window.PalmVision.isReady() && now - lastDetectAt >= 30) {
          if (grabFrame()) {
            lastDetectAt = now;
            const ts = performance.now();
            let hand = null;
            try {
              hand = window.PalmVision.detect(frameCanvas, ts, { mirrored: state.lens === "FRONT" });
            } catch (error) {
              console.error("Palm: hand detection failed", error);
            }
            onFrame(hand, ts);
          }
        }
        paintControls(now);
        paintOverlay(now);
      }
      function stopLoop() {
        cancelAnimationFrame(raf);
        raf = 0;
        // Keep painting the last state (100%) while the stage fades out.
        const settle = (now) => {
          if (dead) return;
          paintControls(now);
          paintOverlay(now);
          raf = requestAnimationFrame(settle);
        };
        raf = requestAnimationFrame(settle);
      }

      const onKey = (event) => {
        if (event.key === "Escape" && state.stage === "live") Palm.backToIntro();
      };
      document.addEventListener("keydown", onKey);

      resetSession();
      render();
      startCamera();
      raf = requestAnimationFrame(loop);

      return {
        render,
        unmount() {
          dead = true;
          cameraKey += 1;
          cancelAnimationFrame(raf);
          clearInterval(tipTimer);
          clearInterval(exposureTimer);
          clearInterval(focusTimer);
          document.removeEventListener("visibilitychange", onVisible);
          document.removeEventListener("keydown", onKey);
          if (permissionStatus) permissionStatus.removeEventListener("change", recheck);
          // The last frame stays on screen while the stage fades out.
          stopCamera(true);
        },
      };
    },
  });
})();
