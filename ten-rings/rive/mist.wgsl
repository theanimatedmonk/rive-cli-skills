// Mist behind the Ten Rings: slow domain-warped fog in deep teal and ink.
// `power` (0..1) lights the fog around the rings in the energy colour and
// stirs it faster; `blast` (0..1) blows the fog outward from the focus and
// clears a hole. Output is premultiplied, y = 0 at the top.

struct Params {
    time: f32,
    power: f32,
    aspect: f32,   // width / height
    blast: f32,
    focusX: f32,   // 0..1 across
    focusY: f32,   // 0..1 down
    pad0: f32,
    pad1: f32,
    energy: vec4<f32>, // linear rgb
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
    let w = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var sum = 0.0;
    var amp = 0.5;
    for (var i = 0; i < 5; i = i + 1) {
        sum = sum + amp * noise(p);
        p = vec2<f32>(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + vec2<f32>(3.1, 1.7);
        amp = amp * 0.5;
    }
    return sum;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let power = clamp(u.power, 0.0, 1.5);
    let blast = clamp(u.blast, 0.0, 1.5);
    let focus = vec2<f32>(u.focusX, u.focusY);

    // Blast: sample nearer the focus so the fog appears shoved outward.
    let c = (in.uv - focus) * vec2<f32>(u.aspect, 1.0);
    let rad = length(c);
    let dir = c / max(rad, 1e-4);
    let sampleRad = max(rad - blast * 0.55 * exp(-rad * 1.2), 0.0);
    let uvS = focus + dir * sampleRad / vec2<f32>(u.aspect, 1.0);
    let clearing = 1.0 - 0.85 * blast * exp(-(rad * rad) / (0.02 + 0.25 * blast));

    let p = vec2<f32>(uvS.x * u.aspect, uvS.y) * 2.2;
    let t = u.time * (0.03 + 0.12 * power);
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3) - vec2<f32>(t, 0.0)));
    let f = fbm(p + 2.8 * q + vec2<f32>(t * 0.6, -t * 0.4));

    // Low-lying: thicker toward the bottom of the frame.
    let low = 0.55 + 0.45 * smoothstep(0.1, 0.95, in.uv.y);
    let fog = smoothstep(0.32, 0.9, f) * low * clearing;
    let veil = smoothstep(0.15, 0.65, f) * 0.3 * clearing;

    let ink = vec3<f32>(0.020, 0.045, 0.060);
    let teal = vec3<f32>(0.055, 0.16, 0.19);
    var color = mix(ink, teal, clamp(length(q) * 0.8, 0.0, 1.0));

    // Energy light gathered around the rings.
    let toFocus = (in.uv - focus) * vec2<f32>(u.aspect, 1.0);
    // Fades while the blast blows the fog away, so no glowing disc is left.
    let near = exp(-dot(toFocus, toFocus) / (0.05 + 0.1 * power)) * (1.0 - clamp(blast, 0.0, 1.0));
    let lit = u.energy.rgb * (0.25 + 0.9 * near) * power * power * 0.55;
    color = color + lit * (0.5 + f * 0.8);

    let alpha = clamp(veil + fog * 0.75 + near * power * 0.15 * clearing, 0.0, 1.0);
    let rgb = color * (veil * 0.8 + fog + near * power * 0.25 * clearing);
    return vec4<f32>(min(rgb, vec3<f32>(alpha)), alpha);
}
