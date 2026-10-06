// Card3DShader — 3D card sized from the face artboard.
// The front (+z) samples the face texture, the back (-z) the back texture
// (kind = 0); the back's mesh UVs already read correctly from behind.
// Rim faces use edgeColor (kind = 1). The foil is on the front only.
// The back gets a gentle saturation lift so its print stays vivid, and is
// read as a grid of particles: waves of glow run through them, each particle
// lighting up in its own colour with a soft halo (paper and greys stay dark).
//
// Lighting: a slight UV bulge so the highlight travels across the face as the
// card turns (a perfectly flat normal would brighten the whole face at once).
//
// Bindings group 0:
//   0: UBO 256 bytes — mvp, model, edgeColor,
//      light (angleRad, lightI, glossI, glossSharp 0-1),
//      params.x = curvature, params.y = ambient 0-1,
//      params.z = 0 card normals / 1 sphere normals (from localPos),
//      params.w = seconds,
//      lightColor = gloss tint,
//      foil (intensity 0-1, stripe count, tilt shift 0-1, angle rad),
//      particles (cells across, glow 0-1, speed, unused),
//      shine (intensity 0-1, rim width, speed rad/s, unused),
//      rim (face half-width, half-height, corner radius, unused) in mesh units
//   1: face texture
//   2: sampler
//   3: back texture

struct UBO {
    mvp: mat4x4<f32>,
    model: mat4x4<f32>,
    edgeColor: vec4<f32>,
    light: vec4<f32>,
    params: vec4<f32>,
    lightColor: vec4<f32>,
    foil: vec4<f32>,
    particles: vec4<f32>,
    shine: vec4<f32>,
    rim: vec4<f32>,
}
@group(0) @binding(0) var<uniform> u: UBO;
@group(0) @binding(1) var tFace: texture_2d<f32>;
@group(0) @binding(2) var tSamp: sampler;
@group(0) @binding(3) var tBack: texture_2d<f32>;

struct VIn {
    @location(0) pos: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) kind: f32,
}

struct VOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) kind: f32,
    @location(2) localPos: vec3<f32>,
}

@vertex
fn vs_main(v: VIn) -> VOut {
    var o: VOut;
    o.clip = u.mvp * vec4<f32>(v.pos, 1.0);
    o.uv = v.uv;
    o.kind = v.kind;
    o.localPos = v.pos;
    return o;
}

@fragment
fn fs_main(f: VOut) -> @location(0) vec4<f32> {
    // Sample both in uniform control flow, then pick by side.
    let front = textureSample(tFace, tSamp, f.uv);
    let rear = textureSample(tBack, tSamp, f.uv);
    let sampled = select(front, rear, f.localPos.z < 0.0);

    // Back particles: the cell this pixel is in, and the print's colour at
    // the cell's centre (sampled here, in uniform control flow).
    let dims = vec2<f32>(textureDimensions(tBack));
    let cellPx = dims.x / max(u.particles.x, 8.0);
    let cellPos = f.uv * dims / cellPx;
    let cellId = floor(cellPos);
    let cellUv = (cellId + 0.5) * cellPx / dims;
    let cellColor = textureSampleLevel(tBack, tSamp, cellUv, 0.0).rgb;
    let k = clamp(f.kind, 0.0, 1.0);
    let albedo = mix(sampled, u.edgeColor, k);

    let uvC = f.uv * 2.0 - 1.0;
    let curve = u.params.x;
    let zRaw = f.localPos.z;
    let zN = select(1.0, sign(zRaw), abs(zRaw) > 0.001);
    let nFace = normalize(vec3<f32>(uvC.x * curve, uvC.y * curve, zN));
    let nRim = normalize(vec3<f32>(f.localPos.x, f.localPos.y, 0.0001));
    let nCard = normalize(mix(nFace, nRim, k));
    let nSphere = normalize(f.localPos);
    let nLocal = normalize(mix(nCard, nSphere, u.params.z));
    let nWorld = normalize((u.model * vec4<f32>(nLocal, 0.0)).xyz);

    let angle = u.light.x;
    let L = normalize(vec3<f32>(sin(angle), 0.42, cos(angle)));
    let V = vec3<f32>(0.0, 0.0, 1.0);
    let H = normalize(L + V);

    let ndl = max(dot(nWorld, L), 0.0);
    let ndh = max(dot(nWorld, H), 0.0);
    let ndv = max(dot(nWorld, V), 0.0);
    let lightI = u.light.y;
    let glossI = u.light.z;
    let sharp = clamp(u.light.w, 0.0, 1.0);
    let power = mix(6.0, 96.0, sharp);
    let specTerm = pow(clamp(ndh, 0.0001, 1.0), power);
    let fres = pow(clamp(1.0 - ndv, 0.0, 1.0), 2.0);
    let spec = specTerm * glossI * 1.6 * (1.0 + fres * 0.45);
    let ambient = u.params.y;
    let diffuse = mix(ambient, 1.0, ndl * clamp(lightI * 2.4, 0.0, 1.0));
    let lit = albedo.rgb * diffuse + u.lightColor.rgb * spec;

    // Foil only on the front face; the back and the rim stay plain.
    let isFront = f.localPos.z > 0.0 && k < 0.5;
    let foilI = select(0.0, u.foil.x, isFront);
    let stripes = max(u.foil.y, 0.25);
    let shiftAmt = u.foil.z;
    let foilAng = u.foil.w;
    let ca = cos(foilAng);
    let sa = sin(foilAng);
    let uvcX = f.uv.x - 0.5;
    let uvcY = f.uv.y - 0.5;
    let stripeUv = uvcX * ca + uvcY * sa + 0.5;
    let perp = uvcX * (0.0 - sa) + uvcY * ca;
    let wave = sin(perp * 8.0) * 0.08;
    let tilt = nWorld.x * 0.9 + nWorld.y * 0.28;
    let phase = (stripeUv + wave + tilt * shiftAmt) * stripes * 6.2831855;
    let hr = 0.5 + 0.5 * sin(phase);
    let hg = 0.5 + 0.5 * sin(phase + 2.094395);
    let hb = 0.5 + 0.5 * sin(phase + 4.18879);
    let foilMask = 0.42 + 0.58 * fres + 0.32 * specTerm;
    let foilLit = vec3<f32>(hr, hg, hb) * foilI * foilMask;
    let invA = vec3<f32>(1.0) - lit;
    let invF = vec3<f32>(1.0) - foilLit;
    var rgb = vec3<f32>(1.0) - invA * invF;

    // Edge shine on the front: a thin bright rim (rounded-rect distance from the
    // face outline), a highlight that travels around it over time, and extra
    // light on whichever edge the tilt brings toward the viewer.
    if (isFront) {
        let p = f.localPos.xy;
        let half = u.rim.xy;
        let radius = u.rim.z;
        let q = abs(p) - half + vec2<f32>(radius);
        let sdf = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
        let inset = max(-sdf, 0.0);
        let rimMask = 1.0 - smoothstep(0.0, max(u.shine.y, 0.5), inset);
        let theta = atan2(p.y, p.x);
        let sweep = pow(0.5 + 0.5 * cos(theta - u.params.w * u.shine.z), 10.0);
        let towardViewer = (u.model * vec4<f32>(p, 0.0, 0.0)).z / max(max(half.x, half.y), 1.0);
        let tiltLift = clamp(towardViewer * 6.0, 0.0, 1.0);
        let shineAmt = rimMask * (0.22 + 0.9 * sweep + 0.8 * tiltLift) * u.shine.x;
        rgb = min(rgb + u.lightColor.rgb * shineAmt, vec3<f32>(1.0));
    }

    // The back's print stays vivid under the light: a gentle saturation lift.
    let isBack = f.localPos.z < 0.0 && k < 0.5;
    if (isBack) {
        let grey = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
        rgb = clamp(mix(vec3<f32>(grey), rgb, 1.25), vec3<f32>(0.0), vec3<f32>(1.0));

        let t = u.params.w * u.particles.z;
        let sat = max(cellColor.r, max(cellColor.g, cellColor.b)) - min(cellColor.r, min(cellColor.g, cellColor.b));
        let colourful = smoothstep(0.12, 0.35, sat);
        // Two waves crossing the card, sharpened into bright fronts.
        let waveA = pow(0.5 + 0.5 * sin(dot(cellId, vec2<f32>(0.11, 0.07)) - t * 2.2), 14.0);
        let waveB = pow(0.5 + 0.5 * sin(dot(cellId, vec2<f32>(-0.05, 0.10)) - t * 1.4 + 1.7), 16.0);
        let seed = fract(sin(dot(cellId, vec2<f32>(127.1, 311.7))) * 43758.5453);
        let twinkle = 0.65 + 0.35 * sin(t * 3.0 + seed * 6.2831855);
        let glow = clamp(waveA * 1.3 + waveB, 0.0, 1.8) * twinkle;
        let d = length(fract(cellPos) - 0.5);
        let dotShape = smoothstep(0.45, 0.2, d) + smoothstep(0.9, 0.0, d) * 0.3;
        let bright = cellColor * 1.8 + vec3<f32>(0.2);
        rgb += bright * dotShape * glow * colourful * u.particles.y;
    }
    return vec4<f32>(rgb, albedo.a);
}
