// Palm reading, SCANNING: the scan animation over the captured photo
// (ScanAnimationScreen, ye6/xe6 in the app).
//
// One clock t runs 0 -> 1 over 6.5 s (linear). A gold line sweeps down the
// hand and back up, the landmarks light up, the skeleton draws itself, then
// the four palm lines are traced one after another with a label at each end.
// 250 ms after t reaches 1 it calls Palm.onScanAnimationDone().
//
// The app draws this canvas in device pixels; its constants are written here
// as px(n) = n / 3 CSS px (a 1080 px wide phone).

(() => {
  if (!window.Palm || !window.PalmDraw) return;
  const { LINE_COLORS, LINE_ORDER, LINE_LABELS, SKELETON, rgba, cover, linePath, pointAt, drawLine, setupCanvas } = window.PalmDraw;

  const DURATION = 6500;
  const DONE_DELAY = 250;
  const px = (n) => n / 3;
  const ramp = (t, a, b) => Math.max(0, Math.min(1, (t - a) / (b - a)));

  const BG = "#0E0C24";
  const GOLD = "#E8C27A";
  const GOLD_LIGHT = "#F2D497";
  const LILAC = "#D9D4EC";

  const WINDOWS = { HEART: [0.36, 0.52], HEAD: [0.5, 0.66], LIFE: [0.64, 0.8], FATE: [0.78, 0.94] };

  const CAPTIONS = [
    [0.3, "Detecting palm contours…"],
    [0.36, "Mapping your hand…"],
    [0.52, "Tracing your heart line…"],
    [0.66, "Reading your head line…"],
    [0.8, "Following your life line…"],
    [0.94, "Uncovering your fate line…"],
    [Infinity, "Scan complete"],
  ];
  const captionFor = (t) => CAPTIONS.find(([end]) => t < end)[1];

  // Kotlin Random(7): [x frac, y phase, size 2..6 px, twinkle phase, speed 1..3].
  const PARTICLES = [[0.95755,0.00277,4.19188,2.33967,1.72684],[0.70417,0.87889,5.28548,0.1487,2.1726],[0.44791,0.35115,5.80562,5.53936,1.40623],[0.63644,0.38552,2.92261,4.87749,2.6932],[0.14697,0.59337,4.7717,1.89817,2.71103],[0.2154,0.70516,2.38712,3.59981,2.35136],[0.31043,0.23354,4.39781,1.60215,1.61783],[0.39018,0.14254,5.3036,3.67582,1.59634],[0.3886,0.06056,5.81384,1.3367,2.26136],[0.90387,0.66448,4.19736,2.46862,2.08455],[0.42036,0.4229,2.22836,1.69918,2.20047],[0.46231,0.86642,3.93202,0.82806,1.47394],[0.1021,0.35276,4.1528,5.53773,1.84901],[0.76124,0.04077,4.37965,6.19358,2.93336],[0.68961,0.50711,3.05711,0.16303,1.80335],[0.8474,0.17025,3.32442,2.02443,1.43796],[0.3655,0.61936,5.60309,1.25679,1.98481],[0.02309,0.94571,3.79291,5.4792,2.4041],[0.70151,0.81135,4.38054,5.73855,1.3568],[0.19188,0.9783,3.23992,3.79226,2.08893],[0.5838,0.83441,2.44948,2.36715,1.99247],[0.09213,0.04172,3.19267,0.81455,1.81649],[0.08495,0.04327,4.51169,3.14492,1.52943],[0.0117,0.035,4.46368,4.20733,2.15066],[0.24559,0.62492,5.63934,1.48234,1.59583],[0.60385,0.23028,3.02664,4.80548,2.36362],[0.87547,0.17574,5.87733,3.17953,1.35643],[0.56095,0.36413,4.13104,2.52077,1.30514],[0.9641,0.04587,4.52161,5.53484,1.91926],[0.20641,0.264,2.12037,0.4163,2.02082],[0.87085,0.20452,5.33619,5.1251,2.39479],[0.28596,0.45543,5.0744,1.73203,2.71417],[0.26936,0.88612,4.86579,2.68027,2.60387],[0.76143,0.38364,2.77855,3.04529,1.10511],[0.24491,0.51557,5.97047,5.0397,1.68122],[0.18638,0.14971,4.01454,5.19234,2.81804],[0.73153,0.59006,2.66958,3.16932,2.37355],[0.66598,0.18546,2.08143,4.37557,2.82071],[0.3277,0.8104,2.45138,5.8854,1.31503],[0.95584,0.0959,2.27557,4.97516,2.86551]];

  // Labels: Roboto Bold 13sp, laid out by Compose's TextMeasurer (no extra
  // line height, so the box is Roboto's ascent + descent).
  const LABEL_FONT = 'bold 13px Roboto, "Helvetica Neue", Arial, sans-serif';
  const LABEL_ASCENT = 13 * (1900 / 2048);
  const LABEL_HEIGHT = 13 * (2400 / 2048);

  function circle(ctx, x, y, r, fill) {
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = fill;
    ctx.fill();
  }

  function segmentLine(ctx, x1, y1, x2, y2, width, style, cap = "butt") {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.lineWidth = width;
    ctx.strokeStyle = style;
    ctx.lineCap = cap;
    ctx.stroke();
  }

  window.Palm.registerStage("scanning", {
    mount(stageEl, Palm) {
      const shot = Palm.state.frame;
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

      const photo = Palm.el("canvas", { class: "palm-scan__photo", "aria-hidden": "true" });
      const overlay = Palm.el("canvas", { class: "palm-scan__canvas", "aria-hidden": "true" });
      const statusBox = Palm.el("div", { class: "palm-scan__status", role: "status", "aria-live": "polite" });
      const bar = Palm.el("canvas", {
        class: "palm-scan__bar",
        role: "progressbar",
        "aria-label": "Scan progress",
        "aria-valuemin": "0",
        "aria-valuemax": "100",
      });
      stageEl.append(
        Palm.el("div", { class: "palm-scan" }, photo, overlay, Palm.el("div", { class: "palm-scan__bottom" }, statusBox, bar))
      );

      let W = 0;
      let H = 0;
      let ctx = null;
      let barCtx = null;
      let barW = 0;
      let geo = null; // landmark screen points, bbox and line paths

      function layout() {
        W = stageEl.clientWidth || 360;
        H = stageEl.clientHeight || 780;
        const photoCtx = setupCanvas(photo, W, H);
        ctx = setupCanvas(overlay, W, H);
        barW = (W - 48) * 0.7; // fillMaxWidth(0.7f) inside the 24dp padding
        barCtx = setupCanvas(bar, barW, 6);
        geo = null;
        if (!shot || !shot.image) return;
        const m = cover(shot.width, shot.height, W, H);
        photoCtx.fillStyle = BG;
        photoCtx.fillRect(0, 0, W, H);
        photoCtx.drawImage(shot.image, m.ox, m.oy, m.dw, m.dh);
        const pts = (shot.landmarks || []).map(m.map);
        if (!pts.length) return;
        const xs = pts.map((p) => p.x);
        const ys = pts.map((p) => p.y);
        const lines = {};
        for (const key of LINE_ORDER) {
          const raw = shot.lines && shot.lines[key];
          if (raw && raw.length > 1) lines[key] = { line: linePath(raw, m.map), end: m.map(raw[raw.length - 1]) };
        }
        geo = {
          pts,
          top: Math.min(...ys) - px(40),
          bottom: Math.max(...ys) + px(40),
          left: Math.min(...xs) - px(40),
          right: Math.max(...xs) + px(40),
          lines,
          faint: new Set(shot.faint || []),
        };
      }

      function drawScene(t) {
        ctx.clearRect(0, 0, W, H);
        if (!geo) return;
        const { pts, top, bottom, left, right, lines, faint } = geo;

        // (1) the photo dims from 25% to 50% while the line sweeps down
        ctx.fillStyle = rgba(BG, 0.25 + ramp(t, 0, 0.3) * 0.25);
        ctx.fillRect(0, 0, W, H);

        // (2) the sweep: down over 0..0.3, back up (fading) over 0.3..0.42
        const a1 = ramp(t, 0, 0.3);
        const a2 = ramp(t, 0.3, 0.42);
        const y = t < 0.3 ? top + (bottom - top) * a1 : bottom - (bottom - top) * a2;
        const k = t < 0.3 ? 1 : (1 - a2) * 0.6;
        if (k > 0.01) {
          const g = ctx.createLinearGradient(0, y - px(140), 0, y + px(42));
          g.addColorStop(0, rgba(GOLD, 0));
          g.addColorStop(0.5, rgba(GOLD, k * 0.35));
          g.addColorStop(1, rgba(GOLD, 0));
          ctx.fillStyle = g;
          ctx.fillRect(0, y - px(140), W, px(182));
          segmentLine(ctx, 0, y, W, y, px(3), rgba(GOLD_LIGHT, k));
          segmentLine(ctx, W * 0.15, y, W * 0.85, y, px(1.5), rgba("#FFFFFF", 0.8 * k));
        }

        // (3) the skeleton, edge by edge, and the landmarks the line has passed
        if (pts.length >= 21) {
          const skelAlpha = (1 - ramp(t, 0.85, 1) * 0.5) * 0.55;
          const edges = Math.floor(21 * ramp(t, 0.12, 0.38));
          for (let i = 0; i < edges; i++) {
            const [a, b] = SKELETON[i];
            segmentLine(ctx, pts[a].x, pts[a].y, pts[b].x, pts[b].y, px(3), rgba(GOLD, skelAlpha), "round");
          }
          const ref = t < 0.3 ? y : bottom + px(100);
          for (const p of pts) {
            const a = Math.max(0, Math.min(1, (ref - p.y) / px(60)));
            if (a > 0) {
              circle(ctx, p.x, p.y, px(4.5 * 2.2), rgba(GOLD, a * 0.3));
              circle(ctx, p.x, p.y, px(4.5), rgba("#FFFFFF", a));
            }
          }
        }

        // (4) the palm lines, traced one after another
        const pulse = Math.sin(ramp(t, 0.94, 1) * 2 * Math.PI) * 0.5 + 1;
        for (const key of LINE_ORDER) {
          const item = lines[key];
          if (!item) continue;
          const p = ramp(t, WINDOWS[key][0], WINDOWS[key][1]);
          if (p <= 0) continue;
          const color = LINE_COLORS[key];
          drawLine(ctx, item.line, color, { progress: p, width: px(6), alpha: pulse, faint: faint.has(key), fate: key === "FATE" });
          if (p < 1) {
            const pos = pointAt(item.line, p * item.line.length);
            circle(ctx, pos.x, pos.y, px(7), "#FFFFFF");
            circle(ctx, pos.x, pos.y, px(20), rgba(color, 0.5));
          } else {
            const text = LINE_LABELS[key].split(" ")[0];
            ctx.font = LABEL_FONT;
            const tw = ctx.measureText(text).width;
            const ox = item.end.x + px(10);
            const oy = item.end.y - LABEL_HEIGHT - px(6);
            ctx.beginPath();
            ctx.roundRect(ox - px(8), oy - px(4), tw + px(16), LABEL_HEIGHT + px(8), px(12));
            ctx.fillStyle = rgba(BG, 0.7);
            ctx.fill();
            ctx.fillStyle = color;
            ctx.textBaseline = "alphabetic";
            ctx.fillText(text, ox, oy + LABEL_ASCENT);
          }
        }

        // (5) sparkles drifting up through the hand's box, twinkling
        const fadeIn = ramp(t, 0.05, 0.2);
        if (fadeIn > 0) {
          for (const [a, b, c, d, e] of PARTICLES) {
            const s = reduce ? 0.7 : (Math.sin(20 * t * e + d) + 1) / 2;
            const al = fadeIn * s;
            const x = left + (right - left) * a;
            let fr = (b - (reduce ? 0 : t * 0.3 * e)) % 1;
            if (fr < 0) fr += 1;
            const yy = top + (bottom - top) * fr;
            const r = px((s + 0.6) * c);
            const col = rgba(GOLD_LIGHT, al * 0.9);
            segmentLine(ctx, x - 2 * r, yy, x + 2 * r, yy, r * 0.5, col, "round");
            segmentLine(ctx, x, yy - 2 * r, x, yy + 2 * r, r * 0.5, col, "round");
            circle(ctx, x, yy, r * 0.6, col);
          }
        }
      }

      // M3 LinearProgressIndicator: a round-capped 6dp bar, a 4dp gap, the
      // track (lilac 20%) and a 4dp stop dot at the end.
      function drawBar(t) {
        const w = barW;
        const sw = 6;
        const half = sw / 2;
        const clampX = (x) => Math.max(half, Math.min(w - half, x));
        barCtx.clearRect(0, 0, w, sw);
        barCtx.lineCap = "round";
        barCtx.lineWidth = sw;
        const end = t * w;
        const trackStart = end + 4 + sw;
        if (trackStart < w) {
          barCtx.strokeStyle = rgba(LILAC, 0.2);
          barCtx.beginPath();
          barCtx.moveTo(clampX(trackStart), half);
          barCtx.lineTo(clampX(w), half);
          barCtx.stroke();
          circle(barCtx, w - half, half, 2, GOLD);
        }
        if (t > 0) {
          barCtx.strokeStyle = GOLD;
          barCtx.beginPath();
          barCtx.moveTo(clampX(0), half);
          barCtx.lineTo(clampX(end), half);
          barCtx.stroke();
        }
        bar.setAttribute("aria-valuenow", String(Math.round(t * 100)));
      }

      // The caption pill: AnimatedContent cross-fades old and new while the
      // box springs to the new pill's size (clipped, content top-left).
      let caption = null;
      function setCaption(text) {
        if (text === caption) return;
        const first = caption == null;
        caption = text;
        const pill = Palm.el("span", { class: "palm-scan__pill", text });
        const old = [...statusBox.children];
        statusBox.append(pill);
        const size = () => {
          statusBox.style.width = `${pill.offsetWidth}px`;
          statusBox.style.height = `${pill.offsetHeight}px`;
        };
        if (first || reduce) {
          old.forEach((node) => node.remove());
          size();
          return;
        }
        pill.classList.add("is-entering");
        size();
        requestAnimationFrame(() => pill.classList.remove("is-entering"));
        for (const node of old) {
          node.classList.add("is-leaving");
          setTimeout(() => node.remove(), 400);
        }
      }

      let raf = 0;
      let doneTimer = 0;
      let start = 0;
      let finished = false;
      function frame(now) {
        if (!start) start = now;
        const t = Math.min(1, (now - start) / DURATION);
        drawScene(t);
        drawBar(t);
        setCaption(captionFor(t));
        if (t < 1) {
          raf = requestAnimationFrame(frame);
        } else if (!finished) {
          finished = true;
          doneTimer = setTimeout(() => Palm.onScanAnimationDone(), DONE_DELAY);
        }
      }

      layout();
      setCaption(captionFor(0));
      drawScene(0);
      drawBar(0);
      // Draw the labels in Roboto once it is in.
      if (document.fonts && document.fonts.load) document.fonts.load(LABEL_FONT).catch(() => {});
      raf = requestAnimationFrame(frame);

      return {
        unmount() {
          cancelAnimationFrame(raf);
          clearTimeout(doneTimer);
        },
      };
    },
  });
})();
