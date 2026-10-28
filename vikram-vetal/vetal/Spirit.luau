-- Spirit: the Vetal as a module, for any script that draws him (Vetal.luau,
-- his own page; later the scene). The same API as Hero (Vikram):
--
--   local Spirit = require('Spirit')
--   local vetal = Spirit.load(context, 'vetal')      -- vetal.bin
--   Spirit.advance(vetal, dt, 0, speed)               -- he hangs, swaying
--   Spirit.write(vetal, u, settings)                  -- his part of the uniforms
--   Spirit.pipelines(vetal, shader, format, samples)  -- vetal.wgsl
--   Spirit.drawShadow(vetal, pass, ubo, shadowView, shadowSampler)
--   Spirit.draw(vetal, pass, ubo, shadowView, shadowSampler, outline)
--
-- He is painted by vertex (no textures): ash-grey skin, yellowed cloth,
-- white hair; his eyes burn (`eyeGlow`, `eyeColor`) and a white spirit
-- light clings to him and surrounds him in a soft aura (`spirit`,
-- `spiritColor`). He hangs upside down
-- from the origin (the point on the branch, where vetal.bin's placement
-- says it is in the scene); the wind takes his hair and cloth as painted in
-- Blender. The host writes the camera, the light, the sky and the mist
-- (vetal.wgsl's first block, as king.wgsl's) and owns the passes.

local Spirit = {}

-- vetal.wgsl's uniforms: laid out as king.wgsl's, so a stage written for
-- Vikram draws him too.
Spirit.BONES = 928
Spirit.MAX_JOINTS = 80
Spirit.UNIFORM_SIZE = Spirit.BONES + Spirit.MAX_JOINTS * 48
local BONES = Spirit.BONES
local VERTEX_STRIDE = 32
-- His aura: how far it reaches past his outline (metres), in how many
-- layers.
local AURA_REACH = 0.35
local AURA_LAYERS = 16
local DEPTH_FORMAT: 'depth32float' = 'depth32float'

type Loop = {
	data: buffer,
	offset: number,
	frames: number,
	fps: number,
}

export type Settings = {
	-- Where he hangs from (metres) and his turn (degrees about Y).
	x: number,
	y: number,
	z: number,
	turn: number,
	eyeGlow: number,
	eyeColor: Color,
	spirit: number,
	spiritColor: Color,
	windX: number,
	windZ: number,
	windStrength: number,
	windPhase: number,
	gustiness: number,
	hairWind: number,
	clothWind: number,
	paint: number,
	bands: number,
	-- Ink outline width, in pixels of the target.
	outline: number,
	inkColor: Color,
	inkDetail: number,
	hatching: number,
	time: number,
	-- The brightest he may be (linear; 0 for no limit): a host whose post
	-- pass streams light shafts from bright pixels keeps him under its
	-- threshold.
	ceiling: number?,
}

export type Spirit = {
	loops: { Loop },
	loopTimes: { number },
	jointCount: number,
	-- Where he hangs in the scene (vetal.bin): x, y, z, turn; and the glow
	-- painted on his eyes (linear rgb, strength).
	placement: { number },
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	-- One id per layer of his aura (instances).
	auraLayers: GPUBuffer,
	-- Stand-ins for the texture bindings vetal.wgsl shares with king.wgsl,
	-- for runtimes that bind every binding in a module.
	placeholderViews: { GPUTextureView },
	textureSampler: GPUSampler,
	bodyPipeline: GPUPipeline?,
	outlinePipeline: GPUPipeline?,
	shadowPipeline: GPUPipeline?,
	glowPipeline: GPUPipeline?,
	bodyBindings: GPUBindGroup?,
	outlineBindings: GPUBindGroup?,
	glowBindings: GPUBindGroup?,
	shadowBindings: GPUBindGroup?,
	boundUbo: GPUBuffer?,
}

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function linear(c: Color): (number, number, number)
	local r, g, b = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return (r / 255) ^ 2.2, (g / 255) ^ 2.2, (b / 255) ^ 2.2
end

local function write4(u: buffer, offset: number, a: number, b: number, c: number, d: number)
	buffer.writef32(u, offset, a)
	buffer.writef32(u, offset + 4, b)
	buffer.writef32(u, offset + 8, c)
	buffer.writef32(u, offset + 12, d)
end

local function writeColor(u: buffer, offset: number, c: Color, w: number)
	local r, g, b = linear(c)
	write4(u, offset, r, g, b, w)
end

local function slice(data: buffer, offset: number, length: number, usage: 'vertex' | 'index'): GPUBuffer
	local size = math.max(4, math.ceil(length / 4) * 4)
	local bytes = buffer.create(size)
	buffer.copy(bytes, 0, data, offset, length)
	return GPUBuffer.new({ size = size, usage = usage, data = bytes, immutable = true })
end

---------------------------------------------------------------------------
-- Loading

-- Him, from the blob asset `asset` (vetal.bin, ../tools/export_vetal.py).
function Spirit.load(context: Context, asset: string): (Spirit?, string?)
	local blob = context:blob(asset)
	if blob == nil then
		return nil, `no blob asset named '{asset}'`
	end
	local data = blob.data
	if buffer.len(data) < 16 or buffer.readstring(data, 0, 4) ~= 'VVTL' then
		return nil, `'{asset}' is not a vetal.bin`
	end
	local count = buffer.readu32(data, 8)
	local jointCount = buffer.readu32(data, 12)
	local loops: { Loop } = {}
	local placement: { number } = {}
	local vb: GPUBuffer? = nil
	local ib: GPUBuffer? = nil
	local indexCount = 0
	for s = 0, count - 1 do
		local at = 16 + s * 32
		local kind = buffer.readu32(data, at)
		local offset = buffer.readu32(data, at + 4)
		local length = buffer.readu32(data, at + 8)
		local a = buffer.readu32(data, at + 12)
		local b = buffer.readu32(data, at + 16)
		local c = buffer.readf32(data, at + 20)
		if kind == 1 then
			vb = slice(data, offset, length, 'vertex')
		elseif kind == 2 then
			ib = slice(data, offset, length, 'index')
			indexCount = a
		elseif kind == 3 then
			loops[b + 1] = { data = data, offset = offset, frames = a, fps = c }
		elseif kind == 4 then
			for k = 0, length // 4 - 1 do
				placement[k + 1] = buffer.readf32(data, offset + k * 4)
			end
		end
	end
	if vb == nil or ib == nil or #loops < 1 then
		return nil, `'{asset}' is missing the body or its loop`
	end
	local px = buffer.create(4)
	buffer.writeu8(px, 0, 128)
	buffer.writeu8(px, 1, 128)
	buffer.writeu8(px, 2, 255)
	buffer.writeu8(px, 3, 255)
	local views: { GPUTextureView } = {}
	for _ = 1, 3 do
		local tex = GPUTexture.new({ width = 1, height = 1, label = 'vetal placeholder' })
		tex:upload({ data = px, width = 1, height = 1 })
		table.insert(views, tex:view())
	end
	local ids = buffer.create(AURA_LAYERS * 4)
	for k = 0, AURA_LAYERS - 1 do
		buffer.writef32(ids, k * 4, k)
	end
	local auraLayers = GPUBuffer.new({ size = AURA_LAYERS * 4, usage = 'vertex', data = ids, immutable = true })
	local spirit: Spirit = {
		loops = loops,
		loopTimes = { 0 },
		jointCount = math.min(jointCount, Spirit.MAX_JOINTS),
		placement = placement,
		vertexBuffer = vb :: GPUBuffer,
		indexBuffer = ib :: GPUBuffer,
		indexCount = indexCount,
		auraLayers = auraLayers,
		placeholderViews = views,
		textureSampler = GPUSampler.new({ min = 'linear', mag = 'linear' }),
		bodyPipeline = nil,
		outlinePipeline = nil,
		shadowPipeline = nil,
		glowPipeline = nil,
		bodyBindings = nil,
		outlineBindings = nil,
		glowBindings = nil,
		shadowBindings = nil,
		boundUbo = nil,
	}
	return spirit, nil
end

---------------------------------------------------------------------------
-- Time

-- He has one pose: hanging, swaying (`pose` is accepted, as Hero's, and
-- ignored).
function Spirit.advance(spirit: Spirit, dt: number, pose: number, speed: number)
	spirit.loopTimes[1] += dt * clamp(speed, 0, 3)
end

-- How much of a pose he is in: hanging is all of him.
function Spirit.mix(spirit: Spirit, pose: number): number
	return if pose == 0 then 1 else 0
end

---------------------------------------------------------------------------
-- Uniforms

-- The skin matrices for now: the loop's two nearest keys, blended.
local function writeBones(spirit: Spirit, u: buffer)
	local loop = spirit.loops[1]
	local floats = spirit.jointCount * 12
	local stride = spirit.jointCount * 48
	local span = loop.frames - 1
	local f = (spirit.loopTimes[1] * loop.fps) % span
	local i = math.min(math.floor(f), span - 1)
	local k = f - i
	local a, b = loop.offset + i * stride, loop.offset + (i + 1) * stride
	local data = loop.data
	for j = 0, floats - 1 do
		local o = j * 4
		local x = buffer.readf32(data, a + o)
		buffer.writef32(u, BONES + o, x + (buffer.readf32(data, b + o) - x) * k)
	end
end

-- His part of vetal.wgsl's uniforms (the host writes the rest).
function Spirit.write(spirit: Spirit, u: buffer, s: Settings)
	writeColor(u, 224, s.inkColor, clamp(s.outline, 0, 12))
	write4(u, 240, clamp(s.paint, 0, 1), clamp(math.floor(s.bands + 0.5), 2, 6), clamp(s.inkDetail, 0, 1), clamp(s.hatching, 0, 1))
	-- Where he hangs from, turned about Y (column-major).
	local a = math.rad(s.turn)
	local c, sn = math.cos(a), math.sin(a)
	write4(u, 320, c, 0, -sn, 0)
	write4(u, 336, 0, 1, 0, 0)
	write4(u, 352, sn, 0, c, 0)
	write4(u, 368, s.x, s.y, s.z, 1)
	-- His eyes' glow, and the spirit light on him and in his aura (king.wgsl's
	-- earColor and aura slots: how much, the aura's reach and layers).
	writeColor(u, 576, s.eyeColor, clamp(s.eyeGlow, 0, 4))
	write4(u, 608, clamp(s.spirit, 0, 3), AURA_REACH, AURA_LAYERS, math.max(s.ceiling or 0, 0))
	writeColor(u, 624, s.spiritColor, clamp(s.spirit, 0, 3))
	-- The wind in his hair and cloth.
	local wl = math.sqrt(s.windX * s.windX + s.windZ * s.windZ)
	local blowX, blowZ = if wl > 1e-6 then s.windX / wl else 1, if wl > 1e-6 then s.windZ / wl else 0
	write4(u, 896, blowX, blowZ, clamp(s.windStrength, 0, 4), s.windPhase)
	write4(u, 912, clamp(s.hairWind, 0, 3), clamp(s.clothWind, 0, 3), clamp(s.gustiness, 0, 1), 0)
	writeBones(spirit, u)
end

---------------------------------------------------------------------------
-- Pipelines and drawing

-- His pipelines for a target: vetal.wgsl, the target's colour format and
-- sample count, depth32float with reverse Z (greater is nearer); the
-- shadow pass's depth is plain (less is nearer).
function Spirit.pipelines(spirit: Spirit, shader: Shader, format: any, samples: number)
	local target: { ColorTarget } = { { format = format } }
	local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
	local body: { VertexBufferLayout } = {
		{
			stride = VERTEX_STRIDE,
			attributes = {
				{ format = 'float32x3', slot = 0, offset = 0 },
				{ format = 'snorm8x4', slot = 1, offset = 12 },
				{ format = 'unorm8x4', slot = 2, offset = 16 },
				{ format = 'uint8x4', slot = 3, offset = 20 },
				{ format = 'unorm8x4', slot = 4, offset = 24 },
				{ format = 'unorm8x4', slot = 5, offset = 28 },
			},
		},
	}
	spirit.bodyPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_vetal' },
		fragment = { module = shader, entryPoint = 'fs_vetal' },
		vertexLayout = body,
		colorTargets = target,
		depthStencil = depth,
		cullMode = 'none',
		sampleCount = samples,
	})
	-- The outline: the body inside out, so only its rim shows past him.
	spirit.outlinePipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_vetal_outline' },
		fragment = { module = shader, entryPoint = 'fs_outline' },
		vertexLayout = body,
		colorTargets = target,
		depthStencil = depth,
		cullMode = 'front',
		sampleCount = samples,
	})
	-- The aura: his body in layers (one instance each), added over what is
	-- behind him, never hiding it.
	local layered: { VertexBufferLayout } = {
		body[1],
		{ stride = 4, stepMode = 'instance', attributes = { { format = 'float32', slot = 6, offset = 0 } } },
	}
	spirit.glowPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_vetal_glow' },
		fragment = { module = shader, entryPoint = 'fs_vetal_glow' },
		vertexLayout = layered,
		colorTargets = {
			{
				format = format,
				blend = {
					srcColor = 'one',
					dstColor = 'one-minus-src-alpha',
					colorOp = 'add',
					srcAlpha = 'zero',
					dstAlpha = 'one',
					alphaOp = 'add',
				},
			},
		},
		depthStencil = { format = DEPTH_FORMAT, compare = 'greater', write = false },
		cullMode = 'back',
		sampleCount = samples,
	})
	spirit.shadowPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_vetal_shadow' },
		vertexLayout = body,
		depthStencil = { format = DEPTH_FORMAT, compare = 'less', write = true },
		cullMode = 'none',
	})
	spirit.bodyBindings = nil
	spirit.boundUbo = nil
end

-- A pipeline's bindings: only what it uses, as WebGPU's layouts list. Some
-- runtimes list every binding in the module for every pipeline instead;
-- then the full set (the shadow map, and placeholders for the texture
-- bindings king.wgsl's stage shares) is bound.
local function bindings(spirit: Spirit, pipeline: GPUPipeline, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler, useShadow: boolean): GPUBindGroup
	local function make(full: boolean): GPUBindGroup
		local entries: { TextureEntry } = {}
		local samplers: { SamplerEntry } = {}
		if useShadow or full then
			table.insert(entries, { slot = 1, view = shadowView })
			table.insert(samplers, { slot = 2, sampler = shadowSampler })
		end
		if full then
			for i, v in spirit.placeholderViews do
				table.insert(entries, { slot = 2 + i, view = v })
			end
			table.insert(samplers, { slot = 6, sampler = spirit.textureSampler })
		end
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = entries,
			samplers = samplers,
		})
	end
	local ok, group = pcall(make, false)
	if ok then
		return group
	end
	return make(true)
end

local function bind(spirit: Spirit, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler): boolean
	local bodyP, outlineP, shadowP, glowP = spirit.bodyPipeline, spirit.outlinePipeline, spirit.shadowPipeline, spirit.glowPipeline
	if not (bodyP and outlineP and shadowP and glowP) then
		return false
	end
	if spirit.boundUbo ~= ubo or spirit.bodyBindings == nil then
		spirit.boundUbo = ubo
		spirit.bodyBindings = bindings(spirit, bodyP, ubo, shadowView, shadowSampler, true)
		spirit.outlineBindings = bindings(spirit, outlineP, ubo, shadowView, shadowSampler, false)
		spirit.shadowBindings = bindings(spirit, shadowP, ubo, shadowView, shadowSampler, false)
		spirit.glowBindings = bindings(spirit, glowP, ubo, shadowView, shadowSampler, false)
	end
	return true
end

local function body(spirit: Spirit, pass: GPURenderPass)
	pass:setVertexBuffer(0, spirit.vertexBuffer)
	pass:setIndexBuffer(spirit.indexBuffer, 'uint16')
	pass:drawIndexed(spirit.indexCount)
end

-- Him, into a shadow pass (depth only, his ubo's lightViewProj).
function Spirit.drawShadow(spirit: Spirit, pass: GPURenderPass, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler)
	if not bind(spirit, ubo, shadowView, shadowSampler) then
		return
	end
	local shadowP, shadowB = spirit.shadowPipeline, spirit.shadowBindings
	if shadowP and shadowB then
		pass:setPipeline(shadowP)
		pass:setBindGroup(0, shadowB)
		body(spirit, pass)
	end
end

-- Him, into the scene's pass: his ink outline, his body, then his aura.
function Spirit.draw(spirit: Spirit, pass: GPURenderPass, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler, outline: boolean)
	if not bind(spirit, ubo, shadowView, shadowSampler) then
		return
	end
	local bodyP, bodyB = spirit.bodyPipeline, spirit.bodyBindings
	local outlineP, outlineB = spirit.outlinePipeline, spirit.outlineBindings
	if outline and outlineP and outlineB then
		pass:setPipeline(outlineP)
		pass:setBindGroup(0, outlineB)
		body(spirit, pass)
	end
	if bodyP and bodyB then
		pass:setPipeline(bodyP)
		pass:setBindGroup(0, bodyB)
		body(spirit, pass)
	end
	local glowP, glowB = spirit.glowPipeline, spirit.glowBindings
	if glowP and glowB then
		pass:setPipeline(glowP)
		pass:setBindGroup(0, glowB)
		pass:setVertexBuffer(0, spirit.vertexBuffer)
		pass:setVertexBuffer(1, spirit.auraLayers)
		pass:setIndexBuffer(spirit.indexBuffer, 'uint16')
		pass:drawIndexed(spirit.indexCount, AURA_LAYERS)
	end
end

return Spirit
