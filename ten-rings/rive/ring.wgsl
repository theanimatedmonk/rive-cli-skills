// The Ten Rings' surface: bronze metal whose carved artwork glows.
//
// Same metal-roughness lighting as glb_pbr.wgsl, plus an imprint glow. The
// carving is real relief in the mesh; TenRings.luau measures how deep each
// vertex sits in a groove (its "cavity") at load time and stores it in
// uv.x. Grooves deeper than `cavLow` start to glow, fully by `cavHigh`, in
// `imprint.rgb` at `imprint.w` intensity (HDR: strong values bloom to a
// white-hot core through the tone mapper). Grooves are also darkened, as
// carving collects grime, so the pattern reads even when the glow is off.
//
// Vertex layout (32 bytes): position xyz | normal xyz | cavity, unused.

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
};

@vertex
fn vs_main(v: VertexIn) -> VertexOut {
    var out: VertexOut;
    out.clip = u.mvp * vec4<f32>(v.position, 1.0);
    out.world = (u.model * vec4<f32>(v.position, 1.0)).xyz;
    out.normal = (u.model * vec4<f32>(v.normal, 0.0)).xyz;
    out.cavity = v.extra.x;
    out.local = v.position;
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

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let metallic = clamp(u.params.x, 0.0, 1.0);
    let roughness = clamp(u.params.y, 0.04, 1.0);
    let time = u.params.z;

    // Imprint mask from the measured groove depth.
    let mask = smoothstep(u.env.z, u.env.w, in.cavity);

    var albedo = u.baseColor.rgb * (1.0 - 0.55 * mask);

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
    let direct = (diffuse + specular) * NdotL * u.light.w * PI;

    let Fr = F0 + (max(vec3<f32>(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);
    let envSpec = environment(reflect(-V, N), roughness) * Fr * u.env.x * (1.0 - 0.6 * mask);
    let envDiff = environment(N, 1.0) * albedo * (1.0 - metallic) * u.camera.w;
    let ambient = albedo * u.camera.w * 0.15;

    let rim = u.rim.rgb * u.rim.w * pow(1.0 - NdotV, 3.0);
    let energy = u.emissive.rgb * u.emissive.w;

    // The glow breathes, with a slow wave running around the ring and a
    // little flicker so it reads as living light rather than paint.
    let around = atan2(in.local.y, in.local.x);
    let wave = 0.8 + 0.2 * sin(time * 1.6 + around * 3.0);
    let flicker = 0.92 + 0.08 * sin(time * 9.0 + hash(floor(in.local * 6.0)) * 40.0);
    let glow = u.imprint.rgb * u.imprint.w * mask * wave * flicker;

    var color = direct + envSpec + envDiff + ambient + rim + energy + glow;
    color = acesTonemap(color * u.params.w);
    color = pow(color, vec3<f32>(1.0 / 2.2));
    let alpha = clamp(u.baseColor.a * u.env.y, 0.0, 1.0);
    return vec4<f32>(color * alpha, alpha);
}
