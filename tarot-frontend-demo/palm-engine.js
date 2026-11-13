// Palm reading engine: hand features and the reading text.
// A port of the app's ef6.b (feature thresholds), kk0.B (hand-shape metrics),
// by8.x (palm-line metrics), g63.a (palm signature) and s23.n (the reading).
// The text lives in palm-content.json (verbatim from the APK).
//
// window.PalmEngine:
//   ready                         Promise, resolves once palm-content.json is in
//   analyze(analysis, frame)      -> Promise<PalmFeatures>
//   match(person, features)       -> "same" | "different" | "unsure" | "new" | "unsaved"
//   buildReading(features, dominantHand, sign) -> PalmReading (synchronous)
//   seedOf(features)              the reading seed (exported for checks)
//
// PalmFeatures (plain JSON, saved with the person):
//   { hand, palmRatio, fingerRatio, indexRingRatio, pinkyRingRatio, middleDominance,
//     thumbAngle, fingerSpread, element, mount, heartCurved, heartEnd, headStart,
//     headSlope, headReach, lifeWide, lifeFull, fateStrong, fateBesideLife, signature }
// PalmReading:
//   { archetype, headline, handMeaning, summary, strengths: string[],
//     sections: { kind, title, trait, body }[] }

(() => {
  let content = null;
  const ready = fetch(new URL("palm-content.json", document.currentScript ? document.currentScript.src : location.href))
    .then((response) => {
      if (!response.ok) throw new Error(`palm-content.json: HTTP ${response.status}`);
      return response.json();
    })
    .then((json) => {
      content = json;
      return json;
    });
  ready.catch((error) => console.error("PalmEngine: content failed to load", error));

  // --- Small maths ---------------------------------------------------------

  const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y, z: (a.z || 0) - (b.z || 0) });
  const dot = (a, b) => a.x * b.x + a.y * b.y + (a.z || 0) * (b.z || 0);
  const len = (a) => Math.sqrt(dot(a, a));
  const dist = (a, b) => len(sub(a, b));
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const deg = (rad) => (rad * 180) / Math.PI;

  function angleDeg(u, v) {
    const lu = len(u);
    const lv = len(v);
    if (lu < 1e-6 || lv < 1e-6) return 0;
    return deg(Math.acos(clamp(dot(u, v) / (lu * lv), -1, 1)));
  }

  // by8.D: the median; an even count takes the mean of the two middle values.
  function median(values) {
    const sorted = [...values].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid] + sorted[mid - 1]) / 2;
  }

  // The 3-D points a frame's shape metrics use: world landmarks when there are
  // all 21, otherwise the image landmarks with x scaled by the aspect.
  function shapePoints(hand) {
    if (hand.world && hand.world.length >= 21) return hand.world.map((p) => ({ x: p.x, y: p.y, z: p.z || 0 }));
    const f = hand.aspect || 1;
    return hand.landmarks.map((p) => ({ x: p.x * f, y: p.y, z: 0 }));
  }

  // --- kk0.B: hand-shape metrics (one frame) --------------------------------

  function shapeMetrics(hand) {
    const L = shapePoints(hand);
    const d = (i, j) => dist(L[i], L[j]);
    const finger = (i) => d(i, i + 1) + d(i + 1, i + 2) + d(i + 2, i + 3);
    const palmLen = d(0, 9);
    return {
      palmRatio: palmLen / Math.max(d(5, 17), 1e-5),
      fingerRatio: finger(9) / Math.max(palmLen, 1e-5),
      indexRingRatio: finger(5) / Math.max(finger(13), 1e-5),
      pinkyRingRatio: finger(17) / finger(13),
      middleDominance: finger(9) / ((finger(5) + finger(13)) / 2),
      thumbAngle: angleDeg(sub(L[4], L[2]), sub(L[8], L[5])),
      fingerSpread:
        (angleDeg(sub(L[8], L[5]), sub(L[12], L[9])) +
          angleDeg(sub(L[12], L[9]), sub(L[16], L[13])) +
          angleDeg(sub(L[16], L[13]), sub(L[20], L[17]))) /
        3,
    };
  }

  // --- g63.a: the palm signature ---------------------------------------------
  // 16 bone lengths divided by the wrist-to-middle-knuckle length. The app
  // uses the world landmarks; without them we use the aspect-corrected image
  // landmarks (scale-free either way).
  const SIGNATURE_BONES = [
    [2, 3], [3, 4], [5, 6], [6, 7], [7, 8], [9, 10], [10, 11], [11, 12],
    [13, 14], [14, 15], [15, 16], [17, 18], [18, 19], [19, 20], [0, 5], [0, 17],
  ];

  function signatureOf(hand) {
    if (!hand || !hand.landmarks || hand.landmarks.length < 21) return null;
    const L = shapePoints(hand);
    const unit = dist(L[0], L[9]);
    if (unit < 1e-4) return null;
    return SIGNATURE_BONES.map(([a, b]) => dist(L[a], L[b]) / unit);
  }

  // --- by8.x: palm-line metrics (one frame) ---------------------------------

  function lineMetrics(lineFrame) {
    const f = lineFrame.aspect || 1;
    const P = (p) => ({ x: p.x * f, y: p.y });
    const L = lineFrame.landmarks.map(P);
    const lines = lineFrame.lines || {};
    const faint = lineFrame.faint || [];
    const get = (key) => (lines[key] && lines[key].length ? lines[key].map(P) : null);
    const H = get("HEART");
    const HD = get("HEAD");
    const LF = get("LIFE");
    const FT = get("FATE");

    const W = L[0];
    const K5 = L[5];
    const K17 = L[17];
    const T2 = L[2];
    const palmLen = Math.max(dist(L[9], L[0]), 1e-5);
    const cross = (a, b) => a.x * b.y - a.y * b.x;
    const chord = (pts) => dist(pts[pts.length - 1], pts[0]);
    const sag = (pts) => {
      const first = pts[0];
      const c = sub(pts[pts.length - 1], first);
      const cl = Math.max(len(c), 1e-9);
      let best = 0;
      for (const p of pts) best = Math.max(best, Math.abs(cross(c, sub(first, p))) / cl);
      return best;
    };
    const axis = sub(K17, K5);
    const axLen2 = Math.max(dot(axis, axis), 1e-9);
    const across = (p) => dot(sub(p, K5), axis) / axLen2;
    const mid = { x: (K5.x + K17.x) / 2, y: (K5.y + K17.y) / 2 };
    const down = sub(W, mid);
    const dnLen2 = Math.max(dot(down, down), 1e-9);
    const downF = (p) => dot(sub(p, mid), down) / dnLen2;
    const thumbX = across(T2);
    const web = { x: (K5.x + T2.x) / 2, y: (K5.y + T2.y) / 2 };
    const endNearest = (pts) => {
      const first = pts[0];
      const last = pts[pts.length - 1];
      return dist(last, web) < dist(first, web) ? last : first;
    };

    let headSlope = 0;
    if (HD) {
      const c = sub(HD[HD.length - 1], HD[0]);
      headSlope = deg(Math.acos(clamp(Math.abs(dot(axis, c)) / Math.max(len(axis) * len(c), 1e-9), 0, 1)));
    }
    let fs = null;
    if (FT) {
      let best = -Infinity;
      for (const p of FT) {
        const v = downF(p);
        if (v > best) {
          best = v;
          fs = p;
        }
      }
    }
    return {
      a: H ? Math.min(sag(H) / Math.max(chord(H), 1e-5), 0.3) : 0,
      b: headSlope,
      c: LF ? sag(LF) / palmLen : 0,
      d: !!FT && !faint.includes("FATE"),
      e: H ? Math.min(...H.map(across)) : null,
      f: HD ? Math.max(...HD.map(across)) : null,
      g: HD && LF ? dist(endNearest(HD), endNearest(LF)) / palmLen : null,
      h: LF ? Math.max(...LF.map(downF)) : null,
      i: fs ? (across(fs) - thumbX) / Math.max(1 - thumbX, 1e-5) : null,
      j: fs && LF ? Math.min(...LF.map((p) => dist(p, fs))) / palmLen : null,
      k: fs ? downF(fs) : null,
    };
  }

  // ef6.b: several frames' line metrics folded into one.
  function aggregateLines(list) {
    if (!list.length) return null;
    if (list.length === 1) return list[0];
    const out = {
      a: median(list.map((m) => m.a)),
      b: median(list.map((m) => m.b)),
      c: median(list.map((m) => m.c)),
      d: list.filter((m) => m.d).length * 2 > list.length,
    };
    for (const key of ["e", "f", "g", "h", "i", "j", "k"]) {
      const values = list.map((m) => m[key]).filter((v) => v != null);
      out[key] = values.length * 2 > list.length ? median(values) : null;
    }
    return out;
  }

  // --- ef6.b: features ------------------------------------------------------

  function featuresFrom(hand, shape, M) {
    const square = shape.palmRatio < 1.59;
    const longF = shape.fingerRatio >= 0.97;
    const element = square && !longF ? "EARTH" : square && longF ? "AIR" : !square && !longF ? "FIRE" : "WATER";
    const zJ = (shape.indexRingRatio - 0.964) / 0.0448;
    const scores = [
      ["JUPITER", zJ],
      ["APOLLO", -zJ],
      ["MERCURY", (shape.pinkyRingRatio - 0.839) / 0.052],
      ["VENUS", (shape.thumbAngle - 26.96) / 20.15],
      ["SATURN", (shape.middleDominance - 1.149) / 0.0404],
    ];
    let mount = scores[0];
    for (const entry of scores) if (entry[1] > mount[1]) mount = entry;

    const e = M ? M.e : null;
    const heartEnd =
      e != null
        ? e < 0.242 ? "INDEX" : e < 0.287 ? "BETWEEN" : e < 0.342 ? "MIDDLE" : "SHORT"
        : shape.fingerSpread >= 9 ? "BETWEEN" : "MIDDLE";
    const g = M ? M.g : null;
    const headStart = g != null ? (g < 0.005 ? "JOINED" : g < 0.205 ? "CLOSE" : "APART") : "JOINED";
    const headSlope = M ? (M.b >= 18.8 ? "SLOPING" : M.b >= 14.2 ? "GENTLE" : "STRAIGHT") : longF ? "SLOPING" : "STRAIGHT";

    return {
      hand,
      palmRatio: shape.palmRatio,
      fingerRatio: shape.fingerRatio,
      indexRingRatio: shape.indexRingRatio,
      pinkyRingRatio: shape.pinkyRingRatio,
      middleDominance: shape.middleDominance,
      thumbAngle: shape.thumbAngle,
      fingerSpread: shape.fingerSpread,
      element,
      mount: mount[0],
      heartCurved: M ? M.a >= 0.067 : shape.fingerSpread >= 9,
      heartEnd,
      headStart,
      headSlope,
      headReach: M && M.f != null ? M.f >= 0.949 : longF,
      lifeWide: M ? M.c >= 0.099 : shape.thumbAngle >= 42,
      lifeFull: M && M.h != null ? M.h >= 0.728 : true,
      fateStrong: M ? M.d : !square,
      fateBesideLife: M && M.j != null ? M.j < 0.05 : true,
    };
  }

  async function analyze(analysis, frame) {
    await ready;
    const shapeFrames = (analysis && analysis.shapeFrames ? analysis.shapeFrames : []).filter(
      (h) => h && h.landmarks && h.landmarks.length >= 21
    );
    const lineFrames = (analysis && analysis.lineFrames ? analysis.lineFrames : []).filter(
      (s) => s && s.landmarks && s.landmarks.length >= 21
    );
    // The capture: the last shape frame (the buffer ends with it), else the
    // first line frame, else the captured shot's own landmarks.
    const capture =
      shapeFrames[shapeFrames.length - 1] ||
      (lineFrames[0] && { ...lineFrames[0], world: [] }) ||
      (frame && frame.landmarks && { landmarks: frame.landmarks, world: [], aspect: frame.aspect || frame.width / frame.height });
    if (!capture) throw new Error("PalmEngine.analyze: no hand landmarks");
    const frames = shapeFrames.length ? shapeFrames : [capture];

    const perFrame = frames.map(shapeMetrics);
    const shape = {};
    for (const key of Object.keys(perFrame[0])) shape[key] = median(perFrame.map((m) => m[key]));

    const M = aggregateLines(lineFrames.map(lineMetrics));
    const hand = capture.hand || (analysis && analysis.hand) || "RIGHT";
    const features = featuresFrom(hand, shape, M);

    // The signature: each component's median over the buffered frames
    // (the app takes sorted[n/2]), else the capture's own.
    const signatures = frames.map(signatureOf).filter(Boolean);
    let signature = null;
    if (signatures.length) {
      signature = signatures[0].map((_, i) => {
        const sorted = signatures.map((s) => s[i]).sort((a, b) => a - b);
        return sorted[Math.floor(sorted.length / 2)];
      });
    } else {
      signature = signatureOf(capture);
    }
    features.signature = signature;
    return features;
  }

  // --- Saved-palm matching (ef6.b step 5) -----------------------------------

  const SHARED_KEYS = ["heartEnd", "headStart", "headSlope", "headReach", "lifeWide", "lifeFull", "element", "mount"];

  function signatureDistance(saved, next) {
    if (!saved || !next || saved.length !== next.length) return Number.MAX_VALUE;
    let sum = 0;
    for (let i = 0; i < saved.length; i++) {
      const mean = (saved[i] + next[i]) / 2;
      const r = mean < 1e-6 ? 0 : (saved[i] - next[i]) / mean;
      sum += r * r;
    }
    return Math.sqrt(sum / saved.length);
  }

  function match(person, features) {
    if (!person || !Array.isArray(person.palms) || !features || !features.signature) return "unsaved";
    const saved = person.palms.find((p) => p.hand === features.hand);
    if (!saved || !saved.features) return "new";
    const d = signatureDistance(saved.signature || saved.features.signature, features.signature);
    const shared = SHARED_KEYS.filter((key) => saved.features[key] === features[key]).length;
    if (d <= 0.049 && shared >= 5) return "same";
    if (d > 0.14 && shared <= 4) return "different";
    return "unsure";
  }

  // --- s23.n: the reading ---------------------------------------------------

  // java.lang.String.hashCode
  function javaStringHash(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
    return h;
  }
  // java.util.List.hashCode over Integer values
  function javaListHash(values) {
    let h = 1;
    for (const v of values) h = (Math.imul(31, h) + (v | 0)) | 0;
    return h;
  }
  const B = (b) => (b ? 1231 : 1237); // java.lang.Boolean.hashCode
  // The app hashes heartEnd/headStart/headSlope by enum identity, which
  // changes every launch; the name's String hash is the stable stand-in.
  const enumHash = (name) => javaStringHash(String(name));

  function seedOf(F) {
    const E = (content || {}).enums || {
      hand: ["LEFT", "RIGHT"],
      element: ["EARTH", "AIR", "FIRE", "WATER"],
      mount: ["JUPITER", "SATURN", "APOLLO", "MERCURY", "VENUS"],
    };
    return (
      javaListHash([
        E.hand.indexOf(F.hand),
        E.element.indexOf(F.element),
        E.mount.indexOf(F.mount),
        B(F.heartCurved),
        enumHash(F.heartEnd),
        enumHash(F.headStart),
        enumHash(F.headSlope),
        B(F.headReach),
        B(F.lifeWide),
        B(F.lifeFull),
        B(F.fateStrong),
        B(F.fateBesideLife),
      ]) & 0x7fffffff
    );
  }

  const pickIndex = (seed, salt, length) => (Math.floor(seed / (salt + 1)) + salt) % length;
  const pick = (seed, salt, list) => list[pickIndex(seed, salt, list.length)];

  // r77.a: the person's sign, trimmed, matched to a sign title (any case).
  function signKey(sign) {
    if (!sign || !content) return null;
    const wanted = String(sign).trim().toLowerCase();
    for (const [key, value] of Object.entries(content.signs)) {
      if (value.title.toLowerCase() === wanted) return key;
    }
    return null;
  }

  function buildReading(F, dominantHand = "RIGHT", sign = null) {
    if (!content) throw new Error("PalmEngine: content is not loaded yet");
    const C = content;
    const s = seedOf(F);
    const signId = signKey(sign);
    const el = C.sections.ELEMENT.byElement[F.element];
    const ht = C.sections.HEART.byEnd[F.heartEnd];
    const H = C.sections.HEAD;
    const L = C.sections.LIFE;
    const FT = C.sections.FATE;
    const MT = C.sections.MOUNT.byMount[F.mount];

    const heartBody = `Your heart line ${C.sections.HEART.curvePhrase[F.heartCurved]} ${C.sections.HEART.endPhrase[F.heartEnd]} ${pick(s, 2, ht.bodies)}`;
    const headBody = `Your head line ${H.startPhrase[F.headStart]}, then ${H.slopePhrase[F.headSlope]} ${H.reachPhrase[F.headReach]}. ${pick(s, 3, H.startBodies[F.headStart])} ${pick(s, 7, H.slopeBodies[F.headSlope])}`;
    const headTrait = [H.startTrait[F.headStart], H.slopeTrait[F.headSlope], H.reachTrait[F.headReach]].join(" · ");
    const lw = L.byWide[F.lifeWide];
    const lifeBody = L.arcPhrase[F.lifeWide] + L.fullPhrase[F.lifeFull] + " " + pick(s, 4, lw.bodies) + L.closer[F.lifeFull];
    const lifeTrait = lw.trait + (F.lifeFull ? L.resilientSuffix : "");
    const fv = F.fateStrong ? (F.fateBesideLife ? "besideLife" : "middle") : "none";
    const elementBody = pick(s, 1, el.bodies) + (signId ? " " + pick(s, 8, C.signs[signId].echoes) : "");

    const sections = [
      { kind: "ELEMENT", title: `${C.enums.elementTitle[F.element]} Hand`, trait: el.trait, body: elementBody },
      { kind: "HEART", title: C.sections.HEART.title, trait: ht.trait, body: heartBody },
      { kind: "HEAD", title: H.title, trait: headTrait, body: headBody },
      { kind: "LIFE", title: L.title, trait: lifeTrait, body: lifeBody },
      F.fateStrong
        ? { kind: "FATE", title: FT.title, trait: FT.variants[fv].trait, body: `${FT.variants[fv].opening} ${pick(s, 5, FT.variants[fv].bodies)}` }
        : null,
      { kind: "MOUNT", title: C.enums.mountTitle[F.mount], trait: MT.trait, body: pick(s, 6, MT.bodies) },
    ].filter(Boolean);

    const E = C.essence;
    const firstWord = (t) => t.split(" ·")[0];
    const chip = signId ? C.signs[signId].chip : C.strengths.headSlopeChip[F.headSlope];
    return {
      archetype: `The ${C.archetype.mountAdjective[F.mount]} ${C.archetype.elementNoun[F.element]}`,
      headline: `${C.enums.handLabel[F.hand]} hand · ${C.enums.elementTitle[F.element]} Hand`,
      handMeaning: F.hand === dominantHand ? C.handMeaning.dominant : C.handMeaning.nonDominant,
      summary: `${E.element[F.element]} ${E.heartEnd[F.heartEnd]} ${E.headStart[F.headStart]} ${E.mount[F.mount]}`,
      strengths: [...new Set([firstWord(el.trait), firstWord(ht.trait), chip])],
      sections,
    };
  }

  window.PalmEngine = {
    ready,
    analyze,
    match,
    buildReading,
    seedOf,
    get content() {
      return content;
    },
  };
})();
