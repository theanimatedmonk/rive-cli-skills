-- The Birdie studio: two form factors of a wildlife tracker (from
-- WildlifeTracker_FormFactors.glb), shot as product photography. Each
-- stands on a stone turntable in an infinity cove, lit by softboxes, over a
-- glossy floor that mirrors them. The materials are painted in the shader
-- (studio.wgsl); the finish is the bloom, depth of field and grade of
-- blur.wgsl and post.wgsl.
--
-- The products are the blob `asset` (birdie.bin, written by
-- ../tools/export_birdie.py): every vertex in its frame, a product's body
-- or its lid, so the lids come off for the exploded view.
--
-- Products: `explode` (0 assembled, 1 opened: the birdhouse's back lid
-- swings out showing its electronics, the turned birdhouse's roof lifts),
-- `spin` (degrees a second, the turntables), `focus` (0 both, 1 the
-- birdhouse, 2 the turned one: the camera moves in).
-- View: `turn` and `tilt` (degrees), `zoom`, `drift` (a slow sway of the
-- camera, 0-1). Drag to orbit, pinch to zoom, tap a product to look at it,
-- tap the floor to step back; a host maps `dragX` / `dragY`, `resetView`.
-- Light: `key`, `fill`, `rim`, `ambient`, `softness` (the shadows').
-- Paint: `panelColor` and `shellColor` (the birdhouse), `bodyColor` and
-- `roofColor` (the turned one), and `plinthColor`. The backdrop leans toward each: `tintLeft`, `tintRight`
-- and `tint` (how much).
-- Director: with `director` on, the camera and the products are exactly
-- what the inputs say, for timelines to key (the Demo state machine):
-- `camTurn`, `camTilt` (degrees), `camDistance` (metres), `camX`, `camY`,
-- `camZ` (what it looks at), `camFov` (degrees), `open` (the exploded view,
-- 0-1) and `turntable` (degrees).
-- Cove: a bright, seamless studio sweep. `backdropColor` (high up),
-- `horizonColor` (where floor meets backdrop), `floorColor` (in the light
-- pool round them), `brightness` (of all three), `floorGloss`, `pool` (the
-- pool's size, metres), `halo` (the glow behind them), `shadowDepth` (how
-- dark their shadows fall, 0-1).
-- Finish: `depthOfField`, `bloom`, `glow`, `exposure`, `grain`, `vignette`.
--
-- Place the node at the artboard's centre and set width/height to the
-- artboard's size.

export type Studio = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	explode: Input<number>,
	spin: Input<number>,
	focus: Input<number>,
	turn: Input<number>,
	tilt: Input<number>,
	zoom: Input<number>,
	drift: Input<number>,
	key: Input<number>,
	fill: Input<number>,
	rim: Input<number>,
	ambient: Input<number>,
	softness: Input<number>,
	keyColor: Input<Color>,
	rimColor: Input<Color>,
	panelColor: Input<Color>,
	shellColor: Input<Color>,
	bodyColor: Input<Color>,
	roofColor: Input<Color>,
	tintLeft: Input<Color>,
	tintRight: Input<Color>,
	tint: Input<number>,
	director: Input<number>,
	camTurn: Input<number>,
	camTilt: Input<number>,
	camDistance: Input<number>,
	camX: Input<number>,
	camY: Input<number>,
	camZ: Input<number>,
	camFov: Input<number>,
	open: Input<number>,
	turntable: Input<number>,
	plinthColor: Input<Color>,
	backdropColor: Input<Color>,
	horizonColor: Input<Color>,
	floorColor: Input<Color>,
	floorGloss: Input<number>,
	brightness: Input<number>,
	shadowDepth: Input<number>,
	pool: Input<number>,
	halo: Input<number>,
	depthOfField: Input<number>,
	bloom: Input<number>,
	glow: Input<number>,
	exposure: Input<number>,
	grain: Input<number>,
	vignette: Input<number>,
	navigation: Input<boolean>,
	resetView: Input<number>,
	dragX: Input<number>,
	dragY: Input<number>,

	context: Context?,
	shader: Shader?,
	postShader: Shader?,
	blurShader: Shader?,
	failed: boolean,
	time: number,
	vertexBuffer: GPUBuffer?,
	indexBuffer: GPUBuffer?,
	indexCount: number,
	-- Per product: its plinth's radius and height, its footprint (centre x,
	-- z, half x, z) and how tall it stands.
	plinths: { number },
	plinthH: number,
	feet: { { number } },
	heights: { number },
	-- Eased toward the inputs.
	opened: number,
	focusX: number,
	focusY: number,
	focusZ: number,
	focusDist: number,
	spun: number,
	-- Navigation on top of the inputs.
	navTurn: number,
	navTilt: number,
	navZoom: number,
	navFocus: number,
	navReset: number,
	lastResetView: number,
	lastDragX: number,
	lastDragY: number,
	pointers: { [number]: Vector },
	pointerCount: number,
	tapStart: Vector,
	tapMoved: number,
	-- Where each product's middle is on screen (pixels), for taps.
	screenSpots: { Vector },
	ubo: GPUBuffer?,
	postUbo: GPUBuffer?,
	productBindings: GPUBindGroup?,
	mirrorBindings: GPUBindGroup?,
	mirrorDepthBindings: GPUBindGroup?,
	skyBindings: GPUBindGroup?,
	shadowBindings: GPUBindGroup?,
	postBindings: GPUBindGroup?,
	nearBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	sceneCanvas: GPUCanvas?,
	outCanvas: GPUCanvas?,
	nearCanvas: GPUCanvas?,
	wideCanvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	productPipeline: GPUPipeline?,
	mirrorPipeline: GPUPipeline?,
	mirrorDepthPipeline: GPUPipeline?,
	skyPipeline: GPUPipeline?,
	shadowPipeline: GPUPipeline?,
	postPipeline: GPUPipeline?,
	nearPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	shadowTarget: GPUTextureView?,
	shadowView: GPUTextureView?,
	shadowSampler: GPUSampler?,
	sampler: GPUSampler?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	frame: buffer,
	postParams: buffer,
	drawSampler: ImageSampler,
}

local UNIFORM_SIZE = 800
local POST_SIZE = 96
local HEADER = 32
local PRODUCTS = 2
local VERTEX_STRIDE = 20
local SHADOW_SIZE = 2048
local SHADOW_SPAN = 0.3
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local FOV = 26
-- The two on the floor (metres): the birdhouse and the turned one, each
-- turned a little toward the other.
local PLACES = { { -0.056, 0.006, 18 }, { 0.058, -0.008, -14 } }
-- The camera on both, and on one.
local WIDE_TARGET = { 0, 0.042, -0.002 }
local WIDE_DISTANCE = 0.32
local CLOSE_DISTANCE = 0.21
-- The studio's lights, toward each (world): the key high at front left,
-- the fill low at front right, the rim strip behind at right.
local KEY_DIR = { -0.5, 0.78, 0.38 }
local FILL_DIR = { 0.85, 0.22, 0.48 }
local RIM_DIR = { 0.62, 0.38, -0.69 }

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function smooth(x: number): number
	local t = clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function linear(c: Color): (number, number, number)
	local r, g, b = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return (r / 255) ^ 2.2, (g / 255) ^ 2.2, (b / 255) ^ 2.2
end

local function write4(u: buffer, offset: number, x: number, y: number, z: number, w: number)
	buffer.writef32(u, offset, x)
	buffer.writef32(u, offset + 4, y)
	buffer.writef32(u, offset + 8, z)
	buffer.writef32(u, offset + 12, w)
end

local function writeColor(u: buffer, offset: number, c: Color, k: number, w: number)
	local r, g, b = linear(c)
	write4(u, offset, r * k, g * k, b * k, w)
end

local function normalize3(x: number, y: number, z: number): (number, number, number)
	local l = math.max(math.sqrt(x * x + y * y + z * z), 1e-6)
	return x / l, y / l, z / l
end

---------------------------------------------------------------------------
-- Loading

local function slice(data: buffer, offset: number, length: number, usage: 'vertex' | 'index'): GPUBuffer
	local size = math.max(4, math.ceil(length / 4) * 4)
	local bytes = buffer.create(size)
	buffer.copy(bytes, 0, data, offset, length)
	return GPUBuffer.new({ size = size, usage = usage, data = bytes, immutable = true })
end

local function load(self: Studio): boolean
	local context = self.context
	assert(context)
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`Studio: no blob asset named '{self.asset}'`)
		return false
	end
	local data = blob.data
	if buffer.len(data) < HEADER or buffer.readstring(data, 0, 4) ~= 'BRDI' then
		print(`Studio: '{self.asset}' is not a birdie.bin`)
		return false
	end
	local vertices = buffer.readu32(data, 8)
	local indices = buffer.readu32(data, 12)
	if buffer.readu32(data, 16) ~= PRODUCTS then
		print(`Studio: '{self.asset}' has {buffer.readu32(data, 16)} products, not {PRODUCTS}`)
		return false
	end
	local header = HEADER + PRODUCTS * 48
	for p = 1, PRODUCTS do
		local at = HEADER + (p - 1) * 48
		local f = function(k: number): number
			return buffer.readf32(data, at + k * 4)
		end
		self.heights[p] = f(4)
		self.plinths[p] = f(6)
		self.plinthH = f(7)
		self.feet[p] = { f(8), f(9), f(10), f(11) }
	end
	self.vertexBuffer = slice(data, header, vertices * VERTEX_STRIDE, 'vertex')
	self.indexBuffer = slice(data, header + vertices * VERTEX_STRIDE, indices * 4, 'index')
	self.indexCount = indices
	self.ubo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.postUbo = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform' })
	self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	local shadow = GPUTexture.new({ width = SHADOW_SIZE, height = SHADOW_SIZE, format = DEPTH_FORMAT, renderTarget = true, label = 'key shadow' })
	self.shadowTarget = shadow:view()
	self.shadowView = shadow:view({ aspect = 'depth-only' })
	self.shadowSampler = GPUSampler.new({ min = 'linear', mag = 'linear', compare = 'less-equal', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	return true
end

function init(self: Studio, context: Context): boolean
	self.context = context
	self.shader = context:shader('studio')
	self.postShader = context:shader('post')
	self.blurShader = context:shader('blur')
	if self.shader == nil or self.postShader == nil or self.blurShader == nil then
		print('Studio: shaders "studio", "blur" and "post" are needed')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('Studio: setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

---------------------------------------------------------------------------
-- Time

function advance(self: Studio, seconds: number): boolean
	if self.resetView ~= self.lastResetView then
		self.lastResetView = self.resetView
		self.navReset = 1
	end
	local dx, dy = self.dragX - self.lastDragX, self.dragY - self.lastDragY
	if dx ~= 0 or dy ~= 0 then
		self.lastDragX, self.lastDragY = self.dragX, self.dragY
		if self.navigation then
			self.navReset = 0
			self.navTurn += dx * 0.3
			self.navTilt = clamp(self.navTilt + dy * 0.15, -20, 50)
		end
	end
	local dt = math.min(seconds, 0.1)
	self.time += dt
	if self.navReset > 0 then
		local k = 1 - math.exp(-dt * 7)
		self.navTurn -= self.navTurn * k
		self.navTilt -= self.navTilt * k
		self.navZoom += (1 - self.navZoom) * k
		self.navReset = math.max(self.navReset - seconds, 0)
		if self.navReset == 0 then
			self.navTurn, self.navTilt, self.navZoom = 0, 0, 1
		end
	end
	-- On the first frame everything starts where it's set; after that it
	-- eases there.
	local first = self.time <= dt + 1e-6
	-- The lids ease open and shut; the turntables stop while they're open.
	if self.director > 0.5 then
		-- The timeline has it: no easing here.
		self.opened = clamp(self.open, 0, 1)
		self.spun = self.turntable
		return true
	end
	self.opened += (clamp(self.explode, 0, 1) - self.opened) * (if first then 1 else 1 - math.exp(-dt * 3.5))
	self.spun += dt * self.spin * (1 - smooth(self.opened * 3))
	-- The camera eases onto its subject.
	local focus = if self.navFocus >= 0 then self.navFocus else math.floor(clamp(self.focus, 0, PRODUCTS) + 0.5)
	local tx, ty, tz, dist = WIDE_TARGET[1], WIDE_TARGET[2], WIDE_TARGET[3], WIDE_DISTANCE
	if focus >= 1 then
		local place = PLACES[focus]
		tx, ty, tz = place[1], self.plinthH + self.heights[focus] * 0.5 + 0.004, place[2]
		dist = CLOSE_DISTANCE
		if focus == 2 then
			-- The turned birdhouse's roof stands above its body.
			ty += 0.014
		end
	end
	-- Opened, the view steps back and rises to take in the lid beside the
	-- birdhouse and the lifted roof.
	local open = smooth(self.opened)
	ty += 0.012 * open
	if focus ~= 2 then
		tx -= 0.022 * open
	end
	dist *= 1 + 0.32 * open
	local k = if first then 1 else 1 - math.exp(-dt * 3)
	self.focusX += (tx - self.focusX) * k
	self.focusY += (ty - self.focusY) * k
	self.focusZ += (tz - self.focusZ) * k
	self.focusDist += (dist - self.focusDist) * k
	return true
end

---------------------------------------------------------------------------
-- Targets and pipelines

local function ensureTargets(self: Studio): boolean
	local context = self.context
	assert(context)
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(1, math.floor(self.width * res))
	local h = math.max(1, math.floor(self.height * res))
	local samples = if self.msaa >= 2 then 4 else 1
	if self.sceneCanvas and self.outCanvas and w == self.targetW and h == self.targetH and samples == self.targetSamples then
		return true
	end
	local function canvas(existing: GPUCanvas?, cw: number, ch: number): GPUCanvas
		if existing == nil then
			return context:gpuCanvas({ width = cw, height = ch })
		end
		existing:resize(cw, ch)
		return existing
	end
	local scene = canvas(self.sceneCanvas, w, h)
	local out = canvas(self.outCanvas, w, h)
	self.sceneCanvas, self.outCanvas = scene, out
	self.nearCanvas = canvas(self.nearCanvas, math.max(1, w // 2), math.max(1, h // 2))
	self.wideCanvas = canvas(self.wideCanvas, math.max(1, w // 4), math.max(1, h // 4))
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = scene.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.productPipeline == nil then
		local shader = self.shader
		local postShader = self.postShader
		local blurShader = self.blurShader
		assert(shader and postShader and blurShader)
		local target: { ColorTarget } = { { format = scene.format } }
		local layout: { VertexBufferLayout } = {
			{
				stride = VERTEX_STRIDE,
				attributes = {
					{ format = 'float32x3', slot = 0, offset = 0 },
					{ format = 'snorm8x4', slot = 1, offset = 12 },
					{ format = 'uint8x4', slot = 2, offset = 16 },
				},
			},
		}
		self.skyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = { format = DEPTH_FORMAT, compare = 'always', write = false },
			sampleCount = samples,
		})
		self.productPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_product' },
			fragment = { module = shader, entryPoint = 'fs_product' },
			vertexLayout = layout,
			colorTargets = target,
			depthStencil = { format = DEPTH_FORMAT, compare = 'greater', write = true },
			cullMode = 'none',
			sampleCount = samples,
		})
		-- Their reflections: first their depth alone (the colour kept), then
		-- the nearest surface blended over the floor, the floor's focus (in
		-- alpha) kept.
		self.mirrorDepthPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_mirror' },
			fragment = { module = shader, entryPoint = 'fs_depth' },
			vertexLayout = layout,
			colorTargets = {
				{
					format = scene.format,
					blend = { srcColor = 'zero', dstColor = 'one', colorOp = 'add', srcAlpha = 'zero', dstAlpha = 'one', alphaOp = 'add' },
				},
			},
			depthStencil = { format = DEPTH_FORMAT, compare = 'greater', write = true },
			cullMode = 'none',
			sampleCount = samples,
		})
		self.mirrorPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_mirror' },
			fragment = { module = shader, entryPoint = 'fs_mirror' },
			vertexLayout = layout,
			colorTargets = {
				{
					format = scene.format,
					blend = {
						srcColor = 'src-alpha',
						dstColor = 'one-minus-src-alpha',
						colorOp = 'add',
						srcAlpha = 'zero',
						dstAlpha = 'one',
						alphaOp = 'add',
					},
				},
			},
			depthStencil = { format = DEPTH_FORMAT, compare = 'greater-equal', write = false },
			cullMode = 'none',
			sampleCount = samples,
		})
		self.shadowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_shadow' },
			vertexLayout = layout,
			depthStencil = { format = DEPTH_FORMAT, compare = 'less', write = true },
			cullMode = 'none',
		})
		self.nearPipeline = GPUPipeline.new({
			vertex = { module = blurShader, entryPoint = 'vs_main' },
			fragment = { module = blurShader, entryPoint = 'fs_near' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		self.widePipeline = GPUPipeline.new({
			vertex = { module = blurShader, entryPoint = 'vs_main' },
			fragment = { module = blurShader, entryPoint = 'fs_wide' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		self.postPipeline = GPUPipeline.new({
			vertex = { module = postShader, entryPoint = 'vs_main' },
			fragment = { module = postShader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		self.productBindings = nil
		self.mirrorBindings = nil
		self.mirrorDepthBindings = nil
		self.skyBindings = nil
		self.shadowBindings = nil
	end
	self.postBindings = nil
	self.nearBindings = nil
	self.wideBindings = nil
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return true
end

---------------------------------------------------------------------------
-- Frame uniforms

-- Where a lid goes as it opens (in its product's frame): the birdhouse's
-- back lid swings out to its left, its electronics turned to the camera;
-- the turned birdhouse's roof lifts and turns.
local function lidPose(product: number, t: number): Mat4
	local e = smooth(t)
	-- Clear of the body first (back, or up), then across.
	local away = math.sin(math.min(t, 1) * math.pi) * 0.022
	if product == 1 then
		return Mat4.fromTranslation(-0.05 * e, 0.008 * e, -away + 0.004 * e) * Mat4.fromRotationY(math.rad(38) * e)
	end
	return Mat4.fromTranslation(0, 0.03 * e, 0) * Mat4.fromRotationY(math.rad(35) * e)
end

local function frameUniforms(self: Studio)
	local u = self.frame
	local t = self.time
	-- The camera: orbiting its subject, swaying slowly.
	local sway = math.sin(t * 0.21) * 7 * clamp(self.drift, 0, 1)
	local swayTilt = math.sin(t * 0.17 + 1.3) * 2 * clamp(self.drift, 0, 1)
	local az: number = math.rad(self.turn + self.navTurn + sway)
	local pitch: number = math.rad(clamp(self.tilt + self.navTilt + swayTilt, -10, 70))
	local dist: number = self.focusDist * clamp(self.zoom, 0.3, 3) * self.navZoom
	local tx: number, ty: number, tz: number = self.focusX, self.focusY, self.focusZ
	local fov: number = FOV
	if self.director > 0.5 then
		az = math.rad(self.camTurn)
		pitch = math.rad(clamp(self.camTilt, -10, 85))
		dist = math.max(self.camDistance, 0.02)
		tx = self.camX
		ty = self.camY
		tz = self.camZ
		fov = clamp(self.camFov, 5, 90)
	end
	local ex = tx + math.sin(az) * math.cos(pitch) * dist
	local ey = ty + math.sin(pitch) * dist
	local ez = tz + math.cos(az) * math.cos(pitch) * dist
	-- Never under the floor.
	ey = math.max(ey, 0.004)
	local fx, fy, fz = normalize3(tx - ex, ty - ey, tz - ez)
	local rx, rz = -fz, fx
	local rl = math.max(math.sqrt(rx * rx + rz * rz), 1e-6)
	rx, rz = rx / rl, rz / rl
	local ux = -rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy
	local aspect = self.targetW / math.max(self.targetH, 1)
	local fovY = math.rad(fov)
	local tanY = math.tan(fovY / 2)
	local proj = Mat4.perspectiveReverseZ(fovY, aspect, 0.005)
	local view = Mat4.lookAt(Vector.xyz(ex, ey, ez), Vector.xyz(tx, ty, tz), Vector.xyz(0, 1, 0))
	local viewProj = proj * view
	viewProj:writeToBuffer(u, 0)
	write4(u, 128, ex, ey, ez, t)

	-- The lights.
	local kx, ky, kz = normalize3(KEY_DIR[1], KEY_DIR[2], KEY_DIR[3])
	write4(u, 144, kx, ky, kz, math.max(self.key, 0))
	writeColor(u, 160, self.keyColor, 1, clamp(self.softness, 0, 4) * 9)
	local fx2, fy2, fz2 = normalize3(FILL_DIR[1], FILL_DIR[2], FILL_DIR[3])
	write4(u, 176, fx2, fy2, fz2, math.max(self.fill, 0))
	writeColor(u, 192, self.keyColor, 1, 0)
	local rx2, ry2, rz2 = normalize3(RIM_DIR[1], RIM_DIR[2], RIM_DIR[3])
	write4(u, 208, rx2, ry2, rz2, math.max(self.rim, 0))
	writeColor(u, 224, self.rimColor, 1, 0)
	-- The cove.
	local level = math.max(self.brightness, 0)
	writeColor(u, 240, self.backdropColor, level, math.max(self.halo, 0))
	writeColor(u, 256, self.horizonColor, level, clamp(self.floorGloss, 0, 1))
	writeColor(u, 272, self.floorColor, level, math.max(self.pool, 0.02))
	write4(u, 288, self.targetW, self.targetH, 1 / self.targetW, 1 / self.targetH)
	write4(u, 304, rx, 0, rz, tanY * aspect)
	write4(u, 320, ux, uy, uz, tanY)
	write4(u, 336, fx, fy, fz, dist)
	write4(u, 352, clamp(self.depthOfField, 0, 1), 0, math.max(self.ambient, 0), clamp(self.shadowDepth, 0, 1))
	-- The paints.
	writeColor(u, 368, self.panelColor, 1, 0)
	writeColor(u, 384, self.shellColor, 1, 0)
	writeColor(u, 400, self.bodyColor, 1, 0)
	writeColor(u, 416, self.roofColor, 1, 0)
	writeColor(u, 768, self.tintLeft, 1, clamp(self.tint, 0, 1))
	writeColor(u, 784, self.tintRight, 1, clamp(self.tint, 0, 1))
	writeColor(u, 432, self.plinthColor, 1, 0)

	-- The products on their turntables, and their lids.
	for p = 1, PRODUCTS do
		local place = PLACES[p]
		local yaw = math.rad(place[3] + self.spun)
		local body = Mat4.fromTranslation(place[1], self.plinthH, place[2]) * Mat4.fromRotationY(yaw)
		body:writeToBuffer(u, 448 + (p - 1) * 128)
		local lid = body * lidPose(p, self.opened)
		lid:writeToBuffer(u, 448 + (p - 1) * 128 + 64)
		write4(u, 704 + (p - 1) * 16, place[1], place[2], self.plinths[p], 0)
		local foot = self.feet[p]
		write4(u, 736 + (p - 1) * 16, foot[1], foot[2], foot[3], foot[4])
		-- Its middle on screen, for taps.
		local q = viewProj:transformPoint(place[1], self.plinthH + self.heights[p] * 0.5, place[2])
		self.screenSpots[p] = Vector.xy((q.x * 0.5 + 0.5) * self.width - self.width / 2, (0.5 - q.y * 0.5) * self.height - self.height / 2)
	end

	-- The key's view, for shadows: orthographic, over all three.
	local half = SHADOW_SPAN / 2
	local cx, cy, cz = 0, 0.04, -0.004
	local lightView = Mat4.lookAt(Vector.xyz(cx + kx * 0.8, cy + ky * 0.8, cz + kz * 0.8), Vector.xyz(cx, cy, cz), Vector.xyz(0, 1, 0))
	local lightViewProj = Mat4.ortho(-half, half, -half, half, 0.2, 1.6) * lightView
	lightViewProj:writeToBuffer(u, 64)
end

---------------------------------------------------------------------------
-- Render

-- Only what a pipeline uses, or, on runtimes that list every binding in
-- the module, the full set.
local function bindings(self: Studio, pipeline: GPUPipeline, ubo: GPUBuffer, useShadow: boolean): GPUBindGroup
	local function make(full: boolean): GPUBindGroup
		local entries: { TextureEntry } = {}
		local samplers: { SamplerEntry } = {}
		if useShadow or full then
			table.insert(entries, { slot = 1, view = self.shadowView :: GPUTextureView })
			table.insert(samplers, { slot = 2, sampler = self.shadowSampler :: GPUSampler })
		end
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = entries,
			samplers = samplers,
		})
	end
	local ok, group = pcall(make, useShadow)
	if ok then
		return group
	end
	return make(true)
end

local function drawProducts(self: Studio, pass: GPURenderPass)
	pass:setVertexBuffer(0, self.vertexBuffer :: GPUBuffer)
	pass:setIndexBuffer(self.indexBuffer :: GPUBuffer, 'uint32')
	pass:drawIndexed(self.indexCount)
end

local function render(self: Studio): Image?
	if self.vertexBuffer == nil or not ensureTargets(self) then
		return nil
	end
	local scene, out = self.sceneCanvas, self.outCanvas
	local depthView, ubo, postUbo, sampler = self.depthView, self.ubo, self.postUbo, self.sampler
	local productP, mirrorP, skyP, shadowP, postP = self.productPipeline, self.mirrorPipeline, self.skyPipeline, self.shadowPipeline, self.postPipeline
	local shadowTarget = self.shadowTarget
	if not (scene and out and depthView and ubo and postUbo and sampler and shadowTarget) then
		return nil
	end
	if not (productP and mirrorP and skyP and shadowP and postP) then
		return nil
	end
	frameUniforms(self)
	ubo:write(self.frame)
	if self.productBindings == nil then
		self.productBindings = bindings(self, productP, ubo, true)
		self.mirrorBindings = bindings(self, mirrorP, ubo, true)
		self.mirrorDepthBindings = bindings(self, self.mirrorDepthPipeline :: GPUPipeline, ubo, false)
		self.skyBindings = bindings(self, skyP, ubo, true)
		self.shadowBindings = bindings(self, shadowP, ubo, false)
	end
	local productB, mirrorB, skyB, shadowB = self.productBindings, self.mirrorBindings, self.skyBindings, self.shadowBindings
	assert(productB and mirrorB and skyB and shadowB)

	-- Shadows, from the key.
	local shadowPass = scene:beginRenderPass({
		depthStencil = { view = shadowTarget, depthLoadOp = 'clear', depthStoreOp = 'store', depthClearValue = 1 },
	})
	shadowPass:setPipeline(shadowP)
	shadowPass:setBindGroup(0, shadowB)
	drawProducts(self, shadowPass)
	shadowPass:finish()

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = scene:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 1 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } }
	local pass = scene:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
	})
	-- The cove, then the reflections in its floor, then the products.
	pass:setPipeline(skyP)
	pass:setBindGroup(0, skyB)
	pass:draw(3)
	local mirrorDepthP, mirrorDepthB = self.mirrorDepthPipeline, self.mirrorDepthBindings
	if self.floorGloss > 0 and mirrorDepthP and mirrorDepthB then
		pass:setPipeline(mirrorDepthP)
		pass:setBindGroup(0, mirrorDepthB)
		drawProducts(self, pass)
		pass:setPipeline(mirrorP)
		pass:setBindGroup(0, mirrorB)
		drawProducts(self, pass)
	end
	pass:setPipeline(productP)
	pass:setBindGroup(0, productB)
	drawProducts(self, pass)
	pass:finish()

	-- The finish.
	local p = self.postParams
	write4(p, 0, 1 / self.targetW, 1 / self.targetH, self.targetW / self.targetH, self.time)
	write4(p, 16, math.max(self.bloom, 0), clamp(self.glow, 0, 1), clamp(self.depthOfField, 0, 1), math.max(self.exposure, 0))
	write4(p, 32, 1.0, 0.99, 0.97, 1.04)
	write4(p, 48, clamp(self.vignette, 0, 2), clamp(self.grain, 0, 1), 0.9, 0.004)
	write4(p, 64, 0, 0, 0, 0)
	write4(p, 80, 0.5, 0.5, 0, 0)
	postUbo:write(p)
	local near, wide = self.nearCanvas, self.wideCanvas
	local nearP, wideP = self.nearPipeline, self.widePipeline
	if not (near and wide and nearP and wideP) then
		return nil
	end
	if self.postBindings == nil then
		self.nearBindings = GPUBindGroup.new({
			layout = nearP:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = scene:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.wideBindings = GPUBindGroup.new({
			layout = wideP:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = near:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.postBindings = GPUBindGroup.new({
			layout = postP:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = {
				{ slot = 1, view = scene:colorView() },
				{ slot = 3, view = near:colorView() },
				{ slot = 4, view = wide:colorView() },
			},
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	local postB, nearB, wideB = self.postBindings, self.nearBindings, self.wideBindings
	assert(postB and nearB and wideB)
	local blurPass = near:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	blurPass:setPipeline(nearP)
	blurPass:setBindGroup(0, nearB)
	blurPass:draw(3)
	blurPass:finish()
	local widePass = wide:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	widePass:setPipeline(wideP)
	widePass:setBindGroup(0, wideB)
	widePass:draw(3)
	widePass:finish()
	local post = out:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	post:setPipeline(postP)
	post:setBindGroup(0, postB)
	post:draw(3)
	post:finish()
	return out.image
end

---------------------------------------------------------------------------
-- Navigation: drag orbits, pinch zooms, a tap looks at a product (or, on
-- the floor, steps back to all three).

local function pointerDown(self: Studio, event: PointerEvent)
	if not self.navigation or self.director > 0.5 then
		return
	end
	if self.pointers[event.id] == nil then
		self.pointerCount += 1
	end
	self.pointers[event.id] = event.position
	self.navReset = 0
	if self.pointerCount == 1 then
		self.tapStart = event.position
		self.tapMoved = 0
	end
	event:hit()
end

local function pointerMove(self: Studio, event: PointerEvent)
	local last = self.pointers[event.id]
	if not self.navigation or last == nil then
		return
	end
	local d = event.position - last
	self.tapMoved += Vector.length(d)
	if self.pointerCount >= 2 then
		local other: Vector? = nil
		for id, p in self.pointers do
			if id ~= event.id then
				other = p
				break
			end
		end
		if other then
			local before = Vector.length(last - other)
			local after = Vector.length(event.position - other)
			if before > 1 and after > 1 then
				self.navZoom = clamp(self.navZoom * before / after, 0.4, 2.2)
			end
		end
		self.tapMoved = 1000
	else
		self.navTurn += d.x * 0.3
		self.navTilt = clamp(self.navTilt + d.y * 0.15, -20, 50)
	end
	self.pointers[event.id] = event.position
	event:hit()
end

local function pointerUp(self: Studio, event: PointerEvent)
	if self.pointers[event.id] == nil then
		return
	end
	self.pointers[event.id] = nil
	self.pointerCount = math.max(self.pointerCount - 1, 0)
	if self.pointerCount == 0 and self.tapMoved < 8 then
		-- A tap: the nearest product's middle, if it's close enough.
		local best, bestD = 0, 110 * (self.width / 1280)
		for p, spot in self.screenSpots do
			local dd = Vector.length(event.position - spot)
			if dd < bestD then
				best, bestD = p, dd
			end
		end
		local current = if self.navFocus >= 0 then self.navFocus else math.floor(clamp(self.focus, 0, PRODUCTS) + 0.5)
		if best == 0 or best == current then
			self.navFocus = 0
			self.navReset = 1
		else
			self.navFocus = best
		end
	end
	event:hit()
end

local function pointerExit(self: Studio, event: PointerEvent)
	if self.pointers[event.id] ~= nil then
		self.pointers[event.id] = nil
		self.pointerCount = math.max(self.pointerCount - 1, 0)
	end
end

function draw(self: Studio, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('Studio: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	if image then
		renderer:save()
		renderer:transform(
			Mat2D.withTranslation(-self.width / 2, -self.height / 2)
				* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
		)
		renderer:drawImage(image, self.drawSampler, 'srcOver', 1)
		renderer:restore()
	end
end

return function(): Node<Studio>
	return {
		asset = 'birdie',
		width = 1280,
		height = 720,
		resolution = 1,
		msaa = 4,
		explode = 0,
		spin = 0,
		focus = 0,
		turn = 0,
		tilt = 14,
		zoom = 1,
		drift = 1,
		key = 2.1,
		fill = 0.6,
		rim = 1.8,
		ambient = 0.45,
		softness = 3.2,
		keyColor = Color.rgb(255, 246, 232),
		rimColor = Color.rgb(255, 236, 214),
		panelColor = Color.rgb(255, 142, 91),
		shellColor = Color.rgb(20, 34, 75),
		bodyColor = Color.rgb(206, 184, 152),
		roofColor = Color.rgb(52, 34, 24),
		tintLeft = Color.rgb(240, 242, 255),
		tintRight = Color.rgb(245, 236, 222),
		tint = 0.5,
		director = 0,
		camTurn = 0,
		camTilt = 12,
		camDistance = 0.34,
		camX = 0,
		camY = 0.045,
		camZ = 0,
		camFov = 26,
		open = 0,
		turntable = 0,
		plinthColor = Color.rgb(232, 228, 220),
		backdropColor = Color.rgb(233, 231, 226),
		horizonColor = Color.rgb(246, 245, 241),
		floorColor = Color.rgb(251, 250, 247),
		floorGloss = 0.22,
		brightness = 1.75,
		shadowDepth = 0.5,
		pool = 0.3,
		halo = 0.25,
		depthOfField = 0.3,
		bloom = 0.04,
		glow = 0,
		exposure = 1,
		grain = 0.04,
		vignette = 0.08,
		navigation = true,
		resetView = 0,
		dragX = 0,
		dragY = 0,

		context = nil,
		shader = nil,
		postShader = nil,
		blurShader = nil,
		failed = false,
		time = 0,
		vertexBuffer = nil,
		indexBuffer = nil,
		indexCount = 0,
		plinths = { 0.038, 0.038 },
		plinthH = 0.007,
		feet = { { 0, 0, 0.02, 0.01 }, { 0, 0, 0.02, 0.02 } },
		heights = { 0.075, 0.086 },
		opened = 0,
		focusX = WIDE_TARGET[1],
		focusY = WIDE_TARGET[2],
		focusZ = WIDE_TARGET[3],
		focusDist = WIDE_DISTANCE,
		spun = 0,
		navTurn = 0,
		navTilt = 0,
		navZoom = 1,
		navFocus = -1,
		navReset = 0,
		lastResetView = 0,
		lastDragX = 0,
		lastDragY = 0,
		pointers = {},
		pointerCount = 0,
		tapStart = Vector.xy(0, 0),
		tapMoved = 0,
		screenSpots = { Vector.xy(0, 0), Vector.xy(0, 0) },
		ubo = nil,
		postUbo = nil,
		productBindings = nil,
		mirrorBindings = nil,
		mirrorDepthBindings = nil,
		skyBindings = nil,
		shadowBindings = nil,
		postBindings = nil,
		nearBindings = nil,
		wideBindings = nil,
		sceneCanvas = nil,
		outCanvas = nil,
		nearCanvas = nil,
		wideCanvas = nil,
		depthView = nil,
		msaaView = nil,
		productPipeline = nil,
		mirrorPipeline = nil,
		mirrorDepthPipeline = nil,
		skyPipeline = nil,
		shadowPipeline = nil,
		postPipeline = nil,
		nearPipeline = nil,
		widePipeline = nil,
		shadowTarget = nil,
		shadowView = nil,
		shadowSampler = nil,
		sampler = nil,
		targetW = 0,
		targetH = 0,
		targetSamples = 0,
		frame = buffer.create(UNIFORM_SIZE),
		postParams = buffer.create(POST_SIZE),
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),

		init = init,
		advance = advance,
		draw = draw,
		pointerDown = pointerDown,
		pointerMove = pointerMove,
		pointerUp = pointerUp,
		pointerExit = pointerExit,
	}
end
