// Palm reading: the vision pipeline (the app's HandTracker k63 and its
// rules palm-line detector tu0.B, with the kx0.A template curves).
//
//   PalmVision.prepare(onProgress)  loads MediaPipe HandLandmarker and the
//                                   app's hand_landmarker.task (float16)
//   PalmVision.detect(source, ts, { mirrored })  -> TrackedHand | null
//   PalmVision.detectLines(canvas, hand)  -> { lines, faint, isPalm, palmScore }
//   PalmVision.templateLines(hand)  -> { lines, faint }
//
// All points are normalized 0..1 in the source image. A TrackedHand is
// { landmarks[21], world[21]|[], hand: "LEFT"|"RIGHT", handScore, mirrored, aspect }.

(() => {
  const MP_VERSION = "0.10.21";
  const MP_BASE = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}`;
  // The app's own model URL (PalmConfig te5.b).
  const MODEL_URL =
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task";
  // Sizes used for progress when a response has no usable Content-Length.
  const MODEL_BYTES = 7819105;
  const WASM_BYTES = 9574032;

  const LINE_KEYS = ["HEART", "HEAD", "LIFE", "FATE"];

  let landmarker = null;
  let preparing = null;
  let lastTs = -1;

  // --- Loading ------------------------------------------------------------

  // Streams a URL into memory, reporting the bytes as they arrive.
  async function download(url, expected, onBytes) {
    const response = await fetch(url, { mode: "cors" });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    const header = Number(response.headers.get("content-length")) || 0;
    // A compressed response reports its compressed length; fall back to the
    // known size then, so the progress never runs past 100%.
    const total = header >= expected * 0.9 ? header : expected;
    if (!response.body || !response.body.getReader) {
      const buffer = new Uint8Array(await response.arrayBuffer());
      onBytes(buffer.length, buffer.length);
      return buffer;
    }
    const reader = response.body.getReader();
    const chunks = [];
    let received = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      received += value.length;
      onBytes(received, Math.max(total, received));
    }
    const out = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      out.set(chunk, offset);
      offset += chunk.length;
    }
    return out;
  }

  function prepare(onProgress = () => {}) {
    if (landmarker) {
      onProgress(1);
      return Promise.resolve();
    }
    if (preparing) return preparing;
    preparing = (async () => {
      const vision = await import(`${MP_BASE}/vision_bundle.mjs`);
      const fileset = await vision.FilesetResolver.forVisionTasks(`${MP_BASE}/wasm`);

      // Both downloads run at once; progress is the share of all their bytes.
      const got = { wasm: [0, WASM_BYTES], model: [0, MODEL_BYTES] };
      let reported = 0;
      const report = () => {
        const done = got.wasm[0] + got.model[0];
        const total = got.wasm[1] + got.model[1];
        const progress = Math.min(0.99, done / total);
        if (progress - reported >= 0.01) {
          reported = progress;
          onProgress(progress);
        }
      };
      const [wasm, model] = await Promise.all([
        download(fileset.wasmBinaryPath, WASM_BYTES, (n, t) => {
          got.wasm = [n, t];
          report();
        }),
        download(MODEL_URL, MODEL_BYTES, (n, t) => {
          got.model = [n, t];
          report();
        }),
      ]);
      const wasmUrl = URL.createObjectURL(new Blob([wasm], { type: "application/wasm" }));
      const files = { ...fileset, wasmBinaryPath: wasmUrl };
      const options = (delegate) => ({
        baseOptions: { modelAssetBuffer: model, delegate },
        runningMode: "VIDEO",
        numHands: 1,
        minHandDetectionConfidence: 0.5,
        minHandPresenceConfidence: 0.5,
        minTrackingConfidence: 0.5,
      });
      try {
        landmarker = await vision.HandLandmarker.createFromOptions(files, options("GPU"));
      } catch (error) {
        console.info("PalmVision: GPU delegate unavailable, using CPU", error && error.message);
        landmarker = await vision.HandLandmarker.createFromOptions(files, options("CPU"));
      }
      // Warm up: the first frame builds the graph and its shaders, which
      // would otherwise stall the camera's first second.
      try {
        const blank = document.createElement("canvas");
        blank.width = 64;
        blank.height = 64;
        blank.getContext("2d").fillRect(0, 0, 64, 64);
        detect(blank, performance.now());
      } catch {}
      onProgress(1);
    })().catch((error) => {
      preparing = null;
      throw error;
    });
    return preparing;
  }

  // --- Hand tracking (k63) ------------------------------------------------

  const opposite = (hand) => (hand === "LEFT" ? "RIGHT" : "LEFT");

  // `source` is a canvas (or video/image) that is already mirrored for the
  // front camera, as the app mirrors its analysis bitmap.
  function detect(source, timestampMs, { mirrored = false } = {}) {
    if (!landmarker) return null;
    const width = source.videoWidth || source.naturalWidth || source.width;
    const height = source.videoHeight || source.naturalHeight || source.height;
    if (!width || !height) return null;
    const ts = Math.max(Math.round(timestampMs), lastTs + 1);
    lastTs = ts;
    const result = landmarker.detectForVideo(source, ts);
    if (!result || !result.landmarks || !result.landmarks.length) return null;
    const landmarks = result.landmarks[0].map((p) => ({ x: p.x, y: p.y }));
    const worldRaw = (result.worldLandmarks && result.worldLandmarks[0]) || [];
    const world = worldRaw.length >= 21 ? worldRaw.map((p) => ({ x: p.x, y: p.y, z: p.z })) : [];
    const handedness = (result.handedness || result.handednesses || [])[0] || [];
    const category = handedness[0] || { categoryName: "Right", score: 0 };
    const label = /^left$/i.test(category.categoryName || category.displayName || "") ? "LEFT" : "RIGHT";
    return {
      landmarks,
      world,
      hand: mirrored ? opposite(label) : label,
      handScore: category.score || 0,
      mirrored,
      aspect: width / height,
    };
  }

  // --- Template curves (kx0.A) --------------------------------------------

  const add = (a, b) => ({ x: a.x + b.x, y: a.y + b.y });
  const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y });
  const mul = (a, k) => ({ x: a.x * k, y: a.y * k });
  const lerp = (a, b, t) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
  const len = (a) => Math.hypot(a.x, a.y);
  const unit = (a) => {
    const l = len(a) || 1e-6;
    return { x: a.x / l, y: a.y / l };
  };

  // The four cubic Beziers, in normalized space: { HEART: [P0, C1, C2, P3], … }
  function priors(hand) {
    const a = hand.aspect;
    const P = (i) => ({ x: hand.landmarks[i].x * a, y: hand.landmarks[i].y });
    const W = P(0), T1 = P(1), T2 = P(2), I = P(5), M = P(9), R = P(13), K = P(17);
    const L = Math.max(1e-4, len(sub(M, W)));
    const u = unit(sub(M, W));
    const v = unit(sub(K, R));
    const C = mul(add(add(add(add(W, I), M), R), K), 1 / 5);
    const A = add(I, mul(sub(T2, I), 0.5));
    const A2 = add(A, mul(sub(C, A), 0.12));

    const heart = [
      sub(add(K, mul(v, 0.1 * L)), mul(u, 0.2 * L)),
      add(R, mul(sub(W, R), 0.2)),
      add(M, mul(sub(W, M), 0.17)),
      sub(add(I, mul(sub(M, I), 0.45)), mul(u, 0.08 * L)),
    ];
    const headEnd = sub(add(K, mul(v, 0.04 * L)), mul(u, 0.3 * L));
    const head = [
      A2,
      add(add(A2, mul(sub(headEnd, A2), 0.33)), mul(u, 0.03 * L)),
      add(add(A2, mul(sub(headEnd, A2), 0.66)), mul(u, 0.01 * L)),
      headEnd,
    ];
    const lifeStart = sub(A2, mul(u, 0.04 * L));
    const lifeEnd = add(add(W, mul(sub(T1, W), 0.35)), mul(u, 0.06 * L));
    const life = [lifeStart, add(lifeStart, mul(sub(C, lifeStart), 0.55)), add(lifeEnd, mul(sub(C, lifeEnd), 0.45)), lifeEnd];
    const f0 = add(add(W, mul(sub(M, W), 0.1)), mul(v, 0.08 * L));
    const f1 = add(M, mul(sub(W, M), 0.32));
    const perp = mul({ x: -u.y, y: u.x }, 0.02 * L);
    const fate = [f0, add(lerp(f0, f1, 0.33), perp), add(lerp(f0, f1, 0.66), perp), f1];

    const back = (pts) => pts.map((p) => ({ x: p.x / a, y: p.y }));
    return { HEART: back(heart), HEAD: back(head), LIFE: back(life), FATE: back(fate) };
  }

  // uc0.a(n): n evenly spaced t on a cubic Bezier.
  function sampleCubic([p0, c1, c2, p3], n) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1);
      const s = 1 - t;
      const b0 = s * s * s, b1 = 3 * s * s * t, b2 = 3 * s * t * t, b3 = t * t * t;
      out.push({
        x: p0.x * b0 + c1.x * b1 + c2.x * b2 + p3.x * b3,
        y: p0.y * b0 + c1.y * b1 + c2.y * b2 + p3.y * b3,
      });
    }
    return out;
  }

  function templateLines(hand) {
    const curves = priors(hand);
    const lines = {};
    for (const key of LINE_KEYS) lines[key] = sampleCubic(curves[key], 32);
    return { lines, faint: [] };
  }

  // --- Rules line detector (tu0.B) ----------------------------------------

  function grayOf(canvas) {
    const W = canvas.width;
    const H = canvas.height;
    const data = canvas.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, W, H).data;
    const gray = new Uint8Array(W * H);
    for (let i = 0, j = 0; i < gray.length; i++, j += 4) {
      gray[i] = (77 * data[j] + 150 * data[j + 1] + 29 * data[j + 2]) >> 8;
    }
    return gray;
  }

  // Integral image + box mean (a75).
  function integral(gray, W, H) {
    const S = new Float64Array((W + 1) * (H + 1));
    for (let y = 0; y < H; y++) {
      let row = 0;
      for (let x = 0; x < W; x++) {
        row += gray[y * W + x];
        S[(y + 1) * (W + 1) + x + 1] = S[y * (W + 1) + x + 1] + row;
      }
    }
    return (x, y, r) => {
      const x0 = Math.max(0, x - r);
      const y0 = Math.max(0, y - r);
      const x1 = Math.min(W, x + r + 1);
      const y1 = Math.min(H, y + r + 1);
      const s = S[y1 * (W + 1) + x1] - S[y0 * (W + 1) + x1] - S[y1 * (W + 1) + x0] + S[y0 * (W + 1) + x0];
      return s / ((y1 - y0) * (x1 - x0));
    };
  }

  function insidePolygon(poly, x, y) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const a = poly[i];
      const b = poly[j];
      if (a.y > y !== b.y > y && x < ((y - a.y) * (b.x - a.x)) / (b.y - a.y) + a.x) inside = !inside;
    }
    return inside;
  }

  const meanOf = (values) => (values.length ? values.reduce((s, v) => s + v, 0) / values.length : 0);
  const near = (pts, x, y, dist) => pts.some((p) => Math.hypot(p.x - x, p.y - y) < dist);

  // Distance from p to segment ab (tu0.D).
  function segDist(p, a, b) {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const l2 = dx * dx + dy * dy;
    let t = 0;
    if (l2 >= 1e-12) t = Math.min(1, Math.max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2));
    return Math.hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t));
  }

  function polyDist(p, pts) {
    let best = Infinity;
    for (let i = 0; i + 1 < pts.length; i++) best = Math.min(best, segDist(p, pts[i], pts[i + 1]));
    return best;
  }

  // Post-filter tu0.j: overlapping HEART/HEAD drops the one farther from its
  // prior; FATE overlapping LIFE is dropped. Dropped lines become faint.
  function postFilter(result, hand, curves) {
    const lm = hand.landmarks;
    if (lm.length < 21) return result;
    const a = hand.aspect;
    const m = (p) => ({ x: p.x * a, y: p.y });
    const L = Math.max(1e-4, Math.hypot((lm[0].x - lm[9].x) * a, lm[0].y - lm[9].y));
    const overlap = (l1, l2) => {
      const [short, long] = l1.length <= l2.length ? [l1, l2] : [l2, l1];
      if (!short.length || long.length < 2) return false;
      const longM = long.map(m);
      const count = short.filter((p) => polyDist(m(p), longM) < 0.04 * L).length;
      return count >= short.length * 0.6;
    };
    const fromPrior = (key) => {
      const pts = result.lines[key];
      if (!pts) return Number.MAX_VALUE;
      const prior = sampleCubic(curves[key], 24).map(m);
      return meanOf(pts.map((p) => polyDist(m(p), prior)));
    };
    const drop = [];
    const { HEART, HEAD, FATE, LIFE } = result.lines;
    if (HEART && HEAD && overlap(HEART, HEAD)) drop.push(fromPrior("HEART") <= fromPrior("HEAD") ? "HEAD" : "HEART");
    if (FATE && LIFE && overlap(FATE, LIFE)) drop.push("FATE");
    if (!drop.length) return result;
    const lines = { ...result.lines };
    for (const key of drop) delete lines[key];
    return { lines, faint: [...new Set([...result.faint, ...drop])] };
  }

  function detectLines(canvas, hand) {
    const W = canvas.width;
    const H = canvas.height;
    const curves = priors(hand);
    const px = hand.landmarks.map((p) => ({ x: p.x * W, y: p.y * H }));
    const L = Math.hypot(px[9].x - px[0].x, px[9].y - px[0].y);

    if (L < 20) {
      const result = postFilter(templateLines(hand), hand, curves);
      return { ...result, isPalm: false, palmScore: 0 };
    }

    const mean = integral(grayOf(canvas), W, H);
    const r = Math.max(1, Math.round(0.006 * L));
    const d = Math.max(2 + r, 0.022 * L);
    const margin = Math.round(r + d + 1);
    const ids = [0, 1, 2, 5, 9, 13, 17];
    const cx = meanOf(ids.map((i) => px[i].x));
    const cy = meanOf(ids.map((i) => px[i].y));
    const poly = ids.map((i) => ({ x: cx + (px[i].x - cx) * 1.18, y: cy + (px[i].y - cy) * 1.18 }));
    const steps = { HEART: 0.15, HEAD: 0.26 };

    const found = []; // [key, points in px]
    const lines = {};
    const faint = [];
    const evidence = {};

    for (const key of LINE_KEYS) {
      const st = ((steps[key] || 0.18) * L) / 18;
      const priorN = sampleCubic(curves[key], 32);
      const s = priorN.map((p) => ({ x: p.x * W, y: p.y * H }));
      const n = s.map((_, i) => {
        const a = s[Math.max(0, i - 1)];
        const b = s[Math.min(s.length - 1, i + 1)];
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const l = Math.max(1e-4, Math.hypot(dx, dy));
        return { x: -dy / l, y: dx / l };
      });

      // Score grid: 32 samples x 37 offsets along the normal.
      const score = s.map((sample, i) => {
        const row = new Float32Array(37);
        for (let k = 0; k < 37; k++) {
          const off = (k - 18) * st;
          const qx = sample.x + n[i].x * off;
          const qy = sample.y + n[i].y * off;
          let value = -0.05;
          if (key !== "LIFE" || i >= 8) {
            for (const [other, pts] of found) {
              if (key === "FATE" && other !== "LIFE") continue;
              if (near(pts, qx, qy, 0.06 * L)) {
                value = NaN;
                break;
              }
            }
          }
          if (!Number.isNaN(value) && key !== "FATE") {
            for (const [other, pts] of found) {
              if ((other === "HEART" || other === "HEAD") && near(pts, qx, qy, 0.035 * L)) {
                value = NaN;
                break;
              }
            }
          }
          if (!Number.isNaN(value)) {
            const ix = Math.round(qx);
            const iy = Math.round(qy);
            if (ix >= margin && iy >= margin && ix < W - margin && iy < H - margin && insidePolygon(poly, qx, qy)) {
              const m0 = mean(ix, iy, r);
              const m1 = mean(Math.round(qx + n[i].x * d), Math.round(qy + n[i].y * d), r);
              const m2 = mean(Math.round(qx - n[i].x * d), Math.round(qy - n[i].y * d), r);
              value = (Math.min(m1, m2) - m0) / (m0 + 8);
            }
            const t = (k - 18) / 18;
            value -= 0.012 * t * t;
          }
          row[k] = value;
        }
        return row;
      });

      // Viterbi: ±2 offsets per step, 0.006 per step of change.
      const size = s.length;
      const dp = [Float32Array.from(score[0], (v) => (Number.isNaN(v) ? 0 : v))];
      const from = [new Int32Array(37)];
      for (let i = 1; i < size; i++) {
        const row = new Float32Array(37);
        const back = new Int32Array(37);
        for (let k = 0; k < 37; k++) {
          let best = -Infinity;
          let arg = k;
          for (let j = Math.max(0, k - 2); j <= Math.min(36, k + 2); j++) {
            const v = dp[i - 1][j] - Math.abs(k - j) * 0.006;
            if (v > best) {
              best = v;
              arg = j;
            }
          }
          const own = score[i][k];
          row[k] = best + (Number.isNaN(own) ? 0 : own);
          back[k] = arg;
        }
        dp.push(row);
        from.push(back);
      }
      const path = new Int32Array(size);
      let bestK = 0;
      for (let k = 1; k < 37; k++) if (dp[size - 1][k] > dp[size - 1][bestK]) bestK = k;
      path[size - 1] = bestK;
      for (let i = size - 1; i > 0; i--) path[i - 1] = from[i][path[i]];
      const pathScores = Array.from(path, (k, i) => score[i][k]);
      const ev = meanOf(pathScores.filter((v) => !Number.isNaN(v)));
      evidence[key] = ev;

      const offsets = Array.from(path, (k) => (k - 18) * st);
      const smooth = offsets.map((_, i) => meanOf(offsets.slice(Math.max(0, i - 3), Math.min(size - 1, i + 3) + 1)));
      const traced = (i) => ({ x: s[i].x + n[i].x * smooth[i], y: s[i].y + n[i].y * smooth[i] });
      const norm = (p) => ({ x: p.x / W, y: p.y / H });

      if (key === "FATE") {
        // Longest run of samples scoring > 0.015, allowing NaN gaps of ≤ 3.
        let best = null;
        let start = -1;
        let last = -1;
        const commit = () => {
          if (start >= 0 && (!best || last - start > best[1] - best[0])) best = [start, last];
          start = -1;
        };
        for (let i = 0; i < size; i++) {
          const v = pathScores[i];
          if (Number.isNaN(v)) continue;
          if (v > 0.015) {
            if (start >= 0 && i - last - 1 > 3) commit();
            if (start < 0) start = i;
            last = i;
          } else {
            commit();
          }
        }
        commit();
        if (best) {
          const runScores = pathScores.slice(best[0], best[1] + 1).filter((v) => !Number.isNaN(v));
          if (runScores.length >= size * 0.6 && meanOf(runScores) >= 0.028) {
            const pts = [];
            for (let i = best[0]; i <= best[1]; i++) pts.push(traced(i));
            found.push([key, pts]);
            lines[key] = pts.map(norm);
          }
        }
      } else if (ev < 0.012) {
        // Too little evidence: the template curve, drawn faint.
        found.push([key, s]);
        lines[key] = priorN;
        faint.push(key);
      } else {
        const pts = s.map((_, i) => traced(i));
        found.push([key, pts]);
        lines[key] = pts.map(norm);
      }
    }

    const palmScore = (evidence.HEART + evidence.HEAD + evidence.LIFE) / 3;
    const result = postFilter({ lines, faint }, hand, curves);
    return { lines: result.lines, faint: result.faint, isPalm: palmScore >= 0.012, palmScore };
  }

  window.PalmVision = {
    MP_VERSION,
    MODEL_URL,
    prepare,
    detect,
    detectLines,
    templateLines,
    isReady: () => Boolean(landmarker),
  };
})();
