-- Pampa Sarovar: a lotus lake in a misty, sunlit forest, from
-- Pampa_Sarovar_Scene.glb. Swans glide, the trees and grass sway, lotuses
-- bob, mist banks drift low between the tree lines and golden pollen and
-- petals float through the light.
--
-- Rendered in 3D on the GPU (lake.wgsl): first the land and sky mirrored
-- into a half-size reflection canvas, then the scene, the lake (reading the
-- reflection through its ripples), the mist banks and the pollen; then
-- finished (blur.wgsl, post.wgsl): bloom, a soft glow, light shafts, depth
-- of field, grading.
--
-- The geometry is the blob `asset` (lake.bin, written by
-- ../tools/export_lake.py): the land, the water and the ripple rings, with
-- the GLB's vertex colours (the light is baked in) and wind attributes.
-- The editor takes blobs under 10 MB, so it comes in parts: `asset`, then
-- `asset`2, `asset`3... Meshes are cut into chunks with u16 indices.
--
-- Camera: cameraX/Y/Z is its position in metres (Y up; the water is y = 0).
-- rotationX tilts it up, rotationY turns it (positive turns left, about the
-- Y axis), rotationZ rolls it; all in degrees. `fov` is the vertical field
-- of view in degrees. `drift` (0-1) adds a slow, floating handheld sway.
-- The defaults are the GLB's Cam_Hero.
--
-- Navigation, as in Blender's viewport (`navigation` on): drag to orbit
-- around the view's centre (`focusDistance` ahead), two fingers to pan,
-- pinch to zoom, double-tap to go back to the camera inputs. A host can map
-- its mouse to the rest: `navMode` 1 makes a drag pan (Shift), 2 zoom
-- (Ctrl); `zoom` scales the orbit distance (the wheel); changing
-- `resetView` resets the view; `dragX` / `dragY` (running totals, in
-- pixels) drag it as the pointer does, e.g. from a trackpad's two-finger
-- scroll. The inputs stay the camera's home. The scene is built for the
-- hero view: far from it, it shows gaps.
--
-- The camera move (`tour` 1): a looping flight through the lake, from
-- Cam_Hero and back. A low skim down the lake's centre past the hamsas,
-- leaning one way then the other; once round the lotus beds, a full 360
-- facing in, banked into the turn; a rising crane onto the valley gap, a
-- held breath; and a long, gliding pull-back home. 106 s at `tourSpeed`
-- 1; the navigation still works on top. The camera
-- inputs are used while it is off (0), and turning it on or off glides
-- between the two over three seconds.
--
-- Sun: `sunAzimuth` (degrees around Y, 0 = +X, 90 = +Z), `sunElevation`,
-- `sunIntensity`, `sunColor`; `lightLeak` is its glow on screen, `shafts`
-- its light shafts through the mist. The GLB's Sun_Key is azimuth -64,
-- elevation 26.
--
-- Wind: `windStrength`, `windSpeed`, `windDirection` (degrees, the way it
-- blows, 0 = +X), `gustiness` (0-1) and `flutter` (the leaves' flick).
--
-- Water: `reflection` (0-1), `ripples` (their strength), `glints`,
-- `ringSpeed` and `rings` (the rings round swans and flowers),
-- `waterColor` (tints the lake's own colour), `swans` (how far they glide),
-- `lotusBob`.
--
-- Mist: `mist` (density of the low banks), `mistHeight` (metres),
-- `mistSpeed` (their drift), `wisps` (mist sheets, up to 64) and
-- `wispOpacity`, `mistColor`; `haze` adds distance haze on top of the baked
-- one.
--
-- Pollen: `pollenAmount` (motes, up to 3000), `pollenSize` (metres),
-- `pollenSpeed`, `petals` (the fraction that are falling petals),
-- `pollenColor`, `petalColor`.
--
-- Greens: `greens` (0-1) repaints the land from its baked colours into
-- families of green (emerald, sage, jade, chartreuse, a few golden crowns);
-- 0 shows the GLB's own colours. `plants` (0-1) is how many of the grown
-- grass tufts, bushes, sunflowers, daisies and small flowers are drawn.
-- `shading` (0-1) is how much the sun shapes the near land, its shade
-- tinted `shadowColor`.
--
-- Sky: `skyColor` above, `skyMidColor` (lavender) between, `horizonColor`
-- at the horizon, `clouds` (0-1); `mountainColor` is the cliffs' stone.
--
-- Watercolour: `paint` (0-1) turns the render into a watercolour painting
-- (soft brushy washes, hand-drawn wobble, pigment pooling at the edges);
-- `brush` is the size of its strokes (pixels at 720 high), `edges` how
-- much pigment pools, `paper` the paper's grain.
--
-- Look: `bloom`, `glow` (soft focus), `depthOfField` (0-1) with
-- `focusDistance` (metres), `exposure`, `skyColor` (above) and
-- `horizonColor`.
--
-- Place the node at the artboard's centre and set width/height to the
-- artboard's size.

export type Lake = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	cameraX: Input<number>,
	cameraY: Input<number>,
	cameraZ: Input<number>,
	rotationX: Input<number>,
	rotationY: Input<number>,
	rotationZ: Input<number>,
	fov: Input<number>,
	drift: Input<number>,
	tour: Input<number>,
	tourSpeed: Input<number>,
	navigation: Input<boolean>,
	navMode: Input<number>,
	zoom: Input<number>,
	resetView: Input<number>,
	dragX: Input<number>,
	dragY: Input<number>,
	sunAzimuth: Input<number>,
	sunElevation: Input<number>,
	sunIntensity: Input<number>,
	lightLeak: Input<number>,
	shafts: Input<number>,
	windStrength: Input<number>,
	windSpeed: Input<number>,
	windDirection: Input<number>,
	gustiness: Input<number>,
	flutter: Input<number>,
	reflection: Input<number>,
	ripples: Input<number>,
	glints: Input<number>,
	ringSpeed: Input<number>,
	rings: Input<number>,
	swans: Input<number>,
	lotusBob: Input<number>,
	mist: Input<number>,
	mistHeight: Input<number>,
	mistSpeed: Input<number>,
	wisps: Input<number>,
	wispOpacity: Input<number>,
	haze: Input<number>,
	bloom: Input<number>,
	glow: Input<number>,
	depthOfField: Input<number>,
	focusDistance: Input<number>,
	exposure: Input<number>,
	paint: Input<number>,
	paper: Input<number>,
	brush: Input<number>,
	edges: Input<number>,
	pollenAmount: Input<number>,
	pollenSize: Input<number>,
	pollenSpeed: Input<number>,
	petals: Input<number>,
	pollenColor: Input<Color>,
	petalColor: Input<Color>,
	sunColor: Input<Color>,
	skyColor: Input<Color>,
	horizonColor: Input<Color>,
	mistColor: Input<Color>,
	shadowColor: Input<Color>,
	shading: Input<number>,
	greens: Input<number>,
	plants: Input<number>,
	clouds: Input<number>,
	skyMidColor: Input<Color>,
	mountainColor: Input<Color>,
	waterColor: Input<Color>,

	context: Context?,
	shader: Shader?,
	postShader: Shader?,
	blurShader: Shader?,
	failed: boolean,
	time: number,
	windPhase: number,
	mistPhase: number,
	land: { Mesh },
	water: { Mesh },
	rippleMesh: { Mesh },
	plantDraws: { PlantDraw },
	camera: Camera,
	-- Navigation, on top of the camera inputs: orbit (degrees), pan (metres,
	-- moving the pivot) and zoom (times the orbit distance).
	tourTime: number,
	tourRamp: number,
	navYaw: number,
	navPitch: number,
	navPanX: number,
	navPanY: number,
	navPanZ: number,
	navZoom: number,
	-- Easing back to the inputs after a reset (1 to 0).
	navReset: number,
	lastResetView: number,
	lastDragX: number,
	lastDragY: number,
	-- Pointers down: id -> position.
	pointers: { [number]: Vector },
	pointerCount: number,
	lastTapTime: number,
	lastTapPosition: Vector,
	tapMoved: number,
	ubo: GPUBuffer?,
	mirrorUbo: GPUBuffer?,
	postUbo: GPUBuffer?,
	ids: GPUBuffer?,
	landBindings: GPUBindGroup?,
	mirrorBindings: GPUBindGroup?,
	mirrorSkyBindings: GPUBindGroup?,
	skyBindings: GPUBindGroup?,
	waterBindings: GPUBindGroup?,
	rippleBindings: GPUBindGroup?,
	wispBindings: GPUBindGroup?,
	pollenBindings: GPUBindGroup?,
	postBindings: GPUBindGroup?,
	nearBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	sceneCanvas: GPUCanvas?,
	mirrorCanvas: GPUCanvas?,
	outCanvas: GPUCanvas?,
	nearCanvas: GPUCanvas?,
	wideCanvas: GPUCanvas?,
	depthView: GPUTextureView?,
	mirrorDepthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	landPipeline: GPUPipeline?,
	instPipeline: GPUPipeline?,
	instMirrorPipeline: GPUPipeline?,
	instBindings: GPUBindGroup?,
	instMirrorBindings: GPUBindGroup?,
	mirrorPipeline: GPUPipeline?,
	mirrorSkyPipeline: GPUPipeline?,
	skyPipeline: GPUPipeline?,
	waterPipeline: GPUPipeline?,
	ripplePipeline: GPUPipeline?,
	wispPipeline: GPUPipeline?,
	pollenPipeline: GPUPipeline?,
	postPipeline: GPUPipeline?,
	nearPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	sampler: GPUSampler?,
	placeholder: GPUTextureView?,
	sunScreen: { number },
	targetW: number,
	targetH: number,
	targetSamples: number,
	frame: buffer,
	postParams: buffer,
	drawSampler: ImageSampler,
}

type Mesh = {
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
}

-- One kind of plant: its template mesh, drawn once per instance.
type PlantDraw = {
	template: number,
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	instanceBuffer: GPUBuffer,
	instanceCount: number,
}

-- The camera, as last set up, for the pan.
type Camera = {
	x: number, y: number, z: number,
	fx: number, fy: number, fz: number,
	rx: number, ry: number, rz: number,
	ux: number, uy: number, uz: number,
	tanX: number, tanY: number,
}

local UNIFORM_SIZE = 432
local POST_SIZE = 112
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local MAX_POLLEN = 3000
local MAX_WISPS = 64
local VERTEX_STRIDE = 24
-- Blob section kinds (see tools/export_lake.py).
local LAND, WATER, RIPPLES, TEMPLATE, INSTANCES = 1, 2, 3, 4, 5
-- Templates too fine to see in the reflection: grass tufts, small flowers.
local NOT_REFLECTED = { [22] = true, [23] = true }

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

-- The camera move: keys of time (s), position (glTF metres), turn, tilt
-- and roll (degrees, as rotationY / rotationX / rotationZ) and fov. The
-- turn is unwound (it runs a full -360 round the lotus beds). `still` keys
-- are held with no speed, so the move eases out of and into them; between
-- them it is a Catmull-Rom glide. On top, the camera banks into its turns.
type TourKey = { t: number, p: { number }, still: boolean? }
local HERO = { 0, 2.4, 6, -3.06, 4.05, 42.55, 0 }
local TOUR: { TourKey } = {
	-- Cam_Hero: the still lake, mirroring the sky and the ridges.
	{ t = 0, p = HERO, still = true },
	{ t = 3, p = HERO, still = true },
	-- A low skim down the lake's centre, a Dutch lean to the left.
	{ t = 13, p = { 3, 1.7, -16, -6, 1, 47, -5 } },
	-- Past the hamsas on the right, leaning back the other way.
	{ t = 22, p = { 5, 2.3, -47, -14, -2, 48, 4 } },
}
-- Then once round the lotus beds, clockwise, facing in: the turn is the
-- angle round the circle. In at -60 degrees, out at -420. Facing back
-- toward the start (about -120 to -270) the gimbal dips onto the lotuses,
-- so the bare ridge behind Cam_Hero (no trees on it) stays out of frame.
local ORBIT_X, ORBIT_Z, ORBIT_R = 22, -88, 16
local ORBIT_TILT = { -8, -11, -18, -30, -34, -32, -26, -14, -8, -8, -8, -8, -8 }
for n = 0, 12 do
	local a = -60 - n * 30
	local r = math.rad(a)
	table.insert(TOUR, {
		t = 30 + n * 2.5,
		p = { ORBIT_X + ORBIT_R * math.sin(r), 3 + 1.2 * math.sin(n / 12 * math.pi), ORBIT_Z + ORBIT_R * math.cos(r), a, ORBIT_TILT[n + 1], 46, 0 },
	})
end
-- Out of the circle, a rising crane onto the valley gap (11, 17, -200).
table.insert(TOUR, { t = 73, p = { 10, 12, -112, -360.6, 3, 48, 0 }, still = true })
table.insert(TOUR, { t = 79, p = { 10, 12, -112, -360.6, 3, 48, 0 }, still = true })
-- And a long, gliding pull-back home, settling as it lands.
table.insert(TOUR, { t = 93, p = { 4, 6, -48, -362, 4.5, 45, -3 } })
table.insert(TOUR, { t = 106, p = { HERO[1], HERO[2], HERO[3], HERO[4] - 360, HERO[5], HERO[6], HERO[7] }, still = true })
local TOUR_LENGTH = 106
local CHANNELS = 7

-- A key's slope for one channel: the Catmull-Rom tangent, 0 on still keys.
local function tourSlope(i: number, c: number): number
	local k = TOUR[i]
	if k.still or i == 1 or i == #TOUR then
		return 0
	end
	local a, b = TOUR[i - 1], TOUR[i + 1]
	return (b.p[c] - a.p[c]) / (b.t - a.t)
end

local function tourSample(t: number): { number }
	t = clamp(t, 0, TOUR_LENGTH)
	local i = 1
	while i < #TOUR - 1 and TOUR[i + 1].t <= t do
		i += 1
	end
	local a, b = TOUR[i], TOUR[i + 1]
	local h = b.t - a.t
	local s = clamp((t - a.t) / h, 0, 1)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local out = {}
	for c = 1, CHANNELS do
		out[c] = h00 * a.p[c] + h10 * h * tourSlope(i, c) + h01 * b.p[c] + h11 * h * tourSlope(i + 1, c)
	end
	return out
end

-- The pose at time t: x, y, z, turn, tilt, fov, roll, with the bank: the
-- camera leans into a turn by 0.75 degree per degree a second of it.
local function tourPose(t: number): { number }
	t = t % TOUR_LENGTH
	local out = tourSample(t)
	local rate = (tourSample(t + 0.25)[4] - tourSample(t - 0.25)[4]) / 0.5
	out[7] += clamp(rate * 0.75, -14, 14)
	return out
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

local function writeColor(u: buffer, offset: number, c: Color, w: number)
	local r, g, b = linear(c)
	write4(u, offset, r, g, b, w)
end

-- A GPU buffer from a slice of the blob, padded to a multiple of 4 bytes.
local function slice(data: buffer, offset: number, length: number, usage: 'vertex' | 'index'): GPUBuffer
	local size = math.max(4, math.ceil(length / 4) * 4)
	local bytes = buffer.create(size)
	buffer.copy(bytes, 0, data, offset, length)
	return GPUBuffer.new({ size = size, usage = usage, data = bytes, immutable = true })
end

local function load(self: Lake): boolean
	local context = self.context
	assert(context)
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`Lake: no blob asset named '{self.asset}'`)
		return false
	end
	local data = blob.data
	if buffer.len(data) < 16 or buffer.readstring(data, 0, 4) ~= 'PMPA' then
		print('Lake: the blob is not a lake.bin')
		return false
	end
	local count = buffer.readu32(data, 8)
	-- Section bytes live in part (kind >> 8): 0 is this blob, n the blob `asset`(n + 1).
	local parts: { [number]: buffer } = { [0] = data }
	local function part(n: number): buffer?
		if parts[n] == nil then
			local b = context:blob(`{self.asset}{n + 1}`)
			if b == nil then
				print(`Lake: no blob asset named '{self.asset}{n + 1}'`)
				return nil
			end
			parts[n] = b.data
		end
		return parts[n]
	end
	local templates: { [number]: Mesh } = {}
	local plants = {}
	for i = 0, count - 1 do
		local o = 16 + i * 32
		local word = buffer.readu32(data, o)
		local kind = bit32.band(word, 0xff)
		local src = part(bit32.rshift(word, 8))
		if src == nil then
			return false
		end
		local vbo, vbl = buffer.readu32(data, o + 12), buffer.readu32(data, o + 16)
		local ibo, ibl = buffer.readu32(data, o + 20), buffer.readu32(data, o + 24)
		local id = buffer.readu32(data, o + 28)
		if kind == INSTANCES then
			table.insert(plants, { template = id, buffer = slice(src, vbo, vbl, 'vertex'), count = buffer.readu32(data, o + 4) })
		else
			local mesh: Mesh = {
				vertexBuffer = slice(src, vbo, vbl, 'vertex'),
				indexBuffer = slice(src, ibo, ibl, 'index'),
				indexCount = buffer.readu32(data, o + 8),
			}
			if kind == LAND then
				table.insert(self.land, mesh)
			elseif kind == WATER then
				table.insert(self.water, mesh)
			elseif kind == RIPPLES then
				table.insert(self.rippleMesh, mesh)
			elseif kind == TEMPLATE then
				templates[id] = mesh
			end
		end
	end
	for _, pl in plants do
		local t = templates[pl.template]
		if t and pl.count > 0 then
			table.insert(self.plantDraws, {
				template = pl.template,
				vertexBuffer = t.vertexBuffer,
				indexBuffer = t.indexBuffer,
				indexCount = t.indexCount,
				instanceBuffer = pl.buffer,
				instanceCount = pl.count,
			})
		end
	end
	self.ubo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.mirrorUbo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.postUbo = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform' })
	local ids = buffer.create(MAX_POLLEN * 4)
	for i = 0, MAX_POLLEN - 1 do
		buffer.writef32(ids, i * 4, i)
	end
	self.ids = GPUBuffer.new({ size = MAX_POLLEN * 4, usage = 'vertex', data = ids, immutable = true })
	self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	return #self.land > 0
end

function init(self: Lake, context: Context): boolean
	self.context = context
	self.shader = context:shader('lake')
	self.postShader = context:shader('post')
	self.blurShader = context:shader('blur')
	if self.shader == nil or self.postShader == nil or self.blurShader == nil then
		print('Lake: shaders "lake", "blur" and "post" are needed')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('Lake: setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

-- Set below, with the navigation.
local hostDrag: (self: Lake, dx: number, dy: number) -> () = function() end

local function startReset(self: Lake)
	self.navReset = 1
end

function advance(self: Lake, seconds: number): boolean
	if self.resetView ~= self.lastResetView then
		self.lastResetView = self.resetView
		startReset(self)
	end
	local dx, dy = self.dragX - self.lastDragX, self.dragY - self.lastDragY
	if dx ~= 0 or dy ~= 0 then
		self.lastDragX, self.lastDragY = self.dragX, self.dragY
		if self.navigation then
			self.navReset = 0
			hostDrag(self, dx, dy)
		end
	end
	if self.navReset > 0 then
		-- Glide home: each step takes the same share of what is left.
		local k = 1 - math.exp(-math.min(seconds, 0.1) * 9)
		self.navYaw -= self.navYaw * k
		self.navPitch -= self.navPitch * k
		self.navPanX -= self.navPanX * k
		self.navPanY -= self.navPanY * k
		self.navPanZ -= self.navPanZ * k
		self.navZoom += (1 - self.navZoom) * k
		self.navReset = math.max(self.navReset - seconds * 1.5, 0)
		if self.navReset == 0 then
			self.navYaw, self.navPitch, self.navZoom = 0, 0, 1
			self.navPanX, self.navPanY, self.navPanZ = 0, 0, 0
		end
	end
	local dt = math.min(seconds, 0.1)
	self.time += dt
	-- The camera move's clock runs only while it is on.
	local on = self.tour > 0.5
	if self.tourRamp < 0 then
		-- The first frame starts where the input says, with no glide.
		self.tourRamp = if on then 1 else 0
	end
	if on then
		self.tourTime = (self.tourTime + dt * clamp(self.tourSpeed, 0, 4)) % TOUR_LENGTH
	end
	self.tourRamp = clamp(self.tourRamp + (if on then dt else -dt) / 3, 0, 1)
	-- Phases run at their speeds, so changing a speed never jumps.
	self.windPhase += dt * math.max(self.windSpeed, 0)
	self.mistPhase += dt * math.max(self.mistSpeed, 0)
	return true
end

---------------------------------------------------------------------------
-- Targets and pipelines

local function canvas(context: Context, existing: GPUCanvas?, w: number, h: number): GPUCanvas
	if existing == nil then
		return context:gpuCanvas({ width = w, height = h })
	end
	existing:resize(w, h)
	return existing
end

local function ensureTargets(self: Lake): boolean
	local context = self.context
	assert(context)
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(1, math.floor(self.width * res))
	local h = math.max(1, math.floor(self.height * res))
	local samples = if self.msaa >= 2 then 4 else 1
	if self.sceneCanvas and self.outCanvas and w == self.targetW and h == self.targetH and samples == self.targetSamples then
		return true
	end
	local scene = canvas(context, self.sceneCanvas, w, h)
	self.sceneCanvas = scene
	self.outCanvas = canvas(context, self.outCanvas, w, h)
	-- The reflection, and the blurs: half and a quarter of the size.
	local hw, hh = math.max(1, w // 2), math.max(1, h // 2)
	local mirror = canvas(context, self.mirrorCanvas, hw, hh)
	self.mirrorCanvas = mirror
	self.nearCanvas = canvas(context, self.nearCanvas, hw, hh)
	self.wideCanvas = canvas(context, self.wideCanvas, math.max(1, w // 4), math.max(1, h // 4))
	local out = self.outCanvas
	assert(out)
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.mirrorDepthView = GPUTexture.new({ width = hw, height = hh, format = DEPTH_FORMAT, renderTarget = true }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = scene.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.landPipeline == nil then
		local shader = self.shader
		local postShader = self.postShader
		local blurShader = self.blurShader
		assert(shader and postShader and blurShader)
		local target: { ColorTarget } = { { format = scene.format } }
		local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
		local behind: DepthStencilState = { format = DEPTH_FORMAT, compare = 'always', write = false }
		local layout: { VertexBufferLayout } = {
			{
				stride = VERTEX_STRIDE,
				attributes = {
					{ format = 'float32x3', slot = 0, offset = 0 },
					{ format = 'snorm8x4', slot = 1, offset = 12 },
					{ format = 'unorm8x4', slot = 2, offset = 16 },
					{ format = 'unorm8x4', slot = 3, offset = 20 },
				},
			},
		}
		local over: { ColorTarget } = {
			{
				format = scene.format,
				blend = {
					srcColor = 'one',
					dstColor = 'one-minus-src-alpha',
					colorOp = 'add',
					srcAlpha = 'zero',
					dstAlpha = 'one',
					alphaOp = 'add',
				},
			},
		}
		local soft: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = false }
		local ids: { VertexBufferLayout } = {
			{ stride = 4, stepMode = 'instance', attributes = { { format = 'float32', slot = 0, offset = 0 } } },
		}
		self.skyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = behind,
			sampleCount = samples,
		})
		self.landPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_land' },
			fragment = { module = shader, entryPoint = 'fs_land' },
			vertexLayout = layout,
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		local instLayout: { VertexBufferLayout } = {
			{
				stride = 28,
				attributes = {
					{ format = 'float32x3', slot = 0, offset = 0 },
					{ format = 'float32x3', slot = 1, offset = 12 },
					{ format = 'float32', slot = 2, offset = 24 },
				},
			},
			{
				stride = 20,
				stepMode = 'instance',
				attributes = {
					{ format = 'float16x4', slot = 3, offset = 0 },
					{ format = 'snorm8x4', slot = 4, offset = 8 },
					{ format = 'snorm8x4', slot = 5, offset = 12 },
					{ format = 'unorm8x4', slot = 6, offset = 16 },
				},
			},
		}
		self.instPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst' },
			fragment = { module = shader, entryPoint = 'fs_inst' },
			vertexLayout = instLayout,
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.waterPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_water' },
			fragment = { module = shader, entryPoint = 'fs_water' },
			vertexLayout = layout,
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.ripplePipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_water' },
			fragment = { module = shader, entryPoint = 'fs_ripple' },
			vertexLayout = layout,
			colorTargets = over,
			depthStencil = soft,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.wispPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_wisp' },
			fragment = { module = shader, entryPoint = 'fs_wisp' },
			vertexLayout = ids,
			colorTargets = over,
			depthStencil = soft,
			sampleCount = samples,
		})
		self.pollenPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_pollen' },
			fragment = { module = shader, entryPoint = 'fs_pollen' },
			vertexLayout = ids,
			colorTargets = over,
			depthStencil = soft,
			sampleCount = samples,
		})
		-- The reflection: no MSAA, at half size.
		local mirrorTarget: { ColorTarget } = { { format = mirror.format } }
		self.mirrorSkyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = mirrorTarget,
			depthStencil = behind,
		})
		self.mirrorPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_land' },
			fragment = { module = shader, entryPoint = 'fs_land' },
			vertexLayout = layout,
			colorTargets = mirrorTarget,
			depthStencil = depth,
			cullMode = 'none',
		})
		self.instMirrorPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst' },
			fragment = { module = shader, entryPoint = 'fs_inst' },
			vertexLayout = instLayout,
			colorTargets = mirrorTarget,
			depthStencil = depth,
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
		self.landBindings = nil
		self.instBindings = nil
		self.instMirrorBindings = nil
		self.mirrorBindings = nil
		self.mirrorSkyBindings = nil
		self.skyBindings = nil
		self.rippleBindings = nil
		self.wispBindings = nil
		self.pollenBindings = nil
	end
	-- These read canvases that have just been remade.
	self.waterBindings = nil
	self.postBindings = nil
	self.nearBindings = nil
	self.wideBindings = nil
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return true
end

---------------------------------------------------------------------------
-- Frame uniforms

local function frameUniforms(self: Lake)
	local u = self.frame
	local t = self.time
	local drift = clamp(self.drift, 0, 2)
	-- The camera: the inputs, or the camera move, or between the two.
	local cx, cy, cz = self.cameraX, self.cameraY, self.cameraZ
	local turn, tilt, fov = self.rotationY, self.rotationX, self.fov
	local roll = self.rotationZ
	local r = self.tourRamp
	if r > 0 then
		local k = r * r * (3 - 2 * r)
		local pose = tourPose(self.tourTime)
		-- The move's turn is unwound; blend to it the short way round.
		pose[4] = turn + ((pose[4] - turn + 180) % 360 - 180)
		cx, cy, cz = cx + (pose[1] - cx) * k, cy + (pose[2] - cy) * k, cz + (pose[3] - cz) * k
		turn, tilt, fov = turn + (pose[4] - turn) * k, tilt + (pose[5] - tilt) * k, fov + (pose[6] - fov) * k
		roll += (pose[7] - roll) * k
	end
	-- With a slow floating sway.
	local ex = cx + math.sin(t * 0.13) * 0.12 * drift
	local ey = cy + math.sin(t * 0.17 + 1) * 0.06 * drift
	local ez = cz + math.cos(t * 0.11) * 0.12 * drift
	local yaw = math.rad(turn + math.sin(t * 0.09) * 0.6 * drift)
	local pitch = math.rad(tilt + math.sin(t * 0.12 + 2) * 0.3 * drift)
	local bank = math.rad(roll + math.sin(t * 0.07) * 0.2 * drift)
	-- Navigation: orbit the eye about a pivot `focusDistance` ahead (moved
	-- by the pan), at that distance times the zoom.
	local cp = math.cos(pitch)
	local orbit = clamp(self.focusDistance, 2, 300)
	local px = ex - math.sin(yaw) * cp * orbit + self.navPanX
	local py = ey + math.sin(pitch) * orbit + self.navPanY
	local pz = ez - math.cos(yaw) * cp * orbit + self.navPanZ
	yaw += math.rad(self.navYaw)
	pitch = clamp(pitch + math.rad(self.navPitch), math.rad(-85), math.rad(85))
	cp = math.cos(pitch)
	local fx, fy, fz = -math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp
	local dist = orbit * self.navZoom * clamp(self.zoom, 0.05, 20)
	ex, ey, ez = px - fx * dist, py - fy * dist, pz - fz * dist
	-- Never under the water.
	ey = math.max(ey, 0.35)
	-- right = fwd x worldUp, up = right x fwd, then the roll.
	local rx, rz = -fz, fx
	local rl = math.max(math.sqrt(rx * rx + rz * rz), 1e-6)
	rx, rz = rx / rl, rz / rl
	local ry = 0
	local ux = ry * fz - rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy - ry * fx
	local cr, sr = math.cos(bank), math.sin(bank)
	local Rx, Ry, Rz = rx * cr + ux * sr, ry * cr + uy * sr, rz * cr + uz * sr
	local Ux, Uy, Uz = ux * cr - rx * sr, uy * cr - ry * sr, uz * cr - rz * sr

	local aspect = self.targetW / math.max(self.targetH, 1)
	local fovY = math.rad(clamp(fov, 10, 120))
	local tanY = math.tan(fovY / 2)
	local proj = Mat4.perspectiveReverseZ(fovY, aspect, 0.1)
	local view = Mat4.lookAt(Vector.xyz(ex, ey, ez), Vector.xyz(ex + fx, ey + fy, ez + fz), Vector.xyz(Ux, Uy, Uz))
	local viewProj = proj * view
	viewProj:writeToBuffer(u, 0)
	write4(u, 64, ex, ey, ez, t)
	local az = math.rad(self.sunAzimuth)
	local el = math.rad(clamp(self.sunElevation, -10, 90))
	local sx, sy, sz = math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)
	write4(u, 80, sx, sy, sz, math.max(self.sunIntensity, 0))
	writeColor(u, 96, self.sunColor, 0.55)
	writeColor(u, 112, self.horizonColor, 0)
	writeColor(u, 128, self.skyColor, math.max(self.haze, 0))
	writeColor(u, 144, self.mistColor, math.max(self.mist, 0))
	write4(u, 160, math.max(self.mistHeight, 0.1), self.mistPhase, clamp(self.wispOpacity, 0, 1), clamp(self.wisps, 0, MAX_WISPS))
	local wa = math.rad(self.windDirection)
	write4(u, 176, math.cos(wa), math.sin(wa), clamp(self.windStrength, 0, 3), clamp(self.gustiness, 0, 1))
	write4(u, 192, self.windPhase, clamp(self.flutter, 0, 3), math.max(self.swans, 0), math.max(self.lotusBob, 0))
	writeColor(u, 208, self.waterColor, clamp(self.reflection, 0, 1))
	write4(u, 224, math.max(self.ripples, 0), math.max(self.glints, 0), math.max(self.ringSpeed, 0), math.max(self.rings, 0))
	write4(u, 240, clamp(self.pollenAmount, 0, MAX_POLLEN), math.max(self.pollenSize, 0.001), math.max(self.pollenSpeed, 0), 1)
	writeColor(u, 256, self.pollenColor, 0.9)
	write4(u, 272, Rx, Ry, Rz, tanY * aspect)
	write4(u, 288, Ux, Uy, Uz, tanY)
	write4(u, 304, fx, fy, fz, math.max(self.focusDistance, 0.5))
	-- Pollen fills a box that travels with the camera, a little ahead of
	-- it and down toward the ground.
	write4(u, 320, ex + fx * 12, math.max(ey - 1.5, 4.6), ez + fz * 12, clamp(self.depthOfField, 0, 2) * 2.5)
	write4(u, 336, clamp(self.petals, 0, 1), math.max(self.pollenSize, 0.001) * 2.4, 0, 0)
	writeColor(u, 352, self.petalColor, 0)
	write4(u, 368, 1 / math.max(self.targetW, 1), 1 / math.max(self.targetH, 1), 0, 0)
	writeColor(u, 384, self.shadowColor, clamp(self.shading, 0, 1))
	writeColor(u, 400, self.skyMidColor, clamp(self.greens, 0, 1))
	writeColor(u, 416, self.mountainColor, clamp(self.clouds, 0, 1))

	local cam = self.camera
	cam.x, cam.y, cam.z = ex, ey, ez
	cam.fx, cam.fy, cam.fz = fx, fy, fz
	cam.rx, cam.ry, cam.rz = Rx, Ry, Rz
	cam.ux, cam.uy, cam.uz = Ux, Uy, Uz
	cam.tanX, cam.tanY = tanY * aspect, tanY

	-- Where the sun is on screen, for the light shafts and glow.
	local ahead = sx * fx + sy * fy + sz * fz
	local q = viewProj:transformPoint(ex + sx * 1000, ey + sy * 1000, ez + sz * 1000)
	local screen = self.sunScreen
	screen[1] = q.x * 0.5 + 0.5
	screen[2] = 0.5 - q.y * 0.5
	screen[3] = if ahead > 0.05 then 1 else 0
end

-- The mirror pass's uniforms: the same, seen from under the water. The
-- view-projection takes a flip about y = 0 (its second column negated).
local function mirrorUniforms(self: Lake)
	local u = self.frame
	for k = 0, 3 do
		local at = 16 + k * 4
		buffer.writef32(u, at, -buffer.readf32(u, at))
	end
	buffer.writef32(u, 124, 1)
	write4(u, 368, 1 / math.max(self.targetW // 2, 1), 1 / math.max(self.targetH // 2, 1), 0, 0)
end

---------------------------------------------------------------------------
-- Render

local function draw3(pass: GPURenderPass, meshes: { Mesh })
	for _, mesh in meshes do
		pass:setVertexBuffer(0, mesh.vertexBuffer)
		pass:setIndexBuffer(mesh.indexBuffer, 'uint16')
		pass:drawIndexed(mesh.indexCount)
	end
end

local function render(self: Lake): Image?
	if not ensureTargets(self) then
		return nil
	end
	local scene, out, mirror = self.sceneCanvas, self.outCanvas, self.mirrorCanvas
	local depthView, mirrorDepth = self.depthView, self.mirrorDepthView
	local ubo, mirrorUbo, postUbo, sampler, ids = self.ubo, self.mirrorUbo, self.postUbo, self.sampler, self.ids
	local sky, landP, mirrorP, mirrorSky = self.skyPipeline, self.landPipeline, self.mirrorPipeline, self.mirrorSkyPipeline
	local waterP, rippleP, wispP, pollenP = self.waterPipeline, self.ripplePipeline, self.wispPipeline, self.pollenPipeline
	local instP, instMirrorP = self.instPipeline, self.instMirrorPipeline
	if not (scene and out and mirror and depthView and mirrorDepth and ubo and mirrorUbo and postUbo and sampler and ids) then
		return nil
	end
	if not (sky and landP and mirrorP and mirrorSky and waterP and rippleP and wispP and pollenP and instP and instMirrorP) then
		return nil
	end

	frameUniforms(self)
	ubo:write(self.frame)
	mirrorUniforms(self)
	mirrorUbo:write(self.frame)

	-- A pipeline's bindings: only the uniforms, as WebGPU's layouts list.
	-- Some runtimes list every binding in the module for every pipeline;
	-- then a 1x1 placeholder stands in for the reflection.
	local function plain(pipeline: GPUPipeline, buf: GPUBuffer): GPUBindGroup
		local ok, group = pcall(function()
			return GPUBindGroup.new({ layout = pipeline:getBindGroupLayout(0), ubos = { { slot = 0, buffer = buf } } })
		end)
		if ok then
			return group
		end
		local placeholder = self.placeholder
		if placeholder == nil then
			local px = buffer.create(4)
			buffer.writeu32(px, 0, 0xffffffff)
			local tex = GPUTexture.new({ width = 1, height = 1, label = 'lake placeholder' })
			tex:upload({ data = px, width = 1, height = 1 })
			placeholder = tex:view()
			self.placeholder = placeholder
		end
		assert(placeholder)
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = buf } },
			textures = { { slot = 1, view = placeholder } },
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	self.landBindings = self.landBindings or plain(landP, ubo)
	self.instBindings = self.instBindings or plain(instP, ubo)
	self.instMirrorBindings = self.instMirrorBindings or plain(instMirrorP, mirrorUbo)
	self.skyBindings = self.skyBindings or plain(sky, ubo)
	self.mirrorBindings = self.mirrorBindings or plain(mirrorP, mirrorUbo)
	self.mirrorSkyBindings = self.mirrorSkyBindings or plain(mirrorSky, mirrorUbo)
	self.rippleBindings = self.rippleBindings or plain(rippleP, ubo)
	self.wispBindings = self.wispBindings or plain(wispP, ubo)
	self.pollenBindings = self.pollenBindings or plain(pollenP, ubo)
	if self.waterBindings == nil then
		self.waterBindings = GPUBindGroup.new({
			layout = waterP:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 1, view = mirror:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	local landBindings, skyBindings, mirrorBindings, mirrorSkyBindings = self.landBindings, self.skyBindings, self.mirrorBindings, self.mirrorSkyBindings
	local waterBindings, rippleBindings, wispBindings, pollenBindings = self.waterBindings, self.rippleBindings, self.wispBindings, self.pollenBindings
	assert(landBindings and skyBindings and mirrorBindings and mirrorSkyBindings)
	assert(waterBindings and rippleBindings and wispBindings and pollenBindings)
	local instBindings, instMirrorBindings = self.instBindings, self.instMirrorBindings
	assert(instBindings and instMirrorBindings)
	local share = clamp(self.plants, 0, 1)
	local function drawPlants(pass: GPURenderPass, mirrored: boolean)
		for _, d in self.plantDraws do
			local n = math.floor(d.instanceCount * share)
			if n > 0 and not (mirrored and NOT_REFLECTED[d.template]) then
				pass:setVertexBuffer(0, d.vertexBuffer)
				pass:setVertexBuffer(1, d.instanceBuffer)
				pass:setIndexBuffer(d.indexBuffer, 'uint16')
				pass:drawIndexed(d.indexCount, n)
			end
		end
	end

	-- The reflection: the sky and the land above the water, mirrored.
	if self.reflection > 0 then
		local rp = mirror:beginRenderPass({
			color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } },
			depthStencil = { view = mirrorDepth, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
		})
		rp:setPipeline(mirrorSky)
		rp:setBindGroup(0, mirrorSkyBindings)
		rp:draw(3)
		rp:setPipeline(mirrorP)
		rp:setBindGroup(0, mirrorBindings)
		draw3(rp, self.land)
		if share > 0 then
			rp:setPipeline(instMirrorP)
			rp:setBindGroup(0, instMirrorBindings)
			drawPlants(rp, true)
		end
		rp:finish()
	end

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = scene:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 1 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } }
	local pass = scene:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
	})
	pass:setPipeline(sky)
	pass:setBindGroup(0, skyBindings)
	pass:draw(3)
	pass:setPipeline(landP)
	pass:setBindGroup(0, landBindings)
	draw3(pass, self.land)
	if share > 0 then
		pass:setPipeline(instP)
		pass:setBindGroup(0, instBindings)
		drawPlants(pass, false)
	end
	pass:setPipeline(waterP)
	pass:setBindGroup(0, waterBindings)
	draw3(pass, self.water)
	if self.rings > 0 then
		pass:setPipeline(rippleP)
		pass:setBindGroup(0, rippleBindings)
		draw3(pass, self.rippleMesh)
	end
	local wisps = math.ceil(clamp(self.wisps, 0, MAX_WISPS))
	if wisps > 0 and self.wispOpacity > 0 then
		pass:setPipeline(wispP)
		pass:setBindGroup(0, wispBindings)
		pass:setVertexBuffer(0, ids)
		pass:draw(6, wisps)
	end
	local pollen = math.ceil(clamp(self.pollenAmount, 0, MAX_POLLEN))
	if pollen > 0 then
		pass:setPipeline(pollenP)
		pass:setBindGroup(0, pollenBindings)
		pass:setVertexBuffer(0, ids)
		pass:draw(6, pollen)
	end
	pass:finish()

	-- The finish.
	local p = self.postParams
	write4(p, 0, 1 / self.targetW, 1 / self.targetH, self.targetW / self.targetH, self.time)
	write4(p, 16, math.max(self.bloom, 0), clamp(self.glow, 0, 1), clamp(self.depthOfField, 0, 1), math.max(self.exposure, 0))
	write4(p, 32, 1.03, 1.0, 0.95, 1.04)
	write4(p, 48, 0.25, 0.35, 0.85, 0.0045)
	local lr, lg, lb = linear(self.sunColor)
	write4(p, 64, lr, lg * 0.95, lb * 0.85, clamp(self.lightLeak, 0, 1.5))
	local sun = self.sunScreen
	write4(p, 80, sun[1], sun[2], math.max(self.shafts, 0), sun[3])
	write4(p, 96, clamp(self.paint, 0, 1), clamp(self.paper, 0, 2), clamp(self.brush, 1, 12) * self.targetH / 720, math.max(self.edges, 0))
	postUbo:write(p)
	local near, wide = self.nearCanvas, self.wideCanvas
	local nearPipeline, widePipeline, postPipeline = self.nearPipeline, self.widePipeline, self.postPipeline
	if not (near and wide and nearPipeline and widePipeline and postPipeline) then
		return nil
	end
	if self.postBindings == nil then
		self.nearBindings = GPUBindGroup.new({
			layout = nearPipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = scene:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		-- The wide blur spreads the half-size one further.
		self.wideBindings = GPUBindGroup.new({
			layout = widePipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = near:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.postBindings = GPUBindGroup.new({
			layout = postPipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = {
				{ slot = 1, view = scene:colorView() },
				{ slot = 3, view = near:colorView() },
				{ slot = 4, view = wide:colorView() },
			},
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	local postBindings, nearBindings, wideBindings = self.postBindings, self.nearBindings, self.wideBindings
	assert(postBindings and nearBindings and wideBindings)
	local blurPass = near:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	blurPass:setPipeline(nearPipeline)
	blurPass:setBindGroup(0, nearBindings)
	blurPass:draw(3)
	blurPass:finish()
	local widePass = wide:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	widePass:setPipeline(widePipeline)
	widePass:setBindGroup(0, wideBindings)
	widePass:draw(3)
	widePass:finish()
	local post = out:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	post:setPipeline(postPipeline)
	post:setBindGroup(0, postBindings)
	post:draw(3)
	post:finish()
	return out.image
end

---------------------------------------------------------------------------
-- Navigation

local ORBIT_DEGREES_PER_PX = 0.3

-- Moves the pivot by a drag of (dx, dy) node pixels: the scene follows the
-- pointer, as in Blender.
local function pan(self: Lake, dx: number, dy: number)
	local cam = self.camera
	local orbit = clamp(self.focusDistance, 2, 300) * self.navZoom * clamp(self.zoom, 0.05, 20)
	local perPx = 2 * orbit * cam.tanY / math.max(self.height, 1)
	self.navPanX += (-cam.rx * dx + cam.ux * dy) * perPx
	self.navPanY += (-cam.ry * dx + cam.uy * dy) * perPx
	self.navPanZ += (-cam.rz * dx + cam.uz * dy) * perPx
end

local function zoomBy(self: Lake, factor: number)
	self.navZoom = clamp(self.navZoom * factor, 0.05, 6)
end

-- A one-pointer drag of (dx, dy) node pixels, by `navMode`: turntable orbit
-- (the scene turns with the pointer), pan or zoom.
local function applyDrag(self: Lake, dx: number, dy: number)
	local mode = math.floor(self.navMode + 0.5)
	if mode == 1 then
		pan(self, dx, dy)
	elseif mode == 2 then
		zoomBy(self, math.exp(dy * 0.005))
	else
		self.navYaw -= dx * ORBIT_DEGREES_PER_PX
		self.navPitch -= dy * ORBIT_DEGREES_PER_PX
		local base = self.rotationX
		self.navPitch = clamp(self.navPitch, -85 - base, 85 - base)
	end
end

hostDrag = applyDrag

local function pointerDown(self: Lake, event: PointerEvent)
	if not self.navigation then
		return
	end
	if self.pointers[event.id] == nil then
		self.pointerCount += 1
	end
	self.pointers[event.id] = event.position
	self.navReset = 0
	if self.pointerCount == 1 then
		-- A second tap soon after, near the first: back home.
		local near = Vector.length(event.position - self.lastTapPosition) < 30
		if self.time - self.lastTapTime < 0.35 and near then
			startReset(self)
			self.lastTapTime = -1
		else
			self.lastTapTime = self.time
			self.lastTapPosition = event.position
		end
		self.tapMoved = 0
	end
	event:hit()
end

local function pointerMove(self: Lake, event: PointerEvent)
	local last = self.pointers[event.id]
	if not self.navigation or last == nil then
		return
	end
	local d = event.position - last
	self.tapMoved += Vector.length(d)
	if self.tapMoved > 12 then
		self.lastTapTime = -1
	end
	if self.pointerCount >= 2 then
		-- Two fingers: the midpoint pans, the spread zooms.
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
				zoomBy(self, before / after)
			end
			pan(self, d.x / 2, d.y / 2)
		end
	else
		applyDrag(self, d.x, d.y)
	end
	self.pointers[event.id] = event.position
	event:hit()
end

local function pointerUp(self: Lake, event: PointerEvent)
	if self.pointers[event.id] ~= nil then
		self.pointers[event.id] = nil
		self.pointerCount = math.max(self.pointerCount - 1, 0)
		event:hit()
	end
end

local function pointerExit(self: Lake, event: PointerEvent)
	pointerUp(self, event)
end

function draw(self: Lake, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('Lake: render failed: ' .. tostring(result))
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

return function(): Node<Lake>
	return {
		asset = 'lake',
		width = 1280,
		height = 720,
		resolution = 1,
		msaa = 4,
		cameraX = -6.6,
		cameraY = 4.1,
		cameraZ = -36.7,
		rotationX = 4.05,
		rotationY = -3.06,
		rotationZ = 0,
		fov = 42.55,
		drift = 1,
		tour = 1,
		tourSpeed = 1,
		tourTime = 0,
		tourRamp = -1,
		navigation = true,
		navMode = 0,
		zoom = 1,
		resetView = 0,
		dragX = 0,
		dragY = 0,
		sunAzimuth = -81,
		sunElevation = 8,
		sunIntensity = 0.4,
		lightLeak = 0.2,
		shafts = 0,
		windStrength = 0.05,
		windSpeed = 0,
		windDirection = 200,
		gustiness = 0.6,
		flutter = 1,
		reflection = 1,
		ripples = 2.45,
		glints = 1.4,
		ringSpeed = 1,
		rings = 0.7,
		swans = 1,
		lotusBob = 1,
		mist = 0.35,
		mistHeight = 3,
		mistSpeed = 1,
		wisps = 14,
		wispOpacity = 0.23,
		haze = 0,
		bloom = 0.35,
		glow = 0.1,
		depthOfField = 0.26,
		focusDistance = 11,
		exposure = 0.54,
		paint = 0.59,
		paper = 1.7,
		brush = 12,
		edges = 0,
		pollenAmount = 1600,
		pollenSize = 0.035,
		pollenSpeed = 1,
		petals = 0.15,
		pollenColor = Color.rgb(255, 222, 140),
		petalColor = Color.rgb(250, 168, 50),
		sunColor = Color.rgb(255, 214, 150),
		skyColor = Color.rgb(247, 236, 208),
		horizonColor = Color.rgb(252, 228, 196),
		mistColor = Color.rgb(214, 190, 222),
		shadowColor = Color.rgb(120, 146, 168),
		shading = 0.36,
		greens = 0.42,
		plants = 1,
		clouds = 0,
		skyMidColor = Color.rgb(246, 226, 210),
		mountainColor = Color.rgb(150, 132, 172),
		waterColor = Color.rgb(150, 228, 205),

		context = nil,
		shader = nil,
		postShader = nil,
		blurShader = nil,
		failed = false,
		time = 0,
		windPhase = 0,
		mistPhase = 0,
		land = {},
		water = {},
		rippleMesh = {},
		plantDraws = {},
		navYaw = 0,
		navPitch = 0,
		navPanX = 0,
		navPanY = 0,
		navPanZ = 0,
		navZoom = 1,
		navReset = 0,
		lastResetView = 0,
		lastDragX = 0,
		lastDragY = 0,
		pointers = {},
		pointerCount = 0,
		lastTapTime = -1,
		lastTapPosition = Vector.xy(0, 0),
		tapMoved = 0,
		camera = { x = 0, y = 0, z = 0, fx = 0, fy = 0, fz = -1, rx = 1, ry = 0, rz = 0, ux = 0, uy = 1, uz = 0, tanX = 1, tanY = 1 },
		ubo = nil,
		mirrorUbo = nil,
		postUbo = nil,
		ids = nil,
		landBindings = nil,
		mirrorBindings = nil,
		mirrorSkyBindings = nil,
		skyBindings = nil,
		waterBindings = nil,
		rippleBindings = nil,
		wispBindings = nil,
		pollenBindings = nil,
		postBindings = nil,
		nearBindings = nil,
		wideBindings = nil,
		sceneCanvas = nil,
		mirrorCanvas = nil,
		outCanvas = nil,
		nearCanvas = nil,
		wideCanvas = nil,
		depthView = nil,
		mirrorDepthView = nil,
		msaaView = nil,
		landPipeline = nil,
		instPipeline = nil,
		instMirrorPipeline = nil,
		instBindings = nil,
		instMirrorBindings = nil,
		mirrorPipeline = nil,
		mirrorSkyPipeline = nil,
		skyPipeline = nil,
		waterPipeline = nil,
		ripplePipeline = nil,
		wispPipeline = nil,
		pollenPipeline = nil,
		postPipeline = nil,
		nearPipeline = nil,
		widePipeline = nil,
		sampler = nil,
		placeholder = nil,
		sunScreen = { 0.5, 0.5, 0, 0 },
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
