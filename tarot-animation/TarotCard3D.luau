-- Node script: a tarot card as a thin 3D slab.
--
-- `back` and `front` are component artboards. Each is instanced privately,
-- drawn into an offscreen canvas, and mapped onto one side of the slab:
-- CardBack on +Z (faces the camera at rotationY = 0), CardFront on -Z.
-- The four thin sides are drawn in gold, so thickness (`depth`) shows while
-- the card turns.
--
-- Projection is done on the CPU: corners go through Rz * Ry * Rx, then a
-- perspective divide toward a camera on +Z. Each face is a subdivided grid
-- drawn with drawImageMesh so affine texturing stays close to perspective.
--
-- The host view model's `face` image is copied onto the private CardFront
-- instance, so the front shows whatever the app bound.

export type TarotCard3D = {
	back: Input<Artboard>,
	front: Input<Artboard>,
	width: Input<number>,
	height: Input<number>,
	depth: Input<number>,
	rotationY: Input<number>,
	rotationX: Input<number>,
	rotationZ: Input<number>,
	viewModelProperty: Input<string>,
	-- Strength of the looping cosmic shine (cosmic_shine.wgsl); 0 turns it off.
	shine: Input<number>,
	-- Width of the sweeping band; 1 is the default, <1 a thin streak, >1 a broad wash.
	shineWidth: Input<number>,

	context: Context?,
	time: number,
	shineOffset: number,
	shinePipeline: GPUPipeline?,
	shineCanvas: GPUCanvas?,
	shineUniforms: GPUBuffer?,
	shineBindings: GPUBindGroup?,
	shineParams: buffer,
	backInst: Artboard?,
	frontInst: Artboard?,
	frontVm: ViewModel?,
	sourceFace: Property<Image>?,
	backCanvas: Canvas?,
	frontCanvas: Canvas?,
	-- Frames left to redraw each texture. The back art is static; the front
	-- only changes when `face` does. A couple of frames lets binds settle.
	backPending: number,
	frontPending: number,
	sampler: ImageSampler,
	uvs: VertexBuffer,
	uvsMirrored: VertexBuffer,
	tris: TriangleBuffer,
	edgePaint: Paint,
	shadePaint: Paint,
}

local TEX_SCALE = 2
local COLS = 6
local ROWS = 10
local CAMERA = 900

-- Host view model that owns `face`: the nearest data context with the
-- property, optionally through a nested view model named by the input.
local function sourceVm(self: TarotCard3D, ctx: Context): ViewModel?
	local path = self.viewModelProperty
	local function pick(vm: ViewModel?): ViewModel?
		if vm == nil then
			return nil
		end
		if path ~= '' then
			local nested = vm:getViewModel(path)
			if nested == nil then
				return nil
			end
			vm = nested.value
		end
		if vm:getImage('face') ~= nil then
			return vm
		end
		return nil
	end

	local found = pick(ctx:viewModel())
	if found then
		return found
	end
	local dc = ctx:dataContext()
	while dc do
		found = pick(dc:viewModel())
		if found then
			return found
		end
		dc = dc:parent()
	end
	return pick(ctx:rootViewModel())
end

local function relayFace(self: TarotCard3D)
	local src = self.sourceFace
	local vm = self.frontVm
	if src == nil or vm == nil then
		return
	end
	local dest = vm:getImage('face')
	if dest ~= nil then
		dest.value = src.value
		self.frontPending = 2
	end
end

local function watchFace(self: TarotCard3D, ctx: Context)
	if self.sourceFace ~= nil then
		return
	end
	local vm = sourceVm(self, ctx)
	if vm == nil then
		return
	end
	local face = vm:getImage('face')
	if face == nil then
		return
	end
	self.sourceFace = face
	face:addListener(function()
		relayFace(self)
		ctx:markNeedsUpdate()
	end)
	relayFace(self)
end

local function buildInstances(self: TarotCard3D)
	local ctx = self.context
	if ctx == nil then
		return
	end
	local w = math.max(1, math.floor(self.width * TEX_SCALE))
	local h = math.max(1, math.floor(self.height * TEX_SCALE))

	local back = self.back:instance()
	back.frameOrigin = false
	self.backInst = back
	self.backCanvas = ctx:canvas({ width = w, height = h })

	-- A private view model, never the placement's: the clone must own the
	-- image it draws, or a host rebind would never reach it.
	local vm = Data.CardFront.new()
	self.frontVm = vm
	local front = self.front:instance(vm)
	front.frameOrigin = false
	self.frontInst = front
	self.frontCanvas = ctx:canvas({ width = w, height = h })

	relayFace(self)
end

local function buildMesh(self: TarotCard3D)
	local uvs = VertexBuffer()
	local mirrored = VertexBuffer()
	local tris = TriangleBuffer()
	for r = 0, ROWS do
		for c = 0, COLS do
			local u = c / COLS
			local v = r / ROWS
			uvs:add(Vector.xy(u, v))
			mirrored:add(Vector.xy(1 - u, v))
		end
	end
	local stride = COLS + 1
	for r = 0, ROWS - 1 do
		for c = 0, COLS - 1 do
			local i = r * stride + c
			tris:add(i, i + 1, i + stride)
			tris:add(i + 1, i + stride + 1, i + stride)
		end
	end
	self.uvs = uvs
	self.uvsMirrored = mirrored
	self.tris = tris
end

-- The shine is rendered by a WGSL pass into a small GPU canvas, then laid
-- over each visible face with the face's own projected mesh. Runtimes
-- without GPU canvases simply draw the card without it.
local function buildShine(self: TarotCard3D, context: Context)
	local shader = context:shader('cosmic_shine')
	if shader == nil then
		print('TarotCard3D: shader "cosmic_shine" not found; no shine')
		return
	end
	local ok, err = pcall(function()
		local canvas = context:gpuCanvas({ width = 128, height = 224 })
		local pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = canvas.format } },
		})
		local uniforms = GPUBuffer.new({ size = 32, usage = 'uniform' })
		self.shineBindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = uniforms } },
		})
		self.shineCanvas = canvas
		self.shinePipeline = pipeline
		self.shineUniforms = uniforms
	end)
	if not ok then
		print('TarotCard3D: shine unavailable: ' .. tostring(err))
		self.shinePipeline = nil
	end
end

-- Returns the shine image for this frame, or nil.
local function renderShine(self: TarotCard3D): Image?
	local pipeline, canvas = self.shinePipeline, self.shineCanvas
	local uniforms, bindings = self.shineUniforms, self.shineBindings
	if self.shine <= 0 or pipeline == nil or canvas == nil or uniforms == nil or bindings == nil then
		return nil
	end
	buffer.writef32(self.shineParams, 0, self.time + self.shineOffset)
	buffer.writef32(self.shineParams, 4, self.shine)
	buffer.writef32(self.shineParams, 8, self.width)
	buffer.writef32(self.shineParams, 12, self.height)
	buffer.writef32(self.shineParams, 16, math.max(0.05, self.shineWidth))
	uniforms:write(self.shineParams)
	local pass = canvas:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipeline)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()
	return canvas.image
end

function init(self: TarotCard3D, context: Context): boolean
	self.context = context
	self.shineOffset = math.random() * 4
	buildMesh(self)
	buildInstances(self)
	watchFace(self, context)
	buildShine(self, context)
	return true
end

function update(self: TarotCard3D)
	local ctx = self.context
	if ctx ~= nil then
		watchFace(self, ctx)
	end
end

function advance(self: TarotCard3D, seconds: number): boolean
	self.time += seconds
	local ctx = self.context
	if ctx ~= nil and self.sourceFace == nil then
		watchFace(self, ctx)
	end
	if self.backInst then
		self.backInst:advance(seconds)
	end
	if self.frontInst then
		self.frontInst:advance(seconds)
	end
	return true
end

-- Rotation of a local point: Rz * Ry * Rx.
type Basis = {
	cx: number, sx: number,
	cy: number, sy: number,
	cz: number, sz: number,
}

local function rotate(b: Basis, x: number, y: number, z: number): (number, number, number)
	-- Rx
	local y1 = y * b.cx - z * b.sx
	local z1 = y * b.sx + z * b.cx
	-- Ry
	local x2 = x * b.cy + z1 * b.sy
	local z2 = -x * b.sy + z1 * b.cy
	-- Rz
	local x3 = x2 * b.cz - y1 * b.sz
	local y3 = x2 * b.sz + y1 * b.cz
	return x3, y3, z2
end

-- Perspective, normalized so the camera-facing side at rest keeps its
-- authored size.
local function project(x: number, y: number, z: number, restZ: number): Vector
	local k = (CAMERA - restZ) / (CAMERA - z)
	return Vector.xy(x * k, y * k)
end

local function faceVisible(b: Basis, nx: number, ny: number, nz: number, cx: number, cy: number, cz: number): boolean
	local wx, wy, wz = rotate(b, nx, ny, nz)
	local px, py, pz = rotate(b, cx, cy, cz)
	return wx * (0 - px) + wy * (0 - py) + wz * (CAMERA - pz) > 0
end

-- Returns false when the canvas cannot take a frame yet. Web runtimes can
-- hand back a canvas whose backing image is not allocated on the first
-- frames; the caller keeps the texture pending and tries again.
local function renderCanvas(canvas: Canvas?, inst: Artboard?): boolean
	if canvas == nil or inst == nil then
		return false
	end
	if canvas.width <= 0 or canvas.image == nil then
		return false
	end
	inst:advance(0)
	local r = canvas:beginFrame()
	r:save()
	r:transform(Mat2D.withScale(TEX_SCALE, TEX_SCALE))
	inst:draw(r)
	r:restore()
	canvas:endFrame()
	return true
end

local function drawFace(
	self: TarotCard3D,
	renderer: Renderer,
	b: Basis,
	canvas: Canvas?,
	z: number,
	restZ: number,
	mirrored: boolean,
	shade: number,
	shineImage: Image?
)
	if canvas == nil then
		return
	end
	local image = canvas.image
	if image == nil then
		return
	end
	local w = self.width
	local h = self.height
	local verts = VertexBuffer()
	for r = 0, ROWS do
		for c = 0, COLS do
			local x = -w / 2 + w * c / COLS
			local y = -h / 2 + h * r / ROWS
			local px, py, pz = rotate(b, x, y, z)
			verts:add(project(px, py, pz, restZ))
		end
	end
	renderer:drawImageMesh(
		image,
		self.sampler,
		verts,
		if mirrored then self.uvsMirrored else self.uvs,
		self.tris,
		'srcOver',
		1
	)

	if shineImage ~= nil then
		renderer:drawImageMesh(
			shineImage,
			self.sampler,
			verts,
			if mirrored then self.uvsMirrored else self.uvs,
			self.tris,
			'screen',
			1
		)
	end

	-- Dim the face as it turns edge-on. A dark overlay rather than
	-- modulateColor: the web runtime applies color modulation to the whole
	-- scene, not just this draw.
	if shade < 0.995 then
		local corners = { { -w / 2, -h / 2 }, { w / 2, -h / 2 }, { w / 2, h / 2 }, { -w / 2, h / 2 } }
		local path = Path.new()
		for i, c in corners do
			local px, py, pz = rotate(b, c[1], c[2], z)
			local v = project(px, py, pz, restZ)
			if i == 1 then
				path:moveTo(v)
			else
				path:lineTo(v)
			end
		end
		path:close()
		self.shadePaint.color = Color.rgba(8, 5, 26, math.floor(255 * (1 - shade)))
		renderer:drawPath(path, self.shadePaint)
	end
end

local function drawQuad(
	renderer: Renderer,
	paint: Paint,
	b: Basis,
	restZ: number,
	corners: { { number } }
)
	local path = Path.new()
	for i, p in corners do
		local px, py, pz = rotate(b, p[1], p[2], p[3])
		local v = project(px, py, pz, restZ)
		if i == 1 then
			path:moveTo(v)
		else
			path:lineTo(v)
		end
	end
	path:close()
	renderer:drawPath(path, paint)
end

function draw(self: TarotCard3D, renderer: Renderer)
	local w = self.width
	local h = self.height
	local d = math.max(0, self.depth)
	local hw, hh, hd = w / 2, h / 2, d / 2

	local b: Basis = {
		cx = math.cos(self.rotationX), sx = math.sin(self.rotationX),
		cy = math.cos(self.rotationY), sy = math.sin(self.rotationY),
		cz = math.cos(self.rotationZ), sz = math.sin(self.rotationZ),
	}

	local backVisible = faceVisible(b, 0, 0, 1, 0, 0, hd)
	local frontVisible = faceVisible(b, 0, 0, -1, 0, 0, -hd)

	-- Sides first; the visible face then covers where they meet it. The
	-- rounded corners of the textures leave the side strips inset a little.
	if d > 0 then
		local inset = 7
		local sides: { { n: { number }, c: { { number } } } } = {
			{ n = { 1, 0, 0 }, c = { { hw, -hh + inset, hd }, { hw, hh - inset, hd }, { hw, hh - inset, -hd }, { hw, -hh + inset, -hd } } },
			{ n = { -1, 0, 0 }, c = { { -hw, -hh + inset, hd }, { -hw, hh - inset, hd }, { -hw, hh - inset, -hd }, { -hw, -hh + inset, -hd } } },
			{ n = { 0, -1, 0 }, c = { { -hw + inset, -hh, hd }, { hw - inset, -hh, hd }, { hw - inset, -hh, -hd }, { -hw + inset, -hh, -hd } } },
			{ n = { 0, 1, 0 }, c = { { -hw + inset, hh, hd }, { hw - inset, hh, hd }, { hw - inset, hh, -hd }, { -hw + inset, hh, -hd } } },
		}
		for _, side in sides do
			local n = side.n
			if faceVisible(b, n[1], n[2], n[3], n[1] * hw, n[2] * hh, 0) then
				drawQuad(renderer, self.edgePaint, b, hd, side.c)
			end
		end
	end

	-- Face shading: full brightness square-on, dimmer edge-on.
	local facing = math.abs(b.cy * b.cx)
	local shade = 0.55 + 0.45 * facing

	local shineImage = renderShine(self)

	if backVisible then
		if self.backPending > 0 and renderCanvas(self.backCanvas, self.backInst) then
			self.backPending -= 1
		end
		drawFace(self, renderer, b, self.backCanvas, hd, hd, false, shade, shineImage)
	end
	if frontVisible then
		if self.frontPending > 0 and renderCanvas(self.frontCanvas, self.frontInst) then
			self.frontPending -= 1
		end
		drawFace(self, renderer, b, self.frontCanvas, -hd, hd, true, shade, shineImage)
	end
end

return function(): Node<TarotCard3D>
	return {
		back = late(),
		front = late(),
		width = 160,
		height = 280,
		depth = 8,
		rotationY = 0,
		rotationX = 0,
		rotationZ = 0,
		viewModelProperty = '',
		shine = 0.85,
		shineWidth = 1,

		context = nil,
		time = 0,
		shineOffset = 0,
		shinePipeline = nil,
		shineCanvas = nil,
		shineUniforms = nil,
		shineBindings = nil,
		shineParams = buffer.create(32),
		backInst = nil,
		frontInst = nil,
		frontVm = nil,
		sourceFace = nil,
		backCanvas = nil,
		frontCanvas = nil,
		backPending = 2,
		frontPending = 2,
		sampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		uvs = VertexBuffer(),
		uvsMirrored = VertexBuffer(),
		tris = TriangleBuffer(),
		edgePaint = Paint.with({ style = 'fill', color = Color.rgb(201, 168, 76) }),
		shadePaint = Paint.with({ style = 'fill', color = Color.rgba(8, 5, 26, 0) }),

		init = init,
		update = update,
		advance = advance,
		draw = draw,
	}
end
