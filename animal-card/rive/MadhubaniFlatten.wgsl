// Madhubani pass 1: flatten. A Kuwahara filter: for each pixel, the four
// square windows that share its corner are averaged, and the window with the
// least colour variance wins. Edges stay sharp while photo texture (feather
// grain, leaf noise) melts into flat painted patches for pass 2 to band.
//
// Alpha carries the subject mask, from three cues:
//   colour  distance to the nearest sample along the top, left or right
//           border (the bottom is skipped: perched birds run off it);
//           `maskThreshold` is the distance that counts as different
//   detail  colour variance around the pixel: feathers are sharp, a
//           blurred background is smooth
//   centre  the subject is usually in the middle, so the edges need more
//           evidence
//
// Bindings group 0:
//   0: UBO — texel size (1/width, 1/height), radius in texels, maskThreshold
//   1: source texture (the photo, cover-fitted at work resolution)
//   2: sampler

struct Params {
    texel: vec2<f32>,
    radius: f32,
    maskThreshold: f32,
};

@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var src: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;

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

const MAX_RADIUS: i32 = 6;

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    let r = clamp(i32(u.radius), 1, MAX_RADIUS);
    let dirs = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0, 1.0),
        vec2<f32>(1.0, 1.0),
    );
    var best = textureSampleLevel(src, smp, in.uv, 0.0).rgb;
    var bestVar = 1e9;
    var detail = 0.0;
    for (var q = 0; q < 4; q++) {
        var sum = vec3<f32>(0.0);
        var sum2 = vec3<f32>(0.0);
        var n = 0.0;
        for (var j = 0; j <= MAX_RADIUS; j++) {
            for (var i = 0; i <= MAX_RADIUS; i++) {
                if (i <= r && j <= r) {
                    let offset = dirs[q] * vec2<f32>(f32(i), f32(j)) * u.texel;
                    let c = textureSampleLevel(src, smp, in.uv + offset, 0.0).rgb;
                    sum += c;
                    sum2 += c * c;
                    n += 1.0;
                }
            }
        }
        let mean = sum / n;
        let v = sum2 / n - mean * mean;
        let total = v.r + v.g + v.b;
        detail += total;
        if (total < bestVar) {
            bestVar = total;
            best = mean;
        }
    }
    // Distance to the nearest border colour.
    var nearest = 9.0;
    for (var i = 0; i < 12; i++) {
        let t = (f32(i) + 0.5) / 12.0;
        let top = textureSampleLevel(src, smp, vec2<f32>(t, 0.015), 0.0).rgb;
        let left = textureSampleLevel(src, smp, vec2<f32>(0.015, t), 0.0).rgb;
        let right = textureSampleLevel(src, smp, vec2<f32>(0.985, t), 0.0).rgb;
        nearest = min(nearest, min(distance(best, top), min(distance(best, left), distance(best, right))));
    }
    let colourScore = nearest / max(u.maskThreshold, 0.01);
    let detailScore = detail / 0.02;
    let centre = length((in.uv - vec2<f32>(0.5, 0.55)) * vec2<f32>(1.0, 0.8));
    let score = (colourScore + detailScore) * mix(1.4, 0.7, smoothstep(0.1, 0.55, centre));
    let mask = smoothstep(0.8, 1.2, score);
    return vec4<f32>(best, mask);
}
