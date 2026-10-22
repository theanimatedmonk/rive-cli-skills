// Blurs for the ruins' finish (post.wgsl), drawn into small canvases so
// the full-size pass only has to sample them:
//   fs_near   half size: the depth-of-field blur. Taps are weighted by how
//             out of focus they are (the scene's alpha), so sharp things
//             don't bleed into a soft background. Alpha: the average.
//   fs_wide   quarter size: a wide blur for the bloom and soft glow.
// The scene and these store colour as sqrt(c / (1 + c)), to keep values
// above 1 in 8 bits.

struct Params {
    texel: vec4<f32>,  // 1/width, 1/height, aspect, time (of the scene)
    look: vec4<f32>,   // bloom, glow, depth of field, exposure
    grade: vec4<f32>,  // tint rgb, saturation
    extra: vec4<f32>,  // vignette, grain, bloom threshold, blur radius
    leak: vec4<f32>,   // light leak rgb (linear), amount
};

@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var scene: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;

struct VertexOutput {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var out: VertexOutput;
    let x = f32((idx << 1u) & 2u) * 2.0 - 1.0;
    let y = f32(idx & 2u) * 2.0 - 1.0;
    out.clip = vec4<f32>(x, y, 0.0, 1.0);
    out.uv = vec2<f32>(x * 0.5 + 0.5, 0.5 - y * 0.5);
    return out;
}

fn decode(s: vec3<f32>) -> vec3<f32> {
    let q = min(s * s, vec3<f32>(0.995));
    return q / (1.0 - q);
}

fn encode(c: vec3<f32>) -> vec3<f32> {
    let m = max(c, vec3<f32>(0.0));
    return sqrt(m / (1.0 + m));
}

fn fetch(uv: vec2<f32>) -> vec4<f32> {
    let s = textureSampleLevel(scene, smp, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    return vec4<f32>(decode(s.rgb), s.a);
}

// 12 taps on a golden-angle spiral, fixed (so neighbouring pixels read
// neighbouring texels).
fn tap(i: i32) -> vec2<f32> {
    let fi = f32(i);
    let a = fi * 2.39996;
    let r = sqrt((fi + 0.5) / 12.0);
    return vec2<f32>(cos(a), sin(a)) * r * vec2<f32>(1.0 / u.texel.z, 1.0);
}

@fragment
fn fs_near(in: VertexOutput) -> @location(0) vec4<f32> {
    let radius = u.extra.w;
    let center = fetch(in.uv);
    var sum = center.rgb * max(center.a, 0.05);
    var w = max(center.a, 0.05);
    var blur = center.a;
    for (var i = 0; i < 12; i++) {
        let s = fetch(in.uv + tap(i) * radius);
        sum += s.rgb * s.a;
        w += s.a;
        blur += s.a;
    }
    return vec4<f32>(encode(sum / w), blur / 13.0);
}

@fragment
fn fs_wide(in: VertexOutput) -> @location(0) vec4<f32> {
    let radius = u.extra.w * 4.0;
    var sum = fetch(in.uv).rgb;
    var w = 1.0;
    for (var i = 0; i < 12; i++) {
        let t = tap(i);
        let k = 1.0 - length(t) * 0.5;
        sum += fetch(in.uv + t * radius).rgb * k;
        w += k;
    }
    return vec4<f32>(encode(sum / w), 1.0);
}
