// The control panel: collapsible sections, each control bound to one path
// in the state (the same paths a script sets through window.mockup.set).

const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null && v !== false) n.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat()) if (k !== null && k !== undefined) n.append(k);
  return n;
};
const getPath = (o, path) => path.split(".").reduce((v, k) => v?.[k], o);
function patchFor(path, value) {
  const keys = path.split(".");
  const root = {};
  let o = root;
  keys.forEach((k, i) => {
    const next = keys[i + 1];
    if (i === keys.length - 1) o[k] = value;
    else o = o[k] = /^\d+$/.test(next) ? [] : {};
  });
  return root;
}
const fmt = (v, step) => (step >= 1 ? String(Math.round(v)) : String(+v.toFixed(step < 0.1 ? 2 : 1)));

export function buildUI(api, state, { DEVICES, BACKDROPS, ASPECTS, loadFile }) {
  const panel = document.getElementById("panel");
  const body = document.getElementById("panel-body");
  const binds = [];
  const OPEN = "mockup-open-sections";
  let open = {};
  try {
    open = JSON.parse(localStorage.getItem(OPEN) || "{}");
  } catch {}

  const section = (id, title, ...kids) => {
    const d = el("details", { class: "section", open: open[id] ?? ["shot", "devices", "camera"].includes(id) }, el("summary", {}, title), el("div", { class: "section__body" }, ...kids));
    d.addEventListener("toggle", () => {
      open[id] = d.open;
      try {
        localStorage.setItem(OPEN, JSON.stringify(open));
      } catch {}
    });
    return d;
  };

  // A labelled slider bound to a path. `manual` sliders take the camera
  // over from the shot first.
  const slider = (path, label, min, max, step, { manual = false, unit = "" } = {}) => {
    const out = el("output");
    const input = el("input", { type: "range", min, max, step });
    input.addEventListener("input", () => {
      if (manual) api.takeOver();
      api.set(patchFor(path, Number(input.value)));
    });
    // Double-click a slider to type an exact value.
    out.addEventListener("dblclick", () => {
      const v = prompt(label, getPath(state, path));
      if (v !== null && v.trim() !== "" && !Number.isNaN(Number(v))) {
        if (manual) api.takeOver();
        api.set(patchFor(path, Number(v)));
      }
    });
    binds.push((s) => {
      const v = getPath(s, path);
      if (document.activeElement !== input) input.value = v;
      out.textContent = fmt(Number(v), step) + unit;
    });
    return el("label", { class: "slider" }, el("span", {}, label), out, input);
  };

  const select = (path, label, options, onChange) => {
    const s = el("select", {}, options.map(([value, text]) => el("option", { value }, text)));
    s.addEventListener("change", () => (onChange ? onChange(s.value) : api.set(patchFor(path, s.value))));
    binds.push((st) => (s.value = String(getPath(st, path))));
    return el("label", { class: "field" }, el("span", {}, label), s);
  };

  const segmented = (path, options, cast = String) => {
    const wrap = el("div", { class: "segmented" });
    for (const [value, text] of options) {
      const b = el("button", { type: "button", onclick: () => api.set(patchFor(path, cast(value))) }, text);
      b.dataset.value = value;
      wrap.append(b);
    }
    binds.push((s) => {
      for (const b of wrap.children) b.classList.toggle("on", b.dataset.value === String(getPath(s, path)));
    });
    return wrap;
  };

  // --- Shot -----------------------------------------------------------------
  const layoutRow = el("div", { class: "row" }, el("span", { class: "hint" }, "Devices"), segmented("layout", [["1", "One"], ["2", "Two"], ["3", "Three"]], Number));
  binds.push((s) => (layoutRow.hidden = s.shot !== "manual"));
  body.append(
    section(
      "shot", "Shot",
      select("shot", "Camera move", api.shots.map((s) => [s.id, s.devices > 1 ? `${s.name} · ${s.devices} devices` : s.name])),
      layoutRow,
      slider("duration", "Length", 2, 30, 0.5, { unit: " s" }),
      slider("speed", "Preview speed", 0.1, 2, 0.05, { unit: "×" }),
    ),
  );

  // --- Devices --------------------------------------------------------------
  const deviceCard = (i, title) => {
    const model = select(`slots.${i}.model`, "Model", Object.entries(DEVICES).map(([id, d]) => [id, d.name]), (v) => {
      api.set(patchFor(`slots.${i}`, { model: v, finish: Object.keys(DEVICES[v].finishes)[0] }));
    });
    const swatches = el("div", { class: "swatches" });
    const finishName = el("span", { class: "hint" });
    binds.push((s) => {
      const slot = s.slots[i];
      const finishes = DEVICES[slot.model].finishes;
      if (swatches.dataset.model !== slot.model) {
        swatches.dataset.model = slot.model;
        swatches.replaceChildren(
          ...Object.entries(finishes).map(([name, f]) =>
            el("button", { type: "button", class: "swatch", title: name, style: `--c:${f.back};--e:${f.frame}`, onclick: () => api.set(patchFor(`slots.${i}.finish`, name)) }),
          ),
        );
      }
      for (const b of swatches.children) b.classList.toggle("on", b.title === slot.finish);
      finishName.textContent = slot.finish;
    });
    const file = el("input", { type: "file", accept: "video/*,image/*", hidden: true });
    file.addEventListener("change", () => {
      if (file.files[0]) loadFile(i, file.files[0]);
      file.value = "";
    });
    const screenName = el("span", { class: "hint ellipsis" });
    binds.push((s) => {
      const src = s.slots[i].screen;
      screenName.textContent = src ? decodeURIComponent(src.split("/").pop()).replace(/^[0-9a-f-]{36}$/, "your file") : "Demo app";
    });
    return el(
      "div", { class: "card" },
      el("div", { class: "card__title" }, title),
      model,
      el("div", { class: "row" }, swatches, finishName),
      el(
        "div", { class: "row" },
        el("button", { type: "button", class: "btn small", onclick: () => file.click() }, "Screen video / image"),
        el("button", { type: "button", class: "btn small ghost", onclick: () => api.setScreen(i, "") }, "Demo"),
        file,
      ),
      screenName,
    );
  };
  body.append(
    section(
      "devices", "Devices",
      deviceCard(0, "Device 1 · the hero"),
      deviceCard(1, "Device 2 · in duo and line-up shots"),
      deviceCard(2, "Device 3 · in the line-up"),
      el("p", { class: "hint" }, "Drop a screen recording anywhere on the page to put it on device 1."),
    ),
  );

  // --- Camera ---------------------------------------------------------------
  const moveRow = el(
    "div", { class: "row wrap" },
    el("button", { type: "button", class: "btn small", onclick: () => { api.takeOver(); api.set({ move: { a: { ...api.get().camera } } }); api.toast("Saved as A"); } }, "Save as A"),
    el("button", { type: "button", class: "btn small", onclick: () => { api.takeOver(); api.set({ move: { b: { ...api.get().camera } } }); api.toast("Saved as B"); } }, "Save as B"),
    el("button", { type: "button", class: "btn small ghost", onclick: () => api.set({ shot: "custom", playing: true }) }, "Play A → B"),
  );
  body.append(
    section(
      "camera", "Camera",
      el("p", { class: "hint" }, "Moving these (or dragging the view, or scrolling on it) takes over from the shot: it switches to Manual."),
      slider("camera.azimuth", "Orbit (Y axis)", -180, 180, 0.5, { manual: true, unit: "°" }),
      slider("camera.elevation", "Height angle (X axis)", -60, 75, 0.5, { manual: true, unit: "°" }),
      slider("camera.roll", "Roll (Z axis)", -45, 45, 0.5, { manual: true, unit: "°" }),
      slider("camera.distance", "Distance", 8, 160, 0.5, { manual: true, unit: " cm" }),
      slider("camera.fov", "Lens (field of view)", 8, 80, 0.5, { manual: true, unit: "°" }),
      slider("camera.targetX", "Aim, sideways", -20, 20, 0.1, { manual: true }),
      slider("camera.targetY", "Aim, up and down", -10, 10, 0.1, { manual: true }),
      moveRow,
    ),
  );

  // --- Device pose ----------------------------------------------------------
  body.append(
    section(
      "pose", "Device rotation and position",
      el("p", { class: "hint" }, "Added on top of the shot's own motion; in Manual, this is the pose."),
      slider("device.rotX", "Tilt (X axis)", -180, 180, 0.5, { unit: "°" }),
      slider("device.rotY", "Turn (Y axis)", -180, 180, 0.5, { unit: "°" }),
      slider("device.rotZ", "Roll (Z axis)", -180, 180, 0.5, { unit: "°" }),
      slider("device.x", "Move X", -20, 20, 0.1),
      slider("device.y", "Move Y", -12, 12, 0.1),
      slider("device.z", "Move Z", -30, 20, 0.1),
      slider("device.float", "Float (Manual)", 0, 2, 0.05),
      el("button", { type: "button", class: "btn small ghost", onclick: () => api.set({ device: { rotX: 0, rotY: 0, rotZ: 0, x: 0, y: 0, z: 0, float: 1 } }) }, "Reset the pose"),
    ),
  );

  // --- Look -----------------------------------------------------------------
  const backdrops = el("div", { class: "swatches big" });
  for (const [name, [inner, outer]] of Object.entries(BACKDROPS)) {
    backdrops.append(el("button", { type: "button", class: "swatch", title: name, style: `--c:${inner};--e:${outer}`, onclick: () => api.set({ look: { backdrop: name } }) }));
  }
  const custom = el("button", { type: "button", class: "swatch custom", title: "Custom", onclick: () => api.set({ look: { backdrop: "Custom" } }) });
  backdrops.append(custom);
  const backdropName = el("span", { class: "hint" });
  binds.push((s) => {
    for (const b of backdrops.children) b.classList.toggle("on", b.title === s.look.backdrop);
    backdropName.textContent = s.look.backdrop;
    custom.style.cssText = `--c:${s.look.inner};--e:${s.look.outer}`;
  });
  const color = (path, label) => {
    const input = el("input", { type: "color" });
    input.addEventListener("input", () => api.set({ look: { backdrop: "Custom", [path.split(".")[1]]: input.value } }));
    binds.push((s) => (input.value = getPath(s, path)));
    return el("label", { class: "color" }, input, el("span", {}, label));
  };
  body.append(
    section(
      "look", "Look",
      el("div", { class: "row" }, backdrops, backdropName),
      el("div", { class: "row" }, color("look.inner", "Centre"), color("look.outer", "Edges")),
      slider("look.shadow", "Floor shadow", 0, 1, 0.01),
      slider("look.reflections", "Reflections", 0, 3, 0.05),
      slider("look.exposure", "Exposure", 0.3, 2, 0.01),
      slider("look.glare", "Glass glare", 0, 3, 0.05),
      slider("look.screen", "Screen brightness", 0.3, 1.5, 0.01),
    ),
  );

  // --- Output ---------------------------------------------------------------
  const progress = el("progress", { max: 1, value: 0, hidden: true });
  const exportBtn = el("button", { type: "button", class: "btn primary" }, "Export MP4");
  exportBtn.addEventListener("click", async () => {
    if (exportBtn.dataset.busy) {
      api.cancelExport();
      return;
    }
    exportBtn.dataset.busy = "1";
    exportBtn.textContent = "Cancel";
    progress.hidden = false;
    try {
      const blob = await api.exportVideo({ onProgress: (p) => (progress.value = p) });
      if (blob) api.toast(`Saved ${(blob.size / 1e6).toFixed(1)} MB`);
    } catch (e) {
      api.toast(e.message);
      console.error(e);
    } finally {
      delete exportBtn.dataset.busy;
      exportBtn.textContent = "Export MP4";
      progress.hidden = true;
    }
  });
  const alpha = el("input", { type: "checkbox" });
  const size = el("span", { class: "hint" });
  binds.push((s) => {
    const { width, height } = api.outputSize();
    size.textContent = `${width} × ${height} · ${s.output.fps} fps · ${s.duration} s`;
  });
  body.append(
    section(
      "output", "Output",
      segmented("output.aspect", Object.keys(ASPECTS).map((a) => [a, a])),
      el("div", { class: "row" }, segmented("output.height", [["1080", "1080p"], ["1440", "1440p"], ["2160", "4K"]], Number), segmented("output.fps", [["30", "30"], ["60", "60 fps"]], Number)),
      size,
      el("div", { class: "row" }, exportBtn, el("button", { type: "button", class: "btn", onclick: () => api.snapshot({ transparent: alpha.checked }) }, "Save PNG")),
      el("label", { class: "check" }, alpha, el("span", {}, "Transparent PNG (no backdrop)")),
      progress,
    ),
  );

  // --- Script ---------------------------------------------------------------
  const copy = async (text, what) => {
    try {
      await navigator.clipboard.writeText(text);
      api.toast(`Copied the ${what}`);
    } catch {
      prompt(`Copy the ${what}:`, text);
    }
  };
  body.append(
    section(
      "script", "For scripts",
      el("p", { class: "hint" }, "Everything here is one JSON state. A script sets it with window.mockup.set(…), from ?state= in the URL, or by postMessage, then calls seek(t) for each frame. See README.md."),
      el(
        "div", { class: "row wrap" },
        el("button", { type: "button", class: "btn small", onclick: () => copy(JSON.stringify(api.get(), null, 2), "state") }, "Copy state"),
        el("button", { type: "button", class: "btn small", onclick: () => copy(api.stateUrl(), "link") }, "Copy link"),
        el("button", { type: "button", class: "btn small ghost", onclick: () => api.set(JSON.parse(JSON.stringify(window.mockupDefaults))) }, "Reset all"),
      ),
    ),
  );

  // --- Panel and timeline ---------------------------------------------------
  const app = document.getElementById("app");
  const togglePanel = () => {
    app.classList.toggle("collapsed");
    document.getElementById("collapse").setAttribute("aria-expanded", String(!app.classList.contains("collapsed")));
  };
  document.getElementById("collapse").addEventListener("click", togglePanel);
  document.getElementById("expand").addEventListener("click", togglePanel);

  const play = document.getElementById("play");
  const scrub = document.getElementById("scrub");
  const clock = document.getElementById("clock");
  play.addEventListener("click", () => api.set({ playing: !api.get().playing }));
  scrub.addEventListener("input", () => {
    const s = api.get();
    api.set({ playing: false });
    api.seek((Number(scrub.value) / 1000) * s.duration);
  });

  const refresh = (s) => binds.forEach((b) => b(s));
  const tick = (s) => {
    play.textContent = s.playing ? "Pause" : "Play";
    const t = s.duration > 0 ? (s.time % (s.duration + 1.2)) : 0;
    if (document.activeElement !== scrub) scrub.value = String(Math.min(t / s.duration, 1) * 1000);
    clock.textContent = `${Math.min(t, s.duration).toFixed(1)} / ${s.duration.toFixed(1)} s`;
  };
  return { refresh, tick, togglePanel };
}
