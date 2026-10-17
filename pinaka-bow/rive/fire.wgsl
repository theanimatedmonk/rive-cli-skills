// Agni's fire: roaring, turbulent flames engulfing the bow and arrow.
//
// A heat field hugs the bow's spine and the arrow's shaft (polylines in
// target pixels) and reaches far further in the rise direction than across,
// so flames climb off them. Domain-warped fbm noise streams along the rise
// direction through that field and breaks it into licking tongues; the heat
// maps through a fire palette, white-hot at the core to deep red at the
// ragged edges. Output is premultiplied.

struct Params {
    size: vec4<f32>,   // target width, height (px), time, reach (px)
    look: vec4<f32>,   // rise direction x, y (unit, y down), bow points, arrow points
    weight: vec4<f32>, // bow strength, arrow strength, pad, pad
    pts: array<vec4<f32>, 24>, // xy: 0-15 the bow's spine, 16-23 the arrow
};

@group(0) @binding(0) var<uniform> u: Params;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

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
    out.uv = vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return out;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (vec2<f32>(3.0, 3.0) - 2.0 * f);
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
        p = vec2<f32>(p.x * 1.7 - p.y * 1.1, p.x * 1.1 + p.y * 1.7) + vec2<f32>(2.3, 4.1);
        amp = amp * 0.5;
    }
    return sum;
}

// Heat from one segment: falls off with distance, but far more slowly in the
// rise direction, so the flames climb off it.
fn segmentHeat(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, rise: vec2<f32>, reach: f32, stretch: f32) -> f32 {
    let ab = b - a;
    let t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
    let v = p - (a + ab * t);
    let along = dot(v, rise);
    let across = v - rise * along;
    let a2 = select(along, along * stretch, along > 0.0);
    let d = sqrt(dot(across, across) + a2 * a2);
    return exp(-d / reach);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let p = in.uv * u.size.xy;
    let time = u.size.z;
    let reach = max(u.size.w, 1.0);
    let rise = u.look.xy;
    let bowN = i32(u.look.z);
    let arrowN = i32(u.look.w);

    // How tall the flames climb varies slowly across the fire, so tall
    // tongues and short licks alternate instead of ending at one height.
    let perp = vec2<f32>(-rise.y, rise.x);
    let column = fbm(vec2<f32>(dot(p, perp) / reach * 0.3 + 3.0, time * 0.7));
    let stretch = mix(0.5, 0.15, clamp((column - 0.25) * 2.2, 0.0, 1.0));
    var field = 0.0;
    for (var i = 0; i < 15; i = i + 1) {
        if (i + 1 < bowN) {
            field = max(field, u.weight.x * segmentHeat(p, u.pts[i].xy, u.pts[i + 1].xy, rise, reach, stretch));
        }
    }
    for (var i = 0; i < 7; i = i + 1) {
        if (i + 1 < arrowN) {
            field = max(field, u.weight.y * segmentHeat(p, u.pts[16 + i].xy, u.pts[17 + i].xy, rise, reach, stretch));
        }
    }
    if (field < 0.01) {
        return vec4<f32>(0.0);
    }

    // Turbulence streaming along the rise direction, folded through itself.
    let q = p / reach * 0.5 - rise * time * 1.7;
    let warp = vec2<f32>(fbm(q * 0.6 + vec2<f32>(0.0, time * 0.35)), fbm(q * 0.6 + vec2<f32>(5.2, 1.3)));
    let n = fbm(q + 2.2 * warp);
    // Large slow billows decide where the tall tongues and the gaps fall.
    let billow = fbm(q * 0.35 + rise * time * 0.6 + vec2<f32>(9.1, 3.7));
    let fine = noise(q * 3.1 + warp * 2.0);

    var heat = field * (0.25 + 1.6 * n) * (0.55 + 0.85 * billow) - 0.38 + 0.12 * (fine - 0.5);
    heat = clamp(heat * 1.25, 0.0, 1.0);

    // Fire palette: deep red at the ragged edge, through orange and yellow,
    // to white-hot at the core.
    var c = mix(vec3<f32>(0.35, 0.03, 0.0), vec3<f32>(0.95, 0.28, 0.03), smoothstep(0.0, 0.35, heat));
    c = mix(c, vec3<f32>(1.0, 0.62, 0.12), smoothstep(0.3, 0.6, heat));
    c = mix(c, vec3<f32>(1.0, 0.86, 0.5), smoothstep(0.7, 0.92, heat));
    c = mix(c, vec3<f32>(1.0, 0.97, 0.88), smoothstep(0.96, 1.0, heat));
    let alpha = smoothstep(0.02, 0.45, heat) * 0.85;
    return vec4<f32>(c * alpha, alpha);
}
