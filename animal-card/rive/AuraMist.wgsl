// Soft mist around the card: slow domain-warped fog that hugs the card's
// rounded outline and fades outward. On a flip, `blast` (1 → 0) pushes the
// fog outward from the card and a soft shockwave ring (`ring`, px from the
// card's edge) runs out through it. Output is premultiplied, y = 0 at top.

struct Params {
    size: vec2<f32>,     // canvas size, px
    time: f32,
    blast: f32,          // 0..1, decays after a flip
    center: vec2<f32>,   // card centre, px
    half: vec2<f32>,     // card half size, px
    corner: f32,         // card corner radius, px
    ring: f32,           // shockwave distance from the card edge, px
    intensity: f32,
    reach: f32,          // how far the mist spreads, px
    colorA: vec4<f32>,
    colorB: vec4<f32>,
};

@group(0) @binding(0) var<uniform> u: Params;

struct VertexOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOut {
    var corners = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    let p = corners[idx];
    var out: VertexOut;
    out.position = vec4<f32>(p, 0.0, 1.0);
    out.uv = vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return out;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), w.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), w.x),
        w.y,
    );
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var q = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(q);
        q = q * 2.03 + vec2<f32>(17.3, 9.1);
        a *= 0.5;
    }
    return v;
}

// Signed distance to a rounded rectangle (positive outside).
fn roundRect(p: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let q = abs(p) - half + vec2<f32>(r);
    return length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let p = in.uv * u.size;
    let rel = p - u.center;
    let d = roundRect(rel, u.half, u.corner);
    let dir = rel / max(length(rel), 1.0);

    // Blow the fog outward while the blast lasts.
    let pushed = p - dir * u.blast * 140.0;
    let t = u.time * 0.06;
    let warp = vec2<f32>(fbm(pushed / 160.0 + vec2<f32>(t, -t)), fbm(pushed / 160.0 + vec2<f32>(-t * 0.7, t * 1.1) + 5.2));
    let fog = fbm(pushed / 110.0 + warp * 2.2 + vec2<f32>(t * 0.5, t * 0.3));

    // Densest just outside the card, fading out over `reach`.
    let reach = max(u.reach, 10.0);
    let falloff = exp(-max(d, 0.0) / reach) * smoothstep(-24.0, 12.0, d);
    let density = smoothstep(0.32, 0.85, fog) * falloff * (1.0 + u.blast * 0.35);

    // Shockwave: a soft bright ring running out from the edge.
    let ringGlow = exp(-pow((d - u.ring) / 16.0, 2.0)) * u.blast;

    let color = mix(u.colorA.rgb, u.colorB.rgb, smoothstep(0.35, 0.8, warp.x));
    let a = clamp(density * u.intensity + ringGlow * 0.3, 0.0, 1.0);
    let rgb = color * density * u.intensity + mix(u.colorB.rgb, vec3<f32>(1.0), 0.3) * ringGlow * 0.32;
    return vec4<f32>(rgb, a);
}
