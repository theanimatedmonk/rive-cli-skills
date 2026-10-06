-- Card3D node: drives Card3DShader (WGSL in the Shaders panel).
-- Inputs: rotX, rotY, depth, roundness, scale, edgeColor, face, back,
-- viewModelProperty (nested VM on this artboard's view model),
-- properties (comma-separated fields to relay: triggers, numbers, etc).
-- maxTilt (deg), tiltArea (px from center to reach max tilt),
-- shadowColor, shadowOpacity, shadowOffsetX, shadowOffsetY, shadowSoftness.
-- Lighting: lightAngle (deg), lightIntensity, glossIntensity, glossSharpness (0-100),
-- lightColor, ambient.
-- Foil: foilIntensity, foilStripes, foilShift, foilAngle.
-- Edge shine (front): shineIntensity (0-100), shineWidth (face px), shineSpeed
-- (rad/s a highlight travels around the rim; the edge tilted toward you also lights up).
-- Shadow: with `harmony`/`baseHue` on the view model (under `front`), the
-- shadow colour is a deep shade of the base hue (the colour scheme helpers below).
-- Back particles: particleCells (across the card), particleGlow (0-100),
-- glowSpeed: the back is read as a grid of particles that glow in their own
-- colour as waves run through them.

-- Face size comes from the assigned face artboard (not a fixed 180×180).
-- `back` is drawn on the rear (unmirrored, same size as the face); without
-- it the rear shows the face. Turn the card with rotY (180 = back). Cursor
-- tilt is applied after rotX/rotY, so it leans the same way on either side.
-- Image properties relay into the face (and the back) like numbers and
-- strings do, so a runtime-bound image reaches both sides.

-- Colour scheme helpers (the same block is in Card3D, Madhubani and Aura;
-- keep them in step). A scheme is a colour-harmony rule plus a base hue
-- (`harmony` and `baseHue` on the view model, next to `photo`). Colours are
-- made in OKLCH, which is perceptually uniform: equal lightness and chroma
-- look equally light and vivid at every hue, so harmony hues come out
-- balanced. Inlined rather than a shared module: a required module upset
-- the editor's script types on push.
local Harmony = {}

-- Hue offsets from the base hue, in degrees.
Harmony.SCHEMES = {
	{ 0, 180 }, -- 0 complementary
	{ -30, 0, 30 }, -- 1 analogous
	{ 0, 150, 210 }, -- 2 split-complementary
	{ 0, 120, 240 }, -- 3 triadic
	{ 0, 90, 180, 270 }, -- 4 tetradic (square)
	{ 0, 60, 180, 240 }, -- 5 tetradic (rectangle)
}

-- The print's seven ink slots cycle through the scheme's hues, so
-- neighbouring slots (a region's ink and its accent) are always different
-- harmony hues, at varied lightness: tints and shades of the scheme.
local SLOT_LIGHTNESS = { 0.66, 0.80, 0.58, 0.86, 0.72, 0.62, 0.78 }
local SLOT_CHROMA = 0.19

-- OKLCH (L 0..1, C, hue degrees) to sRGB 0..1. Out-of-gamut colours lose
-- chroma until they fit, rather than clipping (which shifts the hue).
function Harmony.oklch(L: number, C: number, h: number): (number, number, number)
	local function encode(x: number): number
		if x <= 0.0031308 then
			return 12.92 * x
		end
		return 1.055 * x ^ (1 / 2.4) - 0.055
	end
	local rad = math.rad(h)
	local chroma = C
	local r, g, b = 0, 0, 0
	for _ = 1, 24 do
		local a, bb = chroma * math.cos(rad), chroma * math.sin(rad)
		local l_ = (L + 0.3963377774 * a + 0.2158037573 * bb) ^ 3
		local m_ = (L - 0.1055613458 * a - 0.0638541728 * bb) ^ 3
		local s_ = (L - 0.0894841775 * a - 1.2914855480 * bb) ^ 3
		r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
		g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
		b = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_
		if r >= -0.001 and r <= 1.001 and g >= -0.001 and g <= 1.001 and b >= -0.001 and b <= 1.001 then
			break
		end
		chroma *= 0.9
	end
	return encode(math.clamp(r, 0, 1)), encode(math.clamp(g, 0, 1)), encode(math.clamp(b, 0, 1))
end

-- The same, as a Rive Color with an optional alpha (0..1).
function Harmony.color(L: number, C: number, h: number, alpha: number?): Color
	local r, g, b = Harmony.oklch(L, C, h)
	return Color.rgba(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5),
		math.floor(math.clamp(alpha or 1, 0, 1) * 255 + 0.5)
	)
end

-- The scheme's hues, in degrees.
function Harmony.hues(scheme: number, baseHue: number): { number }
	local offsets = Harmony.SCHEMES[math.clamp(math.floor(scheme), 0, #Harmony.SCHEMES - 1) + 1]
	local out: { number } = {}
	for _, o in offsets do
		table.insert(out, baseHue + o)
	end
	return out
end

-- The print's palette: ink, paper, then seven inks, as { r, g, b } in 0..1.
function Harmony.palette(scheme: number, baseHue: number): { { number } }
	local hues = Harmony.hues(scheme, baseHue)
	local out: { { number } } = {}
	-- Near-black tinted toward the complement; paper a pale tint of the base.
	table.insert(out, { Harmony.oklch(0.2, 0.03, baseHue + 180) })
	table.insert(out, { Harmony.oklch(0.95, 0.025, baseHue) })
	for i = 1, 7 do
		table.insert(out, { Harmony.oklch(SLOT_LIGHTNESS[i], SLOT_CHROMA, hues[(i - 1) % #hues + 1]) })
	end
	return out
end

-- `harmony` and `baseHue` from a view model: on it, or under `front`.
-- Returns nil when it has neither.
function Harmony.read(vm: ViewModel?): (number?, number?)
	if vm == nil then
		return nil, nil
	end
	local source = vm
	if source:getNumber('harmony') == nil then
		local front = source:getViewModel('front')
		if front == nil or front.value == nil then
			return nil, nil
		end
		source = front.value
	end
	local h = source:getNumber('harmony')
	local b = source:getNumber('baseHue')
	if h == nil or b == nil then
		return nil, nil
	end
	return h.value, b.value
end

local DEFAULT_W = 180
local DEFAULT_H = 180
local TEX_SCALE = 2
local MAX_TEX = 1024
local MSAA = 4
-- Padding so blur + offset are not cropped at the canvas edge.
local PAD = 120
local VSTRIDE = 24
local CORNER_SEG = 8
local MAX_OUTLINE = 4 * (CORNER_SEG + 1)
local MAX_VERTS = MAX_OUTLINE * 3 * 2 + MAX_OUTLINE * 6
local VBYTES = VSTRIDE * MAX_VERTS
local UBO_SIZE = 256
local TILT_SMOOTH = 10
local SHADOW_UBO = 64

type Card3D = {
  rotX: Input<number>,
  rotY: Input<number>,
  depth: Input<number>,
  roundness: Input<number>,
  scale: Input<number>,
  maxTilt: Input<number>,
  tiltArea: Input<number>,
  edgeColor: Input<Color>,
  face: Input<Artboard<nil>>,
  back: Input<Artboard<nil>>,
  viewModelProperty: Input<string>,
  properties: Input<string>,
  shadowColor: Input<Color>,
  shadowOpacity: Input<number>,
  shadowOffsetX: Input<number>,
  shadowOffsetY: Input<number>,
  shadowSoftness: Input<number>,
  lightAngle: Input<number>,
  lightIntensity: Input<number>,
  glossIntensity: Input<number>,
  glossSharpness: Input<number>,
  lightColor: Input<Color>,
  ambient: Input<number>,
  foilIntensity: Input<number>,
  foilStripes: Input<number>,
  foilShift: Input<number>,
  foilAngle: Input<number>,
  shineIntensity: Input<number>,
  shineWidth: Input<number>,
  shineSpeed: Input<number>,
  cursorTracking: Input<boolean>,
  particleCells: Input<number>,
  particleGlow: Input<number>,
  glowSpeed: Input<number>,
  _time: number,
  _schemeHue: number?,
  _canvas: Canvas?,
  _gpu: GPUCanvas?,
  _msaaColor: GPUTexture?,
  _msaaView: GPUTextureView?,
  _depthTex: GPUTexture?,
  _depthView: GPUTextureView?,
  _pipe: GPUPipeline?,
  _samples: number,
  _ubo: GPUBuffer?,
  _ubuf: buffer,
  _vbo: GPUBuffer?,
  _vdata: buffer,
  _gpuSamp: GPUSampler?,
  _imgSamp: ImageSampler,
  _dummyView: GPUTextureView?,
  _inst: Artboard<nil>?,
  _backInst: Artboard<nil>?,
  _lastBack: Artboard<nil>?,
  _backCanvas: Canvas?,
  _didWatchBack: boolean,
  _faceVm: ViewModel?,
  _lastFace: Artboard<nil>?,
  _lastPath: string,
  _lastProps: string,
  _didWatch: boolean,
  _dt: number,
  _lastDepth: number,
  _lastRound: number,
  _lastW: number,
  _lastH: number,
  _faceW: number,
  _faceH: number,
  _gpuPx: number,
  _texW: number,
  _texH: number,
  _vcount: number,
  _out: GPUCanvas?,
  _blurA: GPUTexture?,
  _blurB: GPUTexture?,
  _blurAView: GPUTextureView?,
  _blurBView: GPUTextureView?,
  _shadowPipe: GPUPipeline?,
  _shadowUbo: GPUBuffer?,
  _shadowUbuf: buffer,
  _ctx: Context?,
  _hover: boolean,
  _tiltX: number,
  _tiltY: number,
  _tgtX: number,
  _tgtY: number,
  _shadowPath: Path,
  _shadowPathB: Path,
  _shadowFlip: boolean,
  _shadowPaint: Paint,
}

local function faceDims(self: Card3D): (number, number)
  local inst = self._inst
  if inst then
    local w = inst.width
    local h = inst.height
    if type(w) == 'number' and type(h) == 'number' and w > 1 and h > 1 then
      return w, h
    end
  end
  local src = self.face
  if src then
    local w = src.width
    local h = src.height
    if type(w) == 'number' and type(h) == 'number' and w > 1 and h > 1 then
      return w, h
    end
  end
  return DEFAULT_W, DEFAULT_H
end

local function gpuPxFor(fw: number, fh: number, depth: number): number
  local diag = math.sqrt(fw * fw + fh * fh)
  return math.max(64, math.ceil(diag + math.abs(depth) + 64))
end

local function texSize(fw: number, fh: number): (number, number)
  local tw = math.clamp(math.floor(fw * TEX_SCALE + 0.5), 32, MAX_TEX)
  local th = math.clamp(math.floor(fh * TEX_SCALE + 0.5), 32, MAX_TEX)
  return tw, th
end

local function writeVert(
  data: buffer,
  i: number,
  x: number,
  y: number,
  z: number,
  u: number,
  v: number,
  kind: number
)
  local o = i * VSTRIDE
  buffer.writef32(data, o + 0, x)
  buffer.writef32(data, o + 4, y)
  buffer.writef32(data, o + 8, z)
  buffer.writef32(data, o + 12, u)
  buffer.writef32(data, o + 16, v)
  buffer.writef32(data, o + 20, kind)
end

local function writeQuad(
  data: buffer,
  i: number,
  ax: number,
  ay: number,
  az: number,
  au: number,
  av: number,
  bx: number,
  by: number,
  bz: number,
  bu: number,
  bv: number,
  cx: number,
  cy: number,
  cz: number,
  cu: number,
  cv: number,
  dx: number,
  dy: number,
  dz: number,
  du: number,
  dv: number,
  kind: number
): number
  writeVert(data, i + 0, ax, ay, az, au, av, kind)
  writeVert(data, i + 1, bx, by, bz, bu, bv, kind)
  writeVert(data, i + 2, cx, cy, cz, cu, cv, kind)
  writeVert(data, i + 3, ax, ay, az, au, av, kind)
  writeVert(data, i + 4, cx, cy, cz, cu, cv, kind)
  writeVert(data, i + 5, dx, dy, dz, du, dv, kind)
  return i + 6
end

local function writeTri(
  data: buffer,
  i: number,
  ax: number,
  ay: number,
  az: number,
  au: number,
  av: number,
  bx: number,
  by: number,
  bz: number,
  bu: number,
  bv: number,
  cx: number,
  cy: number,
  cz: number,
  cu: number,
  cv: number,
  kind: number
): number
  writeVert(data, i + 0, ax, ay, az, au, av, kind)
  writeVert(data, i + 1, bx, by, bz, bu, bv, kind)
  writeVert(data, i + 2, cx, cy, cz, cu, cv, kind)
  return i + 3
end

local function uvOf(x: number, y: number, hw: number, hh: number): (number, number)
  return (x + hw) / (hw * 2), 1 - (y + hh) / (hh * 2)
end

local function buildBox(data: buffer, hd: number, hw: number, hh: number)
  local i = 0
  i = writeQuad(
    data,
    i,
    -hw,
    -hh,
    hd,
    0,
    1,
    hw,
    -hh,
    hd,
    1,
    1,
    hw,
    hh,
    hd,
    1,
    0,
    -hw,
    hh,
    hd,
    0,
    0,
    0
  )
  i = writeQuad(
    data,
    i,
    hw,
    -hh,
    -hd,
    0,
    1,
    -hw,
    -hh,
    -hd,
    1,
    1,
    -hw,
    hh,
    -hd,
    1,
    0,
    hw,
    hh,
    -hd,
    0,
    0,
    0
  )
  i = writeQuad(
    data,
    i,
    hw,
    -hh,
    hd,
    0,
    0,
    hw,
    -hh,
    -hd,
    1,
    0,
    hw,
    hh,
    -hd,
    1,
    1,
    hw,
    hh,
    hd,
    0,
    1,
    1
  )
  i = writeQuad(
    data,
    i,
    -hw,
    -hh,
    -hd,
    0,
    0,
    -hw,
    -hh,
    hd,
    1,
    0,
    -hw,
    hh,
    hd,
    1,
    1,
    -hw,
    hh,
    -hd,
    0,
    1,
    1
  )
  i = writeQuad(
    data,
    i,
    -hw,
    hh,
    hd,
    0,
    0,
    hw,
    hh,
    hd,
    1,
    0,
    hw,
    hh,
    -hd,
    1,
    1,
    -hw,
    hh,
    -hd,
    0,
    1,
    1
  )
  i = writeQuad(
    data,
    i,
    -hw,
    -hh,
    -hd,
    0,
    0,
    hw,
    -hh,
    -hd,
    1,
    0,
    hw,
    -hh,
    hd,
    1,
    1,
    -hw,
    -hh,
    hd,
    0,
    1,
    1
  )
end

local function buildRounded(
  data: buffer,
  hd: number,
  radius: number,
  hw: number,
  hh: number
): number
  local r = math.clamp(radius, 0, math.min(hw, hh) - 1)
  if r < 0.5 then
    buildBox(data, hd, hw, hh)
    return 36
  end

  local iw = hw - r
  local ih = hh - r
  local xs: { number } = {}
  local ys: { number } = {}
  local p = 0
  local function addCorner(cx: number, cy: number, a0: number, a1: number)
    for i = 0, CORNER_SEG do
      local t = i / CORNER_SEG
      local a = a0 + (a1 - a0) * t
      p += 1
      xs[p] = cx + r * math.cos(a)
      ys[p] = cy + r * math.sin(a)
    end
  end
  addCorner(iw, -ih, -math.pi * 0.5, 0)
  addCorner(iw, ih, 0, math.pi * 0.5)
  addCorner(-iw, ih, math.pi * 0.5, math.pi)
  addCorner(-iw, -ih, math.pi, math.pi * 1.5)

  local m = p
  local vi = 0
  local u0, v0 = uvOf(0, 0, hw, hh)
  for k = 1, m do
    local k2 = if k == m then 1 else k + 1
    local u1, v1 = uvOf(xs[k], ys[k], hw, hh)
    local u2, v2 = uvOf(xs[k2], ys[k2], hw, hh)
    vi = writeTri(
      data,
      vi,
      0,
      0,
      hd,
      u0,
      v0,
      xs[k],
      ys[k],
      hd,
      u1,
      v1,
      xs[k2],
      ys[k2],
      hd,
      u2,
      v2,
      0
    )
  end
  for k = 1, m do
    local k2 = if k == m then 1 else k + 1
    local u1, v1 = uvOf(xs[k], ys[k], hw, hh)
    local u2, v2 = uvOf(xs[k2], ys[k2], hw, hh)
    vi = writeTri(
      data,
      vi,
      0,
      0,
      -hd,
      u0,
      v0,
      xs[k2],
      ys[k2],
      -hd,
      u2,
      v2,
      xs[k],
      ys[k],
      -hd,
      u1,
      v1,
      0
    )
  end
  for k = 1, m do
    local k2 = if k == m then 1 else k + 1
    vi = writeQuad(
      data,
      vi,
      xs[k],
      ys[k],
      hd,
      0,
      0,
      xs[k2],
      ys[k2],
      hd,
      1,
      0,
      xs[k2],
      ys[k2],
      -hd,
      1,
      1,
      xs[k],
      ys[k],
      -hd,
      0,
      1,
      1
    )
  end
  return vi
end

local function num(v: any, fallback: number): number
  if type(v) == 'number' then
    return v
  end
  return fallback
end

local function cardOutline(
  radius: number,
  hw: number,
  hh: number
): ({ number }, { number }, number)
  local r = math.clamp(radius, 0, math.min(hw, hh) - 1)
  local xs: { number } = {}
  local ys: { number } = {}
  if r < 0.5 then
    return { -hw, hw, hw, -hw }, { -hh, -hh, hh, hh }, 4
  end
  local iw = hw - r
  local ih = hh - r
  local p = 0
  local function addCorner(cx: number, cy: number, a0: number, a1: number)
    for i = 0, CORNER_SEG do
      local t = i / CORNER_SEG
      local a = a0 + (a1 - a0) * t
      p += 1
      xs[p] = cx + r * math.cos(a)
      ys[p] = cy + r * math.sin(a)
    end
  end
  addCorner(iw, -ih, -math.pi * 0.5, 0)
  addCorner(iw, ih, 0, math.pi * 0.5)
  addCorner(-iw, ih, math.pi * 0.5, math.pi)
  addCorner(-iw, -ih, math.pi, math.pi * 1.5)
  return xs, ys, p
end

local function convexHull(pts: { { x: number, y: number } }): { { x: number, y: number } }
  if #pts < 3 then
    return pts
  end
  table.sort(pts, function(a: { x: number, y: number }, b: { x: number, y: number })
    if a.x == b.x then
      return a.y < b.y
    end
    return a.x < b.x
  end)
  local function cross(
    o: { x: number, y: number },
    a: { x: number, y: number },
    b: { x: number, y: number }
  ): number
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
  end
  local lower: { { x: number, y: number } } = {}
  for i = 1, #pts do
    while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], pts[i]) <= 0 do
      table.remove(lower)
    end
    table.insert(lower, pts[i])
  end
  local upper: { { x: number, y: number } } = {}
  for i = #pts, 1, -1 do
    while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], pts[i]) <= 0 do
      table.remove(upper)
    end
    table.insert(upper, pts[i])
  end
  table.remove(lower)
  table.remove(upper)
  for _, p in ipairs(upper) do
    table.insert(lower, p)
  end
  return lower
end

local function drawCardShadow(
  self: Card3D,
  renderer: Renderer,
  model: Mat4,
  hd: number,
  radius: number,
  scale: number
)
  local opacity = math.clamp(num(self.shadowOpacity, 45), 0, 100) / 100
  if opacity <= 0.001 then
    return
  end
  if self._shadowPath == nil then
    self._shadowPath = Path.new()
    self._shadowPathB = Path.new()
    self._shadowPaint = Paint.with({ style = 'fill', color = Color.rgb(20, 12, 40) })
    self._shadowFlip = false
  end
  if self._shadowPathB == nil then
    self._shadowPathB = Path.new()
  end
  local softness = math.max(0, num(self.shadowSoftness, 28))
  local ox = num(self.shadowOffsetX, 0)
  local oy = num(self.shadowOffsetY, 18)
  local tiltX = self._tiltX
  local tiltY = self._tiltY
  if type(tiltX) ~= 'number' then
    tiltX = 0
  end
  if type(tiltY) ~= 'number' then
    tiltY = 0
  end
  -- Keep the drop under the card as it leans toward the cursor.
  ox += tiltY * 0.85
  oy += -tiltX * 0.85
  local col = self.shadowColor
  if type(col) ~= 'number' then
    col = Color.rgb(20, 12, 40)
  end
  -- With a colour scheme on the view model, the shadow is a deep shade of
  -- its base hue.
  local baseHue = self._schemeHue
  if baseHue ~= nil then
    col = Harmony.color(0.55, 0.17, baseHue)
  end
  local tint = Color.opacity(col, opacity)
  if type(tint) ~= 'number' then
    return
  end

  local xs, ys, m = cardOutline(radius, self._faceW * 0.5, self._faceH * 0.5)
  local pts: { { x: number, y: number } } = {}
  local n = 0
  for k = 1, m do
    local p1 = model:transformPoint(xs[k], ys[k], hd)
    local p2 = model:transformPoint(xs[k], ys[k], -hd)
    n += 1
    pts[n] = { x = p1.x, y = -p1.y }
    n += 1
    pts[n] = { x = p2.x, y = -p2.y }
  end
  local hull = convexHull(pts)
  if #hull < 3 then
    return
  end

  self._shadowFlip = not self._shadowFlip
  local path = self._shadowPath
  if self._shadowFlip then
    path = self._shadowPathB
  end
  path:reset()
  path:moveTo(Vector.xy(hull[1].x, hull[1].y))
  for i = 2, #hull do
    path:lineTo(Vector.xy(hull[i].x, hull[i].y))
  end
  path:close()

  local paint = self._shadowPaint
  paint.style = 'fill'
  paint.color = tint
  paint.feather = softness

  renderer:save()
  renderer:transform(Mat2D.withTranslation(ox, oy))
  renderer:drawPath(path, paint)
  renderer:restore()
end

local function thickness(self: Card3D): number
  return math.clamp(math.abs(self.depth), 2, 60)
end

local function easeToward(current: number, target: number, dt: number): number
  local a = 1 - math.exp(-TILT_SMOOTH * math.max(dt, 0))
  return current + (target - current) * a
end

local function setPointer(self: Card3D, event: PointerEvent)
  -- If cursor tracking is disabled, don't update tilt
  if not self.cursorTracking then
    return
  end
  
  event:hit()
  self._hover = true
  local fw = self._faceW
  local fh = self._faceH
  if type(fw) ~= 'number' or fw < 1 then
    fw = DEFAULT_W
  end
  if type(fh) ~= 'number' or fh < 1 then
    fh = DEFAULT_H
  end
  local area = math.max(8, num(self.tiltArea, math.max(fw, fh)))
  local maxTilt = num(self.maxTilt, 18)
  local nx = math.clamp(event.position.x / area, -1, 1)
  local ny = math.clamp(event.position.y / area, -1, 1)
  -- Face the pointer: right → yaw (unchanged), down → pitch flipped.
  self._tgtY = nx * maxTilt
  self._tgtX = ny * maxTilt
  local ctx = self._ctx
  if ctx then
    ctx:markNeedsUpdate()
  end
end

local function pointerMove(self: Card3D, event: PointerEvent)
  -- If cursor tracking is disabled, don't process pointer events
  if self.cursorTracking then
    setPointer(self, event)
  end
end

local function pointerDown(self: Card3D, event: PointerEvent)
  -- If cursor tracking is disabled, don't process pointer events
  if self.cursorTracking then
    setPointer(self, event)
  end
end

local function pointerExit(self: Card3D, event: PointerEvent)
  -- If cursor tracking is disabled, don't reset tilt
  if self.cursorTracking then
    self._hover = false
    self._tgtX = 0
    self._tgtY = 0
    local ctx = self._ctx
    if ctx then
      ctx:markNeedsUpdate()
    end
  end
end

local function kick(self: Card3D)
  local ctx = self._ctx
  if ctx then
    ctx:markNeedsUpdate()
  end
end

local function splitNames(list: string): { string }
  local names: { string } = {}
  for part in string.gmatch(list, '[^,]+') do
    local name = string.gsub(part, '^%s+', '')
    name = string.gsub(name, '%s+$', '')
    if name ~= '' then
      table.insert(names, name)
    end
  end
  return names
end

local function vmKeys(self: Card3D, source: ViewModel, clone: ViewModel): { string }
  local seen: { [string]: boolean } = {}
  local keys: { string } = {}
  local function add(name: string)
    if name == '' or name == 'new' or seen[name] then
      return
    end
    seen[name] = true
    table.insert(keys, name)
  end
  local function from(vm: ViewModel)
    pcall(function()
      for k, _ in pairs(vm :: any) do
        if type(k) == 'string' then
          add(k)
        end
      end
    end)
  end
  from(source)
  from(clone)
  local listed = self.properties
  if type(listed) == 'string' then
    for _, name in ipairs(splitNames(listed)) do
      add(name)
    end
  end
  return keys
end

local function bindViewModel(self: Card3D, source: ViewModel, clone: ViewModel)
  local function readValue(prop: any): any
    local ok, val = pcall(function()
      return prop.value
    end)
    if ok then
      return val
    end
    return nil
  end
  local function bindValue(srcProp: any, dstProp: any): boolean
    if not (srcProp and dstProp) then
      return false
    end
    local val = readValue(srcProp)
    if val == nil and readValue(dstProp) == nil then
      return false
    end
    local okSet = pcall(function()
      dstProp.value = srcProp.value
    end)
    if not okSet then
      return false
    end
    srcProp:addListener(self, function(_anchor: any)
      pcall(function()
        dstProp.value = srcProp.value
      end)
      kick(self)
    end)
    return true
  end
  for _, name in ipairs(vmKeys(self, source, clone)) do
    local st = source:getTrigger(name)
    local ct = clone:getTrigger(name)
    if st and ct then
      st:addListener(self, function(_anchor: any)
        ct:fire()
        kick(self)
      end)
    elseif bindValue(source:getNumber(name), clone:getNumber(name)) then
    elseif bindValue(source:getBoolean(name), clone:getBoolean(name)) then
    elseif bindValue(source:getString(name), clone:getString(name)) then
    elseif bindValue(source:getColor(name), clone:getColor(name)) then
    elseif bindValue(source:getEnum(name), clone:getEnum(name)) then
    elseif bindValue(source:getImage(name), clone:getImage(name)) then
    else
      local svm = source:getViewModel(name)
      local cvm = clone:getViewModel(name)
      if svm and cvm then
        local sv = readValue(svm)
        local cv = readValue(cvm)
        if sv and cv then
          bindViewModel(self, sv, cv)
        end
      end
    end
  end
end

local function boundSource(self: Card3D): ViewModel?
  local ctx = self._ctx
  if not ctx then
    return nil
  end
  local path = self.viewModelProperty
  if type(path) ~= 'string' then
    path = ''
  end
  local function from(card: ViewModel?): ViewModel?
    if not card then
      return nil
    end
    if path ~= '' then
      local prop = card:getViewModel(path)
      if prop then
        return prop.value
      end
      return nil
    end
    return card
  end
  local found = from(ctx:viewModel())
  if found then
    return found
  end
  found = from(ctx:rootViewModel())
  if found then
    return found
  end
  local dc = ctx:dataContext()
  while dc do
    found = from(dc:viewModel())
    if found then
      return found
    end
    dc = dc:parent()
  end
  return nil
end

local function watchFaceData(self: Card3D, source: ViewModel, clone: ViewModel)
  if self._didWatch then
    return
  end
  self._didWatch = true
  bindViewModel(self, source, clone)
end

local function ensureInstance(self: Card3D)
  local src = self.face
  if not src then
    self._inst = nil
    self._faceVm = nil
    return
  end
  if not self._inst then
    local inst = src:instance()
    if inst then
      inst.frameOrigin = true
      self._inst = inst
    end
  end
  local inst = self._inst
  if not inst then
    return
  end
  local clone = inst.data :: any
  self._faceVm = clone
  local source = boundSource(self)
  if source and clone then
    watchFaceData(self, source, clone)
  end
end

local function renderFace(self: Card3D)
  local canvas = self._canvas
  local inst = self._inst
  if not (canvas and inst) then
    return
  end
  inst:advance(0)
  local tw = math.max(1, self._texW)
  local th = math.max(1, self._texH)
  local iw = math.max(1, inst.width)
  local ih = math.max(1, inst.height)
  local sx = tw / iw
  local sy = th / ih
  local r = canvas:beginFrame({ clearColor = 0x00000000 })
  r:save()
  r:transform(Mat2D.withScaleAndTranslation(sx, sy, 0, 0))
  inst:draw(r)
  r:restore()
  canvas:endFrame()
end

-- The back artboard, instanced once and drawn into its own texture at the
-- face's texture size (the card is sized from the face). Its data gets the
-- same relay as the face, so a back that shows the face's data (the photo)
-- updates with it. A back bound to the nested model itself (no `front`)
-- is fed from that nested model.
local function ensureBackInstance(self: Card3D)
  local src = self.back
  if src ~= self._lastBack then
    self._backInst = nil
    self._lastBack = src
    self._didWatchBack = false
  end
  if src and not self._backInst then
    local inst = src:instance()
    if inst then
      inst.frameOrigin = true
      self._backInst = inst
    end
  end
  local inst = self._backInst
  if not inst or self._didWatchBack then
    return
  end
  local clone = inst.data :: any
  local source = boundSource(self)
  if not (source and clone) then
    return
  end
  local from = source
  local path = self.viewModelProperty
  if (type(path) ~= 'string' or path == '') and clone:getViewModel('front') == nil then
    local nested = source:getViewModel('front')
    if nested and nested.value then
      from = nested.value
    end
  end
  self._didWatchBack = true
  bindViewModel(self, from, clone)
end

local function renderBack(self: Card3D)
  local inst = self._backInst
  local ctx = self._ctx
  if not (inst and ctx) then
    return
  end
  local tw = math.max(1, self._texW)
  local th = math.max(1, self._texH)
  if not self._backCanvas then
    self._backCanvas = ctx:canvas({ width = tw, height = th })
  end
  local canvas = self._backCanvas
  if not canvas then
    return
  end
  if canvas.width ~= tw or canvas.height ~= th then
    canvas:resize(tw, th)
  end
  inst:advance(0)
  local sx = tw / math.max(1, inst.width)
  local sy = th / math.max(1, inst.height)
  local r = canvas:beginFrame({ clearColor = 0x00000000 })
  r:save()
  r:transform(Mat2D.withScaleAndTranslation(sx, sy, 0, 0))
  inst:draw(r)
  r:restore()
  canvas:endFrame()
end

local function _initShadow(self: Card3D, ctx: Context, fmt: string)
  local sh = ctx:shader('CardShadowShader')
  if not sh then
    print('[Card3D] CardShadowShader missing')
    return
  end
  local gpuPx = self._gpuPx
  if type(gpuPx) ~= 'number' or gpuPx < 8 then
    gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14)
  end
  local compositePx = gpuPx + 2 * PAD
  local function makeRt(): (GPUTexture, GPUTextureView)
    local t = GPUTexture.new({
      width = compositePx,
      height = compositePx,
      format = fmt :: any,
      renderTarget = true,
    })
    return t, t:view()
  end
  local a, av = makeRt()
  local b, bv = makeRt()
  self._blurA = a
  self._blurAView = av
  self._blurB = b
  self._blurBView = bv
  self._out = ctx:gpuCanvas({ width = compositePx, height = compositePx })
  self._shadowPipe = GPUPipeline.new({
    vertex = sh,
    fragment = sh,
    vertexLayout = {},
    colorTargets = {
      {
        format = fmt :: any,
        blend = {
          srcColor = 'src-alpha',
          dstColor = 'one-minus-src-alpha',
          colorOp = 'add',
          srcAlpha = 'one',
          dstAlpha = 'one-minus-src-alpha',
          alphaOp = 'add',
        },
      },
    },
    cullMode = 'none',
    sampleCount = 1,
  })
  self._shadowUbo = GPUBuffer.new({ size = SHADOW_UBO, usage = 'uniform' })
  if buffer.len(self._shadowUbuf) < SHADOW_UBO then
    self._shadowUbuf = buffer.create(SHADOW_UBO)
  end
end

local function writeShadowUbo(
  self: Card3D,
  rgb: { number },
  opacity: number,
  dirX: number,
  dirY: number,
  radius: number,
  mode: number,
  offU: number,
  offV: number
)
  local ubo = self._shadowUbo
  if not ubo then
    return
  end
  local buf = self._shadowUbuf
  local gpuPx = self._gpuPx
  if type(gpuPx) ~= 'number' or gpuPx < 8 then
    gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14)
  end
  local compositePx = gpuPx + 2 * PAD
  local texel = 1 / compositePx
  buffer.writef32(buf, 0, rgb[1])
  buffer.writef32(buf, 4, rgb[2])
  buffer.writef32(buf, 8, rgb[3])
  buffer.writef32(buf, 12, opacity)
  buffer.writef32(buf, 16, texel)
  buffer.writef32(buf, 20, texel)
  buffer.writef32(buf, 24, dirX)
  buffer.writef32(buf, 28, dirY)
  buffer.writef32(buf, 32, radius)
  buffer.writef32(buf, 36, mode)
  buffer.writef32(buf, 40, offU)
  buffer.writef32(buf, 44, offV)
  buffer.writef32(buf, 48, compositePx / gpuPx)
  buffer.writef32(buf, 52, compositePx / gpuPx)
  buffer.writef32(buf, 56, PAD / gpuPx)
  buffer.writef32(buf, 60, PAD / gpuPx)
  ubo:write(buf)
end

local function shadowPass(
  self: Card3D,
  host: GPUCanvas,
  targetView: GPUTextureView?,
  srcView: GPUTextureView,
  loadOp: string
)
  local pipe = self._shadowPipe
  local ubo = self._shadowUbo
  local samp = self._gpuSamp
  if not (pipe and ubo and samp) then
    return
  end
  local bg = GPUBindGroup.new({
    layout = pipe:getBindGroupLayout(0),
    ubos = { { slot = 0, buffer = ubo } },
    textures = { { slot = 1, view = srcView } },
    samplers = { { slot = 2, sampler = samp } },
  })
  local colorAttach
  if targetView then
    colorAttach = {
      view = targetView,
      loadOp = loadOp,
      storeOp = 'store',
      clearColor = { 0, 0, 0, 0 },
    }
  else
    colorAttach = {
      loadOp = loadOp,
      storeOp = 'store',
      clearColor = { 0, 0, 0, 0 },
    }
  end
  local passDesc: { [string]: any } = { color = { colorAttach } }
  local pass = host:beginRenderPass(passDesc :: any)
  pass:setPipeline(pipe)
  pass:setBindGroup(0, bg)
  pass:draw(3)
  pass:finish()
end

local function _compositeShadow(self: Card3D, gc: GPUCanvas): boolean
  local out = self._out
  local aView = self._blurAView
  local bView = self._blurBView
  if not (out and aView and bView and self._shadowPipe and self._shadowUbo) then
    return false
  end
  local opacity = math.clamp(num(self.shadowOpacity, 45), 0, 100) / 100
  if opacity <= 0.001 then
    return false
  end
  local rgb = { 0.08, 0.05, 0.16, 1 }
  if self.shadowColor ~= nil then
    rgb = Color.toFloat(self.shadowColor)
  end
  local gpuPx = self._gpuPx
  if type(gpuPx) ~= 'number' or gpuPx < 8 then
    gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14)
  end
  local compositePx = gpuPx + 2 * PAD
  local softness = math.clamp(num(self.shadowSoftness, 28), 0, PAD)
  local ox = math.clamp(num(self.shadowOffsetX, 0), -PAD, PAD)
  local oy = math.clamp(num(self.shadowOffsetY, 18), -PAD, PAD)
  local offU = ox / compositePx
  local offV = oy / compositePx
  local cardView = gc:colorView()

  writeShadowUbo(self, rgb, opacity, 1, 0, softness, 0, 0, 0)
  shadowPass(self, out, aView, cardView, 'clear')
  writeShadowUbo(self, rgb, opacity, 1, 0, softness, 1, 0, 0)
  shadowPass(self, out, bView, aView, 'clear')
  writeShadowUbo(self, rgb, opacity, 0, 1, softness, 1, 0, 0)
  shadowPass(self, out, aView, bView, 'clear')
  writeShadowUbo(self, rgb, opacity, 0, 0, softness, 3, offU, offV)
  shadowPass(self, out, nil, aView, 'clear')
  writeShadowUbo(self, rgb, opacity, 0, 0, 0, 2, 0, 0)
  shadowPass(self, out, nil, cardView, 'load')
  return true
end

local function initGpu(self: Card3D, ctx: Context): boolean
  local sh = ctx:shader('Card3DShader')
  if not sh then
    print('[Card3D] Card3DShader missing')
    return false
  end

  local samples = MSAA
  local feats = ctx:features()
  if feats.maxSamples < samples then
    samples = math.max(1, feats.maxSamples)
  end

  local gpuPx = self._gpuPx
  if type(gpuPx) ~= 'number' or gpuPx < 8 then
    gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14)
    self._gpuPx = gpuPx
  end

  local gc = ctx:gpuCanvas({ width = gpuPx, height = gpuPx })
  local fmt = gc.format

  local msaaColor: GPUTexture? = nil
  local msaaView: GPUTextureView? = nil
  if samples > 1 then
    msaaColor = GPUTexture.new({
      width = gpuPx,
      height = gpuPx,
      format = fmt,
      renderTarget = true,
      sampleCount = samples,
    })
    msaaView = msaaColor:view()
  end

  local depth = GPUTexture.new({
    width = gpuPx,
    height = gpuPx,
    format = 'depth16unorm',
    renderTarget = true,
    sampleCount = samples,
  })

  local pipe = GPUPipeline.new({
    vertex = sh,
    fragment = sh,
    vertexLayout = {
      {
        stride = VSTRIDE,
        attributes = {
          { format = 'float32x3', slot = 0, offset = 0 },
          { format = 'float32x2', slot = 1, offset = 12 },
          { format = 'float32', slot = 2, offset = 20 },
        },
      },
    },
    colorTargets = {
      {
        format = fmt,
        blend = {
          srcColor = 'src-alpha',
          dstColor = 'one-minus-src-alpha',
          colorOp = 'add',
          srcAlpha = 'one',
          dstAlpha = 'one-minus-src-alpha',
          alphaOp = 'add',
        },
      },
    },
    depthStencil = { format = 'depth16unorm', compare = 'less', write = true },
    cullMode = 'none',
    sampleCount = samples,
  })

  local dummy = GPUTexture.new({ width = 1, height = 1, format = 'rgba8unorm' })
  local px = buffer.create(4)
  buffer.writeu8(px, 0, 255)
  buffer.writeu8(px, 1, 255)
  buffer.writeu8(px, 2, 255)
  buffer.writeu8(px, 3, 255)
  dummy:upload({ data = px })

  self._gpuSamp = GPUSampler.new({
    min = 'linear',
    mag = 'linear',
    wrapU = 'clamp-to-edge',
    wrapV = 'clamp-to-edge',
  })

  self._gpu = gc
  self._msaaColor = msaaColor
  self._msaaView = msaaView
  self._depthTex = depth
  self._depthView = depth:view()
  self._samples = samples
  self._pipe = pipe
  self._ubo = GPUBuffer.new({ size = UBO_SIZE, usage = 'uniform' })
  self._ubuf = buffer.create(UBO_SIZE)
  self._vbo = GPUBuffer.new({ size = VBYTES, usage = 'vertex' })
  self._vdata = buffer.create(VBYTES)
  self._dummyView = dummy:view()
  self._lastDepth = -1
  self._lastRound = -1
  self._lastW = -1
  self._lastH = -1
  self._vcount = 36
  return true
end

local function rebuildRt(self: Card3D, gpuPx: number)
  local gc = self._gpu
  if not gc then
    return
  end
  local samples = self._samples
  if type(samples) ~= 'number' then
    samples = MSAA
  end
  local fmt = gc.format
  local msaaColor: GPUTexture? = nil
  local msaaView: GPUTextureView? = nil
  if samples > 1 then
    msaaColor = GPUTexture.new({
      width = gpuPx,
      height = gpuPx,
      format = fmt,
      renderTarget = true,
      sampleCount = samples,
    })
    msaaView = msaaColor:view()
  end
  local depth = GPUTexture.new({
    width = gpuPx,
    height = gpuPx,
    format = 'depth16unorm',
    renderTarget = true,
    sampleCount = samples,
  })
  self._msaaColor = msaaColor
  self._msaaView = msaaView
  self._depthTex = depth
  self._depthView = depth:view()
end

local function ensureGpuSize(self: Card3D, fw: number, fh: number)
  local ctx = self._ctx
  if not ctx then
    return
  end
  local d = thickness(self)
  local gpx = gpuPxFor(fw, fh, d)
  local tw, th = texSize(fw, fh)
  self._faceW = fw
  self._faceH = fh
  self._texW = tw
  self._texH = th

  local canvas = self._canvas
  if not canvas then
    self._canvas = ctx:canvas({ width = tw, height = th })
  elseif canvas.width ~= tw or canvas.height ~= th then
    canvas:resize(tw, th)
  end

  if not self._gpu then
    self._gpuPx = gpx
    initGpu(self, ctx)
    return
  end
  if self._gpuPx == gpx and self._gpu.width == gpx then
    return
  end
  self._gpuPx = gpx
  self._gpu:resize(gpx, gpx)
  rebuildRt(self, gpx)
end

local function init(self: Card3D, ctx: Context): boolean
  self._ctx = ctx
  self._dt = 0
  self._tiltX = 0
  self._tiltY = 0
  self._tgtX = 0
  self._tgtY = 0
  self._hover = false
  self._didWatch = false
  self._lastPath = ''
  self._lastProps = ''
  self._imgSamp = ImageSampler('clamp', 'clamp', 'bilinear')
  self._faceW = DEFAULT_W
  self._faceH = DEFAULT_H
  self._gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14)
  local tw, th = texSize(DEFAULT_W, DEFAULT_H)
  self._texW = tw
  self._texH = th
  self._lastW = -1
  self._lastH = -1
  self._canvas = ctx:canvas({ width = tw, height = th })
  initGpu(self, ctx)
  ensureInstance(self)
  return true
end

local function update(self: Card3D)
  local src = self.face
  local path = self.viewModelProperty
  if type(path) ~= 'string' then
    path = ''
  end
  local props = self.properties
  if type(props) ~= 'string' then
    props = ''
  end
  if src ~= self._lastFace then
    self._inst = nil
    self._faceVm = nil
    self._didWatch = false
    self._lastFace = src
  end
  if path ~= self._lastPath or props ~= self._lastProps then
    self._didWatch = false
    self._lastPath = path
    self._lastProps = props
  end
  ensureInstance(self)
  local fw, fh = faceDims(self)
  self._faceW = fw
  self._faceH = fh
end

local function advance(self: Card3D, seconds: number): boolean
  self._dt = seconds
  if type(self._tiltX) ~= 'number' then
    self._tiltX = 0
    self._tiltY = 0
    self._tgtX = 0
    self._tgtY = 0
  end
  self._time = ((self._time or 0) + seconds) % 1000
  local _, schemeHue = Harmony.read(boundSource(self))
  self._schemeHue = schemeHue
  self._tiltX = easeToward(self._tiltX, self._tgtX, seconds)
  self._tiltY = easeToward(self._tiltY, self._tgtY, seconds)
  ensureInstance(self)
  local inst = self._inst
  if inst then
    inst:advance(seconds)
  end
  ensureBackInstance(self)
  local backInst = self._backInst
  if backInst then
    backInst:advance(seconds)
  end
  return true
end

local function draw(self: Card3D, renderer: Renderer)
  ensureInstance(self)
  local fw, fh = faceDims(self)
  ensureGpuSize(self, fw, fh)
  renderFace(self)
  ensureBackInstance(self)
  renderBack(self)
  local gc = self._gpu
  local pipe = self._pipe
  local ubo = self._ubo
  local vbo = self._vbo
  local depthTex = self._depthTex
  local gpuSamp = self._gpuSamp
  if not (gc and pipe and ubo and vbo and depthTex and gpuSamp) then
    return
  end

  if self._lastRound == nil then
    self._lastRound = -1
    self._lastW = -1
    self._lastH = -1
    self._vcount = 36
  end

  local hw = fw * 0.5
  local hh = fh * 0.5
  local hd = thickness(self) * 0.5
  local roundness = self.roundness
  if type(roundness) ~= 'number' then
    roundness = 20
  end
  local r = math.clamp(roundness, 0, math.min(hw, hh) - 1)
  local vdata = self._vdata
  if buffer.len(vdata) < VBYTES then
    vdata = buffer.create(VBYTES)
    self._vdata = vdata
    vbo = GPUBuffer.new({ size = VBYTES, usage = 'vertex' })
    self._vbo = vbo
  end
  if
    math.abs(hd - self._lastDepth) > 0.01
    or math.abs(r - self._lastRound) > 0.01
    or math.abs(fw - self._lastW) > 0.01
    or math.abs(fh - self._lastH) > 0.01
  then
    self._vcount = buildRounded(vdata, hd, r, hw, hh)
    vbo:write(vdata)
    self._lastDepth = hd
    self._lastRound = r
    self._lastW = fw
    self._lastH = fh
  end

  local tiltX = self._tiltX
  local tiltY = self._tiltY
  if type(tiltX) ~= 'number' then
    tiltX = 0
  end
  if type(tiltY) ~= 'number' then
    tiltY = 0
  end
  -- Tilt after the turn, so the cursor leans the card the same way whether
  -- the front or the back is showing.
  local model = Mat4.fromRotationY(math.rad(tiltY))
    * Mat4.fromRotationX(math.rad(tiltX))
    * Mat4.fromRotationY(math.rad(self.rotY))
    * Mat4.fromRotationX(math.rad(self.rotX))
  local gpuHw = self._gpuPx * 0.5
  local proj = Mat4.ortho(-gpuHw, gpuHw, -gpuHw, gpuHw, -400, 400)
  local mvp = proj * model
  if buffer.len(self._ubuf) < UBO_SIZE then
    self._ubuf = buffer.create(UBO_SIZE)
    ubo = GPUBuffer.new({ size = UBO_SIZE, usage = 'uniform' })
    self._ubo = ubo
  end
  mvp:writeToBuffer(self._ubuf, 0)
  model:writeToBuffer(self._ubuf, 64)
  local ec = Color.toFloat(self.edgeColor)
  buffer.writef32(self._ubuf, 128, ec[1])
  buffer.writef32(self._ubuf, 132, ec[2])
  buffer.writef32(self._ubuf, 136, ec[3])
  buffer.writef32(self._ubuf, 140, ec[4])
  buffer.writef32(self._ubuf, 144, math.rad(num(self.lightAngle, 90)))
  buffer.writef32(self._ubuf, 148, num(self.lightIntensity, 25) / 100)
  buffer.writef32(self._ubuf, 152, num(self.glossIntensity, 40) / 100)
  buffer.writef32(self._ubuf, 156, num(self.glossSharpness, 40) / 100)
  buffer.writef32(self._ubuf, 160, 0.55)
  buffer.writef32(self._ubuf, 164, num(self.ambient, 42) / 100)
  buffer.writef32(self._ubuf, 168, 0)
  -- params.w: seconds, for the particle glow on the back.
  buffer.writef32(self._ubuf, 172, self._time or 0)
  local lc = { 1, 0.973, 0.902, 1 }
  if self.lightColor ~= nil then
    lc = Color.toFloat(self.lightColor)
  end
  buffer.writef32(self._ubuf, 176, lc[1])
  buffer.writef32(self._ubuf, 180, lc[2])
  buffer.writef32(self._ubuf, 184, lc[3])
  buffer.writef32(self._ubuf, 188, lc[4])
  buffer.writef32(self._ubuf, 192, num(self.foilIntensity, 40) / 100)
  buffer.writef32(self._ubuf, 196, num(self.foilStripes, 3))
  buffer.writef32(self._ubuf, 200, num(self.foilShift, 60) / 100)
  buffer.writef32(self._ubuf, 204, math.rad(num(self.foilAngle, 45)))
  buffer.writef32(self._ubuf, 208, math.max(8, num(self.particleCells, 70)))
  buffer.writef32(self._ubuf, 212, math.max(0, num(self.particleGlow, 60)) / 100)
  buffer.writef32(self._ubuf, 216, num(self.glowSpeed, 1))
  buffer.writef32(self._ubuf, 220, 0)
  -- shine: intensity 0-1, rim width, speed; rim: face half-size and corner radius (mesh units).
  buffer.writef32(self._ubuf, 224, math.max(0, num(self.shineIntensity, 60)) / 100)
  buffer.writef32(self._ubuf, 228, math.max(0.5, num(self.shineWidth, 10)))
  buffer.writef32(self._ubuf, 232, num(self.shineSpeed, 0.8))
  buffer.writef32(self._ubuf, 236, 0)
  buffer.writef32(self._ubuf, 240, hw)
  buffer.writef32(self._ubuf, 244, hh)
  buffer.writef32(self._ubuf, 248, r)
  buffer.writef32(self._ubuf, 252, 0)
  ubo:write(self._ubuf)

  local faceView = self._dummyView
  local canvas = self._canvas
  if canvas and canvas.image then
    faceView = canvas.image:view()
  end
  if not faceView then
    return
  end
  local backView = faceView
  local backCanvas = self._backCanvas
  if self._backInst and backCanvas and backCanvas.image then
    backView = backCanvas.image:view()
  end

  local bg = GPUBindGroup.new({
    layout = pipe:getBindGroupLayout(0),
    ubos = { { slot = 0, buffer = ubo } },
    textures = { { slot = 1, view = faceView }, { slot = 3, view = backView } },
    samplers = { { slot = 2, sampler = gpuSamp } },
  })

  local msaaView = self._msaaView
  local depthView = self._depthView
  if not depthView then
    return
  end
  local colorAttach
  if msaaView then
    colorAttach = {
      view = msaaView,
      resolveTarget = gc:colorView(),
      loadOp = 'clear',
      storeOp = 'discard',
      clearColor = { 0, 0, 0, 0 },
    }
  else
    colorAttach = {
      loadOp = 'clear',
      storeOp = 'store',
      clearColor = { 0, 0, 0, 0 },
    }
  end

  local passDesc: { [string]: any } = {
    color = { colorAttach },
    depthStencil = {
      view = depthView,
      depthLoadOp = 'clear',
      depthStoreOp = 'discard',
      depthClearValue = 1,
    },
  }
  local pass = gc:beginRenderPass(passDesc :: any)
  pass:setPipeline(pipe)
  pass:setVertexBuffer(0, vbo)
  pass:setBindGroup(0, bg)
  pass:draw(self._vcount)
  pass:finish()

  local s = 1
  if type(self.scale) == 'number' then
    s = math.max(0.01, self.scale)
  end
  renderer:save()
  renderer:transform(Mat2D.withScale(s, s))
  drawCardShadow(self, renderer, model, hd, r, s)
  renderer:save()
  renderer:transform(Mat2D.withTranslation(-gpuHw, -gpuHw))
  renderer:drawImage(gc.image, self._imgSamp, 'srcOver', 1)
  renderer:restore()
  renderer:restore()
end

return function(): Node<Card3D>
  return {
    rotX = 0,
    rotY = 22,
    depth = 14,
    roundness = 20,
    scale = 1,
    maxTilt = 18,
    tiltArea = 180,
    edgeColor = Color.rgb(42, 24, 97),
    face = late(),
    back = late(),
    viewModelProperty = 'propertyOfMercari',
    properties = 'idle,lookDown,twitch',
    shadowColor = Color.rgb(20, 12, 40),
    shadowOpacity = 45,
    shadowOffsetX = 0,
    shadowOffsetY = 18,
    shadowSoftness = 28,
    lightAngle = 90,
    lightIntensity = 25,
    glossIntensity = 40,
    glossSharpness = 40,
    lightColor = Color.rgb(255, 248, 230),
    ambient = 42,
    foilIntensity = 40,
    foilStripes = 3,
    foilShift = 60,
    foilAngle = 45,
    shineIntensity = 60,
    shineWidth = 10,
    shineSpeed = 0.8,
    cursorTracking = false,
    particleCells = 70,
    particleGlow = 60,
    glowSpeed = 1,
    _time = 0,
    _schemeHue = nil,
    _canvas = nil,
    _gpu = nil,
    _msaaColor = nil,
    _msaaView = nil,
    _depthTex = nil,
    _depthView = nil,
    _pipe = nil,
    _ubo = nil,
    _ubuf = buffer.create(UBO_SIZE),
    _vbo = nil,
    _vdata = buffer.create(VBYTES),
    _gpuSamp = nil,
    _imgSamp = ImageSampler('clamp', 'clamp', 'bilinear'),
    _dummyView = nil,
    _inst = nil,
    _backInst = nil,
    _lastBack = nil,
    _backCanvas = nil,
    _didWatchBack = false,
    _faceVm = nil,
    _lastFace = nil,
    _lastPath = '',
    _lastProps = '',
    _didWatch = false,
    _dt = 0,
    _lastDepth = -1,
    _lastRound = -1,
    _lastW = -1,
    _lastH = -1,
    _faceW = DEFAULT_W,
    _faceH = DEFAULT_H,
    _gpuPx = gpuPxFor(DEFAULT_W, DEFAULT_H, 14),
    _texW = DEFAULT_W * TEX_SCALE,
    _texH = DEFAULT_H * TEX_SCALE,
    _vcount = 36,
    _samples = 1,
    _out = nil,
    _blurA = nil,
    _blurB = nil,
    _blurAView = nil,
    _blurBView = nil,
    _shadowPipe = nil,
    _shadowUbo = nil,
    _shadowUbuf = buffer.create(SHADOW_UBO),
    _ctx = nil,
    _hover = false,
    _tiltX = 0,
    _tiltY = 0,
    _tgtX = 0,
    _tgtY = 0,
    _shadowPath = Path.new(),
    _shadowPathB = Path.new(),
    _shadowFlip = false,
    _shadowPaint = Paint.with({
      style = 'fill',
      color = Color.rgb(20, 12, 40),
      feather = 28,
    }),
    init = init,
    update = update,
    advance = advance,
    draw = draw,
    pointerMove = pointerMove,
    pointerDown = pointerDown,
    pointerExit = pointerExit,
  }
end
