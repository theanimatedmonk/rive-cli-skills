// Cosmic shine for the tarot card: a slow iridescent band sweeping across the
// card plus twinkling glints, masked to the card's rounded rectangle.
// Output is premultiplied and meant to be composited with 'screen' over the
// card face, so black means "no change".

struct Params {
    time: f32,
    strength: f32,
    width: f32,  // card size in artboard units, for the corner mask
    height: f32,
    spread: f32, // band width multiplier, 1 = default
    pad0: f32,
    pad1: f32,
    pad2: f32,
};

@group(0) @binding(0) var<uniform> u: Params;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

// One oversized triangle covering the target.
@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var corners = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(3.0, -1.0),
        vec2<f32>(-1.0, 3.0),
    );
    let p = corners[idx];
    var out: VertexOutput;
    out.position = vec4<f32>(p, 0.0, 1.0);
    out.uv = p * 0.5 + vec2<f32>(0.5, 0.5);
    return out;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn roundedRectDistance(p: vec2<f32>, half: vec2<f32>, radius: f32) -> f32 {
    let q = abs(p) - (half - vec2<f32>(radius, radius));
    return length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let size = vec2<f32>(u.width, u.height);
    let p = (in.uv - vec2<f32>(0.5, 0.5)) * size;
    let mask = 1.0 - smoothstep(-1.5, 0.5, roundedRectDistance(p, size * 0.5, 10.0));

    // Sweep: a diagonal band crossing the card every ~4s, with a long rest
    // off-card between passes. `spread` widens the band, and the sweep starts
    // and ends further off-card so a wide band still fully leaves.
    let w = max(u.spread, 0.05);
    let s = in.uv.x * 0.55 + in.uv.y * 0.85;
    let phase = fract(u.time * 0.24);
    let margin = 0.4 + 0.4 * w;
    let center = phase * (1.4 + 2.0 * margin) - margin;
    let d = (s - center) / w;
    let core = exp(-(d * d) / 0.0035);
    let halo = exp(-(d * d) / 0.045) * 0.35;
    let band = core + halo;

    // Iridescence along the band.
    let k = 6.2831853 * (s * 1.4 - u.time * 0.15);
    let rainbow = vec3<f32>(
        0.62 + 0.38 * sin(k),
        0.58 + 0.42 * sin(k + 2.1),
        0.72 + 0.28 * sin(k + 4.2),
    );
    let bandColor = mix(vec3<f32>(1.0, 0.95, 0.84), rainbow, 0.45);

    // Glints: sparse cells that flare and fade out of step with each other.
    let grid = vec2<f32>(9.0, 15.0);
    let cell = floor(in.uv * grid);
    let h = hash(cell);
    let local = (fract(in.uv * grid) - vec2<f32>(0.5, 0.5)) * vec2<f32>(1.0, grid.x / grid.y * size.y / size.x);
    let flare = pow(max(0.0, sin(u.time * 2.2 + h * 60.0)), 12.0) * step(0.8, h);
    let star = max(
        exp(-dot(local, local) / 0.004),
        max(exp(-(local.x * local.x) / 0.0006 - (local.y * local.y) / 0.03),
            exp(-(local.y * local.y) / 0.0006 - (local.x * local.x) / 0.03)) * 0.7,
    );
    let glint = flare * star;

    let alpha = clamp(band * 0.5 + glint * 0.95, 0.0, 1.0) * mask * u.strength;
    let color = bandColor * band * 0.5 + vec3<f32>(1.0, 0.97, 0.9) * glint * 0.95;
    return vec4<f32>(color * mask * u.strength, alpha);
}
