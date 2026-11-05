// The dreamy finish for the lake (from Shishupalgarh's): reads the scene (ruins.wgsl stores colour
// as sqrt(c / (1 + c)) and, in alpha, how out of focus each pixel is) and
// its blurs (blur.wgsl: the focus blur at half size, a wide one at a
// quarter), and adds
//   bloom      bright light (the sun, the sky, sunlit stone) spills softly
//   glow       an overall soft focus, screen-blended (the "Orton" look)
//   focus      depth of field: out-of-focus pixels take the blur
// then tone maps, warms, vignettes and adds a fine grain.
//
// Then a watercolour finish (`paint`): the image is flattened into soft
// patches of colour (a Kuwahara filter, so detail turns to brush marks),
// its edges wobble a little as if drawn by hand, pigment pools darker
// along the edges of each wash, the washes are uneven, and it all sits on
// grained paper, where the pigment settles into the tooth in the darks.

struct Params {
    texel: vec4<f32>,  // 1/width, 1/height, aspect, time
    look: vec4<f32>,   // bloom, glow, depth of field, exposure
    grade: vec4<f32>,  // tint rgb, saturation
    extra: vec4<f32>,  // vignette, grain, bloom threshold, blur radius
    leak: vec4<f32>,   // light leak rgb (linear), amount
    sun: vec4<f32>,    // the sun on screen (uv), shafts strength, 1 if ahead
    paint: vec4<f32>,  // watercolour amount, paper, brush size (px), edge pooling
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

fn hash2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q += dot(q, q.yx + 33.33);
    return fract((q.x + q.y) * q.x);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

fn lumaOf(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// A Kuwahara filter: of the four quadrants round the pixel, the colour of
// the one that varies least, so flat areas smooth into washes and edges
// stay crisp, like strokes of a brush.
fn kuwahara(uv: vec2<f32>, size: f32) -> vec3<f32> {
    let stepUv = u.texel.xy * size / 3.0;
    // The quadrants turn with a slowly varying angle, so strokes have
    // directions rather than a grid.
    let a = noise2(uv * vec2<f32>(7.0 * u.texel.z, 7.0)) * 6.283;
    let ca = cos(a);
    let sa = sin(a);
    var best = vec3<f32>(0.0);
    var bestVar = 1e9;
    for (var q = 0; q < 4; q++) {
        let sx = select(-1.0, 1.0, (q & 1) == 1);
        let sy = select(-1.0, 1.0, (q & 2) == 2);
        var sum = vec3<f32>(0.0);
        var sum2 = 0.0;
        var sumL = 0.0;
        for (var j = 0; j <= 3; j++) {
            for (var i = 0; i <= 3; i++) {
                let o = vec2<f32>(f32(i) * sx, f32(j) * sy);
                let c = fetch(uv + vec2<f32>(o.x * ca - o.y * sa, o.x * sa + o.y * ca) * stepUv).rgb;
                let l = lumaOf(c / (1.0 + c));
                sum += c;
                sumL += l;
                sum2 += l * l;
            }
        }
        let mean = sumL / 16.0;
        let variance = sum2 / 16.0 - mean * mean;
        if (variance < bestVar) {
            bestVar = variance;
            best = sum / 16.0;
        }
    }
    return best;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let paint = u.paint.x;
    // Hand-drawn edges: the image wobbles a hair, slowly varying over it.
    let wob = vec2<f32>(noise2(in.uv * vec2<f32>(18.0, 11.0)), noise2(in.uv * vec2<f32>(13.0, 19.0) + 7.0)) - 0.5;
    let uv = in.uv + wob * 0.004 * paint;
    var center = fetch(uv);
    if (paint > 0.0) {
        center = vec4<f32>(mix(center.rgb, kuwahara(uv, u.paint.z), clamp(paint, 0.0, 1.0)), center.a);
    }
    let threshold = u.extra.z;
    // The blurs, drawn small by blur.wgsl and smoothed by the sampler.
    let nearS = textureSampleLevel(nearTex, smp, uv, 0.0);
    let blurred = decode(nearS.rgb);
    let wide = decode(textureSampleLevel(wideTex, smp, uv, 0.0).rgb);
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
    mapped = mapped * 0.96 + vec3<f32>(0.03, 0.02, 0.03);
    // A gentle S-curve, so the mist stays luminous and the near greens
    // keep their depth.
    mapped = mix(mapped, mapped * mapped * (3.0 - 2.0 * mapped), 0.3);

    // Watercolour: pigment pools along the edges of each wash (where the
    // image differs from its blur), the washes are a little uneven, and the
    // paper's tooth catches pigment in the darks.
    if (paint > 0.0) {
        let soft = aces(blurred * exposure);
        // Only on the darker side of an edge: the wash's rim.
        let edge = smoothstep(0.01, 0.12, lumaOf(soft) - lumaOf(mapped));
        mapped *= 1.0 - edge * u.paint.w * 0.3 * paint;
        let wash = noise2(in.uv * vec2<f32>(5.0 * u.texel.z, 5.0)) * 0.6 + noise2(in.uv * vec2<f32>(13.0 * u.texel.z, 13.0)) * 0.4;
        mapped *= 1.0 + (wash - 0.5) * 0.07 * paint;
        let px = in.uv / u.texel.xy;
        let tooth = noise2(px / 2.2) * 0.55 + noise2(px / 0.9) * 0.25 + noise2(px * vec2<f32>(0.08, 0.6)) * 0.2;
        let pigment = 1.0 - lumaOf(mapped);
        mapped *= 1.0 - (tooth - 0.5) * (0.03 + 0.1 * pigment) * u.paint.y;
        // Paper shows through the lightest washes.
        mapped = mix(mapped, vec3<f32>(0.98, 0.95, 0.88), smoothstep(0.85, 1.0, lumaOf(mapped)) * 0.25 * u.paint.y);
    }

    // Vignette and grain.
    let v = in.uv - 0.5;
    let vig = 1.0 - dot(v * vec2<f32>(u.texel.z, 1.0), v * vec2<f32>(u.texel.z, 1.0)) * u.extra.x * 0.9;
    mapped *= clamp(vig, 0.0, 1.0);
    let g = hash(in.uv * vec2<f32>(1931.0, 1373.0) + fract(u.texel.w * 7.13)) - 0.5;
    mapped += g * u.extra.y * 0.05;

    // To the canvas: sRGB-ish gamma.
    let outc = pow(clamp(mapped, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2));
    return vec4<f32>(outc, 1.0);
}
