-- Node script: renders a GLB model (see GLB.luau) in 3D with depth and
-- metal-roughness shading (glb_pbr.wgsl), drawn at `width` x `height`
-- centred on the node.
--
-- Drop the .glb into the project folder; it ships as a blob named after the
-- file (ring.glb -> 'ring'). Put that name in `asset`.
--
-- The model is centred and scaled to fill the view automatically, so
-- `scale = 1` always fits regardless of the units it was exported in.
-- Rotations are degrees, applied X, then Y, then Z. `spinX/Y/Z` add a
-- continuous rotation in degrees per second.
--
-- Material inputs override the file when >= 0 (`metallic`, `roughness`);
-- `tint` blends the base colour by `tintAmount`; `emissive` and `rim` add
-- glow on top. With `interactive` on, dragging over the model rotates it.
--
-- Textures: the GLB's embedded base colour texture is decoded with
-- `context:decodeImage`, which the CLI previewer, editor and native runtimes
-- support but the web runtime (2.44) does not. For the web, extract the
-- texture to a PNG (tools/glb_textures.py), add it as an ImageAsset and put
-- its name in `textureImage`; that path works everywhere and skips decoding.

local GLB = require('GLB')

export type GLBModel = {
	-- Model
	asset: Input<string>,
	textureImage: Input<string>,
	-- Canvas
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	opacity: Input<number>,
	-- Transform
	rotationX: Input<number>,
	rotationY: Input<number>,
	rotationZ: Input<number>,
	spinX: Input<number>,
	spinY: Input<number>,
	spinZ: Input<number>,
	scale: Input<number>,
	offsetX: Input<number>,
	offsetY: Input<number>,
	offsetZ: Input<number>,
	-- Camera
	fov: Input<number>,
	cameraDistance: Input<number>,
	-- Lighting
	lightAzimuth: Input<number>,
	lightElevation: Input<number>,
	lightIntensity: Input<number>,
	ambient: Input<number>,
	environment: Input<number>,
	exposure: Input<number>,
	-- Material
	metallic: Input<number>,
	roughness: Input<number>,
	tint: Input<Color>,
	tintAmount: Input<number>,
	emissive: Input<Color>,
	emissiveStrength: Input<number>,
	rimColor: Input<Color>,
	rimStrength: Input<number>,
	cullBackfaces: Input<boolean>,
	-- Interaction
	interactive: Input<boolean>,

	-- State
	context: Context?,
	model: GLB.Model?,
	loadedAsset: string,
	loadedTexture: string,
	texSource: Image?,
	texCanvas: Canvas?,
	texDirty: boolean,
	failed: boolean,
	spinAngles: { number },
	dragAngles: { number },
	dragging: boolean,
	lastPointer: Vector,

	shader: Shader?,
	pipelines: { [string]: GPUPipeline },
	canvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	sampler: GPUSampler?,
	whiteView: GPUTextureView?,
	drawSampler: ImageSampler,
	parts: { Part },
	scratch: buffer,
}

type Part = {
	primitive: GLB.Primitive,
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	uniforms: GPUBuffer,
	bindings: GPUBindGroup?,
	textureView: GPUTextureView?,
}

local UNIFORM_SIZE = 256
local DEPTH_FORMAT: 'depth32float' = 'depth32float'

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function colorFloats(c: Color): (number, number, number)
	local function lin(v: number): number
		return (v / 255) ^ 2.2
	end
	return lin(Color.red(c) :: number), lin(Color.green(c) :: number), lin(Color.blue(c) :: number)
end

local function release(self: GLBModel)
	self.model = nil
	self.parts = {}
end

-- Builds a pipeline for the current sample count and cull mode, cached.
local function pipelineFor(self: GLBModel, canvas: GPUCanvas, samples: number, cull: boolean): GPUPipeline?
	local shader = self.shader
	if shader == nil then
		return nil
	end
	local key = samples .. (if cull then 'b' else 'n')
	local cached = self.pipelines[key]
	if cached then
		return cached
	end
	local pipeline = GPUPipeline.new({
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
		cullMode = if cull then 'back' else 'none',
		sampleCount = samples,
	})
	self.pipelines[key] = pipeline
	return pipeline
end

local function bindPart(self: GLBModel, part: Part, pipeline: GPUPipeline)
	local view = part.textureView or self.whiteView
	local sampler = self.sampler
	if view == nil or sampler == nil then
		return
	end
	part.bindings = GPUBindGroup.new({
		layout = pipeline:getBindGroupLayout(0),
		ubos = { { slot = 0, buffer = part.uniforms } },
		textures = { { slot = 1, view = view } },
		samplers = { { slot = 2, sampler = sampler } },
	})
end

-- Decodes the model's images and hands each to the parts that use it.
local function loadTextures(self: GLBModel, model: GLB.Model)
	local context = self.context
	if context == nil then
		return
	end
	for imageIndex, image in model.images do
		if buffer.len(image.data) > 0 then
			context:decodeImage(image.data):andThen(function(decoded: DecodedImage)
				if self.model ~= model then
					return -- a different model was loaded meanwhile
				end
				local texture = GPUTexture.new({ width = decoded.width, height = decoded.height })
				texture:upload({ data = decoded.data })
				local view = texture:view()
				for _, part in self.parts do
					if part.primitive.material.baseColorImage == imageIndex - 1 then
						part.textureView = view
						part.bindings = nil -- rebuilt on the next draw
					end
				end
			end)
		end
	end
end

local function loadModel(self: GLBModel)
	local context = self.context
	if context == nil then
		return
	end
	release(self)
	self.loadedAsset = self.asset
	self.loadedTexture = self.textureImage
	self.texSource = nil
	self.texCanvas = nil
	self.texDirty = false
	self.failed = false
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`GLBModel: no blob asset named '{self.asset}' (add {self.asset}.glb to the project)`)
		self.failed = true
		return
	end
	local model, err = GLB.parse(blob.data)
	if model == nil then
		print(`GLBModel: could not load '{self.asset}': {err}`)
		self.failed = true
		return
	end
	print(
		`GLBModel: loaded '{self.asset}' with {#model.primitives} primitive(s), {model.vertexCount} vertices, {model.triangleCount} triangles`
	)
	self.model = model
	for _, primitive in model.primitives do
		table.insert(self.parts, {
			primitive = primitive,
			vertexBuffer = GPUBuffer.new({
				size = buffer.len(primitive.vertices),
				usage = 'vertex',
				data = primitive.vertices,
				immutable = true,
			}),
			indexBuffer = GPUBuffer.new({
				size = buffer.len(primitive.indices),
				usage = 'index',
				data = primitive.indices,
				immutable = true,
			}),
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
			textureView = nil,
		})
	end
	if self.textureImage ~= '' then
		-- An ImageAsset replaces the embedded textures (works on the web).
		local image = context:image(self.textureImage)
		if image then
			self.texSource = image
			-- Sized on first use: on the web the image's size is 0 until it loads.
			self.texCanvas = context:canvas()
			self.texDirty = true
		else
			print(`GLBModel: no image asset named '{self.textureImage}'`)
		end
	else
		loadTextures(self, model)
	end
end

-- Copies the `textureImage` asset into a canvas, whose image a shader can
-- sample, and hands it to the textured parts (or all parts if none are).
local function applyTextureImage(self: GLBModel)
	local source, canvas = self.texSource, self.texCanvas
	if not self.texDirty or source == nil or canvas == nil then
		return
	end
	if source.width <= 0 or source.height <= 0 then
		return -- not loaded yet; try again next frame
	end
	if canvas.width ~= source.width or canvas.height ~= source.height then
		canvas:resize(source.width, source.height)
	end
	local r = canvas:beginFrame()
	r:drawImage(source, self.drawSampler, 'srcOver', 1)
	canvas:endFrame()
	local view = canvas.image:view()
	local anyTextured = false
	for _, part in self.parts do
		if part.primitive.material.baseColorImage ~= nil then
			anyTextured = true
		end
	end
	for _, part in self.parts do
		if not anyTextured or part.primitive.material.baseColorImage ~= nil then
			part.textureView = view
			part.bindings = nil
		end
	end
	self.texDirty = false
end

-- (Re)creates the canvas, depth and MSAA targets to match the inputs.
local function ensureTargets(self: GLBModel): GPUCanvas?
	local context = self.context
	if context == nil then
		return nil
	end
	local res = clamp(self.resolution, 0.25, 4)
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
	local depth = GPUTexture.new({
		width = w,
		height = h,
		format = DEPTH_FORMAT,
		renderTarget = true,
		sampleCount = samples,
	})
	self.depthView = depth:view()
	if samples > 1 then
		local color = GPUTexture.new({
			width = w,
			height = h,
			format = canvas.format,
			renderTarget = true,
			sampleCount = samples,
		})
		self.msaaView = color:view()
	else
		self.msaaView = nil
	end
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	-- Pipelines depend on the sample count; bind groups on the pipeline.
	for _, part in self.parts do
		part.bindings = nil
	end
	return canvas
end

local function writeUniforms(self: GLBModel, part: Part, mvp: Mat4, modelM: Mat4, eye: Vector)
	local u = self.scratch
	local m = part.primitive.material
	mvp:writeToBuffer(u, 0)
	modelM:writeToBuffer(u, 64)
	buffer.writef32(u, 128, m.baseColor[1])
	buffer.writef32(u, 132, m.baseColor[2])
	buffer.writef32(u, 136, m.baseColor[3])
	buffer.writef32(u, 140, m.baseColor[4])
	-- Emissive: the file's factor plus the input.
	local er, eg, eb = colorFloats(self.emissive)
	local es = math.max(0, self.emissiveStrength)
	buffer.writef32(u, 144, m.emissive[1] + er * es)
	buffer.writef32(u, 148, m.emissive[2] + eg * es)
	buffer.writef32(u, 152, m.emissive[3] + eb * es)
	buffer.writef32(u, 156, 1)
	local rr, rg, rb = colorFloats(self.rimColor)
	buffer.writef32(u, 160, rr)
	buffer.writef32(u, 164, rg)
	buffer.writef32(u, 168, rb)
	buffer.writef32(u, 172, math.max(0, self.rimStrength))
	local az, el = math.rad(self.lightAzimuth), math.rad(self.lightElevation)
	buffer.writef32(u, 176, math.cos(el) * math.sin(az))
	buffer.writef32(u, 180, math.sin(el))
	buffer.writef32(u, 184, math.cos(el) * math.cos(az))
	buffer.writef32(u, 188, math.max(0, self.lightIntensity))
	buffer.writef32(u, 192, eye.x)
	buffer.writef32(u, 196, eye.y)
	buffer.writef32(u, 200, eye.z)
	buffer.writef32(u, 204, math.max(0, self.ambient))
	buffer.writef32(u, 208, if self.metallic >= 0 then self.metallic else m.metallic)
	buffer.writef32(u, 212, if self.roughness >= 0 then self.roughness else m.roughness)
	buffer.writef32(u, 216, if part.textureView then 1 else 0)
	buffer.writef32(u, 220, clamp(self.tintAmount, 0, 1))
	local tr, tg, tb = colorFloats(self.tint)
	buffer.writef32(u, 224, tr)
	buffer.writef32(u, 228, tg)
	buffer.writef32(u, 232, tb)
	buffer.writef32(u, 236, math.max(0, self.exposure))
	buffer.writef32(u, 240, math.max(0, self.environment))
	buffer.writef32(u, 244, 1)
	buffer.writef32(u, 248, 0)
	buffer.writef32(u, 252, 0)
	part.uniforms:write(u)
end

local function render(self: GLBModel): Image?
	local model = self.model
	if model == nil then
		return nil
	end
	local canvas = ensureTargets(self)
	if canvas == nil then
		return nil
	end
	local depthView = self.depthView
	if depthView == nil then
		return nil
	end
	local samples = self.targetSamples
	local pipeline = pipelineFor(self, canvas, samples, self.cullBackfaces)
	if pipeline == nil then
		return nil
	end

	-- Model: centre on the origin, normalise to radius 1, then the inputs.
	local s = math.max(self.scale, 0.0001) / model.radius
	local c = model.center
	local rx = math.rad(self.rotationX + self.spinAngles[1] + self.dragAngles[1])
	local ry = math.rad(self.rotationY + self.spinAngles[2] + self.dragAngles[2])
	local rz = math.rad(self.rotationZ + self.spinAngles[3])
	local modelM = Mat4.fromTranslation(self.offsetX, self.offsetY, self.offsetZ)
		* Mat4.fromRotationZ(rz)
		* Mat4.fromRotationY(ry)
		* Mat4.fromRotationX(rx)
		* Mat4.fromScale(s)
		* Mat4.fromTranslation(-c[1], -c[2], -c[3])

	-- Camera: back far enough that a unit sphere fills the narrower side.
	local aspect = self.targetW / self.targetH
	local fovY = math.rad(clamp(self.fov, 5, 120))
	local halfNarrow = if aspect >= 1 then fovY / 2 else math.atan(math.tan(fovY / 2) * aspect)
	local distance = (1.05 / math.sin(halfNarrow)) * math.max(self.cameraDistance, 0.05)
	local eye = Vector.xyz(0, 0, distance)
	local view = Mat4.lookAt(eye, Vector.origin(), Vector.xyz(0, 1, 0))
	local proj = Mat4.perspective(fovY, aspect, math.max(0.01, distance - 50), distance + 50)
	local mvp = proj * view * modelM

	for _, part in self.parts do
		writeUniforms(self, part, mvp, modelM, eye)
		if part.bindings == nil then
			bindPart(self, part, pipeline)
		end
	end

	local colorAttachment: ColorAttachment = if samples > 1
		then {
			view = self.msaaView,
			resolveTarget = canvas:colorView(),
			loadOp = 'clear',
			storeOp = 'discard',
			clearColor = { 0, 0, 0, 0 },
		}
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } }
	local pass = canvas:beginRenderPass({
		color = { colorAttachment },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 1 },
	})
	pass:setPipeline(pipeline)
	for _, part in self.parts do
		local bindings = part.bindings
		if bindings then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, part.vertexBuffer)
			pass:setIndexBuffer(part.indexBuffer, 'uint32')
			pass:drawIndexed(part.primitive.indexCount)
		end
	end
	pass:finish()
	return canvas.image
end

function init(self: GLBModel, context: Context): boolean
	self.context = context
	self.shader = context:shader('glb_pbr')
	if self.shader == nil then
		print('GLBModel: shader "glb_pbr" not found')
		return true
	end
	local ok, err = pcall(function()
		self.sampler = GPUSampler.new({ wrapU = 'repeat', wrapV = 'repeat' })
		local white = GPUTexture.new({ width = 1, height = 1 })
		local pixel = buffer.create(4)
		buffer.writeu32(pixel, 0, 0xFFFFFFFF)
		white:upload({ data = pixel })
		self.whiteView = white:view()
		loadModel(self)
	end)
	if not ok then
		print('GLBModel: GPU setup failed: ' .. tostring(err))
		self.failed = true
	end
	return true
end

function update(self: GLBModel)
	if (self.asset ~= self.loadedAsset or self.textureImage ~= self.loadedTexture) and self.context then
		loadModel(self)
	end
end

function advance(self: GLBModel, seconds: number): boolean
	local a = self.spinAngles
	a[1] = (a[1] + self.spinX * seconds) % 360
	a[2] = (a[2] + self.spinY * seconds) % 360
	a[3] = (a[3] + self.spinZ * seconds) % 360
	return true
end

local function inside(self: GLBModel, p: Vector): boolean
	return math.abs(p.x) <= self.width / 2 and math.abs(p.y) <= self.height / 2
end

local function pointerDown(self: GLBModel, event: PointerEvent)
	if self.interactive and inside(self, event.position) then
		self.dragging = true
		self.lastPointer = event.position
		event:hit()
	end
end

local function pointerMove(self: GLBModel, event: PointerEvent)
	if self.dragging then
		local d = event.position - self.lastPointer
		self.lastPointer = event.position
		self.dragAngles[2] += d.x * 0.5
		self.dragAngles[1] = clamp(self.dragAngles[1] + d.y * 0.5, -89, 89)
		event:hit()
	end
end

local function pointerUp(self: GLBModel, event: PointerEvent)
	if self.dragging then
		self.dragging = false
		event:hit()
	end
end

function draw(self: GLBModel, renderer: Renderer)
	if self.failed then
		return
	end
	local texOk, texErr = pcall(applyTextureImage, self)
	if not texOk then
		print('GLBModel: textureImage failed: ' .. tostring(texErr))
		self.texDirty = false
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('GLBModel: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	if image == nil then
		return
	end
	renderer:save()
	renderer:transform(
		Mat2D.withTranslation(-self.width / 2, -self.height / 2)
			* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
	)
	renderer:drawImage(image, self.drawSampler, 'srcOver', clamp(self.opacity, 0, 1))
	renderer:restore()
end

return function(): Node<GLBModel>
	return {
		asset = 'ring',
		textureImage = '',
		width = 400,
		height = 400,
		resolution = 2,
		msaa = 4,
		opacity = 1,
		rotationX = 0,
		rotationY = 0,
		rotationZ = 0,
		spinX = 0,
		spinY = 0,
		spinZ = 0,
		scale = 1,
		offsetX = 0,
		offsetY = 0,
		offsetZ = 0,
		fov = 30,
		cameraDistance = 1,
		lightAzimuth = 35,
		lightElevation = 40,
		lightIntensity = 2.5,
		ambient = 0.5,
		environment = 1,
		exposure = 1,
		metallic = -1,
		roughness = -1,
		tint = Color.rgb(255, 255, 255),
		tintAmount = 0,
		emissive = Color.rgb(63, 182, 255),
		emissiveStrength = 0,
		rimColor = Color.rgb(63, 182, 255),
		rimStrength = 0,
		cullBackfaces = false,
		interactive = false,

		context = nil,
		model = nil,
		loadedAsset = '',
		loadedTexture = '',
		texSource = nil,
		texCanvas = nil,
		texDirty = false,
		failed = false,
		spinAngles = { 0, 0, 0 },
		dragAngles = { 0, 0, 0 },
		dragging = false,
		lastPointer = Vector.origin(),

		shader = nil,
		pipelines = {},
		canvas = nil,
		depthView = nil,
		msaaView = nil,
		targetW = 0,
		targetH = 0,
		targetSamples = 1,
		sampler = nil,
		whiteView = nil,
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		parts = {},
		scratch = buffer.create(UNIFORM_SIZE),

		init = init,
		update = update,
		advance = advance,
		draw = draw,
		pointerDown = pointerDown,
		pointerMove = pointerMove,
		pointerUp = pointerUp,
	}
end
