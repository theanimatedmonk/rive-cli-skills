-- Aura node: a soft mist and floating glowing particles around the card.
-- Place it at the artboard's top-left, behind Card3D, sized to the artboard.
--
--   mist       AuraMist.wgsl at half resolution: drifting fog hugging the
--              card's rounded outline
--   particles  soft glowing circles, each on a slow orbit around the card,
--              bobbing, held near its home spot by a spring
--
-- When the view model's `flip` trigger fires, every particle is kicked
-- outward and springs back (with a little overshoot), the mist is blown
-- outward and a shockwave ring runs out from the card, then all settles.
--
-- Colours follow the card's colour scheme (the colour scheme helpers below): the mist runs
-- from a mid-tone of the base hue to a tint of the scheme's second hue, and
-- each particle glows in a tint of one of the scheme's hues. Without a
-- scheme on the view model, auraColor and sparkColor are used.
--
-- Inputs: width, height (artboard), cardX, cardY (card centre), cardWidth,
-- cardHeight, cardCorner (the card as drawn), count (particles), mist
-- (0-100), reach (px), auraColor, sparkColor, burst (kick strength).

-- Colour scheme helpers (the same block is in Card3D, Madhubani and Aura;
-- keep them in step). A scheme is a colour-harmony rule plus a base hue
-- (`harmony` and `baseHue` on the view model, next to `photo`). Colours are
-- made in OKLCH, which is perceptually uniform: equal lightness and chroma
-- look equally light and vivid at every hue, so harmony hues come out
-- balanced. Inlined rather than a shared module: a required module upset
-- the editor's script types on push.
local Harmony = {}

-- Hue offsets from the base hue, in degrees.
Harmony.SCHEMES = {
	{ 0, 180 }, -- 0 complementary
	{ -30, 0, 30 }, -- 1 analogous
	{ 0, 150, 210 }, -- 2 split-complementary
	{ 0, 120, 240 }, -- 3 triadic
	{ 0, 90, 180, 270 }, -- 4 tetradic (square)
	{ 0, 60, 180, 240 }, -- 5 tetradic (rectangle)
}

-- The print's seven ink slots cycle through the scheme's hues, so
-- neighbouring slots (a region's ink and its accent) are always different
-- harmony hues, at varied lightness: tints and shades of the scheme.
local SLOT_LIGHTNESS = { 0.66, 0.80, 0.58, 0.86, 0.72, 0.62, 0.78 }
local SLOT_CHROMA = 0.19

-- OKLCH (L 0..1, C, hue degrees) to sRGB 0..1. Out-of-gamut colours lose
-- chroma until they fit, rather than clipping (which shifts the hue).
function Harmony.oklch(L: number, C: number, h: number): (number, number, number)
	local function encode(x: number): number
		if x <= 0.0031308 then
			return 12.92 * x
		end
		return 1.055 * x ^ (1 / 2.4) - 0.055
	end
	local rad = math.rad(h)
	local chroma = C
	local r, g, b = 0, 0, 0
	for _ = 1, 24 do
		local a, bb = chroma * math.cos(rad), chroma * math.sin(rad)
		local l_ = (L + 0.3963377774 * a + 0.2158037573 * bb) ^ 3
		local m_ = (L - 0.1055613458 * a - 0.0638541728 * bb) ^ 3
		local s_ = (L - 0.0894841775 * a - 1.2914855480 * bb) ^ 3
		r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
		g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
		b = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_
		if r >= -0.001 and r <= 1.001 and g >= -0.001 and g <= 1.001 and b >= -0.001 and b <= 1.001 then
			break
		end
		chroma *= 0.9
	end
	return encode(math.clamp(r, 0, 1)), encode(math.clamp(g, 0, 1)), encode(math.clamp(b, 0, 1))
end

-- The same, as a Rive Color with an optional alpha (0..1).
function Harmony.color(L: number, C: number, h: number, alpha: number?): Color
	local r, g, b = Harmony.oklch(L, C, h)
	return Color.rgba(
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5),
		math.floor(math.clamp(alpha or 1, 0, 1) * 255 + 0.5)
	)
end

-- The scheme's hues, in degrees.
function Harmony.hues(scheme: number, baseHue: number): { number }
	local offsets = Harmony.SCHEMES[math.clamp(math.floor(scheme), 0, #Harmony.SCHEMES - 1) + 1]
	local out: { number } = {}
	for _, o in offsets do
		table.insert(out, baseHue + o)
	end
	return out
end

-- The print's palette: ink, paper, then seven inks, as { r, g, b } in 0..1.
function Harmony.palette(scheme: number, baseHue: number): { { number } }
	local hues = Harmony.hues(scheme, baseHue)
	local out: { { number } } = {}
	-- Near-black tinted toward the complement; paper a pale tint of the base.
	table.insert(out, { Harmony.oklch(0.2, 0.03, baseHue + 180) })
	table.insert(out, { Harmony.oklch(0.95, 0.025, baseHue) })
	for i = 1, 7 do
		table.insert(out, { Harmony.oklch(SLOT_LIGHTNESS[i], SLOT_CHROMA, hues[(i - 1) % #hues + 1]) })
	end
	return out
end

-- `harmony` and `baseHue` from a view model: on it, or under `front`.
-- Returns nil when it has neither.
function Harmony.read(vm: ViewModel?): (number?, number?)
	if vm == nil then
		return nil, nil
	end
	local source = vm
	if source:getNumber('harmony') == nil then
		local front = source:getViewModel('front')
		if front == nil or front.value == nil then
			return nil, nil
		end
		source = front.value
	end
	local h = source:getNumber('harmony')
	local b = source:getNumber('baseHue')
	if h == nil or b == nil then
		return nil, nil
	end
	return h.value, b.value
end

export type Aura = {
	width: Input<number>,
	height: Input<number>,
	cardX: Input<number>,
	cardY: Input<number>,
	cardWidth: Input<number>,
	cardHeight: Input<number>,
	cardCorner: Input<number>,
	count: Input<number>,
	mist: Input<number>,
	reach: Input<number>,
	auraColor: Input<Color>,
	sparkColor: Input<Color>,
	burst: Input<number>,

	context: Context?,
	vm: ViewModel?,
	schemeKey: string,
	mistA: Color,
	mistB: Color,
	haloColors: { Color },
	coreColors: { Color },
	time: number,
	sinceFlip: number,
	watching: boolean,
	particles: { Particle },
	pipeline: GPUPipeline?,
	canvas: GPUCanvas?,
	uniforms: GPUBuffer?,
	bindings: GPUBindGroup?,
	params: buffer,
	sampler: ImageSampler,
	halo: Paint,
	core: Paint,
}

type Particle = {
	angle: number, -- position around the card, radians
	spin: number, -- orbit speed, radians per second
	offset: number, -- distance out from the card edge, px
	phase: number,
	size: number,
	tint: number, -- 0 aura colour .. 1 spark colour
	slot: number, -- which scheme hue it glows in
	x: number,
	y: number,
	vx: number,
	vy: number,
}

local MIST_SCALE = 0.5
local SPRING = 16
local DAMPING = 3.6
local KAPPA = 0.5522848

local seed = 1
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rand()
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

-- Where a particle wants to be: on a squarish loop around the card (a
-- superellipse, so it follows the card's corners), bobbing gently.
local function home(self: Aura, p: Particle): (number, number)
	local c, s = math.cos(p.angle), math.sin(p.angle)
	local rx = self.cardWidth * 0.5 + p.offset
	local ry = self.cardHeight * 0.5 + p.offset
	local x = rx * math.sign(c) * math.abs(c) ^ 0.5
	local y = ry * math.sign(s) * math.abs(s) ^ 0.5
	local bob = math.sin(self.time * 0.9 + p.phase) * 6
	local sway = math.cos(self.time * 0.6 + p.phase * 1.7) * 4
	return self.cardX + x + sway, self.cardY + y + bob
end

local function spawn(self: Aura)
	seed = 4127
	self.particles = {}
	for _ = 1, math.max(0, math.floor(self.count)) do
		local p: Particle = {
			angle = range(0, math.pi * 2),
			spin = range(-0.05, 0.05),
			-- Most hug the card; some drift further out.
			offset = range(8, 110) * (if rand() < 0.6 then 0.6 else 1),
			phase = range(0, math.pi * 2),
			size = range(1.6, 4.2),
			tint = rand(),
			slot = math.floor(range(0, 12)),
			x = 0,
			y = 0,
			vx = 0,
			vy = 0,
		}
		p.x, p.y = home(self, p)
		table.insert(self.particles, p)
	end
end

local function onFlip(self: Aura)
	self.sinceFlip = 0
	local strength = math.max(0, self.burst)
	for _, p in self.particles do
		local dx, dy = p.x - self.cardX, p.y - self.cardY
		local d = math.max(1, math.sqrt(dx * dx + dy * dy))
		local kick = range(0.6, 1.4) * strength
		local swirl = range(-0.35, 0.35) * strength
		p.vx += dx / d * kick - dy / d * swirl
		p.vy += dy / d * kick + dx / d * swirl
	end
	local ctx = self.context
	if ctx then
		ctx:markNeedsUpdate()
	end
end

-- Listens for `flip` on the card's view model (found up the data contexts).
local function watchFlip(self: Aura)
	local ctx = self.context
	if self.watching or ctx == nil then
		return
	end
	local function find(vm: ViewModel?): PropertyTrigger?
		if vm == nil then
			return nil
		end
		return vm:getTrigger('flip')
	end
	local owner: ViewModel? = ctx:viewModel()
	local trigger = find(owner)
	if trigger == nil then
		owner = ctx:rootViewModel()
		trigger = find(owner)
	end
	local dc = ctx:dataContext()
	while trigger == nil and dc do
		owner = dc:viewModel()
		trigger = find(owner)
		dc = dc:parent()
	end
	if trigger == nil then
		return
	end
	self.vm = owner
	self.watching = true
	trigger:addListener(function()
		onFlip(self)
	end)
end

local function buildMist(self: Aura, context: Context)
	local shader = context:shader('AuraMist')
	if shader == nil then
		print('Aura: shader "AuraMist" not found; drawing without mist')
		return
	end
	local ok, err = pcall(function()
		local canvas = context:gpuCanvas({
			width = math.max(1, math.floor(self.width * MIST_SCALE)),
			height = math.max(1, math.floor(self.height * MIST_SCALE)),
		})
		local pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = canvas.format } },
		})
		local uniforms = GPUBuffer.new({ size = 80, usage = 'uniform' })
		self.bindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = uniforms } },
		})
		self.canvas, self.pipeline, self.uniforms = canvas, pipeline, uniforms
	end)
	if not ok then
		print('Aura: mist unavailable: ' .. tostring(err))
		self.pipeline = nil
	end
end

function init(self: Aura, context: Context): boolean
	self.context = context
	spawn(self)
	buildMist(self, context)
	watchFlip(self)
	return true
end

-- Re-derives the colours when the scheme (or the fallback inputs) change.
local function updateColors(self: Aura)
	local harmony, baseHue = Harmony.read(self.vm)
	local key = if harmony ~= nil and baseHue ~= nil
		then `{harmony}|{baseHue}`
		else `in|{self.auraColor}|{self.sparkColor}`
	if key == self.schemeKey then
		return
	end
	self.schemeKey = key
	self.haloColors, self.coreColors = {}, {}
	if harmony ~= nil and baseHue ~= nil then
		local hues = Harmony.hues(harmony, baseHue)
		self.mistA = Harmony.color(0.66, 0.16, hues[1])
		self.mistB = Harmony.color(0.86, 0.12, hues[2] or hues[1])
		for _, h in hues do
			table.insert(self.haloColors, Harmony.color(0.68, 0.17, h))
			table.insert(self.coreColors, Harmony.color(0.92, 0.08, h))
		end
	else
		self.mistA, self.mistB = self.auraColor, self.sparkColor
		self.haloColors = { self.auraColor, self.sparkColor }
		self.coreColors = { self.sparkColor, self.sparkColor }
	end
end

function advance(self: Aura, seconds: number): boolean
	watchFlip(self)
	updateColors(self)
	local dt = math.min(seconds, 1 / 20)
	self.time += seconds
	self.sinceFlip += seconds
	if #self.particles ~= math.max(0, math.floor(self.count)) then
		spawn(self)
	end
	for _, p in self.particles do
		p.angle += p.spin * dt
		local hx, hy = home(self, p)
		p.vx += ((hx - p.x) * SPRING - p.vx * DAMPING) * dt
		p.vy += ((hy - p.y) * SPRING - p.vy * DAMPING) * dt
		p.x += p.vx * dt
		p.y += p.vy * dt
	end
	return true
end

local function lin(v: number): number
	return v / 255
end

local function writeColor(p: buffer, offset: number, c: Color)
	buffer.writef32(p, offset, lin(Color.red(c) :: number))
	buffer.writef32(p, offset + 4, lin(Color.green(c) :: number))
	buffer.writef32(p, offset + 8, lin(Color.blue(c) :: number))
	buffer.writef32(p, offset + 12, 1)
end

local function drawMist(self: Aura, renderer: Renderer)
	local pipeline, canvas, uniforms, bindings = self.pipeline, self.canvas, self.uniforms, self.bindings
	if pipeline == nil or canvas == nil or uniforms == nil or bindings == nil or canvas.width <= 0 then
		return
	end
	local s = MIST_SCALE
	local blast = math.exp(-self.sinceFlip * 1.8)
	local p = self.params
	buffer.writef32(p, 0, canvas.width)
	buffer.writef32(p, 4, canvas.height)
	buffer.writef32(p, 8, self.time)
	buffer.writef32(p, 12, blast)
	buffer.writef32(p, 16, self.cardX * s)
	buffer.writef32(p, 20, self.cardY * s)
	buffer.writef32(p, 24, self.cardWidth * 0.5 * s)
	buffer.writef32(p, 28, self.cardHeight * 0.5 * s)
	buffer.writef32(p, 32, self.cardCorner * s)
	buffer.writef32(p, 36, self.sinceFlip * 260 * s)
	buffer.writef32(p, 40, math.max(0, self.mist) / 100)
	buffer.writef32(p, 44, math.max(10, self.reach) * s)
	writeColor(p, 48, self.mistA)
	writeColor(p, 64, self.mistB)
	uniforms:write(p)

	local pass = canvas:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipeline)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()

	local image = canvas.image
	if image == nil then
		return
	end
	renderer:save()
	renderer:transform(Mat2D.withScale(self.width / canvas.width, self.height / canvas.height))
	renderer:drawImage(image, self.sampler, 'screen', 1)
	renderer:restore()
end

local function drawParticles(self: Aura, renderer: Renderer)
	-- Brighter while scattering, then back to a soft twinkle.
	local excite = math.exp(-self.sinceFlip * 1.2)
	for _, p in self.particles do
		local tw = 0.55 + 0.45 * math.sin(self.time * 2.1 + p.phase * 3)
		local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
		local glow = math.clamp(tw * 0.7 + excite * 0.5 + speed / 900, 0, 1.4)
		local r = p.size * (1 + excite * 0.6)

		local halo = Path.new()
		addCircle(halo, p.x, p.y, r * 3.2)
		local n = #self.haloColors
		if n == 0 then
			return
		end
		local slot = p.slot % n + 1
		self.halo.color = Color.opacity(self.haloColors[slot], 0.4 * glow)
		self.halo.feather = r * 4
		renderer:drawPath(halo, self.halo)

		local core = Path.new()
		addCircle(core, p.x, p.y, r)
		self.core.color = Color.opacity(self.coreColors[slot], 0.85 * math.min(glow, 1))
		renderer:drawPath(core, self.core)
	end
end

function draw(self: Aura, renderer: Renderer)
	drawMist(self, renderer)
	drawParticles(self, renderer)
end

return function(): Node<Aura>
	return {
		width = 620,
		height = 780,
		cardX = 310,
		cardY = 390,
		cardWidth = 358.5,
		cardHeight = 508.5,
		cardCorner = 24,
		count = 90,
		mist = 70,
		reach = 70,
		auraColor = Color.rgb(137, 125, 236),
		sparkColor = Color.rgb(255, 214, 150),
		burst = 650,

		context = nil,
		vm = nil,
		schemeKey = '',
		mistA = Color.rgb(137, 125, 236),
		mistB = Color.rgb(255, 214, 150),
		haloColors = {},
		coreColors = {},
		time = 0,
		sinceFlip = 100,
		watching = false,
		particles = {},
		pipeline = nil,
		canvas = nil,
		uniforms = nil,
		bindings = nil,
		params = buffer.create(80),
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		halo = Paint.with({ style = 'fill', blendMode = 'additive' }),
		core = Paint.with({ style = 'fill', blendMode = 'additive' }),

		init = init,
		advance = advance,
		draw = draw,
	}
end
