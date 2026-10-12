-- Mangroves: the night river world, in 3D.
--
-- Every object has a world position (metres): X across (0 = river centre),
-- Y up (0 = water), Z ahead of the camera. A perspective camera sits just
-- above the water behind the boat and glides forward at `speed`; objects
-- that pass behind it are moved to the far end, so the river never ends.
--
-- Drawn back to front:
--   sky        gradient, stars, a moon glow behind the haze
--   treeline   the far forest on the horizon, and its reflection
--   water      gradient, the moon's shimmering path, ripples
--   reflections of the near trees, dim and wavering
--   banks      mud on both sides, with breathing roots (pneumatophores)
--   mangroves  stilt-rooted trees, fogged with distance
--   mist       low drifting banks over the water
--
-- Vector paths and feathering only: no shaders, GPU canvas or blend modes,
-- so it renders the same on the web and on native Android.
--
-- Place at the artboard's top-left. Inputs: width, height, speed (m/s),
-- fog (0-1), mist (0-1), moonX (0-1 across).

export type Mangroves = {
	width: Input<number>,
	height: Input<number>,
	speed: Input<number>,
	fog: Input<number>,
	mist: Input<number>,
	moonX: Input<number>,

	time: number,
	trees: { Tree },
	roots: { Pneumo },
	ripples: { Ripple },
	mists: { Mist },
	stars: { Star },
	treeline: { number },
	fill: Paint,
	stroke: Paint,
}

type Tree = {
	x: number,
	z: number,
	height: number,
	lean: number,
	canopy: number,
	rootCount: number,
	rootSpread: number,
	seed: number,
}

type Pneumo = { x: number, z: number, h: number }
type Ripple = { x: number, z: number, len: number }
type Mist = { x: number, z: number, w: number, h: number, phase: number }
type Star = { x: number, y: number, r: number, phase: number }

-- World and camera.
local RIVER_HALF = 7 -- metres from centre to each bank
local CAM_HEIGHT = 1.7
local FOCAL = 760 -- pixels per metre at 1 m
local NEAR = 1.2
local FAR = 140
local HORIZON = 0.42 -- of the height

-- Palette (0xRRGGBB): night teal and mangrove green.
local SKY_TOP = 0x050B12
local SKY_HAZE = 0x1B3A3A
local FOG = 0x1E3B39
local WATER_FAR = 0x18302F
local WATER_NEAR = 0x060C0E
local MUD = 0x0B1512
local TREE = 0x070D0B
local CANOPY = 0x0B1A14
local MOON = 0xD8E6C4

local KAPPA = 0.5522848

local seed = 1
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rand()
end

local function ch(c: number, shift: number): number
	return bit32.band(bit32.rshift(c, shift), 0xFF)
end

-- `a` toward `b` by t, with alpha 0-1.
local function mix(a: number, b: number, t: number, alpha: number): Color
	t = math.clamp(t, 0, 1)
	return Color.rgba(
		math.floor(ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t),
		math.floor(ch(a, 8) + (ch(b, 8) - ch(a, 8)) * t),
		math.floor(ch(a, 0) + (ch(b, 0) - ch(a, 0)) * t),
		math.floor(math.clamp(alpha, 0, 1) * 255)
	)
end

-- Projection: world (x, y, z) to screen.
local function project(self: Mangroves, x: number, y: number, z: number): (number, number, number)
	local s = FOCAL / z
	return self.width * 0.5 + x * s, self.height * HORIZON + (CAM_HEIGHT - y) * s, s
end

-- How much a point at depth z has faded into the fog.
local function fogAt(self: Mangroves, z: number): number
	return 1 - math.exp(-z * (0.012 + 0.03 * math.clamp(self.fog, 0, 1)))
end

local function addEllipse(path: Path, cx: number, cy: number, rx: number, ry: number)
	local kx, ky = rx * KAPPA, ry * KAPPA
	path:moveTo(Vector.xy(cx + rx, cy))
	path:cubicTo(Vector.xy(cx + rx, cy + ky), Vector.xy(cx + kx, cy + ry), Vector.xy(cx, cy + ry))
	path:cubicTo(Vector.xy(cx - kx, cy + ry), Vector.xy(cx - rx, cy + ky), Vector.xy(cx - rx, cy))
	path:cubicTo(Vector.xy(cx - rx, cy - ky), Vector.xy(cx - kx, cy - ry), Vector.xy(cx, cy - ry))
	path:cubicTo(Vector.xy(cx + kx, cy - ry), Vector.xy(cx + rx, cy - ky), Vector.xy(cx + rx, cy))
	path:close()
end

---------------------------------------------------------------------------
-- Building the world

local function newTree(z: number): Tree
	local side = if rand() < 0.5 then -1 else 1
	-- Mangroves crowd the water: some stand with their roots in it.
	local x = side * (RIVER_HALF + range(-1.2, 9))
	return {
		x = x,
		z = z,
		height = range(3.5, 7.5),
		lean = range(-0.12, 0.12) + side * 0.06,
		canopy = range(1.8, 3.6),
		rootCount = math.floor(range(5, 9)),
		rootSpread = range(1.0, 1.8),
		seed = math.floor(range(1, 100000)),
	}
end

local function build(self: Mangroves)
	seed = 7319
	self.trees = {}
	for _ = 1, 110 do
		table.insert(self.trees, newTree(range(NEAR + 2, FAR)))
	end
	self.roots = {}
	for _ = 1, 260 do
		local side = if rand() < 0.5 then -1 else 1
		table.insert(self.roots, { x = side * (RIVER_HALF + range(0.1, 4)), z = range(NEAR, 60), h = range(0.15, 0.45) })
	end
	self.ripples = {}
	for _ = 1, 70 do
		table.insert(self.ripples, { x = range(-RIVER_HALF, RIVER_HALF), z = range(NEAR, 70), len = range(0.6, 2.2) })
	end
	self.mists = {}
	for _ = 1, 14 do
		table.insert(self.mists, {
			x = range(-RIVER_HALF - 6, RIVER_HALF + 6),
			z = range(6, 90),
			w = range(8, 18),
			h = range(0.5, 1.4),
			phase = range(0, math.pi * 2),
		})
	end
	self.stars = {}
	for _ = 1, 90 do
		table.insert(self.stars, {
			x = range(0, 1),
			y = range(0, HORIZON * 0.85),
			r = if rand() < 0.1 then range(1.2, 1.8) else range(0.4, 1),
			phase = range(0, math.pi * 2),
		})
	end
	-- Far forest silhouette: heights across the horizon (fractions of height).
	self.treeline = {}
	local h = 0.05
	for _ = 1, 96 do
		h = math.clamp(h + range(-0.012, 0.012), 0.025, 0.09)
		table.insert(self.treeline, h + (if rand() < 0.15 then range(0.004, 0.014) else 0))
	end
end

function init(self: Mangroves, context: Context): boolean
	build(self)
	return true
end

-- Everything moves toward the camera; whatever passes behind it goes back
-- to the far end.
function advance(self: Mangroves, seconds: number): boolean
	self.time += seconds
	local dz = math.max(0, self.speed) * seconds
	for _, t in self.trees do
		t.z -= dz
		if t.z < NEAR then
			local fresh = newTree(t.z + FAR - NEAR)
			t.x, t.z, t.height, t.lean = fresh.x, fresh.z, fresh.height, fresh.lean
			t.canopy, t.rootCount, t.rootSpread, t.seed = fresh.canopy, fresh.rootCount, fresh.rootSpread, fresh.seed
		end
	end
	for _, r in self.roots do
		r.z -= dz
		if r.z < NEAR then
			r.z += 60 - NEAR
		end
	end
	for _, r in self.ripples do
		r.z -= dz
		if r.z < NEAR then
			r.z += 70 - NEAR
			r.x = range(-RIVER_HALF, RIVER_HALF)
		end
	end
	for _, m in self.mists do
		m.z -= dz * 0.9
		if m.z < 3 then
			m.z += 90
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Drawing

local function drawSky(self: Mangroves, renderer: Renderer)
	local w, h = self.width, self.height
	local horizon = h * HORIZON
	local p = self.fill
	p.color = Color.rgb(255, 255, 255)
	p.feather = 0
	p.gradient = Gradient.linear(Vector.xy(0, 0), Vector.xy(0, horizon), {
		{ position = 0, color = mix(SKY_TOP, SKY_TOP, 0, 1) },
		{ position = 0.7, color = mix(SKY_TOP, SKY_HAZE, 0.55, 1) },
		{ position = 1, color = mix(SKY_HAZE, SKY_HAZE, 0, 1) },
	})
	local sky = Path.new()
	sky:moveTo(Vector.xy(0, 0))
	sky:lineTo(Vector.xy(w, 0))
	sky:lineTo(Vector.xy(w, horizon + 2))
	sky:lineTo(Vector.xy(0, horizon + 2))
	sky:close()
	renderer:drawPath(sky, p)
	p.gradient = nil

	-- Moon glow, smothered by the haze.
	local mx, my = self.width * self.moonX, horizon * 0.42
	for i, r in { 160, 70, 18 } do
		local glow = Path.new()
		addEllipse(glow, mx, my, r, r)
		p.color = mix(MOON, MOON, 0, ({ 0.07, 0.12, 0.55 })[i])
		p.feather = r * ({ 1.6, 1.2, 0.6 })[i]
		renderer:drawPath(glow, p)
	end
	p.feather = 0

	for _, s in self.stars do
		local tw = 0.45 + 0.4 * math.sin(self.time * 1.7 + s.phase)
		local dot = Path.new()
		addEllipse(dot, s.x * w, s.y * h, s.r, s.r)
		p.color = mix(0xCFE3DC, 0xCFE3DC, 0, tw * (1 - s.y / (h * HORIZON)) * 0.9)
		renderer:drawPath(dot, p)
	end
end

-- The far forest on the horizon, and its reflection.
local function drawTreeline(self: Mangroves, renderer: Renderer)
	local w, h = self.width, self.height
	local horizon = h * HORIZON
	local n = #self.treeline
	local p = self.fill
	for pass = 1, 2 do
		local dir = if pass == 1 then -1 else 1
		local path = Path.new()
		path:moveTo(Vector.xy(0, horizon))
		for i, th in self.treeline do
			local x = (i - 1) / (n - 1) * w
			-- Rounded crowns: a bump between samples.
			local y = horizon + dir * th * h * (if pass == 1 then 1 else 0.75)
			path:lineTo(Vector.xy(x, y))
		end
		path:lineTo(Vector.xy(w, horizon))
		path:close()
		p.color = if pass == 1 then mix(FOG, TREE, 0.35, 1) else mix(WATER_FAR, TREE, 0.3, 0.75)
		p.feather = if pass == 1 then 1.5 else 4
		renderer:drawPath(path, p)
	end
	p.feather = 0
end

local function drawWater(self: Mangroves, renderer: Renderer)
	local w, h = self.width, self.height
	local horizon = h * HORIZON
	local p = self.fill
	p.color = Color.rgb(255, 255, 255)
	p.gradient = Gradient.linear(Vector.xy(0, horizon), Vector.xy(0, h), {
		{ position = 0, color = mix(WATER_FAR, WATER_FAR, 0, 1) },
		{ position = 0.35, color = mix(WATER_FAR, WATER_NEAR, 0.6, 1) },
		{ position = 1, color = mix(WATER_NEAR, WATER_NEAR, 0, 1) },
	})
	local water = Path.new()
	water:moveTo(Vector.xy(0, horizon))
	water:lineTo(Vector.xy(w, horizon))
	water:lineTo(Vector.xy(w, h))
	water:lineTo(Vector.xy(0, h))
	water:close()
	renderer:drawPath(water, p)
	p.gradient = nil

	-- The moon's path on the water: broken shimmering dashes, wider near.
	local mx = self.width * self.moonX
	local t = self.time
	for i = 1, 26 do
		local f = i / 26
		local y = horizon + 4 + (h - horizon) * f ^ 1.7 * 0.85
		local spread = 6 + 90 * f
		local wobble = math.sin(t * 1.3 + i * 1.7) * spread * 0.35
		local len = spread * (0.5 + 0.5 * math.sin(t * 2.1 + i * 2.3))
		local dash = Path.new()
		addEllipse(dash, mx + wobble, y, math.max(2, len), 1 + 2.2 * f)
		p.color = mix(MOON, MOON, 0, (0.18 + 0.2 * math.sin(t * 3 + i)) * (1 - f * 0.6))
		p.feather = 2 + 4 * f
		renderer:drawPath(dash, p)
	end

	-- Ripples on the river: thin light streaks streaming toward the camera.
	local s = self.stroke
	s.cap = 'round'
	for _, r in self.ripples do
		local x1, y1, sc = project(self, r.x - r.len * 0.5, 0, r.z)
		local x2 = project(self, r.x + r.len * 0.5, 0, r.z)
		if y1 > horizon and y1 < h + 4 then
			local fade = 1 - fogAt(self, r.z)
			s.thickness = math.max(0.5, 0.025 * sc)
			s.color = mix(0x9FC2B8, 0x9FC2B8, 0, 0.16 * fade)
			s.feather = 0
			local line = Path.new()
			line:moveTo(Vector.xy(x1, y1))
			line:lineTo(Vector.xy(x2, y1))
			renderer:drawPath(line, s)
		end
	end
end

-- One mangrove, at world (t.x, 0, t.z). `mirror` draws its reflection.
local function drawTree(self: Mangroves, renderer: Renderer, t: Tree, mirror: boolean)
	local z = t.z
	if z < NEAR or z > FAR then
		return
	end
	local fogT = fogAt(self, z)
	local ysign = if mirror then -1 else 1
	-- A reflection is a darker shape on the water, fading into the far water.
	local alpha = if mirror then 0.45 * (1 - fogT * 0.7) else 1
	local wob = if mirror then math.sin(self.time * 1.6 + t.seed) * 0.08 else 0
	local function P(x: number, y: number): (number, number, number)
		return project(self, x + wob * y, y * ysign, z)
	end

	local _, _, sc = P(t.x, 0)
	local rootTop = 1.2 + 0.15 * (t.seed % 5)
	local topX = t.x + t.lean * t.height
	local s = self.stroke
	s.cap = 'round'
	s.feather = 0
	local fogInto = if mirror then WATER_FAR else FOG
	s.color = mix(TREE, fogInto, fogT, alpha)

	-- Stilt roots: arcs from the trunk out and down into the mud or water.
	local rng = t.seed
	for i = 1, t.rootCount do
		rng = (rng * 1103515245 + 12345) % 2147483648
		local spread = t.rootSpread * (0.5 + 0.5 * (rng % 1000) / 1000)
		local dir = if i % 2 == 0 then 1 else -1
		local footX = t.x + dir * spread
		local startY = rootTop * (0.55 + 0.45 * ((rng % 97) / 97))
		local ax, ay = P(t.x + t.lean * startY, startY)
		local cx, cy = P(t.x + dir * spread * 0.85, startY * 1.05)
		local fx, fy = P(footX, 0)
		local root = Path.new()
		root:moveTo(Vector.xy(ax, ay))
		root:cubicTo(Vector.xy(cx, cy), Vector.xy(fx, fy - (ay - fy) * 0.25), Vector.xy(fx, fy))
		s.thickness = math.max(0.6, 0.07 * sc)
		renderer:drawPath(root, s)
	end

	-- Trunk, leaning, with a slight bend.
	local tx0, ty0 = P(t.x, rootTop * 0.6)
	local tmx, tmy = P(t.x + t.lean * t.height * 0.4, t.height * 0.55)
	local tx1, ty1 = P(topX, t.height)
	local trunk = Path.new()
	trunk:moveTo(Vector.xy(tx0, ty0))
	-- (quadTo draws nothing in some renderers; a cubic with both handles on
	-- the bend point gives the same curve.)
	trunk:cubicTo(Vector.xy(tmx, tmy), Vector.xy(tmx, tmy), Vector.xy(tx1, ty1))
	s.thickness = math.max(0.8, 0.22 * sc)
	renderer:drawPath(trunk, s)
	-- A couple of branches up into the crown.
	for b = -1, 1, 2 do
		local bx0, by0 = P(t.x + t.lean * t.height * 0.7, t.height * 0.7)
		local bx1, by1 = P(topX + b * t.canopy * 0.7, t.height * 0.95)
		local branch = Path.new()
		branch:moveTo(Vector.xy(bx0, by0))
		branch:lineTo(Vector.xy(bx1, by1))
		s.thickness = math.max(0.6, 0.09 * sc)
		renderer:drawPath(branch, s)
	end

	-- Crown: a dense mass of dark leaf clusters, soft only at the edges.
	local f = self.fill
	f.color = if mirror then mix(TREE, WATER_FAR, fogT, alpha) else mix(CANOPY, FOG, fogT * 0.85, alpha)
	for k = 0, 8 do
		local a = t.seed * 0.37 + k * 2.39
		local spread = t.canopy * (0.25 + 0.75 * ((k * 7 + t.seed) % 10) / 10)
		local ox = math.cos(a) * spread
		local oy = t.height + 0.2 + math.sin(a) * spread * 0.45
		local cx, cy = P(topX + ox, oy)
		local r = t.canopy * (0.32 + 0.06 * ((t.seed + k) % 4)) * sc
		local blob = Path.new()
		addEllipse(blob, cx, cy, r, r * 0.7)
		f.feather = r * (0.12 + 0.3 * fogT)
		renderer:drawPath(blob, f)
	end
	f.feather = 0
end

-- Mud along both banks, strip by strip so it fogs with distance, with
-- breathing roots sticking up.
local function drawBanks(self: Mangroves, renderer: Renderer)
	local f = self.fill
	local edges = { 1.4, 2, 3, 4.5, 7, 11, 17, 26, 40, 60, 90, FAR }
	for side = -1, 1, 2 do
		for i = #edges - 1, 1, -1 do
			local z0, z1 = edges[i], edges[i + 1]
			local ex0, ey0 = project(self, side * RIVER_HALF, 0, z0)
			local ex1, ey1 = project(self, side * RIVER_HALF, 0, z1)
			local ox0 = project(self, side * (RIVER_HALF + 60), 0, z0)
			local ox1 = project(self, side * (RIVER_HALF + 60), 0, z1)
			local strip = Path.new()
			strip:moveTo(Vector.xy(ex0, ey0))
			strip:lineTo(Vector.xy(ex1, ey1))
			strip:lineTo(Vector.xy(ox1, ey1))
			strip:lineTo(Vector.xy(ox0, ey0))
			strip:close()
			f.color = mix(MUD, FOG, fogAt(self, (z0 + z1) * 0.5), 1)
			f.feather = 0
			renderer:drawPath(strip, f)
		end
	end
	-- A soft wet edge where mud meets water.
	local s = self.stroke
	s.cap = 'round'
	for side = -1, 1, 2 do
		local edge = Path.new()
		local first = true
		for _, z in edges do
			local x, y = project(self, side * RIVER_HALF, 0, z)
			if first then
				edge:moveTo(Vector.xy(x, y))
				first = false
			else
				edge:lineTo(Vector.xy(x, y))
			end
		end
		s.thickness = 2
		s.feather = 6
		s.color = mix(0x2C4A44, 0x2C4A44, 0, 0.18)
		renderer:drawPath(edge, s)
	end
	s.feather = 0
	-- Pneumatophores: the mangroves' breathing roots, pencil spikes in mud.
	for _, r in self.roots do
		local x0, y0, sc = project(self, r.x, 0, r.z)
		local x1, y1 = project(self, r.x, r.h, r.z)
		s.thickness = math.max(0.5, 0.03 * sc)
		s.color = mix(TREE, FOG, fogAt(self, r.z), 0.9)
		local spike = Path.new()
		spike:moveTo(Vector.xy(x0, y0))
		spike:lineTo(Vector.xy(x1, y1))
		renderer:drawPath(spike, s)
	end
end

local function drawMist(self: Mangroves, renderer: Renderer)
	local amount = math.clamp(self.mist, 0, 1)
	if amount <= 0 then
		return
	end
	local f = self.fill
	for _, m in self.mists do
		local drift = math.sin(self.time * 0.12 + m.phase) * 3
		local cx, cy, sc = project(self, m.x + drift, m.h * 0.6, m.z)
		local rx, ry = m.w * 0.5 * sc, m.h * sc
		local fade = 1 - fogAt(self, m.z) * 0.5
		local near = math.clamp((m.z - 3) / 8, 0, 1)
		local blob = Path.new()
		addEllipse(blob, cx, cy, rx, ry)
		f.color = mix(0x6E8F86, 0x6E8F86, 0, 0.06 * amount * fade * near)
		f.feather = math.max(rx, ry) * 0.9
		renderer:drawPath(blob, f)
	end
	f.feather = 0
end

function draw(self: Mangroves, renderer: Renderer)
	-- Far to near, so nearer things cover farther ones.
	table.sort(self.trees, function(a: Tree, b: Tree)
		return a.z > b.z
	end)
	drawSky(self, renderer)
	drawTreeline(self, renderer)
	drawWater(self, renderer)
	for _, t in self.trees do
		drawTree(self, renderer, t, true)
	end
	drawBanks(self, renderer)
	for _, t in self.trees do
		drawTree(self, renderer, t, false)
	end
	drawMist(self, renderer)
end

return function(): Node<Mangroves>
	return {
		width = 1280,
		height = 720,
		speed = 1.2,
		fog = 0.5,
		mist = 1,
		moonX = 0.62,

		time = 0,
		trees = {},
		roots = {},
		ripples = {},
		mists = {},
		stars = {},
		treeline = {},
		fill = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		stroke = Paint.with({ style = 'stroke', color = Color.rgb(255, 255, 255), thickness = 1, cap = 'round', join = 'round' }),

		init = init,
		advance = advance,
		draw = draw,
	}
end
