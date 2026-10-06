-- Madhubani node: draws the card's photo as a folk-art print, on top of the
-- data-bound photo. Place it at the artboard's top-left, sized to the card.
--
-- Reads the view model's `photo` (directly, or under `front`). When it
-- changes, the photo is cover-fitted into a canvas at `resolution` × the
-- node size, then two GPU passes run once:
--   MadhubaniFlatten  Kuwahara filter: photo texture → flat painted patches
--   MadhubaniStylize  tone bands with harmony inks and patterns, ink
--                     outlines, a double outline round the bird, paper grain
-- The result is cached and simply drawn each frame.
--
-- Inputs: width, height (card size), resolution (work pixels per point),
-- amount (0 = photo, 1 = print), harmony and baseHue (the palette, see
-- below; a `harmony`/`baseHue` number next to `photo` on the view model
-- overrides the input), flatten (Kuwahara
-- radius, texels), lineWidth (texels), patternScale (texels), maskThreshold
-- (how different from every border colour counts as the bird, 0–1), dither
-- (0–1, ordered dither across band edges).

export type Madhubani = {
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	amount: Input<number>,
	harmony: Input<number>,
	baseHue: Input<number>,
	flatten: Input<number>,
	lineWidth: Input<number>,
	patternScale: Input<number>,
	maskThreshold: Input<number>,
	dither: Input<number>,

	context: Context?,
	photo: Property<Image>?,
	dataVm: ViewModel?,
	source: Canvas?,
	flat: GPUCanvas?,
	out: GPUCanvas?,
	flatPipe: GPUPipeline?,
	stylePipe: GPUPipeline?,
	flatUbo: GPUBuffer?,
	styleUbo: GPUBuffer?,
	flatParams: buffer,
	styleParams: buffer,
	gpuSampler: GPUSampler?,
	sampler: ImageSampler,
	-- Frames left to re-render: canvases can be unallocated for the first
	-- frames, and binds take a frame or two to settle.
	pending: number,
	lastKey: string,
	ready: boolean,
	reported: { [string]: boolean },
}

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

local function report(self: Madhubani, key: string, message: string)
	if not self.reported[key] then
		self.reported[key] = true
		print(`Madhubani {key}: {message}`)
	end
end

local function workSize(self: Madhubani): (number, number)
	local res = math.clamp(self.resolution, 0.5, 4)
	return math.max(16, math.floor(self.width * res + 0.5)), math.max(16, math.floor(self.height * res + 0.5))
end

-- The `photo` image to draw. Inside Card3D the face artboard sees more than
-- one view model, and only the one the bound Image uses (root > front >
-- photo) holds the picture, so that path is tried first and a property
-- with no image yet is passed over until one has it.
local function findPhoto(self: Madhubani)
	if self.photo ~= nil then
		return
	end
	local ctx = self.context
	if ctx == nil then
		return
	end
	local candidates: { Property<Image> } = {}
	local owners: { ViewModel } = {}
	local function add(vm: ViewModel?)
		if vm == nil then
			return
		end
		local front = vm:getViewModel('front')
		if front ~= nil and front.value ~= nil then
			local p = front.value:getImage('photo')
			if p ~= nil then
				table.insert(candidates, p)
				table.insert(owners, front.value)
			end
		end
		local direct = vm:getImage('photo')
		if direct ~= nil then
			table.insert(candidates, direct)
			table.insert(owners, vm)
		end
	end
	add(ctx:rootViewModel())
	local dc = ctx:dataContext()
	while dc do
		add(dc:viewModel())
		dc = dc:parent()
	end
	add(ctx:viewModel())
	for i, photo in candidates do
		if photo.value ~= nil then
			self.photo = photo
			self.dataVm = owners[i]
			photo:addListener(function()
				self.pending = 3
				ctx:markNeedsUpdate()
			end)
			self.pending = 3
			return
		end
	end
end

local function writeColor(buf: buffer, offset: number, rgb: { number })
	buffer.writef32(buf, offset, rgb[1])
	buffer.writef32(buf, offset + 4, rgb[2])
	buffer.writef32(buf, offset + 8, rgb[3])
	buffer.writef32(buf, offset + 12, 1)
end

-- `harmony` and `baseHue`: the view model's numbers when it has them,
-- otherwise the inputs.
local function scheme(self: Madhubani): (number, number)
	local harmony, hue = self.harmony, self.baseHue
	local h, b = Harmony.read(self.dataVm)
	if h ~= nil and b ~= nil then
		harmony, hue = h, b
	end
	return harmony, hue
end

local function build(self: Madhubani, ctx: Context)
	local flatShader = ctx:shader('MadhubaniFlatten')
	local styleShader = ctx:shader('MadhubaniStylize')
	if flatShader == nil or styleShader == nil then
		report(self, 'shader', 'MadhubaniFlatten or MadhubaniStylize not found')
		return
	end
	local w, h = workSize(self)
	self.source = ctx:canvas({ width = w, height = h })
	local flat = ctx:gpuCanvas({ width = w, height = h })
	local out = ctx:gpuCanvas({ width = w, height = h })
	self.flat, self.out = flat, out
	self.flatPipe = GPUPipeline.new({
		vertex = { module = flatShader, entryPoint = 'vs_main' },
		fragment = { module = flatShader, entryPoint = 'fs_main' },
		vertexLayout = {},
		colorTargets = { { format = flat.format } },
	})
	self.stylePipe = GPUPipeline.new({
		vertex = { module = styleShader, entryPoint = 'vs_main' },
		fragment = { module = styleShader, entryPoint = 'fs_main' },
		vertexLayout = {},
		colorTargets = { { format = out.format } },
	})
	self.flatUbo = GPUBuffer.new({ size = 16, usage = 'uniform' })
	self.styleUbo = GPUBuffer.new({ size = 176, usage = 'uniform' })
	self.gpuSampler = GPUSampler.new({ wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	self.ready = true
end

function init(self: Madhubani, context: Context): boolean
	self.context = context
	local ok, err = pcall(build, self, context)
	if not ok then
		report(self, 'setup', tostring(err))
	end
	findPhoto(self)
	return true
end

function advance(self: Madhubani, seconds: number): boolean
	findPhoto(self)
	-- Re-render when a look input changes.
	local harmony, hue = scheme(self)
	local key = `{harmony}|{hue}|{self.flatten}|{self.lineWidth}|{self.patternScale}|{self.maskThreshold}|{self.amount}|{self.dither}`
	if key ~= self.lastKey then
		self.lastKey = key
		self.pending = math.max(self.pending, 2)
	end
	return true
end

-- Cover-fits the photo into the source canvas.
local function copyPhoto(self: Madhubani, image: Image): boolean
	local source = self.source
	if source == nil or image.width <= 0 or image.height <= 0 then
		return false
	end
	local w, h = source.width, source.height
	local s = math.max(w / image.width, h / image.height)
	local r = source:beginFrame()
	r:save()
	r:transform(Mat2D.withScaleAndTranslation(s, s, (w - image.width * s) * 0.5, (h - image.height * s) * 0.5))
	r:drawImage(image, self.sampler, 'srcOver', 1)
	r:restore()
	source:endFrame()
	return true
end

local function runPass(gc: GPUCanvas, pipe: GPUPipeline, bindings: GPUBindGroup)
	local pass = gc:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipe)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()
end

-- Runs both passes; false while the canvases aren't allocated yet.
local function render(self: Madhubani, image: Image): boolean
	local source, flat, out = self.source, self.flat, self.out
	local flatPipe, stylePipe = self.flatPipe, self.stylePipe
	local flatUbo, styleUbo, gpuSampler = self.flatUbo, self.styleUbo, self.gpuSampler
	if not (source and flat and out and flatPipe and stylePipe and flatUbo and styleUbo and gpuSampler) then
		return false
	end
	if flat.width <= 0 or out.width <= 0 or source.image == nil or not copyPhoto(self, image) then
		return false
	end
	local sourceView = source.image:view()
	local tx, ty = 1 / flat.width, 1 / flat.height

	local fp = self.flatParams
	buffer.writef32(fp, 0, tx)
	buffer.writef32(fp, 4, ty)
	buffer.writef32(fp, 8, math.clamp(self.flatten, 1, 6))
	buffer.writef32(fp, 12, math.clamp(self.maskThreshold, 0, 1))
	flatUbo:write(fp)
	runPass(flat, flatPipe, GPUBindGroup.new({
		layout = flatPipe:getBindGroupLayout(0),
		ubos = { { slot = 0, buffer = flatUbo } },
		textures = { { slot = 1, view = sourceView } },
		samplers = { { slot = 2, sampler = gpuSampler } },
	}))

	local palette = Harmony.palette(scheme(self))
	local sp = self.styleParams
	buffer.writef32(sp, 0, tx)
	buffer.writef32(sp, 4, ty)
	buffer.writef32(sp, 8, math.max(0.5, self.lineWidth))
	buffer.writef32(sp, 12, math.max(2, self.patternScale))
	buffer.writef32(sp, 16, math.clamp(self.amount, 0, 1))
	buffer.writef32(sp, 20, math.clamp(self.dither, 0, 1))
	buffer.writef32(sp, 24, 0)
	buffer.writef32(sp, 28, 0)
	for i = 1, 9 do
		writeColor(sp, 32 + (i - 1) * 16, palette[i])
	end
	styleUbo:write(sp)
	runPass(out, stylePipe, GPUBindGroup.new({
		layout = stylePipe:getBindGroupLayout(0),
		ubos = { { slot = 0, buffer = styleUbo } },
		textures = { { slot = 1, view = flat:colorView() }, { slot = 3, view = sourceView } },
		samplers = { { slot = 2, sampler = gpuSampler } },
	}))
	return true
end

function draw(self: Madhubani, renderer: Renderer)
	if not self.ready then
		return
	end
	local photo = self.photo
	local image = if photo ~= nil then photo.value else nil
	if image == nil then
		report(self, 'photo', 'no photo yet')
		return
	end
	if self.pending > 0 then
		local ok, result = pcall(render, self, image)
		if not ok then
			report(self, 'render', tostring(result))
			self.pending -= 1
		elseif result then
			-- A couple of extra frames lets the binds settle.
			self.pending -= 1
		end
	end
	local out = self.out
	if out == nil or out.image == nil or out.width <= 0 then
		return
	end
	renderer:save()
	renderer:transform(Mat2D.withScale(self.width / out.width, self.height / out.height))
	renderer:drawImage(out.image, self.sampler, 'srcOver', 1)
	renderer:restore()
end

return function(): Node<Madhubani>
	return {
		width = 239,
		height = 339,
		resolution = 2,
		amount = 1,
		harmony = 4,
		baseHue = 30,
		flatten = 4,
		lineWidth = 1.5,
		patternScale = 6,
		maskThreshold = 0.18,
		dither = 0.35,

		context = nil,
		photo = nil,
		dataVm = nil,
		source = nil,
		flat = nil,
		out = nil,
		flatPipe = nil,
		stylePipe = nil,
		flatUbo = nil,
		styleUbo = nil,
		flatParams = buffer.create(16),
		styleParams = buffer.create(176),
		gpuSampler = nil,
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		pending = 0,
		lastKey = '',
		ready = false,
		reported = {},

		init = init,
		advance = advance,
		draw = draw,
	}
end
