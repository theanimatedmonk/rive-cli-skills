// The Birdie studio: two form factors of a wildlife tracker shot as
// product photography, on turntables in an infinity cove.
//
//   vs_product / fs_product   the products (birdie.bin): each vertex placed
//                             by its frame (a body or a lid, so lids open
//                             for the exploded view), lit by a studio of
//                             softboxes: a big key with soft shadows, a
//                             fill card and two rim strips, mirrored in
//                             every glossy surface. Materials are painted
//                             here, smooth and clean: a yellow panel, its
//                             carving shaded deeper, in a deep blue satin
//                             shell; a pale maple-cream body under a
//                             deep walnut roof lacquered to a gloss. Then the
//                             electronics' foil, solder mask, gold and
//                             wire, and stone plinths flecked like
//                             terrazzo.
//   vs_mirror / fs_mirror     the same, mirrored under the floor and faded,
//                             blended over it: the floor's gloss (after
//                             fs_depth has laid down their depth, so only
//                             the nearest surface shows).
//   vs_shadow                 the products seen from the key, for shadows.
//   vs_sky / fs_sky           the cove: the floor (a plane, traced per
//                             pixel) with its light pool, shadows, contact
//                             shadows round each plinth and a sheen from
//                             the key; the backdrop rising behind it,
//                             tinted toward each product's hue on its side.
//
// Colour is written as sqrt(c / (1 + c)), with the depth-of-field blur in
// alpha, for blur.wgsl and post.wgsl.

struct Uniforms {
    viewProj: mat4x4<f32>,
    lightViewProj: mat4x4<f32>,
    camPos: vec4<f32>,       // xyz, time
    keyDir: vec4<f32>,       // toward the key, its strength
    keyColor: vec4<f32>,     // rgb, shadow softness (texels)
    fillDir: vec4<f32>,      // toward the fill, its strength
    fillColor: vec4<f32>,    // rgb, 0
    rimDir: vec4<f32>,       // toward the rim strip, its strength
    rimColor: vec4<f32>,     // rgb, 0
    bgTop: vec4<f32>,        // the backdrop high up, the glow behind
    bgLow: vec4<f32>,        // ... at the horizon and the floor's far reaches, the floor's gloss
    floorColor: vec4<f32>,   // the floor in the light pool, the pool's size (metres)
    viewport: vec4<f32>,     // width, height, 1/width, 1/height
    camRight: vec4<f32>,     // xyz, tan of half the horizontal fov
    camUp: vec4<f32>,        // xyz, tan of half the vertical fov
    camFwd: vec4<f32>,       // xyz, focus distance
    look: vec4<f32>,         // depth of field, 0, ambient, how dark shadows fall on the floor
    panel: vec4<f32>,        // the paints (linear rgb), 0: the birdhouse's panel
    shell: vec4<f32>,        // ... its shell
    body: vec4<f32>,         // the turned birdhouse's body
    roof: vec4<f32>,         // ... its roof
    plinth: vec4<f32>,
    frames: array<mat4x4<f32>, 4>,   // birdhouse body, lid; turned body, roof
    spots: array<vec4<f32>, 2>,      // per product on the floor: x, z, plinth radius, 0
    feet: array<vec4<f32>, 2>,       // per product, its footprint (body frame): centre x, z, half x, z
    tintLeft: vec4<f32>,     // the backdrop's tint on the left of the frame, how much
    tintRight: vec4<f32>,    // ... on the right
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var shadowMap: texture_depth_2d;
@group(0) @binding(2) var shadowSmp: sampler_comparison;

const PI = 3.14159265;

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
    return clamp(abs(1.0 - d / u.camFwd.w) * 1.6, 0.0, 1.0) * u.look.x;
}

// ---------------------------------------------------------------------------
// The studio's light

// A softbox seen along d: 1 inside a w x h card (in tangents) facing axis,
// its edge softened by s.
fn softbox(d: vec3<f32>, axis: vec3<f32>, w: f32, h: f32, s: f32) -> f32 {
    let c = dot(d, axis);
    let up0 = select(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), abs(axis.y) > 0.95);
    let right = normalize(cross(up0, axis));
    let up = cross(axis, right);
    let x = dot(d, right) / max(c, 1e-3);
    let y = dot(d, up) / max(c, 1e-3);
    let inside = (1.0 - smoothstep(w - s, w + s, abs(x))) * (1.0 - smoothstep(h - s, h + s, abs(y)));
    // Brighter at the centre, as a real diffuser.
    let falloff = 1.0 - 0.25 * clamp((x * x) / (w * w + 1e-4) + (y * y) / (h * h + 1e-4), 0.0, 1.0);
    return inside * falloff * step(0.0, c);
}

fn rimMirror() -> vec3<f32> {
    return normalize(vec3<f32>(-u.rimDir.x, u.rimDir.y * 0.9, u.rimDir.z));
}

// What a glossy surface mirrors along d, at a roughness: the key (apart,
// so shadow can take it), and everything else: the fill, the rims, a top
// panel and the dark cove.
struct Env {
    key: vec3<f32>,
    rest: vec3<f32>,
};

fn env(d: vec3<f32>, rough: f32) -> Env {
    var e: Env;
    let r2 = rough * rough;
    let s = 0.015 + r2 * 1.4;
    let k = 1.0 / (1.0 + r2 * 9.0);
    e.key = u.keyColor.rgb * u.keyDir.w * softbox(d, u.keyDir.xyz, 0.62, 0.42, s) * 2.2 * k;
    var rest = u.fillColor.rgb * u.fillDir.w * softbox(d, u.fillDir.xyz, 0.5, 0.7, s) * 1.4 * k;
    rest += u.rimColor.rgb * u.rimDir.w * (softbox(d, u.rimDir.xyz, 0.06, 1.1, s) + 0.55 * softbox(d, rimMirror(), 0.06, 1.1, s)) * 3.0 * k;
    rest += u.keyColor.rgb * u.keyDir.w * softbox(d, normalize(vec3<f32>(0.1, 1.0, -0.25)), 0.55, 0.45, s) * 0.8 * k;
    // The cove: the backdrop above, the floor and its pool below.
    let floorLit = u.floorColor.rgb * (0.25 + 0.6 * u.keyDir.w * u.keyDir.y);
    rest += mix(floorLit * 0.5, u.bgTop.rgb, smoothstep(-0.25, 0.5, d.y)) * 0.55;
    e.rest = rest;
    return e;
}

// The key's shadow (1 lit), soft: 16 taps on a spiral.
fn keyShadow(p: vec3<f32>, n: vec3<f32>) -> f32 {
    let q = u.lightViewProj * vec4<f32>(p + n * 0.0006, 1.0);
    let uv = vec2<f32>(q.x * 0.5 + 0.5, 0.5 - q.y * 0.5);
    let depth = q.z - 0.0008;
    let texel = 1.0 / 2048.0;
    let spin = hash3(vec3<f32>(p * 9000.0)) * 6.283;
    var lit = 0.0;
    for (var i = 0; i < 16; i++) {
        let fi = f32(i);
        let a = fi * 2.39996 + spin;
        let r = sqrt((fi + 0.5) / 16.0) * u.keyColor.w;
        lit += textureSampleCompareLevel(shadowMap, shadowSmp, uv + vec2<f32>(cos(a), sin(a)) * r * texel, depth);
    }
    let inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return mix(1.0, lit / 16.0, inside);
}

// A surface, as painted.
struct Surface {
    base: vec3<f32>,
    rough: f32,
    metal: f32,
    coat: f32,
    emit: vec3<f32>,
    ao: f32,
    sheen: f32,
    wrap: f32,
    bump: f32,
};

fn light(s: Surface, p: vec3<f32>, n: vec3<f32>, v: vec3<f32>, shadow: f32) -> vec3<f32> {
    let nv = clamp(dot(n, v), 1e-3, 1.0);
    let w = s.wrap;
    let dk = clamp((dot(n, u.keyDir.xyz) + w) / (1.0 + w), 0.0, 1.0);
    let df = clamp((dot(n, u.fillDir.xyz) + w) / (1.0 + w), 0.0, 1.0);
    let dr = max(dot(n, u.rimDir.xyz), 0.0) + 0.55 * max(dot(n, rimMirror()), 0.0);
    // Light from all round: the studio's white from above, bounced off the
    // floor below.
    let sky = mix(u.floorColor.rgb * 0.35, u.keyColor.rgb, n.y * 0.5 + 0.5);
    var diffuse = u.keyColor.rgb * u.keyDir.w * dk * shadow
        + u.fillColor.rgb * u.fillDir.w * df
        + u.rimColor.rgb * u.rimDir.w * dr * 0.35
        + sky * u.look.z * s.ao;
    let r = reflect(-v, n);
    let f0 = mix(vec3<f32>(0.04), s.base, s.metal);
    let fr = f0 + (max(vec3<f32>(1.0 - s.rough), f0) - f0) * pow(1.0 - nv, 5.0);
    let e = env(r, s.rough);
    // Reflections close to the surface are dimmed in its creases.
    let specOcc = mix(s.ao, 1.0, 0.35);
    var c = diffuse * s.base * (1.0 - s.metal) + (e.key * mix(0.15, 1.0, shadow) + e.rest) * fr * specOcc;
    if (s.coat > 0.0) {
        let fc = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
        let ec = env(r, 0.06);
        c = c * (1.0 - fc * s.coat) + (ec.key * shadow + ec.rest) * fc * s.coat * specOcc;
    }
    // Soft-touch and cloth-like surfaces catch light at grazing angles.
    c += s.sheen * pow(1.0 - nv, 3.0) * (u.rimColor.rgb * u.rimDir.w * 0.25 + u.keyColor.rgb * 0.05) * s.ao;
    return c + s.emit;
}

// ---------------------------------------------------------------------------
// Painting

fn paint(mat: u32, product: u32, p: vec3<f32>, cav: f32) -> Surface {
    var s: Surface;
    s.base = vec3<f32>(0.5);
    s.rough = 0.5;
    s.metal = 0.0;
    s.coat = 0.0;
    s.emit = vec3<f32>(0.0);
    s.ao = clamp(1.0 - max(cav, 0.0) * 0.7, 0.25, 1.0);
    s.sheen = 0.0;
    s.wrap = 0.0;
    s.bump = 0.0;
    let grain = noise3(p * 4000.0);
    switch mat {
        case 0u: {
            // The LiPo pouch: silver-blue foil.
            s.base = vec3<f32>(0.2, 0.32, 0.6);
            s.rough = 0.28 + grain * 0.1;
            s.metal = 0.75;
        }
        case 1u: {
            // The XIAO boards: solder mask, gold pads.
            let pad = step(0.86, noise3(p * 1500.0));
            s.base = mix(vec3<f32>(0.02, 0.12, 0.05), vec3<f32>(1.0, 0.72, 0.3), pad);
            s.metal = pad;
            s.rough = mix(0.3, 0.2, pad);
            s.coat = 0.5 * (1.0 - pad);
        }
        case 2u, 7u: {
            s.base = vec3<f32>(0.018);
            s.rough = select(0.45, 0.28, mat == 7u);
        }
        case 3u: {
            s.base = vec3<f32>(0.78, 0.78, 0.8);
            s.metal = 1.0;
            s.rough = 0.22;
        }
        case 4u: {
            // The shell: smooth satin, a soft sheen rather than a mirror, so its
            // dark colour holds against the bright studio.
            s.base = u.shell.rgb;
            s.rough = 0.42;
            s.coat = 0.12;
            s.sheen = 0.0;
            s.wrap = 0.1;
        }
        case 5u: {
            // The panel: satin, its carved contours shaded deeper and richer
            // toward their floors, their crests catching the light.
            let depth = clamp(cav * 0.5 + 0.5, 0.0, 1.0);
            let deep = mix(u.panel.rgb, u.shell.rgb, 0.55) * 0.82;
            s.base = mix(u.panel.rgb, deep, smoothstep(0.15, 0.95, depth));
            s.ao = mix(1.0, 0.55, pow(depth, 1.4));
            s.rough = 0.32;
            s.coat = 0.35;
            s.wrap = 0.2;
        }
        case 8u: {
            s.base = vec3<f32>(1.0, 0.72, 0.32);
            s.metal = 1.0;
            s.rough = 0.25;
        }
        case 9u: {
            // The body: pale and smooth, a soft satin.
            s.base = u.body.rgb;
            s.rough = 0.36;
            s.coat = 0.35;
            s.wrap = 0.25;
        }
        case 10u: {
            // The roof, the perch and the finial: deep and lacquered to a
            // high gloss.
            s.base = u.roof.rgb;
            s.rough = 0.2;
            s.coat = 0.9;
            s.wrap = 0.05;
        }
        case 11u: {
            s.base = vec3<f32>(0.6, 0.03, 0.02);
            s.rough = 0.25;
            s.coat = 0.5;
        }
        default: {
            // The plinth: stone, honed, flecked like terrazzo, and darker
            // where the product stands on it.
            let cell = floor(p * 2200.0);
            let fleck = step(0.93, hash3(cell)) * hash3(cell + 3.1);
            s.base = u.plinth.rgb * (0.92 + 0.12 * noise3(p * 900.0)) * (1.0 - fleck * 0.55);
            s.rough = 0.62 - fleck * 0.3;
            let foot = u.feet[product];
            let q = abs(p.xz - foot.xy) - foot.zw;
            let d = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0);
            s.ao = 1.0 - 0.75 * exp(-max(d, 0.0) / 0.0025) * step(-0.0005, p.y);
        }
    }
    return s;
}

// ---------------------------------------------------------------------------
// The products

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec4<f32>,
    @location(2) ids: vec4<u32>,
};

struct ProductOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) local: vec3<f32>,
    @location(3) cav: f32,
    @location(4) @interpolate(flat) ids: vec4<u32>,
    @location(5) mirror: f32,
};

fn place(in: VertexIn, mirror: bool) -> ProductOut {
    var out: ProductOut;
    let m = u.frames[in.ids.y];
    var w = (m * vec4<f32>(in.position, 1.0)).xyz;
    var n = (m * vec4<f32>(in.normal.xyz, 0.0)).xyz;
    if (mirror) {
        w.y = -w.y;
        n.y = -n.y;
    }
    out.clip = u.viewProj * vec4<f32>(w, 1.0);
    out.world = w;
    out.normal = n;
    out.local = in.position;
    out.cav = in.normal.w;
    out.ids = in.ids;
    out.mirror = select(0.0, 1.0, mirror);
    return out;
}

@vertex
fn vs_product(in: VertexIn) -> ProductOut {
    return place(in, false);
}

@vertex
fn vs_mirror(in: VertexIn) -> ProductOut {
    return place(in, true);
}

fn shadeProduct(in: ProductOut) -> vec3<f32> {
    // The real point (a reflection is shaded where the product is).
    var p = in.world;
    var n = normalize(in.normal);
    var cam = u.camPos.xyz;
    if (in.mirror > 0.5) {
        p.y = -p.y;
        n.y = -n.y;
    }
    let v = normalize(cam - p);
    // Two-sided: the side facing the camera.
    if (dot(n, v) < 0.0) {
        n = -n;
    }
    let s = paint(in.ids.x, in.ids.z, in.local, in.cav);
    // A fine texture in the surface itself (fixed to it, so it turns with it).
    if (s.bump > 0.0) {
        let q = in.local * 2200.0;
        let j = vec3<f32>(noise3(q), noise3(q + 17.3), noise3(q + 41.9)) - 0.5;
        n = normalize(n + j * s.bump);
    }
    let shadow = keyShadow(p, n);
    return light(s, p, n, v, shadow);
}

@fragment
fn fs_product(in: ProductOut) -> @location(0) vec4<f32> {
    let c = shadeProduct(in);
    return encode(c, defocus(in.world));
}

@fragment
fn fs_mirror(in: ProductOut) -> @location(0) vec4<f32> {
    // Seen in the floor.
    let c = shadeProduct(in);
    let h = -in.world.y;
    let v = normalize(u.camPos.xyz - vec3<f32>(in.world.x, 0.0, in.world.z));
    let fres = 0.04 + 0.96 * pow(1.0 - clamp(v.y, 0.0, 1.0), 5.0);
    let strength = u.bgLow.w * mix(0.35, 1.0, fres) * exp(-h * 32.0);
    return vec4<f32>(encode(c, 0.0).rgb, clamp(strength, 0.0, 1.0));
}

// The reflections' depth, first, so only their nearest surface is blended
// over the floor (the colour is left as it is).
@fragment
fn fs_depth(in: ProductOut) -> @location(0) vec4<f32> {
    return vec4<f32>(0.0);
}

@vertex
fn vs_shadow(in: VertexIn) -> @builtin(position) vec4<f32> {
    let w = (u.frames[in.ids.y] * vec4<f32>(in.position, 1.0)).xyz;
    return u.lightViewProj * vec4<f32>(w, 1.0);
}

// ---------------------------------------------------------------------------
// The cove

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
fn fs_sky(in: SkyOut) -> @location(0) vec4<f32> {
    let dir = normalize(u.camFwd.xyz + u.camRight.xyz * in.ndc.x * u.camRight.w + u.camUp.xyz * in.ndc.y * u.camUp.w);
    let cam = u.camPos.xyz;
    // The backdrop: a sweep from the horizon up, a glow behind the
    // products.
    let h = dir.y;
    var back = mix(u.bgLow.rgb, u.bgTop.rgb, smoothstep(-0.02, 0.45, h));
    // Each side of the frame leans toward the product standing there.
    let side = smoothstep(-1.0, 1.0, in.ndc.x);
    let tint = mix(mix(vec3<f32>(1.0), u.tintLeft.rgb, u.tintLeft.w), mix(vec3<f32>(1.0), u.tintRight.rgb, u.tintRight.w), side);
    let behind = normalize(vec3<f32>(-u.camFwd.x, 0.0, -u.camFwd.z));
    let toward = normalize(vec3<f32>(dir.x, 0.0, dir.z));
    let glow = u.floorColor.rgb * pow(max(-dot(toward, behind), 0.0), 6.0) * u.bgTop.w;
    back += glow * exp(-max(h, 0.0) * 5.0);
    var c = back;
    var blur = u.look.x;
    if (dir.y < -1e-4) {
        let t = -cam.y / dir.y;
        let p = cam + dir * t;
        let n = vec3<f32>(0.0, 1.0, 0.0);
        let dist = length(p.xz);
        // The floor is the backdrop's colour, lifted to the floor's in the
        // light pool round the products, so it sweeps up into the backdrop
        // without a seam.
        let pool = exp(-pow(dist / u.floorColor.w, 2.0));
        let shadow = keyShadow(p, n);
        // Contact shadows round each plinth, tight at its foot, and a
        // wider soft one.
        var ao = 1.0;
        for (var i = 0; i < 2; i++) {
            let sp = u.spots[i];
            let d = max(length(p.xz - sp.xy) - sp.z, 0.0);
            ao *= 1.0 - u.look.w * (0.75 * exp(-d / 0.0018) + 0.3 * exp(-d / 0.014));
        }
        let shade = mix(1.0 - u.look.w, 1.0, shadow);
        var floorC = mix(u.bgLow.rgb, u.floorColor.rgb, pool) * shade * ao;
        // The floor's own sheen: the key and the top panel smeared across it.
        let r = reflect(dir, n);
        let e = env(r, 0.35);
        let fres = 0.04 + 0.96 * pow(1.0 - clamp(-dir.y, 0.0, 1.0), 5.0);
        floorC += (e.key * shadow + e.rest * 0.4) * fres * u.bgLow.w * ao * 0.35;
        // Into the cove: the floor melts into the backdrop with distance,
        // glow and all, so there's no line where they meet.
        let fade = smoothstep(0.25, 1.4, dist);
        c = mix(floorC, u.bgLow.rgb + glow, fade);
        blur = defocus(p);
    }
    return encode(c * tint, blur);
}
