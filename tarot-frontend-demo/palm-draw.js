// Palm reading: drawing shared by the stages (n52, ld1, pe4 in the app).
// Scan, Reveal and Result draw the palm lines with these, so they look the
// same everywhere. Every size here is in CSS px on a canvas prepared by
// setupCanvas (1 unit = 1 CSS px). The app's sizes are device pixels on a
// 1080 px wide phone: divide them by 3 before passing them in.

(() => {
  const LINE_COLORS = { HEART: "#EFA3AE", HEAD: "#E8C27A", LIFE: "#8FD6C4", FATE: "#B9A4F2" };
  const LINE_ORDER = ["HEART", "HEAD", "LIFE", "FATE"];
  const LINE_LABELS = { HEART: "Heart line", HEAD: "Head line", LIFE: "Life line", FATE: "Fate line" };

  // The hand skeleton (pe4.a), in drawing order.
  const SKELETON = [
    [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11],
    [11, 12], [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20],
  ];

  // "#RRGGBB" + alpha -> rgba(). Alpha replaces, like Compose's Color.copy(alpha).
  function rgba(hex, alpha = 1) {
    const n = parseInt(hex.slice(1), 16);
    const a = Math.max(0, Math.min(1, alpha));
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${+a.toFixed(4)})`;
  }

  // ContentScale.Crop (ld1): the image fills the view, centred, cropped.
  // a/b/c/d mirror the app's field names (dw, dh, ox, oy).
  function cover(srcW, srcH, viewW, viewH) {
    const scale = Math.max(viewW / srcW, viewH / srcH);
    const dw = srcW * scale;
    const dh = srcH * scale;
    const ox = (viewW - dw) / 2;
    const oy = (viewH - dh) / 2;
    return {
      scale, dw, dh, ox, oy,
      a: dw, b: dh, c: ox, d: oy,
      map: (pt) => ({ x: pt.x * dw + ox, y: pt.y * dh + oy }),
    };
  }

  function toMapper(map) {
    if (typeof map === "function") return map;
    if (map && typeof map.map === "function") return map.map;
    if (map && "a" in map) return (p) => ({ x: p.x * map.a + map.c, y: p.y * map.b + map.d });
    return (p) => ({ x: p.x, y: p.y });
  }

  // n52.l: quadratic midpoint smoothing through the mapped points. Besides
  // the Path2D it keeps a flattened copy (with arc lengths) to trim it.
  function linePath(points, map) {
    const mapper = toMapper(map);
    const P = (points || []).map((p) => mapper(p));
    const path = new Path2D();
    const flat = [];
    const cum = [];
    if (!P.length) return { path, length: 0, points: P, flat, cum };
    const push = (x, y) => {
      if (flat.length) {
        const last = flat[flat.length - 1];
        cum.push(cum[cum.length - 1] + Math.hypot(x - last.x, y - last.y));
      } else {
        cum.push(0);
      }
      flat.push({ x, y });
    };
    path.moveTo(P[0].x, P[0].y);
    push(P[0].x, P[0].y);
    let cx = P[0].x;
    let cy = P[0].y;
    for (let i = 1; i < P.length - 1; i++) {
      const mx = (P[i].x + P[i + 1].x) / 2;
      const my = (P[i].y + P[i + 1].y) / 2;
      path.quadraticCurveTo(P[i].x, P[i].y, mx, my);
      for (let s = 1; s <= 8; s++) {
        const t = s / 8;
        const k = 1 - t;
        push(k * k * cx + 2 * k * t * P[i].x + t * t * mx, k * k * cy + 2 * k * t * P[i].y + t * t * my);
      }
      cx = mx;
      cy = my;
    }
    const end = P[P.length - 1];
    path.lineTo(end.x, end.y);
    push(end.x, end.y);
    return { path, length: cum[cum.length - 1], points: P, flat, cum };
  }

  // The point at a distance along the line (PathMeasure.getPosition).
  function pointAt(line, dist) {
    const { flat, cum } = line;
    if (!flat.length) return { x: 0, y: 0 };
    if (dist <= 0) return { ...flat[0] };
    for (let i = 1; i < flat.length; i++) {
      if (cum[i] >= dist) {
        const span = cum[i] - cum[i - 1] || 1;
        const t = (dist - cum[i - 1]) / span;
        return { x: flat[i - 1].x + (flat[i].x - flat[i - 1].x) * t, y: flat[i - 1].y + (flat[i].y - flat[i - 1].y) * t };
      }
    }
    return { ...flat[flat.length - 1] };
  }

  // The first `dist` of the line (PathMeasure.getSegment(0, dist)).
  function segment(line, dist) {
    const { flat, cum } = line;
    const path = new Path2D();
    if (!flat.length) return path;
    path.moveTo(flat[0].x, flat[0].y);
    for (let i = 1; i < flat.length; i++) {
      if (cum[i] >= dist) {
        const end = pointAt(line, dist);
        path.lineTo(end.x, end.y);
        return path;
      }
      path.lineTo(flat[i].x, flat[i].y);
    }
    return path;
  }

  // n52.b: the stacked strokes that make a line glow. `alpha` multiplies the
  // glow layers only (the scan's pulse). Faint wins over fate.
  function drawLine(ctx, line, color, { progress = 1, width, alpha = 1, faint = false, fate = false } = {}) {
    if (!line || progress <= 0 || !line.flat || line.flat.length < 2) return;
    const w = width;
    const path = progress >= 1 ? line.path : segment(line, line.length * progress);
    const stroke = (lineWidth, style, dash) => {
      ctx.lineWidth = lineWidth;
      ctx.strokeStyle = style;
      ctx.setLineDash(dash || []);
      ctx.stroke(path);
    };
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "miter";
    ctx.lineDashOffset = 0;
    if (faint) {
      const dash = [2.5 * w, 2 * w];
      stroke(2.4 * w, rgba(color, alpha * 0.18), dash);
      stroke(0.8 * w, rgba(color, 0.6), dash);
    } else if (fate) {
      const dash = [0.01, 3.25 * w];
      stroke(3.4 * w, rgba(color, alpha * 0.22), dash);
      stroke(1.5 * w, rgba(color, 1), dash);
      stroke(0.55 * w, rgba("#FFFFFF", 0.8), dash);
    } else {
      stroke(5 * w, rgba(color, alpha * 0.18));
      stroke(2.4 * w, rgba(color, alpha * 0.35));
      stroke(w, rgba(color, 1));
      stroke(0.35 * w, rgba("#FFFFFF", 0.7));
    }
    ctx.restore();
  }

  // A canvas whose backing store matches the screen, drawn in CSS px.
  function setupCanvas(canvas, cssW, cssH) {
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    canvas.width = Math.max(1, Math.round(cssW * dpr));
    canvas.height = Math.max(1, Math.round(cssH * dpr));
    canvas.style.width = `${cssW}px`;
    canvas.style.height = `${cssH}px`;
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }

  // Draws an image (or canvas) with ContentScale.Crop into a view; returns the transform.
  function drawCover(ctx, image, viewW, viewH, srcW, srcH) {
    const w = srcW || image.naturalWidth || image.videoWidth || image.width;
    const h = srcH || image.naturalHeight || image.videoHeight || image.height;
    const m = cover(w, h, viewW, viewH);
    ctx.drawImage(image, m.ox, m.oy, m.dw, m.dh);
    return m;
  }

  window.PalmDraw = { LINE_COLORS, LINE_ORDER, LINE_LABELS, SKELETON, rgba, cover, linePath, pointAt, drawLine, setupCanvas, drawCover };
})();
