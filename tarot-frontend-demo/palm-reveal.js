// Palm reading, ANALYZING: the archetype card flip (RevealScreen, i66 in the
// app).
//
// The card springs in showing the palm close-up with its lines, bobbing.
// After 1.3 s, and only once the reading exists, it tips back -12°, then
// flips to 180° (the face swaps at 90°) to show the archetype, holds for
// 1.5 s and calls Palm.onRevealDone(), retrying until the stage moves on.

(() => {
  if (!window.Palm || !window.PalmDraw) return;
  const { LINE_COLORS, LINE_ORDER, rgba, cover, linePath, drawLine, setupCanvas } = window.PalmDraw;

  const ANTIQUE_GOLD = "#D9B56A";
  const PALE_GOLD = "#F2D48C";
  const DEEP = "#1A1236";
  const PLUM = "#5A2A52";
  const GOLD = "#E8C27A";
  const GOLD_LIGHT = "#F2D497";

  // FastOutSlowIn = cubic-bezier(0.4, 0, 0.2, 1).
  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1;
    const bx = 3 * (x2 - x1) - cx;
    const ax = 1 - cx - bx;
    const cy = 3 * y1;
    const by = 3 * (y2 - y1) - cy;
    const ay = 1 - cy - by;
    const sx = (t) => ((ax * t + bx) * t + cx) * t;
    const sy = (t) => ((ay * t + by) * t + cy) * t;
    const dx = (t) => (3 * ax * t + 2 * bx) * t + cx;
    return (x) => {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      let t = x;
      for (let i = 0; i < 8; i++) {
        const err = sx(t) - x;
        if (Math.abs(err) < 1e-6) break;
        const d = dx(t);
        if (Math.abs(d) < 1e-6) break;
        t -= err / d;
      }
      t = Math.max(0, Math.min(1, t));
      return sy(t);
    };
  }
  const fastOutSlowIn = bezier(0.4, 0, 0.2, 1);

  // spring(dampingRatio 0.55, stiffness 200) from 0 to 1, t in ms.
  function enterSpring(ms) {
    const t = ms / 1000;
    const w0 = Math.sqrt(200);
    const z = 0.55;
    const wd = w0 * Math.sqrt(1 - z * z);
    return 1 - Math.exp(-z * w0 * t) * (Math.cos(wd * t) + (z / Math.sqrt(1 - z * z)) * Math.sin(wd * t));
  }

  // infiniteRepeatable(tween(period, easing), Reverse): from -> to -> from …
  function reverse(ms, period, from, to, ease = (x) => x) {
    const n = Math.floor(ms / period);
    let f = (ms - n * period) / period;
    if (n % 2 === 1) f = 1 - f;
    return from + (to - from) * ease(f);
  }

  // The card frame (i66.d) and its corner leaves (i66.e), in units of W/168.
  function drawFrame(ctx, W, H, a) {
    const u = W / 168;
    ctx.save();
    ctx.setLineDash([]);
    ctx.beginPath();
    ctx.roundRect(5 * u, 5 * u, W - 10 * u, H - 10 * u, 10 * u);
    ctx.lineWidth = 1.6 * u;
    ctx.strokeStyle = rgba(ANTIQUE_GOLD, a);
    ctx.stroke();
    ctx.beginPath();
    ctx.roundRect(11 * u, 11 * u, W - 22 * u, H - 22 * u, 6 * u);
    ctx.lineWidth = 0.7 * u;
    ctx.strokeStyle = rgba(ANTIQUE_GOLD, a * 0.8);
    ctx.stroke();
    const corner = (x, y, sx, sy) => {
      ctx.beginPath();
      ctx.moveTo(x, y + 13 * u * sy);
      ctx.quadraticCurveTo(x, y, x + 13 * u * sx, y);
      ctx.lineTo(x + 7 * u * sx, y + 6 * u * sy);
      ctx.quadraticCurveTo(x + 6 * u * sx, y + 11 * u * sy, x, y + 13 * u * sy);
      ctx.closePath();
      ctx.fillStyle = rgba(ANTIQUE_GOLD, a);
      ctx.fill();
    };
    corner(11 * u, 11 * u, 1, 1);
    corner(W - 11 * u, 11 * u, -1, 1);
    corner(11 * u, H - 11 * u, 1, -1);
    corner(W - 11 * u, H - 11 * u, -1, -1);
    ctx.restore();
  }

  const STARS = [[24, 60, 0], [140, 54, 0.4], [150, 120, 0.2], [30, 150, 0.7], [44, 226, 0.5], [128, 220, 0.9], [118, 66, 0.3], [60, 128, 0.8], [108, 168, 0.6]];

  // CardBack canvas (jv5): glow, stars, frame, moon row, ring + star, divider, sheen.
  function drawBack(ctx, W, H, twinkle, sheen) {
    const u = W / 168;
    ctx.clearRect(0, 0, W, H);
    const glow = ctx.createRadialGradient(W / 2, 1.1 * H, 0, W / 2, 1.1 * H, 0.9 * W);
    glow.addColorStop(0, rgba(GOLD, 0.28));
    glow.addColorStop(1, rgba(GOLD, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, W, H);

    for (const [x, y, ph] of STARS) {
      ctx.beginPath();
      ctx.arc(x * u, y * u, 0.9 * u, 0, Math.PI * 2);
      ctx.fillStyle = rgba("#FFFFFF", 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(2 * Math.PI * (twinkle + ph))));
      ctx.fill();
    }

    drawFrame(ctx, W, H, 1);

    ctx.fillStyle = ANTIQUE_GOLD;
    ctx.strokeStyle = ANTIQUE_GOLD;
    const disc = (cx, r, from, to) => {
      ctx.beginPath();
      ctx.moveTo(cx * u, 32 * u);
      ctx.arc(cx * u, 32 * u, r * u, from, to);
      ctx.closePath();
      ctx.fill();
    };
    disc(54, 4, 0, Math.PI * 2);
    disc(70, 4, Math.PI / 2, (3 * Math.PI) / 2);
    ctx.beginPath();
    ctx.arc(84 * u, 32 * u, 4.5 * u, 0, Math.PI * 2);
    ctx.lineWidth = u;
    ctx.stroke();
    disc(98, 4, -Math.PI / 2, Math.PI / 2);
    disc(114, 4, 0, Math.PI * 2);

    ctx.beginPath();
    ctx.arc(84 * u, 90 * u, 20 * u, 0, Math.PI * 2);
    ctx.lineWidth = 0.8 * u;
    ctx.stroke();

    const cx = 84 * u;
    const cy = 90 * u;
    const L = 15 * u;
    const s = 3 * u;
    ctx.beginPath();
    ctx.moveTo(cx, cy - L);
    ctx.lineTo(cx + s, cy);
    ctx.lineTo(cx, cy + L);
    ctx.lineTo(cx - s, cy);
    ctx.closePath();
    ctx.moveTo(cx - L, cy);
    ctx.lineTo(cx, cy - s);
    ctx.lineTo(cx + L, cy);
    ctx.lineTo(cx, cy + s);
    ctx.closePath();
    ctx.fillStyle = PALE_GOLD;
    ctx.fill("nonzero");

    ctx.beginPath();
    ctx.moveTo(44 * u, 203 * u);
    ctx.lineTo(124 * u, 203 * u);
    ctx.lineWidth = 0.6 * u;
    ctx.lineCap = "butt";
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(84 * u, 203 * u, 2 * u, 0, Math.PI * 2);
    ctx.fillStyle = ANTIQUE_GOLD;
    ctx.fill();

    const sx = sheen * W;
    const g = ctx.createLinearGradient(sx - 0.3 * W, 0, sx + 0.3 * W, 0.4 * H);
    g.addColorStop(0, rgba(GOLD_LIGHT, 0));
    g.addColorStop(0.5, rgba(GOLD_LIGHT, 0.22));
    g.addColorStop(1, rgba(GOLD_LIGHT, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
  }

  // CardFront base (x35 case 1): the close-up at 90%, the overlay gradient
  // and every line at w = 4 device px. The frame is drawn on its own layer.
  function drawFrontBase(ctx, W, H, shot) {
    ctx.fillStyle = DEEP;
    ctx.fillRect(0, 0, W, H);
    if (!shot || !shot.image) return;
    const m = cover(shot.width, shot.height, W, H);
    ctx.globalAlpha = 0.9;
    ctx.drawImage(shot.image, m.ox, m.oy, m.dw, m.dh);
    ctx.globalAlpha = 1;
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, rgba(DEEP, 0.45));
    g.addColorStop(0.5, rgba(DEEP, 0));
    g.addColorStop(1, rgba(PLUM, 0.55));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    const faint = new Set(shot.faint || []);
    const lines = shot.lines || {};
    const keys = [...Object.keys(lines).filter((k) => LINE_ORDER.includes(k))];
    for (const key of keys) {
      const pts = lines[key];
      if (!pts || pts.length < 2) continue;
      drawLine(ctx, linePath(pts, m.map), LINE_COLORS[key], { width: 4 / 3, faint: faint.has(key), fate: key === "FATE" });
    }
  }

  window.Palm.registerStage("analyzing", {
    mount(stageEl, Palm) {
      const shot = Palm.state.closeUp || Palm.state.frame;
      const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const generation = Palm.state.generation;

      const blurred = Palm.el("canvas", { class: "palm-reveal__photo", "aria-hidden": "true" });
      const frontBase = Palm.el("canvas", { class: "palm-card__layer", role: "img", "aria-label": "Your palm" });
      const frontFrame = Palm.el("canvas", { class: "palm-card__layer", "aria-hidden": "true" });
      const front = Palm.el("div", { class: "palm-card__face palm-card__face--front" }, frontBase, frontFrame);
      const backArt = Palm.el("canvas", { class: "palm-card__layer", "aria-hidden": "true" });
      const name = Palm.el("p", { class: "palm-card__name" });
      const headline = Palm.el("p", { class: "palm-card__headline" });
      const back = Palm.el(
        "div",
        { class: "palm-card__face palm-card__face--back", hidden: true },
        backArt,
        Palm.el("div", { class: "palm-card__text" }, Palm.el("div", { class: "palm-card__spacer" }), name, Palm.el("div", { class: "palm-card__grow" }), headline)
      );
      const card = Palm.el("div", { class: "palm-card" }, front, back);
      // Behind the card: light rays, a ring of the zodiac, drifting dust.
      // In front: the burst of sparks when the card turns.
      const fxBack = Palm.el("canvas", { class: "palm-reveal__fx", "aria-hidden": "true" });
      const fxFront = Palm.el("canvas", { class: "palm-reveal__fx palm-reveal__fx--front", "aria-hidden": "true" });
      const caption = Palm.el("p", { class: "palm-reveal__caption", text: "\u2726  THE PALM REVEALS  \u2726" });
      stageEl.append(
        Palm.el(
          "div",
          { class: "palm-reveal" },
          blurred,
          Palm.el("div", { class: "palm-reveal__dim" }),
          fxBack,
          Palm.el("div", { class: "palm-reveal__stage" }, card),
          caption,
          fxFront
        )
      );

      const SW = stageEl.clientWidth || 360;
      const SH = stageEl.clientHeight || 780;
      const CW = SW * 0.68;
      const CH = CW / 0.65;
      card.style.width = `${CW}px`;
      card.style.height = `${CH}px`;
      card.style.opacity = "0";

      const blurCtx = setupCanvas(blurred, SW, SH);
      if (shot && shot.image) {
        const m = cover(shot.width, shot.height, SW, SH);
        blurCtx.drawImage(shot.image, m.ox, m.oy, m.dw, m.dh);
      }
      drawFrontBase(setupCanvas(frontBase, CW, CH), CW, CH, shot);
      const backFx = setupCanvas(fxBack, SW, SH);
      const frontFx = setupCanvas(fxFront, SW, SH);
      const CX = SW / 2;
      const CY = SH / 2;
      caption.style.top = `${Math.max(8, CY - (CH * 1.04) / 2 - 44)}px`;
      const dust = Array.from({ length: 46 }, () => ({
        x: Math.random() * SW,
        y: Math.random() * SH,
        r: 0.4 + Math.random() * 1.3,
        v: 4 + Math.random() * 12,
        p: Math.random() * Math.PI * 2,
      }));
      const sparks = [];
      let burstAt = null;
      const frameCtx = setupCanvas(frontFrame, CW, CH);
      const backCtx = setupCanvas(backArt, CW, CH);

      let raf = 0;
      let retry = 0;
      let start = 0;
      let flipAt = null; // ms (since mount) when the tilt starts
      let showingBack = false;
      let doneCalled = false;

      function fillText() {
        const reading = Palm.state.reading;
        name.textContent = (reading && reading.archetype) || "";
        headline.textContent = (reading && reading.headline) || "";
      }

      function angleAt(ms) {
        if (flipAt == null) return 0;
        const dt = ms - flipAt;
        if (reduce) return dt >= 0 ? 180 : 0;
        if (dt <= 0) return 0;
        if (dt < 450) return -12 * fastOutSlowIn(dt / 450);
        if (dt < 1500) return -12 + 192 * fastOutSlowIn((dt - 450) / 1050);
        return 180;
      }

      function finish() {
        if (doneCalled) return;
        doneCalled = true;
        const attempt = () => {
          if (generation !== Palm.state.generation || Palm.state.stage !== "analyzing") return;
          try {
            Palm.onRevealDone();
          } catch (error) {
            console.error("Palm: moving on from the reveal failed", error);
          }
          if (Palm.state.stage === "analyzing") retry = setTimeout(attempt, 250);
        };
        attempt();
      }

      const ZODIAC = ["\u2648", "\u2649", "\u264A", "\u264B", "\u264C", "\u264D", "\u264E", "\u264F", "\u2650", "\u2651", "\u2652", "\u2653"];
      const SPARK_COLORS = [GOLD_LIGHT, GOLD, PALE_GOLD, "#FFFFFF", "#EFA3AE", "#B9A4F2"];

      function burst() {
        if (reduce) return;
        for (let i = 0; i < 110; i++) {
          const a = Math.random() * Math.PI * 2;
          const v = 120 + Math.random() * 360;
          // From the card's edge, outwards.
          const ex = CX + Math.cos(a) * CW * 0.45;
          const ey = CY + Math.sin(a) * CH * 0.45;
          sparks.push({
            x: ex,
            y: ey,
            vx: Math.cos(a) * v,
            vy: Math.sin(a) * v,
            life: 0.7 + Math.random() * 1.1,
            age: 0,
            r: 0.8 + Math.random() * 2,
            c: SPARK_COLORS[(Math.random() * SPARK_COLORS.length) | 0],
          });
        }
      }

      let lastFx = 0;
      function drawFx(ms) {
        const dt = lastFx ? Math.min(0.05, (ms - lastFx) / 1000) : 0;
        lastFx = ms;
        const t = ms / 1000;
        const post = burstAt == null ? 0 : fastOutSlowIn(Math.min(1, (ms - burstAt) / 900));
        const enter = Math.min(1, ms / 900);

        backFx.clearRect(0, 0, SW, SH);
        backFx.save();
        backFx.globalCompositeOperation = "lighter";

        // Light rays, turning slowly; stronger once the card is revealed.
        const rays = 16;
        const R = Math.hypot(SW, SH) * 0.62;
        const rayA = (0.1 + 0.5 * post) * enter;
        for (let i = 0; i < rays; i++) {
          const a = (i / rays) * Math.PI * 2 + (reduce ? 0 : t * 0.07);
          const w = (i % 2 ? 0.05 : 0.09) * (1 + 0.15 * Math.sin(t * 1.3 + i));
          const g = backFx.createRadialGradient(CX, CY, CW * 0.2, CX, CY, R);
          g.addColorStop(0, `rgba(242,212,151,${0.22 * rayA})`);
          g.addColorStop(0.5, `rgba(232,194,122,${0.08 * rayA})`);
          g.addColorStop(1, "rgba(232,194,122,0)");
          backFx.fillStyle = g;
          backFx.beginPath();
          backFx.moveTo(CX, CY);
          backFx.arc(CX, CY, R, a - w, a + w);
          backFx.closePath();
          backFx.fill();
        }

        // A soft halo behind the card.
        const halo = backFx.createRadialGradient(CX, CY, 0, CX, CY, CH * 0.75);
        halo.addColorStop(0, `rgba(185,164,242,${0.2 * enter + 0.15 * post})`);
        halo.addColorStop(0.55, `rgba(232,194,122,${0.08 + 0.1 * post})`);
        halo.addColorStop(1, "rgba(232,194,122,0)");
        backFx.fillStyle = halo;
        backFx.fillRect(0, 0, SW, SH);

        // The zodiac, orbiting the card on an ellipse.
        const rx = SW * 0.47;
        const ry = CH * 0.76;
        const ringA = (0.25 + 0.55 * post) * enter;
        backFx.strokeStyle = `rgba(232,194,122,${0.16 * ringA})`;
        backFx.lineWidth = 1;
        backFx.setLineDash([2, 5]);
        backFx.beginPath();
        backFx.ellipse(CX, CY, rx, ry, 0, 0, Math.PI * 2);
        backFx.stroke();
        backFx.setLineDash([]);
        backFx.font = '15px "Noto Sans Symbols", "Segoe UI Symbol", serif';
        backFx.textAlign = "center";
        backFx.textBaseline = "middle";
        backFx.shadowColor = "rgba(242,212,151,0.9)";
        backFx.shadowBlur = 8;
        for (let i = 0; i < 12; i++) {
          const a = (i / 12) * Math.PI * 2 - (reduce ? 0 : t * 0.12);
          const x = CX + Math.cos(a) * rx;
          const y = CY + Math.sin(a) * ry;
          const tw = reduce ? 1 : 0.65 + 0.35 * Math.sin(t * 2 + i * 1.7);
          backFx.fillStyle = `rgba(242,212,151,${0.75 * ringA * tw})`;
          backFx.fillText(ZODIAC[i], x, y);
        }
        backFx.shadowBlur = 0;

        // Dust, drifting up.
        for (const d of dust) {
          if (!reduce) {
            d.y -= d.v * dt;
            if (d.y < -4) {
              d.y = SH + 4;
              d.x = Math.random() * SW;
            }
          }
          const tw = 0.4 + 0.6 * Math.abs(Math.sin(t * 1.5 + d.p));
          backFx.fillStyle = `rgba(242,212,151,${0.5 * tw * enter})`;
          backFx.beginPath();
          backFx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
          backFx.fill();
        }
        backFx.restore();

        // In front: the shockwave and the sparks.
        frontFx.clearRect(0, 0, SW, SH);
        if (burstAt != null && !reduce) {
          frontFx.save();
          frontFx.globalCompositeOperation = "lighter";
          const k = (ms - burstAt) / 900;
          if (k < 1) {
            const e = fastOutSlowIn(k);
            frontFx.strokeStyle = `rgba(242,212,151,${0.7 * (1 - k)})`;
            frontFx.lineWidth = 3 * (1 - k) + 0.5;
            frontFx.beginPath();
            frontFx.ellipse(CX, CY, CW * 0.5 + e * SW * 0.55, CH * 0.5 + e * SW * 0.55, 0, 0, Math.PI * 2);
            frontFx.stroke();
            // The flash.
            frontFx.fillStyle = `rgba(255,244,214,${0.35 * Math.max(0, 1 - k * 3)})`;
            frontFx.fillRect(0, 0, SW, SH);
          }
          for (let i = sparks.length - 1; i >= 0; i--) {
            const sp = sparks[i];
            sp.age += dt;
            if (sp.age >= sp.life) {
              sparks.splice(i, 1);
              continue;
            }
            sp.vx *= 0.94;
            sp.vy = sp.vy * 0.94 + 30 * dt;
            sp.x += sp.vx * dt;
            sp.y += sp.vy * dt;
            const f = 1 - sp.age / sp.life;
            frontFx.fillStyle = sp.c;
            frontFx.globalAlpha = 0.25 * f;
            frontFx.beginPath();
            frontFx.arc(sp.x, sp.y, sp.r * 3, 0, Math.PI * 2);
            frontFx.fill();
            frontFx.globalAlpha = f;
            frontFx.beginPath();
            frontFx.arc(sp.x, sp.y, sp.r, 0, Math.PI * 2);
            frontFx.fill();
          }
          frontFx.restore();
        }
      }

      function tick(now) {
        if (!start) start = now;
        const ms = now - start;

        // The flip waits 1300 ms, then for the reading.
        if (flipAt == null && ms >= 1300 && Palm.state.reading) flipAt = ms;
        const angle = angleAt(ms);

        const enter = reduce ? 1 : enterSpring(ms);
        const flipped = angle > 90;
        if (flipped !== showingBack) {
          showingBack = flipped;
          if (flipped) {
            fillText();
            if (burstAt == null) {
              burstAt = ms;
              burst();
              card.classList.add("is-revealed");
              caption.classList.add("is-in");
            }
          }
          front.hidden = flipped;
          back.hidden = !flipped;
        }
        const scale = (enter * 0.4 + 0.6) * (flipped ? 1.04 : 1);
        const bob = angle === 0 && !reduce ? reverse(ms, 1800, -1, 1) * 6 : 0;
        card.style.opacity = String(Math.max(0, Math.min(1, enter)));
        card.style.transform = `translateY(${bob.toFixed(3)}px) rotateY(${angle.toFixed(3)}deg) scale(${scale.toFixed(4)})`;

        if (flipped) {
          const twinkle = (ms % 2600) / 2600;
          const sheen = -0.6 + 2.2 * fastOutSlowIn((ms % 3400) / 3400);
          drawBack(backCtx, CW, CH, reduce ? 0.25 : twinkle, reduce ? -0.6 : sheen);
        } else {
          const glow = reduce ? 0.9 : reverse(ms, 1100, 0.35, 0.9, fastOutSlowIn);
          frameCtx.clearRect(0, 0, CW, CH);
          drawFrame(frameCtx, CW, CH, glow * 0.45 + 0.55);
        }

        drawFx(ms);

        // A longer hold than the app's 1500 ms, to take the card in.
        if (flipAt != null && ms - flipAt >= 1500 + 2600) finish();
        raf = requestAnimationFrame(tick);
      }

      if (document.fonts && document.fonts.load) {
        document.fonts.load('27px "Palm Fell"').catch(() => {});
        document.fonts.load("13px Roboto").catch(() => {});
      }
      raf = requestAnimationFrame(tick);

      return {
        render: fillText,
        unmount() {
          cancelAnimationFrame(raf);
          clearTimeout(retry);
        },
      };
    },
  });
})();
