// The phones, modelled in code at their real sizes (1 unit = 1 cm). Each
// device is a group centred on its middle: the screen faces +z, up is +y.
// No logos or wordmarks, only the silhouettes, the camera layouts and the
// finishes.

import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";

// Sizes in cm. `edge` is how round the frame is (the bevel), `corner` the
// corner radius seen from the front, `bezel` the black border round the
// screen, `module` the camera module's centre as seen from the back.
export const DEVICES = {
  iphone17pro: {
    name: "iPhone 17 Pro",
    w: 7.19, h: 15.0, d: 0.875, corner: 1.16, edge: 0.26, bezel: 0.14,
    cutout: "island", module: [-3.595 + 1.9, 7.5 - 1.92],
    finishes: {
      "Cosmic Orange": { frame: "#c4622d", back: "#d9733e", rough: 0.34 },
      "Deep Blue": { frame: "#2c3749", back: "#344156", rough: 0.32 },
      "Silver": { frame: "#d8d8d4", back: "#e6e6e2", rough: 0.3 },
    },
  },
  iphoneAir: {
    name: "iPhone Air",
    w: 7.47, h: 15.62, d: 0.564, corner: 1.2, edge: 0.2, bezel: 0.14,
    cutout: "island", module: [-3.735 + 1.45, 7.81 - 1.445],
    finishes: {
      "Sky Blue": { frame: "#c3d3e3", back: "#d7e3ef", rough: 0.16 },
      "Light Gold": { frame: "#e2cfae", back: "#efe2c9", rough: 0.16 },
      "Cloud White": { frame: "#e9e9e6", back: "#f4f4f1", rough: 0.16 },
      "Space Black": { frame: "#2a2a2c", back: "#1f1f21", rough: 0.18 },
    },
  },
  s25ultra: {
    name: "Galaxy S25 Ultra",
    w: 7.76, h: 16.28, d: 0.82, corner: 0.98, edge: 0.12, bezel: 0.13,
    cutout: "punch", module: [-3.88 + 1.9, 8.14 - 2.95],
    finishes: {
      "Titanium Silverblue": { frame: "#9aa6b4", back: "#a9b4c1", rough: 0.36 },
      "Titanium Black": { frame: "#2c2c2e", back: "#232325", rough: 0.36 },
      "Titanium Gray": { frame: "#8c8b88", back: "#9a9995", rough: 0.36 },
      "Titanium Whitesilver": { frame: "#d6d6d4", back: "#e3e3e1", rough: 0.36 },
    },
  },
};

// A rounded rectangle, centred; the top and bottom corners can differ.
function roundedRect(w, h, rTop, rBottom = rTop) {
  const x = -w / 2, y = -h / 2;
  const s = new THREE.Shape();
  s.moveTo(x + rBottom, y);
  s.lineTo(x + w - rBottom, y);
  s.quadraticCurveTo(x + w, y, x + w, y + rBottom);
  s.lineTo(x + w, y + h - rTop);
  s.quadraticCurveTo(x + w, y + h, x + w - rTop, y + h);
  s.lineTo(x + rTop, y + h);
  s.quadraticCurveTo(x, y + h, x, y + h - rTop);
  s.lineTo(x, y + rBottom);
  s.quadraticCurveTo(x, y, x + rBottom, y);
  return s;
}

// A flat rounded rectangle with 0-1 UVs across it (for the screen).
function flatPanel(w, h, r, segments = 24) {
  const g = new THREE.ShapeGeometry(roundedRect(w, h, r), segments);
  const pos = g.attributes.position, uv = g.attributes.uv;
  for (let i = 0; i < pos.count; i++) {
    uv.setXY(i, pos.getX(i) / w + 0.5, pos.getY(i) / h + 0.5);
  }
  return g;
}

// A slab with rounded edges: the outline extruded, its edges bevelled.
function slab(shapeW, shapeH, rTop, rBottom, depth, bevel) {
  const b = Math.min(bevel, depth / 2 - 0.001);
  const g = new THREE.ExtrudeGeometry(
    roundedRect(shapeW - 2 * b, shapeH - 2 * b, Math.max(rTop - b, 0.01), Math.max(rBottom - b, 0.01)),
    { depth: depth - 2 * b, bevelEnabled: true, bevelThickness: b, bevelSize: b, bevelSegments: 10, curveSegments: 32 },
  );
  g.translate(0, 0, -(depth - 2 * b) / 2);
  g.computeVertexNormals();
  return g;
}

// Shared materials for the glass and the lenses.
const MAT = {
  black: new THREE.MeshPhysicalMaterial({ color: "#050506", roughness: 0.08, clearcoat: 1, clearcoatRoughness: 0.04 }),
  lensGlass: new THREE.MeshPhysicalMaterial({
    color: "#020204", roughness: 0.03, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.02,
    iridescence: 0.45, iridescenceIOR: 1.5, iridescenceThicknessRange: [200, 480],
  }),
  pupil: new THREE.MeshPhysicalMaterial({ color: "#000000", roughness: 0.02, clearcoat: 1, clearcoatRoughness: 0.01, iridescence: 0.7, iridescenceIOR: 1.7 }),
  lensInner: new THREE.MeshPhysicalMaterial({ color: "#020203", roughness: 0.2, metalness: 0.6 }),
  sapphire: new THREE.MeshPhysicalMaterial({ color: "#0d0e12", roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.05 }),
  port: new THREE.MeshStandardMaterial({ color: "#0a0a0b", roughness: 0.6 }),
  antenna: new THREE.MeshStandardMaterial({ color: "#3a3a3c", roughness: 0.55 }),
  flash: new THREE.MeshPhysicalMaterial({ color: "#f3ead6", roughness: 0.25, transmission: 0.2, clearcoat: 1 }),
};

// The glass over the screen: it only adds reflections (black, added on),
// strong at grazing angles as real glass is. It leaves alpha alone, so over
// a live DOM screen (a clear hole in the canvas) the reflections lie on the
// page below.
export function glassMaterial() {
  return new THREE.MeshPhysicalMaterial({
    color: "#000000", roughness: 0.03, metalness: 0, ior: 1.52, specularIntensity: 1,
    transparent: true, depthWrite: false,
    blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
    blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor,
    blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor,
  });
}

function lens(r, rise, frameMat, kind = "lens") {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.CylinderGeometry(r, r * 1.02, rise, 64, 1), frameMat);
  ring.rotation.x = Math.PI / 2;
  ring.position.z = rise / 2;
  g.add(ring);
  // A thin polished lip, then the glass and its inner dark rings.
  const lip = new THREE.Mesh(new THREE.TorusGeometry(r * 0.94, r * 0.05, 12, 64), frameMat);
  lip.position.z = rise;
  g.add(lip);
  if (kind === "lens") {
    const glass = new THREE.Mesh(new THREE.CircleGeometry(r * 0.88, 64), MAT.lensGlass);
    glass.position.z = rise + 0.008;
    g.add(glass);
    const inner = new THREE.Mesh(new THREE.RingGeometry(r * 0.4, r * 0.47, 64), MAT.lensInner);
    inner.position.z = rise + 0.016;
    g.add(inner);
    const pupil = new THREE.Mesh(new THREE.CircleGeometry(r * 0.4, 48), MAT.pupil);
    pupil.position.z = rise + 0.012;
    g.add(pupil);
  } else {
    const face = new THREE.Mesh(new THREE.CircleGeometry(r * 0.86, 48), kind === "flash" ? MAT.flash : MAT.sapphire);
    face.position.z = rise + 0.008;
    g.add(face);
  }
  return g;
}

function button(len, frameMat, depthAlong, bulge = 0.07) {
  return new THREE.Mesh(new RoundedBoxGeometry(bulge * 2, len, depthAlong, 4, Math.min(bulge, depthAlong / 2) * 0.95), frameMat);
}

// Builds one device; returns { group, screen, glass, spec, setFinish }.
export function buildDevice(id, finishName) {
  const spec = DEVICES[id];
  const { w, h, d, corner, edge, bezel } = spec;
  const group = new THREE.Group();
  group.name = spec.name;

  const frameMat = new THREE.MeshPhysicalMaterial({ metalness: 1, roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.2 });
  const backMat = new THREE.MeshPhysicalMaterial({ metalness: 0, roughness: 0.5, clearcoat: 0.6, clearcoatRoughness: 0.35, sheen: 0.2 });

  // The body: one rounded slab in the frame's metal.
  const body = new THREE.Mesh(slab(w, h, corner, corner, d, edge), frameMat);
  group.add(body);

  // Front: black glass, the screen, the glass's reflections, the camera cutout.
  const front = d / 2;
  const glassInset = edge * 0.45;
  const cover = new THREE.Mesh(new THREE.ShapeGeometry(roundedRect(w - 2 * glassInset, h - 2 * glassInset, corner - glassInset), 32), MAT.black);
  cover.position.z = front + 0.004;
  group.add(cover);

  const sw = w - 2 * glassInset - 2 * bezel;
  const sh = h - 2 * glassInset - 2 * bezel;
  const screenMat = new THREE.MeshBasicMaterial({ color: "#ffffff", toneMapped: false });
  const screen = new THREE.Mesh(flatPanel(sw, sh, corner - glassInset - bezel * 0.6, 32), screenMat);
  screen.position.z = front + 0.012;
  screen.userData.aspect = sw / sh;
  group.add(screen);

  if (spec.cutout === "island") {
    const iw = 1.26, ih = 0.37;
    const island = new THREE.Mesh(new THREE.ShapeGeometry(roundedRect(iw, ih, ih / 2), 16), MAT.black);
    island.position.set(0, sh / 2 - 0.12 - ih / 2, front + 0.02);
    group.add(island);
  } else {
    const hole = new THREE.Mesh(new THREE.CircleGeometry(0.16, 32), MAT.black);
    hole.position.set(0, sh / 2 - 0.36, front + 0.02);
    group.add(hole);
  }

  const glass = new THREE.Mesh(new THREE.ShapeGeometry(roundedRect(w - 2 * glassInset, h - 2 * glassInset, corner - glassInset), 32), glassMaterial());
  glass.position.z = front + 0.03;
  glass.renderOrder = 2;
  group.add(glass);

  // Back: a group turned to face -z, so its x runs right as seen from behind.
  const back = new THREE.Group();
  back.rotation.y = Math.PI;
  back.position.z = -d / 2;
  group.add(back);
  const backPanel = new THREE.Mesh(new THREE.ShapeGeometry(roundedRect(w - 2 * glassInset, h - 2 * glassInset, corner - glassInset), 32), backMat);
  backPanel.position.z = 0.01;
  back.add(backPanel);

  const top = h / 2, left = -w / 2, right = w / 2;
  if (id === "iphone17pro") {
    // The full-width plateau, its top corners following the body's.
    const ph = 3.55, inset = 0.16;
    const plateau = new THREE.Mesh(slab(w - 2 * inset, ph, corner - inset, 0.55, 0.26, 0.08), frameMat);
    plateau.position.set(0, top - inset - ph / 2, 0.13);
    back.add(plateau);
    const z = 0.26;
    for (const [x, y] of [[left + 1.28, top - 1.22], [left + 1.28, top - 2.62], [left + 2.5, top - 1.92]]) {
      const l = lens(0.6, 0.15, frameMat);
      l.position.set(x, y, z);
      back.add(l);
    }
    const flash = lens(0.26, 0.04, frameMat, "flash");
    flash.position.set(right - 1.05, top - 1.22, z);
    back.add(flash);
    const lidar = lens(0.24, 0.04, frameMat, "sensor");
    lidar.position.set(right - 1.05, top - 2.62, z);
    back.add(lidar);
  } else if (id === "iphoneAir") {
    // The plateau: one pill across the top.
    const pw = w - 0.9, ph = 2.05;
    const plateau = new THREE.Mesh(slab(pw, ph, ph / 2, ph / 2, 0.24, 0.08), frameMat);
    plateau.position.set(0, top - 0.42 - ph / 2, 0.12);
    back.add(plateau);
    const y = top - 0.42 - ph / 2;
    const l = lens(0.66, 0.14, frameMat);
    l.position.set(left + 0.45 + ph / 2, y, 0.24);
    back.add(l);
    const front2 = lens(0.22, 0.03, frameMat, "sensor");
    front2.position.set(left + 2.4, y, 0.24);
    back.add(front2);
    const flash = lens(0.2, 0.03, frameMat, "flash");
    flash.position.set(right - 1.4, y, 0.24);
    back.add(flash);
  } else {
    // A column of separate lenses, a smaller one beside, flash and laser AF.
    const x = left + 1.48;
    for (const y of [top - 1.55, top - 2.95, top - 4.35]) {
      const l = lens(0.6, 0.13, frameMat);
      l.position.set(x, y, 0);
      back.add(l);
    }
    const tele = lens(0.42, 0.11, frameMat);
    tele.position.set(x + 1.3, top - 1.55, 0);
    back.add(tele);
    const flash = lens(0.17, 0.02, frameMat, "flash");
    flash.position.set(x + 1.3, top - 2.6, 0);
    back.add(flash);
    const laser = lens(0.13, 0.02, frameMat, "sensor");
    laser.position.set(x + 1.3, top - 3.15, 0);
    back.add(laser);
  }

  // Buttons on the sides (left / right as seen from the front).
  const sideDepth = Math.max(d - 2 * edge, 0.2) * 0.8;
  const addButton = (side, y, len, mat = frameMat) => {
    const b = button(len, mat, sideDepth);
    b.position.set(side * (w / 2 - 0.035), y, 0);
    group.add(b);
  };
  if (id === "s25ultra") {
    addButton(1, 3.4, 2.1);
    addButton(1, 1.3, 1.15);
  } else {
    addButton(-1, 4.3, 0.75);
    addButton(-1, 2.9, 1.05);
    addButton(-1, 1.6, 1.05);
    addButton(1, 2.6, 1.7);
    addButton(1, -1.9, 1.45, MAT.sapphire); // camera control, flush sapphire
  }

  // Antenna bands across the frame, near the top and bottom corners.
  for (const [x, y] of [[-1, h / 2 - 1.6], [1, h / 2 - 1.6], [-1, -h / 2 + 1.6], [1, -h / 2 + 1.6]]) {
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.08, sideDepth * 1.05), MAT.antenna);
    band.position.set(x * (w / 2 - 0.005), y, 0);
    group.add(band);
  }

  // The bottom edge: the port and the speaker holes.
  const port = new THREE.Mesh(new RoundedBoxGeometry(0.9, 0.06, 0.3, 4, 0.029), MAT.port);
  port.position.set(0, -h / 2 + 0.01, 0);
  group.add(port);
  const holeGeo = new THREE.CylinderGeometry(0.045, 0.045, 0.06, 16);
  for (let i = 0; i < 6; i++) {
    for (const side of [-1, 1]) {
      const hole = new THREE.Mesh(holeGeo, MAT.port);
      hole.position.set(side * (0.85 + i * 0.17), -h / 2 + 0.012, 0);
      group.add(hole);
    }
  }

  group.traverse((o) => {
    if (o.isMesh) o.castShadow = false;
  });

  function setFinish(name) {
    const f = spec.finishes[name] || Object.values(spec.finishes)[0];
    frameMat.color.set(f.frame);
    frameMat.roughness = f.rough;
    backMat.color.set(f.back);
    group.userData.finish = name in spec.finishes ? name : Object.keys(spec.finishes)[0];
  }
  setFinish(finishName);

  return { id, group, screen, glass, spec, setFinish };
}
