// Palm reading: RESULT stage (ResultScreen, c56) and sharing (tq6 share card).
// Top bar, the palm header (the close-up photo with its lines, or the saved
// palm map; the lines glow and shed sparks), a short essence, tabs for the
// lines, the hand's element and its mount, and the footer.
// Items fade up on one shared 1600 ms clock (a56/ow5/ff).

(() => {
  if (!window.Palm) return;

  const C = {
    bg: "#0E0C24",
    surface: "#1E1B3A",
    gold: "#E8C27A",
    goldLight: "#F2D497",
    cream: "#F3EEDD",
    muted: "#A39FC0",
    mint: "#8FD6C4",
  };
  const LINE_COLORS = { HEART: "#EFA3AE", HEAD: "#E8C27A", LIFE: "#8FD6C4", FATE: "#B9A4F2" };
  const LINE_ORDER = ["HEART", "HEAD", "LIFE", "FATE"];
  const SECTION_COLORS = { ELEMENT: "#E8C27A", HEART: "#EFA3AE", HEAD: "#E8C27A", LIFE: "#8FD6C4", FATE: "#B9A4F2", MOUNT: "#8FD6C4" };
  const SKELETON = [
    [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12],
    [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
  ];
  const SHARE_LINK = "https://app.adjust.com/258alz46";
  const SHARE_TEXT = (name) => `My palm says I'm ${name} ✋\n\nDownload the Horoscope Launcher to read yours 💫\n${SHARE_LINK}`;
  // Header strokes are the app's device px; this phone is 1080 px wide.
  const PX = 1 / 3;
  // The header frame's width: the 360 px phone less 2 x 20 padding.
  const BOX_W = 360 - 40;

  const reducedMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const fastOutSlowIn = cubicBezier(0.4, 0, 0.2, 1);
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const rgba = (hex, a) => {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
  };

  function cubicBezier(x1, y1, x2, y2) {
    const bx = (t) => 3 * x1 * t * (1 - t) ** 2 + 3 * x2 * t * t * (1 - t) + t ** 3;
    const by = (t) => 3 * y1 * t * (1 - t) ** 2 + 3 * y2 * t * t * (1 - t) + t ** 3;
    return (x) => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let lo = 0;
      let hi = 1;
      for (let i = 0; i < 30; i++) {
        const mid = (lo + hi) / 2;
        if (bx(mid) < x) lo = mid;
        else hi = mid;
      }
      return by((lo + hi) / 2);
    };
  }

  // Fallbacks for the few PalmDraw helpers, so the screen still works if
  // palm-draw.js failed to load (the lines are then simply not drawn).
  function setupCanvas(canvas, w, h) {
    if (window.PalmDraw && window.PalmDraw.setupCanvas) return window.PalmDraw.setupCanvas(canvas, w, h);
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }

  function coverMap(srcW, srcH, viewW, viewH) {
    if (window.PalmDraw && window.PalmDraw.cover) return window.PalmDraw.cover(srcW, srcH, viewW, viewH);
    const scale = Math.max(viewW / srcW, viewH / srcH);
    const dw = srcW * scale;
    const dh = srcH * scale;
    const ox = (viewW - dw) / 2;
    const oy = (viewH - dh) / 2;
    return { scale, dw, dh, ox, oy, map: (p) => ({ x: p.x * dw + ox, y: p.y * dh + oy }) };
  }

  // Every line of a PalmLines map, in insertion order (jl4 case 8/9).
  function drawLines(ctx, lines, faint, map, progress, width) {
    const D = window.PalmDraw;
    if (!D || !lines || progress <= 0) return;
    for (const [key, points] of Object.entries(lines)) {
      if (!points || points.length < 2 || !LINE_COLORS[key]) continue;
      const line = D.linePath(points, map);
      D.drawLine(ctx, line, LINE_COLORS[key], { progress, width, faint: faint.includes(key), fate: key === "FATE" });
    }
  }

  // n52.d: bones, then a halo and a core per landmark.
  function drawSkeleton(ctx, landmarks, map, a, { boneAlpha, boneWidth, dotR, dotAlpha }) {
    if (!landmarks || landmarks.length < 21) return;
    const P = landmarks.map((p) => map(p));
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineWidth = boneWidth;
    ctx.strokeStyle = rgba(C.goldLight, boneAlpha * a);
    ctx.beginPath();
    for (const [i, j] of SKELETON) {
      ctx.moveTo(P[i].x, P[i].y);
      ctx.lineTo(P[j].x, P[j].y);
    }
    ctx.stroke();
    const alpha = dotAlpha * a;
    for (const p of P) {
      ctx.fillStyle = rgba(C.goldLight, alpha * 0.3);
      ctx.beginPath();
      ctx.arc(p.x, p.y, dotR * 2.2, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = `rgba(255,255,255,${alpha})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, dotR, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  // Compose's default linear gradient runs corner to corner (top-left to
  // bottom-right); in CSS that is the angle of the box diagonal.
  const diagonalAngle = (w, h) => `${90 + (Math.atan2(h, w) * 180) / Math.PI}deg`;

  // "PALM MAP · READ 13 NOV 2026": d MMM yyyy in the device locale.
  function mapDate(ms) {
    const date = new Date(ms || Date.now());
    let parts = [];
    try {
      parts = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", year: "numeric" }).formatToParts(date);
    } catch {}
    const part = (type) => (parts.find((p) => p.type === type) || {}).value;
    const day = part("day") || String(date.getDate());
    const month = (part("month") || date.toLocaleString("en", { month: "short" })).replace(/\.$/, "");
    const year = part("year") || String(date.getFullYear());
    return `${day} ${month} ${year}`;
  }

  // The saved palm (SavedPalm, ge6) behind a "See your reading" view.
  function savedPalm(Palm) {
    const person = Palm.selected();
    const hand = Palm.state.features && Palm.state.features.hand;
    if (!person || !Array.isArray(person.palms)) return null;
    return person.palms.find((p) => p.hand === hand) || [...person.palms].sort((a, b) => b.lastScan - a.lastScan)[0] || null;
  }

  // --- Share card (tq6.c): 1080 x 1350 ----------------------------------------

  let skyImage = null;
  function loadSky() {
    if (!skyImage) {
      skyImage = new Promise((resolve) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => resolve(null);
        img.src = "assets/palm/palm_bg_night.webp";
      });
    }
    return skyImage;
  }

  function drawCover(ctx, img, iw, ih, x, y, w, h) {
    const s = Math.max(w / iw, h / ih);
    const sw = w / s;
    const sh = h / s;
    ctx.drawImage(img, (iw - sw) / 2, (ih - sh) / 2, sw, sh, x, y, w, h);
  }

  function spacedText(ctx, text, x, y, spacing) {
    if ("letterSpacing" in ctx) {
      ctx.letterSpacing = `${spacing}px`;
      // Canvas adds the spacing after every glyph; shift so the text stays centred.
      ctx.fillText(text, x + spacing / 2, y);
      ctx.letterSpacing = "0px";
      return;
    }
    const chars = [...text];
    const widths = chars.map((ch) => ctx.measureText(ch).width);
    const total = widths.reduce((a, b) => a + b, 0) + spacing * chars.length;
    const align = ctx.textAlign;
    ctx.textAlign = "left";
    let cx = x - total / 2 + spacing / 2;
    chars.forEach((ch, i) => {
      ctx.fillText(ch, cx, y);
      cx += widths[i] + spacing;
    });
    ctx.textAlign = align;
  }

  async function renderShareCard({ landmarks, lines, faint, aspect, reading, bitmap }) {
    await Promise.all([
      document.fonts.load('600 96px "Palm Cormorant"'),
      document.fonts.load('600 38px "Palm DM Sans"'),
      document.fonts.load('400 34px "Palm DM Sans"'),
    ]).catch(() => {});
    const sky = await loadSky();
    const W = 1080;
    const H = 1350;
    const canvas = document.createElement("canvas");
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext("2d");

    ctx.fillStyle = C.bg;
    ctx.fillRect(0, 0, W, H);
    if (sky) drawCover(ctx, sky, sky.naturalWidth, sky.naturalHeight, 0, 0, W, H);

    const fa = clamp(aspect || 0.8, 0.5, 1.2);
    const FH = Math.min(760 / fa, 800);
    const bottom = 150 + FH;

    let g = ctx.createRadialGradient(540, FH / 2 + 150, 0, 540, FH / 2 + 150, 700);
    g.addColorStop(0, rgba(C.mint, 0.14));
    g.addColorStop(1, rgba(C.mint, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    g = ctx.createLinearGradient(0, 150, 0, bottom);
    g.addColorStop(0, C.surface);
    g.addColorStop(1, C.bg);
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.roundRect(160, 150, 760, FH, 48);
    ctx.fill();

    ctx.save();
    ctx.beginPath();
    ctx.rect(160, 150, 760, FH);
    ctx.clip();
    ctx.translate(160, 150);
    g = ctx.createRadialGradient(380, FH / 2, 0, 380, FH / 2, FH * 0.6);
    g.addColorStop(0, rgba(C.mint, 0.16));
    g.addColorStop(1, rgba(C.mint, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 760, FH);
    let map;
    if (bitmap) {
      const bw = bitmap.width;
      const bh = bitmap.height;
      drawCover(ctx, bitmap, bw, bh, 0, 0, 760, FH);
      const r = Math.max(760, FH) * 0.7;
      g = ctx.createRadialGradient(380, FH / 2, 0, 380, FH / 2, r);
      g.addColorStop(0, rgba(C.bg, 0));
      g.addColorStop(1, rgba(C.bg, 0.75));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, 760, FH);
      ctx.fillStyle = rgba(C.bg, 0.2);
      ctx.fillRect(0, 0, 760, FH);
      map = coverMap(bw, bh, 760, FH);
    } else {
      map = coverMap(fa * 1000, 1000, 760, FH);
      drawSkeleton(ctx, landmarks, map.map, 1, { boneAlpha: 0.3, boneWidth: 3, dotR: 4, dotAlpha: 0.45 });
    }
    drawLines(ctx, lines, faint || [], map.map, 1, 9);
    ctx.restore();

    g = ctx.createLinearGradient(160, 150, 920, bottom);
    g.addColorStop(0, C.goldLight);
    g.addColorStop(0.5, rgba(C.gold, 0.3));
    g.addColorStop(1, C.goldLight);
    ctx.strokeStyle = g;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.roundRect(160, 150, 760, FH, 48);
    ctx.stroke();

    ctx.textAlign = "center";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = C.mint;
    ctx.font = '600 30px "Palm DM Sans", sans-serif';
    spacedText(ctx, "MY PALM READING", 540, 100, 30 * 0.18);
    ctx.fillStyle = C.goldLight;
    ctx.font = '400 30px "Palm DM Sans", sans-serif';
    ctx.fillText("✦", 194, 202);
    ctx.fillText("✦", 886, 202);

    let size = 96;
    ctx.font = `600 ${size}px "Palm Cormorant", serif`;
    const width = ctx.measureText(reading.archetype).width;
    if (width > 980) {
      size = Math.floor((size * 980) / width);
      ctx.font = `600 ${size}px "Palm Cormorant", serif`;
    }
    ctx.fillStyle = C.cream;
    ctx.fillText(reading.archetype, 540, bottom + 130);

    ctx.fillStyle = C.gold;
    ctx.font = '600 38px "Palm DM Sans", sans-serif';
    spacedText(ctx, reading.strengths.join("  ·  "), 540, bottom + 200, 38 * 0.04);

    ctx.fillStyle = C.muted;
    ctx.font = '400 34px "Palm DM Sans", sans-serif';
    ctx.fillText("What does your palm say?", 540, 1280);
    return canvas;
  }

  const toJpeg = (canvas) => new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));

  // Tab icons, one per section, drawn on a 24 grid in the section's colour.
  const ICONS = {
    // A heart, with the heart line curving through it.
    HEART: '<path d="M12 20.2s-7.6-4.6-7.6-10.3A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.6 2.5c0 5.7-7.6 10.3-7.6 10.3Z" fill="currentColor" fill-opacity=".18"/><path d="M12 20.2s-7.6-4.6-7.6-10.3A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.6 2.5c0 5.7-7.6 10.3-7.6 10.3Z"/><path d="M6.6 12.6c2.2-1.3 4.8-.2 6.6-1.2s2.6-2.3 4.4-2.1" stroke-opacity=".75"/>',
    // A head in profile, with a spark of thought.
    HEAD: '<path d="M9.5 21v-3.2H7.4a1.4 1.4 0 0 1-1.4-1.4v-2.2l-1.6-.5 1.6-3.1A6.6 6.6 0 0 1 12.6 4a6.4 6.4 0 0 1 6.4 6.5 6.5 6.5 0 0 1-2.6 5.2V21" fill="currentColor" fill-opacity=".14"/><path d="M9.5 21v-3.2H7.4a1.4 1.4 0 0 1-1.4-1.4v-2.2l-1.6-.5 1.6-3.1A6.6 6.6 0 0 1 12.6 4a6.4 6.4 0 0 1 6.4 6.5 6.5 6.5 0 0 1-2.6 5.2V21"/><path d="M13 7.6l.7 1.6 1.6.7-1.6.7-.7 1.6-.7-1.6-1.6-.7 1.6-.7Z" fill="currentColor" stroke-width="1"/>',
    // A sprout: growth and vitality.
    LIFE: '<path d="M12 21v-8.5"/><path d="M12 13c0-4.2-2.7-6.6-7.2-6.6 0 4.4 2.8 6.6 7.2 6.6Z" fill="currentColor" fill-opacity=".18"/><path d="M12 13c0-4.2-2.7-6.6-7.2-6.6 0 4.4 2.8 6.6 7.2 6.6Z"/><path d="M12 10.6c0-3.7 2.4-6.6 7.2-6.6 0 4.2-2.6 6.6-7.2 6.6Z" fill="currentColor" fill-opacity=".18"/><path d="M12 10.6c0-3.7 2.4-6.6 7.2-6.6 0 4.2-2.6 6.6-7.2 6.6Z"/><path d="M8 21h8"/>',
    // A path rising to a star: destiny.
    FATE: '<path d="M6 21c1.6-3.2 5.6-3.4 6-7s-2.6-4-1.4-6.6" stroke-dasharray="1.6 2.4"/><path d="M15.5 3l1.1 2.9 2.9 1.1-2.9 1.1-1.1 2.9-1.1-2.9-2.9-1.1 2.9-1.1Z" fill="currentColor" fill-opacity=".3"/>',
    // The four hand elements.
    EARTH: '<path d="M2.5 19.5 9 8.5l3.4 5.4 2.4-3.4 6.7 9Z" fill="currentColor" fill-opacity=".16"/><path d="M2.5 19.5 9 8.5l3.4 5.4 2.4-3.4 6.7 9Z"/><path d="M7.4 11.2 9 12.4l1.4-1.6"/>',
    AIR: '<path d="M3 9h10.5a2.6 2.6 0 1 0-2.6-2.6"/><path d="M3 13h15a2.8 2.8 0 1 1-2.8 2.8"/><path d="M3 17h7"/>',
    FIRE: '<path d="M12 21.5c-3.9 0-6.5-2.6-6.5-6 0-3.7 3.2-5.3 3.6-9.5 2.4 1.4 3.7 3.4 3.9 5.8 1-.6 1.7-1.6 2-2.8 1.9 1.8 3.5 4 3.5 6.5 0 3.4-2.6 6-6.5 6Z" fill="currentColor" fill-opacity=".18"/><path d="M12 21.5c-3.9 0-6.5-2.6-6.5-6 0-3.7 3.2-5.3 3.6-9.5 2.4 1.4 3.7 3.4 3.9 5.8 1-.6 1.7-1.6 2-2.8 1.9 1.8 3.5 4 3.5 6.5 0 3.4-2.6 6-6.5 6Z"/><path d="M12 21.5a2.6 2.6 0 0 1-2.6-2.7c0-1.8 1.6-2.6 2.2-4.3 1.8 1.1 3 2.6 3 4.3a2.6 2.6 0 0 1-2.6 2.7Z"/>',
    WATER: '<path d="M12 21.2a6 6 0 0 1-6-6c0-4.4 6-11.4 6-11.4s6 7 6 11.4a6 6 0 0 1-6 6Z" fill="currentColor" fill-opacity=".18"/><path d="M12 21.2a6 6 0 0 1-6-6c0-4.4 6-11.4 6-11.4s6 7 6 11.4a6 6 0 0 1-6 6Z"/><path d="M9 15.4a3 3 0 0 0 3 3" stroke-opacity=".75"/>',
    // A ringed planet over a rise in the palm: the mount.
    MOUNT: '<circle cx="12" cy="9.5" r="4.2" fill="currentColor" fill-opacity=".18"/><circle cx="12" cy="9.5" r="4.2"/><path d="M6.2 11.6c-2 1.4-2.5 2.6-1.6 3 1.4.6 5.4-.8 8.8-3s5.4-4.4 4.6-5.2c-.5-.5-1.8-.2-3.4.6"/><path d="M3 20.5c2.6-2.4 5.4-3.4 9-3.4s6.4 1 9 3.4"/>',
  };

  function icon(kind, features, size) {
    const key = kind === "ELEMENT" ? features.element || "EARTH" : kind;
    const body = ICONS[key] || ICONS.MOUNT;
    return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
  }

  // --- The stage -------------------------------------------------------------

  Palm.registerStage("result", {
    mount(stageEl, Palm) {
      const { el, svg, state } = Palm;
      const reading = state.reading;
      const generation = state.generation;
      const shot = !state.savedReading && state.closeUp ? state.closeUp : null;
      const saved = state.savedReading ? savedPalm(Palm) : null;
      const palmMap = !shot && saved && saved.map && saved.map.landmarks ? saved.map : null;
      const legendSource = shot || palmMap;
      const rafs = new Set();
      let alive = true;
      let sharing = false;
      let toastTimer = 0;

      const view = el("div", { class: "palm-result" });
      const list = el("div", { class: "palm-result__list" });
      const toast = el("div", { class: "palm-result__toast", role: "status", "aria-live": "polite" });
      view.append(list, el("div", { class: "palm-result__scrim", "aria-hidden": "true" }), toast);
      stageEl.append(view);

      if (!reading) {
        list.append(topBar());
        return { unmount() {} };
      }

      // Stagger index k: delay min(k * 128, 960) ms, 640 ms fade-up from +28 px.
      let k = 0;
      const staggered = (node) => {
        node.classList.add("palm-result__item");
        node.style.setProperty("--d", `${Math.min(k * 128, 960)}ms`);
        k += 1;
        return node;
      };

      // The palm frame (its lines glow and shed sparks), a short essence, then
      // one tab per section: picking a line's tab lights that line up.
      let fx = null;
      list.append(topBar());
      if (shot) list.append(staggered(photoHeader(shot)));
      else if (palmMap) list.append(staggered(mapHeader(palmMap, saved.lastScan)));
      list.append(staggered(essence()));
      list.append(staggered(sectionTabs(legendSource)));
      list.append(footer());

      // --- Parts ---

      function topBar() {
        return el(
          "div",
          { class: "palm-result__top" },
          el(
            "button",
            { type: "button", class: "palm-result__icon palm-result__back", "aria-label": "Back", onclick: () => Palm.close() },
            svg(`<svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M7.825 13L13.425 18.6L12 20L4 12L12 4L13.425 5.4L7.825 11H20V13H7.825Z"/></svg>`)
          ),
          // Back and Share only, like the tarot reading's top bar.
          el(
            "button",
            { type: "button", class: "palm-result__share", onclick: share },
            svg(`<svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><circle cx="18" cy="5" r="2.5" /><circle cx="6" cy="12" r="2.5" /><circle cx="18" cy="19" r="2.5" /><path d="M8.2 10.8l7.6-4.4M8.2 13.2l7.6 4.4" /></svg>`),
            "Share"
          )
        );
      }

      function corners(which) {
        return which.map((pos) => el("span", { class: `palm-result__star palm-result__star--${pos}`, "aria-hidden": "true", text: "✦" }));
      }

      // Runs the 1600 ms FastOutSlowIn line reveal, calling draw(progress).
      function reveal(draw) {
        if (reducedMotion()) {
          draw(1);
          return;
        }
        const start = performance.now();
        const step = (now) => {
          if (!alive) return;
          const p = fastOutSlowIn(clamp((now - start) / 1600, 0, 1));
          draw(p);
          if (p < 1) {
            const id = requestAnimationFrame(step);
            rafs.add(id);
          }
        };
        draw(0);
        rafs.add(requestAnimationFrame(step));
      }

      function photoHeader(palmShot) {
        const bw = palmShot.width || palmShot.image.width;
        const bh = palmShot.height || palmShot.image.height;
        const w = BOX_W;
        const h = Math.round((w * bh) / bw);
        const photo = el("canvas", { class: "palm-result__canvas", role: "img", "aria-label": "Your palm" });
        const overlay = el("canvas", { class: "palm-result__canvas", "aria-hidden": "true" });
        const pctx = setupCanvas(photo, w, h);
        const map = coverMap(bw, bh, w, h);
        pctx.drawImage(palmShot.image, map.ox, map.oy, map.dw, map.dh);
        const g = pctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, Math.max(w, h) * 0.7);
        g.addColorStop(0, rgba(C.bg, 0));
        g.addColorStop(1, rgba(C.bg, 0.75));
        pctx.fillStyle = g;
        pctx.fillRect(0, 0, w, h);
        pctx.fillStyle = rgba(C.bg, 0.2);
        pctx.fillRect(0, 0, w, h);

        const octx = setupCanvas(overlay, w, h);
        fx = lineFx(octx, w, h, palmShot.lines, palmShot.faint || [], map.map, 6 * PX);
        return el(
          "div",
          { class: "palm-result__pad" },
          el(
            "div",
            { class: "palm-result__frame", style: `aspect-ratio:${bw}/${bh};--border-angle:${diagonalAngle(w, h)}` },
            photo,
            overlay,
            corners(["tl", "tr", "bl", "br"])
          )
        );
      }

      function mapHeader(palm, lastScan) {
        const aspect = clamp(palm.aspect || 0.8, 0.5, 1.2);
        const w = BOX_W;
        const h = Math.round(w / aspect);
        const canvas = el("canvas", { class: "palm-result__canvas", role: "img", "aria-label": "Your palm map" });
        const overlay = el("canvas", { class: "palm-result__canvas", "aria-hidden": "true" });
        const ctx = setupCanvas(canvas, w, h);
        const map = coverMap(aspect * 1000, 1000, w, h);
        reveal((a) => {
          ctx.clearRect(0, 0, w, h);
          const g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, Math.max(w, h) * 0.6);
          g.addColorStop(0, rgba(C.mint, 0.16));
          g.addColorStop(1, rgba(C.mint, 0));
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, w, h);
          drawSkeleton(ctx, palm.landmarks, map.map, a, { boneAlpha: 0.22, boneWidth: 3 * PX, dotR: 2.5 * PX, dotAlpha: 0.35 });
        });
        fx = lineFx(setupCanvas(overlay, w, h), w, h, palm.lines, palm.faint || [], map.map, 6 * PX);
        return el(
          "div",
          { class: "palm-result__pad" },
          el(
            "div",
            { class: "palm-result__frame palm-result__frame--map", style: `aspect-ratio:${aspect};--border-angle:${diagonalAngle(w, h)}` },
            canvas,
            overlay,
            corners(["tl", "tr"]),
            el("span", { class: "palm-result__map-pill", text: `PALM MAP · READ ${mapDate(lastScan)}`.toUpperCase() })
          )
        );
      }

      // The lines, alive: each one draws on (1600 ms), then breathes an aura
      // and sheds small sparks of its own colour. setFocus(key) brings one
      // line forward (brighter, more sparks) and dims the others.
      function lineFx(ctx, w, h, lines, faint, map, width) {
        const D = window.PalmDraw;
        const keys = LINE_ORDER.filter((key) => lines && lines[key] && lines[key].length > 1);
        const paths = Object.fromEntries(keys.map((key) => [key, D.linePath(lines[key], map)]));
        const alpha = Object.fromEntries(keys.map((key) => [key, 1]));
        const phase = { HEART: 0, HEAD: 1.7, LIFE: 3.1, FATE: 4.4 };
        const sparks = [];
        let focus = null;
        let last = performance.now();
        const start = last;
        const still = reducedMotion();

        function spawn(key, now) {
          const line = paths[key];
          const d = Math.random() * line.length;
          const p = D.pointAt(line, d);
          const q = D.pointAt(line, Math.min(line.length, d + 2));
          let nx = -(q.y - p.y);
          let ny = q.x - p.x;
          const n = Math.hypot(nx, ny) || 1;
          const side = Math.random() < 0.5 ? -1 : 1;
          nx = (nx / n) * side;
          ny = (ny / n) * side;
          const speed = 5 + Math.random() * 14;
          sparks.push({
            key,
            x: p.x + nx * 2,
            y: p.y + ny * 2,
            vx: nx * speed,
            vy: ny * speed - 6,
            born: now,
            life: 1100 + Math.random() * 1500,
            r: 0.5 + Math.random() * 1.1,
          });
        }

        function frame(now) {
          if (!alive) return;
          const dt = Math.min(64, now - last) / 1000;
          last = now;
          const t = now / 1000;
          const p = still ? 1 : fastOutSlowIn(clamp((now - start) / 1600, 0, 1));
          ctx.clearRect(0, 0, w, h);

          for (const key of keys) {
            const target = !focus || !paths[focus] || focus === key ? 1 : 0.28;
            alpha[key] += (target - alpha[key]) * Math.min(1, dt * 8);
            const color = LINE_COLORS[key];
            const line = paths[key];
            const lift = focus === key ? 1.6 : 1;
            const pulse = still ? 0.5 : 0.5 + 0.5 * Math.sin(t * 2.2 + phase[key]);

            // Aura: a soft, breathing glow along the line.
            ctx.save();
            ctx.globalCompositeOperation = "lighter";
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.setLineDash([line.length * p, line.length + 1]);
            ctx.strokeStyle = rgba(color, alpha[key] * (0.1 + 0.1 * pulse) * lift);
            ctx.shadowColor = rgba(color, alpha[key] * 0.9);
            ctx.shadowBlur = (10 + 8 * pulse) * lift;
            ctx.lineWidth = width * (6 + 3 * pulse);
            ctx.stroke(line.path);
            ctx.restore();

            D.drawLine(ctx, line, color, { progress: p, width, alpha: alpha[key], faint: faint.includes(key), fate: key === "FATE" });

            // Sparks once the line is mostly drawn.
            if (!still && p > 0.6) {
              const rate = (focus === key ? 26 : 9) * alpha[key];
              let n = rate * dt;
              while (n > 0 && sparks.length < 260) {
                if (n >= 1 || Math.random() < n) spawn(key, now);
                n -= 1;
              }
            }
          }

          ctx.save();
          ctx.globalCompositeOperation = "lighter";
          for (let i = sparks.length - 1; i >= 0; i--) {
            const sp = sparks[i];
            const age = (now - sp.born) / sp.life;
            if (age >= 1) {
              sparks.splice(i, 1);
              continue;
            }
            sp.x += sp.vx * dt;
            sp.y += sp.vy * dt;
            sp.vx *= 0.985;
            sp.vy = sp.vy * 0.985 - 4 * dt;
            const fade = Math.sin(Math.PI * age) * alpha[sp.key];
            const color = LINE_COLORS[sp.key];
            ctx.fillStyle = rgba(color, 0.22 * fade);
            ctx.beginPath();
            ctx.arc(sp.x, sp.y, sp.r * 3.2, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = `rgba(255,255,255,${0.85 * fade})`;
            ctx.beginPath();
            ctx.arc(sp.x, sp.y, sp.r * 0.8, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = rgba(color, 0.9 * fade);
            ctx.beginPath();
            ctx.arc(sp.x, sp.y, sp.r, 0, Math.PI * 2);
            ctx.fill();
          }
          ctx.restore();

          if (!still || Object.values(alpha).some((a) => Math.abs(a - (focus ? 0.28 : 1)) > 0.01 && Math.abs(a - 1) > 0.01)) {
            rafs.add(requestAnimationFrame(frame));
          }
        }

        rafs.add(requestAnimationFrame(frame));
        return {
          setFocus(key) {
            focus = key;
            if (still) rafs.add(requestAnimationFrame(frame));
          },
        };
      }

      // Below the frame: who this palm says you are, in a few words.
      function essence() {
        const elementTitle = reading.sections.find((s) => s.kind === "ELEMENT").title;
        return el(
          "div",
          { class: "palm-result__essence" },
          el("p", { class: "palm-result__label", text: `✦ ${Palm.possessive()} palm · ${elementTitle} ✦`.toUpperCase() }),
          el("h1", { class: "palm-result__archetype", text: reading.archetype }),
          el("p", { class: "palm-result__summary", text: reading.summary })
        );
      }

      // Tabs: the lines first, then the hand's element and its mount.
      function sectionTabs(source) {
        const order = ["HEART", "HEAD", "LIFE", "FATE", "ELEMENT", "MOUNT"];
        const sections = order.map((kind) => reading.sections.find((s) => s.kind === kind)).filter(Boolean);
        const faint = (source && source.faint) || [];
        const features = state.features || {};
        const tabs = el("div", { class: "palm-tabs__row", role: "tablist", "aria-label": "Your palm, line by line" });
        const panel = el("div", { class: "palm-tabs__panel", role: "tabpanel" });
        const buttons = [];

        const label = (section) =>
          section.kind === "MOUNT" ? "Mount" : section.kind === "ELEMENT" ? section.title.replace(" Hand", "") : section.title.replace(" line", "");

        function show(index, animate = true) {
          const section = sections[index];
          const color = SECTION_COLORS[section.kind] || C.gold;
          buttons.forEach((b, i) => {
            b.setAttribute("aria-selected", String(i === index));
            b.tabIndex = i === index ? 0 : -1;
          });
          if (fx) fx.setFocus(LINE_COLORS[section.kind] ? section.kind : null);
          const isFaint = faint.includes(section.kind);
          const card = el(
            "section",
            { class: "palm-tabs__card", style: `--c:${color}` },
            el(
              "div",
              { class: "palm-tabs__head" },
              el("span", { class: "palm-tabs__badge", "aria-hidden": "true" }, svg(icon(section.kind, features, 30))),
              el(
                "div",
                {},
                el("h2", { class: "palm-tabs__title", text: section.title }),
                isFaint && el("p", { class: "palm-tabs__faint", text: "Faint on your palm" })
              )
            ),
            el(
              "div",
              { class: "palm-tabs__traits" },
              section.trait.split(" · ").map((t) => el("span", { class: "palm-tabs__trait", text: t }))
            ),
            el("p", { class: "palm-tabs__body", text: section.body }),
            section.kind === "ELEMENT" && el("p", { class: "palm-tabs__note", text: reading.handMeaning })
          );
          if (animate) card.classList.add("is-entering");
          panel.replaceChildren(card);
        }

        sections.forEach((section, i) => {
          const color = SECTION_COLORS[section.kind] || C.gold;
          const button = el(
            "button",
            { type: "button", class: "palm-tabs__tab", role: "tab", style: `--c:${color}`, onclick: () => show(i) },
            el("span", { class: "palm-tabs__icon", "aria-hidden": "true" }, svg(icon(section.kind, features, 18))),
            label(section)
          );
          button.addEventListener("keydown", (event) => {
            const step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
            if (!step) return;
            event.preventDefault();
            const next = (i + step + sections.length) % sections.length;
            show(next);
            buttons[next].focus();
            buttons[next].scrollIntoView({ block: "nearest", inline: "nearest" });
          });
          buttons.push(button);
          tabs.append(button);
        });
        show(0, false);
        return el("div", { class: "palm-tabs" }, tabs, panel);
      }

      function footer() {
        return el(
          "div",
          { class: "palm-result__footer" },
          el("button", { type: "button", class: "palm-result__again", text: "Read another palm", onclick: () => Palm.backToIntro() }),
          el("button", { type: "button", class: "palm-result__home", text: "Back to horoscope", onclick: () => Palm.close() }),
          el("p", { class: "palm-result__disclaimer", text: "Palm reading is for entertainment and reflection only." })
        );
      }

      // --- Share ---

      function showToast(text) {
        toast.textContent = text;
        toast.classList.add("is-shown");
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => toast.classList.remove("is-shown"), 2600);
      }

      async function share() {
        if (sharing || !state.reading || generation !== state.generation) return;
        sharing = true;
        const text = SHARE_TEXT(reading.archetype);
        try {
          let blob = null;
          try {
            const card = shot
              ? await renderShareCard({ landmarks: shot.landmarks, lines: shot.lines, faint: shot.faint, aspect: shot.width / shot.height, reading, bitmap: shot.image })
              : await renderShareCard({
                  landmarks: palmMap && palmMap.landmarks,
                  lines: palmMap && palmMap.lines,
                  faint: palmMap && palmMap.faint,
                  aspect: palmMap ? palmMap.aspect : 0.8,
                  reading,
                  bitmap: null,
                });
            blob = await toJpeg(card);
          } catch (error) {
            console.error("Palm: share image failed", error);
          }
          const file = blob && new File([blob], "palm_reading.jpg", { type: "image/jpeg" });
          if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
            await navigator.share({ files: [file], text });
          } else if (!file && navigator.share) {
            await navigator.share({ text });
          } else {
            if (file) {
              const url = URL.createObjectURL(file);
              const a = el("a", { href: url, download: "palm_reading.jpg" });
              document.body.append(a);
              a.click();
              a.remove();
              setTimeout(() => URL.revokeObjectURL(url), 4000);
            }
            let copied = false;
            try {
              await navigator.clipboard.writeText(text);
              copied = true;
            } catch {}
            if (alive) showToast(file ? (copied ? "Image saved · text copied" : "Image saved") : copied ? "Text copied" : "Couldn't share");
          }
        } catch (error) {
          if (error && error.name !== "AbortError") console.error("Palm: share failed", error);
        } finally {
          sharing = false;
        }
      }

      return {
        unmount() {
          alive = false;
          for (const id of rafs) cancelAnimationFrame(id);
          rafs.clear();
          clearTimeout(toastTimer);
        },
      };
    },
  });
})();
