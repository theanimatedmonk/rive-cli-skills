// The dreamy finish for the ruins: reads the scene (ruins.wgsl stores colour
// as sqrt(c / (1 + c)) and, in alpha, how out of focus each pixel is) and
// its blurs (blur.wgsl: the focus blur at half size, a wide one at a
// quarter), and adds
//   bloom      bright light (the sun, the sky, sunlit stone) spills softly
//   glow       an overall soft focus, screen-blended (the "Orton" look)
//   focus      depth of field: out-of-focus pixels take the blur
// then tone maps, warms, vignettes and adds a fine grain.

struct Params {
    texel: vec4<f32>,  // 1/width, 1/height, aspect, time
    look: vec4<f32>,   // bloom, glow, depth of field, exposure
    grade: vec4<f32>,  // tint rgb, saturation
    extra: vec4<f32>,  // vignette, grain, bloom threshold, blur radius
    leak: vec4<f32>,   // light leak rgb (linear), amount
    sun: vec4<f32>,    // the sun on screen (uv), shafts strength, 1 if ahead
};

@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var scene: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;
@group(0) @binding(3) var nearTex: texture_2d<f32>;
@group(0) @binding(4) var wideTex: texture_2d<f32>;

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

fn fetch(uv: vec2<f32>) -> vec4<f32> {
    let s = textureSampleLevel(scene, smp, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    return vec4<f32>(decode(s.rgb), s.a);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let center = fetch(in.uv);
    let threshold = u.extra.z;
    // The blurs, drawn small by blur.wgsl and smoothed by the sampler.
    let nearS = textureSampleLevel(nearTex, smp, in.uv, 0.0);
    let blurred = decode(nearS.rgb);
    let wide = decode(textureSampleLevel(wideTex, smp, in.uv, 0.0).rgb);
    var c = mix(center.rgb, blurred, clamp(center.a * u.look.z, 0.0, 1.0));
    let bright = (max(wide - vec3<f32>(threshold), vec3<f32>(0.0)) * 1.5
        + max(blurred - vec3<f32>(threshold), vec3<f32>(0.0)) * 0.5) * 0.75;

    // Light shafts: march toward the sun through the wide blur, gathering
    // its brightest light, so gaps between pillars and leaves stream rays.
    var shafts = vec3<f32>(0.0);
    if (u.sun.w > 0.5 && u.sun.z > 0.0) {
        let toSun = u.sun.xy - in.uv;
        var decay = 1.0;
        for (var i = 0; i < 20; i++) {
            let t = (f32(i) + 0.5) / 20.0;
            let s = decode(textureSampleLevel(wideTex, smp, in.uv + toSun * t * 0.85, 0.0).rgb);
            shafts += max(s - vec3<f32>(threshold * 0.9), vec3<f32>(0.0)) * decay;
            decay *= 0.93;
        }
        shafts *= u.sun.z / 20.0;
    }

    let exposure = u.look.w;
    c *= exposure;
    c += bright * u.look.x * exposure;
    c += shafts * u.leak.rgb * exposure;
    var mapped = aces(c);
    // Soft focus: screen the wide blur over the image.
    let soft = aces(wide * exposure);
    mapped = 1.0 - (1.0 - mapped) * (1.0 - soft * u.look.y);
    mapped = mix(mapped, soft, u.look.y * 0.15);

    // A warm glow around the sun, spilling in even when it is just out of
    // frame.
    let lp = (in.uv - clamp(u.sun.xy, vec2<f32>(-0.15), vec2<f32>(1.15))) * vec2<f32>(u.texel.z, 1.0);
    let leak = exp(-dot(lp, lp) * 1.6) * u.leak.w;
    mapped = 1.0 - (1.0 - mapped) * (1.0 - u.leak.rgb * leak);

    // Grade: a warm tint and a touch less saturation, lifted blacks.
    let luma = dot(mapped, vec3<f32>(0.299, 0.587, 0.114));
    mapped = mix(vec3<f32>(luma), mapped, u.grade.w);
    mapped *= u.grade.rgb;
    // Blacks barely lifted: the night can go properly dark.
    mapped = mapped * 0.99 + vec3<f32>(0.004, 0.004, 0.006);

    // Vignette and grain.
    let v = in.uv - 0.5;
    let vig = 1.0 - dot(v * vec2<f32>(u.texel.z, 1.0), v * vec2<f32>(u.texel.z, 1.0)) * u.extra.x * 0.9;
    mapped *= clamp(vig, 0.0, 1.0);

    // To the canvas: sRGB-ish gamma. The grain goes on after it, so it is
    // as faint in the dark as in the light (before the gamma, the darks
    // amplified it into visible noise).
    var outc = pow(clamp(mapped, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2));
    let g = hash(in.uv * vec2<f32>(1931.0, 1373.0) + fract(u.texel.w * 7.13)) - 0.5;
    outc = clamp(outc + g * u.extra.y * 0.03, vec3<f32>(0.0), vec3<f32>(1.0));
    return vec4<f32>(outc, 1.0);
}
