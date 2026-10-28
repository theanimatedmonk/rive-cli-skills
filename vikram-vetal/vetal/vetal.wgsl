// The Vetal, drawn as King Vikram is (king.wgsl): a painting that happens
// to be 3D, in the night scene's look. His uniforms and stage (the ground,
// the sky, the fireflies) are king.wgsl's, so his page is King's page.
//
//   vs_vetal / fs_vetal      the body: skinned on the GPU from the bones
//                            (Spirit.luau plays his loop), painted by
//                            vertex with a brush's grain, lit in flat toon
//                            bands by the moon and a fire's glow, shadows
//                            tinted rather than black, a hard rim of
//                            moonlight, ink where the paint changes colour,
//                            hatching in the deepest shadow; a cold spirit
//                            light at his edges, and his eyes burning.
//   vs_vetal_outline /       the ink outline: the body again, pushed out
//   fs_outline               along its normals and drawn inside out.
//   vs_vetal_shadow          the body seen from the moon, for its shadow.
//   vs_ground / fs_ground    the earth under him; vs_sky / fs_sky the night
//   vs_motes / fs_motes      sky; fireflies drifting round him.
//
// He hangs upside down from the origin (the point on the branch). His eyes'
// glow is in the earColor slot (rgb, strength), the spirit light in aura.x
// and auraColor; the wind in windA / windB, as Vikram's.
//
// Colour is written as sqrt(c / (1 + c)), with the depth-of-field blur in
// alpha, for blur.wgsl and post.wgsl.

const JOINTS = 80;

struct Uniforms {
    viewProj: mat4x4<f32>,
    lightViewProj: mat4x4<f32>,
    camPos: vec4<f32>,       // xyz, time
    moonDir: vec4<f32>,      // toward the moon, its light
    moonColor: vec4<f32>,    // rgb, rim strength
    fireDir: vec4<f32>,      // toward the fire, its light (flickering)
    fireColor: vec4<f32>,    // rgb, 0
    shadowTint: vec4<f32>,   // what shadow is painted in, ambient
    ink: vec4<f32>,          // rgb, outline width (pixels)
    style: vec4<f32>,        // paint, bands, ink detail, hatching
    viewport: vec4<f32>,     // width, height, 1/width, 1/height
    skyTop: vec4<f32>,       // rgb, stars
    skyLow: vec4<f32>,       // rgb, moon (0-1)
    mist: vec4<f32>,         // rgb, density
    model: mat4x4<f32>,      // his turn
    camRight: vec4<f32>,     // xyz, tan of half the horizontal fov
    camUp: vec4<f32>,        // xyz, tan of half the vertical fov
    camFwd: vec4<f32>,       // xyz, focus distance
    motes: vec4<f32>,        // count, size, depth of field, 0
    moteColor: vec4<f32>,    // rgb, 0
    ground: vec4<f32>,       // scroll x, scroll z, 0, 0
    eyeL: vec4<f32>,         // the eyes' centres (bind pose), 0
    eyeR: vec4<f32>,         // ..., how much they are brought out (0-1)
    irisL: vec4<f32>,        // the irises' centres (bind pose)
    irisR: vec4<f32>,
    earL: vec4<f32>,         // the earrings' gems (world), glow
    earR: vec4<f32>,         // ..., shimmer
    earColor: vec4<f32>,     // their glow (linear), 0
    lid: vec4<f32>,          // the eyelids' colour (linear), blink (0 open, 1 shut)
    aura: vec4<f32>,         // the bow's aura (0-1+), the string's shape key, release (0-1), flash
    auraColor: vec4<f32>,    // its colour (linear), how much aura (0-2)
    bowOrigin: vec4<f32>,    // the limbs' axis (bind pose): its start, length
    bowAxis: vec4<f32>,      // ..., its direction, 0
    spine: array<vec4<f32>, 14>,   // along the bow (world), tip to tip, then the nock
    windA: vec4<f32>,        // the wind: its direction (x, z), strength, phase
    windB: vec4<f32>,        // how much the hair and the cloth take it, gustiness
    bones: array<vec4<f32>, 240>,  // per joint, the skin matrix's rows
};

@group(0) @binding(0) var<uniform> u: Uniforms;

struct FragOut {
    @location(0) color: vec4<f32>,
};

fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
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

fn encode(c: vec3<f32>, blur: f32) -> vec4<f32> {
    let m = max(c, vec3<f32>(0.0));
    return vec4<f32>(sqrt(m / (1.0 + m)), blur);
}

// How out of focus a point is, by its distance from the focus.
fn defocus(p: vec3<f32>) -> f32 {
    let d = dot(p - u.camPos.xyz, u.camFwd.xyz);
    return clamp(abs(1.0 - d / u.camFwd.w) * 0.9, 0.0, 1.0);
}

// The mist: thicker with distance and near the ground.
fn misty(c: vec3<f32>, p: vec3<f32>) -> vec3<f32> {
    let d = length(p - u.camPos.xyz);
    let low = exp(-max(p.y, 0.0) * 1.2);
    let wisps = 0.6 + 0.8 * noise3(p * 0.35 + vec3<f32>(u.camPos.w * 0.05, 0.0, u.camPos.w * 0.03));
    let k = 1.0 - exp(-d * u.mist.w * (0.012 + 0.05 * low * wisps));
    return mix(c, u.mist.rgb, clamp(k, 0.0, 1.0));
}

// ---------------------------------------------------------------------------
// Skinning

struct SkinIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec4<f32>,
    // Painted in Blender (sRGB); a = what it is: 0 body, 0.5 hair, 1 eyes.
    @location(2) color: vec4<f32>,
    @location(3) joints: vec4<u32>,
    @location(4) weights: vec4<f32>,
    // The wind painted on him: how much it sways, its phase, what it is / 4
    // (0 still, 1 hair, 2 and 4 cloth).
    @location(5) wind: vec4<f32>,
};

struct Skinned {
    world: vec3<f32>,
    normal: vec3<f32>,
};

// His hair and cloth in the wind (world metres). His hair streams out along
// it, not at all at the roots (they stay on his head) and more and more
// toward the tips (the painted sway runs from the roots to them),
// a ripple running down each strand and a flutter across it, the tips
// lifting; the strands move together (the painted phase only nudges each).
// His cloth flows the same way, heavier: streaming out more toward its free
// edges, rippling, and fluttering faster.
fn windSway(w: vec4<f32>) -> vec3<f32> {
    if (w.x <= 0.0 || u.windA.z <= 0.0) {
        return vec3<f32>(0.0);
    }
    let what = round(w.z * 4.0);
    if (what > 0.5 && what < 1.5) {
        let t = u.windA.w;
        let along = clamp((w.x - 0.3) / 0.7, 0.0, 1.0);
        let gust = 1.0 - u.windB.z * 0.45 * (1.0 + sin(t * 0.43 + 1.3) * sin(t * 0.17));
        let strength = pow(u.windA.z, 0.75) * u.windB.x;
        let dir = vec3<f32>(u.windA.x, 0.0, u.windA.y);
        let side = vec3<f32>(-u.windA.y, 0.0, u.windA.x);
        let nudge = w.y * 0.6;
        let stream = 0.4 * pow(along, 1.5) * (0.7 + 0.3 * sin(t * 1.6 - along * 3.2 + nudge)) * gust;
        let flutter = sin(t * 2.8 - along * 4.5 + nudge) * 0.07 * along;
        let lift = 0.07 * along * along;
        return (dir * stream + side * flutter + vec3<f32>(0.0, lift, 0.0)) * strength;
    }
    if (what > 1.5) {
        let t = u.windA.w;
        let along = clamp(w.x, 0.0, 1.0);
        let gust = 1.0 - u.windB.z * 0.45 * (1.0 + sin(t * 0.43 + 1.3) * sin(t * 0.17));
        let strength = pow(u.windA.z, 0.75) * u.windB.y;
        let dir = vec3<f32>(u.windA.x, 0.0, u.windA.y);
        let side = vec3<f32>(-u.windA.y, 0.0, u.windA.x);
        let nudge = w.y * 0.6;
        let stream = 0.12 * pow(along, 1.5) * (0.7 + 0.3 * sin(t * 1.9 - along * 3.0 + nudge)) * gust;
        let flutter = sin(t * 4.2 - along * 5.0 + nudge) * 0.03 * along;
        let lift = 0.02 * along * along;
        return (dir * stream + side * flutter + vec3<f32>(0.0, lift, 0.0)) * strength;
    }
    let take = select(u.windB.y, u.windB.x, what > 0.5 && what < 1.5) * select(1.0, 0.0, what < 0.5);
    let t = u.windA.w;
    let ph = w.y * 6.283;
    let gust = 1.0 - u.windB.z * 0.5 * (1.0 + sin(t * 0.43 + 1.3) * sin(t * 0.17));
    let sway = 0.6 + 0.4 * sin(t * 1.7 + ph);
    let flutter = sin(t * select(4.0, 9.0, what > 1.5) + ph * 3.0);
    let dir = vec3<f32>(u.windA.x, 0.0, u.windA.y);
    let side = vec3<f32>(-u.windA.y, 0.0, u.windA.x);
    let strength = pow(u.windA.z, 0.7);
    return (dir * sway * gust + side * flutter * 0.35 + vec3<f32>(0.0, flutter * 0.12, 0.0))
        * w.x * take * strength * 0.08;
}

fn skin(v: SkinIn) -> Skinned {
    var r0 = vec4<f32>(0.0);
    var r1 = vec4<f32>(0.0);
    var r2 = vec4<f32>(0.0);
    for (var k = 0; k < 4; k++) {
        let w = v.weights[k];
        let j = min(v.joints[k], u32(JOINTS - 1)) * 3u;
        r0 += u.bones[j] * w;
        r1 += u.bones[j + 1u] * w;
        r2 += u.bones[j + 2u] * w;
    }
    let p = vec4<f32>(v.position, 1.0);
    let local = vec3<f32>(dot(r0, p), dot(r1, p), dot(r2, p));
    let n = vec4<f32>(v.normal.xyz, 0.0);
    let ln = vec3<f32>(dot(r0, n), dot(r1, n), dot(r2, n));
    var s: Skinned;
    s.world = (u.model * vec4<f32>(local, 1.0)).xyz + windSway(v.wind);
    s.normal = normalize((u.model * vec4<f32>(ln, 0.0)).xyz);
    return s;
}

struct VetalOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) color: vec4<f32>,
    @location(3) rest: vec3<f32>,
};

@vertex
fn vs_vetal(v: SkinIn) -> VetalOut {
    let s = skin(v);
    var out: VetalOut;
    out.clip = u.viewProj * vec4<f32>(s.world, 1.0);
    out.world = s.world;
    out.normal = s.normal;
    out.color = v.color;
    out.rest = v.position;
    return out;
}

@vertex
fn vs_vetal_shadow(v: SkinIn) -> @builtin(position) vec4<f32> {
    let s = skin(v);
    return u.lightViewProj * vec4<f32>(s.world, 1.0);
}

@group(0) @binding(1) var shadowMap: texture_depth_2d;
@group(0) @binding(2) var shadowSmp: sampler_comparison;
// (King's texture bindings, unused here: a stage written for king.wgsl may
// bind them.)
@group(0) @binding(3) var colorTex: texture_2d<f32>;
@group(0) @binding(4) var normalTex: texture_2d<f32>;
@group(0) @binding(5) var rmTex: texture_2d<f32>;
@group(0) @binding(6) var texSmp: sampler;

// The moon's shadow (1 lit, 0 shadowed), softened over a few taps.
fn moonShadow(p: vec3<f32>, n: vec3<f32>) -> f32 {
    let q = u.lightViewProj * vec4<f32>(p + n * 0.02, 1.0);
    let uv = vec2<f32>(q.x * 0.5 + 0.5, 0.5 - q.y * 0.5);
    let depth = q.z - 0.0015;
    let texel = 1.0 / 1024.0;
    var lit = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            lit += textureSampleCompareLevel(shadowMap, shadowSmp, uv + vec2<f32>(f32(x), f32(y)) * texel * 1.5, depth);
        }
    }
    let inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return mix(1.0, lit / 9.0, inside);
}

// Light in bands: 0 is smooth, 1 flat steps with a soft brush edge.
fn bands(x: f32, count: f32, paint: f32) -> f32 {
    let s = clamp(x, 0.0, 1.0);
    let f = s * count;
    let step0 = floor(f);
    let edge = smoothstep(0.5 - 0.06, 0.5 + 0.06, fract(f) - 0.0);
    let q = (step0 + edge) / count;
    return mix(s, q, paint);
}

// Where his eyes are, in his bind pose (hanging from the origin).
const EYES = vec3<f32>(0.0, -1.275, 0.396);

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@fragment
fn fs_vetal(in: VetalOut, @builtin(front_facing) front: bool) -> FragOut {
    var out: FragOut;
    let paint = u.style.x;
    let p = in.world;
    let part = in.color.a;
    // The painted colour, with a brush's grain so the flat vertex colour
    // reads as paint; ink where the painting turns sharply.
    var albedo = pow(in.color.rgb, vec3<f32>(2.2));
    let lumEdge = fwidth(luma(in.color.rgb));
    let grain = 0.86 + 0.28 * noise3(in.rest * 14.0) + 0.1 * (noise3(in.rest * 41.0) - 0.5);
    albedo *= mix(1.0, grain, paint);

    var n = normalize(in.normal);
    if (!front) {
        n = -n;
    }
    let view = normalize(u.camPos.xyz - p);

    // The moon: cool light from above and behind, with real shadow; the
    // fire: warm, low and in front, flickering.
    let L = u.moonDir.xyz;
    let shadow = moonShadow(p, n);
    let moonN = max(dot(n, L), 0.0) * shadow;
    let moonBand = bands(moonN * 1.15, u.style.y, paint);
    let F = u.fireDir.xyz;
    let fireN = max(dot(n, F) * 0.9 + 0.1, 0.0);
    let fireBand = bands(fireN, u.style.y, paint);

    // Shadow is painted in a colour, not black.
    let ambient = u.shadowTint.rgb * u.shadowTint.w * (0.6 + 0.4 * max(-n.y, 0.0) + 0.2 * max(n.y, 0.0));
    let light = ambient
        + u.moonColor.rgb * u.moonDir.w * moonBand
        + u.fireColor.rgb * u.fireDir.w * fireBand;
    var c = albedo * light;

    // His eyes' smoulder on his face round them (measured in his bind pose,
    // where the eyes are: tools/export_vetal.py).
    let eyes = u.earColor.w;
    let toEye = in.rest - EYES;
    let ed = dot(toEye, toEye);
    c += albedo * u.earColor.rgb * eyes * 0.6 * exp(-ed / 0.006);

    // Moonlight on the rim: a hard line in the painting, a soft sheen in 3D.
    let fres = 1.0 - max(dot(n, view), 0.0);
    let facing = clamp(dot(n, L) * 0.6 + 0.5, 0.0, 1.0);
    let rim = mix(pow(fres, 3.0), smoothstep(0.55, 0.61, fres), paint) * facing * u.moonColor.w;
    c += u.moonColor.rgb * rim * (0.5 + u.moonDir.w * 3.0) * (0.4 + 0.6 * shadow);

    // The spirit: a pale light clinging to all of him, brightest at his
    // edges and breathing (the halo, vs_vetal_glow, carries it past them).
    let breath = 0.75 + 0.25 * sin(u.camPos.w * 1.3 + in.rest.y * 3.0);
    let cling = pow(fres, 2.0) * (0.6 + 0.4 * breath) + 0.12;
    c += u.auraColor.rgb * u.aura.x * cling * select(0.45, 0.8, part > 0.25 && part < 0.75);

    // Hatching in the deepest shadow: fine diagonal strokes in screen space.
    let unlit = 1.0 - clamp(moonBand + fireBand * u.fireDir.w * 0.6, 0.0, 1.0);
    let sp = in.clip.xy / max(u.viewport.y / 720.0, 0.5);
    let stroke = sin((sp.x + sp.y) * 0.9 + noise3(vec3<f32>(sp * 0.05, 0.0)) * 4.0);
    let hatch = smoothstep(0.55, 0.85, stroke) * smoothstep(0.55, 0.95, unlit) * u.style.w * paint;
    c *= 1.0 - hatch * 0.55;
    // Ink where the paint changes colour.
    let inkLine = smoothstep(0.04, 0.14, lumEdge) * u.style.z * paint;
    c = mix(c, u.ink.rgb, inkLine * 0.8);

    // The eyes burn.
    if (part > 0.75) {
        let flick = 0.85 + 0.15 * sin(u.camPos.w * 9.0 + in.rest.x * 40.0);
        c = u.earColor.rgb * eyes * flick * (1.3 + 1.2 * (1.0 - fres)) + vec3<f32>(1.0, 0.55, 0.3) * eyes * 0.35 * (1.0 - fres);
    }

    if (u.aura.w > 0.0) {
        c = min(c, vec3<f32>(u.aura.w));
    }
    out.color = encode(misty(c, p), defocus(p) * u.motes.z);
    return out;
}

// ---------------------------------------------------------------------------
// The aura: his body again, drawn as nested layers swollen along its
// normals out to aura.y metres (aura.z layers, one instance each), each
// fainter than the one inside, added over the scene. Each layer glows where
// it turns away from the eye, so together they make a soft white light that
// hugs his silhouette and falls off into the night, broken into wisps that
// drift upward like smoke, and breathing.

struct GlowOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) layer: f32,
};

// The smooth normal (tools/export_vetal.py), from its octahedral encoding.
fn smoothNormal(v: SkinIn) -> vec3<f32> {
    let e = vec2<f32>(v.normal.w, v.wind.w * 2.0 - 1.0);
    var n = vec3<f32>(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
    if (n.y < 0.0) {
        n = vec3<f32>((1.0 - abs(n.z)) * sign(n.x), n.y, (1.0 - abs(n.x)) * sign(n.z));
    }
    return normalize(n);
}

@vertex
fn vs_vetal_glow(v: SkinIn, @location(6) layer: f32) -> GlowOut {
    let s = skin(v);
    var out: GlowOut;
    let k = (layer + 1.0) / max(u.aura.z, 1.0);
    // Swollen along the smooth normal, so the layers stay closed across the
    // mesh's hard edges; thin hair cards swell less.
    var r0 = vec4<f32>(0.0);
    var r1 = vec4<f32>(0.0);
    var r2 = vec4<f32>(0.0);
    for (var j = 0; j < 4; j++) {
        let w = v.weights[j];
        let b = min(v.joints[j], u32(JOINTS - 1)) * 3u;
        r0 += u.bones[b] * w;
        r1 += u.bones[b + 1u] * w;
        r2 += u.bones[b + 2u] * w;
    }
    let sn = vec4<f32>(smoothNormal(v), 0.0);
    let n = normalize((u.model * vec4<f32>(dot(r0, sn), dot(r1, sn), dot(r2, sn), 0.0)).xyz);
    let reach = u.aura.y * k * select(1.0, 0.6, v.color.a > 0.25);
    let p = s.world + n * reach;
    out.clip = u.viewProj * vec4<f32>(p, 1.0);
    out.world = p;
    out.normal = n;
    out.layer = k;
    return out;
}

@fragment
fn fs_vetal_glow(in: GlowOut) -> FragOut {
    var out: FragOut;
    let t = u.camPos.w;
    let view = normalize(u.camPos.xyz - in.world);
    let edge = 1.0 - abs(dot(normalize(in.normal), view));
    // Fainter the further out. Each layer is brightest just inside its own
    // silhouette and fades to nothing at it, so no layer ends in an edge
    // and together they fall off smoothly.
    let falloff = (1.0 - in.layer) * (1.0 - in.layer);
    let rim = smoothstep(0.05, 0.6, edge) * (1.0 - smoothstep(0.6, 0.98, edge));
    // Wisps rising through it, and a slow breath.
    let q = in.world * 5.0 - vec3<f32>(0.0, t * 0.7, 0.0);
    let wisp = 0.45 + 1.1 * noise3(q) * (0.6 + 0.4 * noise3(q * 2.3 + vec3<f32>(3.1)));
    let breath = 0.8 + 0.2 * sin(t * 1.3);
    let a = clamp(rim * falloff * wisp * breath * u.aura.x * 0.15, 0.0, 1.0);
    var c = u.auraColor.rgb * 2.2;
    if (u.aura.w > 0.0) {
        // Under the host's ceiling, and thinner, so what it adds stays
        // under it too.
        c = min(c, vec3<f32>(u.aura.w));
    }
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a * 0.15);
    return out;
}

// ---------------------------------------------------------------------------
// The outline

struct OutlineOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
};

@vertex
fn vs_vetal_outline(v: SkinIn) -> OutlineOut {
    let s = skin(v);
    var out: OutlineOut;
    if (v.color.a > 0.25) {
        // His hair (thin cards) and his eyes take no ink.
        out.clip = vec4<f32>(0.0, 0.0, 0.0, 1.0);
        out.world = s.world;
        return out;
    }
    var clip = u.viewProj * vec4<f32>(s.world, 1.0);
    let nc = (u.viewProj * vec4<f32>(s.normal, 0.0)).xy;
    let len = length(nc);
    if (len > 1e-5) {
        // A brush's wavering width: thicker and thinner along the stroke.
        let wobble = 0.65 + 0.7 * noise3(s.world * 9.0);
        let px = u.ink.w * wobble;
        clip = vec4<f32>(clip.xy + nc / len * px * 2.0 * u.viewport.zw * clip.w, clip.z, clip.w);
    }
    out.clip = clip;
    out.world = s.world;
    return out;
}

@fragment
fn fs_outline(in: OutlineOut) -> FragOut {
    var out: FragOut;
    out.color = encode(misty(u.ink.rgb, in.world), defocus(in.world) * u.motes.z);
    return out;
}

// ---------------------------------------------------------------------------
// The ground

struct GroundOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
};

const GROUND_SIZE = 40.0;

@vertex
fn vs_ground(@builtin(vertex_index) vi: u32) -> GroundOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    let c = corners[vi] * GROUND_SIZE;
    var out: GroundOut;
    out.world = vec3<f32>(c.x, 0.0, c.y);
    out.clip = u.viewProj * vec4<f32>(out.world, 1.0);
    return out;
}

fn groundShadowAt(p: vec3<f32>) -> f32 {
    let q = u.lightViewProj * vec4<f32>(p, 1.0);
    let uv = vec2<f32>(q.x * 0.5 + 0.5, 0.5 - q.y * 0.5);
    let depth = q.z - 0.002;
    let texel = 1.0 / 1024.0;
    var lit = 0.0;
    for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
            lit += textureSampleCompareLevel(shadowMap, shadowSmp, uv + vec2<f32>(f32(x), f32(y)) * texel * 1.6, depth);
        }
    }
    let inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return mix(1.0, lit / 25.0, inside);
}

@fragment
fn fs_ground(in: GroundOut) -> FragOut {
    var out: FragOut;
    let paint = u.style.x;
    let p = in.world;
    // The earth, scrolled under his feet as he walks.
    let q = vec3<f32>(p.x + u.ground.x, 0.0, p.z + u.ground.y);
    let big = fbm3(q * 0.45);
    let small = noise3(q * 3.1);
    var albedo = mix(vec3<f32>(0.035, 0.028, 0.022), vec3<f32>(0.075, 0.06, 0.045), big);
    // Ash and pale dust in patches; dark cracks.
    albedo = mix(albedo, vec3<f32>(0.11, 0.105, 0.1), smoothstep(0.55, 0.7, fbm3(q * 0.8 + 5.0)) * 0.6);
    // Fine dark cracks, broken up so they never run on as contours.
    let crack = (1.0 - smoothstep(0.0, 0.025, abs(noise3(q * 2.3 + 2.0) - 0.5))) * smoothstep(0.45, 0.65, noise3(q * 0.9 + 7.0));
    albedo *= 1.0 - crack * 0.4 * (0.4 + 0.6 * paint);
    albedo *= 0.85 + 0.3 * small;
    // Dry tufts of grass, as painted flecks.
    let tuft = smoothstep(0.72, 0.8, noise3(q * 7.0) * 0.6 + big * 0.5);
    albedo = mix(albedo, vec3<f32>(0.09, 0.085, 0.035), tuft * 0.8);

    let shadow = groundShadowAt(p);
    let moon = bands(max(u.moonDir.y, 0.0) * shadow, u.style.y, paint);
    // The fire's glow pools on the ground on its side, flickering.
    let toFire = normalize(vec2<f32>(u.fireDir.x, u.fireDir.z));
    let along = dot(p.xz, toFire);
    let pool = exp(-length(p.xz - toFire * 3.2) * 0.45) * (0.5 + 0.5 * smoothstep(-2.0, 2.0, along));
    let fire = bands(pool, u.style.y, paint) * u.fireDir.w;
    let ambient = u.shadowTint.rgb * u.shadowTint.w;
    var c = albedo * (ambient + u.moonColor.rgb * u.moonDir.w * moon + u.fireColor.rgb * fire * 1.6);
    // Contact shadow, so he stands on the ground even with no moon.
    let r = length(p.xz / vec2<f32>(0.55, 0.38));
    c *= mix(0.35, 1.0, smoothstep(0.2, 1.1, r));
    out.color = encode(misty(c, p), defocus(p) * u.motes.z);
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
    let dir = normalize(u.camFwd.xyz + u.camRight.xyz * in.ndc.x * u.camRight.w + u.camUp.xyz * in.ndc.y * u.camUp.w);
    let h = clamp(dir.y, -0.2, 1.0);
    var c = mix(u.skyLow.rgb, u.skyTop.rgb, smoothstep(-0.05, 0.5, h));
    // Stars, twinkling, fading into the mist low down.
    if (dir.y > 0.0) {
        let sp = dir * 160.0;
        let cell = floor(sp);
        let jitter = vec3<f32>(hash3(cell), hash3(cell + 7.1), hash3(cell + 3.3));
        let d = length(sp - cell - jitter);
        let bright = hash3(cell + 11.7);
        let lit = step(0.84, bright);
        let tw = 0.65 + 0.35 * sin(u.camPos.w * (1.5 + bright * 3.0) + bright * 50.0);
        let star = smoothstep(0.09 + bright * 0.06, 0.0, d) * lit * tw * smoothstep(0.03, 0.3, dir.y);
        c += mix(vec3<f32>(1.0, 0.92, 0.8), vec3<f32>(0.75, 0.85, 1.0), hash3(cell + 2.2)) * star * (0.6 + bright * 1.4) * u.skyTop.w;
    }
    // The moon's glow, wide and faint, where it hangs.
    let md = max(dot(dir, u.moonDir.xyz), 0.0);
    c += u.moonColor.rgb * (pow(md, 40.0) * 0.5 + pow(md, 6.0) * 0.12) * u.skyLow.w;
    // Mist low down, drifting.
    let band = exp(-max(dir.y + 0.02, 0.0) * 9.0);
    let drift = 0.7 + 0.6 * fbm3(vec3<f32>(dir.x * 3.0 + u.camPos.w * 0.02, dir.y * 9.0, dir.z * 3.0));
    c = mix(c, u.mist.rgb, clamp(band * drift * 0.8, 0.0, 1.0));
    out.color = vec4<f32>(sqrt(c / (1.0 + c)), 0.85 * u.motes.z);
    return out;
}

// ---------------------------------------------------------------------------
// Fireflies

struct MoteOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) tint: vec4<f32>,
};

@vertex
fn vs_motes(@builtin(vertex_index) vi: u32, @location(0) mote: f32) -> MoteOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    let corner = corners[vi];
    let i = mote;
    let t = u.camPos.w;
    let a = hash3(vec3<f32>(i, 1.3, 7.1)) * 6.283;
    let r = 0.9 + hash3(vec3<f32>(i, 4.2, 2.9)) * 2.6;
    let speed = 0.08 + hash3(vec3<f32>(i, 9.7, 5.5)) * 0.12;
    let ang = a + t * speed * select(1.0, -1.0, hash3(vec3<f32>(i, 3.3, 3.3)) < 0.4);
    var pos = vec3<f32>(cos(ang) * r, 0.25 + hash3(vec3<f32>(i, 8.8, 1.1)) * 2.3, sin(ang) * r);
    pos += vec3<f32>(sin(t * 0.7 + i), sin(t * 0.9 + i * 1.7) * 0.6, cos(t * 0.6 + i * 2.3)) * 0.25;
    let beat = t * (0.5 + hash3(vec3<f32>(i, 2.0, 9.0)) * 0.6) + i * 7.0;
    let pulse = pow(max(sin(beat), 0.0), 3.0);
    let size = u.motes.y * (0.6 + 0.8 * pulse);
    let world = pos + (u.camRight.xyz * corner.x + u.camUp.xyz * corner.y) * size;
    var out: MoteOut;
    out.clip = u.viewProj * vec4<f32>(world, 1.0);
    out.uv = corner;
    out.tint = vec4<f32>(u.moteColor.rgb * (0.4 + 2.6 * pulse), 0.15 + 0.85 * pulse);
    return out;
}

@fragment
fn fs_motes(in: MoteOut) -> FragOut {
    var out: FragOut;
    let r = length(in.uv);
    if (r > 1.0) {
        discard;
    }
    let core = exp(-r * r * 10.0);
    let glow = (1.0 - smoothstep(0.15, 1.0, r)) * 0.4;
    let a = (core + glow) * in.tint.a;
    let c = in.tint.rgb * (1.0 + core * 2.0);
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a);
    return out;
}

