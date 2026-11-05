// Pampa Sarovar: a lotus lake in a misty, sunlit forest. Swans glide, the
// trees and grass sway, lotuses bob on the water, mist banks drift between
// the tree lines, and golden pollen and petals float through the light.
//
// The scene's shading, its aerial haze and the tree shadows are baked into
// the vertex colours (Blender), so the land is lit only lightly here: a
// soft sun wrap, light through the leaves, a shimmer as they flick.
//
//   vs_land / fs_land     the land: terrain, hills, trees, grass, lotuses,
//                         birds. Also drawn mirrored (u.skyHorizon.w = 1)
//                         into the reflection canvas, cut at the water.
//   vs_water / fs_water   the lake: the reflection, rippled, a Fresnel
//                         blend over its own colour, and the sun's glints
//   vs_water / fs_ripple  expanding rings where things touch the water
//   vs_sky / fs_sky       the cream sky and the sun's glow
//   vs_wisp / fs_wisp     mist banks: big soft sheets drifting low over the
//                         lake and between the tree lines
//   vs_pollen / fs_pollen pollen motes and tumbling petals, soft bokeh
//
// Colours are linear. The scene is stored compressed (sqrt(c / (1 + c))) so
// the post pass can recover values above 1 for the bloom; alpha holds how
// out of focus the pixel is, for the post pass's depth of field.

struct Uniforms {
    viewProj: mat4x4<f32>,  // the mirror pass: times a flip about y = 0
    camPos: vec4<f32>,      // xyz, time
    sunDir: vec4<f32>,      // towards the sun, intensity
    sunColor: vec4<f32>,    // rgb, light through leaves
    skyHorizon: vec4<f32>,  // rgb, 1 in the mirror pass
    skyTop: vec4<f32>,      // rgb, haze on top of the baked one
    mistColor: vec4<f32>,   // rgb, mist density
    mist: vec4<f32>,        // x height (m), y drift (m), z wisp opacity, w wisp count
    wind: vec4<f32>,        // direction x, direction z, strength, gustiness
    windPhase: vec4<f32>,   // x accumulated phase, y flutter, z swan drift, w lotus bob
    water: vec4<f32>,       // rgb tint, reflection strength
    ripple: vec4<f32>,      // x ripple strength, y glints, z ring speed, w ring brightness
    pollen: vec4<f32>,      // x count, y size, z drift speed, w glow
    pollenColor: vec4<f32>, // rgb, opacity
    camRight: vec4<f32>,    // xyz, tan(half fov x)
    camUp: vec4<f32>,       // xyz, tan(half fov y)
    camFwd: vec4<f32>,      // xyz, focus distance
    pollenBox: vec4<f32>,   // centre xyz, bokeh
    petals: vec4<f32>,      // x fraction of motes that are petals, y petal size
    petalColor: vec4<f32>,  // rgb, 0
    viewport: vec4<f32>,    // 1/width, 1/height of the target drawn to
    shadow: vec4<f32>,      // the shade's tint, how much the sun shapes the near land
    skyMid: vec4<f32>,      // the sky between horizon and top (lavender), how green (0-1)
    mountain: vec4<f32>,    // the far cliffs' colour
};

@group(0) @binding(0) var<uniform> u: Uniforms;
// The lake's reflection: the land and sky drawn mirrored (fs_land, fs_sky).
@group(0) @binding(1) var reflection: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;

// Mesh ids (wind.w), as tools/export_lake.py numbers them.
const TERRAIN: f32 = 0.0;
const HILLS: f32 = 1.0;
const FOREST_FAR: f32 = 2.0;
const CANOPY: f32 = 3.0;
const BUSHES: f32 = 5.0;
const GRASS: f32 = 6.0;
const LOTUS_PADS: f32 = 9.0;
const LOTUS_FLOWERS: f32 = 10.0;
const BIRDS: f32 = 11.0;
const TRUNKS: f32 = 4.0;
const VINES: f32 = 7.0;

// ---------------------------------------------------------------------------
// Noise

fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = mix(mix(hash3(i), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), w.x),
                mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), w.x), w.y);
    let b = mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), w.x),
                mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), w.x), w.y);
    return mix(a, b, w.z);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        s += noise3(q) * a;
        q = q * 2.03 + vec3<f32>(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s / 0.9375;
}

// ---------------------------------------------------------------------------
// Motion

// How far a point that sways by `weight` is pushed by the wind: a slow gust
// rolling across the land along the wind, and a quicker sway of its own.
fn windOffset(world: vec3<f32>, weight: f32, seed: f32) -> vec3<f32> {
    let t = u.windPhase.x;
    let dir = vec3<f32>(u.wind.x, 0.0, u.wind.y);
    let along = dot(world.xz, u.wind.xy);
    let across = dot(world.xz, vec2<f32>(-u.wind.y, u.wind.x));
    let roll = 0.5 + 0.5 * sin(along * 0.12 - t * 1.1 + sin(across * 0.07 + t * 0.3) * 1.4);
    let gust = mix(0.55, roll * roll * 1.6, u.wind.w);
    let own = sin(t * 2.1 + seed * 6.283 + along * 0.4) * 0.3 + sin(t * 3.7 + seed * 17.0) * 0.12 * u.windPhase.y;
    let push = u.wind.z * weight * (gust + own);
    let side = vec3<f32>(-u.wind.y, 0.0, u.wind.x) * sin(t * 1.6 + seed * 9.0 + across * 0.3) * 0.2;
    return (dir + side) * push - vec3<f32>(0.0, abs(push) * 0.2, 0.0);
}

// Where a vertex is this frame, by its wind group (x weight, y phase,
// z group, w mesh; see tools/export_lake.py).
fn animate(p0: vec3<f32>, w: vec4<f32>) -> vec3<f32> {
    let t = u.camPos.w;
    let group = w.z;
    var p = p0;
    if (group == 3.0) {
        // Leaves: the crowns sway, most at the top.
        p += windOffset(p0, w.x, w.y) * 0.32;
    } else if (group == 4.0) {
        // Hanging vines swing from the root.
        p += windOffset(p0, w.x * w.x, w.y) * 0.4;
    } else if (group == 5.0) {
        // Grass bends from its base.
        p += windOffset(p0, w.x * w.x, w.y) * 0.22;
    } else if (group == 6.0) {
        // Lotus pads and flowers ride the water: a slow bob, and the
        // flowers lean on their stems.
        let ph = w.y * 6.283;
        let bob = u.windPhase.w;
        p.y += (sin(t * 0.9 + ph + p0.x * 0.21) * 0.012 + sin(t * 1.7 + ph * 2.0) * 0.005) * bob;
        let lean = clamp(p0.y / 1.2, 0.0, 1.0);
        p.x += (sin(t * 0.7 + ph) * 0.03 + u.wind.x * u.wind.z * 0.02) * lean * bob;
        p.z += (cos(t * 0.6 + ph * 1.3) * 0.03 + u.wind.y * u.wind.z * 0.02) * lean * bob;
    } else if (group == 7.0) {
        // Swans: each glides on its own slow loop and rides the swell (the
        // phase is the same over a bird, so it moves as one).
        let ph = w.y * 6.283;
        let glide = u.windPhase.z;
        p.x += sin(t * 0.045 + ph) * 2.2 * glide;
        p.z += cos(t * 0.037 + ph * 1.7) * 1.4 * glide;
        p.y += sin(t * 1.1 + ph) * 0.012;
    }
    return p;
}

// ---------------------------------------------------------------------------
// Sky and air

// Blue above, lavender through the middle, warm toward the horizon (most
// on the sun's side), and the sun's glow.
fn skyColor(dir: vec3<f32>) -> vec3<f32> {
    let y = dir.y;
    let toSun = max(dot(normalize(vec3<f32>(dir.x, 0.0, dir.z) + vec3<f32>(1e-5, 0.0, 0.0)), normalize(vec3<f32>(u.sunDir.x, 0.0, u.sunDir.z))), 0.0);
    let horizon = mix(mix(u.skyMid.rgb, u.skyHorizon.rgb, 0.6), u.skyHorizon.rgb, toSun);
    var c = mix(horizon, u.skyMid.rgb, smoothstep(0.0, 0.16, y));
    c = mix(c, u.skyTop.rgb, smoothstep(0.1, 0.42, y));
    c = mix(c, u.mistColor.rgb, clamp(-y * 6.0, 0.0, 1.0));
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    c += u.sunColor.rgb * (pow(sd, 8.0) * 0.35 + pow(sd, 64.0) * 0.8 + pow(sd, 900.0) * 6.0) * u.sunDir.w;
    return c;
}

// The air: a soft haze that thickens with distance and thins with height,
// warm toward the sun and turning to sky far off; and a few low mist banks
// drifting over the water and the hollows.
fn mist(c: vec3<f32>, world: vec3<f32>) -> vec4<f32> {
    let toP = world - u.camPos.xyz;
    let d = length(toP);
    let dir = toP / max(d, 1e-4);
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    let thick = exp(-max(world.y, 0.0) * 0.012);
    let f = 1.0 - exp(-d * u.skyTop.w * 0.0015 * (0.35 + 0.65 * thick));
    let scatter = u.mistColor.rgb + u.sunColor.rgb * pow(sd, 6.0) * 0.2 * u.sunDir.w;
    let farSky = skyColor(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.5, dir.z));
    let hazeCol = mix(scatter, farSky, smoothstep(150.0, 900.0, d) * 0.45);
    var out = mix(c, hazeCol, clamp(f, 0.0, 1.0));
    // Mist banks.
    let drift = vec2<f32>(u.wind.x, u.wind.y) * u.mist.y;
    let n = fbm3(vec3<f32>(world.xz * 0.028 + drift, world.y * 0.08 + u.camPos.w * 0.015));
    let clumps = smoothstep(0.4, 0.8, n);
    let low = exp(-max(world.y, 0.0) / max(u.mist.x, 0.1));
    let m = (1.0 - exp(-d * u.mistColor.w * 0.006 * low * clumps)) * smoothstep(20.0, 80.0, d);
    out = mix(out, scatter * 1.05, clamp(m, 0.0, 1.0));
    return vec4<f32>(out, d);
}

fn encode(c: vec3<f32>, dist: f32) -> vec4<f32> {
    let m = max(c, vec3<f32>(0.0));
    let blur = clamp(abs(1.0 - dist / u.camFwd.w) * 0.9, 0.0, 1.0);
    return vec4<f32>(sqrt(m / (1.0 + m)), blur);
}

fn decode(s: vec3<f32>) -> vec3<f32> {
    let q = min(s * s, vec3<f32>(0.995));
    return q / (1.0 - q);
}

// ---------------------------------------------------------------------------
// Greens

// A three-stop ramp: dark (t 0), mid (0.55), light (1).
fn ramp(t: f32, lo: vec3<f32>, mid: vec3<f32>, hi: vec3<f32>) -> vec3<f32> {
    let k = clamp(t, 0.0, 1.0);
    if (k < 0.55) {
        return mix(lo, mid, k / 0.55);
    }
    return mix(mid, hi, (k - 0.55) / 0.45);
}

// The palette's families, by how much light there is (t), as in a
// painting of a sunlit valley: cool teal in the shade rising to golden
// tops in the sun (canopy), a deeper teal for trees in shadow, golden
// ochre grass, and a few crowns all gold.
fn canopy(t: f32) -> vec3<f32> {
    return ramp(t, vec3<f32>(0.03, 0.1, 0.09), vec3<f32>(0.16, 0.34, 0.12), vec3<f32>(0.8, 0.72, 0.2));
}
fn olive(t: f32) -> vec3<f32> {
    return ramp(t, vec3<f32>(0.04, 0.1, 0.06), vec3<f32>(0.22, 0.36, 0.1), vec3<f32>(0.7, 0.66, 0.18));
}
fn teal(t: f32) -> vec3<f32> {
    return ramp(t, vec3<f32>(0.015, 0.055, 0.065), vec3<f32>(0.05, 0.16, 0.15), vec3<f32>(0.3, 0.4, 0.25));
}
fn meadow(t: f32) -> vec3<f32> {
    return ramp(t, vec3<f32>(0.07, 0.11, 0.03), vec3<f32>(0.34, 0.36, 0.07), vec3<f32>(0.86, 0.66, 0.15));
}
fn golden(t: f32) -> vec3<f32> {
    return ramp(t, vec3<f32>(0.12, 0.13, 0.03), vec3<f32>(0.52, 0.44, 0.07), vec3<f32>(0.96, 0.74, 0.2));
}

// A tree's or a patch's colour: the families drift into one another in
// broad patches, so neighbours differ gently, and a few go golden.
fn foliageGreen(t: f32, place: vec3<f32>) -> vec3<f32> {
    let a = noise3(place * 0.035);
    let b = noise3(place * 0.022 + vec3<f32>(17.0, 3.0, 5.0));
    let g = noise3(place * 0.016 + vec3<f32>(40.0, 9.0, 2.0));
    var c = mix(canopy(t), olive(t), smoothstep(0.45, 0.75, a));
    c = mix(c, teal(t), smoothstep(0.55, 0.75, b));
    return mix(c, golden(t), smoothstep(0.72, 0.84, g) * 0.6);
}

// The baked colours are pale (their haze and light are in them); the
// land is repainted in greens from their lightness, which keeps the
// baked shading and the tree shadows.
// How forested the cliffs are at this point: fully at their feet, thinning
// with height (a little higher on gentler slopes) along a ragged line.
// Only the nearer cliffs: on the far peaks the trees are lost in the haze.
fn cliffTrees(world: vec3<f32>, up: f32) -> f32 {
    let ragged = (noise3(world * 0.02) - 0.5) * 34.0 + (noise3(world * 0.07) - 0.5) * 12.0;
    let line = world.y + ragged - clamp(up, 0.0, 1.0) * 10.0;
    let far = smoothstep(220.0, 420.0, length(world.xz - vec2<f32>(0.0, 6.0)));
    return (1.0 - smoothstep(30.0, 120.0, line)) * (1.0 - far);
}

fn repaint(albedo: vec3<f32>, group: f32, mesh: f32, world: vec3<f32>, up: f32) -> vec3<f32> {
    // The bake's haze pulls everything toward a lightness of about 0.52
    // with distance from the hero camera; take it back out, so the far
    // forests are green again (the haze here is added in mist()).
    let dh = length(world - vec3<f32>(0.0, 2.4, 6.0));
    let h = min(1.0 - exp(-pow(dh / 200.0, 1.3)), 0.88);
    let lum = clamp((dot(albedo, vec3<f32>(0.3, 0.59, 0.11)) - 0.52 * h) / (1.0 - h), 0.0, 1.0);
    let hi = max(albedo.r, max(albedo.g, albedo.b));
    let sat = (hi - min(albedo.r, min(albedo.g, albedo.b))) / max(hi, 1e-3);
    if (group == 3.0) {
        // Crowns, bushes and the far forest.
        return foliageGreen(pow(smoothstep(0.04, 0.95, lum), 0.85), world);
    } else if (group == 5.0) {
        return meadow(smoothstep(0.02, 0.6, lum)) * (0.9 + 0.2 * noise3(world * 0.4));
    } else if (mesh == TERRAIN) {
        let path = smoothstep(0.55, 0.7, lum) * (1.0 - smoothstep(0.35, 0.5, sat));
        let k = noise3(world * 0.12);
        let ground = mix(meadow(smoothstep(0.05, 0.6, lum)), olive(smoothstep(0.05, 0.6, lum)), smoothstep(0.35, 0.75, k));
        let sand = mix(vec3<f32>(0.62, 0.55, 0.42), vec3<f32>(0.85, 0.8, 0.68), smoothstep(0.55, 0.85, lum));
        return mix(ground, sand, path);
    } else if (mesh == LOTUS_PADS) {
        return olive(smoothstep(0.05, 0.6, lum) * 0.8 + 0.15);
    } else if (mesh == HILLS) {
        // The cliffs: tree-green at their feet where the forest climbs
        // them, thinning with height (further up the gentler slopes, in a
        // ragged line) and merging into lavender stone (`mountain`) and
        // the violet haze above.
        let t = smoothstep(0.05, 0.9, lum);
        let stone = mix(u.mountain.rgb, u.mistColor.rgb, 0.3) * mix(0.45, 1.15, t) * (0.8 + 0.4 * noise3(world * 0.03));
        // The trees' own green: their palette (foliageGreen, as the
        // canopy is repainted) blended with their baked yellow-olive by
        // `greens`, just as the trees are; in their shade, as the floor
        // between the crowns is: darker and cooler than the lit tops.
        let tg = mix(0.18, 0.48, t);
        // (The canopy's baked colour at the cliffs' distance, in shade.)
        let baked = vec3<f32>(0.46, 0.47, 0.3) * mix(0.35, 0.75, t);
        // (Mostly olive and canopy: teal alone would lie in broad cool
        // patches over a cliff.)
        let palette = mix(mix(canopy(tg), olive(tg), smoothstep(0.35, 0.65, noise3(world * 0.035))), teal(tg), 0.3);
        let green = mix(baked, palette, u.skyMid.w) * (0.88 + 0.24 * noise3(world * 0.09));
        let trees = cliffTrees(world, up);
        // Up the cliff the shaded floor gives way to a light, hazy green
        // (the forest seen through the air), and that to the stone: never
        // the dark green straight into violet, which goes muddy.
        let lightTg = mix(0.45, 0.75, t);
        let lightGreen = mix(baked * 1.6, mix(canopy(lightTg), olive(lightTg), 0.5), u.skyMid.w);
        let upper = mix(lightGreen, u.mistColor.rgb * 0.85, 0.5);
        let rock = mix(stone, upper, smoothstep(0.0, 0.5, trees));
        return mix(rock, green, smoothstep(0.5, 1.0, trees));
    } else if (mesh == TRUNKS) {
        return vec3<f32>(0.17, 0.12, 0.08) * mix(0.5, 1.4, smoothstep(0.1, 0.6, lum));
    } else if (group == 4.0 || mesh == VINES) {
        return teal(smoothstep(0.0, 0.4, lum));
    }
    return albedo;
}

// ---------------------------------------------------------------------------
// The land

struct LandIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec4<f32>,
    @location(2) color: vec4<f32>,
    @location(3) wind: vec4<f32>,
};

struct LandOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) albedo: vec3<f32>,
    @location(3) wind: vec4<f32>, // weight, phase, group, mesh
};

@vertex
fn vs_land(v: LandIn) -> LandOut {
    var out: LandOut;
    let w = vec4<f32>(v.wind.x, v.wind.y, round(v.wind.z * 255.0), round(v.wind.w * 255.0));
    let p = animate(v.position, w);
    out.clip = u.viewProj * vec4<f32>(p, 1.0);
    out.world = p;
    out.normal = v.normal.xyz;
    let baked = pow(v.color.rgb, vec3<f32>(2.2));
    // The cliffs' triangles are huge (base to summit), so they are
    // repainted per pixel, in fs_land.
    out.albedo = select(mix(baked, repaint(baked, w.z, w.w, v.position, v.normal.y), u.skyMid.w), baked, w.w == HILLS);
    out.wind = w;
    return out;
}

struct FragOut {
    @location(0) color: vec4<f32>,
};

// Sunlight on a surface: a soft toon step from the shade tint to the sun,
// sky light from above and warm bounce from the ground below.
fn sunlight(n: vec3<f32>, open: f32) -> vec3<f32> {
    let ndl = mix(dot(n, u.sunDir.xyz), 0.55, open);
    let lit = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
    let k = smoothstep(0.2, 0.75, lit);
    // The sun, a little less golden on the greens than in the sky.
    let sunC = mix(u.sunColor.rgb, vec3<f32>(1.0), 0.35);
    var light = mix(u.shadow.rgb, sunC * 1.08, k) * mix(1.0, u.sunDir.w, k);
    let sky = mix(u.mistColor.rgb * vec3<f32>(1.0, 0.95, 0.85), mix(u.skyMid.rgb, u.skyTop.rgb, 0.6), n.y * 0.5 + 0.5);
    light += sky * 0.22;
    light += u.sunColor.rgb * vec3<f32>(1.0, 0.85, 0.6) * 0.12 * clamp(0.6 - n.y * 0.6, 0.0, 1.0);
    return light;
}

@fragment
fn fs_land(in: LandOut, @builtin(front_facing) front: bool) -> FragOut {
    var out: FragOut;
    let mirror = u.skyHorizon.w > 0.5;
    // The reflection shows only what is above the water.
    if (mirror && in.world.y < -0.02) {
        discard;
    }
    let v = normalize(u.camPos.xyz - in.world);
    var n = normalize(in.normal);
    if (dot(n, v) < 0.0 && !mirror) {
        n = -n;
    }
    let group = in.wind.z;
    let mesh = in.wind.w;
    let sun = u.sunDir.xyz;
    let d = length(u.camPos.xyz - in.world);
    // The repainted colours carry the baked light; the sun shapes the near
    // crowns (their shade sides cool and deep), and farther off the haze
    // takes over. Up-facing ground and grass keep their light.
    let near = (1.0 - smoothstep(60.0, 260.0, d)) * u.shadow.w;
    let open = select(0.0, 0.75, group == 5.0 || mesh == TERRAIN || mesh == LOTUS_PADS);
    let light = mix(vec3<f32>(1.0), sunlight(n, open), near);
    var albedo = in.albedo;
    if (mesh == HILLS) {
        // Always: their baked colour is the pale stone this replaces.
        albedo = repaint(albedo, group, mesh, in.world, n.y);
    }
    var c = albedo * light;
    let foliage = group == 3.0 || group == 5.0 || mesh == LOTUS_PADS;
    let ndl = dot(n, sun);
    // Light through the leaves; the forest floor on the cliffs catches a
    // little of it too.
    // (On the cliffs, only a little: it is the floor under the trees.)
    let leafy = select(select(0.0, 1.0, foliage), cliffTrees(in.world, n.y) * 0.2, mesh == HILLS);
    if (leafy > 0.0) {
        // Light through the leaves, when the sun is behind them.
        let back = pow(max(dot(-v, sun), 0.0), 3.0) * (0.4 + 0.6 * max(-ndl, 0.0));
        c += albedo * vec3<f32>(1.25, 1.35, 0.55) * back * u.sunColor.w * u.sunDir.w * leafy;
    }
    if (foliage) {
        // Leaves flick and catch the light as the wind moves them.
        let flick = sin(u.windPhase.x * 4.1 + in.wind.y * 40.0 + in.world.x * 0.7) * 0.5 + 0.5;
        c *= 1.0 + (flick - 0.5) * 0.12 * u.wind.z * u.windPhase.y * in.wind.x;
    }
    // A warm rim where surfaces turn away, toward the sun.
    let rim = pow(1.0 - max(dot(n, v), 0.0), 3.0) * max(dot(-v, sun) * 0.5 + 0.5, 0.0);
    c += u.sunColor.rgb * rim * 0.2 * albedo;
    if (mesh == LOTUS_FLOWERS || mesh == BIRDS) {
        // Petals and feathers glow a little in the sun.
        c += in.albedo * u.sunColor.rgb * (rim * 0.25 + max(ndl, 0.0) * 0.15) * u.sunDir.w;
    }
    let m = mist(c, in.world);
    out.color = encode(m.rgb, m.w);
    return out;
}

// ---------------------------------------------------------------------------
// The meadow's plants: instances of small template meshes (tools/plant.py),
// swaying in the wind. Grass tufts, leafy bush clumps and the leaves over
// them, sunflowers, white daisies and small yellow and white flowers.

const LEAF: f32 = 10.0;
const GRASS_TUFT: f32 = 13.0;
const FLOWER: f32 = 14.0;
const BUSH: f32 = 15.0;
const SUNFLOWER: f32 = 21.0;
const DAISY: f32 = 22.0;

struct InstIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) bend: f32,
    @location(3) placeScale: vec4<f32>,
    @location(4) axisX: vec4<f32>, // w: random
    @location(5) axisY: vec4<f32>, // w: random
    @location(6) kindLight: vec4<f32>, // kind / 255, ground light
};

struct InstOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) albedo: vec3<f32>,
    @location(3) params: vec4<f32>, // kind, ground shade, scale, seed
};

// Bushes come in two tones, a bush at a time: sunny olive, and deep teal.
fn lightBush(place: vec3<f32>) -> f32 {
    return smoothstep(0.44, 0.56, noise3(place * 0.55 + vec3<f32>(7.0, 0.0, 3.0)));
}

fn isBloom(kind: f32) -> bool {
    return kind == SUNFLOWER || kind == DAISY;
}

@vertex
fn vs_inst(v: InstIn) -> InstOut {
    var out: InstOut;
    let kind = round(v.kindLight.x * 255.0);
    let ax = normalize(v.axisX.xyz);
    let ay = normalize(v.axisY.xyz - ax * dot(v.axisY.xyz, ax));
    let az = cross(ax, ay);
    let seed = v.axisX.w * 0.5 + 0.5;
    let seed2 = v.axisY.w * 0.5 + 0.5;
    let s = v.placeScale.w;
    let base = v.placeScale.xyz;
    var local = v.position;
    var ln = v.normal;
    if (isBloom(kind) && v.bend >= 0.0) {
        // The head turns on its stem toward the camera (local +z), nodding
        // in and out of the light.
        let tilt = select(1.05, 0.85, kind == DAISY) + (seed2 - 0.5) * 0.4;
        let c = cos(tilt);
        let sn = sin(tilt);
        let q = local - vec3<f32>(0.0, 3.04, 0.0);
        local = vec3<f32>(q.x, q.y * c - q.z * sn, q.y * sn + q.z * c) + vec3<f32>(0.0, 3.04, 0.0);
        ln = vec3<f32>(ln.x, ln.y * c - ln.z * sn, ln.y * sn + ln.z * c);
    }
    var p = base + (ax * local.x + ay * local.y + az * local.z) * s;
    let n = normalize(ax * ln.x + ay * ln.y + az * ln.z);

    // How much it sways: grass and flowers from the root, blooms from the
    // head, leaves more the higher they grow.
    var weight = 0.0;
    var flutter = 0.0;
    if (kind == GRASS_TUFT) {
        weight = v.bend * v.bend * 0.16;
    } else if (kind == FLOWER) {
        weight = 0.06;
        flutter = 0.3;
    } else if (isBloom(kind)) {
        weight = clamp(local.y / 3.0, 0.0, 1.0) * select(0.12, 0.08, kind == SUNFLOWER);
    } else if (kind == BUSH) {
        weight = v.bend * 0.06;
    } else {
        weight = clamp(base.y / 2.5, 0.0, 1.0) * 0.07 + 0.01;
        flutter = 0.8;
    }
    p += windOffset(base, weight, seed);
    if (kind == BUSH) {
        // Clumps breathe: their surface ripples as gusts pass through.
        let t = u.windPhase.x;
        let ripple = sin(t * 2.6 + seed * 20.0 + dot(v.position, vec3<f32>(3.1, 2.3, 2.7))) * 0.5
            + sin(t * 4.1 + seed * 7.0 + v.position.y * 5.0) * 0.5;
        p += n * ripple * 0.035 * s * u.wind.z * (0.4 + v.bend);
    }
    if (flutter > 0.0) {
        // Leaves flick about their stems.
        let t = u.windPhase.x;
        let f = sin(t * 7.0 + seed * 40.0 + base.x * 3.0) * 0.6 + sin(t * 11.3 + seed2 * 25.0) * 0.4;
        let amp = u.wind.z * u.windPhase.y * flutter * v.bend * s * 0.03;
        p += az * f * amp + ay * abs(f) * amp * 0.3;
    }

    var albedo = vec3<f32>(1.0);
    if (kind == GRASS_TUFT) {
        albedo = mix(meadow(v.bend * 0.8 + seed * 0.3), olive(v.bend * 0.7 + seed * 0.25), smoothstep(0.35, 0.75, noise3(base * 0.08))) * (0.85 + 0.3 * seed2);
    } else if (kind == FLOWER) {
        // Buttercup yellow, marigold orange and white, with yellow hearts.
        let petal = select(select(vec3<f32>(1.0, 0.76, 0.14), vec3<f32>(1.0, 0.5, 0.06), seed > 0.42), vec3<f32>(0.96, 0.95, 0.92), seed > 0.66);
        albedo = mix(vec3<f32>(1.0, 0.72, 0.12), petal, smoothstep(0.1, 0.45, v.bend));
    } else if (isBloom(kind)) {
        let r = v.bend;
        if (r < 0.0) {
            albedo = vec3<f32>(0.08, 0.26, 0.05) * (0.8 + 0.4 * seed2);
        } else if (kind == SUNFLOWER) {
            let petal = mix(vec3<f32>(0.95, 0.5, 0.02), vec3<f32>(1.0, 0.78, 0.12), r);
            let centre = mix(vec3<f32>(0.12, 0.05, 0.015), vec3<f32>(0.45, 0.24, 0.04), smoothstep(0.1, 0.25, r));
            albedo = select(petal, centre, r < 0.26) * (0.9 + 0.2 * seed);
        } else {
            let petal = mix(vec3<f32>(0.86, 0.85, 0.78), vec3<f32>(1.0, 0.99, 0.95), r);
            albedo = select(petal, vec3<f32>(1.0, 0.72, 0.1), r < 0.26);
        }
    } else if (kind == BUSH) {
        // The clump is the shadowed core under its leaves.
        let dark = teal(seed * 0.4 + v.bend * 0.4) * (0.5 + 0.3 * v.bend);
        let light = olive(seed * 0.5 + v.bend * 0.55) * (0.75 + 0.35 * v.bend);
        albedo = mix(dark, light, lightBush(base));
    } else {
        let dark = teal(seed * 0.8 + 0.1);
        let light = canopy(seed * 0.9 + 0.1);
        albedo = mix(dark, light, lightBush(base)) * (0.85 + 0.3 * v.bend);
    }
    // In the trees' shade (the ground's baked light) it is darker.
    let ground = v.kindLight.y * 0.75;
    let shade = mix(0.5, 1.0, smoothstep(0.1, 0.38, ground));
    out.clip = u.viewProj * vec4<f32>(p, 1.0);
    out.world = p;
    out.normal = n;
    out.albedo = albedo;
    out.params = vec4<f32>(kind, shade, s, seed);
    return out;
}

@fragment
fn fs_inst(in: InstOut, @builtin(front_facing) front: bool) -> FragOut {
    var out: FragOut;
    let mirror = u.skyHorizon.w > 0.5;
    if (mirror && in.world.y < -0.02) {
        discard;
    }
    let kind = in.params.x;
    let p = in.world;
    let view = normalize(u.camPos.xyz - p);
    var n = normalize(in.normal);
    if (kind == BUSH) {
        // A leafy silhouette: the clump's rim broken up by noise, and a
        // lumpy, many-leaved normal.
        let size = max(in.params.z, 0.2);
        let q = p * (7.0 / size) + vec3<f32>(u.windPhase.x * 0.15);
        let leafy = noise3(q) * 0.65 + noise3(q * 2.7) * 0.35;
        let rim = 1.0 - abs(dot(n, view));
        if (rim > 0.32 + leafy * 0.62) {
            discard;
        }
        let bump = vec3<f32>(noise3(q + 11.0), noise3(q + 23.0), noise3(q + 37.0)) - 0.5;
        n = normalize(n + bump * 1.4);
    }
    if (!front) {
        n = -n;
    }
    let open = select(0.0, 0.6, kind == GRASS_TUFT || kind == FLOWER);
    let shade = in.params.y;
    var light = sunlight(n, open);
    light = mix(u.shadow.rgb * 0.9 + mix(u.skyMid.rgb, u.skyTop.rgb, 0.6) * 0.2, light, shade);
    var c = in.albedo * light;
    let sun = u.sunDir.xyz;
    if (kind != BUSH) {
        // Leaves, petals and blades glow when the sun shines through them.
        let through = pow(max(dot(-view, sun), 0.0), 3.0);
        let back = max(-dot(n, sun), 0.0);
        c += in.albedo * vec3<f32>(1.25, 1.35, 0.55) * through * (0.4 + back) * 0.8 * shade;
        let hlf = normalize(view + sun);
        c += u.sunColor.rgb * pow(max(dot(n, hlf), 0.0), 24.0) * 0.08 * shade;
    }
    let rim = pow(1.0 - max(dot(n, view), 0.0), 3.0) * max(dot(-view, sun) * 0.5 + 0.5, 0.0);
    c += u.sunColor.rgb * rim * 0.24 * in.albedo * (0.3 + 0.7 * shade);
    let m = mist(c, p);
    out.color = encode(m.rgb, m.w);
    return out;
}

// ---------------------------------------------------------------------------
// The lake

struct WaterOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) albedo: vec3<f32>,
    @location(2) wind: vec4<f32>,
};

@vertex
fn vs_water(v: LandIn) -> WaterOut {
    var out: WaterOut;
    out.clip = u.viewProj * vec4<f32>(v.position, 1.0);
    out.world = v.position;
    out.albedo = pow(v.color.rgb, vec3<f32>(2.2));
    out.wind = vec4<f32>(v.wind.x, v.wind.y, round(v.wind.z * 255.0), round(v.wind.w * 255.0));
    return out;
}

// The water's height field: long swells along the wind and a finer chop
// across it, in metres. Its slope is the ripple.
fn waterHeight(p: vec2<f32>) -> f32 {
    let t = u.camPos.w;
    let along = vec2<f32>(u.wind.x, u.wind.y);
    let across = vec2<f32>(-u.wind.y, u.wind.x);
    var h = sin(dot(p, along) * 0.9 - t * 1.3) * 0.5;
    h += sin(dot(p, along * 0.6 + across * 0.8) * 1.7 - t * 1.9) * 0.3;
    h += (noise3(vec3<f32>(p * 0.9 - along * t * 0.6, t * 0.25)) - 0.5) * 1.2;
    h += (noise3(vec3<f32>(p * 3.1 + across * t * 0.4, t * 0.5)) - 0.5) * 0.45;
    return h;
}

fn waterNormal(p: vec2<f32>, strength: f32) -> vec3<f32> {
    let e = 0.08;
    let h = waterHeight(p);
    let dx = (waterHeight(p + vec2<f32>(e, 0.0)) - h) / e;
    let dz = (waterHeight(p + vec2<f32>(0.0, e)) - h) / e;
    return normalize(vec3<f32>(-dx * strength, 1.0, -dz * strength));
}

// Pebbles: distance to the nearest cell edge (x), and that cell (yz).
fn pebbles(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);
    var d1 = 9.0;
    var d2 = 9.0;
    var id = vec2<f32>(0.0);
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let g = vec2<f32>(f32(x), f32(y));
            let o = vec2<f32>(hash3(vec3<f32>(i + g, 11.0)), hash3(vec3<f32>(i + g, 23.0))) * 0.8 + 0.1;
            let d = length(g + o - f);
            if (d < d1) {
                d2 = d1;
                d1 = d;
                id = i + g;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    return vec3<f32>(d2 - d1, id);
}

@fragment
fn fs_water(in: WaterOut) -> FragOut {
    var out: FragOut;
    let toCam = u.camPos.xyz - in.world;
    let dist = length(toCam);
    let v = toCam / max(dist, 1e-4);
    // Ripples calm with distance (they'd only shimmer), and near the shore
    // and pads where the weight is low.
    let strength = u.ripple.x * mix(0.25, 1.0, in.wind.x) * 0.05 * mix(1.0, 0.35, smoothstep(30.0, 160.0, dist));
    let n = waterNormal(in.world.xz, strength);
    // The reflection, at this pixel, nudged by the ripples.
    let screen = in.clip.xy * u.viewport.xy;
    let nudge = n.xz * vec2<f32>(1.0, -1.0) * (0.9 / (1.0 + dist * 0.06));
    let r = decode(textureSampleLevel(reflection, smp, clamp(screen + nudge * 0.08, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
    let cosT = max(dot(n, v), 0.0);
    let fresnel = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);
    // Looking down into clear water near the shore: a bed of pebbles,
    // tinted by the water, fading into its colour with depth and distance.
    let bedUv = in.world.xz * 0.9 + n.xz * 0.5;
    let cell = pebbles(bedUv);
    let pebble = mix(vec3<f32>(0.3, 0.27, 0.2), vec3<f32>(0.56, 0.5, 0.4), hash3(vec3<f32>(cell.yz, 3.0)))
        * mix(0.7, 1.0, smoothstep(0.0, 0.5, cell.x));
    let clear = (1.0 - smoothstep(14.0, 70.0, dist)) * (1.0 - fresnel);
    let body = mix(in.albedo * u.water.rgb, pebble * u.water.rgb * 1.3, clear * 0.85);
    var c = mix(body, r, clamp(mix(mix(0.55, 0.25, clear), 1.0, fresnel) * u.water.w, 0.0, 1.0));
    // The sun on the ripples: a broad sheen and sharp glints.
    let h = normalize(v + u.sunDir.xyz);
    let nh = max(dot(n, h), 0.0);
    let glint = pow(nh, 900.0) * 9.0 + pow(nh, 120.0) * 0.6;
    // Sparkles: tiny cells that wink as the ripples turn them to the sun.
    let sq = in.world.xz * 4.0;
    let sp = floor(sq);
    let dot_ = 1.0 - smoothstep(0.08, 0.2, length(fract(sq) - 0.5));
    let wink = pow(max(sin(u.camPos.w * (2.0 + hash3(vec3<f32>(sp, 1.0)) * 4.0) + hash3(vec3<f32>(sp, 7.0)) * 40.0), 0.0), 24.0);
    let sparkle = wink * dot_ * step(0.9, hash3(vec3<f32>(sp, 2.0))) * smoothstep(0.2, 0.8, pow(nh, 8.0)) * 4.0 * (1.0 - smoothstep(15.0, 60.0, dist));
    c += u.sunColor.rgb * (glint + sparkle) * u.ripple.y * u.sunDir.w;
    let m = mist(c, in.world);
    out.color = encode(m.rgb, m.w);
    return out;
}

// Rings spreading where swans and flowers touch the water: x runs 0 at a
// ring's centre to 1 at its rim; each ring starts at its own phase.
@fragment
fn fs_ripple(in: WaterOut) -> FragOut {
    var out: FragOut;
    let t = u.camPos.w;
    let x = in.wind.x;
    var a = 0.0;
    var c = in.albedo * u.sunColor.rgb * 1.4;
    if (in.wind.z == 9.0) {
        // Glints (Water_Glints): little stars on the water that wink on and
        // off, each at its own moment.
        let ph = in.wind.y * 6.283;
        let wink = pow(max(sin(t * (1.1 + in.wind.y * 1.7) + ph * 7.0), 0.0), 10.0);
        a = wink * u.ripple.y * 0.9;
        c = in.albedo * 2.2;
    } else {
        let age = fract(t * u.ripple.z * 0.18 + in.wind.y);
        let band = exp(-pow((x - age) / 0.05, 2.0));
        a = band * pow(1.0 - age, 1.5) * smoothstep(0.0, 0.08, age) * u.ripple.w;
    }
    let m = mist(c, in.world);
    // Premultiplied, over; alpha (depth of field) left alone by the blend.
    out.color = vec4<f32>(sqrt(m.rgb / (1.0 + m.rgb)) * a, a);
    return out;
}

// ---------------------------------------------------------------------------
// The sky

struct SkyOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) ndc: vec2<f32>,
};

@vertex
fn vs_sky(@builtin(vertex_index) idx: u32) -> SkyOut {
    var out: SkyOut;
    let x = f32((idx << 1u) & 2u) * 2.0 - 1.0;
    let y = f32(idx & 2u) * 2.0 - 1.0;
    out.clip = vec4<f32>(x, y, 0.0, 1.0);
    out.ndc = vec2<f32>(x, y);
    return out;
}

@fragment
fn fs_sky(in: SkyOut) -> FragOut {
    var out: FragOut;
    var dir = normalize(u.camFwd.xyz + u.camRight.xyz * in.ndc.x * u.camRight.w + u.camUp.xyz * in.ndc.y * u.camUp.w);
    if (u.skyHorizon.w > 0.5) {
        // The mirror pass: the sky as the lake sees it.
        dir.y = -dir.y;
    }
    var c = skyColor(dir);
    // Clouds: soft fbm on a high plane, drifting with the wind; lavender
    // undersides, cream tops, gold-rimmed toward the sun.
    if (dir.y > 0.0) {
        let plane = dir.xz / (dir.y + 0.08) * 1.6;
        let drift = vec2<f32>(u.wind.x, u.wind.y) * u.windPhase.x * 0.03;
        let q = vec3<f32>(plane + drift, u.camPos.w * 0.01);
        let d = fbm3(q * 0.6);
        let d2 = fbm3(q * 1.7 + vec3<f32>(3.0, 1.0, 0.0));
        let amount = u.mountain.w;
        let cover = smoothstep(0.62 - amount * 0.35, 0.95 - amount * 0.25, d * 0.75 + d2 * 0.35);
        let fade = smoothstep(0.0, 0.25, dir.y);
        let sd = max(dot(dir, u.sunDir.xyz), 0.0);
        let shade = mix(mix(u.skyMid.rgb, vec3<f32>(0.95, 0.9, 1.0), 0.45), vec3<f32>(1.12, 1.02, 0.94), smoothstep(0.35, 0.8, d2));
        let rim = smoothstep(0.55, 0.9, d) * (1.0 - smoothstep(0.9, 1.1, d));
        let cloud = shade + u.sunColor.rgb * (pow(sd, 5.0) * 0.7 + rim * pow(sd, 2.0) * 0.5);
        c = mix(c, cloud, cover * fade * 0.85);
    }
    out.color = vec4<f32>(sqrt(c / (1.0 + c)), 0.85);
    return out;
}

// ---------------------------------------------------------------------------
// Mist banks: each instance is a big sheet facing the camera, low over the
// lake and between the tree lines, drifting downwind and wrapping round a
// box over the scene. Its shape is soft noise, so the edges never show.

struct WispOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) world: vec3<f32>,
    @location(2) seed: vec2<f32>, // random, opacity
};

const WISP_LO: vec3<f32> = vec3<f32>(-80.0, 0.0, -260.0);
const WISP_SIZE: vec3<f32> = vec3<f32>(240.0, 1.0, 255.0);

@vertex
fn vs_wisp(@builtin(vertex_index) vi: u32, @location(0) id: f32) -> WispOut {
    var out: WispOut;
    let r1 = hash1(id * 1.31 + 0.7);
    let r2 = hash1(id * 2.17 + 3.1);
    let r3 = hash1(id * 4.03 + 1.9);
    let drift = vec2<f32>(u.wind.x, u.wind.y) * u.mist.y * (0.7 + 0.6 * r3);
    var xz = vec2<f32>(r1, r2) * WISP_SIZE.xz + drift;
    xz = WISP_LO.xz + ((xz % WISP_SIZE.xz) + WISP_SIZE.xz) % WISP_SIZE.xz;
    // Farther sheets are bigger, so the far tree lines get whole banks.
    let centre = vec3<f32>(xz.x, 0.0, xz.y);
    let dist = length(centre - u.camPos.xyz);
    let w = mix(10.0, 34.0, r3) * mix(0.8, 1.6, smoothstep(30.0, 200.0, dist));
    let h = w * mix(0.16, 0.26, r1);
    let corner = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    let c = corner[vi];
    // Upright, turned to the camera about the vertical.
    var side = vec3<f32>(u.camRight.x, 0.0, u.camRight.z);
    side = side / max(length(side), 1e-4);
    let base = centre + vec3<f32>(0.0, -h * 0.25 + r2 * u.mist.x * 0.6, 0.0);
    let world = base + side * c.x * w + vec3<f32>(0.0, c.y * h, 0.0);
    out.clip = u.viewProj * vec4<f32>(world, 1.0);
    out.uv = c;
    out.world = world;
    // Fade near the lens, at the box's edges, and the ones past the count.
    let near = smoothstep(20.0, 55.0, dist);
    let edge = smoothstep(0.0, 25.0, min(min(xz.x - WISP_LO.x, WISP_LO.x + WISP_SIZE.x - xz.x),
                                         min(xz.y - WISP_LO.z, WISP_LO.z + WISP_SIZE.z - xz.y)));
    out.seed = vec2<f32>(r1 * 17.0 + r2 * 3.0, near * edge * clamp(u.mist.w - id, 0.0, 1.0));
    return out;
}

@fragment
fn fs_wisp(in: WispOut) -> FragOut {
    var out: FragOut;
    let t = u.camPos.w;
    // A soft lens of mist, thick in the middle and low, torn by noise that
    // rolls slowly through it.
    let shape = (1.0 - smoothstep(0.3, 1.0, abs(in.uv.x))) * smoothstep(0.0, 0.25, in.uv.y) * (1.0 - smoothstep(0.35, 1.0, in.uv.y));
    let n = fbm3(vec3<f32>(in.uv.x * 2.2 + in.seed.x + t * 0.02, in.uv.y * 3.0 - t * 0.03, in.seed.x + t * 0.01));
    let a = shape * smoothstep(0.3, 0.75, n) * in.seed.y * u.mist.z;
    let toP = in.world - u.camPos.xyz;
    let dir = toP / max(length(toP), 1e-4);
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    let c = u.mistColor.rgb * 1.05 + u.sunColor.rgb * (pow(sd, 4.0) * 0.6 + 0.08) * u.sunDir.w;
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a);
    return out;
}

// ---------------------------------------------------------------------------
// Pollen: each instance is a mote in a box that travels with the camera
// (wrapping, so each mote stays put in the world until it leaves), drifting
// downwind and floating in slow loops; one in a few is a petal that tumbles
// down. Drawn as camera-facing discs that soften (bokeh) away from the
// focus distance.

struct PollenOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) tint: vec4<f32>,  // rgb, alpha
    @location(2) shape: vec4<f32>, // x softness, y petal, z dist
};

@vertex
fn vs_pollen(@builtin(vertex_index) vi: u32, @location(0) mote: f32) -> PollenOut {
    var out: PollenOut;
    let id = mote;
    let r1 = hash1(id * 1.13 + 0.5);
    let r2 = hash1(id * 2.71 + 1.7);
    let r3 = hash1(id * 3.37 + 4.1);
    let r4 = hash1(id * 5.19 + 2.3);
    let t = u.camPos.w;
    let size = vec3<f32>(36.0, 9.0, 36.0);
    let speed = u.pollen.z;
    let petal = select(0.0, 1.0, r4 < u.petals.x);
    // Drift downwind, with a slow buoyant rise and lazy loops; petals fall.
    let drift = vec3<f32>(u.wind.x, 0.0, u.wind.y) * u.windPhase.x * 0.3 * (0.6 + 0.8 * r4);
    let fall = select(t * 0.03 * speed * (r4 - 0.3), -t * 0.22 * speed * (0.6 + r2), petal > 0.5);
    let loops = vec3<f32>(
        sin(t * 0.21 * speed + r1 * 30.0) * 0.8 + sin(t * 0.53 * speed + r3 * 11.0) * 0.25,
        sin(t * 0.17 * speed + r2 * 20.0) * 0.5 + fall,
        cos(t * 0.19 * speed + r3 * 25.0) * 0.8 + cos(t * 0.47 * speed + r1 * 13.0) * 0.25);
    var p = vec3<f32>(r1, r2, r3) * size + drift + loops;
    let lo = u.pollenBox.xyz - size * 0.5;
    p = lo + (((p - lo) % size) + size) % size;

    var radius = u.pollen.y * (0.5 + r3 * r3 * 1.2);
    if (petal > 0.5) {
        radius = u.petals.y * (0.7 + 0.6 * r1);
    }
    let toP = p - u.camPos.xyz;
    let dist = length(toP);
    let focus = u.camFwd.w;
    let coc = abs(1.0 - dist / focus) * u.pollenBox.w * 0.012;
    let grown = radius + coc;
    let corner = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    var c = corner[vi];
    var stretch = vec2<f32>(1.0, 1.0);
    if (petal > 0.5) {
        let a = t * (0.8 + r2) * speed + r1 * 6.28;
        let flip = 0.3 + 0.7 * abs(sin(t * (0.6 + r3) * speed + r2 * 6.28));
        let cs = cos(a);
        let sn = sin(a);
        c = vec2<f32>(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
        stretch = vec2<f32>(1.0, flip);
    }
    let world = p + (u.camRight.xyz * c.x + u.camUp.xyz * c.y) * grown;
    out.clip = u.viewProj * vec4<f32>(world, 1.0);
    out.uv = corner[vi] / stretch;
    let near = smoothstep(1.5, 5.0, dist);
    let edge = smoothstep(0.0, 3.0, min(min(p.x - lo.x, lo.x + size.x - p.x), min(p.z - lo.z, lo.z + size.z - p.z)))
        * smoothstep(0.0, 1.5, min(p.y - lo.y, lo.y + size.y - p.y));
    let twinkle = 0.7 + 0.3 * sin(t * (1.5 + r2 * 2.0) + r1 * 40.0);
    let spread = (radius * radius) / (grown * grown);
    var tint = u.pollenColor.rgb * mix(0.85, 1.2, r1);
    if (r2 > 0.8) {
        // A few motes are bright, sunlit sparks.
        tint = mix(u.pollenColor.rgb, vec3<f32>(1.0, 0.95, 0.85), 0.6) * 1.5;
    }
    if (petal > 0.5) {
        // Golden petals and white ones, as on the bank.
        tint = select(u.petalColor.rgb, vec3<f32>(1.0, 0.97, 0.92), r3 > 0.62);
    }
    let lit = mist(tint, p);
    out.tint = vec4<f32>(lit.rgb, u.pollenColor.w * near * edge * twinkle * mix(0.35, 1.0, spread) * clamp(u.pollen.x - id, 0.0, 1.0));
    out.shape = vec4<f32>(coc / grown, petal, dist, 0.0);
    return out;
}

@fragment
fn fs_pollen(in: PollenOut) -> FragOut {
    var out: FragOut;
    let r = length(in.uv);
    if (r > 1.0) {
        discard;
    }
    let soft = clamp(in.shape.x, 0.0, 1.0);
    let core = exp(-r * r * 9.0);
    let glow = (1.0 - smoothstep(0.2, 1.0, r)) * 0.45;
    let bokeh = (1.0 - smoothstep(0.82, 1.0, r)) * (0.55 + 0.45 * smoothstep(0.5, 0.95, r));
    var a = mix(core + glow * u.pollen.w, bokeh * 0.6, soft);
    if (in.shape.y > 0.5) {
        a = mix(1.0 - smoothstep(0.75, 1.0, r), bokeh * 0.6, soft);
    }
    a *= in.tint.a;
    let c = in.tint.rgb * (1.0 + u.pollen.w * core * 2.5 * (1.0 - in.shape.y));
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a);
    return out;
}
