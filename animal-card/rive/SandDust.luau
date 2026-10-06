-- SandDust node: drives SandDustShader (WGSL in the Shaders panel).
-- Overlay of drifting sand / dust motes. Drop on an artboard over a gradient.
-- Width / height size the GPU canvas (defaults match the dither artboard).
-- cursorSensitivity (0-100) how strongly dust parts around the pointer.
-- cursorRadius (0-100) how wide that soft field is.
-- dustColor tints grains. hazeColor1 / hazeColor2 split the veil.

local UBO_SIZE = 160
local DEFAULT_W = 1220
local DEFAULT_H = 567
local PTR_SMOOTH = 16
local LAG1_SMOOTH = 8
local LAG2_SMOOTH = 4.5
local LAG3_SMOOTH = 2.6
local LAG4_SMOOTH = 1.5
local VEL_SMOOTH = 20
local VEL_MAX = 6

type SandDust = {
  width: Input<number>,
  height: Input<number>,
  density: Input<number>,
  grainSize: Input<number>,
  softness: Input<number>,
  opacity: Input<number>,
  speed: Input<number>,
  windAngle: Input<number>,
  turbulence: Input<number>,
  falloff: Input<number>,
  sparkle: Input<number>,
  haze: Input<number>,
  seed: Input<number>,
  cursorSensitivity: Input<number>,
  cursorRadius: Input<number>,
  dustColor: Input<Color>,
  hazeColor1: Input<Color>,
  hazeColor2: Input<Color>,
  _gpu: GPUCanvas?,
  _pipe: GPUPipeline?,
  _ubo: GPUBuffer?,
  _ubuf: buffer,
  _imgSamp: ImageSampler,
  _hitPath: Path,
  _hitPaint: Paint,
  _hitW: number,
  _hitH: number,
  _ctx: Context?,
  _t: number,
  _gpuW: number,
  _gpuH: number,
  _hover: boolean,
  _tgtX: number,
  _tgtY: number,
  _ptrX: number,
  _ptrY: number,
  _lag1X: number,
  _lag1Y: number,
  _lag2X: number,
  _lag2Y: number,
  _lag3X: number,
  _lag3Y: number,
  _lag4X: number,
  _lag4Y: number,
  _ptrAmt: number,
  _velX: number,
  _velY: number,
  _lastTgtX: number,
  _lastTgtY: number,
}

local function num(v: any, fallback: number): number
  if type(v) == 'number' then
    return v
  end
  return fallback
end

local function dim(v: any, fallback: number): number
  local n = num(v, fallback)
  if n <= 0 then
    return fallback
  end
  return n
end

local function easeRate(current: number, target: number, dt: number, rate: number): number
  local a = 1 - math.exp(-rate * math.max(dt, 0))
  return current + (target - current) * a
end

local function initGpu(self: SandDust, ctx: Context): boolean
  local sh = ctx:shader('SandDustShader')
  if not sh then
    print('[SandDust] SandDustShader missing')
    return false
  end

  local w = math.max(8, math.floor(dim(self.width, DEFAULT_W) + 0.5))
  local h = math.max(8, math.floor(dim(self.height, DEFAULT_H) + 0.5))
  local gc = ctx:gpuCanvas({ width = w, height = h })
  local fmt = gc.format

  local pipe = GPUPipeline.new({
    vertex = sh,
    fragment = sh,
    vertexLayout = {},
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
    cullMode = 'none',
    sampleCount = 1,
  })

  self._gpu = gc
  self._pipe = pipe
  self._ubo = GPUBuffer.new({ size = UBO_SIZE, usage = 'uniform' })
  self._ubuf = buffer.create(UBO_SIZE)
  self._gpuW = w
  self._gpuH = h
  return true
end

local function ensureSize(self: SandDust)
  local gc = self._gpu
  if not gc then
    return
  end
  local w = math.max(8, math.floor(dim(self.width, DEFAULT_W) + 0.5))
  local h = math.max(8, math.floor(dim(self.height, DEFAULT_H) + 0.5))
  if w == self._gpuW and h == self._gpuH and gc.width == w then
    return
  end
  gc:resize(w, h)
  self._gpuW = w
  self._gpuH = h
end

local function ensureHit(self: SandDust, w: number, h: number)
  if self._hitW == w and self._hitH == h then
    return
  end
  local path = self._hitPath
  path:reset()
  local hw = w * 0.5
  local hh = h * 0.5
  path:moveTo(Vector.xy(-hw, -hh))
  path:lineTo(Vector.xy(hw, -hh))
  path:lineTo(Vector.xy(hw, hh))
  path:lineTo(Vector.xy(-hw, hh))
  path:close()
  self._hitW = w
  self._hitH = h
end

local function init(self: SandDust, ctx: Context): boolean
  self._ctx = ctx
  self._t = 0
  self._imgSamp = ImageSampler('clamp', 'clamp', 'bilinear')
  self._hitPaint = Paint.with({
    style = 'fill',
    color = Color.rgba(0, 0, 0, 1),
  })
  initGpu(self, ctx)
  return true
end

local function update(self: SandDust) end

local function advance(self: SandDust, seconds: number): boolean
  if type(self._velX) ~= 'number' then
    self._velX = 0
    self._velY = 0
    self._lastTgtX = self._tgtX
    self._lastTgtY = self._tgtY
  end
  if type(self._lag1X) ~= 'number' then
    self._lag1X = self._ptrX
    self._lag1Y = self._ptrY
    self._lag2X = self._ptrX
    self._lag2Y = self._ptrY
    self._lag3X = self._ptrX
    self._lag3Y = self._ptrY
    self._lag4X = self._ptrX
    self._lag4Y = self._ptrY
  end
  self._t += seconds
  self._ptrX = easeRate(self._ptrX, self._tgtX, seconds, PTR_SMOOTH)
  self._ptrY = easeRate(self._ptrY, self._tgtY, seconds, PTR_SMOOTH)
  self._lag1X = easeRate(self._lag1X, self._ptrX, seconds, LAG1_SMOOTH)
  self._lag1Y = easeRate(self._lag1Y, self._ptrY, seconds, LAG1_SMOOTH)
  self._lag2X = easeRate(self._lag2X, self._lag1X, seconds, LAG2_SMOOTH)
  self._lag2Y = easeRate(self._lag2Y, self._lag1Y, seconds, LAG2_SMOOTH)
  self._lag3X = easeRate(self._lag3X, self._lag2X, seconds, LAG3_SMOOTH)
  self._lag3Y = easeRate(self._lag3Y, self._lag2Y, seconds, LAG3_SMOOTH)
  self._lag4X = easeRate(self._lag4X, self._lag3X, seconds, LAG4_SMOOTH)
  self._lag4Y = easeRate(self._lag4Y, self._lag3Y, seconds, LAG4_SMOOTH)
  local want = 0
  if self._hover then
    want = 1
  end
  self._ptrAmt = easeRate(self._ptrAmt, want, seconds, PTR_SMOOTH)

  local dt = math.max(seconds, 0.0001)
  local vx = 0
  local vy = 0
  if self._hover then
    vx = (self._tgtX - self._lastTgtX) / dt
    vy = (self._tgtY - self._lastTgtY) / dt
    local mag = math.sqrt(vx * vx + vy * vy)
    if mag > VEL_MAX then
      vx = vx * VEL_MAX / mag
      vy = vy * VEL_MAX / mag
    end
  end
  local a = 1 - math.exp(-VEL_SMOOTH * dt)
  self._velX += (vx - self._velX) * a
  self._velY += (vy - self._velY) * a
  self._lastTgtX = self._tgtX
  self._lastTgtY = self._tgtY
  return true
end

local function setPointer(self: SandDust, event: PointerEvent)
  event:hit()
  local w = math.max(8, self._gpuW)
  local h = math.max(8, self._gpuH)
  local uvx = math.clamp(event.position.x / w + 0.5, 0, 1)
  local uvy = math.clamp(event.position.y / h + 0.5, 0, 1)
  if self._ptrAmt < 0.05 then
    self._ptrX = uvx
    self._ptrY = uvy
    self._lag1X = uvx
    self._lag1Y = uvy
    self._lag2X = uvx
    self._lag2Y = uvy
    self._lag3X = uvx
    self._lag3Y = uvy
    self._lag4X = uvx
    self._lag4Y = uvy
    self._lastTgtX = uvx
    self._lastTgtY = uvy
    self._velX = 0
    self._velY = 0
  end
  self._tgtX = uvx
  self._tgtY = uvy
  self._hover = true
  local ctx = self._ctx
  if ctx then
    ctx:markNeedsUpdate()
  end
end

local function pointerMove(self: SandDust, event: PointerEvent)
  setPointer(self, event)
end

local function pointerDown(self: SandDust, event: PointerEvent)
  setPointer(self, event)
end

local function pointerExit(self: SandDust, event: PointerEvent)
  self._hover = false
  local ctx = self._ctx
  if ctx then
    ctx:markNeedsUpdate()
  end
end

local function draw(self: SandDust, renderer: Renderer)
  ensureSize(self)
  if buffer.len(self._ubuf) ~= UBO_SIZE then
    local ctx = self._ctx
    if ctx then
      initGpu(self, ctx)
    end
  end
  local gc = self._gpu
  local pipe = self._pipe
  local ubo = self._ubo
  if gc == nil or pipe == nil or ubo == nil then
    return
  end
  if buffer.len(self._ubuf) ~= UBO_SIZE then
    self._ubuf = buffer.create(UBO_SIZE)
    ubo = GPUBuffer.new({ size = UBO_SIZE, usage = 'uniform' })
    self._ubo = ubo
  end

  local w = self._gpuW
  local h = self._gpuH
  ensureHit(self, w, h)
  renderer:drawPath(self._hitPath, self._hitPaint)

  local buf = self._ubuf
  buffer.writef32(buf, 0, self._t)
  buffer.writef32(buf, 4, num(self.seed, 1))
  buffer.writef32(buf, 8, num(self.density, 45) / 100)
  buffer.writef32(buf, 12, num(self.grainSize, 35) / 100)
  buffer.writef32(buf, 16, math.rad(num(self.windAngle, 18)))
  buffer.writef32(buf, 20, num(self.speed, 22) / 100)
  buffer.writef32(buf, 24, num(self.turbulence, 40) / 100)
  buffer.writef32(buf, 28, w / math.max(h, 1))
  buffer.writef32(buf, 32, num(self.opacity, 55) / 100)
  buffer.writef32(buf, 36, num(self.softness, 50) / 100)
  buffer.writef32(buf, 40, num(self.falloff, 70) / 100)
  buffer.writef32(buf, 44, num(self.sparkle, 28) / 100)
  local dc = { 0.91, 0.82, 0.68, 1 }
  if self.dustColor ~= nil then
    dc = Color.toFloat(self.dustColor)
  end
  buffer.writef32(buf, 48, dc[1])
  buffer.writef32(buf, 52, dc[2])
  buffer.writef32(buf, 56, dc[3])
  buffer.writef32(buf, 60, 1)
  local h1 = { 0.36, 0.54, 0.84, 1 }
  if self.hazeColor1 ~= nil then
    h1 = Color.toFloat(self.hazeColor1)
  end
  buffer.writef32(buf, 64, h1[1])
  buffer.writef32(buf, 68, h1[2])
  buffer.writef32(buf, 72, h1[3])
  buffer.writef32(buf, 76, num(self.haze, 35) / 100)
  buffer.writef32(buf, 80, self._ptrX)
  buffer.writef32(buf, 84, self._ptrY)
  buffer.writef32(buf, 88, num(self.cursorSensitivity, 55) / 100 * self._ptrAmt)
  buffer.writef32(buf, 92, num(self.cursorRadius, 40) / 100)
  buffer.writef32(buf, 96, self._velX)
  buffer.writef32(buf, 100, self._velY)
  buffer.writef32(buf, 104, 0)
  buffer.writef32(buf, 108, 0)
  buffer.writef32(buf, 112, self._lag1X)
  buffer.writef32(buf, 116, self._lag1Y)
  buffer.writef32(buf, 120, self._lag2X)
  buffer.writef32(buf, 124, self._lag2Y)
  buffer.writef32(buf, 128, self._lag3X)
  buffer.writef32(buf, 132, self._lag3Y)
  buffer.writef32(buf, 136, self._lag4X)
  buffer.writef32(buf, 140, self._lag4Y)
  local h2 = { 0.69, 0.44, 0.82, 1 }
  if self.hazeColor2 ~= nil then
    h2 = Color.toFloat(self.hazeColor2)
  end
  buffer.writef32(buf, 144, h2[1])
  buffer.writef32(buf, 148, h2[2])
  buffer.writef32(buf, 152, h2[3])
  buffer.writef32(buf, 156, 1)
  ubo:write(buf)

  local bg = GPUBindGroup.new({
    layout = pipe:getBindGroupLayout(0),
    ubos = { { slot = 0, buffer = ubo } },
  })

  local pass = gc:beginRenderPass({
    color = {
      {
        loadOp = 'clear',
        storeOp = 'store',
        clearColor = { 0, 0, 0, 0 },
      },
    },
  } :: any)
  pass:setPipeline(pipe)
  pass:setBindGroup(0, bg)
  pass:draw(3)
  pass:finish()

  renderer:save()
  renderer:transform(Mat2D.withTranslation(-w * 0.5, -h * 0.5))
  renderer:drawImage(gc.image, self._imgSamp, 'srcOver', 1)
  renderer:restore()
end

return function(): Node<SandDust>
  return {
    width = DEFAULT_W,
    height = DEFAULT_H,
    density = 45,
    grainSize = 35,
    softness = 50,
    opacity = 55,
    speed = 22,
    windAngle = 18,
    turbulence = 40,
    falloff = 70,
    sparkle = 28,
    haze = 35,
    seed = 1,
    cursorSensitivity = 55,
    cursorRadius = 40,
    dustColor = Color.rgb(232, 209, 173),
    hazeColor1 = Color.rgb(92, 138, 214),
    hazeColor2 = Color.rgb(176, 112, 210),
    _gpu = nil,
    _pipe = nil,
    _ubo = nil,
    _ubuf = buffer.create(UBO_SIZE),
    _imgSamp = ImageSampler('clamp', 'clamp', 'bilinear'),
    _hitPath = Path.new(),
    _hitPaint = Paint.with({
      style = 'fill',
      color = Color.rgba(0, 0, 0, 1),
    }),
    _hitW = 0,
    _hitH = 0,
    _ctx = nil,
    _t = 0,
    _gpuW = DEFAULT_W,
    _gpuH = DEFAULT_H,
    _hover = false,
    _tgtX = 0.5,
    _tgtY = 0.5,
    _ptrX = 0.5,
    _ptrY = 0.5,
    _lag1X = 0.5,
    _lag1Y = 0.5,
    _lag2X = 0.5,
    _lag2Y = 0.5,
    _lag3X = 0.5,
    _lag3Y = 0.5,
    _lag4X = 0.5,
    _lag4Y = 0.5,
    _ptrAmt = 0,
    _velX = 0,
    _velY = 0,
    _lastTgtX = 0.5,
    _lastTgtY = 0.5,
    init = init,
    update = update,
    advance = advance,
    draw = draw,
    pointerMove = pointerMove,
    pointerDown = pointerDown,
    pointerExit = pointerExit,
  }
end