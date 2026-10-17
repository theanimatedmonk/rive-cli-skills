// The Pinaka's surface: gold whose carved ornament glows with divine light.
// Adapted from the Ten Rings' ring shader; the glow here flows along the
// bow's length (model Y) instead of around a ring.
//
// Same metal-roughness lighting as glb_pbr.wgsl, plus an imprint glow. The
// carving is real relief in the mesh; TenRings.luau measures how deep each
// vertex sits in a groove (its "cavity") at load time and stores it in
// uv.x. Grooves deeper than `cavLow` start to glow, fully by `cavHigh`, in
// `imprint.rgb` at `imprint.w` intensity (HDR: strong values bloom to a
// white-hot core through the tone mapper). Grooves are also darkened, as
// carving collects grime, so the pattern reads even when the glow is off.
//
// Vertex layout (32 bytes): position xyz | normal xyz | cavity, inlay.
// inlay: distance from the limbs' almond eye inlay (< 1 inside), 3 elsewhere.

struct Uniforms {
    mvp: mat4x4<f32>,
    model: mat4x4<f32>,
    baseColor: vec4<f32>,  // linear bronze rgb, a
    emissive: vec4<f32>,   // energy glow rgb, strength
    rim: vec4<f32>,        // energy rim rgb, strength
    light: vec4<f32>,      // direction towards the light, intensity
    camera: vec4<f32>,     // camera position, ambient
    params: vec4<f32>,     // metallic, roughness, time, exposure
    imprint: vec4<f32>,    // imprint glow rgb (linear), intensity
    env: vec4<f32>,        // environment, opacity, cavLow, cavHigh
    wood: vec4<f32>,       // linear wood rgb, grain strength
    mode: vec4<f32>,       // x: 0 brass, 1 wood + brass filigree, 2 wooden grip
                           //    with cord wraps, 3 light, 4 the arrow; y: the
                           //    bow's centre (model y); z, w: where the limbs
                           //    start (half the grip) and their length. For
                           //    the arrow: y its length (local x, nock at 0),
                           //    z how far it has formed, w its head's glow
    deform: vec4<f32>,     // drawing the bow: x string pull at the nock,
                           // y tip flex (both toward the archer, -x),
                           // z the string's half length, w how much of the
                           // tip flex the string's ends follow
};

@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) extra: vec2<f32>,
};

struct VertexOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) cavity: f32,
    @location(3) local: vec3<f32>,
    @location(4) localNormal: vec3<f32>,
    @location(5) inlay: f32,
};

@vertex
fn vs_main(v: VertexIn) -> VertexOut {
    var out: VertexOut;
    // Drawing the bow: the limbs flex toward the archer more toward the tips,
    // and the string becomes a V from the tips to the nock point.
    // A limb deflects as B f^2 (f: 0 at the grip, 1 at the tip); keeping its
    // length, it shortens toward the centre by (2/3) B^2 / L f^3, and its
    // surface turns with the slope 2 B f / L, so the light follows the bend.
    var p = v.position;
    var n = v.normal;
    let dy = p.y - u.mode.y;
    let side = sign(dy);
    let bend = u.deform.y;
    let limb = max(u.mode.w, 1e-4);
    let shorten = 0.6667 * bend * bend / limb;
    if (u.mode.x > 3.5) {
        // The arrow: placed by its own matrix, not bent.
    } else if (u.mode.x > 2.5) {
        let s = clamp(abs(dy) / max(u.deform.z, 1e-4), 0.0, 1.0);
        p.x = p.x - mix(u.deform.x, bend * u.deform.w, s);
        p.y = p.y - side * shorten * pow(u.deform.w, 1.5) * s;
    } else {
        let f = clamp((abs(dy) - u.mode.z) / limb, 0.0, 1.0);
        p.x = p.x - bend * f * f;
        p.y = p.y - side * shorten * f * f * f;
        let a = side * atan(2.0 * bend * f / limb);
        let c = cos(a);
        let sn = sin(a);
        n = vec3<f32>(n.x * c - n.y * sn, n.x * sn + n.y * c, n.z);
    }
    out.clip = u.mvp * vec4<f32>(p, 1.0);
    out.world = (u.model * vec4<f32>(p, 1.0)).xyz;
    out.normal = (u.model * vec4<f32>(n, 0.0)).xyz;
    out.cavity = v.extra.x;
    out.local = v.position;
    out.localNormal = v.normal;
    out.inlay = v.extra.y;
    return out;
}

const PI: f32 = 3.14159265;

fn environment(dir: vec3<f32>, roughness: f32) -> vec3<f32> {
    let y = dir.y;
    let sky = mix(vec3<f32>(0.30, 0.30, 0.32), vec3<f32>(0.07, 0.08, 0.10), clamp(y, 0.0, 1.0));
    let ground = mix(vec3<f32>(0.20, 0.14, 0.10), vec3<f32>(0.035, 0.03, 0.025), clamp(-y, 0.0, 1.0));
    var c = select(ground, sky, y >= 0.0);
    let band = exp(-y * y / mix(0.004, 0.08, roughness)) * mix(1.4, 0.45, roughness);
    c += vec3<f32>(1.0, 0.93, 0.85) * band;
    let box1 = pow(max(dot(dir, normalize(vec3<f32>(0.6, 0.55, 0.6))), 0.0), mix(180.0, 6.0, roughness));
    let box2 = pow(max(dot(dir, normalize(vec3<f32>(-0.7, 0.35, -0.3))), 0.0), mix(120.0, 5.0, roughness));
    c += vec3<f32>(2.0, 1.9, 1.75) * box1 + vec3<f32>(0.8, 0.85, 0.95) * box2;
    return mix(c, vec3<f32>(0.26, 0.25, 0.24), roughness * roughness * 0.8);
}

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Wood grain: fine wavering streaks along the limb, with slow colour drift.
fn grain(p: vec3<f32>) -> f32 {
    let warp = sin(p.y * 38.0 + p.x * 70.0) * 1.6 + sin(p.z * 120.0) * 0.6;
    let lines = sin(p.y * 520.0 + warp * 3.0) * 0.5 + sin(p.y * 1300.0 + warp) * 0.25;
    let drift = sin(p.y * 22.0 + p.x * 40.0) * 0.5;
    return 0.5 + 0.35 * lines + 0.3 * drift;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    var metallic = clamp(u.params.x, 0.0, 1.0);
    var roughness = clamp(u.params.y, 0.04, 1.0);
    let time = u.params.z;
    let mode = u.mode.x;
    // The arrow forms out of light from the nock: nothing past the formed
    // length, and a bright seam at it.
    var arrowLight = 0.0;
    if (mode > 3.5) {
        let formed = u.mode.z;
        if (in.local.x > formed) {
            discard;
        }
        let forming = select(0.0, 1.0, formed < u.mode.y);
        let seam = (1.0 - smoothstep(0.0, 0.07, formed - in.local.x)) * forming;
        let head = smoothstep(u.mode.y - 0.2, u.mode.y - 0.03, in.local.x) * u.mode.w;
        arrowLight = seam * 8.0 + head * 2.2;
    }

    // Relief from the measured cavity: < 0 raised, > 0 recessed; -1 means
    // the part has no carving.
    let carved = in.cavity > -0.9;
    let raised = select(0.0, smoothstep(-0.06, -0.22, in.cavity), carved);
    let groove = select(0.0, smoothstep(0.04, 0.26, in.cavity), carved);
    // Imprint mask (the glow) only in the deepest grooves.
    let mask = select(0.0, smoothstep(u.env.z, u.env.w, in.cavity), carved);

    let woodCol = u.wood.rgb * (1.0 - u.wood.w + u.wood.w * 2.0 * grain(in.local));
    var albedo = u.baseColor.rgb;
    if (mode > 0.5 && mode < 1.5) {
        // A limb, laid out like the reference from the grip to the tip
        // (t 0..1 along it): a carved brass sleeve framing an oval wood
        // panel on each face, then carved wood with brass filigree raised
        // on it, then brass again toward the curled tip.
        let t = clamp((abs(in.local.y - u.mode.y) - u.mode.z) / u.mode.w, 0.0, 1.0);

        let carvedWood = smoothstep(0.40, 0.46, t) * (1.0 - smoothstep(0.80, 0.86, t));
        let filigree = smoothstep(0.0, -0.10, in.cavity);
        // The almond eye inlay: in.inlay < 1 inside it (from the load).
        let eye = 1.0 - smoothstep(0.93, 1.0, in.inlay);
        let wood = max(eye, carvedWood * (1.0 - filigree));
        albedo = mix(u.baseColor.rgb, woodCol, wood);
        metallic = mix(1.0, 0.08, wood);
        // Polished wood in the eye, satin elsewhere.
        roughness = mix(roughness, mix(0.5, 0.3, eye), wood);
    } else if (mode > 1.5 && mode < 2.5) {
        // The grip: wood, with two bands of white cord either side of centre.
        let d = abs(in.local.y - u.mode.y);
        let cord = smoothstep(0.030, 0.034, d) * (1.0 - smoothstep(0.083, 0.087, d));
        let twist = 0.85 + 0.15 * sin(in.local.y * 2400.0 + atan2(in.local.z, in.local.x) * 3.0);
        albedo = mix(woodCol, vec3<f32>(0.78, 0.75, 0.68) * twist, cord);
        metallic = 0.0;
        roughness = mix(0.5, 0.85, cord);
    }
    // Depth: grooves collect dark patina, ridges catch the light.
    let patina = vec3<f32>(0.05, 0.03, 0.012);
    albedo = mix(albedo * (1.0 + 0.2 * raised), patina, 0.8 * groove);

    let V = normalize(u.camera.xyz - in.world);
    var N = normalize(in.normal);
    if (dot(N, V) < 0.0) {
        N = -N;
    }
    let L = normalize(u.light.xyz);
    let H = normalize(L + V);
    let NdotL = max(dot(N, L), 0.0);
    let NdotV = max(dot(N, V), 1e-4);
    let NdotH = max(dot(N, H), 0.0);
    let VdotH = max(dot(V, H), 0.0);

    let F0 = mix(vec3<f32>(0.04), albedo, metallic);
    let F = F0 + (vec3<f32>(1.0) - F0) * pow(1.0 - VdotH, 5.0);
    let a = roughness * roughness;
    let a2 = a * a;
    let dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    let D = a2 / (PI * dd * dd);
    let k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    let G = (NdotL / (NdotL * (1.0 - k) + k)) * (NdotV / (NdotV * (1.0 - k) + k));
    let specular = D * G * F / max(4.0 * NdotL * NdotV, 1e-4);
    let diffuse = (vec3<f32>(1.0) - F) * (1.0 - metallic) * albedo / PI;
    let direct = (diffuse + specular) * NdotL * u.light.w * PI * (1.0 - 0.45 * groove);

    let Fr = F0 + (max(vec3<f32>(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);
    let envSpec = environment(reflect(-V, N), roughness) * Fr * u.env.x * (1.0 - 0.75 * groove);
    let envDiff = environment(N, 1.0) * albedo * (1.0 - metallic) * u.camera.w;
    let ambient = albedo * u.camera.w * 0.15;

    let rim = u.rim.rgb * u.rim.w * pow(1.0 - NdotV, 3.0);
    let energy = u.emissive.rgb * u.emissive.w;

    // The glow breathes, with a slow wave running around the ring and a
    // little flicker so it reads as living light rather than paint.
    // Light flowing from the grip out to both tips.
    let along = abs(in.local.y);
    let wave = 0.7 + 0.3 * sin(time * 2.2 - along * 7.0);
    let flicker = 0.92 + 0.08 * sin(time * 9.0 + hash(floor(in.local * 6.0)) * 40.0);
    let glow = u.imprint.rgb * u.imprint.w * mask * wave * flicker;

    var color = direct + envSpec + envDiff + ambient + rim + energy + glow + u.rim.rgb * arrowLight;
    color = acesTonemap(color * u.params.w);
    color = pow(color, vec3<f32>(1.0 / 2.2));
    let alpha = clamp(u.baseColor.a * u.env.y, 0.0, 1.0);
    return vec4<f32>(color * alpha, alpha);
}
