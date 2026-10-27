-- King Vikram: the hero of Vikram and Vetal, on his own, in the night
-- scene's visual language. The rigged, textured GLB (Vikram_King.glb)
-- drawn as a painting that happens to be 3D: flat toon bands of moonlight
-- and firelight, shadows painted in colour, a hard rim of moonlight, gold
-- that glints, ink outlines and ink lines from his painted texture, and
-- hatching in the deepest shadow. `paint` (0-1) is the 2D-3D mix.
--
-- Rendered in 3D on the GPU (king.wgsl), then finished like the scene
-- (blur.wgsl, post.wgsl). He himself is the Hero module (Hero.luau, shared
-- with the scene): the blob `asset` (king.bin, written by
-- ../tools/export_king.py) with the mesh, its texture set, his bow and his
-- three loops baked to skin matrices. This script draws his stage: the sky,
-- the ground, fireflies, the camera and the light.
--
-- Pose: `pose` (0 idle, 1 walking, 2 drawing his bow; he eases from one to
-- the next), `speed`. Walking is in place: the ground scrolls under him.
-- Drawing plays once (he raises the bow and draws the string) and then
-- holds at full draw, trembling, until the pose changes.
-- Bow: as the string draws, the bow's aura kindles, as the Pinaka's: a
-- breathing radiance, god rays, a halo along the arc, divine fire, sparks,
-- glints on the string, and gold light on him. `aura` (0-2) scales it,
-- `auraColor` colours it. `release` (0-1, over about 3 s) looses the
-- string: it snaps home and shivers, and rings of gold ripple out.
-- View: `turn` (degrees, he turns on the spot), `autoTurn` (degrees a
-- second), `tilt` (the camera's, degrees), `zoom`. Drag to turn him and
-- tilt the view, pinch to zoom, double-tap to reset; a host maps `dragX` /
-- `dragY` and `resetView`.
-- Light: `moon` (0-1) and `moonColor`, from above and behind him, casting
-- his shadow; `fire` (0-1) and `fireColor`, a pyre's flickering glow from
-- in front, low.
-- Eyes: `eyes` (0-1) brings them out of the brow's shadow; `blink` (0
-- open, 1 shut) is keyed by the Blink layer of the state machine.
-- Style: `paint`, `bands` (how many tones), `outline` (ink width, pixels),
-- `inkColor`, `inkDetail` (lines from the texture), `hatching`, `rim`.
-- Air: `fireflies` (0-200), `fireflySize`, `fireflyColor`, `mist`,
-- `bloom`, `glow`, `depthOfField`, `exposure`, `grain`.
--
-- Place the node at the artboard's centre and set width/height to the
-- artboard's size.

local Hero = require('Hero')

export type King = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	turn: Input<number>,
	autoTurn: Input<number>,
	tilt: Input<number>,
	zoom: Input<number>,
	pose: Input<number>,
	aura: Input<number>,
	auraColor: Input<Color>,
	release: Input<number>,
	speed: Input<number>,
	moon: Input<number>,
	moonColor: Input<Color>,
	fire: Input<number>,
	fireColor: Input<Color>,
	paint: Input<number>,
	bands: Input<number>,
	outline: Input<number>,
	inkColor: Input<Color>,
	inkDetail: Input<number>,
	hatching: Input<number>,
	rim: Input<number>,
	shadowColor: Input<Color>,
	skyColor: Input<Color>,
	horizonColor: Input<Color>,
	hazeColor: Input<Color>,
	fireflies: Input<number>,
	fireflySize: Input<number>,
	fireflyColor: Input<Color>,
	mist: Input<number>,
	bloom: Input<number>,
	glow: Input<number>,
	depthOfField: Input<number>,
	exposure: Input<number>,
	grain: Input<number>,
	eyes: Input<number>,
	blink: Input<number>,
	earringGlow: Input<number>,
	earringColor: Input<Color>,
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
	hero: Hero.Hero?,
	settings: Hero.Settings,
	-- Where the ground has scrolled to (metres), and his turn so far.
	scrollX: number,
	scrollZ: number,
	spin: number,
	-- Navigation on top of the inputs: turn and tilt (degrees), zoom.
	navTurn: number,
	navTilt: number,
	navZoom: number,
	navReset: number,
	lastResetView: number,
	lastDragX: number,
	lastDragY: number,
	pointers: { [number]: Vector },
	pointerCount: number,
	lastTapTime: number,
	lastTapPosition: Vector,
	tapMoved: number,
	ubo: GPUBuffer?,
	postUbo: GPUBuffer?,
	groundBindings: GPUBindGroup?,
	skyBindings: GPUBindGroup?,
	moteBindings: GPUBindGroup?,
	-- The fireflies' ids, one per instance.
	moteIds: GPUBuffer?,
	postBindings: GPUBindGroup?,
	nearBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	sceneCanvas: GPUCanvas?,
	outCanvas: GPUCanvas?,
	nearCanvas: GPUCanvas?,
	wideCanvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	groundPipeline: GPUPipeline?,
	skyPipeline: GPUPipeline?,
	motePipeline: GPUPipeline?,
	postPipeline: GPUPipeline?,
	nearPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	shadowTarget: GPUTextureView?,
	shadowView: GPUTextureView?,
	shadowSampler: GPUSampler?,
	sampler: GPUSampler?,
	moonScreen: { number },
	targetW: number,
	targetH: number,
	targetSamples: number,
	frame: buffer,
	postParams: buffer,
	drawSampler: ImageSampler,
}

local UNIFORM_SIZE = Hero.UNIFORM_SIZE
local POST_SIZE = 96
local SHADOW_SIZE = 1024
local SHADOW_SPAN = 7
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local MAX_FIREFLIES = 200
-- His walk covers this much ground a second (at speed 1), so his planted
-- foot holds still on the scrolling earth.
local WALK_PACE = 0.85
-- The camera looks at his middle from this far (times the zoom); zoomed
-- in, it rises to his face.
local TARGET_Y = 1.02
-- Drawing the bow he turns side-on; the view turns with him this much
-- (degrees) to see the bow broadside, his face over his shoulder.
local DRAW_TURN = 50
local DISTANCE = 5.4
local FOV = 30

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

local function load(self: King): boolean
	local context = self.context
	assert(context)
	local hero, err = Hero.load(context, self.asset)
	if hero == nil then
		print('King: ' .. tostring(err))
		return false
	end
	self.hero = hero
	local ids = buffer.create(MAX_FIREFLIES * 4)
	for i = 0, MAX_FIREFLIES - 1 do
		buffer.writef32(ids, i * 4, i)
	end
	self.moteIds = GPUBuffer.new({ size = MAX_FIREFLIES * 4, usage = 'vertex', data = ids, immutable = true })
	self.ubo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.postUbo = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform' })
	self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	local shadow = GPUTexture.new({ width = SHADOW_SIZE, height = SHADOW_SIZE, format = DEPTH_FORMAT, renderTarget = true, label = 'moon shadow' })
	self.shadowTarget = shadow:view()
	self.shadowView = shadow:view({ aspect = 'depth-only' })
	self.shadowSampler = GPUSampler.new({ min = 'linear', mag = 'linear', compare = 'less-equal', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	return true
end

function init(self: King, context: Context): boolean
	self.context = context
	self.shader = context:shader('king')
	self.postShader = context:shader('post')
	self.blurShader = context:shader('blur')
	if self.shader == nil or self.postShader == nil or self.blurShader == nil then
		print('King: shaders "king", "blur" and "post" are needed')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('King: setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

---------------------------------------------------------------------------
-- Time

local function startReset(self: King)
	self.navReset = 1
end

function advance(self: King, seconds: number): boolean
	if self.resetView ~= self.lastResetView then
		self.lastResetView = self.resetView
		startReset(self)
	end
	local dx, dy = self.dragX - self.lastDragX, self.dragY - self.lastDragY
	if dx ~= 0 or dy ~= 0 then
		self.lastDragX, self.lastDragY = self.dragX, self.dragY
		if self.navigation then
			self.navReset = 0
			self.navTurn += dx * 0.4
			self.navTilt = clamp(self.navTilt + dy * 0.2, -30, 40)
		end
	end
	local dt = math.min(seconds, 0.1)
	if self.navReset > 0 then
		local k = 1 - math.exp(-dt * 9)
		self.navTurn -= self.navTurn * k
		self.navTilt -= self.navTilt * k
		self.navZoom += (1 - self.navZoom) * k
		self.spin -= self.spin * k
		self.navReset = math.max(self.navReset - seconds * 1.5, 0)
		if self.navReset == 0 then
			self.navTurn, self.navTilt, self.navZoom, self.spin = 0, 0, 1, 0
		end
	end
	self.time += dt
	local hero = self.hero
	if hero then
		Hero.advance(hero, dt, self.pose, self.speed)
		self.spin += dt * self.autoTurn
		-- The ground scrolls the way he faces, at his pace.
		local facing = math.rad(self.turn + self.navTurn + self.spin + DRAW_TURN * Hero.mix(hero, 2))
		local pace = WALK_PACE * clamp(self.speed, 0, 3) * Hero.mix(hero, 1) * dt
		self.scrollX += math.sin(facing) * pace
		self.scrollZ += math.cos(facing) * pace
	end
	return true
end

---------------------------------------------------------------------------
-- Targets and pipelines

local function ensureTargets(self: King): boolean
	local context = self.context
	local hero = self.hero
	assert(context and hero)
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
	if samples ~= self.targetSamples or self.groundPipeline == nil then
		local shader = self.shader
		local postShader = self.postShader
		local blurShader = self.blurShader
		assert(shader and postShader and blurShader)
		local target: { ColorTarget } = { { format = scene.format } }
		local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
		Hero.pipelines(hero, shader, scene.format, samples)
		self.skyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = { format = DEPTH_FORMAT, compare = 'always', write = false },
			sampleCount = samples,
		})
		self.groundPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_ground' },
			fragment = { module = shader, entryPoint = 'fs_ground' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.motePipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_motes' },
			fragment = { module = shader, entryPoint = 'fs_motes' },
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
		self.groundBindings = nil
		self.skyBindings = nil
		self.moteBindings = nil
	end
	self.postBindings = nil
	self.nearBindings = nil
	self.wideBindings = nil
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return true
end

---------------------------------------------------------------------------
-- Frame uniforms

local function frameUniforms(self: King, hero: Hero.Hero)
	local u = self.frame
	local t = self.time
	-- The camera: in front of him (+Z), looking at his chest, tilted.
	-- Drawing, the view swings round to see the bow broadside and steps
	-- back to fit it.
	local drawing = Hero.mix(hero, 2)
	local zoom = clamp(self.zoom, 0.2, 4) * self.navZoom * (1 + 0.18 * drawing)
	local dist = DISTANCE * zoom
	local pitch = math.rad(clamp(self.tilt + self.navTilt, -30, 60))
	local tx, ty, tz = 0, TARGET_Y + (1 - math.min(zoom, 1)) * 1.1 + 0.18 * drawing, 0
	local ex, ey, ez = tx, ty + math.sin(pitch) * dist, tz + math.cos(pitch) * dist
	local fx, fy, fz = normalize3(tx - ex, ty - ey, tz - ez)
	local rx, rz = -fz, fx
	local rl = math.max(math.sqrt(rx * rx + rz * rz), 1e-6)
	rx, rz = rx / rl, rz / rl
	local ux = -rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy
	local aspect = self.targetW / math.max(self.targetH, 1)
	local fovY = math.rad(FOV)
	local tanY = math.tan(fovY / 2)
	local proj = Mat4.perspectiveReverseZ(fovY, aspect, 0.05)
	local view = Mat4.lookAt(Vector.xyz(ex, ey, ez), Vector.xyz(tx, ty, tz), Vector.xyz(0, 1, 0))
	local viewProj = proj * view
	viewProj:writeToBuffer(u, 0)
	write4(u, 128, ex, ey, ez, t)

	-- The moon: up, behind him and to his left (screen right), for a rim.
	local moon = clamp(self.moon, 0, 1)
	local mx, my, mz = normalize3(0.62, 0.72, -0.5)
	write4(u, 144, mx, my, mz, 0.02 + 1.6 * moon)
	writeColor(u, 160, self.moonColor, 1, math.max(self.rim, 0) * (0.15 + 0.85 * math.min(moon / 0.3, 1)))
	-- The fire: low, in front and to his right, flickering.
	local flicker = 0.82 + 0.1 * math.sin(t * 7.3) + 0.06 * math.sin(t * 13.1 + 1.3) + 0.04 * math.sin(t * 23.7)
	local fdx, fdy, fdz = normalize3(-0.75, 0.32, 0.6)
	write4(u, 176, fdx, fdy, fdz, clamp(self.fire, 0, 1) * 0.75 * flicker)
	writeColor(u, 192, self.fireColor, 1, 0)
	-- Shadow is painted in a deep indigo; a little more of it when the moon
	-- is up.
	writeColor(u, 208, self.shadowColor, 1, 0.4 + 0.4 * math.min(moon / 0.3, 1))
	write4(u, 256, self.targetW, self.targetH, 1 / self.targetW, 1 / self.targetH)
	local lit = 0.25 + 0.75 * math.min(moon / 0.3, 1)
	writeColor(u, 272, self.skyColor, lit, 1)
	writeColor(u, 288, self.horizonColor, lit, moon)
	writeColor(u, 304, self.hazeColor, lit, math.max(self.mist, 0))
	write4(u, 384, rx, 0, rz, tanY * aspect)
	write4(u, 400, ux, uy, uz, tanY)
	write4(u, 416, fx, fy, fz, dist)
	write4(u, 432, clamp(self.fireflies, 0, MAX_FIREFLIES), math.max(self.fireflySize, 0.001), clamp(self.depthOfField, 0, 1), 0)
	writeColor(u, 448, self.fireflyColor, 1, 0)
	write4(u, 464, self.scrollX, self.scrollZ, 0, 0)

	-- Him: where he stands (the origin, turned), his eyes, earrings and bow.
	local s = self.settings
	s.x, s.y, s.z = 0, 0, 0
	s.turn = self.turn + self.navTurn + self.spin + DRAW_TURN * drawing
	s.eyes, s.blink = self.eyes, self.blink
	s.earringGlow, s.earringColor = self.earringGlow, self.earringColor
	s.aura, s.auraColor, s.release = self.aura, self.auraColor, self.release
	s.paint, s.bands, s.inkDetail, s.hatching = self.paint, self.bands, self.inkDetail, self.hatching
	s.outline = clamp(self.outline, 0, 8) * clamp(self.resolution, 0.25, 3) / math.max(zoom, 0.5)
	s.inkColor = self.inkColor
	s.time = t
	Hero.write(hero, u, s)

	-- The moon's view, for his shadow: orthographic, round him.
	local half = SHADOW_SPAN / 2
	local lightView = Mat4.lookAt(Vector.xyz(mx * 12, 1 + my * 12, mz * 12), Vector.xyz(0, 1, 0), Vector.xyz(0, 1, 0))
	local lightViewProj = Mat4.ortho(-half, half, -half, half, 1, 30) * lightView
	lightViewProj:writeToBuffer(u, 64)
	-- Where the moon is on screen, for its glow.
	local q = viewProj:transformPoint(ex + mx * 1000, ey + my * 1000, ez + mz * 1000)
	local screen = self.moonScreen
	screen[1] = q.x * 0.5 + 0.5
	screen[2] = 0.5 - q.y * 0.5
	screen[3] = if mx * fx + my * fy + mz * fz > 0.05 then 1 else 0
end

---------------------------------------------------------------------------
-- Render

-- The stage's bindings (sky, ground, fireflies): only what each uses, or,
-- on runtimes that list every binding in the module, the full set.
local function bindings(self: King, pipeline: GPUPipeline, ubo: GPUBuffer, useShadow: boolean): GPUBindGroup
	local hero = self.hero
	assert(hero)
	local function make(full: boolean): GPUBindGroup
		local entries: { TextureEntry } = {}
		local samplers: { SamplerEntry } = {}
		if useShadow or full then
			table.insert(entries, { slot = 1, view = self.shadowView :: GPUTextureView })
			table.insert(samplers, { slot = 2, sampler = self.shadowSampler :: GPUSampler })
		end
		if full then
			for i, v in hero.placeholderViews do
				table.insert(entries, { slot = 2 + i, view = v })
			end
			table.insert(samplers, { slot = 6, sampler = hero.textureSampler })
		end
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = entries,
			samplers = samplers,
		})
	end
	local ok, group = pcall(make, false)
	if ok then
		return group
	end
	return make(true)
end

local function render(self: King): Image?
	local hero = self.hero
	if hero == nil or not ensureTargets(self) then
		return nil
	end
	local scene, out = self.sceneCanvas, self.outCanvas
	local depthView, ubo, postUbo, sampler = self.depthView, self.ubo, self.postUbo, self.sampler
	local groundP, skyP, moteP, postP = self.groundPipeline, self.skyPipeline, self.motePipeline, self.postPipeline
	local shadowView, shadowSampler, shadowTarget = self.shadowView, self.shadowSampler, self.shadowTarget
	if not (scene and out and depthView and ubo and postUbo and sampler) then
		return nil
	end
	if not (groundP and skyP and moteP and postP and shadowView and shadowSampler and shadowTarget) then
		return nil
	end
	frameUniforms(self, hero)
	ubo:write(self.frame)
	if self.groundBindings == nil then
		self.groundBindings = bindings(self, groundP, ubo, true)
		self.skyBindings = bindings(self, skyP, ubo, false)
		self.moteBindings = bindings(self, moteP, ubo, false)
	end

	-- His shadow, from the moon.
	local shadowPass = scene:beginRenderPass({
		depthStencil = { view = shadowTarget, depthLoadOp = 'clear', depthStoreOp = 'store', depthClearValue = 1 },
	})
	Hero.drawShadow(hero, shadowPass, ubo, shadowView, shadowSampler)
	shadowPass:finish()

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = scene:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 1 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } }
	local pass = scene:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
	})
	local skyB, groundB, moteB = self.skyBindings, self.groundBindings, self.moteBindings
	assert(skyB and groundB and moteB)
	pass:setPipeline(skyP)
	pass:setBindGroup(0, skyB)
	pass:draw(3)
	pass:setPipeline(groundP)
	pass:setBindGroup(0, groundB)
	pass:draw(6)
	local motes = math.ceil(clamp(self.fireflies, 0, MAX_FIREFLIES))
	local moteIds = self.moteIds
	if motes > 0 and moteIds then
		pass:setPipeline(moteP)
		pass:setBindGroup(0, moteB)
		pass:setVertexBuffer(0, moteIds)
		pass:draw(6, motes)
	end
	Hero.draw(hero, pass, ubo, shadowView, shadowSampler, self.outline > 0)
	pass:finish()

	-- The finish, as the scene's.
	local p = self.postParams
	write4(p, 0, 1 / self.targetW, 1 / self.targetH, self.targetW / self.targetH, self.time)
	write4(p, 16, math.max(self.bloom, 0), clamp(self.glow, 0, 1), clamp(self.depthOfField, 0, 1), math.max(self.exposure, 0))
	write4(p, 32, 0.95, 1.0, 1.07, 1.04)
	write4(p, 48, 0.35, clamp(self.grain, 0, 1), 0.8, 0.0045)
	local lr, lg, lb = linear(self.moonColor)
	write4(p, 64, lr, lg * 0.92, lb * 0.85, 0.12 * math.min(clamp(self.moon, 0, 1) / 0.3, 1))
	local m = self.moonScreen
	write4(p, 80, m[1], m[2], 0, 0)
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
-- Navigation: drag turns him (and tilts the view), pinch zooms.

local function pointerDown(self: King, event: PointerEvent)
	if not self.navigation then
		return
	end
	if self.pointers[event.id] == nil then
		self.pointerCount += 1
	end
	self.pointers[event.id] = event.position
	self.navReset = 0
	if self.pointerCount == 1 then
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

local function pointerMove(self: King, event: PointerEvent)
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
				self.navZoom = clamp(self.navZoom * before / after, 0.3, 2.5)
			end
		end
	else
		self.navTurn += d.x * 0.4
		self.navTilt = clamp(self.navTilt + d.y * 0.2, -30, 40)
	end
	self.pointers[event.id] = event.position
	event:hit()
end

local function pointerUp(self: King, event: PointerEvent)
	if self.pointers[event.id] ~= nil then
		self.pointers[event.id] = nil
		self.pointerCount = math.max(self.pointerCount - 1, 0)
		event:hit()
	end
end

local function pointerExit(self: King, event: PointerEvent)
	pointerUp(self, event)
end

function draw(self: King, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('King: render failed: ' .. tostring(result))
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

return function(): Node<King>
	return {
		asset = 'king',
		width = 1280,
		height = 720,
		resolution = 1,
		msaa = 4,
		turn = 18,
		autoTurn = 0,
		tilt = 6,
		zoom = 1,
		pose = 0,
		aura = 1,
		auraColor = Color.rgb(255, 190, 90),
		release = 0,
		speed = 1,
		moon = 0.45,
		moonColor = Color.rgb(150, 175, 245),
		fire = 0.6,
		fireColor = Color.rgb(255, 170, 95),
		paint = 0.75,
		bands = 3,
		outline = 2.2,
		inkColor = Color.rgb(16, 10, 24),
		inkDetail = 0.6,
		hatching = 0.5,
		rim = 1,
		shadowColor = Color.rgb(70, 60, 130),
		skyColor = Color.rgb(3, 5, 14),
		horizonColor = Color.rgb(24, 34, 62),
		hazeColor = Color.rgb(34, 46, 76),
		fireflies = 40,
		fireflySize = 0.025,
		fireflyColor = Color.rgb(210, 255, 120),
		mist = 1,
		bloom = 0.8,
		glow = 0.2,
		depthOfField = 0.4,
		exposure = 1.25,
		grain = 0.1,
		eyes = 1,
		blink = 0,
		earringGlow = 1,
		earringColor = Color.rgb(255, 176, 70),
		navigation = true,
		resetView = 0,
		dragX = 0,
		dragY = 0,

		context = nil,
		hero = nil,
		settings = {
			x = 0,
			y = 0,
			z = 0,
			turn = 0,
			eyes = 1,
			blink = 0,
			earringGlow = 1,
			earringColor = Color.rgb(255, 176, 70),
			aura = 1,
			auraColor = Color.rgb(255, 190, 90),
			release = 0,
			paint = 0.75,
			bands = 3,
			outline = 2.2,
			inkColor = Color.rgb(16, 10, 24),
			inkDetail = 0.6,
			hatching = 0.5,
			time = 0,
		},
		shader = nil,
		postShader = nil,
		blurShader = nil,
		failed = false,
		time = 0,
		scrollX = 0,
		scrollZ = 0,
		spin = 0,
		navTurn = 0,
		navTilt = 0,
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
		ubo = nil,
		postUbo = nil,
		groundBindings = nil,
		skyBindings = nil,
		moteBindings = nil,
		moteIds = nil,
		postBindings = nil,
		nearBindings = nil,
		wideBindings = nil,
		sceneCanvas = nil,
		outCanvas = nil,
		nearCanvas = nil,
		wideCanvas = nil,
		depthView = nil,
		msaaView = nil,
		groundPipeline = nil,
		skyPipeline = nil,
		motePipeline = nil,
		postPipeline = nil,
		nearPipeline = nil,
		widePipeline = nil,
		shadowTarget = nil,
		shadowView = nil,
		shadowSampler = nil,
		sampler = nil,
		moonScreen = { 0.5, 0.5, 0 },
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
