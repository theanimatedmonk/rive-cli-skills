// Shading for meshes loaded by GLB.luau / GLBModel.luau.
//
// Metal-roughness PBR (GGX specular, Schlick Fresnel, Smith geometry) lit by
// one directional light plus a procedural studio environment, so metals have
// something to reflect without an HDR map. Adds an optional rim light and
// emissive glow, then ACES tone mapping and gamma. Output is premultiplied.
//
// Vertex layout (32 bytes): position xyz | normal xyz | uv.

struct Uniforms {
    mvp: mat4x4<f32>,
    model: mat4x4<f32>,
    baseColor: vec4<f32>,  // linear rgba
    emissive: vec4<f32>,   // rgb, strength
    rim: vec4<f32>,        // rgb, strength
    light: vec4<f32>,      // direction towards the light (xyz), intensity
    camera: vec4<f32>,     // camera position (xyz), ambient
    params: vec4<f32>,     // metallic, roughness, hasTexture, tintAmount
    tint: vec4<f32>,       // rgb, exposure
    env: vec4<f32>,        // environment strength, opacity, unused, unused
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var baseTex: texture_2d<f32>;
@group(0) @binding(2) var baseSampler: sampler;

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

@vertex
fn vs_main(v: VertexIn) -> VertexOut {
    var out: VertexOut;
    let world = u.model * vec4<f32>(v.position, 1.0);
    out.clip = u.mvp * vec4<f32>(v.position, 1.0);
    out.world = world.xyz;
    // The model matrix is rotation + uniform scale + translation, so its
    // upper 3x3 transforms normals correctly once renormalised.
    out.normal = (u.model * vec4<f32>(v.normal, 0.0)).xyz;
    out.uv = v.uv;
    return out;
}

const PI: f32 = 3.14159265;

fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

// Soft studio surroundings: a warm floor, cool sky, a bright horizon band and
// two softbox highlights. Rougher surfaces see a flatter, averaged version.
fn environment(dir: vec3<f32>, roughness: f32) -> vec3<f32> {
    let y = dir.y;
    let sky = mix(vec3<f32>(0.32, 0.36, 0.42), vec3<f32>(0.08, 0.10, 0.14), clamp(y, 0.0, 1.0));
    let ground = mix(vec3<f32>(0.20, 0.15, 0.11), vec3<f32>(0.04, 0.035, 0.03), clamp(-y, 0.0, 1.0));
    var c = select(ground, sky, y >= 0.0);
    let band = exp(-y * y / mix(0.004, 0.08, roughness)) * mix(1.6, 0.5, roughness);
    c += vec3<f32>(1.0, 0.95, 0.88) * band;
    let box1 = pow(max(dot(dir, normalize(vec3<f32>(0.6, 0.55, 0.6))), 0.0), mix(180.0, 6.0, roughness));
    let box2 = pow(max(dot(dir, normalize(vec3<f32>(-0.7, 0.35, -0.3))), 0.0), mix(120.0, 5.0, roughness));
    c += vec3<f32>(2.2, 2.1, 2.0) * box1 + vec3<f32>(0.9, 1.0, 1.2) * box2;
    let average = vec3<f32>(0.28, 0.27, 0.27);
    return mix(c, average, roughness * roughness * 0.8);
}

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let metallic = clamp(u.params.x, 0.0, 1.0);
    let roughness = clamp(u.params.y, 0.04, 1.0);
    let hasTexture = u.params.z;
    let tintAmount = clamp(u.params.w, 0.0, 1.0);

    let texel = textureSample(baseTex, baseSampler, in.uv);
    let texColor = mix(vec3<f32>(1.0), srgbToLinear(texel.rgb), hasTexture);
    var albedo = u.baseColor.rgb * texColor;
    albedo = mix(albedo, u.tint.rgb, tintAmount);

    let V = normalize(u.camera.xyz - in.world);
    var N = normalize(in.normal);
    // Light back faces as if they faced the camera (thin or open meshes).
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

    // Environment: reflections for the specular part, a flat ambient for the
    // diffuse part.
    let Fr = F0 + (max(vec3<f32>(1.0 - roughness), F0) - F0) * pow(1.0 - NdotV, 5.0);
    let R = reflect(-V, N);
    let envSpec = environment(R, roughness) * Fr * u.env.x;
    let envDiff = environment(N, 1.0) * albedo * (1.0 - metallic) * u.camera.w;
    let ambient = albedo * u.camera.w * 0.15;

    let rim = u.rim.rgb * u.rim.w * pow(1.0 - NdotV, 3.0);
    let glow = u.emissive.rgb * u.emissive.w;

    var color = direct + envSpec + envDiff + ambient + rim + glow;
    color = acesTonemap(color * u.tint.w);
    color = pow(color, vec3<f32>(1.0 / 2.2));

    let alpha = clamp(u.baseColor.a * u.env.y, 0.0, 1.0);
    return vec4<f32>(color * alpha, alpha);
}
