// The studio: an environment of softboxes for the reflections (the long,
// clean highlights down a phone's frame and glass), a seamless backdrop,
// and soft contact shadows on an invisible floor.

import * as THREE from "three";
import { HorizontalBlurShader } from "three/addons/shaders/HorizontalBlurShader.js";
import { VerticalBlurShader } from "three/addons/shaders/VerticalBlurShader.js";

// A dim room lit by softboxes. Colours above 1 are light (HDR).
function softboxScene() {
  const scene = new THREE.Scene();
  const room = new THREE.Mesh(
    new THREE.SphereGeometry(50, 48, 24),
    new THREE.MeshBasicMaterial({ color: new THREE.Color(0.06, 0.06, 0.065), side: THREE.BackSide }),
  );
  scene.add(room);
  const box = (w, h, intensity, pos, look, tint = [1, 1, 1]) => {
    const m = new THREE.Mesh(
      new THREE.PlaneGeometry(w, h),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(tint[0] * intensity, tint[1] * intensity, tint[2] * intensity), side: THREE.DoubleSide }),
    );
    m.position.set(...pos);
    m.lookAt(...look);
    scene.add(m);
  };
  // The key: a big softbox above and in front.
  box(30, 18, 4.5, [0, 26, 14], [0, 0, 0]);
  // Two tall strips either side: the long highlights down the frame.
  box(3, 40, 7, [-24, 4, 6], [0, 0, 0]);
  box(3, 40, 6, [24, 4, 2], [0, 0, 0], [1, 0.98, 0.95]);
  // A rim from behind, and a broad soft fill from the camera side.
  box(40, 4, 5, [0, 10, -26], [0, 0, 0]);
  box(60, 20, 0.9, [0, 2, 40], [0, 0, 0]);
  // A warm and a cool card low down, for colour in the glass.
  box(12, 6, 1.4, [-18, -8, 18], [0, 0, 0], [1, 0.92, 0.84]);
  box(12, 6, 1.2, [18, -8, -10], [0, 0, 0], [0.86, 0.92, 1]);
  return scene;
}

export function studioEnvironment(renderer) {
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromScene(softboxScene(), 0.02).texture;
  pmrem.dispose();
  return env;
}

// The backdrop: a soft radial gradient, drawn once into a texture.
export const BACKDROPS = {
  Studio: ["#fbfbfd", "#e3e4e9"],
  White: ["#ffffff", "#f2f2f4"],
  Graphite: ["#4a4b50", "#1d1d1f"],
  Black: ["#1c1c1f", "#000000"],
  Midnight: ["#22304a", "#070b14"],
  Blush: ["#fdf3ef", "#ecd9d3"],
};

export function backdropTexture(inner, outer) {
  const c = document.createElement("canvas");
  c.width = c.height = 1024;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(512, 430, 40, 512, 560, 760);
  grad.addColorStop(0, inner);
  grad.addColorStop(1, outer);
  g.fillStyle = grad;
  g.fillRect(0, 0, 1024, 1024);
  // A whisper of grain, so wide gradients don't band in the video.
  const img = g.getImageData(0, 0, 1024, 1024);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (Math.random() - 0.5) * 3;
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// Contact shadows: the scene's depth seen from the floor looking up,
// darker where things are nearer the floor, blurred twice.
export class ContactShadows {
  constructor(renderer, scene, { width = 70, depth = 50, height = 32, floorY = -10.5, resolution = 1024 } = {}) {
    this.renderer = renderer;
    this.scene = scene;
    this.blur = 3.2;
    this.opacity = 0.55;
    this.group = new THREE.Group();
    this.group.position.y = floorY;
    scene.add(this.group);

    const rt = () => {
      const t = new THREE.WebGLRenderTarget(resolution, resolution);
      t.texture.generateMipmaps = false;
      return t;
    };
    this.target = rt();
    this.targetBlur = rt();

    const plane = new THREE.PlaneGeometry(width, depth).rotateX(Math.PI / 2);
    this.plane = new THREE.Mesh(plane, new THREE.MeshBasicMaterial({ map: this.target.texture, transparent: true, depthWrite: false, opacity: this.opacity }));
    this.plane.renderOrder = 1;
    this.plane.scale.y = -1;
    this.group.add(this.plane);
    this.blurPlane = new THREE.Mesh(plane);
    this.blurPlane.visible = false;
    this.group.add(this.blurPlane);

    this.camera = new THREE.OrthographicCamera(-width / 2, width / 2, depth / 2, -depth / 2, 0, height);
    this.camera.rotation.x = Math.PI / 2;
    this.group.add(this.camera);

    this.depthMaterial = new THREE.MeshDepthMaterial();
    this.depthMaterial.userData.darkness = { value: 1.4 };
    this.depthMaterial.onBeforeCompile = (shader) => {
      shader.uniforms.darkness = this.depthMaterial.userData.darkness;
      shader.fragmentShader = `uniform float darkness;\n${shader.fragmentShader.replace(
        "gl_FragColor = vec4( vec3( 1.0 - fragCoordZ ), opacity );",
        "gl_FragColor = vec4( vec3( 0.0 ), pow( 1.0 - fragCoordZ, 2.2 ) * darkness );",
      )}`;
    };
    this.depthMaterial.depthTest = false;
    this.depthMaterial.depthWrite = false;
    this.hBlur = new THREE.ShaderMaterial(HorizontalBlurShader);
    this.hBlur.depthTest = false;
    this.vBlur = new THREE.ShaderMaterial(VerticalBlurShader);
    this.vBlur.depthTest = false;
    this.resolution = resolution;
  }

  blurPass(amount) {
    const { renderer, blurPlane } = this;
    blurPlane.visible = true;
    blurPlane.material = this.hBlur;
    this.hBlur.uniforms.tDiffuse.value = this.target.texture;
    this.hBlur.uniforms.h.value = amount / this.resolution;
    renderer.setRenderTarget(this.targetBlur);
    renderer.render(blurPlane, this.camera);
    blurPlane.material = this.vBlur;
    this.vBlur.uniforms.tDiffuse.value = this.targetBlur.texture;
    this.vBlur.uniforms.v.value = amount / this.resolution;
    renderer.setRenderTarget(this.target);
    renderer.render(blurPlane, this.camera);
    blurPlane.visible = false;
  }

  update() {
    const { renderer, scene } = this;
    this.plane.material.opacity = this.opacity;
    this.plane.visible = false;
    const background = scene.background;
    scene.background = null;
    scene.overrideMaterial = this.depthMaterial;
    const clearAlpha = renderer.getClearAlpha();
    const clearColor = renderer.getClearColor(new THREE.Color());
    renderer.setClearColor(0x000000, 0);
    renderer.setRenderTarget(this.target);
    renderer.clear();
    renderer.render(scene, this.camera);
    scene.overrideMaterial = null;
    this.blurPass(this.blur);
    this.blurPass(this.blur * 0.45);
    renderer.setRenderTarget(null);
    renderer.setClearColor(clearColor, clearAlpha);
    scene.background = background;
    this.plane.visible = this.opacity > 0;
  }
}
