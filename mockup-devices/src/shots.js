// The shot library. A shot maps progress p (0-1 over its length) to where
// each device is and where the camera looks from. Slots: 0 the hero
// device, 1 the second, 2 the third. Rotations are [tilt, turn, roll] in
// radians (applied turn last, so a leaning phone turns about the vertical).
// Looping shots end where they start.

import * as THREE from "three";

const TAU = Math.PI * 2;
const lerp = (a, b, t) => a + (b - a) * t;
const mix = (a, b, t) => a.map((v, i) => lerp(v, b[i], t));
const clamp01 = (x) => Math.min(Math.max(x, 0), 1);
const inOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const outQuart = (t) => 1 - Math.pow(1 - t, 4);
const outCubic = (t) => 1 - Math.pow(1 - t, 3);
const inOutSine = (t) => -(Math.cos(Math.PI * t) - 1) / 2;
const seg = (p, a, b) => inOut(clamp01((p - a) / (b - a)));

// A point on a device (its own coordinates) in the world.
const _e = new THREE.Euler(0, 0, 0, "YXZ");
const _v = new THREE.Vector3();
function onDevice(pos, rot, local) {
  _e.set(rot[0], rot[1], rot[2]);
  _v.set(...local).applyEuler(_e);
  return [_v.x + pos[0], _v.y + pos[1], _v.z + pos[2]];
}

export const SHOTS = [
  {
    id: "reveal", name: "Reveal: side to front", count: 1, dur: 7, loop: false,
    fn(p) {
      const e = inOut(p);
      return {
        items: [{ slot: 0, pos: [0, lerp(-0.6, 0, e), 0], rot: [lerp(0.02, 0.05, e), lerp(-1.48, -0.2, e), 0] }],
        cam: { pos: [lerp(7, 3.4, e), lerp(1.8, 1, e), lerp(54, 41, e)], target: [0, 0, 0], fov: 28 },
      };
    },
  },
  {
    id: "float", name: "Float", count: 1, dur: 8, loop: true,
    fn(p) {
      const a = TAU * p;
      return {
        items: [{ slot: 0, pos: [0, 0.45 * Math.sin(a), 0], rot: [0.05 * Math.sin(2 * a + 1), -0.32 + 0.22 * Math.sin(a), 0.04 * Math.sin(a + 0.6)] }],
        cam: { pos: [-3 + 2 * Math.sin(a), 1.6 + 0.8 * Math.cos(a), 44], target: [0, -0.3, 0], fov: 28 },
      };
    },
  },
  {
    id: "tilt", name: "Side tilt, low angle", count: 1, dur: 7, loop: false,
    fn(p) {
      const e = inOut(p);
      return {
        items: [{ slot: 0, pos: [0, 0, 0], rot: [-0.24, lerp(-1.0, -0.38, e), 0.1] }],
        cam: { pos: mix([-15, -7.5, 31], [-9.5, -6, 27], e), target: [0, 1.4, 0], fov: 30, roll: lerp(0.09, 0.03, e) },
      };
    },
  },
  {
    id: "turntable", name: "Turntable 360", count: 1, dur: 10, loop: true,
    fn(p) {
      return {
        items: [{ slot: 0, pos: [0, 0.2 * Math.sin(TAU * p), 0], rot: [0.04, -0.35 + TAU * p, 0] }],
        cam: { pos: [0, 4, 47], target: [0, -0.3, 0], fov: 27 },
      };
    },
  },
  {
    id: "flip", name: "Flip: screen, back, screen", count: 1, dur: 8, loop: true,
    fn(p) {
      const turn = Math.PI * (seg(p, 0.12, 0.42) + seg(p, 0.6, 0.9));
      return {
        items: [{ slot: 0, pos: [0, 0.3 * Math.sin(TAU * p), 0], rot: [0.03, -0.2 + turn, 0.03 * Math.sin(TAU * p)] }],
        cam: { pos: [2, 1.4, 45 - 3 * Math.sin(Math.PI * p)], target: [0, 0, 0], fov: 28 },
      };
    },
  },
  {
    id: "macro", name: "Camera close-up", count: 1, dur: 7, loop: false,
    fn(p, ctx) {
      const e = inOut(p);
      const spec = ctx.spec(0);
      const pos = [0, 0, 0];
      const rot = [0.06, Math.PI + lerp(0.55, 0.12, e), 0];
      const [mx, my] = spec.module;
      const target = onDevice(pos, rot, [-mx, my, -spec.d / 2 - 0.25]);
      const normal = onDevice([0, 0, 0], rot, [0, 0, -1]);
      const dist = lerp(12, 8.5, e);
      return {
        items: [{ slot: 0, pos, rot }],
        cam: {
          pos: [target[0] + normal[0] * dist + lerp(3, -1.5, e), target[1] + lerp(1.6, 0.4, e), target[2] + normal[2] * dist],
          target, fov: 26, roll: lerp(-0.04, 0.02, e),
        },
      };
    },
  },
  {
    id: "screen", name: "Screen: the app flow", count: 1, dur: 10, loop: true,
    fn(p) {
      const a = TAU * p;
      return {
        items: [{ slot: 0, pos: [0, 0, 0], rot: [0.025 * Math.sin(a + 1), 0.06 * Math.sin(a), 0] }],
        cam: { pos: [0.6 * Math.sin(a), 0.3, 30.5], target: [0, 0, 0], fov: 30 },
      };
    },
  },
  {
    id: "spin", name: "Spin in", count: 1, dur: 6, loop: false,
    fn(p) {
      const e = outQuart(clamp01(p / 0.85));
      return {
        items: [{ slot: 0, pos: [0, lerp(14, 0, outCubic(clamp01(p / 0.8))), 0], rot: [lerp(0.5, 0.04, e), lerp(-3 * Math.PI - 0.2, -0.2, e), lerp(0.3, 0, e)] }],
        cam: { pos: [2.5, 1, lerp(48, 44, p)], target: [0, 0, 0], fov: 28 },
      };
    },
  },
  {
    id: "orbit", name: "Orbit, high to low", count: 1, dur: 8, loop: false,
    fn(p) {
      const e = inOutSine(p);
      const a = lerp(-0.8, 0.8, e);
      return {
        items: [{ slot: 0, pos: [0, 0, 0], rot: [-0.04, -0.12, 0] }],
        cam: { pos: [44 * Math.sin(a), lerp(8, 0.5, e), 44 * Math.cos(a)], target: [0, 0, 0], fov: 28 },
      };
    },
  },
  {
    id: "duo", name: "Duo, floating", count: 2, dur: 9, loop: true,
    fn(p) {
      const a = TAU * p;
      const x = 4 * Math.sin(a);
      return {
        items: [
          { slot: 0, pos: [-4.7, 0.4 + 0.35 * Math.sin(a), 1.5], rot: [0.03, 0.32 + 0.06 * Math.sin(a), 0.02] },
          { slot: 1, pos: [4.7, -0.4 + 0.35 * Math.sin(a + Math.PI), -2.5], rot: [0.03, -0.38 + 0.06 * Math.sin(a + 2), -0.02] },
        ],
        cam: { pos: [x, 1.6, 50], target: [x * 0.35, 0, 0], fov: 30 },
        fitWidth: 23,
      };
    },
  },
  {
    id: "lineup", name: "Line-up of three", count: 3, dur: 10, loop: true,
    fn(p) {
      const a = TAU * p;
      const x = 6 * Math.sin(a);
      return {
        items: [
          { slot: 1, pos: [-9.8, 0.3 * Math.sin(a + 2), -1], rot: [0.03, 0.38, 0] },
          { slot: 0, pos: [0, 0.3 * Math.sin(a), 1.5], rot: [0.03, 0.04 * Math.sin(a), 0] },
          { slot: 2, pos: [9.8, 0.3 * Math.sin(a + 4), -1], rot: [0.03, -0.38, 0] },
        ],
        cam: { pos: [x, 2, 60], target: [x * 0.5, 0, 0], fov: 30 },
        fitWidth: 36,
      };
    },
  },
  {
    id: "custom", name: "Your move (A to B)", count: 1, dur: 8, loop: false,
    fn(p, ctx) {
      const e = inOut(p);
      const a = TAU * p;
      const { a: A, b: B } = ctx.custom;
      return {
        items: [{ slot: 0, pos: [0, 0.3 * Math.sin(a), 0], rot: [0.04 * Math.sin(a + 1), -0.2 + 0.12 * Math.sin(a), 0] }],
        cam: { pos: mix(A.pos, B.pos, e), target: mix(A.target, B.target, e), fov: lerp(A.fov, B.fov, e) },
      };
    },
  },
];
