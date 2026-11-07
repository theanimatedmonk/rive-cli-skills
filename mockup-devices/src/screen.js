// What the phones show: a built-in demo app (a course search screen that
// scrolls by itself), or your own screen recording or screenshot.

import * as THREE from "three";

const W = 900, H = 1956; // about the phones' screen shape (2.17 : 1)
const FONT = `-apple-system, "SF Pro Display", "Inter", "Segoe UI", system-ui, sans-serif`;

function rr(g, x, y, w, h, r) {
  g.beginPath();
  g.roundRect(x, y, w, h, r);
}

// The scrolling content, drawn once into a tall canvas.
function drawContent() {
  const c = document.createElement("canvas");
  c.width = W;
  c.height = 3600;
  const g = c.getContext("2d");
  const bg = g.createLinearGradient(0, 0, 0, c.height);
  bg.addColorStop(0, "#eef0f7");
  bg.addColorStop(1, "#e4e7f1");
  g.fillStyle = bg;
  g.fillRect(0, 0, W, c.height);

  const shadow = (blur, y, a = 0.1) => {
    g.shadowColor = `rgba(40, 50, 90, ${a})`;
    g.shadowBlur = blur;
    g.shadowOffsetY = y;
  };
  const noShadow = () => {
    g.shadowColor = "transparent";
    g.shadowBlur = 0;
    g.shadowOffsetY = 0;
  };

  // The round menu and profile buttons.
  for (const x of [96, W - 96]) {
    shadow(30, 10);
    g.fillStyle = "#f8f9fc";
    g.beginPath();
    g.arc(x, 250, 46, 0, Math.PI * 2);
    g.fill();
  }
  noShadow();
  g.strokeStyle = "#3b3f4e";
  g.lineWidth = 5;
  g.lineCap = "round";
  for (const [dy, len] of [[-12, 30], [0, 22], [12, 30]]) {
    g.beginPath();
    g.moveTo(82, 250 + dy);
    g.lineTo(82 + len, 250 + dy);
    g.stroke();
  }
  g.beginPath();
  g.arc(W - 96, 238, 11, 0, Math.PI * 2);
  g.stroke();
  g.beginPath();
  g.arc(W - 96, 278, 22, Math.PI * 1.1, Math.PI * 1.9);
  g.stroke();

  // The title, the search key and the field.
  g.fillStyle = "#14161f";
  g.font = `800 104px ${FONT}`;
  g.fillText("Search", 60, 450);
  g.fillStyle = "#9aa0b2";
  g.font = `500 38px ${FONT}`;
  g.fillText("Find any course or section", 62, 518);
  shadow(40, 16, 0.3);
  const key = g.createLinearGradient(W - 210, 340, W - 60, 490);
  key.addColorStop(0, "#5b4cf6");
  key.addColorStop(0.6, "#4f7cf7");
  key.addColorStop(1, "#4fd1c5");
  g.fillStyle = key;
  rr(g, W - 196, 352, 136, 136, 40);
  g.fill();
  noShadow();
  g.strokeStyle = "#ffffff";
  g.lineWidth = 9;
  g.beginPath();
  g.arc(W - 136, 412, 26, 0, Math.PI * 2);
  g.stroke();
  g.beginPath();
  g.moveTo(W - 117, 431);
  g.lineTo(W - 96, 452);
  g.stroke();

  shadow(36, 12, 0.08);
  g.fillStyle = "#f7f8fb";
  rr(g, 48, 590, W - 96, 122, 40);
  g.fill();
  noShadow();
  g.strokeStyle = "#7b8194";
  g.lineWidth = 5;
  g.beginPath();
  g.arc(116, 645, 17, 0, Math.PI * 2);
  g.stroke();
  g.beginPath();
  g.moveTo(129, 658);
  g.lineTo(141, 670);
  g.stroke();
  g.fillStyle = "#b4b9c8";
  g.font = `500 40px ${FONT}`;
  g.fillText("Search courses and sections", 168, 665);

  // Filter chips.
  let x = 48;
  for (const [label, active] of [["All", true], ["Courses", false], ["Sections", false]]) {
    g.font = `600 38px ${FONT}`;
    const w = g.measureText(label).width + 76;
    if (active) {
      shadow(30, 12, 0.35);
      const a = g.createLinearGradient(x, 0, x + w, 0);
      a.addColorStop(0, "#5b4cf6");
      a.addColorStop(1, "#6a6ff8");
      g.fillStyle = a;
    } else {
      shadow(24, 8, 0.07);
      g.fillStyle = "#f7f8fb";
    }
    rr(g, x, 770, w, 96, 48);
    g.fill();
    noShadow();
    g.fillStyle = active ? "#ffffff" : "#2b2f3d";
    g.fillText(label, x + 38, 832);
    x += w + 24;
  }

  // Suggestions.
  g.fillStyle = "#14161f";
  g.font = `750 50px ${FONT}`;
  g.fillText("Suggestions", 56, 980);
  x = 48;
  for (const label of ["SwiftUI", "Animation", "Menu"]) {
    g.font = `600 38px ${FONT}`;
    const w = g.measureText(label).width + 110;
    shadow(24, 8, 0.07);
    g.fillStyle = "#f7f8fb";
    rr(g, x, 1030, w, 96, 48);
    g.fill();
    noShadow();
    g.fillStyle = "#2b2f3d";
    g.fillText(label, x + 76, 1092);
    g.strokeStyle = "#2b2f3d";
    g.lineWidth = 4;
    g.beginPath();
    g.moveTo(x + 58, 1092);
    g.lineTo(x + 40, 1074);
    g.moveTo(x + 40, 1074);
    g.lineTo(x + 40, 1090);
    g.moveTo(x + 40, 1074);
    g.lineTo(x + 56, 1074);
    g.stroke();
    x += w + 22;
  }

  // Popular: gradient course cards, two to a row.
  g.fillStyle = "#14161f";
  g.font = `750 50px ${FONT}`;
  g.fillText("Popular", 56, 1250);
  const cards = [
    ["Animations", "in SwiftUI", "20 sections · 3 hours", ["#6a3df0", "#9d6bf7"]],
    ["Build Quick Apps", "with SwiftUI", "17 sections · 2 hours", ["#4f7cf7", "#86b3fb"]],
    ["Design for", "visionOS", "12 sections · 2 hours", ["#f06a7a", "#f7a46b"]],
    ["Motion with", "Rive", "15 sections · 2 hours", ["#18a999", "#6fd6c4"]],
    ["SwiftData", "essentials", "9 sections · 1 hour", ["#3d5af0", "#6b9bf7"]],
    ["Prototyping", "in Figma", "14 sections · 2 hours", ["#c04ce8", "#f07ac6"]],
  ];
  const cw = (W - 48 * 2 - 30) / 2, ch = 520;
  cards.forEach(([a, b, meta, [c1, c2]], i) => {
    const cx = 48 + (i % 2) * (cw + 30);
    const cy = 1300 + Math.floor(i / 2) * (ch + 34);
    shadow(50, 22, 0.22);
    const grad = g.createLinearGradient(cx, cy, cx + cw, cy + ch);
    grad.addColorStop(0, c1);
    grad.addColorStop(1, c2);
    g.fillStyle = grad;
    rr(g, cx, cy, cw, ch, 48);
    g.fill();
    noShadow();
    g.fillStyle = "rgba(255,255,255,0.22)";
    g.beginPath();
    g.arc(cx + cw - 40, cy + 60, 130, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = "rgba(255,255,255,0.92)";
    rr(g, cx + 36, cy + 40, 84, 84, 26);
    g.fill();
    g.fillStyle = c1;
    g.beginPath();
    g.arc(cx + 78, cy + 82, 18, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = "#ffffff";
    g.font = `750 46px ${FONT}`;
    g.fillText(a, cx + 36, cy + ch - 170);
    g.fillText(b, cx + 36, cy + ch - 112);
    g.fillStyle = "rgba(255,255,255,0.8)";
    g.font = `500 30px ${FONT}`;
    g.fillText(meta, cx + 36, cy + ch - 56);
  });
  return c;
}

// The fixed chrome: the status bar, the floating tab bar, the home bar.
function drawChrome(g, android) {
  g.fillStyle = "#14161f";
  g.font = `650 40px ${FONT}`;
  g.fillText(android ? "11:53" : "9:41", android ? 60 : 110, 84);
  // Signal bars, wifi, battery.
  const rx = W - (android ? 70 : 100);
  for (let i = 0; i < 4; i++) g.fillRect(rx - 150 + i * 13, 82 - 10 - i * 6, 9, 10 + i * 6);
  g.lineWidth = 6;
  g.strokeStyle = "#14161f";
  for (const r of [10, 22]) {
    g.beginPath();
    g.arc(rx - 72, 84, r, Math.PI * 1.25, Math.PI * 1.75);
    g.stroke();
  }
  rr(g, rx - 40, 58, 58, 30, 9);
  g.lineWidth = 3;
  g.stroke();
  g.fillStyle = "#34c759";
  rr(g, rx - 36, 62, 44, 22, 6);
  g.fill();

  // The tab bar.
  const ty = H - 230;
  g.shadowColor = "rgba(20, 24, 40, 0.35)";
  g.shadowBlur = 40;
  g.shadowOffsetY = 14;
  g.fillStyle = "#1c1f2b";
  rr(g, 80, ty, W - 160, 140, 70);
  g.fill();
  g.shadowColor = "transparent";
  const icons = 5;
  for (let i = 0; i < icons; i++) {
    const cx = 80 + (W - 160) * ((i + 0.5) / icons);
    const active = i === 1;
    g.strokeStyle = active ? "#ffffff" : "#8a90a6";
    g.fillStyle = g.strokeStyle;
    g.lineWidth = 5;
    g.beginPath();
    if (i === 0) {
      rr(g, cx - 22, ty + 48, 44, 34, 10);
    } else if (i === 1) {
      g.arc(cx - 4, ty + 64, 17, 0, Math.PI * 2);
      g.moveTo(cx + 9, ty + 77);
      g.lineTo(cx + 22, ty + 90);
    } else if (i === 2) {
      g.arc(cx, ty + 72, 22, 0, Math.PI * 2);
      g.moveTo(cx, ty + 72);
      g.lineTo(cx, ty + 58);
    } else if (i === 3) {
      g.moveTo(cx - 18, ty + 86);
      g.quadraticCurveTo(cx - 18, ty + 46, cx, ty + 46);
      g.quadraticCurveTo(cx + 18, ty + 46, cx + 18, ty + 86);
      g.closePath();
    } else {
      g.arc(cx, ty + 58, 13, 0, Math.PI * 2);
      g.moveTo(cx + 24, ty + 94);
      g.arc(cx, ty + 94, 24, 0, Math.PI, true);
    }
    g.stroke();
    if (active) {
      rr(g, cx - 22, ty + 14, 44, 8, 4);
      g.fillStyle = "#6a7bff";
      g.fill();
    }
    if (i === 3) {
      g.fillStyle = "#ff4d6a";
      g.beginPath();
      g.arc(cx + 18, ty + 46, 9, 0, Math.PI * 2);
      g.fill();
    }
  }
  g.fillStyle = "#14161f";
  rr(g, W / 2 - 140, H - 36, 280, 12, 6);
  g.fill();
}

// The demo app: one canvas, redrawn only when its scroll moves.
export class DemoScreen {
  constructor(android = false) {
    this.content = drawContent();
    this.canvas = document.createElement("canvas");
    this.canvas.width = W;
    this.canvas.height = H;
    this.g = this.canvas.getContext("2d");
    this.android = android;
    this.texture = new THREE.CanvasTexture(this.canvas);
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.anisotropy = 8;
    this.lastScroll = -1;
    this.aspect = W / H;
  }

  // The scroll, from time: rest, glide down, rest, glide back. 12 s a loop.
  update(t) {
    const p = (t % 12) / 12;
    const ease = (x) => x * x * (3 - 2 * x);
    const max = this.content.height - H + 120;
    let s;
    if (p < 0.2) s = 0;
    else if (p < 0.45) s = ease((p - 0.2) / 0.25);
    else if (p < 0.65) s = 1;
    else if (p < 0.9) s = 1 - ease((p - 0.65) / 0.25);
    else s = 0;
    const scroll = Math.round(s * max * 0.62);
    if (scroll === this.lastScroll) return;
    this.lastScroll = scroll;
    const g = this.g;
    g.drawImage(this.content, 0, -scroll + 40);
    // The status bar sits over a soft fade of the content.
    const fade = g.createLinearGradient(0, 0, 0, 170);
    fade.addColorStop(0, "rgba(238,240,247,1)");
    fade.addColorStop(1, "rgba(238,240,247,0)");
    g.fillStyle = fade;
    g.fillRect(0, 0, W, 170);
    drawChrome(g, this.android);
    this.texture.needsUpdate = true;
  }
}

// Your own media on a screen: a video (looped, silent) or an image.
export class MediaScreen {
  constructor(file) {
    this.name = file.name;
    this.url = URL.createObjectURL(file);
    this.isVideo = file.type.startsWith("video/");
    this.texture = null;
  }

  async load() {
    if (this.isVideo) {
      const v = document.createElement("video");
      v.src = this.url;
      v.muted = true;
      v.loop = true;
      v.playsInline = true;
      v.crossOrigin = "anonymous";
      await new Promise((ok, fail) => {
        v.addEventListener("loadeddata", ok, { once: true });
        v.addEventListener("error", () => fail(new Error(`Could not play ${this.name}`)), { once: true });
      });
      await v.play().catch(() => {});
      this.video = v;
      this.texture = new THREE.Texture(v);
      this.aspect = v.videoWidth / v.videoHeight;
    } else {
      const img = new Image();
      img.src = this.url;
      await img.decode();
      this.texture = new THREE.Texture(img);
      this.texture.needsUpdate = true;
      this.aspect = img.naturalWidth / img.naturalHeight;
    }
    this.texture.colorSpace = THREE.SRGBColorSpace;
    this.texture.anisotropy = 8;
    this.texture.generateMipmaps = false;
    this.texture.minFilter = THREE.LinearFilter;
    return this;
  }

  // Live preview: take the video's newest frame.
  update() {
    if (this.video && this.video.readyState >= 2) this.texture.needsUpdate = true;
  }

  // Export: show exactly the frame at time t.
  async seek(t) {
    if (!this.video) return;
    const v = this.video;
    v.pause();
    const target = v.duration ? t % v.duration : 0;
    if (Math.abs(v.currentTime - target) > 1e-4) {
      await new Promise((ok) => {
        v.addEventListener("seeked", ok, { once: true });
        v.currentTime = target;
      });
    }
    this.texture.needsUpdate = true;
  }

  resume() {
    this.video?.play().catch(() => {});
  }

  dispose() {
    this.video?.pause();
    this.texture?.dispose();
    URL.revokeObjectURL(this.url);
  }
}

// Fit a texture into a screen of the given aspect (cover, centred).
export function coverFit(texture, mediaAspect, screenAspect) {
  texture.repeat.set(1, 1);
  texture.offset.set(0, 0);
  if (mediaAspect > screenAspect) {
    const k = screenAspect / mediaAspect;
    texture.repeat.x = k;
    texture.offset.x = (1 - k) / 2;
  } else {
    const k = mediaAspect / screenAspect;
    texture.repeat.y = k;
    texture.offset.y = (1 - k) / 2;
  }
}
