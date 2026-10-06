// Madhubani pass 2: turn the flattened photo into a folk-art print.
//
//   mask      the subject mask comes from pass 1 (alpha)
//   bands     inside the mask, luminance splits into five tone bands, each
//             with its own pattern; bands 1–3 take one of seven harmony inks
//             (generated in Madhubani.luau from a colour scheme), picked
//             from the band, the photo's hue there and a slow spatial drift,
//             so every region is one ink but neighbours differ (darkest first): ink with
//             fine light feather lines, light stripes, chevrons, dots, sparse dots on paper
//   patterns  run along the local contour, snapped to four angles so they
//             form crisp patches instead of swirling
//   ink       outlines where bands meet, plus a double outline around the bird
//   dither    the colour layer's bands are chosen through a 4×4 Bayer
//             matrix, so band edges break into a grain of coloured dots
//   paper     cream with grain outside the bird; the colour layer is nudged
//             off the ink a touch, like a misregistered print
//
// `params.x` (amount) blends from the original photo (0) to the print (1).
//
// Bindings group 0:
//   0: UBO (176 bytes, below)
//   1: flattened texture (pass 1)
//   2: sampler
//   3: source photo (for the blend)

struct Params {
    texel: vec2<f32>,
    lineWidth: f32,     // texels
    patternScale: f32,  // pattern period, texels
    params: vec4<f32>,  // amount, dither, unused × 2
    ink: vec4<f32>,
    paper: vec4<f32>,
    inks: array<vec4<f32>, 7>,  // the colour inks
};

@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var flatTex: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;
@group(0) @binding(3) var photo: texture_2d<f32>;

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

fn flatAt(p: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(flatTex, smp, clamp(p, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn lum(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn alphaAt(p: vec2<f32>) -> f32 {
    return textureSampleLevel(flatTex, smp, clamp(p, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;
}

// Subject mask from pass 1's alpha, averaged over a small cross so pinholes
// fill in and stray specks drop out.
fn inside(p: vec2<f32>) -> bool {
    let d = 3.0 * u.texel;
    let a = alphaAt(p) * 2.0
        + alphaAt(p + vec2<f32>(d.x, 0.0)) + alphaAt(p - vec2<f32>(d.x, 0.0))
        + alphaAt(p + vec2<f32>(0.0, d.y)) + alphaAt(p - vec2<f32>(0.0, d.y));
    return a / 6.0 > 0.45;
}

// Hue 0..1 of an RGB colour.
fn hue(c: vec3<f32>) -> f32 {
    let mx = max(c.r, max(c.g, c.b));
    let mn = min(c.r, min(c.g, c.b));
    let d = mx - mn;
    if (d < 1e-4) {
        return 0.0;
    }
    var h = 0.0;
    if (mx == c.r) {
        h = (c.g - c.b) / d;
    } else if (mx == c.g) {
        h = (c.b - c.r) / d + 2.0;
    } else {
        h = (c.r - c.g) / d + 4.0;
    }
    return fract(h / 6.0);
}

// Smooth value noise, for the slow drift between inks.
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// One of the seven inks.
fn inkAt(i: i32) -> vec3<f32> {
    return u.inks[((i % 7) + 7) % 7].rgb;
}

// 4×4 Bayer threshold in 0..1, in 2-texel blocks.
fn bayer(px: vec2<f32>) -> f32 {
    let m = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    let c = vec2<i32>(floor(px * 0.5)) & vec2<i32>(3, 3);
    return (m[c.y * 4 + c.x] + 0.5) / 16.0;
}

// Tone band (0 darkest .. 4 lightest) from luminance softened over a ring,
// so bands form broad regions instead of flickering patch to patch. `jitter`
// shifts the luminance before banding (the dither).
fn band(p: vec2<f32>, jitter: f32) -> f32 {
    let r = 2.5 * u.lineWidth * u.texel;
    var l = lum(flatAt(p)) * 2.0;
    for (var i = 0; i < 8; i++) {
        let a = f32(i) * 0.78539816;
        l += lum(flatAt(p + vec2<f32>(cos(a), sin(a)) * r));
    }
    l = clamp((l / 10.0 - 0.06) / 0.84 + jitter, 0.0, 1.0);
    return min(floor(l * 5.0), 4.0);
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let px = uv / u.texel;
    let isIn = inside(uv);

    // Distance (in line widths) to the mask edge, from rings of 8 samples.
    var edgeRing = 99.0;
    for (var k = 1; k <= 5; k++) {
        for (var a = 0; a < 8; a++) {
            let ang = f32(a) * 0.78539816;
            let off = vec2<f32>(cos(ang), sin(ang)) * f32(k) * u.lineWidth * u.texel;
            if (inside(uv + off) != isIn && edgeRing > 90.0) {
                edgeRing = f32(k);
            }
        }
    }

    // Paper with grain.
    let grain = (hash(floor(px)) - 0.5) * 0.06;
    var color = u.paper.rgb + vec3<f32>(grain);

    if (isIn) {
        // Contour direction from the luminance gradient, snapped to 45°.
        let g = 3.0 * u.texel;
        let gx = lum(flatAt(uv + vec2<f32>(g.x, 0.0))) - lum(flatAt(uv - vec2<f32>(g.x, 0.0)));
        let gy = lum(flatAt(uv + vec2<f32>(0.0, g.y))) - lum(flatAt(uv - vec2<f32>(0.0, g.y)));
        var ang = 0.0;
        if (abs(gx) + abs(gy) > 0.01) {
            ang = atan2(gy, gx);
        }
        ang = round(ang / 0.78539816) * 0.78539816;
        let n = vec2<f32>(cos(ang), sin(ang));       // across the contour
        let along = vec2<f32>(-n.y, n.x);           // along the contour
        let P = max(u.patternScale, 2.0);
        let s = dot(px, along) / P;
        let t = dot(px, n) / P;

        // Colour layer, nudged off the ink like a misregistered print.
        let jitter = (bayer(px) - 0.5) * u.params.y;
        let b = band(uv + u.texel * vec2<f32>(1.2, 0.8), jitter);
        // Which ink this region takes: band + hue + slow drift.
        let sampleUv = uv + u.texel * vec2<f32>(1.2, 0.8);
        let h = hue(flatAt(sampleUv));
        let drift = noise(sampleUv * vec2<f32>(3.0, 4.2));
        let pick = i32(b) * 2 + i32(floor(h * 7.0)) + i32(floor(drift * 3.0));
        let main = inkAt(pick);
        // The next slot is always another harmony hue: a deliberate contrast.
        let accent = inkAt(pick + 1);
        if (b < 0.5) {
            color = u.ink.rgb;
            if (fract(t * 1.5) < 0.16) {
                color = accent;
            }
        } else if (b < 1.5) {
            color = main;
            if (fract(t) < 0.28) {
                color = u.paper.rgb;
            }
        } else if (b < 2.5) {
            color = main;
            let z = t + abs(fract(s * 0.5) - 0.5) * 2.0;
            if (fract(z) < 0.3) {
                color = u.ink.rgb;
            }
        } else if (b < 3.5) {
            color = main;
            let f = fract(vec2<f32>(s, t)) - 0.5;
            if (length(f) < 0.24) {
                color = accent;
            }
        } else {
            color = u.paper.rgb;
            let f = fract(vec2<f32>(s, t) * 0.6) - 0.5;
            if (length(f) < 0.16) {
                color = accent;
            }
        }
        color += vec3<f32>(grain * 0.5);

        // Ink where tone bands meet.
        let bc = band(uv, 0.0);
        let w = u.lineWidth * u.texel;
        let o = array<vec2<f32>, 4>(
            vec2<f32>(w.x, 0.0), vec2<f32>(-w.x, 0.0),
            vec2<f32>(0.0, w.y), vec2<f32>(0.0, -w.y),
        );
        for (var i = 0; i < 4; i++) {
            if (abs(band(uv + o[i], 0.0) - bc) > 0.5) {
                color = u.ink.rgb;
            }
        }
    }

    // Double outline around the bird: one on the edge, one just outside.
    if (edgeRing <= 1.0 || (!isIn && edgeRing > 2.5 && edgeRing < 3.5)) {
        color = u.ink.rgb;
    }

    let original = textureSampleLevel(photo, smp, uv, 0.0).rgb;
    return vec4<f32>(mix(original, color, clamp(u.params.x, 0.0, 1.0)), 1.0);
}
