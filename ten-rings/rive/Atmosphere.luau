-- Node script: everything behind the rings.
--
--   mist     mist.wgsl at half resolution, scaled up to the artboard
--   embers   warm specks drifting upward; with power they cool toward the
--            energy colour, speed up and stream toward the rings
--
-- `power` and `blast` are keyed by the state machine (same meaning as on
-- TenRings / mist.wgsl). Place the node at the artboard's top-left corner.

export type Atmosphere = {
	width: Input<number>,
	height: Input<number>,
	power: Input<number>,
	blast: Input<number>,
	focusX: Input<number>,
	focusY: Input<number>,
	energyColor: Input<Color>,

	time: number,
	embers: { Ember },
	pipeline: GPUPipeline?,
	canvas: GPUCanvas?,
	uniforms: GPUBuffer?,
	bindings: GPUBindGroup?,
	params: buffer,
	sampler: ImageSampler,
	paint: Paint,
}

type Ember = { x: number, y: number, vx: number, vy: number, size: number, phase: number, life: number }

local MIST_SCALE = 0.5
local KAPPA = 0.5522848

local seed = 1
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rand()
end
local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
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

local function respawn(self: Atmosphere, e: Ember, anywhere: boolean)
	e.x = range(0, self.width)
	e.y = if anywhere then range(0, self.height) else self.height + range(5, 60)
	e.vx = range(-6, 6)
	e.vy = -range(10, 28)
	e.size = range(0.9, 2.4)
	e.phase = range(0, math.pi * 2)
	e.life = 1
end

local function buildMist(self: Atmosphere, context: Context)
	local shader = context:shader('mist')
	if shader == nil then
		print('Atmosphere: shader "mist" not found; drawing without mist')
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
		local uniforms = GPUBuffer.new({ size = 48, usage = 'uniform' })
		self.bindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = uniforms } },
		})
		self.canvas, self.pipeline, self.uniforms = canvas, pipeline, uniforms
	end)
	if not ok then
		print('Atmosphere: mist unavailable: ' .. tostring(err))
		self.pipeline = nil
	end
end

function init(self: Atmosphere, context: Context): boolean
	seed = 7731
	for _ = 1, 70 do
		local e: Ember = { x = 0, y = 0, vx = 0, vy = 0, size = 1, phase = 0, life = 1 }
		respawn(self, e, true)
		table.insert(self.embers, e)
	end
	buildMist(self, context)
	return true
end

function advance(self: Atmosphere, seconds: number): boolean
	self.time += seconds
	local power = clamp(self.power, 0, 1.5)
	local blast = clamp(self.blast, 0, 1.5)
	local fx, fy = self.focusX * self.width, self.focusY * self.height
	for _, e in self.embers do
		-- Drift up, wander, and with power get drawn toward the rings.
		local dx, dy = fx - e.x, fy - e.y
		local d = math.sqrt(dx * dx + dy * dy) + 1
		local pull = power * 60
		local push = blast * 900 / (1 + d / 120)
		local ax = dx / d * pull - dx / d * push + math.sin(self.time * 1.3 + e.phase) * 6
		local ay = dy / d * pull - dy / d * push
		e.vx += ax * seconds
		e.vy += ay * seconds
		e.vx *= 1 - 0.8 * seconds
		e.vy = e.vy * (1 - 0.6 * seconds) - 8 * seconds
		local speed = 1 + power * 1.5
		e.x += e.vx * seconds * speed
		e.y += e.vy * seconds * speed
		if e.y < -20 or e.x < -40 or e.x > self.width + 40 or e.y > self.height + 80 or d < 14 then
			respawn(self, e, false)
		end
	end
	return true
end

local function drawMist(self: Atmosphere, renderer: Renderer)
	local pipeline, canvas, uniforms, bindings = self.pipeline, self.canvas, self.uniforms, self.bindings
	if pipeline == nil or canvas == nil or uniforms == nil or bindings == nil then
		return
	end
	local p = self.params
	buffer.writef32(p, 0, self.time)
	buffer.writef32(p, 4, clamp(self.power, 0, 1.5))
	buffer.writef32(p, 8, self.width / self.height)
	buffer.writef32(p, 12, clamp(self.blast, 0, 1.5))
	buffer.writef32(p, 16, self.focusX)
	buffer.writef32(p, 20, self.focusY)
	local function lin(v: number): number
		return (v / 255) ^ 2.2
	end
	buffer.writef32(p, 32, lin(Color.red(self.energyColor) :: number))
	buffer.writef32(p, 36, lin(Color.green(self.energyColor) :: number))
	buffer.writef32(p, 40, lin(Color.blue(self.energyColor) :: number))
	buffer.writef32(p, 44, 1)
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
	renderer:drawImage(image, self.sampler, 'srcOver', 1)
	renderer:restore()
end

local function drawEmbers(self: Atmosphere, renderer: Renderer)
	local power = clamp(self.power, 0, 1)
	local er, eg, eb = Color.red(self.energyColor) :: number, Color.green(self.energyColor) :: number, Color.blue(self.energyColor) :: number
	-- Warm amber at rest, shading toward the energy colour with power.
	local r = 255 + (er - 255) * power
	local g = 170 + (eg - 170) * power
	local b = 90 + (eb - 90) * power
	for _, e in self.embers do
		local tw = 0.55 + 0.45 * math.sin(self.time * 2.3 + e.phase)
		local alpha = clamp(tw * (0.45 + 0.5 * power), 0, 1)
		self.paint.color = Color.rgba(math.floor(r), math.floor(g), math.floor(b), math.floor(alpha * 255))
		local path = Path.new()
		addCircle(path, e.x, e.y, e.size * (0.8 + 0.4 * power))
		renderer:drawPath(path, self.paint)
	end
end

function draw(self: Atmosphere, renderer: Renderer)
	drawMist(self, renderer)
	drawEmbers(self, renderer)
end

return function(): Node<Atmosphere>
	return {
		width = 1280,
		height = 720,
		power = 0.2,
		blast = 0,
		focusX = 0.52,
		focusY = 0.5,
		energyColor = Color.rgb(63, 182, 255),

		time = 0,
		embers = {},
		pipeline = nil,
		canvas = nil,
		uniforms = nil,
		bindings = nil,
		params = buffer.create(48),
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		paint = Paint.with({ style = 'fill', color = Color.rgb(255, 170, 90) }),

		init = init,
		advance = advance,
		draw = draw,
	}
end
