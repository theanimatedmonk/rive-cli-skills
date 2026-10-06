// Posterizes the sampled image into 4 levels per channel. Where the sample
// is fully transparent black (what an unreadable view gives), it shows
// magenta, so "read nothing" can't be mistaken for a dark image.

@group(0) @binding(1) var srcTex: texture_2d<f32>;
@group(0) @binding(2) var srcSampler: sampler;

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

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let c = textureSample(srcTex, srcSampler, in.uv);
    if (c.r + c.g + c.b + c.a == 0.0) {
        return vec4<f32>(1.0, 0.0, 1.0, 1.0);
    }
    let posterized = floor(c.rgb * 4.0) / 3.0;
    return vec4<f32>(posterized, 1.0);
}
