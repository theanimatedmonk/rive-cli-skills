-- Node script: the Unleash blast, centred on the node.
--
-- `burst` runs 0 -> 1 over the blast (keyed by the state machine):
-- a white-hot flash, light rays, a double shockwave ring and sparks, all
-- tinted by `energyColor`. Draws nothing at 0 and at 1.

export type Burst = {
	burst: Input<number>,
	energyColor: Input<Color>,
	size: Input<number>,

	rays: { Ray },
	sparks: { Spark },
	solid: Paint,
	stroke: Paint,
	soft: Paint,
	shaded: Paint,
}

type Ray = { angle: number, length: number, width: number }
type Spark = { angle: number, speed: number, length: number }

local KAPPA = 0.5522848

local seed = 1
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
	return 1 - (1 - clamp01(t)) ^ 3
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

function init(self: Burst, context: Context): boolean
	seed = 4242
	for i = 1, 18 do
		table.insert(self.rays, {
			angle = (i - 1) / 18 * math.pi * 2 + range(-0.12, 0.12),
			length = range(0.55, 1.0),
			width = range(0.04, 0.09),
		})
	end
	for _ = 1, 64 do
		table.insert(self.sparks, { angle = range(0, math.pi * 2), speed = range(220, 620), length = range(14, 42) })
	end
	return true
end

function draw(self: Burst, renderer: Renderer)
	local burst = clamp01(self.burst)
	if burst <= 0 or burst >= 1 then
		return
	end
	local k = math.max(self.size, 0.1)
	local grow = easeOut(burst)
	local fade = 1 - burst
	local er, eg, eb = Color.red(self.energyColor) :: number, Color.green(self.energyColor) :: number, Color.blue(self.energyColor) :: number
	local function energy(a: number): Color
		return Color.rgba(er, eg, eb, math.floor(clamp01(a) * 255))
	end
	local function hot(a: number): Color
		-- Halfway between white and the energy colour.
		return Color.rgba(
			math.floor((255 + er) / 2),
			math.floor((255 + eg) / 2),
			math.floor((255 + eb) / 2),
			math.floor(clamp01(a) * 255)
		)
	end

	-- The flash peaks almost at once, then decays.
	local flash = if burst < 0.06 then burst / 0.06 else math.max(0, 1 - (burst - 0.06) / 0.5)

	-- Light rays.
	for _, ray in self.rays do
		local len = (80 + 520 * grow) * ray.length * k
		local cs, sn = math.cos(ray.angle), math.sin(ray.angle)
		local px, py = -sn, cs
		local base = 16 * k
		local half = len * ray.width * 0.5 * (0.3 + fade)
		self.shaded.gradient = Gradient.linear(Vector.xy(cs * base, sn * base), Vector.xy(cs * len, sn * len), {
			{ position = 0, color = hot(fade * fade * 0.9) },
			{ position = 1, color = energy(0) },
		})
		local path = Path.new()
		path:moveTo(Vector.xy(cs * base + px * half * 0.3, sn * base + py * half * 0.3))
		path:lineTo(Vector.xy(cs * len + px * half, sn * len + py * half))
		path:lineTo(Vector.xy(cs * len - px * half, sn * len - py * half))
		path:lineTo(Vector.xy(cs * base - px * half * 0.3, sn * base - py * half * 0.3))
		path:close()
		renderer:drawPath(path, self.shaded)
	end

	-- Sparks.
	for _, s in self.sparks do
		local d = (20 + s.speed * grow) * k
		local cs, sn = math.cos(s.angle), math.sin(s.angle)
		local len = s.length * (0.4 + fade) * k
		self.stroke.thickness = 2 * fade + 0.4
		self.stroke.color = hot(fade * 1.2)
		local path = Path.new()
		path:moveTo(Vector.xy(cs * d, sn * d * 0.8))
		path:lineTo(Vector.xy(cs * (d - len), sn * (d - len) * 0.8))
		renderer:drawPath(path, self.stroke)
	end

	-- Two shockwaves, the second trailing the first.
	for n, lag in { 0, 0.18 } do
		local g = easeOut(clamp01((burst - lag) / (1 - lag)))
		local f = 1 - clamp01((burst - lag) / (1 - lag))
		if g > 0 and f > 0 then
			local radius = (40 + 520 * g) * k
			local halo = Path.new()
			addCircle(halo, 0, 0, radius)
			self.soft.thickness = (12 + 22 * f) * k
			self.soft.feather = 16 * k
			self.soft.color = energy(f * (if n == 1 then 0.55 else 0.3))
			renderer:drawPath(halo, self.soft)
			local line = Path.new()
			addCircle(line, 0, 0, radius)
			self.stroke.thickness = 1.5 + 2.5 * f
			self.stroke.color = hot(f * (if n == 1 then 0.95 else 0.5))
			renderer:drawPath(line, self.stroke)
		end
	end

	-- Core flash and a brief white-out.
	if flash > 0.01 then
		local radius = (90 + 420 * grow) * k
		self.shaded.gradient = Gradient.radial(Vector.xy(0, 0), radius, {
			{ position = 0, color = Color.rgba(255, 255, 255, math.floor(flash * 255)) },
			{ position = 0.3, color = hot(flash * 0.85) },
			{ position = 0.7, color = energy(flash * 0.35) },
			{ position = 1, color = energy(0) },
		})
		local core = Path.new()
		addCircle(core, 0, 0, radius)
		renderer:drawPath(core, self.shaded)
		local whiteout = flash * flash * flash * 0.55
		if whiteout > 0.01 then
			self.solid.color = Color.rgba(235, 248, 255, math.floor(whiteout * 255))
			local screen = Path.new()
			screen:moveTo(Vector.xy(-2000, -2000))
			screen:lineTo(Vector.xy(2000, -2000))
			screen:lineTo(Vector.xy(2000, 2000))
			screen:lineTo(Vector.xy(-2000, 2000))
			screen:close()
			renderer:drawPath(screen, self.solid)
		end
	end
end

return function(): Node<Burst>
	return {
		burst = 0,
		energyColor = Color.rgb(63, 182, 255),
		size = 1,

		rays = {},
		sparks = {},
		solid = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		stroke = Paint.with({ style = 'stroke', cap = 'round', thickness = 2, color = Color.rgb(255, 255, 255) }),
		soft = Paint.with({ style = 'stroke', thickness = 12, color = Color.rgb(255, 255, 255) }),
		shaded = Paint.with({ style = 'fill' }),

		init = init,
		draw = draw,
	}
end
