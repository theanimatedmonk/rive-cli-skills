// CardShadowShader — silhouette, gaussian blur, and blit for the card drop shadow.
// Bindings group 0:
//   0: UBO
//   1: source texture
//   2: sampler
//
// extra.y mode: 0 silhouette, 1 blur, 2 card blit, 3 shadow blit

struct UBO {
  color:  vec4<f32>,
  params: vec4<f32>,
  extra:  vec4<f32>,
  map:    vec4<f32>,
}
@group(0) @binding(0) var<uniform> u:     UBO;
@group(0) @binding(1) var          tSrc:  texture_2d<f32>;
@group(0) @binding(2) var          tSamp: sampler;

struct VOut {
  @builtin(position) clip: vec4<f32>,
  @location(0)       uv:   vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vid: u32) -> VOut {
  var pos = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  let p = pos[vid];
  var o: VOut;
  o.clip = vec4<f32>(p, 0.0, 1.0);
  o.uv = vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
  return o;
}

fn blur13(uv: vec2<f32>) -> vec4<f32> {
  let stepv = u.params.xy * u.params.zw * (u.extra.x / 6.0);
  var acc = vec4<f32>(0.0);
  var wsum = 0.0;
  for (var i: i32 = -6; i <= 6; i++) {
    let fi = f32(i);
    let w = exp(-0.5 * fi * fi / 4.0);
    acc += textureSample(tSrc, tSamp, uv + stepv * fi) * w;
    wsum += w;
  }
  return acc / wsum;
}

@fragment
fn fs_main(f: VOut) -> @location(0) vec4<f32> {
  let uv = f.uv;
  let cardUv = uv * u.map.xy - u.map.zw;
  let cardS = textureSample(tSrc, tSamp, clamp(cardUv, vec2<f32>(0.0), vec2<f32>(1.0)));
  let offS = textureSample(tSrc, tSamp, uv - u.extra.zw);
  let blr = blur13(uv);

  let inside = step(0.0, cardUv.x) * step(cardUv.x, 1.0)
    * step(0.0, cardUv.y) * step(cardUv.y, 1.0);
  let sil = vec4<f32>(u.color.rgb, u.color.a * cardS.a * inside);
  let card = vec4<f32>(cardS.rgb, cardS.a * inside);

  let mode = u.extra.y;
  let w0 = 1.0 - step(0.5, mode);
  let w1 = step(0.5, mode) * (1.0 - step(1.5, mode));
  let w2 = step(1.5, mode) * (1.0 - step(2.5, mode));
  let w3 = step(2.5, mode);
  return sil * w0 + blr * w1 + card * w2 + offS * w3;
}