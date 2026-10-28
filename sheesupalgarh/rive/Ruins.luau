-- Shishupalgarh: the ruined sandstone pillars from Shishupalgarh_Ruins.blend,
-- in a sunlit meadow. Ivy and bushes wave in the wind, the grass rolls with
-- passing gusts, pink pollen and petals drift slowly through a soft haze,
-- and the whole frame has a dreamy bloom and soft focus.
--
-- Rendered in 3D on the GPU (ruins.wgsl), then finished in a second pass
-- (blur.wgsl, post.wgsl): bloom, a soft glow, depth of field, grading.
--
-- The geometry is the blob `asset` (ruins.bin, written by
-- ../tools/export_scene.py): the static meshes, plus the leaves, grass and
-- flowers as GPU instances of four small template meshes.
--
-- Camera: cameraX/Y/Z is its position in metres (Y up; the plinth is
-- centred on the origin, 25 m along X). rotationX tilts it up, rotationY
-- turns it (positive turns left, about the Y axis), rotationZ rolls it; all
-- in degrees.
-- `fov` is the vertical field of view in degrees. `drift` (0-1) adds a
-- slow, floating handheld sway.
--
-- Sun: `sunAzimuth` (degrees around Y, 0 = +X, 90 = +Z; the camera looks
-- toward about -52 by default), `sunElevation` (degrees) and `sunIntensity`. The
-- default is a low golden sun to the right of the view, so the pillars are
-- lit from the side and their shadows stream toward the camera;
-- `lightLeak` (0-1) is its glow on screen. The .blend's own sun is azimuth 28, elevation 27. The sun casts
-- shadows (a shadow map from the stone and the clumps), and `shafts` sets
-- its light shafts.
--
-- Wind: `windStrength` (0-2), `windSpeed`, `windDirection` (degrees, the
-- way it blows, 0 = +X), `gustiness` (0-1: how much it comes in waves
-- rolling across the meadow) and `flutter` (how much the leaves flick).
--
-- Air: `haze` (density), `clouds` (0-1), `bloom`, `glow` (soft focus),
-- `depthOfField` (0-1) with `focusDistance` (metres), `exposure`.
--
-- Glory: `glory` (0-1) takes the ruins to their full glory: the fallen
-- fragments fly back onto their pillars one by one, glowing; the ivy, moss,
-- vines and the bushes on the plinth recede; the stone comes up clean and
-- the light warms. The state machine keys it (the `restore` and `ruin`
-- triggers).
--
-- Navigation, as in Blender's viewport (`navigation` on): drag to orbit
-- around the view's centre (`focusDistance` ahead), two fingers to pan,
-- pinch to zoom, double-tap to go back to the camera inputs. A host can map
-- its mouse to the rest: `navMode` 1 makes a drag pan (Shift), 2 zoom
-- (Ctrl); `zoom` scales the orbit distance (the wheel); changing
-- `resetView` resets the view; `dragX` / `dragY` (running totals, in
-- pixels) drag it as the pointer does, e.g. from a trackpad's two-finger
-- scroll. The inputs stay the camera's home.
--
-- Hills: `mountains` scales the distant ranges' height (0 hides them),
-- `mountainColor` is the nearest range's colour (the farther ones fade into
-- the haze).
--
-- Pollen: `pollenAmount` (motes, up to 3000), `pollenSize` (metres),
-- `pollenSpeed`, `petals` (the fraction that are tumbling petals),
-- `pollenColor`.
--
-- Place the node at the artboard's centre and set width/height to the
-- artboard's size.

export type Ruins = {
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
	sunAzimuth: Input<number>,
	sunElevation: Input<number>,
	sunIntensity: Input<number>,
	lightLeak: Input<number>,
	shafts: Input<number>,
	glory: Input<number>,
	navigation: Input<boolean>,
	navMode: Input<number>,
	zoom: Input<number>,
	resetView: Input<number>,
	dragX: Input<number>,
	dragY: Input<number>,
	windStrength: Input<number>,
	windSpeed: Input<number>,
	windDirection: Input<number>,
	gustiness: Input<number>,
	flutter: Input<number>,
	haze: Input<number>,
	clouds: Input<number>,
	bloom: Input<number>,
	glow: Input<number>,
	depthOfField: Input<number>,
	focusDistance: Input<number>,
	exposure: Input<number>,
	pollenAmount: Input<number>,
	pollenSize: Input<number>,
	pollenSpeed: Input<number>,
	petals: Input<number>,
	pollenColor: Input<Color>,
	flowerColor: Input<Color>,
	sunColor: Input<Color>,
	shadowColor: Input<Color>,
	skyColor: Input<Color>,
	skyMidColor: Input<Color>,
	mountains: Input<number>,
	mountainColor: Input<Color>,
	horizonColor: Input<Color>,
	hazeColor: Input<Color>,

	context: Context?,
	shader: Shader?,
	postShader: Shader?,
	blurShader: Shader?,
	failed: boolean,
	time: number,
	windPhase: number,
	draws: { Draw },
	shared: { Shared },
	visible: { Draw },
	camera: Camera,
	-- Navigation, on top of the camera inputs: orbit (degrees), pan (metres,
	-- moving the pivot) and zoom (times the orbit distance).
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
	skyUbo: GPUBuffer?,
	skyBindings: GPUBindGroup?,
	pollenUbo: GPUBuffer?,
	pollenBindings: GPUBindGroup?,
	pollenIds: GPUBuffer?,
	postUbo: GPUBuffer?,
	postBindings: GPUBindGroup?,
	nearBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	sceneCanvas: GPUCanvas?,
	outCanvas: GPUCanvas?,
	nearCanvas: GPUCanvas?,
	wideCanvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	staticPipeline: GPUPipeline?,
	instPipeline: GPUPipeline?,
	skyPipeline: GPUPipeline?,
	pollenPipeline: GPUPipeline?,
	staticShadowPipeline: GPUPipeline?,
	instShadowPipeline: GPUPipeline?,
	shadowTexture: GPUTexture?,
	shadowTarget: GPUTextureView?,
	shadowView: GPUTextureView?,
	shadowSampler: GPUSampler?,
	sunScreen: { number },
	postPipeline: GPUPipeline?,
	nearPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	sampler: GPUSampler?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	frame: buffer,
	postParams: buffer,
	drawSampler: ImageSampler,
}

-- An object from the animation: its track (position xyz, rotation xyzw,
-- scale xyz per sample) over [t0, t1] seconds, and its shape key's weight
-- over [w0, w1]. Outside a window it holds the first or last sample.
type Track = {
	data: buffer,
	offset: number,
	samples: number,
	t0: number,
	t1: number,
	weightOffset: number,
	weightSamples: number,
	w0: number,
	w1: number,
	rest: { number },
	-- Glows gold as it is restored (pillars as they re-form, fragments in
	-- flight).
	glows: boolean,
}

-- One per material (and pipeline), shared by every draw of it; an object
-- has its own, for its pose.
type Shared = {
	material: number,
	instanced: boolean,
	track: Track?,
	-- Set each frame for an object: whether it has any size at all.
	visible: boolean,
	uniforms: GPUBuffer,
	bindings: GPUBindGroup?,
	shadowBindings: GPUBindGroup?,
}

type Draw = {
	material: number,
	instanced: boolean,
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	instanceBuffer: GPUBuffer?,
	instanceCount: number,
	-- Shape key deltas (objects), or the shared zero buffer.
	morphBuffer: GPUBuffer?,
	shared: Shared,
	-- Instanced draws are one tile of the meadow: a bounding sphere, and how
	-- far away they are still drawn. Sort key, set each frame.
	cx: number,
	cy: number,
	cz: number,
	radius: number,
	maxDistance: number,
	depth: number,
}

-- The camera, as last set up, for culling.
type Camera = {
	x: number, y: number, z: number,
	fx: number, fy: number, fz: number,
	rx: number, ry: number, rz: number,
	ux: number, uy: number, uz: number,
	tanX: number, tanY: number,
}

local UNIFORM_SIZE = 560
local POST_SIZE = 96
-- The sun's shadow map: its size, and how much of the world it covers (a
-- square this many metres across, centred on the ruins).
local SHADOW_SIZE = 2048
local SHADOW_SPAN = 68
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local MAX_POLLEN = 3000
-- How far each instanced material is drawn (metres); past that the haze
-- and the ground's own colour carry it.
local MAX_DISTANCE: { [number]: number } = { [10] = 70, [11] = 200, [12] = 200, [13] = 32, [14] = 26, [15] = 120, [16] = 300, [21] = 40, [22] = 30 }
-- Leaves, blades and wind reach this far past their instance positions.
local TILE_MARGIN = 0.8

-- Blob section kinds (see tools/export_anim.py): 1-8 merged static meshes,
-- by material; 40 an object of the animation.
local STATIC_MATERIAL = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [7] = 7, [8] = 8 }
local OBJECT = 40
-- The RuinsToGlory animation's length: `glory` 1 is its end.
local DURATION = 10
local ENTRY = 192
-- Enough zeros to stand in for the shape key of any static chunk.
local MAX_VERTICES = 65536
local MORPH_STRIDE = 16
-- Instance kind -> material drawn (ruins.wgsl), template kind.
-- 30 bushes and 32 tree crowns are soft clumps, with leaves over them (35,
-- 36); 31 the ivy; 33 grass; 34 pink flowers; 37 sunflowers, 38 daisies.
local INSTANCE_MATERIAL = { [30] = 15, [31] = 11, [32] = 16, [33] = 13, [34] = 14, [35] = 10, [36] = 12, [37] = 21, [38] = 22 }

-- Colour ramps for the instanced kinds (linear): dark, mid, light.
-- Each plant's family of greens (linear): dark, mid, light. Jade ivy,
-- emerald bush leaves over deep forest-teal cores, olive-sage crowns and
-- warm chartreuse grass; ruins.wgsl drifts them all warmer or cooler.
local RAMPS: { [number]: { { number } } } = {
	[10] = { { 0.03, 0.14, 0.06 }, { 0.1, 0.34, 0.12 }, { 0.3, 0.55, 0.2 } },
	[11] = { { 0.02, 0.12, 0.07 }, { 0.07, 0.3, 0.16 }, { 0.24, 0.5, 0.3 } },
	[12] = { { 0.1, 0.18, 0.06 }, { 0.28, 0.4, 0.14 }, { 0.52, 0.6, 0.26 } },
	[13] = { { 0.07, 0.19, 0.03 }, { 0.24, 0.45, 0.08 }, { 0.5, 0.64, 0.16 } },
	[15] = { { 0.02, 0.1, 0.05 }, { 0.08, 0.26, 0.1 }, { 0.22, 0.44, 0.16 } },
	[16] = { { 0.06, 0.14, 0.05 }, { 0.2, 0.34, 0.12 }, { 0.44, 0.54, 0.22 } },
}

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
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

local function load(self: Ruins): boolean
	local context = self.context
	assert(context)
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`Ruins: no blob asset named '{self.asset}'`)
		return false
	end
	local data = blob.data
	if buffer.len(data) < 12 or buffer.readstring(data, 0, 4) ~= 'SHRN' then
		print('Ruins: the blob is not a ruins.bin')
		return false
	end
	local count = buffer.readu32(data, 8)
	local templates: { [number]: { vb: GPUBuffer, ib: GPUBuffer, indexCount: number } } = {}
	local sections = {}
	for i = 0, count - 1 do
		local o = 12 + i * ENTRY
		local function u32(word: number): number
			return buffer.readu32(data, o + word * 4)
		end
		local function f32(word: number): number
			return buffer.readf32(data, o + word * 4)
		end
		local lx, ly, lz, hx, hy, hz = f32(8), f32(9), f32(10), f32(11), f32(12), f32(13)
		local rest = table.create(10, 0)
		for k = 1, 10 do
			rest[k] = f32(23 + k)
		end
		table.insert(sections, {
			kind = u32(0),
			count = u32(1),
			indexCount = u32(2),
			vbOffset = u32(3),
			vbLength = u32(4),
			ibOffset = u32(5),
			ibLength = u32(6),
			material = u32(7),
			cx = (lx + hx) / 2,
			cy = (ly + hy) / 2,
			cz = (lz + hz) / 2,
			radius = math.sqrt((hx - lx) ^ 2 + (hy - ly) ^ 2 + (hz - lz) ^ 2) / 2 + TILE_MARGIN,
			morphOffset = u32(14),
			morphLength = u32(15),
			track = {
				data = data,
				offset = u32(16),
				samples = u32(17),
				t0 = f32(18),
				t1 = f32(19),
				weightOffset = u32(20),
				weightSamples = u32(21),
				w0 = f32(22),
				w1 = f32(23),
				rest = rest,
				glows = u32(34) == 1,
			},
		})
	end
	local function shared(material: number, instanced: boolean): Shared
		for _, sh in self.shared do
			if sh.material == material and sh.instanced == instanced and sh.track == nil then
				return sh
			end
		end
		local sh: Shared = {
			material = material,
			instanced = instanced,
			track = nil,
			visible = true,
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
			shadowBindings = nil,
		}
		table.insert(self.shared, sh)
		return sh
	end
	local function own(material: number, track: Track): Shared
		local sh: Shared = {
			material = material,
			instanced = false,
			track = track,
			visible = true,
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
			shadowBindings = nil,
		}
		table.insert(self.shared, sh)
		return sh
	end
	local zeros = GPUBuffer.new({
		size = MAX_VERTICES * MORPH_STRIDE,
		usage = 'vertex',
		data = buffer.create(MAX_VERTICES * MORPH_STRIDE),
		immutable = true,
	})
	for _, s in sections do
		if s.kind >= 20 and s.kind < 30 then
			templates[s.kind] = {
				vb = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				ib = slice(data, s.ibOffset, s.ibLength, 'index'),
				indexCount = s.indexCount,
			}
		end
	end
	for _, s in sections do
		local material = if s.kind == OBJECT then s.material else STATIC_MATERIAL[s.kind]
		if material then
			table.insert(self.draws, {
				material = material,
				instanced = false,
				vertexBuffer = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				indexBuffer = slice(data, s.ibOffset, s.ibLength, 'index'),
				indexCount = s.indexCount,
				instanceBuffer = nil,
				instanceCount = 0,
				morphBuffer = if s.morphLength > 0 then slice(data, s.morphOffset, s.morphLength, 'vertex') else zeros,
				shared = if s.kind == OBJECT then own(material, s.track) else shared(material, false),
				cx = 0,
				cy = 0,
				cz = 0,
				radius = math.huge,
				maxDistance = math.huge,
				depth = 0,
			})
		end
	end
	for _, s in sections do
		local material = INSTANCE_MATERIAL[s.kind]
		-- For instances, indexCount holds the template's kind.
		local template = templates[s.indexCount]
		if material and template and s.count > 0 then
			table.insert(self.draws, {
				material = material,
				instanced = true,
				vertexBuffer = template.vb,
				indexBuffer = template.ib,
				indexCount = template.indexCount,
				instanceBuffer = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				instanceCount = s.count,
				morphBuffer = nil,
				shared = shared(material, true),
				cx = s.cx,
				cy = s.cy,
				cz = s.cz,
				radius = s.radius,
				maxDistance = MAX_DISTANCE[material] or math.huge,
				depth = 0,
			})
		end
	end
	self.skyUbo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.pollenUbo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.postUbo = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform' })
	local ids = buffer.create(MAX_POLLEN * 4)
	for i = 0, MAX_POLLEN - 1 do
		buffer.writef32(ids, i * 4, i)
	end
	self.pollenIds = GPUBuffer.new({ size = MAX_POLLEN * 4, usage = 'vertex', data = ids, immutable = true })
	self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	local shadow = GPUTexture.new({ width = SHADOW_SIZE, height = SHADOW_SIZE, format = DEPTH_FORMAT, renderTarget = true, label = 'sun shadow' })
	self.shadowTexture = shadow
	self.shadowTarget = shadow:view()
	self.shadowView = shadow:view({ aspect = 'depth-only' })
	self.shadowSampler = GPUSampler.new({ min = 'linear', mag = 'linear', compare = 'less-equal', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	return #self.draws > 0
end

function init(self: Ruins, context: Context): boolean
	self.context = context
	self.shader = context:shader('ruins')
	self.postShader = context:shader('post')
	self.blurShader = context:shader('blur')
	if self.shader == nil or self.postShader == nil or self.blurShader == nil then
		print('Ruins: shaders "ruins", "blur" and "post" are needed')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('Ruins: setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

-- Set below, with the navigation.
local hostDrag: (self: Ruins, dx: number, dy: number) -> () = function() end

local function startReset(self: Ruins)
	self.navReset = 1
end

function advance(self: Ruins, seconds: number): boolean
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
	-- The wind's phase runs at its speed, so changing the speed never jumps.
	self.windPhase += dt * math.max(self.windSpeed, 0)
	return true
end

---------------------------------------------------------------------------
-- Targets and pipelines

local function ensureTargets(self: Ruins): boolean
	local context = self.context
	assert(context)
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(1, math.floor(self.width * res))
	local h = math.max(1, math.floor(self.height * res))
	local samples = if self.msaa >= 2 then 4 else 1
	if self.sceneCanvas and self.outCanvas and w == self.targetW and h == self.targetH and samples == self.targetSamples then
		return true
	end
	local scene = self.sceneCanvas
	if scene == nil then
		scene = context:gpuCanvas({ width = w, height = h })
		self.sceneCanvas = scene
	else
		scene:resize(w, h)
	end
	local out = self.outCanvas
	if out == nil then
		out = context:gpuCanvas({ width = w, height = h })
		self.outCanvas = out
	else
		out:resize(w, h)
	end
	-- The blurs: half and a quarter of the size.
	local nw, nh = math.max(1, w // 2), math.max(1, h // 2)
	local near = self.nearCanvas
	if near == nil then
		near = context:gpuCanvas({ width = nw, height = nh })
		self.nearCanvas = near
	else
		near:resize(nw, nh)
	end
	local ww, wh = math.max(1, w // 4), math.max(1, h // 4)
	local wide = self.wideCanvas
	if wide == nil then
		wide = context:gpuCanvas({ width = ww, height = wh })
		self.wideCanvas = wide
	else
		wide:resize(ww, wh)
	end
	assert(scene and out)
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = scene.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.staticPipeline == nil then
		local shader = self.shader
		local postShader = self.postShader
		assert(shader and postShader)
		local target: { ColorTarget } = { { format = scene.format } }
		local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
		self.skyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = { format = DEPTH_FORMAT, compare = 'always', write = false },
			sampleCount = samples,
		})
		self.staticPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_static' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {
				{
					stride = 20,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'snorm8x4', slot = 1, offset = 12 },
						{ format = 'unorm8x4', slot = 2, offset = 16 },
					},
				},
				{
					stride = MORPH_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 12 },
					},
				},
			},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.instPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {
				{
					stride = 28,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'float32x3', slot = 1, offset = 12 },
						{ format = 'float32', slot = 2, offset = 24 },
					},
				},
				{
					stride = 16,
					stepMode = 'instance',
					attributes = {
						{ format = 'float16x4', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 8 },
						{ format = 'snorm8x4', slot = 5, offset = 12 },
					},
				},
			},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.pollenPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_pollen' },
			fragment = { module = shader, entryPoint = 'fs_pollen' },
			vertexLayout = {
				{ stride = 4, stepMode = 'instance', attributes = { { format = 'float32', slot = 0, offset = 0 } } },
			},
			colorTargets = {
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
			},
			depthStencil = { format = DEPTH_FORMAT, compare = 'greater', write = false },
			sampleCount = samples,
		})
		-- The shadow pass: depth only, from the sun.
		local shadowDepth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'less', write = true }
		self.staticShadowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_static_shadow' },
			vertexLayout = {
				{
					stride = 20,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'snorm8x4', slot = 1, offset = 12 },
						{ format = 'unorm8x4', slot = 2, offset = 16 },
					},
				},
				{
					stride = MORPH_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 12 },
					},
				},
			},
			depthStencil = shadowDepth,
			cullMode = 'none',
		})
		self.instShadowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst_shadow' },
			vertexLayout = {
				{
					stride = 28,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'float32x3', slot = 1, offset = 12 },
						{ format = 'float32', slot = 2, offset = 24 },
					},
				},
				{
					stride = 16,
					stepMode = 'instance',
					attributes = {
						{ format = 'float16x4', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 8 },
						{ format = 'snorm8x4', slot = 5, offset = 12 },
					},
				},
			},
			depthStencil = shadowDepth,
			cullMode = 'none',
		})
		local blurShader = self.blurShader
		assert(blurShader)
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
		for _, sh in self.shared do
			sh.bindings = nil
			sh.shadowBindings = nil
		end
		self.skyBindings = nil
		self.pollenBindings = nil
	end
	-- The post pass reads the scene canvas, which has just been remade.
	self.postBindings = nil
	self.nearBindings = nil
	self.wideBindings = nil
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return true
end

---------------------------------------------------------------------------
-- Frame uniforms

local function frameUniforms(self: Ruins)
	local u = self.frame
	local t = self.time
	local drift = clamp(self.drift, 0, 2)
	-- The camera, with a slow floating sway.
	local ex = self.cameraX + math.sin(t * 0.13) * 0.08 * drift
	local ey = self.cameraY + math.sin(t * 0.17 + 1) * 0.04 * drift
	local ez = self.cameraZ + math.cos(t * 0.11) * 0.08 * drift
	local yaw = math.rad(self.rotationY + math.sin(t * 0.09) * 0.7 * drift)
	local pitch = math.rad(self.rotationX + math.sin(t * 0.12 + 2) * 0.35 * drift)
	local roll = math.rad(self.rotationZ + math.sin(t * 0.07) * 0.25 * drift)
	-- Navigation: orbit the eye about a pivot `focusDistance` ahead (moved
	-- by the pan), at that distance times the zoom.
	local cp = math.cos(pitch)
	local orbit = clamp(self.focusDistance, 2, 60)
	local px = ex - math.sin(yaw) * cp * orbit + self.navPanX
	local py = ey + math.sin(pitch) * orbit + self.navPanY
	local pz = ez - math.cos(yaw) * cp * orbit + self.navPanZ
	yaw += math.rad(self.navYaw)
	pitch = clamp(pitch + math.rad(self.navPitch), math.rad(-85), math.rad(85))
	cp = math.cos(pitch)
	local fx, fy, fz = -math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp
	local dist = orbit * self.navZoom * clamp(self.zoom, 0.05, 20)
	ex, ey, ez = px - fx * dist, py - fy * dist, pz - fz * dist
	-- Never under the meadow.
	ey = math.max(ey, 0.35)
	-- right = fwd x worldUp, up = right x fwd, then the roll.
	local rx, rz = -fz, fx
	local rl = math.max(math.sqrt(rx * rx + rz * rz), 1e-6)
	rx, rz = rx / rl, rz / rl
	local ry = 0
	local ux = ry * fz - rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy - ry * fx
	local cr, sr = math.cos(roll), math.sin(roll)
	local Rx, Ry, Rz = rx * cr + ux * sr, ry * cr + uy * sr, rz * cr + uz * sr
	local Ux, Uy, Uz = ux * cr - rx * sr, uy * cr - ry * sr, uz * cr - rz * sr

	local aspect = self.targetW / math.max(self.targetH, 1)
	local fovY = math.rad(clamp(self.fov, 10, 120))
	local tanY = math.tan(fovY / 2)
	local proj = Mat4.perspectiveReverseZ(fovY, aspect, 0.05)
	local view = Mat4.lookAt(Vector.xyz(ex, ey, ez), Vector.xyz(ex + fx, ey + fy, ez + fz), Vector.xyz(Ux, Uy, Uz))
	local viewProj = proj * view
	viewProj:writeToBuffer(u, 0)
	-- Glory: brighter sun, thinner haze, a warmer horizon, more pollen.
	local g = clamp(self.glory, 0, 1)
	g = g * g * (3 - 2 * g)
	write4(u, 64, ex, ey, ez, t)
	-- The sun: its compass direction (0 = +X, 90 = +Z) and height.
	local az = math.rad(self.sunAzimuth)
	local el = math.rad(clamp(self.sunElevation, -10, 90))
	write4(u, 80, math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el), math.max(self.sunIntensity, 0) * (1 + 0.2 * g))
	writeColor(u, 96, self.sunColor, 0.2)
	writeColor(u, 112, self.shadowColor, 0.08)
	writeColor(u, 128, self.skyColor, clamp(self.clouds, 0, 1))
	writeColor(u, 528, self.skyMidColor, math.max(self.mountains, 0))
	writeColor(u, 544, self.mountainColor, 1)
	do
		local hr, hg, hb = linear(self.horizonColor)
		write4(u, 144, hr + (1.0 - hr) * g * 0.5, hg + (0.78 - hg) * g * 0.5, hb + (0.55 - hb) * g * 0.5, math.max(self.haze, 0) * 0.014 * (1 - 0.35 * g))
	end
	writeColor(u, 160, self.hazeColor, 0.22)
	local wa = math.rad(self.windDirection)
	write4(u, 176, math.cos(wa), math.sin(wa), clamp(self.windStrength, 0, 3), clamp(self.gustiness, 0, 1))
	write4(u, 192, self.windPhase, clamp(self.flutter, 0, 3), self.windPhase * 0.03, 0)
	write4(u, 208, 0, 1, 0, 0)
	write4(u, 272, clamp(self.pollenAmount * (1 + 0.5 * g), 0, MAX_POLLEN), math.max(self.pollenSize, 0.001), math.max(self.pollenSpeed, 0), 1)
	writeColor(u, 288, self.pollenColor, 0.9)
	local cam = self.camera
	cam.x, cam.y, cam.z = ex, ey, ez
	cam.fx, cam.fy, cam.fz = fx, fy, fz
	cam.rx, cam.ry, cam.rz = Rx, Ry, Rz
	cam.ux, cam.uy, cam.uz = Ux, Uy, Uz
	cam.tanX, cam.tanY = tanY * aspect, tanY
	write4(u, 304, Rx, Ry, Rz, tanY * aspect)
	write4(u, 320, Ux, Uy, Uz, tanY)
	write4(u, 336, fx, fy, fz, math.max(self.focusDistance, 0.5))
	-- Pollen fills a box from the camera to beyond the ruins.
	write4(u, 352, -4, 0, 6, clamp(self.depthOfField, 0, 2) * 2.5)
	write4(u, 368, clamp(self.petals, 0, 1), math.max(self.pollenSize, 0.001) * 2.2, 0, 0)
	write4(u, 448, g, 0, 0, 0)
	-- The sun's view for the shadow map: orthographic, over the ruins.
	local sx, sy, sz = math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)
	local half = SHADOW_SPAN / 2
	local up = if math.abs(sy) > 0.97 then Vector.xyz(1, 0, 0) else Vector.xyz(0, 1, 0)
	local lightView = Mat4.lookAt(Vector.xyz(sx * 80, 1.5 + sy * 80, sz * 80), Vector.xyz(0, 1.5, 0), up)
	local lightViewProj = Mat4.ortho(-half, half, -half, half, 1, 170) * lightView
	lightViewProj:writeToBuffer(u, 464)
	-- Where the sun is on screen, for the light shafts and glow.
	local ahead = sx * fx + sy * fy + sz * fz
	local q = viewProj:transformPoint(ex + sx * 1000, ey + sy * 1000, ez + sz * 1000)
	local screen = self.sunScreen
	screen[1] = q.x * 0.5 + 0.5
	screen[2] = 0.5 - q.y * 0.5
	screen[3] = if ahead > 0.05 then 1 else 0
end

-- Where an object is at `time` seconds into the animation: its model matrix
-- goes into the uniforms, with its shape key's weight in mode.w. Returns
-- whether it has any size (a scale of 0 hides it).
local function writeTrack(u: buffer, track: Track, time: number): boolean
	local r = track.rest
	local px: number = r[1]
	local py: number = r[2]
	local pz: number = r[3]
	local qx: number = r[4]
	local qy: number = r[5]
	local qz: number = r[6]
	local qw: number = r[7]
	local sx: number = r[8]
	local sy: number = r[9]
	local sz: number = r[10]
	if track.samples > 0 then
		local d, o = track.data, track.offset
		local f = clamp((time - track.t0) / math.max(track.t1 - track.t0, 1e-6), 0, 1) * (track.samples - 1)
		local i = math.min(math.floor(f), track.samples - 2)
		if track.samples < 2 then
			i = 0
		end
		local k = if track.samples < 2 then 0 else f - i
		local a = o + i * 40
		local b = if track.samples < 2 then a else a + 40
		local function lerp(at: number): number
			local x = buffer.readf32(d, a + at)
			return x + (buffer.readf32(d, b + at) - x) * k
		end
		px = lerp(0)
		py = lerp(4)
		pz = lerp(8)
		qx = lerp(12)
		qy = lerp(16)
		qz = lerp(20)
		qw = lerp(24)
		sx = lerp(28)
		sy = lerp(32)
		sz = lerp(36)
		local l = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if l > 0 then
			qx /= l
			qy /= l
			qz /= l
			qw /= l
		end
	end
	local weight = 0
	if track.weightSamples > 0 then
		local f = clamp((time - track.w0) / math.max(track.w1 - track.w0, 1e-6), 0, 1) * (track.weightSamples - 1)
		local i = math.min(math.floor(f), math.max(track.weightSamples - 2, 0))
		local a = track.weightOffset + i * 4
		local x = buffer.readf32(track.data, a)
		local y = if track.weightSamples > 1 then buffer.readf32(track.data, a + 4) else x
		weight = x + (y - x) * (f - i)
	end
	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local wx, wy, wz = qw * qx, qw * qy, qw * qz
	write4(u, 384, (1 - 2 * (yy + zz)) * sx, (2 * (xy + wz)) * sx, (2 * (xz - wy)) * sx, 0)
	write4(u, 400, (2 * (xy - wz)) * sy, (1 - 2 * (xx + zz)) * sy, (2 * (yz + wx)) * sy, 0)
	write4(u, 416, (2 * (xz + wy)) * sz, (2 * (yz - wx)) * sz, (1 - 2 * (xx + yy)) * sz, 0)
	write4(u, 432, px, py, pz, 1)
	buffer.writef32(u, 220, weight)
	-- The glow (mode.z): rising as a pillar re-forms, then an afterglow
	-- that fades over a few seconds; a fragment glows in flight.
	local glow = 0
	if track.glows then
		if track.weightSamples > 0 then
			if time >= track.w0 then
				local fade = math.exp(-math.max(time - track.w1, 0) * 0.9)
				glow = math.sqrt(clamp(weight, 0, 1)) * fade
			end
		elseif track.samples > 0 then
			local f = clamp((time - track.t0) / math.max(track.t1 - track.t0, 1e-6), 0, 1)
			glow = math.sin(f * math.pi) ^ 0.7
		end
	end
	buffer.writef32(u, 216, glow)
	return math.abs(sx) + math.abs(sy) + math.abs(sz) > 1e-4
end

local function materialUniforms(self: Ruins, d: Shared)
	local u = self.frame
	-- How much light passes through: leaves more than grass.
	local through = if d.material == 13
		then 0.5
		elseif d.material >= 10 and d.material <= 18 then 1
		elseif d.material == 21 or d.material == 22 then 0.7
		else 0
	write4(u, 208, d.material, through, 0, 0)
	local track = d.track
	if track then
		d.visible = writeTrack(u, track, clamp(self.glory, 0, 1) * DURATION)
	else
		write4(u, 384, 1, 0, 0, 0)
		write4(u, 400, 0, 1, 0, 0)
		write4(u, 416, 0, 0, 1, 0)
		write4(u, 432, 0, 0, 0, 1)
	end
	local ramp = RAMPS[d.material]
	if d.material == 14 then
		write4(u, 224, 0.95, 0.94, 0.9, 1)
		writeColor(u, 240, self.flowerColor, 1)
		write4(u, 256, 1, 0.86, 0.45, 1)
	elseif ramp then
		write4(u, 224, ramp[1][1], ramp[1][2], ramp[1][3], 1)
		write4(u, 240, ramp[2][1], ramp[2][2], ramp[2][3], 1)
		write4(u, 256, ramp[3][1], ramp[3][2], ramp[3][3], 1)
	end
	d.uniforms:write(u)
end

-- Whether a tile's bounding sphere is in front of the camera, inside the
-- view and near enough; sets its depth for sorting.
local function inView(cam: Camera, d: Draw): boolean
	local dx, dy, dz = d.cx - cam.x, d.cy - cam.y, d.cz - cam.z
	local z = dx * cam.fx + dy * cam.fy + dz * cam.fz
	local r = d.radius
	if z < -r or z - r > d.maxDistance then
		return false
	end
	local x = dx * cam.rx + dy * cam.ry + dz * cam.rz
	local y = dx * cam.ux + dy * cam.uy + dz * cam.uz
	-- Distance from the sphere's centre to each side plane, along its normal.
	if math.abs(x) - z * cam.tanX > r * math.sqrt(1 + cam.tanX * cam.tanX) then
		return false
	end
	if math.abs(y) - z * cam.tanY > r * math.sqrt(1 + cam.tanY * cam.tanY) then
		return false
	end
	d.depth = z
	return true
end

local function byDepth(a: Draw, b: Draw): boolean
	return a.depth < b.depth
end

---------------------------------------------------------------------------
-- Render

local function render(self: Ruins): Image?
	if not ensureTargets(self) then
		return nil
	end
	local scene, out = self.sceneCanvas, self.outCanvas
	local depthView = self.depthView
	local skyPipeline, staticPipeline, instPipeline = self.skyPipeline, self.staticPipeline, self.instPipeline
	local pollenPipeline, postPipeline = self.pollenPipeline, self.postPipeline
	local skyUbo, pollenUbo, postUbo, sampler = self.skyUbo, self.pollenUbo, self.postUbo, self.sampler
	if not (scene and out and depthView and skyPipeline and staticPipeline and instPipeline and pollenPipeline and postPipeline) then
		return nil
	end
	if not (skyUbo and pollenUbo and postUbo and sampler) then
		return nil
	end

	frameUniforms(self)
	skyUbo:write(self.frame)
	pollenUbo:write(self.frame)
	local shadowView, shadowSampler, shadowTarget = self.shadowView, self.shadowSampler, self.shadowTarget
	local staticShadow, instShadow = self.staticShadowPipeline, self.instShadowPipeline
	if not (shadowView and shadowSampler and shadowTarget and staticShadow and instShadow) then
		return nil
	end
	local function withShadow(pipeline: GPUPipeline, ubo: GPUBuffer): GPUBindGroup
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 1, view = shadowView } },
			samplers = { { slot = 2, sampler = shadowSampler } },
		})
	end
	local function plain(pipeline: GPUPipeline, ubo: GPUBuffer): GPUBindGroup
		return GPUBindGroup.new({ layout = pipeline:getBindGroupLayout(0), ubos = { { slot = 0, buffer = ubo } } })
	end
	for _, sh in self.shared do
		materialUniforms(self, sh)
		if sh.bindings == nil then
			sh.bindings = withShadow(if sh.instanced then instPipeline else staticPipeline, sh.uniforms)
			sh.shadowBindings = plain(if sh.instanced then instShadow else staticShadow, sh.uniforms)
		end
	end
	-- The tiles of foliage in view, nearest first so the ones behind fail
	-- the depth test early.
	local visible = self.visible
	table.clear(visible)
	for _, d in self.draws do
		if d.instanced and inView(self.camera, d) then
			table.insert(visible, d)
		end
	end
	table.sort(visible, byDepth)
	if self.skyBindings == nil then
		local ok, b = pcall(plain, skyPipeline, skyUbo)
		self.skyBindings = if ok then b else withShadow(skyPipeline, skyUbo)
	end
	if self.pollenBindings == nil then
		local ok, b = pcall(plain, pollenPipeline, pollenUbo)
		self.pollenBindings = if ok then b else withShadow(pollenPipeline, pollenUbo)
	end

	-- The sun's shadow map: what blocks the sun (the stone, the objects, the
	-- bush and tree clumps; not the grass, flowers or leaf cards).
	local shadowPass = scene:beginRenderPass({
		depthStencil = { view = shadowTarget, depthLoadOp = 'clear', depthStoreOp = 'store', depthClearValue = 1 },
	})
	shadowPass:setPipeline(staticShadow)
	for _, d in self.draws do
		local b = d.shared.shadowBindings
		local morph = d.morphBuffer
		if not d.instanced and b and morph and d.shared.visible and d.material ~= 4 and d.material ~= 5 and d.material ~= 8 then
			shadowPass:setBindGroup(0, b)
			shadowPass:setVertexBuffer(0, d.vertexBuffer)
			shadowPass:setVertexBuffer(1, morph)
			shadowPass:setIndexBuffer(d.indexBuffer, 'uint16')
			shadowPass:drawIndexed(d.indexCount)
		end
	end
	shadowPass:setPipeline(instShadow)
	for _, d in self.draws do
		local b = d.shared.shadowBindings
		local instances = d.instanceBuffer
		if d.instanced and b and instances and (d.material == 15 or d.material == 16) then
			shadowPass:setBindGroup(0, b)
			shadowPass:setVertexBuffer(0, d.vertexBuffer)
			shadowPass:setVertexBuffer(1, instances)
			shadowPass:setIndexBuffer(d.indexBuffer, 'uint16')
			shadowPass:drawIndexed(d.indexCount, d.instanceCount)
		end
	end
	shadowPass:finish()

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = scene:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 1 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } }
	local pass = scene:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
	})
	local skyBindings = self.skyBindings
	assert(skyBindings)
	pass:setPipeline(skyPipeline)
	pass:setBindGroup(0, skyBindings)
	pass:draw(3)
	pass:setPipeline(staticPipeline)
	for _, d in self.draws do
		local bindings = d.shared.bindings
		local morph = d.morphBuffer
		if not d.instanced and bindings and morph and d.shared.visible then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, d.vertexBuffer)
			pass:setVertexBuffer(1, morph)
			pass:setIndexBuffer(d.indexBuffer, 'uint16')
			pass:drawIndexed(d.indexCount)
		end
	end
	pass:setPipeline(instPipeline)
	for _, d in visible do
		local bindings = d.shared.bindings
		local instances = d.instanceBuffer
		if bindings and instances then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, d.vertexBuffer)
			pass:setVertexBuffer(1, instances)
			pass:setIndexBuffer(d.indexBuffer, 'uint16')
			pass:drawIndexed(d.indexCount, d.instanceCount)
		end
	end
	local pollen = math.ceil(clamp(self.pollenAmount, 0, MAX_POLLEN))
	local pollenBindings = self.pollenBindings
	local pollenIds = self.pollenIds
	if pollen > 0 and pollenBindings and pollenIds then
		pass:setPipeline(pollenPipeline)
		pass:setBindGroup(0, pollenBindings)
		pass:setVertexBuffer(0, pollenIds)
		pass:draw(6, pollen)
	end
	pass:finish()

	-- The finish.
	local p = self.postParams
	write4(p, 0, 1 / self.targetW, 1 / self.targetH, self.targetW / self.targetH, self.time)
	write4(p, 16, math.max(self.bloom, 0), clamp(self.glow, 0, 1), clamp(self.depthOfField, 0, 1), math.max(self.exposure, 0))
	write4(p, 32, 1.04, 1.0, 0.96, 1.06)
	write4(p, 48, 0.35, 0.4, 0.8, 0.0045)
	local lr, lg, lb = linear(self.sunColor)
	write4(p, 64, lr, lg * 0.92, lb * 0.85, clamp(self.lightLeak + 0.3 * clamp(self.glory, 0, 1), 0, 1.5))
	local sun = self.sunScreen
	write4(p, 80, sun[1], sun[2], math.max(self.shafts, 0), sun[3])
	postUbo:write(p)
	local near, wide = self.nearCanvas, self.wideCanvas
	local nearPipeline, widePipeline = self.nearPipeline, self.widePipeline
	if not (near and wide and nearPipeline and widePipeline) then
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
local function pan(self: Ruins, dx: number, dy: number)
	local cam = self.camera
	local orbit = clamp(self.focusDistance, 2, 60) * self.navZoom * clamp(self.zoom, 0.05, 20)
	local perPx = 2 * orbit * cam.tanY / math.max(self.height, 1)
	self.navPanX += (-cam.rx * dx + cam.ux * dy) * perPx
	self.navPanY += (-cam.ry * dx + cam.uy * dy) * perPx
	self.navPanZ += (-cam.rz * dx + cam.uz * dy) * perPx
end

local function zoomBy(self: Ruins, factor: number)
	self.navZoom = clamp(self.navZoom * factor, 0.08, 6)
end

-- A one-pointer drag of (dx, dy) node pixels, by `navMode`: turntable orbit
-- (the scene turns with the pointer), pan or zoom.
local function applyDrag(self: Ruins, dx: number, dy: number)
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

local function pointerDown(self: Ruins, event: PointerEvent)
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

local function pointerMove(self: Ruins, event: PointerEvent)
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

local function pointerUp(self: Ruins, event: PointerEvent)
	if self.pointers[event.id] ~= nil then
		self.pointers[event.id] = nil
		self.pointerCount = math.max(self.pointerCount - 1, 0)
		event:hit()
	end
end

local function pointerExit(self: Ruins, event: PointerEvent)
	pointerUp(self, event)
end

function draw(self: Ruins, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('Ruins: render failed: ' .. tostring(result))
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

return function(): Node<Ruins>
	return {
		asset = 'ruins',
		width = 1280,
		height = 720,
		resolution = 1,
		msaa = 4,
		cameraX = -14,
		cameraY = 2,
		cameraZ = 17.5,
		rotationX = 2,
		rotationY = -38,
		rotationZ = 0,
		fov = 46,
		drift = 1,
		sunAzimuth = 15,
		sunElevation = 26,
		sunIntensity = 1,
		lightLeak = 0.35,
		shafts = 0.6,
		glory = 0,
		navigation = true,
		navMode = 0,
		zoom = 1,
		resetView = 0,
		dragX = 0,
		dragY = 0,
		windStrength = 1,
		windSpeed = 1,
		windDirection = 30,
		gustiness = 0.6,
		flutter = 1,
		haze = 0.45,
		clouds = 0.5,
		bloom = 0.7,
		glow = 0.18,
		depthOfField = 0.5,
		focusDistance = 18,
		exposure = 0.95,
		pollenAmount = 1400,
		pollenSize = 0.03,
		pollenSpeed = 1,
		petals = 0.12,
		pollenColor = Color.rgb(255, 120, 190),
		flowerColor = Color.rgb(255, 170, 200),
		sunColor = Color.rgb(255, 222, 170),
		shadowColor = Color.rgb(160, 148, 190),
		skyColor = Color.rgb(70, 128, 230),
		skyMidColor = Color.rgb(186, 160, 232),
		mountains = 1,
		mountainColor = Color.rgb(84, 92, 150),
		horizonColor = Color.rgb(255, 226, 170),
		hazeColor = Color.rgb(236, 214, 222),

		context = nil,
		shader = nil,
		postShader = nil,
		blurShader = nil,
		failed = false,
		time = 0,
		windPhase = 0,
		draws = {},
		shared = {},
		visible = {},
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
		skyUbo = nil,
		skyBindings = nil,
		pollenUbo = nil,
		pollenBindings = nil,
		pollenIds = nil,
		postUbo = nil,
		postBindings = nil,
		nearBindings = nil,
		wideBindings = nil,
		sceneCanvas = nil,
		outCanvas = nil,
		nearCanvas = nil,
		wideCanvas = nil,
		depthView = nil,
		msaaView = nil,
		staticPipeline = nil,
		instPipeline = nil,
		skyPipeline = nil,
		pollenPipeline = nil,
		staticShadowPipeline = nil,
		instShadowPipeline = nil,
		shadowTexture = nil,
		shadowTarget = nil,
		shadowView = nil,
		shadowSampler = nil,
		sunScreen = { 0.5, 0.5, 0, 0 },
		postPipeline = nil,
		nearPipeline = nil,
		widePipeline = nil,
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
