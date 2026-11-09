// The blob's jelly. The rig (BlobRig) is drawn into a texture in material
// colours (see ../tools/make_scene.py); these passes turn it into a soft,
// glossy, translucent jelly:
//
//   fs_narrow  half size: the material, blurred a little. R body, G horn,
//              B coverage. The edges' roundness.
//   fs_mid     quarter size: the narrow blur blurred again, wider.
//   fs_wide    quarter size: the mid blur blurred wide. The dome.
//   fs_final   full size: heights from both blurs give the surface's
//              normals; the jelly is lit from them. Light through it (deeper
//              red where it's thick), a glow where light gathers inside the
//              bottom, a fresnel rim, a glossy highlight, a darker painted
//              edge, and its shadow and the red light it throws on the floor.
//
// Every pass draws one full-screen triangle. Colours out are premultiplied.

struct Params {
    texel: vec4<f32>,    // 1/width, 1/height (full size), aspect, time
    light: vec4<f32>,    // light direction xyz (y down, toward the viewer is +z), gloss
    body: vec4<f32>,     // body rgb, translucency
    deep: vec4<f32>,     // deep rgb, outline
    glow: vec4<f32>,     // inner glow rgb, glow
    horn: vec4<f32>,     // horn rgb, paint (watercolour mottling)
    ink: vec4<f32>,      // ink rgb, rim
    blush: vec4<f32>,    // blush rgb, shadow
    back: vec4<f32>,     // backdrop rgb (what the jelly is seen against), refraction
    shadow: vec4<f32>,   // floor: centre x, y (uv), half width (uv), squash
    radius: vec4<f32>,   // narrow, mid, wide blur radius (uv of height), normal step (uv)
};

@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var material: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;
@group(0) @binding(3) var narrowTex: texture_2d<f32>;
@group(0) @binding(4) var wideTex: texture_2d<f32>;
@group(0) @binding(5) var midTex: texture_2d<f32>;

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

// --- Material --------------------------------------------------------------

struct Mat {
    cover: f32,
    body: f32,
    horn: f32,
    ink: f32,
    catchlight: f32,
    blush: f32,
};

fn readMaterial(uv: vec2<f32>) -> Mat {
    let s = textureSampleLevel(material, smp, uv, 0.0);
    var m: Mat;
    m.cover = s.a;
    let c = s.rgb / max(s.a, 0.0001);
    let g = clamp(c.g, 0.0, 1.0);
    let b = clamp(c.b, 0.0, 1.0);
    m.catchlight = g * b;
    m.horn = g * (1.0 - b);
    m.ink = b * (1.0 - g);
    m.blush = clamp((c.r - 0.5) * 2.0, 0.0, 1.0);
    m.body = 1.0 - m.horn;
    return m;
}

// 24 taps on a golden-angle spiral.
fn spiral(i: i32) -> vec2<f32> {
    let fi = f32(i);
    let a = fi * 2.39996;
    let r = sqrt((fi + 0.5) / 24.0);
    return vec2<f32>(cos(a), sin(a)) * r;
}

@fragment
fn fs_narrow(in: VertexOutput) -> @location(0) vec4<f32> {
    let rad = vec2<f32>(u.radius.x / u.texel.z, u.radius.x);
    var acc = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0; i < 24; i++) {
        let t = spiral(i);
        let w = 1.0 - dot(t, t) * 0.6;
        let m = readMaterial(in.uv + t * rad);
        acc += vec3<f32>(m.cover * m.body, m.cover * m.horn, m.cover) * w;
        wsum += w;
    }
    let m0 = readMaterial(in.uv);
    acc += vec3<f32>(m0.cover * m0.body, m0.cover * m0.horn, m0.cover);
    wsum += 1.0;
    return vec4<f32>(acc / wsum, 1.0);
}

fn blurOf(tex: texture_2d<f32>, uv: vec2<f32>, radius: f32) -> vec4<f32> {
    let rad = vec2<f32>(radius / u.texel.z, radius);
    var acc = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0; i < 24; i++) {
        let t = spiral(i);
        let w = 1.0 - dot(t, t) * 0.5;
        acc += textureSampleLevel(tex, smp, uv + t * rad, 0.0).rgb * w;
        wsum += w;
    }
    acc += textureSampleLevel(tex, smp, uv, 0.0).rgb;
    wsum += 1.0;
    return vec4<f32>(acc / wsum, 1.0);
}

@fragment
fn fs_mid(in: VertexOutput) -> @location(0) vec4<f32> {
    return blurOf(narrowTex, in.uv, u.radius.y);
}

@fragment
fn fs_wide(in: VertexOutput) -> @location(0) vec4<f32> {
    return blurOf(midTex, in.uv, u.radius.z);
}

// --- Surface ---------------------------------------------------------------

// The body's height: rounded at the edges by the narrow blur, domed by the
// wide one.
fn bodyHeight(uv: vec2<f32>) -> f32 {
    let n = textureSampleLevel(narrowTex, smp, uv, 0.0).r;
    let m = textureSampleLevel(midTex, smp, uv, 0.0).r;
    let w = textureSampleLevel(wideTex, smp, uv, 0.0).r;
    return sqrt(max(n, 0.0)) * 0.35 + sqrt(max(m, 0.0)) * 0.35 + w * 0.8;
}

fn hornHeight(uv: vec2<f32>) -> f32 {
    let n = textureSampleLevel(narrowTex, smp, uv, 0.0).g;
    return sqrt(max(n, 0.0));
}

fn hash(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(123.34, 456.21));
    let r = q + dot(q, q + 45.32);
    return fract(r.x * r.y);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        v += noise(q) * a;
        q = q * 2.03 + vec2<f32>(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

fn normalFrom(h: f32, hx: f32, hy: f32, strength: f32) -> vec3<f32> {
    return normalize(vec3<f32>((h - hx) * strength, (h - hy) * strength, 1.0));
}

@fragment
fn fs_final(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let px = vec2<f32>(u.radius.w / u.texel.z, u.radius.w);
    let m = readMaterial(uv);

    // --- The floor: a soft shadow, and red light thrown through the jelly.
    let sh = u.shadow;
    let d = (uv - sh.xy) / vec2<f32>(sh.z, sh.z * 0.13 * u.texel.z);
    let r2 = dot(d, d);
    let contact = exp(-r2 * 2.6);
    let wideShadow = exp(-r2 * 0.9);
    var floorA = (contact * 0.42 + wideShadow * 0.16) * u.blush.w;
    var floorRGB = u.deep.rgb * 0.55 * floorA;
    // The caustic: light focused through the dome lands just inside the shadow.
    let cd = (uv - sh.xy - vec2<f32>(sh.z * 0.12, -sh.z * 0.02 * u.texel.z)) / vec2<f32>(sh.z * 0.55, sh.z * 0.07 * u.texel.z);
    let caustic = exp(-dot(cd, cd) * 1.6) * 0.7 * u.glow.w * u.blush.w;
    floorRGB = floorRGB * (1.0 - caustic) + u.glow.rgb * caustic;
    floorA = floorA + caustic * (1.0 - floorA);

    if (m.cover <= 0.001) {
        return vec4<f32>(floorRGB, floorA);
    }

    // --- The surface.
    let h = bodyHeight(uv);
    let gx = bodyHeight(uv - vec2<f32>(px.x, 0.0)) - bodyHeight(uv + vec2<f32>(px.x, 0.0));
    let gy = bodyHeight(uv - vec2<f32>(0.0, px.y)) - bodyHeight(uv + vec2<f32>(0.0, px.y));
    var n = normalize(vec3<f32>(gx / (2.0 * px.y) * 0.13, gy / (2.0 * px.y) * 0.13, 1.0));

    let hh = hornHeight(uv);
    let hhx = hornHeight(uv + vec2<f32>(px.x, 0.0));
    let hhy = hornHeight(uv + vec2<f32>(0.0, px.y));
    let nHorn = normalFrom(hh, hhx, hhy, 22.0);
    n = normalize(mix(n, nHorn, m.horn));

    let l = normalize(u.light.xyz);
    let v = vec3<f32>(0.0, 0.0, 1.0);
    let hv = normalize(l + v);
    let ndl = dot(n, l);
    let ndh = max(dot(n, hv), 0.0);
    let fres = pow(1.0 - max(n.z, 0.0), 2.5);
    let narrow = textureSampleLevel(narrowTex, smp, uv, 0.0);

    // --- Jelly: light through it, tinted by how much jelly it passed.
    // The thickness is read where the view ray bends to (refraction), so
    // the inside shifts like a lens as the surface moves.
    let bend = n.xy * u.back.w * 0.06;
    let thick = clamp(bodyHeight(uv + bend), 0.0, 1.6);
    let absorb = max(vec3<f32>(1.0) - u.body.rgb, vec3<f32>(0.02)) * 3.2;
    let through = u.back.rgb * exp(-absorb * (0.25 + thick * 1.35));
    // Its own colour where light scatters inside, deeper where it's thick.
    let wrap = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
    // Lit from above: the top of the jelly is full of light, the far side
    // and the thick lower body sink to the deep colour.
    let up = clamp(-n.y, 0.0, 1.0);
    let depth = clamp(smoothstep(0.4, 1.35, thick) * 0.6 + (1.0 - wrap) * 0.75 - up * 0.3, 0.0, 1.0);
    let bright = min(u.body.rgb * 1.22 + vec3<f32>(0.05, 0.02, 0.03), vec3<f32>(1.0));
    let scatter = mix(bright, u.deep.rgb, depth);
    var col = scatter * (0.62 + 0.48 * wrap);
    // Thin jelly at the rim lets the light behind it through.
    let thin = 1.0 - smoothstep(0.15, 0.85, thick);
    col = mix(col, through, thin * 0.55 * u.body.w);

    // Watercolour: pigment pooling unevenly, a little bloom of colour.
    let p = fbm(uv * vec2<f32>(u.texel.z, 1.0) * 7.0);
    let p2 = fbm(uv * vec2<f32>(u.texel.z, 1.0) * 19.0 + vec2<f32>(3.1, 1.7));
    col *= 1.0 + (p - 0.5) * 0.32 * u.horn.w + (p2 - 0.5) * 0.12 * u.horn.w;

    // Light gathers inside the bottom, and shines out through it.
    let bottom = clamp(n.y, 0.0, 1.0);
    let inside = smoothstep(0.05, 0.6, narrow.r);
    let gather = pow(bottom, 1.4) * inside * (1.0 - smoothstep(0.6, 1.0, narrow.r) * 0.6);
    col += u.glow.rgb * gather * 1.05 * u.glow.w;
    // A soft core glow, low in the body.
    let core = smoothstep(0.6, 1.4, thick) * smoothstep(-0.2, 0.6, n.y + 0.3);
    col += u.glow.rgb * core * 0.16 * u.glow.w;

    // Bubbles, suspended inside and drifting up very slowly: a bright rim
    // on the lit side and a soft dark edge, seen through the jelly.
    let bubbleSpace = (uv + bend * 0.5) * vec2<f32>(u.texel.z, 1.0);
    var bub = 0.0;
    var bubDark = 0.0;
    for (var i = 0; i < 6; i++) {
        let fi = f32(i);
        let seed = vec2<f32>(hash(vec2<f32>(fi, 1.3)), hash(vec2<f32>(fi, 7.9)));
        let rise = fract(seed.y + u.texel.w * (0.006 + 0.004 * seed.x));
        // On the flanks, clear of the face.
        let side = select(0.2 + seed.x * 0.14, 0.66 + seed.x * 0.14, i % 2 == 1);
        let c = vec2<f32>(side, 0.84 - rise * 0.22) * vec2<f32>(u.texel.z, 1.0);
        let r = (0.006 + 0.008 * hash(vec2<f32>(fi, 3.1)));
        let dist = length(bubbleSpace - c);
        let ring = smoothstep(r, r * 0.55, dist);
        let lit = smoothstep(r * 0.9, r * 0.35, length(bubbleSpace - c + vec2<f32>(r * 0.35, r * 0.4)));
        let fade = smoothstep(0.0, 0.15, rise) * (1.0 - smoothstep(0.75, 1.0, rise));
        bub += (ring - lit * 0.75) * fade;
        bubDark += lit * fade;
    }
    let inBody = smoothstep(0.55, 0.9, thick) * (1.0 - m.ink) * (1.0 - m.horn);
    col = mix(col, col * 0.78, clamp(bubDark, 0.0, 1.0) * 0.35 * inBody);
    col += mix(u.glow.rgb, vec3<f32>(1.0), 0.5) * clamp(bub, 0.0, 1.0) * 0.22 * inBody;

    // Blush.
    col = mix(col, u.blush.rgb, m.blush * 0.55);

    // The edge: lighter where the surface turns away (fresnel), with a thin
    // darker line of pooled pigment right at the rim.
    col = mix(col, mix(u.body.rgb, mix(u.glow.rgb, vec3<f32>(1.0), 0.5), 0.6), fres * 0.55 * u.ink.w);
    let rimLine = 1.0 - smoothstep(0.08, 0.42, narrow.b);
    col = mix(col, u.deep.rgb * 0.75, rimLine * u.deep.w);

    // Horns: dense, dark, glossy.
    let hornWrap = clamp(ndl * 0.6 + 0.4, 0.0, 1.0);
    let hornCol = u.horn.rgb * (0.55 + 0.75 * hornWrap) + vec3<f32>(0.35, 0.08, 0.16) * fres * 0.8;
    col = mix(col, hornCol, m.horn);

    // The face: ink sits just under the skin, so the gloss still crosses it.
    col = mix(col, u.ink.rgb, m.ink * 0.96);

    // --- Gloss: a broad soft sheen, and a crisp window highlight.
    let gloss = u.light.w;
    let sheen = pow(ndh, 18.0) * 0.32;
    let spec = pow(ndh, 90.0);
    let window = smoothstep(0.32, 0.62, spec) * 0.8;
    let sparkle = smoothstep(0.82, 0.9, pow(ndh, 260.0));
    var hi = (sheen + window + sparkle * 0.6) * gloss;
    // A small secondary kick on the lower opposite side.
    let l2 = normalize(vec3<f32>(-u.light.x * 0.8, 0.55, 0.45));
    let ndh2 = max(dot(n, normalize(l2 + v)), 0.0);
    hi += smoothstep(0.3, 0.9, pow(ndh2, 24.0)) * fres * 0.35 * gloss * (1.0 - m.horn * 0.5);
    col += vec3<f32>(1.0, 0.95, 0.96) * hi;
    col = mix(col, vec3<f32>(1.0, 0.99, 0.98), m.catchlight);

    // Over the floor.
    let a = m.cover;
    let rgb = col * a + floorRGB * (1.0 - a);
    let outA = a + floorA * (1.0 - a);
    return vec4<f32>(rgb, outA);
}
