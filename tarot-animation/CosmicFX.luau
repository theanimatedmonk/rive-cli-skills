-- Node script: the cosmic reveal around the chosen card.
--
-- Two placements share this script: `layer` 0 sits behind the card, `layer` 1
-- in front of it. Comets orbit on tilted 3D ellipses, so each point of an
-- orbit is drawn by whichever layer matches its depth; that is what makes
-- them pass behind and in front of the card.
--
-- Driven by two keyed inputs:
--   charge 0..1  comets gather and accelerate, sparkles close in, aura pulses
--   burst  0..1  flash, light rays, shockwave and sparks; comets fly outward
-- Both placements are keyed identically and seeded identically, so their
-- orbits stay in step.
--
-- Everything is paths and gradients: no color modulation, which the web
-- runtime applies to the whole scene.

type Comet = {
	radius: number,
	incline: number, -- orbit plane tilt away from the screen, radians
	spin: number, -- orbit plane rotation in the screen, radians
	angle: number,
	speed: number,
	size: number,
	appear: number, -- charge at which this comet fades in
	r: number,
	g: number,
	b: number,
}

type Mote = {
	distance: number,
	angle: number,
	drift: number,
	size: number,
	twinkle: number,
	front: boolean,
}

type Ray = { angle: number, length: number, width: number }
type Spark = { angle: number, speed: number, length: number, front: boolean }

export type CosmicFX = {
	charge: Input<number>,
	burst: Input<number>,
	layer: Input<number>,

	time: number,
	comets: { Comet },
	motes: { Mote },
	rays: { Ray },
	sparks: { Spark },
	solid: Paint,
	glow: Paint,
	soft: Paint,
	shaded: Paint,
}

local TRAIL_STEPS = 16
local TAU = math.pi * 2
local KAPPA = 0.5522848

-- Deterministic so both placements build the same sky.
local seed = 0
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rand()
end

local function clamp01(x: number): number
	return math.max(0, math.min(1, x))
end

local function easeOut(t: number): number
	local u = 1 - clamp01(t)
	return 1 - u * u * u
end

local function addCircle(path: Path, cx: number, cy: number, r: number)
	local k = r * KAPPA
	path:moveTo(Vector.xy(cx + r, cy))
	path:cubicTo(Vector.xy(cx + r, cy + k), Vector.xy(cx + k, cy + r), Vector.xy(cx, cy + r))
	path:cubicTo(Vector.xy(cx - k, cy + r), Vector.xy(cx - r, cy + k), Vector.xy(cx - r, cy))
	path:cubicTo(Vector.xy(cx - r, cy - k), Vector.xy(cx - k, cy - r), Vector.xy(cx, cy - r))
	path:cubicTo(Vector.xy(cx + k, cy - r), Vector.xy(cx + r, cy - k), Vector.xy(cx + r, cy))
	path:close()
end

local function addSparkle(path: Path, cx: number, cy: number, r: number)
	local w = r * 0.28
	path:moveTo(Vector.xy(cx, cy - r))
	path:lineTo(Vector.xy(cx + w, cy - w))
	path:lineTo(Vector.xy(cx + r, cy))
	path:lineTo(Vector.xy(cx + w, cy + w))
	path:lineTo(Vector.xy(cx, cy + r))
	path:lineTo(Vector.xy(cx - w, cy + w))
	path:lineTo(Vector.xy(cx - r, cy))
	path:lineTo(Vector.xy(cx - w, cy - w))
	path:close()
end

local function rgba(r: number, g: number, b: number, a: number): Color
	return Color.rgba(math.floor(r), math.floor(g), math.floor(b), math.floor(255 * clamp01(a)))
end

-- A point on a comet's orbit: screen x, y and depth (positive = toward us).
local function orbitPoint(c: Comet, angle: number, scale: number): (number, number, number)
	local r = c.radius * scale
	local ox = r * math.cos(angle)
	local oy = r * math.sin(angle) * math.cos(c.incline)
	local oz = r * math.sin(angle) * math.sin(c.incline)
	local cs, sn = math.cos(c.spin), math.sin(c.spin)
	return ox * cs - oy * sn, ox * sn + oy * cs, oz
end

local function build(self: CosmicFX)
	seed = 20260930
	local palette = {
		{ 255, 236, 180 },
		{ 255, 214, 130 },
		{ 190, 170, 255 },
		{ 150, 220, 255 },
		{ 255, 250, 235 },
	}
	for i = 1, 9 do
		local col = palette[(i - 1) % #palette + 1]
		table.insert(self.comets, {
			radius = range(125, 190),
			incline = range(1.05, 1.35),
			spin = range(-0.7, 0.7),
			angle = range(0, TAU),
			speed = range(1.4, 2.2) * (if i % 2 == 0 then -1 else 1),
			size = range(2.2, 3.6),
			appear = (i - 1) / 9 * 0.55,
			r = col[1],
			g = col[2],
			b = col[3],
		})
	end
	for _ = 1, 44 do
		table.insert(self.motes, {
			distance = range(150, 260),
			angle = range(0, TAU),
			drift = range(-0.25, 0.25),
			size = range(1.6, 4.4),
			twinkle = range(0, TAU),
			front = rand() > 0.5,
		})
	end
	for i = 1, 20 do
		table.insert(self.rays, {
			angle = (i - 1) / 20 * TAU + range(-0.08, 0.08),
			length = range(0.55, 1.0),
			width = range(0.05, 0.11),
		})
	end
	for _ = 1, 56 do
		table.insert(self.sparks, {
			angle = range(0, TAU),
			speed = range(160, 420),
			length = range(8, 22),
			front = rand() > 0.35,
		})
	end
end

function init(self: CosmicFX, context: Context): boolean
	build(self)
	return true
end

function advance(self: CosmicFX, seconds: number): boolean
	self.time += seconds
	-- Comets speed up sharply as the charge builds.
	local charge = clamp01(self.charge)
	local boost = 0.35 + 5.5 * charge * charge
	for _, c in self.comets do
		c.angle += c.speed * boost * seconds
	end
	for _, m in self.motes do
		m.angle += m.drift * (1 + 3 * charge) * seconds
	end
	return true
end

local function drawAura(self: CosmicFX, renderer: Renderer, charge: number, burst: number)
	local pulse = 0.75 + 0.25 * math.sin(self.time * (6 + 18 * charge))
	local alpha = 0.55 * charge * pulse * (1 - burst)
	if alpha <= 0.01 then
		return
	end
	local radius = 150 + 50 * charge
	self.shaded.gradient = Gradient.radial(Vector.xy(0, 0), radius, {
		{ position = 0, color = rgba(255, 220, 140, alpha) },
		{ position = 0.45, color = rgba(200, 150, 255, alpha * 0.45) },
		{ position = 1, color = rgba(120, 80, 220, 0) },
	})
	local path = Path.new()
	addCircle(path, 0, 0, radius)
	renderer:drawPath(path, self.shaded)
end

local function drawMotes(self: CosmicFX, renderer: Renderer, front: boolean, charge: number, burst: number)
	local visible = charge * (1 - burst)
	if visible <= 0.01 then
		return
	end
	local pull = 1 - 0.25 * charge
	for _, m in self.motes do
		if m.front == front then
			local d = m.distance * pull * (1 + 1.6 * easeOut(burst))
			local x = d * math.cos(m.angle)
			local y = d * math.sin(m.angle) * 1.15
			local tw = 0.5 + 0.5 * math.sin(self.time * 5 + m.twinkle)
			self.solid.color = rgba(255, 244, 214, visible * (0.35 + 0.65 * tw))
			local path = Path.new()
			addSparkle(path, x, y, m.size * (0.7 + 0.6 * tw))
			renderer:drawPath(path, self.solid)
		end
	end
end

local function drawComets(self: CosmicFX, renderer: Renderer, front: boolean, charge: number, burst: number)
	local scatter = 1 + 2.2 * easeOut(burst)
	local fadeOut = 1 - clamp01(burst * 1.6)
	local trailArc = 0.55 + 1.3 * charge
	for _, c in self.comets do
		local presence = clamp01((charge - c.appear) / 0.2) * fadeOut
		if presence > 0.01 then
			local dir = if c.speed > 0 then 1 else -1
			-- Trail: segments from the tail forward, thinning and fading.
			for k = TRAIL_STEPS, 1, -1 do
				local a0 = c.angle - dir * trailArc * k / TRAIL_STEPS
				local a1 = c.angle - dir * trailArc * (k - 1) / TRAIL_STEPS
				local x0, y0, z0 = orbitPoint(c, a0, scatter)
				local x1, y1, z1 = orbitPoint(c, a1, scatter)
				if (z0 + z1 > 0) == front then
					local t = 1 - (k - 0.5) / TRAIL_STEPS
					self.glow.thickness = c.size * (0.25 + 1.5 * t)
					self.glow.color = rgba(c.r, c.g, c.b, presence * t * t * 0.9)
					local path = Path.new()
					path:moveTo(Vector.xy(x0, y0))
					path:lineTo(Vector.xy(x1, y1))
					renderer:drawPath(path, self.glow)
				end
			end
			-- Head: soft halo and a hot core.
			local hx, hy, hz = orbitPoint(c, c.angle, scatter)
			if (hz > 0) == front then
				local halo = c.size * (2.6 + 1.4 * charge)
				self.shaded.gradient = Gradient.radial(Vector.xy(hx, hy), halo, {
					{ position = 0, color = rgba(c.r, c.g, c.b, presence * 0.85) },
					{ position = 1, color = rgba(c.r, c.g, c.b, 0) },
				})
				local glowPath = Path.new()
				addCircle(glowPath, hx, hy, halo)
				renderer:drawPath(glowPath, self.shaded)
				self.solid.color = rgba(255, 255, 250, presence)
				local core = Path.new()
				addCircle(core, hx, hy, c.size * 0.75)
				renderer:drawPath(core, self.solid)
			end
		end
	end
end

local function drawBurst(self: CosmicFX, renderer: Renderer, front: boolean, burst: number)
	if burst <= 0 or burst >= 1 then
		return
	end
	local grow = easeOut(burst)
	local fade = 1 - burst

	-- Sparks flying outward, both layers.
	for _, s in self.sparks do
		if s.front == front then
			local d = 24 + s.speed * grow
			local cs, sn = math.cos(s.angle), math.sin(s.angle)
			local len = s.length * (0.4 + fade)
			self.glow.thickness = 2.2 * fade + 0.4
			self.glow.color = rgba(255, 236, 190, fade * 1.2)
			local path = Path.new()
			path:moveTo(Vector.xy(cs * d, sn * d * 0.85))
			path:lineTo(Vector.xy(cs * (d - len), sn * (d - len) * 0.85))
			renderer:drawPath(path, self.glow)
		end
	end

	if not front then
		return
	end

	-- The flash peaks almost at once, then decays.
	local flash = if burst < 0.07 then burst / 0.07 else math.max(0, 1 - (burst - 0.07) / 0.55)

	-- Light rays.
	local rayAlpha = fade * fade
	for _, ray in self.rays do
		local len = (90 + 420 * grow) * ray.length
		local cs, sn = math.cos(ray.angle), math.sin(ray.angle)
		local px, py = -sn, cs
		local base = 18
		local half = len * ray.width * 0.5 * (0.3 + fade)
		self.shaded.gradient = Gradient.linear(Vector.xy(cs * base, sn * base), Vector.xy(cs * len, sn * len), {
			{ position = 0, color = rgba(255, 250, 230, rayAlpha * 0.9) },
			{ position = 1, color = rgba(255, 210, 120, 0) },
		})
		local path = Path.new()
		path:moveTo(Vector.xy(cs * base + px * half * 0.3, sn * base + py * half * 0.3))
		path:lineTo(Vector.xy(cs * len + px * half, sn * len + py * half))
		path:lineTo(Vector.xy(cs * len - px * half, sn * len - py * half))
		path:lineTo(Vector.xy(cs * base - px * half * 0.3, sn * base - py * half * 0.3))
		path:close()
		renderer:drawPath(path, self.shaded)
	end

	-- Shockwave ring.
	local ringRadius = 40 + 330 * grow
	local halo = Path.new()
	addCircle(halo, 0, 0, ringRadius)
	self.soft.thickness = 10 + 18 * fade
	self.soft.feather = 14
	self.soft.color = rgba(255, 200, 120, fade * 0.45)
	renderer:drawPath(halo, self.soft)
	local ring = Path.new()
	addCircle(ring, 0, 0, ringRadius)
	self.glow.thickness = 1.5 + 2.5 * fade
	self.glow.color = rgba(255, 244, 214, fade * 0.95)
	renderer:drawPath(ring, self.glow)

	-- Core flash.
	if flash > 0.01 then
		local radius = 80 + 380 * grow
		self.shaded.gradient = Gradient.radial(Vector.xy(0, 0), radius, {
			{ position = 0, color = rgba(255, 255, 255, flash) },
			{ position = 0.3, color = rgba(255, 238, 190, flash * 0.85) },
			{ position = 0.65, color = rgba(255, 196, 110, flash * 0.35) },
			{ position = 1, color = rgba(255, 180, 90, 0) },
		})
		local core = Path.new()
		addCircle(core, 0, 0, radius)
		renderer:drawPath(core, self.shaded)

		-- A brief white-out over the whole screen for the "boom".
		local whiteout = flash * flash * flash * 0.7
		if whiteout > 0.01 then
			self.solid.color = rgba(255, 250, 240, whiteout)
			local screen = Path.new()
			screen:moveTo(Vector.xy(-1200, -1200))
			screen:lineTo(Vector.xy(1200, -1200))
			screen:lineTo(Vector.xy(1200, 1200))
			screen:lineTo(Vector.xy(-1200, 1200))
			screen:close()
			renderer:drawPath(screen, self.solid)
		end
	end
end

function draw(self: CosmicFX, renderer: Renderer)
	local charge = clamp01(self.charge)
	local burst = clamp01(self.burst)
	if charge <= 0 and burst <= 0 then
		return
	end
	local front = self.layer >= 0.5
	if not front then
		drawAura(self, renderer, charge, burst)
	end
	drawMotes(self, renderer, front, charge, burst)
	drawComets(self, renderer, front, charge, burst)
	drawBurst(self, renderer, front, burst)
end

return function(): Node<CosmicFX>
	return {
		charge = 0,
		burst = 0,
		layer = 1,

		time = 0,
		comets = {},
		motes = {},
		rays = {},
		sparks = {},
		solid = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		glow = Paint.with({ style = 'stroke', cap = 'round', thickness = 2, color = Color.rgb(255, 255, 255) }),
		soft = Paint.with({ style = 'stroke', thickness = 12, feather = 14, color = Color.rgb(255, 255, 255) }),
		shaded = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),

		init = init,
		advance = advance,
		draw = draw,
	}
end
