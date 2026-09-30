-- Node script: the living sky behind the whole artboard.
--
-- Layers, back to front:
--   stardust clouds  nebula.wgsl, rendered at artboard resolution into a GPU
--                    canvas and scaled up to the artboard
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

	pipeline: GPUPipeline?,
	canvas: GPUCanvas?,
	uniforms: GPUBuffer?,
	bindings: GPUBindGroup?,
	params: buffer,
	sampler: ImageSampler,
	solid: Paint,
	trail: Paint,
}

local CLOUD_SCALE = 1
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

-- The cloud pass. Any failure (no GPU on this runtime, missing shader)
-- leaves the pipeline nil and the sky simply has no clouds.
local function buildClouds(self: Nebula, context: Context)
	local shader = context:shader('nebula')
	if shader == nil then
		print('Nebula: shader "nebula" not found; drawing without clouds')
		return
	end
	local ok, err = pcall(function()
		local canvas = context:gpuCanvas({
			width = math.max(1, math.floor(self.width * CLOUD_SCALE)),
			height = math.max(1, math.floor(self.height * CLOUD_SCALE)),
		})
		local pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = canvas.format } },
		})
		local uniforms = GPUBuffer.new({ size = 48, usage = 'uniform' })
		self.bindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = uniforms } },
		})
		self.canvas = canvas
		self.pipeline = pipeline
		self.uniforms = uniforms
	end)
	if not ok then
		print('Nebula: cloud pass unavailable: ' .. tostring(err))
		self.pipeline = nil
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
	buildClouds(self, context)
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

local function drawClouds(self: Nebula, renderer: Renderer, heat: number)
	local pipeline, canvas, uniforms, bindings = self.pipeline, self.canvas, self.uniforms, self.bindings
	if pipeline == nil or canvas == nil or uniforms == nil or bindings == nil then
		return
	end
	buffer.writef32(self.params, 0, self.time)
	buffer.writef32(self.params, 4, heat)
	buffer.writef32(self.params, 8, self.width / self.height)
	buffer.writef32(self.params, 12, self.focusY / self.height)
	buffer.writef32(self.params, 16, self.blast)
	buffer.writef32(self.params, 20, self.grain)
	buffer.writef32(self.params, 24, self.mist)
	buffer.writef32(self.params, 28, self.cursorStrength * self.presence)
	buffer.writef32(self.params, 32, self.cursorX / self.width)
	buffer.writef32(self.params, 36, self.cursorY / self.height)
	buffer.writef32(self.params, 40, self.cursorRadius / self.height)
	uniforms:write(self.params)

	local pass = canvas:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipeline)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()

	renderer:save()
	renderer:transform(Mat2D.withScale(self.width / canvas.width, self.height / canvas.height))
	renderer:drawImage(canvas.image, self.sampler, 'srcOver', 1)
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

		pipeline = nil,
		canvas = nil,
		uniforms = nil,
		bindings = nil,
		params = buffer.create(48),
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
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
