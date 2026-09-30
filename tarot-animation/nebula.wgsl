// Stardust nebula behind the whole scene: domain-warped fbm clouds with a
// fine dust of twinkling specks. `heat` (0..1) warms the palette from indigo
// and teal to magenta, ember and gold, speeds the swirl up and pulls a glow
// toward the chosen card. `blast` (0..1) blows the clouds outward from the
// card and clears a hole around it. `mist` adds a soft drifting haze and
// `grain` a film-grain dither plus fine sand granules caught in the dust.
// The cursor bulges the clouds, dust and sand outward within `cursorRadius`.
// Output is premultiplied.

struct Params {
    time: f32,
    heat: f32,
    aspect: f32,   // width / height
    focusY: f32,   // card center, 0 = top of the artboard
    blast: f32,    // 0..1, clouds pushed away from the card
    grain: f32,    // film grain + sand granules strength
    mist: f32,     // drifting haze strength
    cursorAmt: f32,     // cursor strength x presence, 0 = no cursor
    cursorX: f32,       // cursor in uv, 0 = left
    cursorY: f32,       // cursor in uv, 0 = top
    cursorRadius: f32,  // in units of the artboard height
    pad0: f32,
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
    // uv with y = 0 at the top of the image.
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
        p = vec2<f32>(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6) + vec2<f32>(3.1, 1.7);
        amp = amp * 0.5;
    }
    return sum;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let heat = clamp(u.heat, 0.0, 1.0);
    let blast = clamp(u.blast, 0.0, 1.5);
    let focusUv = vec2<f32>(0.5, u.focusY);

    // Blast: each pixel samples the cloud from closer to the card, so the
    // clouds appear to be shoved outward. Near clouds move most.
    let c = (in.uv - focusUv) * vec2<f32>(u.aspect, 1.0);
    let rad = length(c);
    let dir = c / max(rad, 1e-4);
    let sampleRad = max(rad - blast * 0.5 * exp(-rad * 1.4), 0.0);
    let uvBlast = focusUv + dir * sampleRad / vec2<f32>(u.aspect, 1.0);

    // Cursor: sample from nearer the cursor so the sky bulges away from it,
    // and thin the dust a little under it.
    let toCursor = (uvBlast - vec2<f32>(u.cursorX, u.cursorY)) * vec2<f32>(u.aspect, 1.0);
    let cr = max(u.cursorRadius, 1e-3);
    let cursorFall = exp(-dot(toCursor, toCursor) / (cr * cr));
    // Saturates below 1 so a strong cursor bulges harder but never folds
    // the clouds over themselves.
    let bulge = 0.9 * (1.0 - exp(-0.8 * max(u.cursorAmt, 0.0)));
    let uvS = uvBlast - toCursor * (bulge * cursorFall) / vec2<f32>(u.aspect, 1.0);

    let clearing = (1.0 - 0.9 * blast * exp(-(rad * rad) / (0.015 + 0.2 * blast)))
        * (1.0 - 0.4 * clamp(u.cursorAmt, 0.0, 1.0) * cursorFall);

    let p = vec2<f32>(uvS.x * u.aspect, uvS.y) * 2.4;
    let t = u.time * (0.025 + 0.16 * heat);

    // Domain warping: clouds folded through two layers of noise.
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3) - vec2<f32>(t, 0.0)));
    let r = vec2<f32>(
        fbm(p + 3.2 * q + vec2<f32>(1.7, 9.2) + vec2<f32>(t * 1.4, 0.0)),
        fbm(p + 3.2 * q + vec2<f32>(8.3, 2.8) - vec2<f32>(0.0, t)),
    );
    let f = fbm(p + 2.6 * r);
    let dust = smoothstep(0.3, 0.86, f) * clearing;
    let veil = smoothstep(0.12, 0.62, f) * 0.35 * clearing;

    let cool = mix(
        mix(vec3<f32>(0.14, 0.09, 0.38), vec3<f32>(0.42, 0.28, 0.82), clamp(length(q) * 0.9, 0.0, 1.0)),
        vec3<f32>(0.18, 0.52, 0.72),
        clamp(r.x * r.x, 0.0, 1.0) * 0.45,
    );
    let hot = mix(
        mix(vec3<f32>(0.72, 0.12, 0.42), vec3<f32>(1.0, 0.45, 0.16), clamp(length(r) * 0.85, 0.0, 1.0)),
        vec3<f32>(1.0, 0.86, 0.5),
        smoothstep(0.72, 1.0, f),
    );
    let color = mix(cool, hot, heat);

    // Heat gathers around the card.
    let toFocus = (in.uv - vec2<f32>(0.5, u.focusY)) * vec2<f32>(u.aspect, 1.0);
    let focus = exp(-dot(toFocus, toFocus) / 0.06) * heat * clearing;

    // Stardust: sparse soft specks, round within their cell so the
    // half-resolution texture scales up without hard pixels.
    let grid = vec2<f32>(u.aspect * 64.0, 64.0);
    let cell = floor(in.uv * grid);
    let h = hash(cell);
    let offset = vec2<f32>(hash(cell + vec2<f32>(7.0, 3.0)), hash(cell + vec2<f32>(1.0, 9.0))) - vec2<f32>(0.5, 0.5);
    let local = fract(in.uv * grid) - vec2<f32>(0.5, 0.5) - offset * 0.5;
    let round = exp(-dot(local, local) / 0.012);
    let speck = step(0.975, h) * round * (0.45 + 0.55 * sin(u.time * (1.5 + h * 3.0) + h * 40.0));

    // Mist: a large, slow haze drifting sideways, thicker low in the sky.
    let mistN = fbm(p * 0.45 + vec2<f32>(u.time * 0.02, -u.time * 0.008) + vec2<f32>(11.0, 4.0));
    let mistA = smoothstep(0.32, 0.78, mistN) * (0.55 + 0.45 * in.uv.y) * 0.22 * u.mist * clearing;
    let mistColor = mix(vec3<f32>(0.62, 0.58, 0.86), vec3<f32>(1.0, 0.7, 0.55), heat);

    // Sand: minute granules at artboard-pixel scale, mostly where the dust
    // is, each glinting slowly. Pinned to the pushed cloud so they fly
    // outward with it on the blast.
    let sandCell = floor(uvS * vec2<f32>(u.aspect * 844.0, 844.0));
    let sh = hash(sandCell + vec2<f32>(3.7, 8.1));
    let sandTw = 0.55 + 0.45 * sin(u.time * (0.8 + sh * 2.5) + sh * 90.0);
    let sand = step(0.94, sh) * sandTw * (0.25 + 0.75 * (dust + veil)) * u.grain;
    let sandColor = mix(vec3<f32>(0.9, 0.86, 1.0), vec3<f32>(1.0, 0.85, 0.6), heat);

    var alpha = veil * (0.6 + 0.4 * heat) + dust * (0.55 + 0.3 * heat) + focus * 0.4 + speck * 0.6 * (0.5 + dust);
    var rgb = color * (veil * (0.45 + 0.4 * heat) + dust * (0.7 + 0.5 * heat) + focus * 0.6) + vec3<f32>(1.0, 0.95, 0.85) * speck * 0.6 * (0.5 + dust);
    rgb = rgb + mistColor * mistA;
    alpha = alpha + mistA * (1.0 - alpha);
    rgb = rgb + sandColor * sand * 0.45;
    alpha = alpha + sand * 0.45 * (1.0 - alpha);

    // Film grain / dither: per-pixel noise that re-rolls a dozen times a
    // second. Breaks up banding in the smooth gradients.
    let gh = hash(floor(in.position.xy) + vec2<f32>(floor(u.time * 12.0) * 17.0, 3.0)) - 0.5;
    alpha = clamp(alpha, 0.0, 1.0);
    rgb = clamp(rgb + vec3<f32>(gh * 0.09 * u.grain * alpha), vec3<f32>(0.0), vec3<f32>(alpha));
    return vec4<f32>(rgb, alpha);
}
