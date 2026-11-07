// device-stage: real phones in a studio, with your live UI on their screens.
//
//   import { defineDeviceStage } from "device-stage";
//   defineDeviceStage();   // then <device-stage> ... </device-stage>
//
//   import { DeviceStage } from "device-stage";
//   const stage = new DeviceStage(container, { state: { shot: "tilt" } });

export { DeviceStage, DEFAULTS, ASPECTS } from "./stage.js";
export { DeviceStageElement, defineDeviceStage } from "./element.js";
export { DEVICES } from "./devices.js";
export { SHOTS } from "./shots.js";
export { BACKDROPS } from "./studio.js";
