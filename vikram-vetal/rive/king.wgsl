// King Vikram, drawn as a painting that happens to be 3D: the night
// scene's look (world.wgsl) carried onto a character.
//
//   vs_king / fs_king        the body: skinned on the GPU from the bones
//                            (King.luau blends the loops), lit in flat
//                            toon bands by the moon and a fire's glow,
//                            shadows tinted rather than black, a hard rim
//                            of moonlight, gold that glints, ink lines
//                            drawn from the painted texture and hatching
//                            in the deepest shadow.
//   vs_outline / fs_outline  the ink outline: the body again, pushed out
//                            along its normals a few pixels and drawn
//                            inside out, its width wavering like a brush.
//   vs_king_shadow           the body seen from the moon, for its shadow.
//   vs_ground / fs_ground    dry, cracked earth underfoot (it scrolls when
//                            he walks), fading into the mist.
//   vs_sky / fs_sky          the night sky behind him: stars, the moon's
//                            glow, mist at the horizon.
//   vs_motes / fs_motes      fireflies drifting round him.
//   vs_aura / fs_aura        his bow's aura as he draws it, as the Pinaka's:
//                            a breathing radiance, god rays, a halo hugging
//                            the arc, divine fire rising off it, sparks, and
//                            glints running down the string to the nock.
//
// The bow is skinned with him (bow bones in the same rig) and its string
// pulls by a shape key, weighted by `aura.y`. As it draws (`aura.x`) its
// gold and string kindle, light flows from the grip to the tips, and it
// lights him in gold.
//
// `style.x` (paint, 0-1) is the 2D-3D mix: 0 is soft 3D shading, 1 flat
// painted bands, simplified colour and hard edges.
//
// Colour is written as sqrt(c / (1 + c)), with the depth-of-field blur in
// alpha, for blur.wgsl and post.wgsl.

const JOINTS = 80;
const BOW_SAMPLES = 13;

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
    @location(2) uv: vec2<f32>,
    @location(3) joints: vec4<u32>,
    @location(4) weights: vec4<f32>,
    // The drawn string's shape key (zero but on the bow): position delta,
    // normal delta / 2.
    @location(5) morphPosition: vec3<f32>,
    @location(6) morphNormal: vec4<f32>,
    // The wind painted on him: how much it sways, its phase, what it is / 2
    // (0 skin, 1 hair, 2 cloth).
    @location(7) wind: vec4<f32>,
};

struct Skinned {
    world: vec3<f32>,
    normal: vec3<f32>,
};

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
    let p = vec4<f32>(v.position + v.morphPosition * u.aura.y, 1.0);
    let local = vec3<f32>(dot(r0, p), dot(r1, p), dot(r2, p));
    let n = vec4<f32>(v.normal.xyz + v.morphNormal.xyz * 2.0 * u.aura.y, 0.0);
    let ln = vec3<f32>(dot(r0, n), dot(r1, n), dot(r2, n));
    var s: Skinned;
    s.world = (u.model * vec4<f32>(local, 1.0)).xyz + windSway(v.wind);
    s.normal = normalize((u.model * vec4<f32>(ln, 0.0)).xyz);
    return s;
}

// His hair and cloth in the wind (world metres): blown along it, swaying
// as it gusts, the cloth fluttering faster; each vertex in its own phase,
// as painted.
fn windSway(w: vec4<f32>) -> vec3<f32> {
    if (w.x <= 0.0 || u.windA.z <= 0.0) {
        return vec3<f32>(0.0);
    }
    let what = round(w.z * 2.0);
    let take = select(select(0.0, u.windB.y, what > 1.5), u.windB.x, what > 0.5 && what < 1.5);
    let t = u.windA.w;
    let ph = w.y * 6.283;
    let gust = 1.0 - u.windB.z * 0.5 * (1.0 + sin(t * 0.43 + 1.3) * sin(t * 0.17));
    let sway = 0.6 + 0.4 * sin(t * 1.7 + ph);
    let flutter = sin(t * select(4.0, 9.0, what > 1.5) + ph * 3.0);
    let dir = vec3<f32>(u.windA.x, 0.0, u.windA.y);
    let side = vec3<f32>(-u.windA.y, 0.0, u.windA.x);
    let strength = pow(u.windA.z, 0.7);
    return (dir * sway * gust + side * flutter * 0.35 + vec3<f32>(0.0, flutter * 0.12, 0.0))
        * w.x * take * strength * 0.06;
}

struct KingOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) rest: vec3<f32>,
};

@vertex
fn vs_king(v: SkinIn) -> KingOut {
    let s = skin(v);
    var out: KingOut;
    out.clip = u.viewProj * vec4<f32>(s.world, 1.0);
    out.world = s.world;
    out.normal = s.normal;
    out.uv = v.uv;
    out.rest = v.position;
    return out;
}

@vertex
fn vs_king_shadow(v: SkinIn) -> @builtin(position) vec4<f32> {
    let s = skin(v);
    return u.lightViewProj * vec4<f32>(s.world, 1.0);
}

@group(0) @binding(1) var shadowMap: texture_depth_2d;
@group(0) @binding(2) var shadowSmp: sampler_comparison;
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

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Inside an eye (1) to outside (0): an almond round its centre, on the face's
// front, in bind pose.
fn almond(r: vec3<f32>, c: vec3<f32>, w: f32, h: f32) -> f32 {
    let d = vec2<f32>((r.x - c.x) / w, (r.y - c.y) / h);
    return (1.0 - smoothstep(0.7, 1.0, length(d))) * step(0.07, r.z);
}

// The earrings' warm light on what is near them (his jaw, neck, shoulders).
// The bow's aura lights what is near it in gold: his hands, arms and chest.
fn bowLight(p: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    let g = u.spine[6].xyz;
    let d = g - p;
    let d2 = dot(d, d);
    let wrap = max(dot(n, d * inverseSqrt(max(d2, 1e-8))) * 0.6 + 0.4, 0.0);
    return u.auraColor.rgb * u.aura.x * exp(-d2 / 0.18) * wrap * 0.9;
}

fn earLight(p: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    var sum = 0.0;
    for (var i = 0; i < 2; i++) {
        let e = select(u.earR.xyz, u.earL.xyz, i == 0);
        let d = e - p;
        let d2 = dot(d, d);
        let wrap = max(dot(n, d * inverseSqrt(max(d2, 1e-8))) * 0.6 + 0.4, 0.0);
        sum += exp(-d2 / 0.012) * wrap;
    }
    return u.earColor.rgb * u.earL.w * sum * 0.5;
}

@fragment
fn fs_king(in: KingOut, @builtin(front_facing) front: bool) -> FragOut {
    var out: FragOut;
    let paint = u.style.x;
    let p = in.world;
    // The painted texture, and a simpler one (a few mips down) whose broad
    // colour the painting keeps.
    let texel = textureSample(colorTex, texSmp, in.uv).rgb;
    let broad = textureSampleBias(colorTex, texSmp, in.uv, 2.5).rgb;
    let nm = textureSample(normalTex, texSmp, in.uv).rgb;
    let rm = textureSample(rmTex, texSmp, in.uv).rgb;
    // Ink from the painting itself: where its value turns sharply (an eye,
    // a brow, a fold, the edge of a trim) a line is drawn.
    let lum = luma(texel);
    let lumEdge = fwidth(lum);
    let dp = dpdx(p);
    let dq = dpdy(p);
    let duv1 = dpdx(in.uv);
    let duv2 = dpdy(in.uv);

    var albedo = pow(texel, vec3<f32>(2.2));
    let flat = pow(broad, vec3<f32>(2.2));
    // Painted: the broad colour with a little of the detail, a touch richer.
    var painted = mix(flat, albedo, 0.45);
    let pl = luma(painted);
    painted = max(mix(vec3<f32>(pl), painted, 1.06), vec3<f32>(0.0));
    albedo = mix(albedo, painted, paint);

    // The normal: the mesh's, with the normal map's detail (less of it the
    // more painted).
    var n = normalize(in.normal);
    if (!front) {
        n = -n;
    }
    let dp2perp = cross(dq, n);
    let dp1perp = cross(n, dp);
    let t = dp2perp * duv1.x + dp1perp * duv2.x;
    let b = dp2perp * duv1.y + dp1perp * duv2.y;
    let inv = inverseSqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
    let tn = nm * 2.0 - 1.0;
    let detailed = normalize(t * inv * tn.x - b * inv * tn.y + n * max(tn.z, 0.2));
    let ln = normalize(mix(detailed, n, 0.25 + 0.6 * paint));

    let view = normalize(u.camPos.xyz - p);
    let roughness = rm.g;
    let metal = rm.b;

    // The moon: cool light from above and behind, with real shadow.
    let L = u.moonDir.xyz;
    let shadow = moonShadow(p, n);
    let moonN = max(dot(ln, L), 0.0) * shadow;
    let moonBand = bands(moonN * 1.15, u.style.y, paint);
    // The fire: warm, low and in front, flickering.
    let F = u.fireDir.xyz;
    let fireN = max(dot(ln, F) * 0.9 + 0.1, 0.0);
    let fireBand = bands(fireN, u.style.y, paint);

    // Shadow is painted in a colour, not black.
    let ambient = u.shadowTint.rgb * u.shadowTint.w * (0.6 + 0.4 * max(ln.y, 0.0));
    var light = ambient
        + u.moonColor.rgb * u.moonDir.w * moonBand
        + u.fireColor.rgb * u.fireDir.w * fireBand;
    var c = albedo * light + albedo * (earLight(p, ln) + bowLight(p, ln));

    // Gold glints: a hard highlight where the metal faces a light.
    let hm = normalize(L + view);
    let hf = normalize(F + view);
    let gloss = mix(8.0, 90.0, 1.0 - roughness);
    let specM = pow(max(dot(ln, hm), 0.0), gloss) * shadow;
    let specF = pow(max(dot(ln, hf), 0.0), gloss);
    let specRaw = specM * u.moonDir.w * u.moonColor.rgb + specF * u.fireDir.w * u.fireColor.rgb;
    let specStep = smoothstep(0.25, 0.35, specM) * u.moonDir.w * u.moonColor.rgb
        + smoothstep(0.25, 0.35, specF) * u.fireDir.w * u.fireColor.rgb;
    let spec = mix(specRaw, specStep, paint) * mix(0.15, 1.6, metal) * mix(vec3<f32>(1.0), albedo * 3.0, metal);
    c += spec;

    // A rim of moonlight on the edge facing it: a hard line in the
    // painting, a soft sheen in 3D.
    let fres = 1.0 - max(dot(n, view), 0.0);
    let facing = clamp(dot(n, L) * 0.6 + 0.5, 0.0, 1.0);
    let rimSoft = pow(fres, 3.0);
    let rimHard = smoothstep(0.55, 0.61, fres);
    let rim = mix(rimSoft, rimHard, paint) * facing * u.moonColor.w;
    c += u.moonColor.rgb * rim * (0.5 + u.moonDir.w * 3.0) * (0.4 + 0.6 * shadow);

    // Hatching in the deepest shadow: fine diagonal strokes in screen space.
    let unlit = 1.0 - clamp(moonBand + fireBand * u.fireDir.w * 0.6, 0.0, 1.0);
    let sp = in.clip.xy / max(u.viewport.y / 720.0, 0.5);
    let stroke = sin((sp.x + sp.y) * 0.9 + noise3(vec3<f32>(sp * 0.05, 0.0)) * 4.0);
    // The eyes, brought out of the brow's shadow: they catch light even
    // when the face is dark, the whites read, the iris is ringed, the pupil
    // dark, with a catchlight. The socket round them is lifted a little.
    let r = in.rest;
    let eyes = u.eyeR.w;
    let eyeM = max(almond(r, u.eyeL.xyz, 0.0175, 0.0068), almond(r, u.eyeR.xyz, 0.0175, 0.0068)) * eyes;
    let socket = max(almond(r, u.eyeL.xyz, 0.03, 0.017), almond(r, u.eyeR.xyz, 0.03, 0.017)) * eyes;
    let faceLight = ambient * 2.0 + u.moonColor.rgb * u.moonDir.w * 0.35 + u.fireColor.rgb * u.fireDir.w * 0.8 + vec3<f32>(0.04, 0.045, 0.06);
    c = max(c, albedo * faceLight * 0.6 * socket);
    let sat = max(texel.r, max(texel.g, texel.b)) - min(texel.r, min(texel.g, texel.b));
    let sclera = smoothstep(0.3, 0.48, lum) * (1.0 - smoothstep(0.16, 0.3, sat));
    let dL = length(r.xy - u.irisL.xy);
    let dR = length(r.xy - u.irisR.xy);
    let dI = min(dL, dR);
    let irisC = select(u.irisR.xy, u.irisL.xy, dL < dR);
    var eyeC = albedo * faceLight * 1.3;
    eyeC = mix(eyeC, vec3<f32>(0.62, 0.6, 0.57) * (faceLight * 1.6 + vec3<f32>(0.05)), sclera);
    let iris = 1.0 - smoothstep(0.0058, 0.0068, dI);
    eyeC = mix(eyeC, albedo * faceLight * 1.7 + vec3<f32>(0.03, 0.015, 0.0), iris);
    eyeC *= 1.0 - 0.55 * smoothstep(0.0042, 0.0062, dI) * iris;
    eyeC *= 1.0 - 0.8 * (1.0 - smoothstep(0.0021, 0.0029, dI));
    let catchD = length(r.xy - irisC - vec2<f32>(-0.0021, 0.0022));
    eyeC += vec3<f32>(1.4, 1.35, 1.25) * (1.0 - smoothstep(0.0008, 0.0013, catchD)) * iris;
    c = mix(c, eyeC, eyeM);

    // Blinking: the upper lid sweeps down from the eye's top to the curve of
    // its bottom, in his eyelid's skin, its edge a line of lashes in ink.
    let blink = u.lid.w;
    let nearL = length(r.xy - u.eyeL.xy) < length(r.xy - u.eyeR.xy);
    let ec = select(u.eyeR.xyz, u.eyeL.xyz, nearL);
    let ax = (r.x - ec.x) / 0.0175;
    let arc = sqrt(max(1.0 - ax * ax, 0.0));
    let lidEdge = mix(ec.y + 0.0068 * 1.05 * arc, ec.y - 0.0068 * 1.02 * arc, blink);
    let lidBox = almond(r, ec, 0.0182, 0.0076) * eyes;
    let lidCover = lidBox * smoothstep(-0.00025, 0.00025, r.y - lidEdge) * smoothstep(0.0, 0.08, blink);
    // Rounded: lit along its middle, darker into the crease above.
    let crease = smoothstep(0.0, 0.006, r.y - lidEdge);
    let lidC = u.lid.rgb * faceLight * mix(0.85, 0.6, crease);
    c = mix(c, lidC, lidCover);

    let hatch = smoothstep(0.55, 0.85, stroke) * smoothstep(0.55, 0.95, unlit) * u.style.w * paint * (1.0 - socket);
    c *= 1.0 - hatch * 0.55;

    // Ink where the painting turns sharply.
    let inkLine = smoothstep(0.05, 0.16, lumEdge) * u.style.z * paint;
    c = mix(c, u.ink.rgb, inkLine * 0.8 * (1.0 - 0.6 * eyeM) * (1.0 - lidCover));
    let lash = (1.0 - smoothstep(0.0003 + 0.0005 * blink, 0.0006 + 0.0007 * blink, abs(r.y - lidEdge))) * lidBox;
    c = mix(c, u.ink.rgb, lash * smoothstep(0.0, 0.15, blink));
    // Catchlights stay on top of the ink, unless the lid is over them.
    c += vec3<f32>(1.2, 1.15, 1.05) * (1.0 - smoothstep(0.0008, 0.0013, catchD)) * iris * eyeM * (1.0 - lidCover);

    // The earrings: gold that glows from within, and a gem drop that burns.
    if (in.uv.x < -0.5) {
        let glow = u.earL.w * (0.85 + 0.15 * u.earR.w);
        let gold = vec3<f32>(0.8, 0.48, 0.1);
        var ec = gold * light * 1.4 + gold * u.earColor.rgb * glow * (0.5 + 1.2 * fres);
        let glint = smoothstep(0.55, 0.7, max(dot(n, hm), dot(n, hf)));
        ec += vec3<f32>(1.0, 0.85, 0.55) * glint * (u.moonDir.w + u.fireDir.w);
        if (in.uv.y > 0.5) {
            ec = u.earColor.rgb * glow * (1.1 + 0.9 * (1.0 - fres)) + vec3<f32>(1.0, 0.75, 0.4) * glow * 0.6 * pow(1.0 - fres, 6.0);
        }
        c = ec;
    }

    // The bow: dark wood and gold in the night; as he draws, the gold and
    // the string kindle and light flows along it from the grip to the tips.
    if (in.uv.x < -1.5) {
        let part = in.uv.y;
        let A = u.aura.x;
        let tb = clamp(dot(r - u.bowOrigin.xyz, u.bowAxis.xyz) / max(u.bowOrigin.w, 1e-3), 0.0, 1.0);
        let fromGrip = abs(tb - 0.5) * 2.0;
        let flow = pow(0.5 + 0.5 * sin(fromGrip * 16.0 - u.camPos.w * 5.0), 3.0);
        let glint = smoothstep(0.55, 0.7, max(dot(n, hm), dot(n, hf)));
        let lightN = ambient + u.moonColor.rgb * u.moonDir.w * moonBand + u.fireColor.rgb * u.fireDir.w * fireBand;
        var bc: vec3<f32>;
        if (part < 0.5) {
            let wood = vec3<f32>(0.1, 0.045, 0.02);
            bc = wood * lightN * 1.3 + vec3<f32>(0.5, 0.35, 0.2) * glint * 0.15 * (u.moonDir.w + u.fireDir.w);
            bc += u.auraColor.rgb * A * (pow(fres, 2.0) * 0.9 + flow * 0.12);
        } else if (part < 1.5) {
            let gold = vec3<f32>(0.8, 0.52, 0.18);
            bc = gold * lightN * 1.4 + vec3<f32>(1.0, 0.85, 0.55) * glint * (u.moonDir.w + u.fireDir.w);
            bc += gold * u.auraColor.rgb * A * (0.35 + 1.1 * flow + 0.6 * fres);
        } else {
            let cord = vec3<f32>(0.75, 0.68, 0.55);
            bc = cord * lightN + u.auraColor.rgb * A * 2.6 + vec3<f32>(1.0, 0.95, 0.85) * A * 1.4;
        }
        c = bc;
    }

    out.color = encode(misty(c, p), defocus(p) * u.motes.z);
    return out;
}

// ---------------------------------------------------------------------------
// The outline

struct OutlineOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
};

@vertex
fn vs_outline(v: SkinIn) -> OutlineOut {
    let s = skin(v);
    var out: OutlineOut;
    if (v.uv.x < -1.5 && v.uv.y > 1.5) {
        // The bowstring is a line of light: no ink round it.
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

// ---------------------------------------------------------------------------
// The bow's aura

// A point along the bow (0 one tip, 1 the other), through its samples.
fn spineAt(t: f32) -> vec3<f32> {
    let f = clamp(t, 0.0, 1.0) * f32(BOW_SAMPLES - 1);
    let i = min(i32(floor(f)), BOW_SAMPLES - 2);
    let k = f - f32(i);
    let p0 = u.spine[max(i - 1, 0)].xyz;
    let p1 = u.spine[i].xyz;
    let p2 = u.spine[i + 1].xyz;
    let p3 = u.spine[min(i + 2, BOW_SAMPLES - 1)].xyz;
    // Catmull-Rom.
    let k2 = k * k;
    let k3 = k2 * k;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3);
}

fn h1(n: f32, s: f32) -> f32 {
    return hash3(vec3<f32>(n, s, n * 0.37 + s * 1.7));
}

struct AuraOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) tint: vec4<f32>,
    @location(2) shape: f32,
};

// The aura's pieces, by id: 0 the radiance; 1-14 rays; 15-74 the halo;
// 75-154 wisps of fire; 155-214 sparks; 215-234 glints on the string;
// 235-330 the gold waves: arcs of light rippling out from the bow, away
// from the string, in its plane; 331-522 the release's ripples: three rings
// of gold spreading from the grip, in the bow's plane, across it and level.
@vertex
fn vs_aura(@builtin(vertex_index) vi: u32, @location(0) id: f32) -> AuraOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0));
    let corner = corners[vi];
    let A = u.aura.x;
    let t = u.camPos.w;
    let R = u.camRight.xyz;
    let U = u.camUp.xyz;
    let gold = u.auraColor.rgb;
    let grip = spineAt(0.5);
    var pos = grip;
    var ax = R;
    var ay = U;
    var sx = 0.0;
    var sy = 0.0;
    var tint = vec4<f32>(0.0);
    var shape = 0.0;
    let breath = 0.85 + 0.15 * sin(t * 1.7);
    var scale = A;
    var alpha = min(A, 1.0);
    if (id > 330.5) {
        // The release's ripples: each ring a band of light spreading fast,
        // then slowing, thinning as it goes.
        let i = id - 331.0;
        let ring = floor(i / 64.0);
        let j = i - ring * 64.0;
        let rr = u.aura.z;
        let along = normalize(u.spine[BOW_SAMPLES - 1].xyz - u.spine[0].xyz);
        var draw = grip - u.spine[BOW_SAMPLES].xyz;
        draw = normalize(draw - along * dot(draw, along) + vec3<f32>(1e-4, 0.0, 0.0));
        let across = cross(along, draw);
        var e1 = along;
        var e2 = draw;
        if (ring > 0.5 && ring < 1.5) {
            e1 = draw;
            e2 = across;
        } else if (ring > 1.5) {
            e1 = along;
            e2 = across;
        }
        let ang = j / 64.0 * 6.2832;
        let dir = e1 * cos(ang) + e2 * sin(ang);
        let grow = 1.0 - pow(1.0 - clamp(rr * (1.0 + ring * 0.15), 0.0, 1.0), 3.0);
        let radius = 0.15 + grow * 3.4;
        pos = grip + dir * radius;
        ax = e1 * -sin(ang) + e2 * cos(ang);
        ay = cross(ax, dir);
        sx = 0.22 + radius * 0.05;
        sy = 0.035 + 0.05 * (1.0 - rr);
        let live = select(0.0, 1.0, rr > 0.0 && rr < 1.0);
        tint = vec4<f32>(gold * 1.6 + vec3<f32>(0.3, 0.25, 0.15) * (1.0 - rr), 0.75 * pow(1.0 - rr, 1.6) * live);
        scale = 1.0;
        alpha = min(u.auraColor.w, 1.0);
    } else if (id < 0.5) {
        // The radiance: a broad, breathing glow behind the bow.
        sx = 0.85 * breath;
        sy = sx;
        tint = vec4<f32>(gold * 0.8, 0.42);
    } else if (id < 14.5) {
        // God rays fanning slowly out from the grip.
        let i = id - 1.0;
        let ang = i / 14.0 * 6.2832 + t * 0.06 + h1(i, 1.0) * 0.4;
        let dir = R * cos(ang) + U * sin(ang);
        let len = (0.55 + 0.6 * h1(i, 2.0)) * (0.8 + 0.2 * sin(t * 0.8 + i * 1.3));
        pos = grip + dir * len * 0.5;
        ax = cross(dir, u.camFwd.xyz);
        ay = dir;
        sx = 0.03 + 0.02 * h1(i, 3.0);
        sy = len * 0.5;
        tint = vec4<f32>(gold * 0.8, 0.3);
        shape = 1.0;
    } else if (id < 74.5) {
        // The halo: soft glow hugging the arc, waves of it running out.
        let i = id - 15.0;
        let tt = (i + 0.5) / 60.0;
        pos = spineAt(tt);
        let wave = 0.5 + 0.5 * sin(abs(tt - 0.5) * 14.0 - t * 3.0);
        sx = 0.1 + 0.07 * wave;
        sy = sx;
        tint = vec4<f32>(gold * (0.8 + 0.7 * wave), 0.22 + 0.14 * wave);
    } else if (id < 154.5) {
        // Divine fire rising off the bow: each wisp born somewhere along it,
        // rising, swaying, from white-gold to ember as it fades.
        let i = id - 75.0;
        let life = 1.1 + 0.9 * h1(i, 4.0);
        let ph = fract(t / life + h1(i, 5.0));
        let base = spineAt(0.04 + 0.92 * h1(i, 6.0));
        let lift = ph * (0.25 + 0.2 * h1(i, 7.0));
        let sway = sin(ph * 6.0 + i) * 0.035;
        pos = base + vec3<f32>(0.0, lift, 0.0) + R * sway;
        let grow = sin(ph * 3.1416);
        sx = 0.028 * grow + 0.004;
        sy = sx * 2.2;
        let col = mix(vec3<f32>(1.2, 1.05, 0.8), gold * vec3<f32>(1.0, 0.6, 0.3), ph);
        tint = vec4<f32>(col * 1.4, 0.55 * grow);
        shape = 2.0;
    } else if (id < 214.5) {
        // Sparks twinkling round it.
        let i = id - 155.0;
        let base = spineAt(h1(i, 8.0));
        let a = h1(i, 9.0) * 6.2832 + t * (0.3 + 0.5 * h1(i, 10.0));
        let r = 0.06 + 0.2 * h1(i, 11.0);
        pos = base + (R * cos(a) + U * sin(a)) * r + vec3<f32>(0.0, sin(t * 0.7 + i) * 0.03, 0.0);
        let tw = pow(max(sin(t * (2.5 + 4.0 * h1(i, 12.0)) + i * 3.7), 0.0), 6.0);
        sx = 0.012 + 0.01 * tw;
        sy = sx;
        tint = vec4<f32>(vec3<f32>(1.3, 1.15, 0.85) * (0.6 + 1.6 * tw), 0.2 + 0.8 * tw);
        shape = 3.0;
    } else if (id > 234.5) {
        // The gold waves: three arcs at a time, each leaving the bow and
        // spreading out, away from the string, fading as it goes.
        let i = id - 235.0;
        let ring = floor(i / 32.0);
        let tt = (i - ring * 32.0 + 0.5) / 32.0;
        let on = spineAt(tt);
        let chord = mix(u.spine[0].xyz, u.spine[BOW_SAMPLES - 1].xyz, tt);
        let mid = mix(u.spine[0].xyz, u.spine[BOW_SAMPLES - 1].xyz, 0.5);
        // Away from the string: from the nock through the bow's belly.
        var out = on - u.spine[BOW_SAMPLES].xyz;
        out = normalize(out + (on - chord) * 0.5 + (on - mid) * 0.2);
        let ph = fract(t * 0.35 + ring / 3.0);
        let reach = ph * 0.55;
        pos = on + out * reach;
        let ends = sin(tt * 3.1416);
        sx = 0.05 + 0.05 * ph;
        sy = sx;
        let fade = (1.0 - ph) * smoothstep(0.0, 0.12, ph) * (0.35 + 0.65 * ends);
        tint = vec4<f32>(gold * 1.1, 0.32 * fade);
    } else {
        // Glints running down the string from each tip to the nock.
        let i = id - 215.0;
        let tip = select(u.spine[0].xyz, u.spine[BOW_SAMPLES - 1].xyz, i < 9.5);
        let s = fract(t * 0.55 + h1(i, 13.0));
        pos = mix(tip, u.spine[BOW_SAMPLES].xyz, s);
        let f = sin(s * 3.1416);
        sx = 0.016 * f + 0.003;
        sy = sx;
        tint = vec4<f32>(vec3<f32>(1.2, 1.05, 0.75) * 1.5, 0.8 * f);
        shape = 3.0;
    }
    let world = pos + ax * corner.x * sx * scale + ay * corner.y * sy * scale;
    var out: AuraOut;
    out.clip = u.viewProj * vec4<f32>(world, 1.0);
    out.uv = corner;
    out.tint = vec4<f32>(tint.rgb, tint.a * alpha);
    out.shape = shape;
    return out;
}

@fragment
fn fs_aura(in: AuraOut) -> FragOut {
    var out: FragOut;
    let x = in.uv.x;
    let y = in.uv.y;
    let r2 = x * x + y * y;
    var a = 0.0;
    if (in.shape < 0.5) {
        a = exp(-r2 * 4.0) * step(r2, 1.0);
    } else if (in.shape < 1.5) {
        // A ray: bright at the grip, thinning out to nothing.
        let along = y * 0.5 + 0.5;
        a = exp(-x * x * 5.0) * pow(1.0 - along, 2.0) * smoothstep(0.0, 0.08, along);
    } else if (in.shape < 2.5) {
        // A flame: a teardrop, round below, drawn to a point above.
        let v = y * 0.5 + 0.5;
        let w = mix(0.75, 0.08, v);
        a = exp(-(x * x) / (w * w) * 2.5) * smoothstep(0.0, 0.25, v) * (1.0 - smoothstep(0.7, 1.0, v));
    } else {
        // A spark: a hot core with a four-pointed flare.
        a = exp(-r2 * 16.0) + (exp(-abs(x) * 28.0) * exp(-y * y * 4.0) + exp(-abs(y) * 28.0) * exp(-x * x * 4.0)) * 0.45;
        a *= step(r2, 1.0);
    }
    a *= in.tint.a;
    let c = in.tint.rgb;
    out.color = vec4<f32>(sqrt(c / (1.0 + c)) * a, a);
    return out;
}
