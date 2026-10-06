-- Spike: can a WGSL shader read a data-bound image?
--
-- Reads `photo` from the view model and draws three square panels:
--   A  the image drawn as-is, to prove the binding itself delivers it
--   B  probe.wgsl sampling the image's own view() directly
--   C  the image drawn into a context:canvas() first, then that canvas's
--      image sampled by probe.wgsl (the workaround the docs give for assets)
-- probe.wgsl posterizes what it reads and shows magenta where it reads
-- nothing. Every route is wrapped so one failing can't hide the others;
-- failures are printed once each.

export type ImageProbe = {
	context: Context?,
	photo: Property<Image>?,
	pipeline: GPUPipeline?,
	gpuSampler: GPUSampler?,
	outB: GPUCanvas?,
	outC: GPUCanvas?,
	copy: Canvas?,
	sampler: ImageSampler,
	reported: { [string]: boolean },
}

local SIZE = 260
local GAP = 20
local TOP = 20

local function report(self: ImageProbe, key: string, message: string)
	if not self.reported[key] then
		self.reported[key] = true
		print(`ImageProbe {key}: {message}`)
	end
end

local function findPhoto(self: ImageProbe)
	if self.photo ~= nil then
		return
	end
	local ctx = self.context
	if ctx == nil then
		return
	end
	-- The nearest data context that has `photo`, as TarotCard3D finds `face`.
	local photo: Property<Image>? = nil
	local function pick(vm: ViewModel?)
		if photo == nil and vm ~= nil then
			photo = vm:getImage('photo')
		end
	end
	pick(ctx:viewModel())
	local dc = ctx:dataContext()
	while photo == nil and dc do
		pick(dc:viewModel())
		dc = dc:parent()
	end
	pick(ctx:rootViewModel())
	if photo == nil then
		report(self, 'vm', 'no view model with an image named photo (yet)')
		return
	end
	self.photo = photo
	photo:addListener(function()
		print('ImageProbe: photo changed')
		ctx:markNeedsUpdate()
	end)
end

function init(self: ImageProbe, context: Context): boolean
	self.context = context
	local shader = context:shader('probe')
	if shader == nil then
		report(self, 'shader', 'probe.wgsl not found')
		return true
	end
	local ok, err = pcall(function()
		self.outB = context:gpuCanvas({ width = SIZE, height = SIZE })
		self.outC = context:gpuCanvas({ width = SIZE, height = SIZE })
		self.copy = context:canvas({ width = SIZE, height = SIZE })
		self.pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = (self.outB :: GPUCanvas).format } },
		})
		self.gpuSampler = GPUSampler.new({ wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	end)
	if not ok then
		report(self, 'setup', tostring(err))
	end
	findPhoto(self)
	return true
end

function advance(self: ImageProbe, seconds: number): boolean
	findPhoto(self)
	return true
end

-- Runs probe.wgsl over `view` into `out`; false if any step failed.
local function shade(self: ImageProbe, key: string, view: GPUTextureView, out: GPUCanvas): boolean
	local pipeline, gpuSampler = self.pipeline, self.gpuSampler
	if pipeline == nil or gpuSampler == nil then
		return false
	end
	local ok, err = pcall(function()
		local bindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			textures = { { slot = 1, view = view } },
			samplers = { { slot = 2, sampler = gpuSampler } },
		})
		local pass = out:beginRenderPass({
			color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
		})
		pass:setPipeline(pipeline)
		pass:setBindGroup(0, bindings)
		pass:draw(3)
		pass:finish()
	end)
	if not ok then
		report(self, key, 'shader pass failed: ' .. tostring(err))
	end
	return ok
end

-- Draws `image` scaled to fill a SIZE square at column `index`.
local function panel(self: ImageProbe, renderer: Renderer, image: Image, index: number)
	if image.width <= 0 or image.height <= 0 then
		return
	end
	renderer:save()
	renderer:transform(Mat2D.withTranslation(GAP + index * (SIZE + GAP), TOP))
	renderer:transform(Mat2D.withScale(SIZE / image.width, SIZE / image.height))
	renderer:drawImage(image, self.sampler, 'srcOver', 1)
	renderer:restore()
end

function draw(self: ImageProbe, renderer: Renderer)
	local photo = self.photo
	local image = if photo ~= nil then photo.value else nil
	if image == nil then
		report(self, 'A', 'photo has no image value')
		return
	end
	report(self, 'A', `photo is {image.width}x{image.height}`)

	-- A: the bound image as-is.
	panel(self, renderer, image, 0)

	-- B: sample the bound image's own view.
	local outB = self.outB
	if outB ~= nil then
		local ok, view = pcall(function()
			return image:view()
		end)
		if not ok then
			report(self, 'B', 'view() failed: ' .. tostring(view))
		elseif shade(self, 'B', view, outB) then
			panel(self, renderer, outB.image, 1)
		end
	end

	-- C: copy into a canvas, then sample the canvas's image.
	local copy, outC = self.copy, self.outC
	if copy ~= nil and outC ~= nil then
		local ok, err = pcall(function()
			local r = copy:beginFrame()
			r:save()
			r:transform(Mat2D.withScale(SIZE / image.width, SIZE / image.height))
			r:drawImage(image, self.sampler, 'srcOver', 1)
			r:restore()
			copy:endFrame()
		end)
		if not ok then
			report(self, 'C', 'canvas copy failed: ' .. tostring(err))
		else
			local vok, view = pcall(function()
				return copy.image:view()
			end)
			if not vok then
				report(self, 'C', 'view() failed: ' .. tostring(view))
			elseif shade(self, 'C', view, outC) then
				panel(self, renderer, outC.image, 2)
			end
		end
	end
end

return function(): Node<ImageProbe>
	return {
		context = nil,
		photo = nil,
		pipeline = nil,
		gpuSampler = nil,
		outB = nil,
		outC = nil,
		copy = nil,
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		reported = {},

		init = init,
		advance = advance,
		draw = draw,
	}
end
