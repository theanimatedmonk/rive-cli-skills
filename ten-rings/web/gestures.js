import {
  FilesetResolver,
  GestureRecognizer,
} from "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";

const WASM =
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm";
const MODEL =
  "https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task";

const GESTURE_COOLDOWN_MS = 2200;

// Palm centre: the wrist and the bases of the index, middle and pinky
// fingers, averaged. Steadier than a fingertip.
const PALM = [0, 5, 9, 17];
const PALM_SMOOTHING = 0.7; // 0 = raw, closer to 1 = smoother but laggier

/** MediaPipe category → { trigger, allowedPhases } */
const RULES = {
  Open_Palm: [{ trigger: "recall", phases: new Set(["summoned"]) }],
};

const PRAY_RULE = { trigger: "summon", phases: new Set(["orbit"]) };
const FIST_AWAKEN = { trigger: "awaken", phases: new Set(["rest"]) };
// The same fist while the rings orbit sends them back onto the forearms.
const FIST_RETRACT = { trigger: "retract", phases: new Set(["orbit"]) };
const CLOSE_FIST_UNLEASH = { trigger: "unleash", phases: new Set(["summoned"]) };

const CURL_OPEN = 0.088;
const CURL_CLOSED = 0.068;

function dist(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const dz = (a.z ?? 0) - (b.z ?? 0);
  return Math.hypot(dx, dy, dz);
}

/** Palms together, fingers up — not in MediaPipe's canned set. */
function isPrayGesture(landmarks) {
  if (!landmarks || landmarks.length !== 2) return false;
  const [a, b] = landmarks;

  const wristDist = dist(a[0], b[0]);
  if (wristDist > 0.14 || wristDist < 0.015) return false;

  const tipIds = [8, 12, 16, 20];
  let tipGap = 0;
  for (const i of tipIds) tipGap += dist(a[i], b[i]);
  if (tipGap / tipIds.length > 0.08) return false;

  for (const h of [a, b]) {
    if (h[12].y >= h[9].y - 0.02) return false;
    if (h[8].y >= h[5].y - 0.02) return false;
    if (h[20].y >= h[17].y - 0.02) return false;
  }

  return true;
}

function isCurledFist(hand) {
  return curlSpread(hand) < CURL_CLOSED;
}

function curlSpread(hand) {
  const pairs = [
    [8, 5],
    [12, 9],
    [16, 13],
    [20, 17],
  ];
  let curl = 0;
  for (const [tip, mcp] of pairs) curl += dist(hand[tip], hand[mcp]);
  return curl / pairs.length;
}

/** Knuckle width (index base to pinky base): the hand's own scale, so the
 *  checks below hold whether the fist is near the lens or far from it. */
function knuckleSpan(hand) {
  return Math.max(dist(hand[5], hand[17]), 1e-4);
}

/** Fingers curled in: fingertips close to their knuckles, relative to the
 *  hand's size (a fist measured ~0.7 knuckle widths, an open hand ~1.2+).
 *  Loose on purpose: the pointing checks below are the strict part. */
function isCurledRelative(hand) {
  return curlSpread(hand) / knuckleSpan(hand) < 0.85;
}

/**
 * A fist punched toward the camera, knuckles forward (like holding both
 * arms out at the lens). Two cues, both scale-free:
 *  - foreshortened: the wrist sits almost behind the knuckles on screen, so
 *    wrist→middle-knuckle is short compared with the knuckle width
 *    (a flat hand facing the camera is ~1.3-1.6; a fist at the lens < ~1);
 *  - depth: MediaPipe puts the knuckles nearer than the wrist (lower z).
 */
function isFistTowardCamera(hand, gesture) {
  const classified =
    gesture?.categoryName === "Closed_Fist" && (gesture.score ?? 0) >= 0.5;
  if (!classified && !isCurledRelative(hand)) return false;

  const span = knuckleSpan(hand);
  const wrist = hand[0];
  const reach = Math.hypot(hand[9].x - wrist.x, hand[9].y - wrist.y);
  if (reach / span > 1.1) return false;

  const knuckleZ = (hand[5].z + hand[9].z + hand[13].z + hand[17].z) / 4;
  if (knuckleZ > wrist.z - span * 0.12) return false;

  return true;
}

/** Both hands balled into fists and pointed at the camera. */
function findFistTowardCamera(result) {
  const hands = result.landmarks || [];
  const gestures = result.gestures || [];
  if (hands.length < 2) return false;
  let fists = 0;
  for (let i = 0; i < hands.length; i += 1) {
    if (isFistTowardCamera(hands[i], gestures[i]?.[0])) fists += 1;
  }
  return fists >= 2;
}

/** Open hand → closed fist within a frame or two. */
function detectClosingFist(result, prevCurls) {
  const hands = result.landmarks || [];
  const gestures = result.gestures || [];
  const nextCurls = [];
  let closing = false;

  for (let i = 0; i < hands.length; i += 1) {
    const curl = curlSpread(hands[i]);
    const prev = prevCurls[i];
    if (prev != null && prev >= CURL_OPEN && curl <= CURL_CLOSED) {
      closing = true;
    }
    const g = gestures[i]?.[0];
    if (
      prev != null &&
      prev >= CURL_OPEN &&
      g?.categoryName === "Closed_Fist" &&
      (g.score ?? 0) >= 0.55
    ) {
      closing = true;
    }
    nextCurls[i] = curl;
  }

  return { closing, nextCurls };
}

export function startVisionGestures({ getPhase, fire, onStatus, onHand }) {
  const video = document.getElementById("gesture-video");
  const preview = document.getElementById("gesture-preview");
  const label = document.getElementById("gesture-label");
  const toggle = document.getElementById("gesture-toggle");

  let recognizer = null;
  let stream = null;
  let raf = 0;
  let lastVideoTime = -1;
  let lastFire = { key: "", at: 0 };
  let active = false;
  let prevCurls = [];

  function setStatus(text) {
    if (onStatus) onStatus(text);
    if (label) label.textContent = text;
  }

  function tryFire(trigger, gestureName) {
    const key = `${gestureName}:${trigger}`;
    const now = performance.now();
    if (lastFire.key === key && now - lastFire.at < GESTURE_COOLDOWN_MS) {
      return;
    }
    lastFire = { key, at: now };
    fire(trigger);
    setStatus(`${gestureName} → ${trigger}`);
  }

  // Palm centre of the first hand, mirrored (0..1 of the camera frame),
  // smoothed; or null when no hand is visible. Drives the rings' follow.
  let palm = null;
  function reportHand(result) {
    if (!onHand) return;
    const hand = result.landmarks && result.landmarks[0];
    if (!hand) {
      palm = null;
      onHand(null);
      return;
    }
    let x = 0;
    let y = 0;
    for (const i of PALM) {
      x += hand[i].x;
      y += hand[i].y;
    }
    x = 1 - x / PALM.length;
    y = y / PALM.length;
    palm = palm
      ? { x: palm.x + (x - palm.x) * (1 - PALM_SMOOTHING), y: palm.y + (y - palm.y) * (1 - PALM_SMOOTHING) }
      : { x, y };
    onHand(palm);
  }

  function handleResult(result) {
    reportHand(result);
    const phase = getPhase();
    const { closing, nextCurls } = detectClosingFist(result, prevCurls);
    prevCurls = nextCurls;

    if (isPrayGesture(result.landmarks)) {
      if (PRAY_RULE.phases.has(phase)) {
        tryFire(PRAY_RULE.trigger, "Pray");
      } else {
        setStatus("Pray (wrong phase)");
      }
      return;
    }

    if (closing) {
      if (CLOSE_FIST_UNLEASH.phases.has(phase)) {
        tryFire(CLOSE_FIST_UNLEASH.trigger, "Close fist");
        return;
      }
    }

    if (findFistTowardCamera(result)) {
      if (FIST_AWAKEN.phases.has(phase)) {
        tryFire(FIST_AWAKEN.trigger, "Both fists");
      } else if (FIST_RETRACT.phases.has(phase)) {
        tryFire(FIST_RETRACT.trigger, "Both fists");
      } else {
        setStatus("Both fists (wrong phase)");
      }
      return;
    }

    const top = result.gestures?.[0]?.[0];
    if (!top || top.score < 0.6) {
      if (active) setStatus("Watching…");
      return;
    }
    const name = top.categoryName;
    const rules = RULES[name];
    if (!rules) {
      setStatus(name);
      return;
    }
    for (const rule of rules) {
      if (rule.phases.has(phase)) {
        tryFire(rule.trigger, name);
        return;
      }
    }
    setStatus(`${name} (hold — wrong phase)`);
  }

  async function ensureRecognizer() {
    if (recognizer) return recognizer;
    setStatus("Loading vision model…");
    const vision = await FilesetResolver.forVisionTasks(WASM);
    recognizer = await GestureRecognizer.createFromOptions(vision, {
      baseOptions: { modelAssetPath: MODEL, delegate: "GPU" },
      runningMode: "VIDEO",
      numHands: 2,
      // Fists held out at the lens are big, close and partly cut off, so be
      // a little more willing to find the second hand.
      minHandDetectionConfidence: 0.35,
      minHandPresenceConfidence: 0.35,
      minTrackingConfidence: 0.35,
    });
    return recognizer;
  }

  function loop() {
    if (!active || !recognizer || video.readyState < 2) {
      raf = requestAnimationFrame(loop);
      return;
    }
    if (video.currentTime !== lastVideoTime) {
      lastVideoTime = video.currentTime;
      const result = recognizer.recognizeForVideo(video, performance.now());
      handleResult(result);
    }
    raf = requestAnimationFrame(loop);
  }

  async function start() {
    if (active) return;
    try {
      await ensureRecognizer();
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      });
      video.srcObject = stream;
      await video.play();
      active = true;
      preview.hidden = false;
      toggle.setAttribute("aria-pressed", "true");
      toggle.textContent = "Gestures on";
      setStatus("Watching…");
      loop();
    } catch (err) {
      console.error("Vision gestures:", err);
      setStatus("Camera blocked or unavailable");
      stop();
    }
  }

  function stop() {
    active = false;
    cancelAnimationFrame(raf);
    if (stream) {
      stream.getTracks().forEach((t) => t.stop());
      stream = null;
    }
    video.srcObject = null;
    prevCurls = [];
    palm = null;
    if (onHand) onHand(null);
    preview.hidden = true;
    toggle.setAttribute("aria-pressed", "false");
    toggle.textContent = "Gestures";
    setStatus("");
  }

  toggle.addEventListener("click", () => {
    if (active) stop();
    else start();
  });

  return { start, stop };
}
