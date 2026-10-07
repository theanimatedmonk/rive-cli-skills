-- Node script: the living sky behind the whole artboard.
--
-- Layers, back to front:
--   stardust clouds  large feathered vector ellipses, translucent glows that
--                    build up where they overlap, with a few dark patches
--                    for depth; plain paths with normal blending (no GPU
--                    canvas, shader or blend mode), so every runtime and
--                    backend renders them the same (a screen blend came out
--                    hot pink on Android Vulkan)
--   stardust         ~2600 tiny dots scattered by a noise field so they clump
--                    into grainy wisps (the shader's grain, as vectors);
--                    built once into a few static paths, then only moved,
--                    twinkled and recoloured each frame
--   stars            twinkling points and four-point sparkles
--   comets           occasional streaks falling across the sky
--
-- `heat` (0..1) is keyed while the card charges: the clouds swing to hot
-- colours and swirl faster, stars flare, and comets fall more often.
-- `blast` (0..1) is keyed on the explosion and pushes the clouds away from
-- the card. `mist` and `grain` scale the haze and the grain/sand texture.
-- The cursor pushes stars and clouds out of its way within `cursorRadius`,
-- by `cursorStrength`; they ease back when it leaves.
-- Place it at the artboard origin, drawn behind everything.

type Star = {
	x: number,
	y: number,
	ox: number, -- current cursor displacement
	oy: number,
	size: number,
	phase: number,
	rate: number,
	sparkle: boolean,
}
type Comet = {
	active: boolean,
	x: number,
	y: number,
	vx: number,
	vy: number,
	life: number,
	age: number,
	length: number,
	warm: boolean,
}

export type Nebula = {
	width: Input<number>,
	height: Input<number>,
	heat: Input<number>,
	focusY: Input<number>,
	blast: Input<number>,
	grain: Input<number>,
	mist: Input<number>,
	cursorRadius: Input<number>,
	cursorStrength: Input<number>,

	time: number,
	stars: { Star },
	comets: { Comet },
	nextComet: number,

	-- Cursor: raw target, smoothed position, and presence (0 away, 1 over).
	pointerX: number,
	pointerY: number,
	cursorX: number,
	cursorY: number,
	cursorOn: boolean,
	presence: number,

	clouds: { Cloud },
	cloudPaint: Paint,
	dust: { Path }, -- one path per tint x twinkle group
	dustPaint: Paint,
	solid: Paint,
	trail: Paint,
}

type Cloud = {
	x: number,
	y: number,
	rx: number,
	ry: number,
	rotation: number,
	phase: number,
	speed: number,
	tint: number, -- index into the palettes
	alpha: number,
	dark: boolean,
}

-- Cool sky (heat 0) and charged sky (heat 1), as 0xRRGGBB.
local COOL = { 0x3B2A7A, 0x5A3FA6, 0x7A3FA0, 0x2E3F8F, 0x8A4FBF }
local HOT = { 0xC2410C, 0xE05A47, 0xF59E42, 0xB83280, 0xE8C27A }
local DARK = 0x07050F

-- Stardust: tints (cool, hot) and how the dots split into twinkle groups.
local DUST_COOL = { 0xB9A6FF, 0x8F7BE8, 0xE2B8FF, 0xA9C4FF }
local DUST_HOT = { 0xFFC27A, 0xFF8A5C, 0xFFD9A8, 0xF7A6C8 }
local DUST_GROUPS = 3
local DUST_COUNT = 2600

-- Value noise and fractal noise (0..1) for where the dust gathers.
local function hash2(x: number, y: number): number
	local n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
	return n - math.floor(n)
end

local function valueNoise(x: number, y: number): number
	local ix, iy = math.floor(x), math.floor(y)
	local fx, fy = x - ix, y - iy
	local ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	local a = hash2(ix, iy)
	local b = hash2(ix + 1, iy)
	local c = hash2(ix, iy + 1)
	local d = hash2(ix + 1, iy + 1)
	return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
end

local function fbm(x: number, y: number): number
	local v, amp, freq = 0, 0.5, 1
	for _ = 1, 4 do
		v += amp * valueNoise(x * freq, y * freq)
		freq *= 2.03
		amp *= 0.5
	end
	return v
end
local KAPPA = 0.5522848

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

local function rgba(r: number, g: number, b: number, a: number): Color
	return Color.rgba(math.floor(r), math.floor(g), math.floor(b), math.floor(255 * clamp01(a)))
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
	local w = r * 0.22
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

-- Tiny square dot (cheaper than a circle at this size).
local function addDot(path: Path, x: number, y: number, r: number)
	path:moveTo(Vector.xy(x - r, y - r))
	path:lineTo(Vector.xy(x + r, y - r))
	path:lineTo(Vector.xy(x + r, y + r))
	path:lineTo(Vector.xy(x - r, y + r))
	path:close()
end

-- Scatter the dust once: accept points where the noise is dense (more
-- around the card band), plus a sparse sprinkle everywhere.
local function buildDust(self: Nebula)
	local w, h = self.width, self.height
	self.dust = {}
	for _ = 1, #DUST_COOL * DUST_GROUPS do
		table.insert(self.dust, Path.new())
	end
	local placed, tries = 0, 0
	while placed < DUST_COUNT and tries < DUST_COUNT * 30 do
		tries += 1
		local x, y = range(0, w), range(0, h)
		local n = fbm(x / 150 + 3.1, y / 150 + 7.7)
		local band = math.exp(-((y - self.focusY) / (h * 0.32)) ^ 2)
		local density = math.clamp((n - 0.42) / 0.3, 0, 1) * (0.55 + 0.45 * band) + 0.06
		if rand() < density then
			placed += 1
			local tint = math.floor(rand() * #DUST_COOL)
			local group = math.floor(rand() * DUST_GROUPS)
			local r = if rand() < 0.85 then range(0.35, 0.75) else range(0.8, 1.3)
			addDot(self.dust[tint * DUST_GROUPS + group + 1], x, y, r)
		end
	end
end

local function build(self: Nebula)
	seed = 844390
	local w, h = self.width, self.height
	for i = 1, 90 do
		table.insert(self.stars, {
			x = range(4, w - 4),
			y = range(4, h - 4),
			ox = 0,
			oy = 0,
			size = if i % 9 == 0 then range(4, 7) else range(0.8, 2.0),
			phase = range(0, math.pi * 2),
			rate = range(0.6, 2.4),
			sparkle = i % 9 == 0,
		})
	end
	for _ = 1, 5 do
		table.insert(self.comets, {
			active = false, x = 0, y = 0, vx = 0, vy = 0,
			life = 1, age = 0, length = 60, warm = false,
		})
	end
	self.nextComet = 1.2
	buildDust(self)

	-- Clouds: big soft glows spread over the sky, densest around the card,
	-- and a few dark lanes between them.
	for i = 1, 16 do
		local dark = i % 6 == 0
		table.insert(self.clouds, {
			x = range(-0.1, 1.1) * w,
			y = (if i % 2 == 0 then range(0.25, 0.75) else range(-0.05, 1.05)) * h,
			rx = range(90, 190),
			ry = range(60, 130),
			rotation = range(-0.8, 0.8),
			phase = range(0, math.pi * 2),
			speed = range(0.05, 0.14),
			tint = (i - 1) % #COOL + 1,
			alpha = if dark then range(0.35, 0.5) else range(0.16, 0.3),
			dark = dark,
		})
	end
end

local function launchComet(self: Nebula, heat: number)
	for _, c in self.comets do
		if not c.active then
			local w = self.width
			c.active = true
			c.x = range(w * 0.1, w * 1.15)
			c.y = range(-40, self.height * 0.35)
			local speed = range(260, 420) * (1 + 0.8 * heat)
			local angle = range(2.05, 2.45) -- down and to the left
			c.vx = math.cos(angle) * speed
			c.vy = math.sin(angle) * speed
			c.life = range(0.9, 1.5)
			c.age = 0
			c.length = range(50, 110) * (1 + 0.5 * heat)
			c.warm = heat > 0.3 or rand() > 0.6
			return
		end
	end
end

function init(self: Nebula, context: Context): boolean
	build(self)
	return true
end

-- Smoothing factor for an exponential approach at `rate` per second.
local function approach(rate: number, seconds: number): number
	return 1 - math.exp(-rate * seconds)
end

local function advanceCursor(self: Nebula, seconds: number)
	local follow = approach(14, seconds)
	self.cursorX += (self.pointerX - self.cursorX) * follow
	self.cursorY += (self.pointerY - self.cursorY) * follow
	local target = if self.cursorOn then 1 else 0
	self.presence += (target - self.presence) * approach(5, seconds)

	-- Each star springs toward its pushed-out spot, and back when the
	-- cursor leaves.
	local radius = math.max(1, self.cursorRadius)
	local amount = self.cursorStrength * self.presence
	local settle = approach(8, seconds)
	for _, st in self.stars do
		local dx, dy = st.x - self.cursorX, st.y - self.cursorY
		local d = math.sqrt(dx * dx + dy * dy)
		local tx, ty = 0, 0
		if amount > 0 and d < radius * 2.5 and d > 1e-3 then
			local push = amount * radius * 0.45 * math.exp(-(d * d) / (radius * radius))
			tx, ty = dx / d * push, dy / d * push
		end
		st.ox += (tx - st.ox) * settle
		st.oy += (ty - st.oy) * settle
	end
end

function advance(self: Nebula, seconds: number): boolean
	self.time += seconds
	advanceCursor(self, seconds)
	local heat = clamp01(self.heat)
	self.nextComet -= seconds * (1 + 4 * heat)
	if self.nextComet <= 0 then
		launchComet(self, heat)
		self.nextComet = range(1.4, 3.6)
	end
	for _, c in self.comets do
		if c.active then
			c.age += seconds
			c.x += c.vx * seconds
			c.y += c.vy * seconds
			if c.age >= c.life then
				c.active = false
			end
		end
	end
	return true
end

local function mixRgb(a: number, b: number, t: number, alpha: number): Color
	local function ch(c: number, shift: number): number
		return bit32.band(bit32.rshift(c, shift), 0xFF)
	end
	local r = ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t
	local g = ch(a, 8) + (ch(b, 8) - ch(a, 8)) * t
	local bl = ch(a, 0) + (ch(b, 0) - ch(a, 0)) * t
	return Color.rgba(math.floor(r), math.floor(g), math.floor(bl), math.floor(clamp01(alpha) * 255))
end

-- Ellipse centred on the origin.
local function addEllipse(path: Path, rx: number, ry: number)
	local kx, ky = rx * KAPPA, ry * KAPPA
	path:moveTo(Vector.xy(rx, 0))
	path:cubicTo(Vector.xy(rx, ky), Vector.xy(kx, ry), Vector.xy(0, ry))
	path:cubicTo(Vector.xy(-kx, ry), Vector.xy(-rx, ky), Vector.xy(-rx, 0))
	path:cubicTo(Vector.xy(-rx, -ky), Vector.xy(-kx, -ry), Vector.xy(0, -ry))
	path:cubicTo(Vector.xy(kx, -ry), Vector.xy(rx, -ky), Vector.xy(rx, 0))
	path:close()
end

-- The clouds: drift, swing toward ember colours with heat, get pushed off
-- by the blast and by the cursor.
local function drawClouds(self: Nebula, renderer: Renderer, heat: number)
	local mist = math.max(0, self.mist)
	if mist <= 0 then
		return
	end
	local t = self.time
	local cx, cy = self.width * 0.5, self.focusY
	local paint = self.cloudPaint
	for _, c in self.clouds do
		local x = c.x + math.sin(t * c.speed + c.phase) * 22
		local y = c.y + math.cos(t * c.speed * 0.7 + c.phase) * 14
		-- Blast: away from the card.
		local dx, dy = x - cx, y - cy
		local d = math.max(1, math.sqrt(dx * dx + dy * dy))
		x += dx / d * self.blast * 140
		y += dy / d * self.blast * 140
		-- Cursor: out of the way, easing back when it leaves.
		if self.presence > 0 then
			local px, py = x - self.cursorX, y - self.cursorY
			local pd = math.max(1, math.sqrt(px * px + py * py))
			local reach = self.cursorRadius * 2
			if pd < reach then
				local push = (1 - pd / reach) * 60 * self.cursorStrength * self.presence
				x += px / pd * push
				y += py / pd * push
			end
		end

		local breathe = 1 + 0.06 * math.sin(t * 0.3 + c.phase)
		local path = Path.new()
		addEllipse(path, c.rx * breathe, c.ry * breathe)
		if c.dark then
			paint.color = mixRgb(DARK, DARK, 0, c.alpha * math.min(mist, 1))
		else
			paint.color = mixRgb(COOL[c.tint], HOT[c.tint], heat, c.alpha * mist * (1 + 0.6 * heat))
		end
		paint.feather = math.max(c.rx, c.ry) * 0.9
		renderer:save()
		renderer:transform(Mat2D.withTranslation(x, y) * Mat2D.withRotation(c.rotation + 0.05 * math.sin(t * 0.2 + c.phase)))
		renderer:drawPath(path, paint)
		renderer:restore()
	end
end

-- The stardust: drifts slowly, twinkles by group, warms with heat, and the
-- blast blows the whole field outward from the card.
local function drawDust(self: Nebula, renderer: Renderer, heat: number)
	local grain = math.max(0, self.grain)
	if grain <= 0 or #self.dust == 0 then
		return
	end
	local t = self.time
	local cx, cy = self.width * 0.5, self.focusY
	local spread = 1 + self.blast * 0.35
	renderer:save()
	renderer:transform(
		Mat2D.withTranslation(cx + math.sin(t * 0.05) * 6, cy + math.cos(t * 0.04) * 4)
			* Mat2D.withScale(spread, spread)
			* Mat2D.withTranslation(-cx, -cy)
	)
	local paint = self.dustPaint
	for tint = 1, #DUST_COOL do
		for group = 0, DUST_GROUPS - 1 do
			local twinkle = 0.55 + 0.45 * math.sin(t * (0.9 + group * 0.35) + group * 2.1 + tint)
			local alpha = math.clamp(grain * (0.32 + 0.38 * twinkle) * (1 + 0.5 * heat), 0, 1)
			paint.color = mixRgb(DUST_COOL[tint], DUST_HOT[tint], heat, alpha)
			renderer:drawPath(self.dust[(tint - 1) * DUST_GROUPS + group + 1], paint)
		end
	end
	renderer:restore()
end

local function drawStars(self: Nebula, renderer: Renderer, heat: number)
	for _, s in self.stars do
		local tw = 0.5 + 0.5 * math.sin(self.time * s.rate * (1 + 1.5 * heat) + s.phase)
		local alpha = (0.25 + 0.75 * tw) * (0.8 + 0.2 * heat)
		local warmth = heat * 0.6
		self.solid.color = rgba(255, 245 - 40 * warmth, 225 - 110 * warmth, alpha)
		local path = Path.new()
		if s.sparkle then
			addSparkle(path, s.x + s.ox, s.y + s.oy, s.size * (0.6 + 0.6 * tw))
		else
			addCircle(path, s.x + s.ox, s.y + s.oy, s.size * (0.7 + 0.3 * tw))
		end
		renderer:drawPath(path, self.solid)
	end
end

local function drawComets(self: Nebula, renderer: Renderer)
	for _, c in self.comets do
		if c.active then
			local t = c.age / c.life
			local fade = math.min(1, t * 6) * (1 - t)
			local speed = math.sqrt(c.vx * c.vx + c.vy * c.vy)
			local dx, dy = c.vx / speed, c.vy / speed
			local r, g, b = 220, 230, 255
			if c.warm then
				r, g, b = 255, 214, 150
			end
			local steps = 10
			for k = steps, 1, -1 do
				local a0 = (k / steps) * c.length
				local a1 = ((k - 1) / steps) * c.length
				local u = 1 - (k - 0.5) / steps
				self.trail.thickness = 0.4 + 2.2 * u
				self.trail.color = rgba(r, g, b, fade * u * u)
				local path = Path.new()
				path:moveTo(Vector.xy(c.x - dx * a0, c.y - dy * a0))
				path:lineTo(Vector.xy(c.x - dx * a1, c.y - dy * a1))
				renderer:drawPath(path, self.trail)
			end
			self.solid.color = rgba(255, 255, 250, fade)
			local head = Path.new()
			addCircle(head, c.x, c.y, 1.8)
			renderer:drawPath(head, self.solid)
		end
	end
end

-- The sky follows every pointer in the artboard but never claims one, so
-- the cards' taps still land.
local function pointerMove(self: Nebula, event: PointerEvent)
	if not self.cursorOn then
		-- Enter without sweeping in from the last spot.
		self.cursorX, self.cursorY = event.position.x, event.position.y
	end
	self.pointerX, self.pointerY = event.position.x, event.position.y
	self.cursorOn = true
end

local function pointerExit(self: Nebula, event: PointerEvent)
	self.cursorOn = false
end

function draw(self: Nebula, renderer: Renderer)
	local heat = clamp01(self.heat)
	drawClouds(self, renderer, heat)
	drawDust(self, renderer, heat)
	drawStars(self, renderer, heat)
	drawComets(self, renderer)
end

return function(): Node<Nebula>
	return {
		width = 390,
		height = 844,
		heat = 0,
		focusY = 300,
		blast = 0,
		grain = 1,
		mist = 1,
		cursorRadius = 140,
		cursorStrength = 1,

		time = 0,
		stars = {},
		comets = {},
		nextComet = 1,

		pointerX = 0,
		pointerY = 0,
		cursorX = 0,
		cursorY = 0,
		cursorOn = false,
		presence = 0,

		clouds = {},
		cloudPaint = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		dust = {},
		dustPaint = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		solid = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		trail = Paint.with({ style = 'stroke', cap = 'round', thickness = 2, color = Color.rgb(255, 255, 255) }),

		init = init,
		advance = advance,
		draw = draw,
		pointerDown = pointerMove,
		pointerMove = pointerMove,
		pointerExit = pointerExit,
	}
end
