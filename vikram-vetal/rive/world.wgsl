// Shishupalgarh: sunlit sandstone ruins in a meadow, ivy on the pillars,
// wind in the leaves and pink pollen drifting through a soft haze.
//
// One uniform block for every draw; `mode.x` says what is being drawn.
//   vs_static   the static meshes (stone, rock, clay, ground, bark, vines)
//   vs_inst     instanced templates (leaves, grass clumps, flowers), swaying
//               in the wind
//   fs_main     stylized lighting (a toon ramp from cool shadow to warm sun),
//               procedural materials and haze
//   vs_sky / fs_sky       the pastel sky and its clouds, behind everything
//   vs_pollen / fs_pollen pollen motes and petals, as soft bokeh discs
//
// `glory.x` takes the ruins (0) to their full glory (1), over the 10 s of the
// RuinsToGlory animation from Blender: objects move by their `model` matrix
// and morph by their shape key (weight in `mode.w`). Here, the painted ivy
// and moss dissolve and the leaf cards wither with the ivy meshes (the first
// 4.5 s), grass sinks under the rising floor, and the stone comes up clean.
//
// Colours are linear. The scene is stored compressed (sqrt(c / (1 + c))) so
// the post pass can recover values above 1 for the bloom; alpha holds how
// far away the pixel is, for the post pass's depth of field.

struct Uniforms {
    viewProj: mat4x4<f32>,
    camPos: vec4<f32>,      // xyz, time
    sunDir: vec4<f32>,      // towards the sun, intensity
    sunColor: vec4<f32>,    // rgb, ambient
    shadowColor: vec4<f32>, // rgb, toon softness
    skyTop: vec4<f32>,      // rgb, cloud amount
    skyHorizon: vec4<f32>,  // rgb, haze density
    hazeColor: vec4<f32>,   // rgb, haze height falloff
    wind: vec4<f32>,        // direction x, direction z, strength, gustiness
    windPhase: vec4<f32>,   // x accumulated phase, y flutter, z cloud drift
    mode: vec4<f32>,        // x what is drawn, y foliage translucency
    colorA: vec4<f32>,      // ramp: dark
    colorB: vec4<f32>,      //       mid
    colorC: vec4<f32>,      //       light
    pollen: vec4<f32>,      // x count, y size, z drift speed, w glow
    pollenColor: vec4<f32>, // rgb, opacity
    camRight: vec4<f32>,    // xyz, tan(half fov x)
    camUp: vec4<f32>,       // xyz, tan(half fov y)
    camFwd: vec4<f32>,      // xyz, focus distance
    pollenBox: vec4<f32>,   // centre xyz, bokeh
    petals: vec4<f32>,      // x fraction of motes that are petals, y petal size
    model: mat4x4<f32>,     // static meshes: identity, or a fragment's pose
    glory: vec4<f32>,       // x ruins (0) to full glory (1), y how near the camera nothing stands (metres)
    lightViewProj: mat4x4<f32>, // world to the sun's shadow map
    skyMid: vec4<f32>,      // the sky between horizon and top (lavender), mountain height
    mountain: vec4<f32>,    // the nearest range's colour, the moon (0 on amavas)
    // The fireflies that light their surroundings: position, glow (0-1).
    // The first FIREFLY_LIGHTS motes fly where these say.
    fireflyLights: array<vec4<f32>, 24>,
    hero: vec4<f32>,        // the hero tree's base xyz, the share of fireflies round it
    heroB: vec4<f32>,       // ghost lights: how many, their colour (rgb)
    // Each ghost light's orbit round the hero tree: radius, height, phase,
    // angular speed (radians a second; negative goes the other way).
    ghosts: array<vec4<f32>, 16>,
    // Where each ghost light is this frame and its flicker (from the script,
    // so the light needs no trigonometry per pixel).
    ghostNow: array<vec4<f32>, 16>,
    // The golden wave from King Vikram's bow: where it began and how far it
    // has spread (metres); its colour (linear) and strength.
    blast: vec4<f32>,
    blastColor: vec4<f32>,
    // King Vikram's own light (his earrings, and his bow's aura when he
    // draws): where it is, how strong; and its colour (linear).
    kingLight: vec4<f32>,
    kingLightColor: vec4<f32>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
// The sun's shadow map (depth, from vs_*_shadow), sampled with comparison.
@group(0) @binding(1) var shadowMap: texture_depth_2d;
@group(0) @binding(2) var shadowSampler: sampler_comparison;
const SHADOW_SIZE: f32 = 2048.0;
const FIREFLY_LIGHTS: u32 = 12u;
// Ghost-light instances start here in the mote ids; each ghost is a head
// and three trailing ghosts of itself.
const GHOST_BASE: f32 = 3000.0;
const GHOST_TRAIL: u32 = 4u;

// Where ghost light i is at time t: circling the hero tree, bobbing.
fn ghostPos(i: u32, t: f32) -> vec3<f32> {
    let g = u.ghosts[i];
    let a = g.z + t * g.w;
    let bob = sin(t * 0.9 + g.z * 3.0) * 0.35 + sin(t * 2.3 + g.z) * 0.08;
    return u.hero.xyz + vec3<f32>(cos(a) * g.x, g.y + bob, sin(a) * g.x);
}

// A ghost light flickers like a candle in a draught.
fn ghostFlicker(i: u32, t: f32) -> f32 {
    let fi = f32(i);
    return 0.8 + 0.12 * sin(t * 7.3 + fi * 1.7) + 0.08 * sin(t * 13.1 + fi * 4.1);
}

// The ghost lights' cool glow on what they pass.
fn ghostLight(p: vec3<f32>, n: vec3<f32>, wrap: f32) -> f32 {
    var sum = 0.0;
    let t = u.camPos.w;
    let count = u32(clamp(u.heroB.x, 0.0, 16.0));
    for (var i = 0u; i < count; i++) {
        let g = u.ghostNow[i];
        let dv = g.xyz - p;
        let d2 = dot(dv, dv);
        if (d2 > 49.0) {
            continue;
        }
        let facing = max(dot(n, dv * inverseSqrt(d2 + 1e-4)), 0.0) * (1.0 - wrap) + wrap;
        sum += g.w * facing / (1.0 + d2 * 0.6);
    }
    return sum;
}

// The warm light of the nearby fireflies on a surface: each a soft point
// light that swells and fades with its blink.
fn fireflyLight(p: vec3<f32>, n: vec3<f32>, wrap: f32) -> f32 {
    var sum = 0.0;
    for (var i = 0u; i < FIREFLY_LIGHTS; i++) {
        let l = u.fireflyLights[i];
        if (l.w <= 0.01) {
            continue;
        }
        let dv = l.xyz - p;
        let d2 = dot(dv, dv);
        // Past 4 m a firefly's light is lost in the dark.
        if (d2 > 16.0) {
            continue;
        }
        let facing = max(dot(n, dv * inverseSqrt(d2 + 1e-4)), 0.0) * (1.0 - wrap) + wrap;
        sum += l.w * facing / (1.0 + d2 * 3.0);
    }
    return sum;
}

// Materials (mode.x).
const STONE: f32 = 1.0;
const ROCK: f32 = 2.0;
const CLAY: f32 = 3.0;
const GROUND: f32 = 4.0;
const GROUND_FAR: f32 = 5.0;
const BARK: f32 = 6.0;
const VINE: f32 = 7.0;
const FLAME: f32 = 8.0;
const BUSH_LEAF: f32 = 10.0;
const CREEPER_LEAF: f32 = 11.0;
const TREE_LEAF: f32 = 12.0;
const GRASS: f32 = 13.0;
const FLOWER: f32 = 14.0;
const BUSH_PUFF: f32 = 15.0;
const CROWN_PUFF: f32 = 16.0;
const IVY_MESH: f32 = 17.0;
const BUSH_MESH: f32 = 18.0;
const THATCH: f32 = 19.0;
const WOOD: f32 = 20.0;
const SUNFLOWER: f32 = 21.0;
const DAISY: f32 = 22.0;
const FLOOR: f32 = 23.0;
const PILLAR: f32 = 24.0;

fn isStone(kind: f32) -> bool {
    return kind == STONE || kind == PILLAR || kind == FLOOR;
}

// Bushes come in two tones, a bush at a time: the light, sunny greens of
// the first version, and dark emerald over forest-teal. Which one varies
// smoothly over the meadow (about a metre and a half per patch), so the
// clumps and leaves of one bush agree.
fn lightBush(place: vec3<f32>) -> f32 {
    return smoothstep(0.44, 0.56, noise3(place * 0.55 + vec3<f32>(7.0, 0.0, 3.0)));
}

fn lightRamp(t: f32, lo: vec3<f32>, mid: vec3<f32>, hi: vec3<f32>) -> vec3<f32> {
    let k = clamp(t, 0.0, 1.0);
    if (k < 0.55) {
        return mix(lo, mid, k / 0.55);
    }
    return mix(mid, hi, (k - 0.55) / 0.45);
}

fn isBloom(kind: f32) -> bool {
    return kind == SUNFLOWER || kind == DAISY;
}

// The night scene's own materials (tools/export_world.py); FOLIAGE is
// BUSH_MESH (the leafy clump shading).
const BONE: f32 = 25.0;
const SOCKET: f32 = 26.0;
const GRASS_MESH: f32 = 27.0;
const MOSS: f32 = 28.0;
const ASH: f32 = 29.0;

fn isFoliage(kind: f32) -> bool {
    return (kind >= BUSH_LEAF && kind <= BUSH_MESH) || isBloom(kind) || kind == GRASS_MESH || kind == MOSS;
}

// Greens in harmony: each plant has its own family (its ramp, from the
// script), and the meadow drifts in broad patches between a cool,
// blue-green and a warm, sunny yellow-green, so neighbours differ gently.
fn greenHarmony(c: vec3<f32>, place: vec3<f32>, seed: f32) -> vec3<f32> {
    let drift = noise3(place * 0.09) * 0.75 + seed * 0.25;
    let cool = vec3<f32>(0.84, 1.0, 1.14);
    let warm = vec3<f32>(1.1, 1.03, 0.8);
    return c * mix(cool, warm, smoothstep(0.2, 0.8, drift));
}

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
        s += a * noise3(q);
        q = q * 2.03 + vec3<f32>(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s / 0.9375;
}

// Distance to the nearest cell point (voronoi F1), for pits in the stone.
fn cells(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var d = 8.0;
    for (var z = -1; z <= 1; z++) {
        for (var y = -1; y <= 1; y++) {
            for (var x = -1; x <= 1; x++) {
                let o = vec3<f32>(f32(x), f32(y), f32(z));
                let c = i + o;
                let r = vec3<f32>(hash3(c), hash3(c + 17.0), hash3(c + 43.0));
                d = min(d, length(o + r - f));
            }
        }
    }
    return d;
}

fn ramp3(t: f32) -> vec3<f32> {
    let k = clamp(t, 0.0, 1.0);
    if (k < 0.55) {
        return mix(u.colorA.rgb, u.colorB.rgb, k / 0.55);
    }
    return mix(u.colorB.rgb, u.colorC.rgb, (k - 0.55) / 0.45);
}

// ---------------------------------------------------------------------------
// Wind

// How far a point that sways by `weight` is pushed by the wind: a slow gust
// rolling across the meadow along the wind, and a quicker sway of its own.
fn windOffset(world: vec3<f32>, weight: f32, seed: f32) -> vec3<f32> {
    let t = u.windPhase.x;
    let dir = vec3<f32>(u.wind.x, 0.0, u.wind.y);
    let along = dot(world.xz, u.wind.xy);
    let across = dot(world.xz, vec2<f32>(-u.wind.y, u.wind.x));
    let roll = 0.5 + 0.5 * sin(along * 0.45 - t * 1.25 + sin(across * 0.21 + t * 0.3) * 1.4);
    let gust = mix(0.55, roll * roll * 1.6, u.wind.w);
    let own = sin(t * 2.3 + seed * 6.283 + along * 0.9) * 0.3 + sin(t * 3.9 + seed * 17.0) * 0.12;
    let push = u.wind.z * weight * (gust + own);
    let side = vec3<f32>(-u.wind.y, 0.0, u.wind.x) * sin(t * 1.7 + seed * 9.0 + across) * 0.18;
    // Bending over, it also dips a little.
    var off = (dir + side) * push - vec3<f32>(0.0, abs(push) * 0.25, 0.0);
    // The golden wave shoves what it passes outward as it goes by.
    if (u.blastColor.w > 0.0) {
        let d = world.xz - u.blast.xz;
        let dl = max(length(d), 0.5);
        let front = exp(-pow((dl - u.blast.w) / 2.5, 2.0));
        let shove = front * u.blastColor.w * weight * (1.1 + 0.4 * sin(seed * 31.0));
        off += vec3<f32>(d.x / dl, 0.0, d.y / dl) * shove - vec3<f32>(0.0, shove * 0.3, 0.0);
    }
    return off;
}

// The golden wave's light at a point: bright at its front, an afterglow
// behind it.
fn blastLight(p: vec3<f32>) -> f32 {
    if (u.blastColor.w <= 0.0) {
        return 0.0;
    }
    let bd = distance(p, u.blast.xyz);
    let width = 1.2 + u.blast.w * 0.1;
    let front = exp(-pow((bd - u.blast.w) / width, 2.0));
    let behind = select(0.0, exp(-(u.blast.w - bd) / 9.0), bd < u.blast.w);
    return (front * 2.4 + behind * 0.5) * u.blastColor.w;
}

// ---------------------------------------------------------------------------
// Vertex stages

struct VertexOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) albedo: vec3<f32>,
    @location(3) params: vec4<f32>, // material, path, grass, seed
    // Objects: the position and normal in their own space (for carving).
    @location(4) local: vec3<f32>,
    @location(5) localNormal: vec3<f32>,
    // The painted colour (static meshes), a = 1 when there is one.
    @location(6) paint: vec4<f32>,
};

struct StaticIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec4<f32>,
    @location(2) extra: vec4<f32>, // wind weight, seed, path, grass
    // The shape key's deltas (zero for meshes without one).
    @location(3) morphPosition: vec3<f32>,
    @location(4) morphNormal: vec4<f32>,
    // The colour painted in Blender (a = 1 when there is one).
    @location(5) color: vec4<f32>,
};

@vertex
fn vs_static(v: StaticIn) -> VertexOut {
    return staticOut(v);
}

// The shadow pass: the same surfaces, seen from the sun.
@vertex
fn vs_static_shadow(v: StaticIn) -> @builtin(position) vec4<f32> {
    return u.lightViewProj * vec4<f32>(staticOut(v).world, 1.0);
}

fn staticOut(v: StaticIn) -> VertexOut {
    var out: VertexOut;
    let w = u.mode.w;
    var p = (u.model * vec4<f32>(v.position + v.morphPosition * w, 1.0)).xyz;
    if (v.extra.x > 0.0) {
        p += windOffset(p, v.extra.x, v.extra.y) * 0.5;
    }
    out.clip = u.viewProj * vec4<f32>(p, 1.0);
    out.world = p;
    out.normal = (u.model * vec4<f32>(v.normal.xyz + v.morphNormal.xyz * w, 0.0)).xyz;
    out.albedo = vec3<f32>(1.0);
    out.params = vec4<f32>(u.mode.x, v.extra.z, v.extra.w, v.extra.y);
    out.local = v.position + v.morphPosition * w;
    out.localNormal = v.normal.xyz + v.morphNormal.xyz * w;
    out.paint = v.color;
    return out;
}

struct InstIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) bend: f32,
    @location(3) placeScale: vec4<f32>,
    @location(4) axisX: vec4<f32>, // w: random
    @location(5) axisY: vec4<f32>, // w: random
};

@vertex
fn vs_inst(v: InstIn) -> VertexOut {
    return instOut(v);
}

@vertex
fn vs_inst_shadow(v: InstIn) -> @builtin(position) vec4<f32> {
    return u.lightViewProj * vec4<f32>(instOut(v).world, 1.0);
}

fn instOut(v: InstIn) -> VertexOut {
    var out: VertexOut;
    let kind = u.mode.x;
    let ax = normalize(v.axisX.xyz);
    let ay = normalize(v.axisY.xyz - ax * dot(v.axisY.xyz, ax));
    let az = cross(ax, ay);
    let seed = v.axisX.w * 0.5 + 0.5;
    let seed2 = v.axisY.w * 0.5 + 0.5;
    var s = v.placeScale.w;
    let base = v.placeScale.xyz;
    // What grows only on the ruins withers away in glory, each at its own
    // moment.
    // (its random is the moment, in glory, that it goes).
    if (v.axisY.w > 0.5 && (kind == CREEPER_LEAF || kind == BUSH_PUFF || kind == BUSH_LEAF || isBloom(kind))) {
        s *= 1.0 - smoothstep(seed - 0.04, seed + 0.04, u.glory.x);
    }
    // The glory floor (52.8 x 22 m, rising 4.6-5.6 s) covers the meadow:
    // grass and flowers sink as it comes.
    if ((kind == GRASS || kind == FLOWER || isBloom(kind)) && v.axisY.w < 0.5 && abs(base.x) < 26.6 && abs(base.z) < 11.2) {
        s *= 1.0 - smoothstep(0.44, 0.52, u.glory.x);
    }
    var p = base + (ax * v.position.x + ay * v.position.y + az * v.position.z) * s;
    let n = normalize(ax * v.normal.x + ay * v.normal.y + az * v.normal.z);

    // How much it sways: grass and flowers from the root, leaves more the
    // higher (and further out) they grow; ivy flutters against the stone.
    var weight = 0.0;
    var flutter = 0.0;
    if (kind == GRASS) {
        weight = v.bend * v.bend * 0.13;
    } else if (kind == FLOWER) {
        weight = 0.05 + clamp(base.y, 0.0, 2.0) * 0.02;
        flutter = 0.3;
    } else if (isBloom(kind)) {
        // Nodding on their stems: the head sways, the root stays.
        weight = clamp(v.position.y / 3.0, 0.0, 1.0) * 0.07;
    } else if (kind == CREEPER_LEAF) {
        weight = 0.012 + clamp(base.y / 6.0, 0.0, 1.0) * 0.02;
        flutter = 1.0;
    } else if (kind == BUSH_LEAF) {
        weight = clamp(base.y / 2.2, 0.0, 1.0) * 0.07 + 0.01;
        flutter = 0.8;
    } else if (kind == BUSH_PUFF) {
        weight = v.bend * 0.06;
    } else if (kind == CROWN_PUFF) {
        weight = 0.06 + v.bend * 0.1;
    } else {
        weight = clamp((base.y - 1.0) / 4.5, 0.0, 1.0) * 0.12 + 0.01;
        flutter = 0.8;
    }
    p += windOffset(base, weight, seed);
    // Clumps breathe: their surface ripples as gusts pass through.
    if (kind == BUSH_PUFF || kind == CROWN_PUFF) {
        let t = u.windPhase.x;
        let ripple = sin(t * 2.6 + seed * 20.0 + dot(v.position, vec3<f32>(3.1, 2.3, 2.7))) * 0.5
            + sin(t * 4.1 + seed * 7.0 + v.position.y * 5.0) * 0.5;
        p += n * ripple * 0.035 * s * u.wind.z * (0.4 + v.bend);
    }
    // Leaves flick about their stems: a quick wobble that grows to the tip.
    if (flutter > 0.0) {
        let t = u.windPhase.x;
        let f = sin(t * 7.0 + seed * 40.0 + base.x * 3.0) * 0.6 + sin(t * 11.3 + seed2 * 25.0) * 0.4;
        // About a third of a leaf's length (templates are ~0.09 m, times s).
        let amp = u.wind.z * u.windPhase.y * flutter * v.bend * s * 0.03;
        p += az * f * amp + ay * abs(f) * amp * 0.3;
    }

    // Colour: a ramp per kind, from the instance's random.
    var albedo = ramp3(seed);
    if (kind == GRASS) {
        albedo = ramp3(v.bend * 0.8 + seed * 0.35) * (0.82 + 0.3 * seed2);
    } else if (kind == FLOWER) {
        // White, blush pink and buttery yellow, mostly pink.
        let k = seed;
        albedo = mix(u.colorA.rgb, u.colorB.rgb, smoothstep(0.15, 0.5, k));
        albedo = mix(albedo, u.colorC.rgb, smoothstep(0.85, 0.97, k));
        // Their hearts are yellow.
        albedo = mix(vec3<f32>(1.0, 0.78, 0.25), albedo, smoothstep(0.1, 0.45, v.bend));
    } else if (isBloom(kind)) {
        let r = v.bend;
        if (r < 0.0) {
            albedo = vec3<f32>(0.1, 0.3, 0.06);
        } else if (kind == SUNFLOWER) {
            // Golden petals, a dark seed-brown centre with a ring of pollen.
            let petal = mix(vec3<f32>(0.95, 0.5, 0.02), vec3<f32>(1.0, 0.78, 0.12), r);
            let centre = mix(vec3<f32>(0.12, 0.05, 0.015), vec3<f32>(0.45, 0.24, 0.04), smoothstep(0.1, 0.25, r));
            albedo = select(petal, centre, r < 0.26) * (0.9 + 0.2 * seed);
        } else {
            // White petals, faintly warm, and a buttercup-yellow centre.
            let petal = mix(vec3<f32>(0.86, 0.85, 0.78), vec3<f32>(1.0, 0.99, 0.95), r);
            albedo = select(petal, vec3<f32>(1.0, 0.72, 0.1), r < 0.26);
        }
    } else if (kind == BUSH_PUFF || kind == CROWN_PUFF) {
        // The clump is the shadowed core under its leaves.
        albedo = ramp3(seed * 0.4 + v.bend * 0.4) * (0.5 + 0.3 * v.bend);
        if (kind == BUSH_PUFF) {
            let light = lightRamp(seed * 0.5 + v.bend * 0.55, vec3<f32>(0.05, 0.16, 0.03), vec3<f32>(0.18, 0.38, 0.06), vec3<f32>(0.44, 0.58, 0.14))
                * (0.75 + 0.35 * v.bend);
            albedo = mix(albedo, light, lightBush(base));
        }
    } else {
        // Leaves catch more light at their tips.
        if (kind == BUSH_LEAF) {
            // At night, the lighter bushes are only a shade lighter.
            let light = lightRamp(seed, vec3<f32>(0.012, 0.04, 0.02), vec3<f32>(0.035, 0.1, 0.045), vec3<f32>(0.09, 0.17, 0.08));
            albedo = mix(albedo, light, lightBush(base));
        }
        albedo *= 0.85 + 0.3 * v.bend;
    }

    if (kind != FLOWER && !isBloom(kind)) {
        albedo = greenHarmony(albedo, base, seed2);
    } else if (isBloom(kind) && v.bend < 0.0) {
        albedo = greenHarmony(albedo, base, seed2);
    }
    out.clip = u.viewProj * vec4<f32>(p, 1.0);
    out.world = p;
    out.normal = n;
    out.albedo = albedo;
    out.params = vec4<f32>(kind, 0.0, s, seed);
    out.local = vec3<f32>(0.0);
    out.localNormal = vec3<f32>(0.0, 1.0, 0.0);
    out.paint = vec4<f32>(0.0);
    return out;
}

// ---------------------------------------------------------------------------
// Lighting

// How much moon there is (0 on amavas, the new-moon night): its disc, glow
// and the warmth of the sky toward it.
fn moonAmount() -> f32 {
    return u.mountain.w;
}

fn skyColor(dir: vec3<f32>) -> vec3<f32> {
    let y = dir.y;
    // Warm yellow at the horizon, lavender through the middle, blue above;
    // the horizon warms most toward the sun.
    let toSun = max(dot(normalize(vec3<f32>(dir.x, 0.0, dir.z)), normalize(vec3<f32>(u.sunDir.x, 0.0, u.sunDir.z))), 0.0);
    let horizon = mix(mix(u.skyMid.rgb, u.skyHorizon.rgb, 0.6), u.skyHorizon.rgb, toSun);
    var c = mix(horizon, u.skyMid.rgb, smoothstep(0.0, 0.16, y));
    c = mix(c, u.skyTop.rgb, smoothstep(0.1, 0.42, y));
    // Below the horizon, the haze.
    c = mix(c, u.hazeColor.rgb, clamp(-y * 6.0, 0.0, 1.0));
    // The sun's glow.
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    // The moon's glow on the sky (its disc is drawn in fs_sky).
    c += u.sunColor.rgb * (pow(sd, 8.0) * 0.18 + pow(sd, 64.0) * 0.3) * moonAmount();
    return c;
}

fn haze(c: vec3<f32>, world: vec3<f32>) -> vec4<f32> {
    let toP = world - u.camPos.xyz;
    let d = length(toP);
    let dir = toP / max(d, 1e-4);
    let density = u.skyHorizon.w;
    // Thicker low down, thinning with height.
    let h = max(world.y, 0.0);
    // Night mist: thick in a layer a metre or two deep over the ground,
    // broken into wisps that roll along with the wind.
    let flow = vec3<f32>(u.wind.x, 0.0, u.wind.y) * u.windPhase.x * 0.35;
    let wisp = noise3(world * vec3<f32>(0.16, 0.7, 0.16) - flow) * 0.65 + noise3(world * vec3<f32>(0.45, 1.4, 0.45) - flow * 1.6) * 0.35;
    let thick = exp(-h * u.hazeColor.w) * mix(0.25, 1.8, smoothstep(0.25, 0.75, wisp));
    let f = 1.0 - exp(-d * density * (0.3 + 0.7 * thick));
    // Light scattering toward the sun.
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    let scatter = u.hazeColor.rgb + u.sunColor.rgb * pow(sd, 6.0) * 0.45;
    let farSky = skyColor(vec3<f32>(dir.x, max(dir.y, 0.0) * 0.5, dir.z));
    let fogCol = mix(scatter, farSky, smoothstep(30.0, 200.0, d));
    var mixed = mix(c, fogCol, clamp(f, 0.0, 1.0));
    // The mist itself glows where the golden wave passes through it.
    mixed += u.blastColor.rgb * blastLight(world) * clamp(f, 0.0, 1.0) * 0.6;
    return vec4<f32>(mixed, d);
}

// How much sun reaches this point (0 in shadow, 1 lit), from the shadow
// map, softened over a 3x3 of comparisons.
fn sunShadow(world: vec3<f32>, n: vec3<f32>) -> f32 {
    let lp = u.lightViewProj * vec4<f32>(world + n * 0.06 + u.sunDir.xyz * 0.03, 1.0);
    let ndc = lp.xyz / lp.w;
    let uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0) {
        return 1.0;
    }
    var lit = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let o = vec2<f32>(f32(x), f32(y)) * (1.6 / SHADOW_SIZE);
            lit += textureSampleCompareLevel(shadowMap, shadowSampler, uv + o, ndc.z - 0.0012);
        }
    }
    return lit / 9.0;
}

// ---------------------------------------------------------------------------
// Carving on the pillars, in a pillar's own space (y up from its base): a
// beaded band every 1.15 m, and between the bands framed panels with, by
// turns, a lotus and a diamond lattice. 0 is a groove, 0.5 the face, 1 a
// raised motif.
fn carveHeight(u0: f32, v: f32) -> f32 {
    let step = 1.15;
    let vb = v - 0.3;
    let bi = floor(vb / step);
    let bv = vb - bi * step;
    if (bv < 0.24) {
        let bead = length(vec2<f32>((fract(u0 / 0.1) - 0.5) * 0.1, bv - 0.12));
        var h = 0.5 + 0.5 * smoothstep(0.04, 0.026, bead);
        h = max(h, 0.5 + 0.4 * smoothstep(0.012, 0.004, abs(bv - 0.014)));
        h = max(h, 0.5 + 0.4 * smoothstep(0.012, 0.004, abs(bv - 0.226)));
        return h;
    }
    let pc = bv - 0.24 - 0.455;
    let frame = abs(max(abs(u0) - 0.29, abs(pc) - 0.37));
    var h = mix(0.5, 0.0, smoothstep(0.016, 0.006, frame));
    if (abs(u0) < 0.27 && abs(pc) < 0.35) {
        if (fract(bi * 0.5) < 0.25) {
            // A lotus: eight petals round a seed.
            let r = length(vec2<f32>(u0, pc));
            let a = atan2(pc, u0);
            let petal = 0.17 * (0.55 + 0.45 * abs(cos(a * 4.0)));
            h = max(h, 0.5 + 0.5 * smoothstep(petal, petal - 0.02, r));
            h = mix(h, 0.15, smoothstep(0.012, 0.0, abs(r - 0.205)));
            h = max(h, smoothstep(0.045, 0.03, r));
        } else {
            // A lattice of diamonds.
            let q = vec2<f32>(u0, pc) * 9.0;
            let dd = abs(fract(q.x + q.y) - 0.5) + abs(fract(q.x - q.y) - 0.5);
            h = 0.5 + 0.5 * smoothstep(0.42, 0.3, dd);
        }
    }
    return h;
}

struct Carving {
    h: f32,
    dir: vec3<f32>,   // the normal's tilt from the relief
};

fn carving(lp: vec3<f32>, ln: vec3<f32>) -> Carving {
    var out: Carving;
    out.h = 0.5;
    out.dir = vec3<f32>(0.0);
    if (abs(ln.y) > 0.6 || lp.y < 0.05) {
        return out;
    }
    let onX = abs(ln.x) > abs(ln.z);
    let u0 = select(lp.x, lp.z, onX);
    let tangent = select(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), onX);
    let e = 0.006;
    out.h = carveHeight(u0, lp.y);
    let du = (carveHeight(u0 + e, lp.y) - carveHeight(u0 - e, lp.y)) / (2.0 * e);
    let dv = (carveHeight(u0, lp.y + e) - carveHeight(u0, lp.y - e)) / (2.0 * e);
    out.dir = -(tangent * du + vec3<f32>(0.0, 1.0, 0.0) * dv) * 0.02;
    return out;
}

// The courtyard floor: flagstones on top, ashlar courses down the sides.
fn floorAlbedo(p: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    var cellId: vec2<f32>;
    var edge: f32;
    if (n.y > 0.5) {
        let row = floor(p.z / 0.75);
        let q = vec2<f32>(p.x / 1.1 + row * 0.5, p.z / 0.75);
        cellId = floor(q);
        let f = fract(q);
        edge = min(min(f.x, 1.0 - f.x) * 1.1, min(f.y, 1.0 - f.y) * 0.75);
    } else {
        let along = select(p.x, p.z, abs(n.x) > abs(n.z));
        let row = floor(p.y / 0.3);
        let q = vec2<f32>(along / 0.85 + row * 0.5, p.y / 0.3);
        cellId = floor(q);
        let f = fract(q);
        edge = min(min(f.x, 1.0 - f.x) * 0.85, min(f.y, 1.0 - f.y) * 0.3);
    }
    let tone = hash3(vec3<f32>(cellId, 3.0));
    var c = mix(vec3<f32>(0.6, 0.45, 0.28), vec3<f32>(0.82, 0.66, 0.44), tone);
    c *= 0.88 + 0.2 * noise3(p * 6.0);
    // Worn hollows and dark grout lines.
    c *= mix(0.45, 1.0, smoothstep(0.008, 0.03, edge));
    return c;
}

fn encode(c: vec3<f32>, dist: f32) -> vec4<f32> {
    let m = max(c, vec3<f32>(0.0));
    let blur = clamp(abs(1.0 - dist / u.camFwd.w) * 0.9, 0.0, 1.0);
    return vec4<f32>(sqrt(m / (1.0 + m)), blur);
}

// How much of the ruin's overgrowth is left at this point: it recedes in
// glory through a noisy front, so it dissolves in patches.
fn overgrowth(p: vec3<f32>) -> f32 {
    let g = u.glory.x;
    let k = noise3(p * 2.3) * 0.7 + noise3(p * 7.0) * 0.3;
    return 1.0 - smoothstep(k - 0.08, k + 0.08, g * 2.4 - 0.1);
}

fn stoneAlbedo(p: vec3<f32>, n: vec3<f32>, ivy: f32) -> vec3<f32> {
    // Sandstone: a warm ramp over broad noise, with banding along the
    // courses and darker pits; moss gathers in patches low down and on top.
    let q = p * 1.3;
    let n1 = fbm3(q);
    var c = mix(vec3<f32>(0.40, 0.27, 0.15), vec3<f32>(0.72, 0.55, 0.34), smoothstep(0.35, 0.68, n1));
    let fine = noise3(p * 9.0);
    c *= 0.86 + 0.24 * fine;
    let band = 0.5 + 0.5 * sin(p.y * 9.0 + n1 * 3.0);
    c *= 0.94 + 0.08 * band;
    let pit = cells(p * 5.0);
    c *= mix(0.45, 1.0, smoothstep(0.06, 0.16, pit));
    let mossN = fbm3(p * 2.0 + vec3<f32>(4.0, 0.0, 2.0));
    let low = 1.0 - smoothstep(0.3, 2.8, p.y);
    let up = smoothstep(0.4, 0.9, n.y);
    let moss = smoothstep(0.6, 0.72, mossN + low * 0.12 + up * 0.2);
    let wild = overgrowth(p);
    // In glory the stone is clean, smoother and warmer.
    let g = smoothstep(0.2, 0.6, u.glory.x);
    c = mix(c, mix(vec3<f32>(0.5, 0.34, 0.19), vec3<f32>(0.76, 0.56, 0.34), smoothstep(0.3, 0.7, n1)) * (0.9 + 0.16 * fine), g * 0.65);
    c = mix(c, vec3<f32>(0.24, 0.33, 0.08) * (0.8 + 0.4 * fine), moss * 0.7 * wild);
    // Ivy painted on the stone where the mask says: leafy dark greens.
    let leaf = noise3(p * 16.0);
    let cover = smoothstep(0.25, 0.6, ivy + (leaf - 0.5) * 0.5) * wild;
    let ivyCol = mix(vec3<f32>(0.06, 0.16, 0.03), vec3<f32>(0.26, 0.44, 0.09), smoothstep(0.3, 0.8, leaf));
    c = mix(c, ivyCol, cover);
    return c;
}

fn materialAlbedo(kind: f32, p: vec3<f32>, n: vec3<f32>, params: vec4<f32>, albedo: vec3<f32>) -> vec3<f32> {
    if (kind == STONE || kind == PILLAR) {
        return stoneAlbedo(p, n, params.y);
    } else if (kind == FLOOR) {
        return floorAlbedo(p, n);
    } else if (kind == ROCK) {
        let k = fbm3(p * 3.0);
        return mix(vec3<f32>(0.30, 0.27, 0.24), vec3<f32>(0.55, 0.50, 0.44), smoothstep(0.3, 0.7, k));
    } else if (kind == CLAY) {
        let k = fbm3(p * 6.0);
        return mix(vec3<f32>(0.42, 0.18, 0.08), vec3<f32>(0.70, 0.36, 0.18), smoothstep(0.3, 0.7, k));
    } else if (kind == GROUND) {
        let k = fbm3(p * vec3<f32>(0.5, 0.5, 0.5));
        let k2 = noise3(p * 4.0);
        var c = mix(vec3<f32>(0.13, 0.26, 0.05), vec3<f32>(0.30, 0.44, 0.10), smoothstep(0.3, 0.75, k));
        c *= 0.85 + 0.25 * k2;
        let dirt = mix(vec3<f32>(0.40, 0.31, 0.19), vec3<f32>(0.55, 0.45, 0.30), k2);
        return mix(c, dirt, smoothstep(0.3, 0.8, params.y));
    } else if (kind == GROUND_FAR) {
        let k = noise3(p * 0.05);
        return mix(vec3<f32>(0.20, 0.30, 0.08), vec3<f32>(0.30, 0.38, 0.12), k);
    } else if (kind == BARK) {
        return vec3<f32>(0.12, 0.085, 0.06) * (0.8 + 0.4 * noise3(p * vec3<f32>(20.0, 3.0, 20.0)));
    } else if (kind == VINE) {
        return vec3<f32>(0.16, 0.12, 0.05);
    } else if (kind == IVY_MESH) {
        let k = noise3(p * 14.0);
        return mix(vec3<f32>(0.05, 0.15, 0.03), vec3<f32>(0.28, 0.46, 0.1), smoothstep(0.25, 0.8, k));
    } else if (kind == BUSH_MESH) {
        let k = noise3(p * 3.0);
        let dark = mix(vec3<f32>(0.02, 0.11, 0.05), vec3<f32>(0.1, 0.3, 0.12), k);
        let light = mix(vec3<f32>(0.05, 0.16, 0.03), vec3<f32>(0.2, 0.4, 0.08), k);
        return greenHarmony(mix(dark, light, lightBush(p)) * (0.7 + 0.5 * smoothstep(0.0, 1.2, p.y)), p, 0.5);
    } else if (kind == THATCH) {
        // Straw, streaked down the slope, sun-bleached on top.
        let streak = noise3(vec3<f32>(p.x * 26.0, p.y * 2.5, p.z * 26.0));
        let blotch = noise3(p * 1.5);
        return mix(vec3<f32>(0.42, 0.28, 0.1), vec3<f32>(0.82, 0.62, 0.3), streak * 0.7 + blotch * 0.3);
    } else if (kind == WOOD) {
        let grain = noise3(vec3<f32>(p.x * 2.0, p.y * 30.0, p.z * 2.0));
        return mix(vec3<f32>(0.22, 0.12, 0.05), vec3<f32>(0.42, 0.25, 0.11), grain);
    } else if (kind == BONE) {
        // Old ivory, darker in the pits.
        let k = noise3(p * 18.0);
        return mix(vec3<f32>(0.55, 0.5, 0.4), vec3<f32>(0.86, 0.82, 0.7), smoothstep(0.25, 0.75, k));
    } else if (kind == SOCKET) {
        return vec3<f32>(0.03, 0.025, 0.03);
    } else if (kind == GRASS_MESH) {
        let k = noise3(p * 3.0);
        return mix(vec3<f32>(0.14, 0.15, 0.05), vec3<f32>(0.42, 0.38, 0.16), smoothstep(0.2, 0.8, k));
    } else if (kind == MOSS) {
        let k = noise3(p * vec3<f32>(9.0, 2.0, 9.0));
        return mix(vec3<f32>(0.12, 0.16, 0.08), vec3<f32>(0.34, 0.4, 0.24), k);
    } else if (kind == ASH) {
        // Grey ash and charred earth, a few embers' worth of warmth.
        let k = fbm3(p * 0.8);
        let fine = noise3(p * 7.0);
        return mix(vec3<f32>(0.12, 0.11, 0.1), vec3<f32>(0.38, 0.36, 0.34), smoothstep(0.3, 0.75, k)) * (0.85 + 0.3 * fine);
    }
    return albedo;
}

struct FragOut {
    @location(0) color: vec4<f32>,
};

@fragment
fn fs_main(in: VertexOut, @builtin(front_facing) front: bool) -> FragOut {
    var out: FragOut;
    let kind = in.params.x;
    let p = in.world;
    let view = normalize(u.camPos.xyz - p);
    // A cinematic camera clears what stands right in front of it (trunks,
    // leaves; never the ground, its grass or flowers), cut clean at that
    // distance.
    if (u.glory.y > 0.0 && kind != GROUND && kind != GROUND_FAR && kind != ASH && kind != GRASS_MESH
        && kind != GRASS && kind != FLOWER) {
        let near = distance(p, u.camPos.xyz) / u.glory.y;
        if (near < 1.0) {
            discard;
        }
    }
    if (kind == FLAME) {
        let c = vec3<f32>(3.2, 1.6, 0.5);
        let h = haze(c, p);
        out.color = encode(h.rgb, h.w);
        return out;
    }
    if (kind == VINE && overgrowth(p * 1.5) < 0.5) {
        discard;
    }
    var n = normalize(in.normal);
    let foliage = isFoliage(kind);
    if (kind == IVY_MESH && noise3(p * 9.0) < 0.28) {
        // Gaps between the leaves.
        discard;
    }
    if (kind == BUSH_PUFF || kind == CROWN_PUFF || kind == BUSH_MESH) {
        // A leafy silhouette: break up the clump's rim with noise, and give
        // its surface a lumpy, many-leaved normal.
        let size = select(max(in.params.z, 0.2), 0.6, kind == BUSH_MESH);
        let q = p * (7.0 / size) + vec3<f32>(u.windPhase.x * 0.15);
        let leafy = noise3(q) * 0.65 + noise3(q * 2.7) * 0.35;
        let rim = 1.0 - abs(dot(n, view));
        if (rim > 0.32 + leafy * 0.62) {
            discard;
        }
        let bump = vec3<f32>(noise3(q + 11.0), noise3(q + 23.0), noise3(q + 37.0)) - 0.5;
        n = normalize(n + bump * 1.4);
    }
    if (foliage && !front) {
        n = -n;
    }
    var albedo = materialAlbedo(kind, p, n, in.params, in.albedo);
    // Colour painted in Blender leads; the material adds its grain on top.
    if (in.paint.a > 0.5) {
        let grain = select(0.82 + 0.36 * noise3(p * 4.0), 0.7 + 0.6 * noise3(p * 3.0), foliage);
        albedo = in.paint.rgb * grain;
    }
    if (kind == MOSS && noise3(p * vec3<f32>(14.0, 1.5, 14.0)) < 0.35) {
        // Gaps between the hanging strands.
        discard;
    }
    var carveH = 0.5;
    if (kind == PILLAR) {
        // Carved relief: all but worn away in ruin, coming back as the
        // pillar is restored (its shape key, mode.w), crisp and gilded.
        let g = smoothstep(0.0, 1.0, u.mode.w);
        let cv = carving(in.local, normalize(in.localNormal));
        carveH = cv.h;
        let strength = mix(0.08, 1.0, g) * (0.7 + 0.3 * noise3(in.local * 3.0));
        n = normalize(n + cv.dir * strength);
        albedo *= mix(1.0, mix(0.6, 1.08, cv.h), strength);
        albedo = mix(albedo, vec3<f32>(0.95, 0.68, 0.25), g * 0.55 * smoothstep(0.72, 0.95, cv.h));
    }
    // Sun or shadow.
    let sh = sunShadow(p, n);

    // The toon ramp: shadow tint below 0.08 lit, full sun above 0.4.
    let sun = u.sunDir.xyz;
    var ndl = dot(n, sun);
    if (kind == GRASS || kind == FLOWER) {
        // Thin blades: lit mostly by how open they are to the sky.
        ndl = mix(ndl, 0.55, 0.6);
    }
    let lit = clamp(ndl * 0.5 + 0.5, 0.0, 1.0) * u.sunDir.w;
    let softness = u.shadowColor.w;
    let k = smoothstep(0.08 * 1.6, 0.4 * 1.6 + softness, lit) * sh;
    var light = mix(u.shadowColor.rgb, u.sunColor.rgb, k);
    // Sky fill from above (blue and lavender), warm ground bounce below.
    let sky = mix(u.hazeColor.rgb * vec3<f32>(1.05, 0.95, 0.8), mix(u.skyMid.rgb, u.skyTop.rgb, 0.7), n.y * 0.5 + 0.5);
    light += sky * u.sunColor.w;
    // Warm light bounced up from the sunlit ground into the shade.
    light += u.sunColor.rgb * vec3<f32>(1.0, 0.85, 0.6) * 0.2 * clamp(0.6 - n.y * 0.6, 0.0, 1.0) * u.sunDir.w;

    var c = albedo * light;

    // Leaves and grass glow when the sun shines through them.
    if (foliage) {
        let through = pow(max(dot(-view, sun), 0.0), 3.0);
        let back = max(-dot(n, sun), 0.0);
        c += albedo * vec3<f32>(1.25, 1.35, 0.55) * through * (0.4 + back) * u.mode.y * (0.25 + 0.75 * sh) * u.sunDir.w;
        // A soft sheen on their faces.
        let hlf = normalize(view + sun);
        c += u.sunColor.rgb * pow(max(dot(n, hlf), 0.0), 24.0) * 0.08 * sh * u.sunDir.w;
    }
    // A warm rim where surfaces turn away from the eye, toward the sun.
    let rim = pow(1.0 - max(dot(n, view), 0.0), 3.0) * max(dot(-view, sun) * 0.5 + 0.5, 0.0);
    // (All of these are the moon's: they fade with its light.)
    c += u.sunColor.rgb * rim * 0.24 * albedo * (0.3 + 0.7 * sh) * u.sunDir.w;
    // Ground occlusion: things darken toward the meadow.
    if (kind == STONE || kind == PILLAR || kind == ROCK || kind == CLAY) {
        c *= mix(0.6, 1.0, smoothstep(0.0, 0.7, p.y));
    }
    if (isStone(kind)) {
        // Glory: a warm sheen on the restored stone.
        let sheen = pow(1.0 - max(dot(n, view), 0.0), 2.0);
        c += vec3<f32>(1.0, 0.72, 0.36) * sheen * 0.25 * u.glory.x * albedo;
        // Restoring: the stone glows gold, brightest at its edges, and a
        // pillar's carving lights up as it comes back.
        c += vec3<f32>(1.3, 0.8, 0.3) * u.mode.z * (0.06 + sheen * 0.7);
        if (kind == PILLAR) {
            c += vec3<f32>(2.2, 1.35, 0.45) * u.mode.z * smoothstep(0.65, 0.95, carveH);
        }
    }
    // Fireflies light what is near them, warm yellow-green; leaves and
    // grass let it through from behind.
    // (Only near the camera: the fireflies that light anything are there.)
    var ff = 0.0;
    if (dot(p - u.camPos.xyz, p - u.camPos.xyz) < 900.0) {
        ff = fireflyLight(p, n, select(0.15, 0.55, foliage));
    }
    // And the ghost lights circling the hero tree light it in cool blue.
    let toHero = p.xz - u.hero.xz;
    if (u.heroB.x >= 1.0 && dot(toHero, toHero) < 196.0) {
        let gl = ghostLight(p, n, select(0.2, 0.6, foliage));
        c += (albedo * 1.8 + vec3<f32>(0.015)) * u.heroB.yzw * gl;
    }
    c += (albedo * 2.2 + vec3<f32>(0.02)) * u.pollenColor.rgb * ff;
    // The golden wave washes over everything it passes.
    let gw = blastLight(p);
    c += (albedo * 2.6 + vec3<f32>(0.015)) * u.blastColor.rgb * gw;
    // A warm pool of light round King Vikram.
    if (u.kingLight.w > 0.0) {
        let kd = u.kingLight.xyz - p;
        let k2 = dot(kd, kd);
        if (k2 < 64.0) {
            let wrap = max(dot(n, kd * inverseSqrt(max(k2, 1e-6))) * 0.5 + 0.5, 0.0);
            c += (albedo * 2.2 + vec3<f32>(0.006)) * u.kingLightColor.rgb * u.kingLight.w * exp(-k2 / 5.0) * wrap;
        }
    }

    let h = haze(c, p);
    out.color = encode(h.rgb, h.w);
    return out;
}

// ---------------------------------------------------------------------------
// Sky

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
    let dir = normalize(u.camFwd.xyz + u.camRight.xyz * in.ndc.x * u.camRight.w + u.camUp.xyz * in.ndc.y * u.camUp.w);
    // A pixel's height in elevation, to soften the ridgelines by.
    let aa = max(fwidth(dir.y) * 1.5, 0.0008);
    var c = skyColor(dir);
    // Stars: a jittered point in each cell of a grid on the sky, some
    // brighter and bluer, twinkling; fading into the mist at the horizon.
    if (dir.y > 0.0) {
        let sp = dir * 180.0;
        let cell = floor(sp);
        let jitter = vec3<f32>(hash3(cell), hash3(cell + 7.1), hash3(cell + 3.3));
        let d = length(sp - cell - jitter);
        let bright = hash3(cell + 11.7);
        // The Milky Way: a soft band across the sky, dusted with more stars.
        let band = exp(-pow(dot(dir, normalize(vec3<f32>(0.35, 0.55, 0.76))), 2.0) * 28.0);
        let dust = band * (fbm3(dir * 9.0) * 0.8 + 0.2);
        let lit = step(0.86 - 0.12 * band - 0.08 * (1.0 - moonAmount()), bright);
        let tw = 0.65 + 0.35 * sin(u.camPos.w * (1.5 + bright * 3.0) + bright * 50.0);
        let star = smoothstep(0.09 + bright * 0.06, 0.0, d) * lit * tw * smoothstep(0.02, 0.3, dir.y);
        c += mix(vec3<f32>(1.0, 0.92, 0.8), vec3<f32>(0.75, 0.85, 1.0), hash3(cell + 2.2)) * star * (0.8 + bright * 1.6);
        c += vec3<f32>(0.05, 0.06, 0.1) * dust * smoothstep(0.05, 0.35, dir.y) * (1.0 - moonAmount() * 0.7);
    }
    // The moon: a crisp disc with soft maria, a halo and a wide corona; none
    // at all on amavas.
    let md = dot(dir, u.sunDir.xyz);
    let moonR = 0.0115;
    let mAng = acos(clamp(md, -1.0, 1.0));
    if (mAng < moonR * 1.2 && moonAmount() > 0.0) {
        let local = (dir - u.sunDir.xyz * md) / moonR;
        let maria = noise3(local * 3.0 + vec3<f32>(0.0, 0.0, 1.0)) * 0.6 + noise3(local * 7.0 + vec3<f32>(0.0, 0.0, 2.0)) * 0.4;
        let disc = 1.0 - smoothstep(moonR * 0.92, moonR, mAng);
        c = mix(c, u.sunColor.rgb * mix(2.6, 3.4, smoothstep(0.35, 0.7, maria)), disc * moonAmount());
    }
    c += u.sunColor.rgb * (exp(-mAng * 22.0) * 0.35 + exp(-mAng * 5.0) * 0.12) * moonAmount();
    // Clouds: soft fbm on a high plane, drifting with the wind.
    if (dir.y > 0.0) {
        let plane = dir.xz / (dir.y + 0.08) * 1.6;
        let drift = vec2<f32>(u.wind.x, u.wind.y) * u.windPhase.z;
        let q = vec3<f32>(plane + drift, u.camPos.w * 0.01);
        let d = fbm3(q * 0.6);
        let d2 = fbm3(q * 1.7 + vec3<f32>(3.0, 1.0, 0.0));
        let amount = u.skyTop.w;
        let cover = smoothstep(0.62 - amount * 0.35, 0.95 - amount * 0.25, d * 0.75 + d2 * 0.35);
        let fade = smoothstep(0.0, 0.25, dir.y);
        // Night clouds: dark indigo bodies, silvered at their edges and
        // where they pass near the moon.
        let sd = max(dot(dir, u.sunDir.xyz), 0.0);
        let shade = mix(u.skyMid.rgb * 0.7, u.skyMid.rgb * 1.6 + u.sunColor.rgb * 0.06, smoothstep(0.35, 0.8, d2));
        let rim = smoothstep(0.55, 0.9, d) * (1.0 - smoothstep(0.9, 1.1, d));
        let cloud = shade + u.sunColor.rgb * (pow(sd, 6.0) * 0.6 + rim * (0.1 + pow(sd, 2.0) * 0.6));
        c = mix(c, cloud, cover * fade * 0.8);
    }
    c = mountains(dir, c, aa);
    out.color = vec4<f32>(sqrt(c / (1.0 + c)), 0.85);
    return out;
}

// Distant hills, painted into the sky: three ranges of soft, rounded
// silhouettes, the nearest darkest and tallest, the farthest pale and lost
// in the haze. They wrap all the way round (noise sampled on a circle), sit
// in front of the clouds, and fade into the haze at their feet.
fn ridge(az: f32, layer: f32, scale: f32) -> f32 {
    let ring = vec2<f32>(cos(az), sin(az));
    let a = noise3(vec3<f32>(ring * scale, layer * 7.3));
    let b = noise3(vec3<f32>(ring * scale * 2.7, layer * 7.3 + 3.1));
    // Rounded: broad swells with a gentle wobble, no sharp peaks.
    let swell = smoothstep(0.0, 1.0, a);
    return swell * 0.75 + b * 0.25;
}

fn mountains(dir: vec3<f32>, sky: vec3<f32>, edge: f32) -> vec3<f32> {
    let height = u.skyMid.w;
    if (height <= 0.0 || dir.y > 0.2 * height + 0.02) {
        return sky;
    }
    let az = atan2(dir.z, dir.x);
    let elev = dir.y;
    let horizonHaze = mix(u.hazeColor.rgb, u.skyHorizon.rgb, 0.5);
    let toSun = max(dot(normalize(vec3<f32>(dir.x, 0.0, dir.z)), normalize(vec3<f32>(u.sunDir.x, 0.0, u.sunDir.z))), 0.0);
    var c = sky;
    // Far to near: (base elevation, peak height, noise scale, haze).
    for (var i = 0; i < 3; i++) {
        let fi = f32(i);
        let base = -0.004 + fi * 0.004;
        let peak = (0.03 + fi * 0.015) * height;
        let top = base + peak * ridge(az, fi, 1.4 + fi * 0.9);
        let inside = 1.0 - smoothstep(top - edge, top + edge, elev);
        if (inside <= 0.0) {
            continue;
        }
        // Each range is the near colour, lost into the haze with distance,
        // lighter toward its feet, warmed on the side toward the sun.
        let haze = 0.84 - fi * 0.22;
        var col = mix(u.mountain.rgb, horizonHaze, haze);
        let depth = clamp((top - elev) / max(peak, 1e-3), 0.0, 1.0);
        col = mix(col, horizonHaze, smoothstep(0.35, 1.0, depth) * 0.35);
        col += u.sunColor.rgb * pow(toSun, 3.0) * 0.12 * (1.0 - haze);
        c = mix(c, col, inside);
    }
    // The sun's glow still hangs over them.
    let sd = max(dot(dir, u.sunDir.xyz), 0.0);
    c += u.sunColor.rgb * pow(sd, 10.0) * 0.25;
    return c;
}

// ---------------------------------------------------------------------------
// Pollen: each instance is a mote in a box around the ruins, drifting
// downwind and floating in slow loops; one in a few is a pink petal that
// tumbles. Drawn as camera-facing discs that soften (bokeh) away from the
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
    // Each instance's index, from a buffer (instance_index is not portable).
    let id = mote;
    let r1 = hash1(id * 1.13 + 0.5);
    let r2 = hash1(id * 2.71 + 1.7);
    let r3 = hash1(id * 3.37 + 4.1);
    let r4 = hash1(id * 5.19 + 2.3);
    let t = u.camPos.w;
    let size = vec3<f32>(20.0, 4.5, 18.0);
    let speed = u.pollen.z;
    // Fireflies wander: slow, looping, searching flights low over the
    // ground, barely pushed by the wind.
    let drift = vec3<f32>(u.wind.x, 0.0, u.wind.y) * u.windPhase.x * 0.03 * (0.5 + r4);
    let loops = vec3<f32>(
        sin(t * 0.31 * speed + r1 * 30.0) * 1.4 + sin(t * 0.83 * speed + r3 * 11.0) * 0.35,
        sin(t * 0.43 * speed + r2 * 20.0) * 0.45 + sin(t * 1.1 * speed + r4 * 9.0) * 0.12,
        cos(t * 0.27 * speed + r3 * 25.0) * 1.4 + cos(t * 0.71 * speed + r1 * 13.0) * 0.35);
    var p = vec3<f32>(r1, r2, r3) * size + drift + loops;
    // Wrap within the box around its centre.
    let lo = u.pollenBox.xyz - size * vec3<f32>(0.5, 0.0, 0.5);
    p = lo + ((p % size) + size) % size;
    // Mostly knee to head height, a few higher in the trees.
    p.y = lo.y + 0.25 + (p.y - lo.y) * (0.12 + 0.55 * r2 * r2 * r2);
    // The first few are the ones that light the scene: they fly where the
    // script says, and glow as it says.
    // A share of them gather round the hero tree, from its roots up into
    // its canopy, in looser loops.
    let r5 = hash1(id * 7.73 + 3.1);
    if (r5 < u.hero.w) {
        let a = r1 * 6.283;
        let rad = 1.5 + r3 * 5.5;
        let h = 0.4 + r2 * r2 * 6.5;
        p = u.hero.xyz + vec3<f32>(cos(a) * rad, h, sin(a) * rad) + loops * 0.7;
    }
    let lit = u32(id) < FIREFLY_LIGHTS;
    if (lit) {
        p = u.fireflyLights[u32(id)].xyz;
    }
    // Ghost lights: a head and its trail, circling the hero tree.
    let ghost = id >= GHOST_BASE;
    var gi = 0u;
    var gk = 0.0;
    if (ghost) {
        let gid = u32(id - GHOST_BASE);
        gi = gid / GHOST_TRAIL;
        gk = f32(gid % GHOST_TRAIL);
        p = ghostPos(gi, t - gk * 0.16);
    }

    let petal = select(0.0, 1.0, r4 < u.petals.x && !ghost);
    var radius = u.pollen.y * (0.5 + r3 * r3 * 1.2);
    if (ghost) {
        radius = 0.24 * (1.0 - gk * 0.2);
    }
    if (petal > 0.5) {
        radius = u.petals.y * (0.7 + 0.6 * r1);
    }
    let toP = p - u.camPos.xyz;
    let dist = length(toP);
    // Circle of confusion, in world units at the mote: a lens's blur is
    // |1/d - 1/focus| in angle, so d times that here.
    let focus = u.camFwd.w;
    let coc = abs(1.0 - dist / focus) * u.pollenBox.w * 0.012;
    let grown = radius + coc;
    // Corners of the quad, facing the camera.
    let corner = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    var c = corner[vi];
    var stretch = vec2<f32>(1.0, 1.0);
    if (petal > 0.5) {
        // Petals tumble: an ellipse that turns and flips.
        let a = t * (0.8 + r2) * speed + r1 * 6.28;
        let flip = 0.35 + 0.65 * abs(sin(t * (0.6 + r3) * speed + r2 * 6.28));
        let cs = cos(a);
        let sn = sin(a);
        c = vec2<f32>(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
        stretch = vec2<f32>(1.0, flip);
    }
    let right = u.camRight.xyz;
    let up = u.camUp.xyz;
    let world = p + (right * c.x + up * c.y) * grown;
    out.clip = u.viewProj * vec4<f32>(world, 1.0);
    out.uv = corner[vi] / stretch;
    // Fade the ones right at the lens and at the edges of the box.
    let near = smoothstep(0.25, 0.9, dist);
    let edge = smoothstep(0.0, 1.5, min(min(p.x - lo.x, lo.x + size.x - p.x), min(p.z - lo.z, lo.z + size.z - p.z)));
    // Each blinks on its own rhythm: a slow swell to a bright glow, a pause
    // in the dark, now and then a quick double flash.
    let beat = t * (0.35 + r2 * 0.45) * (0.7 + 0.3 * speed) + r1 * 37.0;
    var pulse = pow(max(sin(beat), 0.0), 3.0) + 0.6 * pow(max(sin(beat * 2.7 + r3 * 5.0), 0.0), 12.0) * step(0.6, r4);
    if (lit) {
        pulse = u.fireflyLights[u32(id)].w;
    }
    if (ghost) {
        pulse = ghostFlicker(gi, t) * pow(1.0 - gk * 0.24, 2.0);
    }
    let twinkle = 0.06 + pulse;
    // Spread over the bigger disc, the same light is fainter.
    let spread = (radius * radius) / (grown * grown);
    // Warm yellow-green, a few more golden; bright enough to bloom.
    var tint = mix(u.pollenColor.rgb, vec3<f32>(1.0, 0.82, 0.3), select(0.0, 0.6, r3 > 0.8)) * (1.1 + 0.9 * pulse);
    // Hazed like everything else (the mist softens the far ones).
    if (ghost) {
        tint = u.heroB.yzw * (2.4 + 1.2 * pulse);
    }
    let hz = haze(tint, p);
    var count = clamp(u.pollen.x - id, 0.0, 1.0);
    var fade = edge;
    if (ghost) {
        count = 1.0;
        fade = 1.0;
    } else if (r5 < u.hero.w) {
        fade = 1.0;
    }
    out.tint = vec4<f32>(hz.rgb, u.pollenColor.w * near * fade * twinkle * mix(0.35, 1.0, spread) * count);
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
    // A bright core with a soft glow; out of focus, an even disc with a
    // brighter rim, like a lens's bokeh.
    let soft = clamp(in.shape.x, 0.0, 1.0);
    let core = exp(-r * r * 9.0);
    let glow = (1.0 - smoothstep(0.2, 1.0, r)) * 0.45;
    let bokeh = (1.0 - smoothstep(0.82, 1.0, r)) * (0.55 + 0.45 * smoothstep(0.5, 0.95, r));
    var a = mix(core + glow * u.pollen.w, bokeh * 0.6, soft);
    if (in.shape.y > 0.5) {
        a = mix(1.0 - smoothstep(0.75, 1.0, r), bokeh * 0.6, soft);
    }
    a *= in.tint.a;
    let c = in.tint.rgb * (1.0 + u.pollen.w * core * 2.5);
    // Premultiplied; the alpha channel (depth of field) is left alone.
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a);
    return out;
}
