// <device-stage>: wrap your UI in a 3D phone.
//
//   <device-stage device="iphone17pro" finish="Deep Blue" shot="float">
//     <my-app></my-app>                       <!-- on device 1's screen -->
//   </device-stage>
//
//   <device-stage device="s25ultra" src="flow.html" shot="tilt"></device-stage>
//
// Children go on device 1's screen; a child with screen="2" or screen="3"
// goes on that device (for the duo and line-up shots). The screen is the
// phone's CSS viewport (402 x 874 on an iPhone 17 Pro); size your UI with
// 100% or the container units cqw / cqh, and pad it with
// var(--ds-safe-top) and var(--ds-safe-bottom).
//
// Attributes: device, finish, src (device 1's screen: a page, video or
// image URL), shot, duration, backdrop, interact ("screen" | "device"),
// aspect, paused, lock-toggle="off", and state (JSON, any part of the state).
// The element's `stage` is the DeviceStage, for set(), seek() and the rest.

import { DeviceStage } from "./stage.js";

const ATTRS = ["device", "finish", "src", "shot", "duration", "backdrop", "interact", "aspect", "paused", "state"];

function patchFrom(el, name) {
  const v = el.getAttribute(name);
  switch (name) {
    case "device":
      return v ? { slots: [{ model: v }] } : null;
    case "finish":
      return v ? { slots: [{ finish: v }] } : null;
    case "src":
      return v !== null ? { slots: [{ screen: v }] } : null;
    case "shot":
      return v ? { shot: v } : null;
    case "duration":
      return v ? { duration: Number(v) } : null;
    case "backdrop":
      return v ? { look: { backdrop: v } } : null;
    case "interact":
      return v ? { interact: v } : null;
    case "aspect":
      return v ? { output: { aspect: v } } : null;
    case "paused":
      return { playing: v === null };
    case "state":
      try {
        return v ? JSON.parse(v) : null;
      } catch {
        console.warn("<device-stage>: state is not valid JSON");
        return null;
      }
  }
  return null;
}

export class DeviceStageElement extends HTMLElement {
  static observedAttributes = ATTRS;

  connectedCallback() {
    if (this.stage) return;
    if (!this.style.display) this.style.display = "block";
    if (!this.style.position) this.style.position = "relative";
    const content = [...this.childNodes];
    const state = {};
    for (const name of ATTRS) {
      const patch = patchFrom(this, name);
      if (patch) deepAssign(state, patch);
    }
    this.replaceChildren();
    this.stage = new DeviceStage(this, { state, lockToggle: this.getAttribute("lock-toggle") !== "off" });
    // Children onto the screens.
    const bySlot = [[], [], []];
    for (const node of content) {
      const n = node.nodeType === 1 ? Number(node.getAttribute("screen")) : 0;
      if (node.nodeType === 3 && !node.textContent.trim()) continue;
      bySlot[n >= 2 && n <= 3 ? n - 1 : 0].push(node);
    }
    bySlot.forEach((nodes, i) => {
      if (nodes.length) this.stage.screen(i).append(...nodes);
    });
    this.dispatchEvent(new CustomEvent("ready", { detail: this.stage }));
  }

  attributeChangedCallback(name) {
    if (!this.stage) return;
    const patch = patchFrom(this, name);
    if (patch) this.stage.set(patch);
  }

  disconnectedCallback() {
    // Kept alive if only moved; destroyed if it doesn't come back.
    queueMicrotask(() => {
      if (!this.isConnected && this.stage) {
        this.stage.destroy();
        this.stage = null;
      }
    });
  }
}

function deepAssign(target, patch) {
  for (const [k, v] of Object.entries(patch)) {
    if (Array.isArray(v)) {
      target[k] = target[k] || [];
      v.forEach((item, i) => {
        target[k][i] = Object.assign(target[k][i] || {}, item);
      });
    } else if (v && typeof v === "object") {
      target[k] = deepAssign(target[k] || {}, v);
    } else target[k] = v;
  }
  return target;
}

export function defineDeviceStage(tag = "device-stage") {
  if (!customElements.get(tag)) customElements.define(tag, class extends DeviceStageElement {});
}
