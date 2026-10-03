-- Node script: the Ten Rings.
--
-- Loads the ring from a GLB (via GLB.luau). In the file one ring is three
-- nested meshes sharing a transform (outer band, engraved band, decorated
-- band); every ring here draws all three, so each of the ten is the complete
-- ring. One GPU pass with a shared depth buffer, so rings that pass through
-- each other intersect correctly.
-- Shading is ring.wgsl: bronze metal whose carved artwork glows in
-- `imprintColor`. The carving is relief in the mesh, so at load time each
-- vertex gets a "cavity" value (how deep it sits below its neighbours, per
-- unit of edge length) stored in the vertex's uv.x; the shader lights
-- cavities between `cavityLow` and `cavityHigh`. Soft waves of energy in
-- `energyColor` flow around each ring (the aura).
--
-- The state machine keys three numbers and the script blends between poses:
--
--   formation  0 = orbit: rings drift around a tilted halo
--              1 = circle: rings shrink into a slowly turning circle
--   launch     0..1 throws the stack outward in a fan (Unleash)
--   power      0..1 energy: rim glow, emissive, halo glow, spin speed
--   intro      0..1 rings arrive from the dark, one after another
--   rest       1 = rings sit on two forearms (the default, before awakening)
--   dive       0..1 pushes every ring deep into the screen
--   flight     0..1 Awaken: rings fly off the forearms along curves into orbit
--   charge     0..1 Unleash: the circle collapses into a tight, interlocked,
--              fast-spinning cluster
--   shake      0..1 Unleash: the cluster trembles before it explodes
--
-- The pointer tilts the whole formation (never claims the event).
-- Place the node at the centre of the artboard; it draws `width` x `height`.

local GLB = require('GLB')

export type TenRings = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	formation: Input<number>,
	launch: Input<number>,
	power: Input<number>,
	intro: Input<number>,
	rest: Input<number>,
	dive: Input<number>,
	flight: Input<number>,
	charge: Input<number>,
	shake: Input<number>,
	-- External follow target (e.g. a tracked hand), 0..1 across and down the
	-- node's width/height. While `followActive`, it drives the Orbit chain
	-- exactly like the pointer does.
	followX: Input<number>,
	followY: Input<number>,
	followActive: Input<boolean>,
	energyColor: Input<Color>,
	imprintColor: Input<Color>,
	imprintGlow: Input<number>,
	cavityLow: Input<number>,
	cavityHigh: Input<number>,
	aura: Input<number>,
	metalColor: Input<Color>,
	metallic: Input<number>,
	roughness: Input<number>,
	tiltAmount: Input<number>,

	context: Context?,
	failed: boolean,
	time: number,
	turn: number, -- rotation of the summoned circle
	tumble: number, -- flip angle of the rings in the circle
	spins: { number },
	tiltX: number,
	tiltY: number,
	pointerX: number,
	pointerY: number,
	pointerOn: boolean,
	-- Cursor follow (Orbit only): the rings chain along the cursor's path.
	follow: number, -- 0 = normal orbit, 1 = fully following
	lastMove: number, -- time of the last pointer move
	cursorX: number, -- cursor on the z = 0 plane, in world units
	cursorY: number,
	leaderX: number, -- the chain's head, easing after the cursor
	leaderY: number,
	trailX: { number }, -- the path the head has drawn, oldest first
	trailY: { number },

	shader: Shader?,
	pipeline: GPUPipeline?,
	canvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	sampler: GPUSampler?,
	whiteView: GPUTextureView?,
	shapes: { Shape },
	ringRadius: number, -- outer radius of the assembled ring
	rings: { Ring },
	scratch: buffer,
	drawSampler: ImageSampler,
	glowPaint: Paint,
	auraPaint: Paint,
}

type Shape = {
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	center: { number },
	radius: number, -- ring radius in the mesh's own units
}

type Ring = {
	uniforms: GPUBuffer,
	bindings: GPUBindGroup?,
	screen: Vector, -- projected centre, for the glow
	screenRadius: number,
	depth: number,
	mvp: Mat4,
}

local COUNT = 10
local UNIFORM_SIZE = 256
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local FOV = math.rad(30)
local CAMERA_Z = 10
-- The whole formation sits a little below centre, clear of a page title.
local LIFT = -0.38

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function easeOutBack(t: number): number
	t = clamp(t, 0, 1)
	local c = 1.4
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function linear(c: Color): (number, number, number)
	local function lin(v: number): number
		return (v / 255) ^ 2.2
	end
	return lin(Color.red(c) :: number), lin(Color.green(c) :: number), lin(Color.blue(c) :: number)
end

local function normalize(x: number, y: number, z: number): (number, number, number)
	local l = math.sqrt(x * x + y * y + z * z)
	if l < 1e-9 then
		return 0, 0, 1
	end
	return x / l, y / l, z / l
end

local function cross(ax: number, ay: number, az: number, bx: number, by: number, bz: number): (number, number, number)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

-- A matrix that maps the ring's own axis (+Z) onto `axis`, spun `spin`
-- radians about that axis, scaled by `s` and moved to (px, py, pz).
local function orient(px: number, py: number, pz: number, ax: number, ay: number, az: number, spin: number, s: number): Mat4
	ax, ay, az = normalize(ax, ay, az)
	-- Any vector not parallel to the axis gives the first basis vector.
	local ux, uy, uz = 0, 1, 0
	if math.abs(ay) > 0.95 then
		ux, uy, uz = 1, 0, 0
	end
	local xx, xy, xz = normalize(cross(ux, uy, uz, ax, ay, az))
	local yx, yy, yz = cross(ax, ay, az, xx, xy, xz)
	local c, sn = math.cos(spin), math.sin(spin)
	local bx, by, bz = xx * c + yx * sn, xy * c + yy * sn, xz * c + yz * sn
	local cx, cy, cz = yx * c - xx * sn, yy * c - xy * sn, yz * c - xz * sn
	return Mat4.values(bx * s, by * s, bz * s, 0, cx * s, cy * s, cz * s, 0, ax * s, ay * s, az * s, 0, px, py, pz, 1)
end

-- ---------------------------------------------------------------------------
-- Poses
-- ---------------------------------------------------------------------------

-- Per-ring constants: shape, size and a little personality.
local SIZE = { 0.66, 0.62, 0.68, 0.6, 0.64, 0.66, 0.62, 0.68, 0.6, 0.64 }
local PHASE = {}
for i = 1, COUNT do
	PHASE[i] = (i * 2.399963) % (math.pi * 2) -- golden angle
end

type Pose = { x: number, y: number, z: number, ax: number, ay: number, az: number, s: number }

-- `turn` is the shared rotation of the halo (and of the summoned circle).
local function orbitPose(i: number, t: number, turn: number): Pose
	local theta = (i - 1) / COUNT * math.pi * 2 + turn
	local tilt = math.rad(32)
	local rx, rz = 3.6, 2.3
	local x = math.cos(theta) * rx
	local zFlat = math.sin(theta) * rz
	local bob = math.sin(t * 0.9 + PHASE[i]) * 0.12
	local y = 0.05 + zFlat * math.sin(tilt) + bob
	local z = zFlat * math.cos(tilt)
	-- Each ring leans its face toward the halo's centre and up a little.
	local ax, ay, az = -math.cos(theta) * 0.8, 0.55 + 0.15 * math.sin(t * 0.7 + PHASE[i]), -math.sin(theta) * 0.8 + 0.6
	return { x = x, y = y, z = z, ax = ax, ay = ay, az = az, s = SIZE[i] }
end

-- Rest: five rings on each of two forearms rising from the bottom of the
-- frame, angled in toward each other, largest at the wrist nearest the
-- viewer, nested close together and humming gently.
local ARM_BOTTOM_X, ARM_BOTTOM_Y, ARM_BOTTOM_S = 1.15, -2.2, 0.63
local ARM_TOP_X, ARM_TOP_Y, ARM_TOP_S = 0.63, -1.6, 0.39
local DIVE_DEPTH = 24

-- Which forearm each ring rests on, and where along it (0 = wrist). Each
-- arm takes the rings whose orbit slots are on its side of the halo, so
-- when they fly out their paths never cross.
local ARM_SIDE = { 1, 1, 1, -1, -1, -1, -1, -1, 1, 1 }
local ARM_J = { 2, 3, 4, 0, 1, 2, 3, 4, 0, 1 }

local function armsPose(i: number, t: number): Pose
	local side = ARM_SIDE[i]
	local j = ARM_J[i]
	local f = j / (COUNT / 2 - 1)
	local bob = math.sin(t * 1.3 + j * 0.6 + (if side < 0 then 0 else 1.7)) * 0.018
	local x = side * mix(ARM_BOTTOM_X, ARM_TOP_X, f)
	local y = mix(ARM_BOTTOM_Y, ARM_TOP_Y, f) + bob
	local z = -f * 0.6
	-- Faces the viewer, leaning along the forearm (up and inward).
	return { x = x, y = y, z = z, ax = -side * 0.32, ay = 0.42, az = 1, s = mix(ARM_BOTTOM_S, ARM_TOP_S, f) }
end

-- Awaken flight: from the forearm to the ring's orbit slot along a cubic
-- curve that rises straight up off the arm, swings out over its own side
-- and drops into the slot from above and outside. Rings at the elbow end
-- leave first. `flight` 0..1 is keyed; at 1 every ring is in its slot.
local function cubic(a: number, b: number, c: number, d: number, u: number): number
	local v = 1 - u
	return v * v * v * a + 3 * v * v * u * b + 3 * v * u * u * c + u * u * u * d
end

local function flightPose(i: number, from: Pose, to: Pose, flight: number): Pose
	local side = ARM_SIDE[i]
	local delay = (4 - ARM_J[i]) * 0.06
	local u = smooth(clamp((flight - delay) / (1 - 0.24), 0, 1))
	local p1x, p1y = from.x + side * 0.2, from.y + 3.2
	local p2x, p2y = to.x + side * 1.6, to.y + 1.7
	local x = cubic(from.x, p1x, p2x, to.x, u)
	local y = cubic(from.y, p1y, p2y, to.y, u)
	local z = mix(from.z, to.z, u) - 2.2 * math.sin(u * math.pi)
	-- Turn from facing the viewer to the orbit's lean, with an extra
	-- roll in the middle of the flight.
	local roll = math.sin(u * math.pi) * 0.6 * side
	return {
		x = x,
		y = y,
		z = z,
		ax = mix(from.ax, to.ax, u) + roll,
		ay = mix(from.ay, to.ay, u),
		az = mix(from.az, to.az, u),
		s = mix(from.s, to.s, u),
	}
end

-- Summoned: the rings shrink and line up evenly around a large circle,
-- face-on to the viewer. Each keeps its angle from the halo (the halo's
-- x/y on screen follow cos/sin of the same angle), so summoning draws every
-- ring straight inward rather than crossing paths. Power adds a slight
-- breathing.
local CIRCLE_RADIUS = 1.75
local CIRCLE_Y = 0.05
local CIRCLE_RING = 0.24

local function circleAngle(i: number, turn: number): number
	return (i - 1) / COUNT * math.pi * 2 + turn
end

-- `tumble` (radians, accumulated in advance) flips each ring over about its
-- spoke like a spun coin, all rings in step, so the circle moves as one
-- symmetric pattern; a second, slower term makes every axis wobble together
-- like a precessing gyroscope.
local function circlePose(i: number, t: number, power: number, turn: number, tumble: number): Pose
	local a = circleAngle(i, turn)
	local breathe = 1 + math.sin(t * 2.2) * 0.015 * power
	local x = math.cos(a) * CIRCLE_RADIUS * breathe
	local y = CIRCLE_Y + math.sin(a) * CIRCLE_RADIUS * breathe
	local rx, ry = math.cos(a), math.sin(a) -- spoke (radial)
	local tx, ty = -ry, rx -- tangent
	local flip = tumble
	local wobble = math.sin(tumble * 0.55) * 0.45
	-- Face-on axis rotated about the spoke, then leaned along the spoke.
	local ax = tx * math.sin(flip) + rx * wobble
	local ay = ty * math.sin(flip) + ry * wobble
	local az = math.cos(flip)
	return { x = x, y = y, z = 0, ax = ax, ay = ay, az = az, s = CIRCLE_RING }
end

-- Unleash cluster: the rings pulled into a tight circle, so close they
-- overlap, tilted alternately along their tangent so neighbours interlace
-- like chain links.
local CLUSTER_RADIUS = 0.55
local CLUSTER_RING = 0.36

local function clusterPose(i: number, turn: number): Pose
	local a = circleAngle(i, turn)
	local rx, ry = math.cos(a), math.sin(a)
	local tx, ty = -ry, rx
	local lean = if i % 2 == 0 then 0.7 else -0.7
	return {
		x = rx * CLUSTER_RADIUS,
		y = CIRCLE_Y + ry * CLUSTER_RADIUS,
		z = if i % 2 == 0 then 0.06 else -0.06,
		ax = tx * lean,
		ay = ty * lean,
		az = 1,
		s = CLUSTER_RING,
	}
end

-- Unleash: each ring flies straight out from the circle along its spoke,
-- and a little toward the camera.
local function launchDir(i: number, turn: number): (number, number, number)
	local a = circleAngle(i, turn)
	return normalize(math.cos(a), math.sin(a), 0.35)
end

-- Cursor follow (Orbit): the rings line up along the path the cursor has
-- drawn, largest at the cursor, smaller toward the tail, each spaced by its
-- size, facing the viewer and leaning a little along the path.
local FOLLOW_IDLE = 0.5 -- seconds of stillness before the rings let go
local TRAIL_STEP = 0.04 -- world units between recorded path points
local TRAIL_MAX = 400
local CHAIN_LEAD = 0.38 -- radius of the ring at the cursor
local CHAIN_TAIL = 0.18 -- radius of the last ring
local LEAD_EASE = 5 -- how quickly the chain's head catches the cursor (per second)
local CHAIN_GAP = 1.0 -- spacing, in ring radii

local function mixPose(a: Pose, b: Pose, t: number): Pose
	return {
		x = mix(a.x, b.x, t),
		y = mix(a.y, b.y, t),
		z = mix(a.z, b.z, t),
		ax = mix(a.ax, b.ax, t),
		ay = mix(a.ay, b.ay, t),
		az = mix(a.az, b.az, t),
		s = mix(a.s, b.s, t),
	}
end

-- ---------------------------------------------------------------------------
-- Carving
-- ---------------------------------------------------------------------------

-- Writes each vertex's groove depth into its uv.x: the average offset of its
-- neighbours along its normal, over the average edge length, so it is
-- independent of the model's scale. Positive = recessed (carved). One
-- smoothing pass keeps single noisy vertices from sparkling.
-- Parts whose deepest groove is shallower than this are treated as plain.
local CARVED_DEPTH = 0.12

local function measureCavity(p: GLB.Primitive)
	local n = p.vertexCount
	local v = p.vertices
	local stride = GLB.VERTEX_STRIDE
	local sx, sy, sz = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local count, edge = table.create(n, 0), table.create(n, 0)
	local function pos(i: number): (number, number, number)
		local o = i * stride
		return buffer.readf32(v, o), buffer.readf32(v, o + 4), buffer.readf32(v, o + 8)
	end
	local function link(a: number, b: number)
		local ax, ay, az = pos(a)
		local bx, by, bz = pos(b)
		sx[a + 1] += bx
		sy[a + 1] += by
		sz[a + 1] += bz
		count[a + 1] += 1
		edge[a + 1] += math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
	end
	local idx = p.indices
	local neighbours: { { number } } = {}
	for i = 1, n do
		neighbours[i] = {}
	end
	for t = 0, p.indexCount - 1, 3 do
		local a = buffer.readu32(idx, t * 4)
		local b = buffer.readu32(idx, t * 4 + 4)
		local c = buffer.readu32(idx, t * 4 + 8)
		for _, e in { { a, b }, { b, c }, { c, a } } do
			link(e[1], e[2])
			link(e[2], e[1])
			table.insert(neighbours[e[1] + 1], e[2] + 1)
			table.insert(neighbours[e[2] + 1], e[1] + 1)
		end
	end
	local cav = table.create(n, 0)
	for i = 1, n do
		local c = count[i]
		if c > 0 then
			local x, y, z = pos(i - 1)
			local o = (i - 1) * stride
			local nx, ny, nz = buffer.readf32(v, o + 12), buffer.readf32(v, o + 16), buffer.readf32(v, o + 20)
			local dx, dy, dz = sx[i] / c - x, sy[i] / c - y, sz[i] / c - z
			cav[i] = (dx * nx + dy * ny + dz * nz) / math.max(edge[i] / c, 1e-9)
		end
	end
	-- A part with no deep grooves is a plain band: its values only describe
	-- its curvature, so mark it uncarved rather than let its edges glow.
	local deepest = 0
	for i = 1, n do
		deepest = math.max(deepest, cav[i])
	end
	local carved = deepest > CARVED_DEPTH
	for i = 1, n do
		local value = -1
		if carved then
			local list = neighbours[i]
			local sum = 0
			for _, j in list do
				sum += cav[j]
			end
			local smooth = if #list > 0 then sum / #list else cav[i]
			value = cav[i] * 0.6 + smooth * 0.4
		end
		buffer.writef32(v, (i - 1) * stride + 24, value)
	end
end

-- ---------------------------------------------------------------------------
-- GPU setup
-- ---------------------------------------------------------------------------

local function loadShapes(self: TenRings): boolean
	local context = self.context
	if context == nil then
		return false
	end
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`TenRings: no blob asset named '{self.asset}'`)
		return false
	end
	local model, err = GLB.parse(blob.data, { bakeTransforms = false })
	if model == nil then
		print(`TenRings: could not load '{self.asset}': {err}`)
		return false
	end
	-- Keep each distinct ring once (the file repeats shapes on several nodes).
	local seen: { [string]: boolean } = {}
	local found: { GLB.Primitive } = {}
	for _, p in model.primitives do
		local key = p.vertexCount .. ':' .. p.indexCount
		if not seen[key] then
			seen[key] = true
			table.insert(found, p)
		end
	end
	-- Largest ring first.
	local function extent(p: GLB.Primitive): number
		local r = 0
		for v = 0, p.vertexCount - 1 do
			local x = buffer.readf32(p.vertices, v * GLB.VERTEX_STRIDE)
			local y = buffer.readf32(p.vertices, v * GLB.VERTEX_STRIDE + 4)
			r = math.max(r, math.sqrt(x * x + y * y))
		end
		return r
	end
	local radii: { [GLB.Primitive]: number } = {}
	for _, p in found do
		radii[p] = extent(p)
	end
	table.sort(found, function(a: GLB.Primitive, b: GLB.Primitive): boolean
		return radii[a] > radii[b]
	end)
	for _, p in found do
		measureCavity(p)
		table.insert(self.shapes, {
			vertexBuffer = GPUBuffer.new({ size = buffer.len(p.vertices), usage = 'vertex', data = p.vertices, immutable = true }),
			indexBuffer = GPUBuffer.new({ size = buffer.len(p.indices), usage = 'index', data = p.indices, immutable = true }),
			indexCount = p.indexCount,
			center = { 0, 0, 0 },
			radius = math.max(radii[p], 1e-6),
		})
	end
	self.ringRadius = 0
	for _, shape in self.shapes do
		self.ringRadius = math.max(self.ringRadius, shape.radius)
	end
	print(`TenRings: one ring from {#self.shapes} part(s) from '{self.asset}' ({model.vertexCount} vertices in the file)`)
	return #self.shapes > 0
end

local function ensureTargets(self: TenRings): GPUCanvas?
	local context = self.context
	if context == nil then
		return nil
	end
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(1, math.floor(self.width * res))
	local h = math.max(1, math.floor(self.height * res))
	local samples = if self.msaa >= 2 then 4 else 1
	local canvas = self.canvas
	if canvas and w == self.targetW and h == self.targetH and samples == self.targetSamples then
		return canvas
	end
	if canvas == nil then
		canvas = context:gpuCanvas({ width = w, height = h })
		self.canvas = canvas
	else
		canvas:resize(w, h)
	end
	assert(canvas)
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = canvas.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.pipeline == nil then
		local shader = self.shader
		assert(shader)
		self.pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {
				{
					stride = GLB.VERTEX_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'float32x3', slot = 1, offset = 12 },
						{ format = 'float32x2', slot = 2, offset = 24 },
					},
				},
			},
			colorTargets = { { format = canvas.format } },
			depthStencil = { format = DEPTH_FORMAT, compare = 'less', write = true },
			cullMode = 'none',
			sampleCount = samples,
		})
		for _, ring in self.rings do
			ring.bindings = nil
		end
	end
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return canvas
end

-- ---------------------------------------------------------------------------
-- Per-frame
-- ---------------------------------------------------------------------------

local function writeUniforms(self: TenRings, ring: Ring, mvp: Mat4, model: Mat4, power: number)
	local u = self.scratch
	mvp:writeToBuffer(u, 0)
	model:writeToBuffer(u, 64)
	local mr, mg, mb = linear(self.metalColor)
	buffer.writef32(u, 128, mr)
	buffer.writef32(u, 132, mg)
	buffer.writef32(u, 136, mb)
	buffer.writef32(u, 140, 1)
	local er, eg, eb = linear(self.energyColor)
	local glow = power * power * 0.06
	buffer.writef32(u, 144, er * glow)
	buffer.writef32(u, 148, eg * glow)
	buffer.writef32(u, 152, eb * glow)
	buffer.writef32(u, 156, 1)
	buffer.writef32(u, 160, er)
	buffer.writef32(u, 164, eg)
	buffer.writef32(u, 168, eb)
	buffer.writef32(u, 172, 0.08 + power * 0.32)
	-- Key light from the upper left, in front.
	local lx, ly, lz = normalize(-0.5, 0.7, 0.75)
	buffer.writef32(u, 176, lx)
	buffer.writef32(u, 180, ly)
	buffer.writef32(u, 184, lz)
	buffer.writef32(u, 188, 2.1)
	buffer.writef32(u, 192, 0)
	buffer.writef32(u, 196, 0)
	buffer.writef32(u, 200, CAMERA_Z)
	buffer.writef32(u, 204, 0.35)
	buffer.writef32(u, 208, clamp(self.metallic, 0, 1))
	buffer.writef32(u, 212, clamp(self.roughness, 0.04, 1))
	buffer.writef32(u, 216, self.time)
	buffer.writef32(u, 220, 1) -- exposure
	local ir, ig, ib = linear(self.imprintColor)
	buffer.writef32(u, 224, ir)
	buffer.writef32(u, 228, ig)
	buffer.writef32(u, 232, ib)
	buffer.writef32(u, 236, math.max(0, self.imprintGlow) * (1 + power * 0.8))
	buffer.writef32(u, 240, 0.65) -- environment
	buffer.writef32(u, 244, 1) -- opacity
	buffer.writef32(u, 248, self.cavityLow)
	buffer.writef32(u, 252, math.max(self.cavityHigh, self.cavityLow + 0.001))
	ring.uniforms:write(u)
end

-- Walks back along the trail from its newest point and places each ring at
-- its accumulated distance. Past the trail's oldest point the chain carries
-- on in the direction the path started, so a short stroke never piles the
-- tail up in one spot.
local function chainPoses(self: TenRings): { Pose }
	local xs, ys = self.trailX, self.trailY
	local n = #xs
	local poses: { Pose } = {}
	local idx = n -- segment end being walked
	local walked = 0 -- distance from the head to point idx
	local want = 0
	local prevS = 0
	local lastDirX, lastDirY = 1, 0
	for i = 1, COUNT do
		local s = mix(CHAIN_LEAD, CHAIN_TAIL, (i - 1) / (COUNT - 1))
		if i > 1 then
			want += (prevS + s) * CHAIN_GAP
		end
		prevS = s
		-- Advance along the trail until it reaches `want`.
		local px, py = xs[math.max(idx, 1)] or self.leaderX, ys[math.max(idx, 1)] or self.leaderY
		local dirX, dirY = lastDirX, lastDirY
		while idx > 1 do
			local ax, ay = xs[idx], ys[idx]
			local bx, by = xs[idx - 1], ys[idx - 1]
			local seg = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
			if walked + seg >= want then
				local f = if seg > 0 then (want - walked) / seg else 0
				px, py = mix(ax, bx, f), mix(ay, by, f)
				if seg > 0 then
					dirX, dirY = (ax - bx) / seg, (ay - by) / seg
				end
				break
			end
			walked += seg
			idx -= 1
			px, py = bx, by
			if seg > 0 then
				dirX, dirY = (ax - bx) / seg, (ay - by) / seg
			end
		end
		if idx <= 1 and walked < want then
			-- Beyond the recorded path: extend straight back.
			local over = want - walked
			px, py = px - dirX * over, py - dirY * over
		end
		-- Face the viewer, leaning toward the direction of travel, with a slow
		-- tumble of its own so the chain never looks rigid.
		local t = self.time
		local wx = math.sin(t * 0.7 + PHASE[i]) * 0.5
		local wy = math.cos(t * 0.55 + PHASE[i] * 1.3) * 0.4
		table.insert(poses, { x = px, y = py, z = 0, ax = dirX * 0.35 + wx, ay = dirY * 0.35 + wy, az = 1, s = s })
		lastDirX, lastDirY = dirX, dirY
	end
	return poses
end

local function render(self: TenRings): Image?
	if #self.shapes == 0 then
		return nil
	end
	local canvas = ensureTargets(self)
	local pipeline = self.pipeline
	local depthView = self.depthView
	if canvas == nil or pipeline == nil or depthView == nil then
		return nil
	end

	local t = self.time
	local formation = smooth(self.formation)
	local launch = clamp(self.launch, 0, 1.5)
	local power = clamp(self.power, 0, 1.5)
	local intro = self.intro

	local aspect = self.targetW / self.targetH
	local proj = Mat4.perspective(FOV, aspect, 1, 40)
	local view = Mat4.lookAt(Vector.xyz(0, 0, CAMERA_Z), Vector.origin(), Vector.xyz(0, 1, 0))
	local tilt = Mat4.fromRotationX(math.rad(self.tiltY)) * Mat4.fromRotationY(math.rad(self.tiltX))
	local viewProj = proj * view * Mat4.fromTranslation(0, LIFT, 0)

	local rest = clamp(self.rest, 0, 1)
	local dive = clamp(self.dive, 0, 1)
	local follow = self.follow * (1 - formation) * (1 - clamp(launch, 0, 1)) * clamp(intro, 0, 1) * (1 - rest) * (1 - dive) * (1 - clamp(self.flight, 0, 1))
	local chain = if follow > 0.001 then chainPoses(self) else nil

	for i, ring in self.rings do
		local o = orbitPose(i, t, self.turn)
		local flight = clamp(self.flight, 0, 1)
		if flight > 0 then
			o = flightPose(i, armsPose(i, t), o, flight)
		elseif rest > 0 then
			o = mixPose(o, armsPose(i, t), smooth(rest))
		end
		if chain then
			o = mixPose(o, chain[i], smooth(follow))
		end
		local st = circlePose(i, t, power, self.turn, self.tumble)
		local x, y, z = mix(o.x, st.x, formation), mix(o.y, st.y, formation), mix(o.z, st.z, formation)
		local ax, ay, az = mix(o.ax, st.ax, formation), mix(o.ay, st.ay, formation), mix(o.az, st.az, formation)
		local s = mix(o.s, st.s, formation)
		-- Unleash, part 1: collapse into the interlocked cluster.
		local charge = clamp(self.charge, 0, 1)
		if charge > 0 then
			local c = clusterPose(i, self.turn)
			local k = smooth(charge)
			x = mix(x, c.x, k)
			y = mix(y, c.y, k)
			z = mix(z, c.z, k)
			ax = mix(ax, c.ax, k)
			ay = mix(ay, c.ay, k)
			az = mix(az, c.az, k)
			s = mix(s, c.s, k)
		end
		-- Part 2: tremble, the whole cluster and each ring on its own.
		local shake = clamp(self.shake, 0, 1)
		if shake > 0 then
			local a = shake * shake
			x += (math.sin(t * 53 + i * 1.7) * 0.05 + math.sin(t * 37) * 0.07) * a
			y += (math.cos(t * 47 + i * 2.3) * 0.05 + math.cos(t * 41) * 0.07) * a
			ax += math.sin(t * 61 + i) * 0.25 * a
			ay += math.cos(t * 57 + i * 1.3) * 0.25 * a
		end
		-- Part 3: explode outward, turning to face the direction of travel.
		if launch > 0 then
			local dx, dy, dz = launchDir(i, self.turn)
			local dist = 3.2 * launch
			x, y, z = x + dx * dist, y + dy * dist, z + dz * dist
			ax, ay, az = ax + dx * launch * 2.5, ay + dy * launch * 2.5, az + dz * launch * 2.5
			s *= 1 + 0.35 * launch
		end
		-- Awaken: pushed deep into the screen, each to a slightly different
		-- depth, turning to face the way they travel.
		if dive > 0 then
			local d = dive * dive * (3 - 2 * dive)
			z -= DIVE_DEPTH * d * (1 + 0.18 * math.sin((PHASE[i] :: number) * 3))
			ax = mix(ax, 0, d * 0.6)
			ay = mix(ay, 0, d * 0.6)
			az = mix(az, 1, d * 0.6)
		end
		-- Intro: each ring flies in from the dark in turn.
		local k = clamp(intro * 1.7 - (i - 1) * 0.07, 0, 1)
		s *= math.max(easeOutBack(k), 0.0001)
		z -= (1 - smooth(k)) * 9
		y += (1 - smooth(k)) * 1.5

		local scale = s / self.ringRadius
		local model = tilt * orient(x, y, z, ax, ay, az, self.spins[i] or 0, scale)
		ring.mvp = viewProj * model
		writeUniforms(self, ring, ring.mvp, model, power)

		-- Screen-space centre and size, for the 2D glow behind the ring.
		local c = (viewProj * tilt):transformPoint(x, y, z)
		ring.screen = Vector.xy((c.x * 0.5 + 0.5) * self.width - self.width / 2, (0.5 - c.y * 0.5) * self.height - self.height / 2)
		ring.screenRadius = s / (CAMERA_Z - z) / math.tan(FOV / 2) * self.height / 2
		ring.depth = z

		if ring.bindings == nil then
			ring.bindings = GPUBindGroup.new({
				layout = pipeline:getBindGroupLayout(0),
				ubos = { { slot = 0, buffer = ring.uniforms } },
			})
		end
	end

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = canvas:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 0 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } }
	local pass = canvas:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 1 },
	})
	pass:setPipeline(pipeline)
	for _, ring in self.rings do
		local bindings = ring.bindings
		if bindings then
			pass:setBindGroup(0, bindings)
			for _, shape in self.shapes do
				pass:setVertexBuffer(0, shape.vertexBuffer)
				pass:setIndexBuffer(shape.indexBuffer, 'uint32')
				pass:drawIndexed(shape.indexCount)
			end
		end
	end
	pass:finish()
	return canvas.image
end

-- Aura: soft waves of energy flowing around each ring, in `energyColor`.
-- Each ring carries a few light ribbons that follow its circle but undulate
-- in and out of its plane; bright pulses travel along them and fade, so the
-- energy reads as moving currents rather than a static halo. A faint steady
-- glow sits under them. Everything strengthens with `power`.
local RIBBON_POINTS = 72
local RIBBON_CHUNKS = 12
type Ribbon = { freq: number, wobble: number, speed: number, amp: number, lift: number }
local RIBBONS: { Ribbon } = {
	{ freq = 3, wobble = 5, speed = 1.1, amp = 0.09, lift = 0.14 },
	{ freq = 5, wobble = 3, speed = -0.8, amp = 0.06, lift = 0.18 },
	{ freq = 2, wobble = 7, speed = 0.6, amp = 0.12, lift = 0.1 },
}

-- `front` false draws the soft glow behind the rings; true draws the
-- waves over them, screen-blended so they read as light on the metal.
local function drawAura(self: TenRings, renderer: Renderer, front: boolean)
	local strength = math.max(0, self.aura) * (0.55 + clamp(self.power, 0, 1.5) * 0.9)
	if strength <= 0.01 or self.ringRadius <= 0 then
		return
	end
	local r, g, b = Color.red(self.energyColor) :: number, Color.green(self.energyColor) :: number, Color.blue(self.energyColor) :: number
	local paint = self.auraPaint
	local R = self.ringRadius
	local hw, hh = self.width / 2, self.height / 2
	local t = self.time
	local xs, ys = table.create(RIBBON_POINTS + 1, 0), table.create(RIBBON_POINTS + 1, 0)
	local function alphaColor(a: number): Color
		return Color.rgba(r, g, b, math.floor(clamp(a, 0, 1) * 255))
	end

	for i, ring in self.rings do
		local size = ring.screenRadius
		if size > 2 then
			local phase = i * 1.7

			if not front then
			-- Faint steady glow along the ring itself, behind it.
			local base = Path.new()
			for k = 0, RIBBON_POINTS do
				local a = k / RIBBON_POINTS * math.pi * 2
				local q = ring.mvp:transformPoint(math.cos(a) * R, math.sin(a) * R, 0)
				local pt = Vector.xy(q.x * hw, -q.y * hh)
				if k == 0 then
					base:moveTo(pt)
				else
					base:lineTo(pt)
				end
			end
			paint.thickness = size * 0.16
			paint.feather = size * 0.22
			paint.blendMode = 'srcOver'
			paint.color = alphaColor(0.22 * strength)
			renderer:drawPath(base, paint)
			end

			for n, rb in (if front then RIBBONS else {}) :: { Ribbon } do
				paint.blendMode = 'screen'
				-- The ribbon's path: around the ring, breathing radially and
				-- rippling out of the ring's plane.
				for k = 0, RIBBON_POINTS do
					local a = k / RIBBON_POINTS * math.pi * 2
					local rr = R * (1.02 + rb.amp * math.sin(rb.freq * a + t * rb.speed * 2 + phase + n))
					local z = R * rb.lift * math.cos(rb.wobble * a - t * rb.speed * 1.6 + phase * 0.7)
					local q = ring.mvp:transformPoint(math.cos(a) * rr, math.sin(a) * rr, z)
					xs[k + 1] = q.x * hw
					ys[k + 1] = -q.y * hh
				end
				-- Pulses: brightness travels around the ribbon, so the light
				-- appears to flow. Drawn in chunks, each with its own alpha.
				local per = RIBBON_POINTS / RIBBON_CHUNKS
				for c = 0, RIBBON_CHUNKS - 1 do
					local mid = (c + 0.5) / RIBBON_CHUNKS * math.pi * 2
					local pulse = 0.5 + 0.5 * math.sin(mid * 2 - t * rb.speed * 2.4 + phase * 1.3 + n * 2)
					pulse = pulse * pulse
					local alpha = (0.12 + 0.88 * pulse) * strength
					if alpha > 0.03 then
						local path = Path.new()
						for k = c * per, (c + 1) * per do
							local pt = Vector.xy(xs[k + 1], ys[k + 1])
							if k == c * per then
								path:moveTo(pt)
							else
								path:lineTo(pt)
							end
						end
						-- Soft wide glow, then the bright core of the wave.
						paint.thickness = size * 0.07
						paint.feather = size * 0.1
						paint.color = alphaColor(alpha * 0.4)
						renderer:drawPath(path, paint)
						paint.thickness = math.max(1, size * 0.018)
						paint.feather = size * 0.025
						paint.color = alphaColor(alpha * 0.85)
						renderer:drawPath(path, paint)
					end
				end
			end
		end
	end
end

local function drawGlow(self: TenRings, renderer: Renderer)
	-- Only once energy builds: the resting halo stays dark.
	local power = clamp((self.power - 0.25) / 0.75, 0, 1.5)
	if power <= 0.02 then
		return
	end
	local r, g, b = Color.red(self.energyColor) :: number, Color.green(self.energyColor) :: number, Color.blue(self.energyColor) :: number
	for _, ring in self.rings do
		local radius = ring.screenRadius * 1.7
		if radius > 1 then
			local c = ring.screen
			self.glowPaint.gradient = Gradient.radial(c, radius, {
				{ position = 0, color = Color.rgba(r, g, b, math.floor(clamp(power * 0.14, 0, 1) * 255)) },
				{ position = 0.55, color = Color.rgba(r, g, b, math.floor(clamp(power * 0.06, 0, 1) * 255)) },
				{ position = 1, color = Color.rgba(r, g, b, 0) },
			})
			local path = Path.new()
			path:moveTo(Vector.xy(c.x - radius, c.y - radius))
			path:lineTo(Vector.xy(c.x + radius, c.y - radius))
			path:lineTo(Vector.xy(c.x + radius, c.y + radius))
			path:lineTo(Vector.xy(c.x - radius, c.y + radius))
			path:close()
			renderer:drawPath(path, self.glowPaint)
		end
	end
end

function init(self: TenRings, context: Context): boolean
	self.context = context
	self.shader = context:shader('ring')
	if self.shader == nil then
		print('TenRings: shader "ring" not found')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		self.sampler = GPUSampler.new()
		local white = GPUTexture.new({ width = 1, height = 1 })
		local pixel = buffer.create(4)
		buffer.writeu32(pixel, 0, 0xFFFFFFFF)
		white:upload({ data = pixel })
		self.whiteView = white:view()
		if not loadShapes(self) then
			self.failed = true
			return
		end
		for i = 1, COUNT do
			table.insert(self.rings, {
				uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
				bindings = nil,
				screen = Vector.origin(),
				screenRadius = 0,
				depth = 0,
				mvp = Mat4.identity(),
			})
			self.spins[i] = PHASE[i]
		end
	end)
	if not ok then
		print('TenRings: setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

-- Moves the follow target to a point in the node's local space (origin at
-- the centre), from the pointer or from `followX`/`followY`.
local function setCursor(self: TenRings, px: number, py: number)
	self.pointerX = clamp(px / (self.width / 2), -1, 1)
	self.pointerY = clamp(py / (self.height / 2), -1, 1)
	-- The target on the rings' plane (z = 0), in world units.
	local halfH = CAMERA_Z * math.tan(FOV / 2)
	local x = px / (self.height / 2) * halfH
	local y = -py / (self.height / 2) * halfH - LIFT
	if (x - self.cursorX) ^ 2 + (y - self.cursorY) ^ 2 > 1e-6 then
		self.lastMove = self.time
	end
	self.cursorX, self.cursorY = x, y
end

function advance(self: TenRings, seconds: number): boolean
	self.time += seconds
	local power = clamp(self.power, 0, 1.5)
	local formation = smooth(self.formation)
	-- One rotation for halo and circle: lazy in orbit, a little quicker
	-- once summoned.
	-- Held while resting, so each arm's rings fly to the slots on its side.
	local moving = 1 - clamp(self.rest, 0, 1)
	self.turn = (self.turn + seconds * moving * (0.16 + formation * 0.2 * power)) % (math.pi * 2)
	-- Tumbling eases in with the circle and speeds up with power.
	self.tumble = (self.tumble + seconds * formation * (1.4 + 1.8 * power)) % (math.pi * 4)
	-- Charging spins the interlocked cluster faster and faster.
	local charge = clamp(self.charge, 0, 1)
	self.turn = (self.turn + seconds * charge * charge * 11) % (math.pi * 2)
	local launch = clamp(self.launch, 0, 1.5)
	for i = 1, COUNT do
		-- Lazy turning in orbit; fast, alternating spin on the arm and in flight.
		local dir = if i % 2 == 0 then 1 else -1
		-- Orbit: lazy, alternating. Summoned: every ring spins the same way at
		-- the same speed, in step with the tumble.
		local rate = mix(0.25 * dir, 1.2 * (0.4 + power), formation) + dir * launch * 14 + charge * 6
		self.spins[i] = (self.spins[i] + rate * seconds) % (math.pi * 2)
	end
	-- Cursor follow: on while the pointer has moved recently, off once it
	-- has been still for a moment (then the rings drift back into orbit).
	if self.followActive then
		self.pointerOn = true
		setCursor(self, (self.followX - 0.5) * self.width, (self.followY - 0.5) * self.height)
	end
	-- Recency alone decides: leaving the canvas also means no more moves.
	local active = (self.time - self.lastMove) < FOLLOW_IDLE
	if active and self.follow < 0.02 then
		-- Starting fresh: the chain grows out of the cursor.
		self.leaderX, self.leaderY = self.cursorX, self.cursorY
		self.trailX, self.trailY = { self.cursorX }, { self.cursorY }
	end
	local rateIn = if active then 1.8 else 1.2
	self.follow += ((if active then 1 else 0) - self.follow) * (1 - math.exp(-rateIn * seconds))
	if self.follow > 0.001 then
		local k = 1 - math.exp(-LEAD_EASE * seconds)
		self.leaderX += (self.cursorX - self.leaderX) * k
		self.leaderY += (self.cursorY - self.leaderY) * k
		local n = #self.trailX
		local lx, ly = self.trailX[n], self.trailY[n]
		if lx == nil or (self.leaderX - lx) ^ 2 + (self.leaderY - ly) ^ 2 > TRAIL_STEP * TRAIL_STEP then
			table.insert(self.trailX, self.leaderX)
			table.insert(self.trailY, self.leaderY)
			if #self.trailX > TRAIL_MAX then
				table.remove(self.trailX, 1)
				table.remove(self.trailY, 1)
			end
		end
	end

	-- Pointer tilt eases toward the target (or back to rest); none while
	-- the rings follow the cursor.
	local tiltOn = self.pointerOn and self.follow < 0.5
	local tx = if tiltOn then self.pointerX * self.tiltAmount else 0
	local ty = if tiltOn then self.pointerY * self.tiltAmount else 0
	local f = 1 - math.exp(-4 * seconds)
	self.tiltX += (tx - self.tiltX) * f
	self.tiltY += (ty - self.tiltY) * f
	return true
end

local function pointerMove(self: TenRings, event: PointerEvent)
	-- An external target (a tracked hand) takes over from the pointer.
	if self.followActive then
		return
	end
	self.pointerOn = true
	setCursor(self, event.position.x, event.position.y)
end

local function pointerExit(self: TenRings, event: PointerEvent)
	self.pointerOn = false
end

function draw(self: TenRings, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('TenRings: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	if image == nil then
		return
	end
	drawAura(self, renderer, false)
	drawGlow(self, renderer)
	renderer:save()
	renderer:transform(
		Mat2D.withTranslation(-self.width / 2, -self.height / 2)
			* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
	)
	renderer:drawImage(image, self.drawSampler, 'srcOver', 1)
	renderer:restore()
	drawAura(self, renderer, true)
end

return function(): Node<TenRings>
	return {
		asset = 'rings',
		width = 1280,
		height = 720,
		resolution = 1.25,
		msaa = 4,
		formation = 0,
		launch = 0,
		power = 0.2,
		intro = 1,
		rest = 0,
		dive = 0,
		flight = 0,
		charge = 0,
		shake = 0,
		followX = 0.5,
		followY = 0.5,
		followActive = false,
		energyColor = Color.rgb(63, 182, 255),
		imprintColor = Color.rgb(255, 122, 46),
		imprintGlow = 2.2,
		cavityLow = 0.012,
		cavityHigh = 0.06,
		aura = 1,
		metalColor = Color.rgb(132, 78, 44),
		metallic = 1,
		roughness = 0.42,
		tiltAmount = 10,

		context = nil,
		failed = false,
		time = 0,
		turn = 0,
		tumble = 0,
		spins = {},
		tiltX = 0,
		tiltY = 0,
		pointerX = 0,
		pointerY = 0,
		pointerOn = false,
		follow = 0,
		lastMove = -10,
		cursorX = 0,
		cursorY = 0,
		leaderX = 0,
		leaderY = 0,
		trailX = {},
		trailY = {},

		shader = nil,
		pipeline = nil,
		canvas = nil,
		depthView = nil,
		msaaView = nil,
		targetW = 0,
		targetH = 0,
		targetSamples = 0,
		sampler = nil,
		whiteView = nil,
		shapes = {},
		ringRadius = 1,
		rings = {},
		scratch = buffer.create(UNIFORM_SIZE),
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		glowPaint = Paint.with({ style = 'fill' }),
		auraPaint = Paint.with({ style = 'stroke', join = 'round', cap = 'round', thickness = 10 }),

		init = init,
		advance = advance,
		draw = draw,
		pointerMove = pointerMove,
		pointerExit = pointerExit,
	}
end
