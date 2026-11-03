-- Hero: King Vikram as a module, for any script that draws him (King.luau,
-- his own page; World.luau, the scene and the story).
--
--   local Hero = require('Hero')
--   local hero = Hero.load(context, 'king')         -- king.bin
--   Hero.advance(hero, dt, pose, speed, blend?)      -- 0 idle, 1 walk, 2 draw, 3 shoot,
--                                                    -- 4 hold at full draw, 5 loose,
--                                                    -- 9-12 struck (Hero.HIT_*), 13 fall
--   Hero.aim(hero, pitch)                            -- drawn, the bow aims up or down
--   Hero.write(hero, u, settings)                    -- his part of the uniforms
--   Hero.pipelines(hero, shader, format, samples)    -- king.wgsl
--   Hero.drawShadow(hero, pass, ubo, shadowView, shadowSampler)
--   Hero.draw(hero, pass, ubo, shadowView, shadowSampler)
--
-- The host writes the rest of king.wgsl's uniforms (the camera, the moon
-- and fire, the sky and mist, the viewport) and owns the render passes;
-- Hero writes where he stands, his eyes, earrings and blink, the bones, the
-- bow's shape key and its aura, and draws his body, its ink outline, the
-- earrings' halos and the aura.
--
-- For the game the shot comes in parts: the draw (pose 2) into the hold at
-- full draw (pose 4, a loop) and the loose (pose 5: the string lets go at
-- its key, and he follows through). Drawn, `Hero.aim` pitches his upper body
-- (degrees, + up; blending the GLB's three aim poses) so the bow points up
-- or down.
--
-- Struck (a ghost light breaking on him), he reacts from the side it came
-- (Hero.HIT_FRONT, _BACK, _LEFT, _RIGHT: in place, about 0.75 s, the
-- impact Hero.HIT_IMPACT seconds in); felled, he goes down to one knee and
-- stays (Hero.FALL). Pass a quicker `blend` (5 is the usual, about half a
-- second) for a hit to land sharply.
--
-- The release (`settings.release`, 0-1 over about 3 s): the string snaps
-- home from full draw and shivers still, a flash at the grip, and rings of
-- gold ripple out from the bow in three planes. Hold it at 1 and the string
-- stays slack; set it back to 0 to draw again. The shoot (pose 3) draws,
-- looses and follows through by itself, and its release starts at the key
-- where the string lets go.
--
-- The wind (`settings.windX/Z` its direction, `windStrength`, `windPhase`
-- its accumulated phase, `gustiness`) blows his hair and cloth as painted
-- in Blender (the body's _WIND attribute), `hairWind` and `clothWind` how
-- much each takes it.

local Hero = {}

-- king.wgsl's uniforms: the host's part, then his, then the bones.
Hero.BONES = 928
Hero.MAX_JOINTS = 80
Hero.UNIFORM_SIZE = Hero.BONES + Hero.MAX_JOINTS * 48
local BONES = Hero.BONES
local BOW_SAMPLES = 13
-- The loops, as king.bin has them (1-based): the poses, then the aim poses.
local DRAW, SHOOT, HOLD, LOOSE = 3, 4, 5, 6
local AIM_LEVEL, AIM_UP, AIM_DOWN = 7, 8, 9
-- The aim poses pitch the bow this far (degrees) up and down.
local AIM_UP_DEGREES, AIM_DOWN_DEGREES = 45, 35
-- Then the reactions: struck from the front, back, left and right, and the
-- fall; as poses (0-based) for Hero.advance.
local HIT_FIRST = 10
Hero.HIT_FRONT, Hero.HIT_BACK, Hero.HIT_LEFT, Hero.HIT_RIGHT = 9, 10, 11, 12
Hero.FALL = 13
Hero.HIT_IMPACT = 0.125
-- The aura's pieces (king.wgsl's vs_aura), the ripples last.
local AURA_PIECES = 523
local VERTEX_STRIDE = 32
local DEPTH_FORMAT: 'depth32float' = 'depth32float'

type Loop = {
	data: buffer,
	offset: number,
	frames: number,
	fps: number,
	-- The bow's shape key weight at each key, and (for the draw) the first
	-- key at full draw, where the hold begins; (for the shoot) the first key
	-- after it where the string has let go, or -1.
	weights: { number },
	holdFrom: number,
	letGo: number,
}

export type Settings = {
	-- Where he stands (metres) and faces (degrees about Y; 0 faces +Z).
	x: number,
	y: number,
	z: number,
	turn: number,
	eyes: number,
	blink: number,
	earringGlow: number,
	earringColor: Color,
	aura: number,
	auraColor: Color,
	release: number,
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
}

export type Hero = {
	loops: { Loop },
	-- How much he aims up and down (0-1 each; the aim poses' shares).
	aimUp: number,
	aimDown: number,
	-- Each loop's time (seconds) and share of the pose (summing to 1).
	loopTimes: { number },
	mixes: { number },
	lastPose: number,
	-- How far the string is drawn now (the bow's shape key), before the
	-- release.
	pull: number,
	jointCount: number,
	headJoint: number,
	-- The eyes' and irises' centres, the earrings' gems (bind pose), the
	-- eyelids' colour.
	head: { number },
	-- Points along the bow (bind pose), 14 floats each; then its axis and
	-- the grip's and nock's joints.
	bowSamples: { number },
	bowAxis: { number },
	-- The bow's grip, where it was last written (world), for hosts.
	gripX: number,
	gripY: number,
	gripZ: number,
	vertexBuffer: GPUBuffer,
	morphBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	haloIds: GPUBuffer,
	auraIds: GPUBuffer,
	textureViews: { GPUTextureView },
	placeholderViews: { GPUTextureView },
	textureSampler: GPUSampler,
	pendingMips: number,
	texturesReady: boolean,
	-- Pipelines and their bindings (remade with the pipelines, or when the
	-- textures arrive).
	kingPipeline: GPUPipeline?,
	outlinePipeline: GPUPipeline?,
	shadowPipeline: GPUPipeline?,
	motePipeline: GPUPipeline?,
	auraPipeline: GPUPipeline?,
	kingBindings: GPUBindGroup?,
	outlineBindings: GPUBindGroup?,
	shadowBindings: GPUBindGroup?,
	moteBindings: GPUBindGroup?,
	auraBindings: GPUBindGroup?,
	boundUbo: GPUBuffer?,
	boundReal: boolean,
	auraOn: boolean,
	haloOn: boolean,
}

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function linear(c: Color): (number, number, number)
	local r, g, b = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return (r / 255) ^ 2.2, (g / 255) ^ 2.2, (b / 255) ^ 2.2
end

local function write4(u: buffer, offset: number, x: number, y: number, z: number, w: number)
	buffer.writef32(u, offset, x)
	buffer.writef32(u, offset + 4, y)
	buffer.writef32(u, offset + 8, z)
	buffer.writef32(u, offset + 12, w)
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

local function ids(from: number, count: number): GPUBuffer
	local b = buffer.create(count * 4)
	for i = 0, count - 1 do
		buffer.writef32(b, i * 4, from + i)
	end
	return GPUBuffer.new({ size = count * 4, usage = 'vertex', data = b, immutable = true })
end

---------------------------------------------------------------------------
-- Loading

-- Reads king.bin (../tools/export_king.py). The textures decode in the
-- background; until they are in, he is drawn in plain colours.
function Hero.load(context: Context, asset: string): (Hero?, string?)
	local blob = context:blob(asset)
	if blob == nil then
		return nil, `no blob asset named '{asset}'`
	end
	local data = blob.data
	if buffer.len(data) < 16 or buffer.readstring(data, 0, 4) ~= 'VKNG' then
		return nil, `'{asset}' is not a king.bin`
	end
	local count = buffer.readu32(data, 8)
	local loops: { Loop } = {}
	local head: { number } = {}
	local bowSamples: { number } = {}
	local bowAxis: { number } = {}
	local vb: GPUBuffer? = nil
	local ib: GPUBuffer? = nil
	local mb: GPUBuffer? = nil
	local indexCount = 0
	local headJoint = -1
	-- Texture mips by texture: { level, offset, length, width, height }.
	local mips: { [number]: { { number } } } = {}
	local function loopAt(index: number): Loop
		local loop = loops[index]
		if loop == nil then
			loop = { data = data, offset = 0, frames = 0, fps = 24, weights = {}, holdFrom = 0, letGo = -1 }
			loops[index] = loop
		end
		return loop
	end
	for i = 0, count - 1 do
		local at = 16 + i * 32
		local kind = buffer.readu32(data, at)
		local offset = buffer.readu32(data, at + 4)
		local length = buffer.readu32(data, at + 8)
		local a = buffer.readu32(data, at + 12)
		local b = buffer.readu32(data, at + 16)
		local c = buffer.readf32(data, at + 20)
		local e = buffer.readu32(data, at + 28)
		if kind == 1 then
			vb = slice(data, offset, length, 'vertex')
		elseif kind == 2 then
			ib = slice(data, offset, length, 'index')
			indexCount = a
		elseif kind == 3 then
			local loop = loopAt(b + 1)
			loop.offset, loop.frames, loop.fps = offset, a, c
		elseif kind == 6 then
			local loop = loopAt(b + 1)
			local most = 0
			for k = 0, a - 1 do
				local w = buffer.readf32(data, offset + k * 4)
				loop.weights[k + 1] = w
				most = math.max(most, w)
			end
			for k = 1, a do
				if loop.weights[k] >= most * 0.98 then
					loop.holdFrom = k - 1
					break
				end
			end
			for k = loop.holdFrom + 1, a do
				if most > 0 and loop.weights[k] < most * 0.5 then
					loop.letGo = k - 1
					break
				end
			end
		elseif kind == 5 then
			mb = slice(data, offset, length, 'vertex')
		elseif kind == 7 then
			for k = 0, length // 4 - 1 do
				local v = buffer.readf32(data, offset + k * 4)
				if k < (BOW_SAMPLES + 1) * 14 then
					table.insert(bowSamples, v)
				else
					table.insert(bowAxis, v)
				end
			end
		elseif kind == 4 then
			headJoint = a
			for k = 0, length // 4 - 1 do
				head[k + 1] = buffer.readf32(data, offset + k * 4)
			end
		elseif kind >= 10 and kind < 13 then
			local t = kind - 9
			local list = mips[t] or {}
			mips[t] = list
			table.insert(list, { e, offset, length, a, b })
		end
	end
	if vb == nil or ib == nil or mb == nil or #loops < 3 then
		return nil, `'{asset}' is missing the body, the bow or the loops`
	end
	-- Until the textures are in, a texel each: a plain skin tone, a flat
	-- normal, matte.
	local function plain(r: number, g: number, b: number): GPUTextureView
		local px = buffer.create(4)
		buffer.writeu8(px, 0, r)
		buffer.writeu8(px, 1, g)
		buffer.writeu8(px, 2, b)
		buffer.writeu8(px, 3, 255)
		local tex = GPUTexture.new({ width = 1, height = 1, label = 'king placeholder' })
		tex:upload({ data = px, width = 1, height = 1 })
		return tex:view()
	end
	local hero: Hero = {
		loops = loops,
		loopTimes = table.create(#loops, 0),
		mixes = table.create(#loops, 0),
		aimUp = 0,
		aimDown = 0,
		lastPose = 0,
		pull = 0,
		jointCount = math.min(buffer.readu32(data, 12), Hero.MAX_JOINTS),
		headJoint = headJoint,
		head = head,
		bowSamples = bowSamples,
		bowAxis = bowAxis,
		gripX = 0,
		gripY = 1,
		gripZ = 0,
		vertexBuffer = vb :: GPUBuffer,
		morphBuffer = mb :: GPUBuffer,
		indexBuffer = ib :: GPUBuffer,
		indexCount = indexCount,
		haloIds = ids(1000, 2),
		auraIds = ids(0, AURA_PIECES),
		textureViews = {},
		placeholderViews = { plain(170, 120, 90), plain(128, 128, 255), plain(0, 200, 0) },
		textureSampler = GPUSampler.new({
			min = 'linear',
			mag = 'linear',
			mipmap = 'linear',
			wrapU = 'clamp-to-edge',
			wrapV = 'clamp-to-edge',
			maxAnisotropy = 8,
		}),
		pendingMips = 0,
		texturesReady = false,
		kingPipeline = nil,
		outlinePipeline = nil,
		shadowPipeline = nil,
		motePipeline = nil,
		auraPipeline = nil,
		kingBindings = nil,
		outlineBindings = nil,
		shadowBindings = nil,
		moteBindings = nil,
		auraBindings = nil,
		boundUbo = nil,
		boundReal = false,
		auraOn = false,
		haloOn = false,
	}
	-- The textures: each mip is a JPEG, decoded and uploaded as it comes.
	for t = 1, 3 do
		local list = mips[t]
		if list == nil or #list == 0 then
			return nil, `'{asset}' is missing a texture`
		end
		table.sort(list, function(x: { number }, y: { number }): boolean
			return x[1] < y[1]
		end)
		local texture = GPUTexture.new({
			width = list[1][4],
			height = list[1][5],
			mipmaps = #list,
			label = if t == 1 then 'king colour' elseif t == 2 then 'king normal' else 'king rm',
		})
		hero.textureViews[t] = texture:view()
		for _, m in list do
			hero.pendingMips += 1
			local jpeg = buffer.create(m[3])
			buffer.copy(jpeg, 0, data, m[2], m[3])
			local level = m[1]
			context:decodeImage(jpeg):andThen(function(image: DecodedImage)
				texture:upload({ data = image.data, mipLevel = level, width = image.width, height = image.height })
				hero.pendingMips -= 1
				if hero.pendingMips == 0 then
					hero.texturesReady = true
				end
				return nil
			end)
		end
	end
	hero.mixes[1] = 1
	return hero, nil
end

---------------------------------------------------------------------------
-- Time

-- From one pose into the next over about half a second (0 idle, 1 walk, 2
-- draw, 3 shoot); the draw and the shoot start from the beginning each time.
function Hero.advance(hero: Hero, dt: number, pose: number, speed: number, blend: number?)
	local count = #hero.loops
	local p = clamp(math.floor(pose + 0.5), 0, count - 1)
	if p ~= hero.lastPose then
		if p >= 2 then
			hero.loopTimes[p + 1] = 0
		end
		hero.lastPose = p
	end
	local k = 1 - math.exp(-dt * (blend or 5))
	local s = clamp(speed, 0, 3)
	for i = 1, count do
		hero.loopTimes[i] += dt * s
		local target = if i == p + 1 then 1 else 0
		hero.mixes[i] += (target - hero.mixes[i]) * k
		if math.abs(target - hero.mixes[i]) < 0.002 then
			hero.mixes[i] = target
		end
	end
end

-- How much of each pose he is in now: idle, walk, draw, shoot, hold, loose.
function Hero.mix(hero: Hero, pose: number): number
	return hero.mixes[pose + 1] or 0
end

-- Where his bow aims, drawn: degrees above the level (below, negative).
function Hero.aim(hero: Hero, pitch: number)
	hero.aimUp = clamp(pitch / AIM_UP_DEGREES, 0, 1)
	hero.aimDown = clamp(-pitch / AIM_DOWN_DEGREES, 0, 1)
end

-- How long ago (seconds of the clip) the string let go, in the shoot or
-- the loose, whichever he is in; nil before it has (or in neither).
function Hero.sinceLetGo(hero: Hero): number?
	for _, li in { SHOOT, LOOSE } do
		local loop = hero.loops[li]
		if loop and loop.letGo >= 0 and hero.mixes[li] > 0.5 then
			local since = hero.loopTimes[li] - loop.letGo / loop.fps
			return if since >= 0 then since else nil
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Uniforms

-- Where a loop is at `time`: its two nearest keys and the blend between
-- them. Idle and walk loop; the draw plays once, then rocks back and forth
-- over its held part (full draw), so the hold never jumps; the shoot plays
-- once and holds its last key.
local function keysAt(loop: Loop, time: number, once: boolean, rock: boolean): (number, number, number)
	local span = loop.frames - 1
	local f = time * loop.fps
	if once then
		if rock and f > span then
			local hold = math.max(span - loop.holdFrom, 1)
			local q = (f - span) % (2 * hold)
			f = if q < hold then span - q else loop.holdFrom + (q - hold)
		end
		f = clamp(f, 0, span)
	else
		f = f % span
	end
	local i = math.min(math.floor(f), span - 1)
	return i, i + 1, f - i
end

-- The skin matrices for now: each loop's two nearest keys, blended by the
-- loops' shares of the pose; and how far the string is drawn. Drawn (in the
-- hold, the drawn end of the draw, the loose as it lets go), the aim poses
-- add how far up or down they pitch from the level one.
local function writeBones(hero: Hero, u: buffer)
	local joints = hero.jointCount
	local floats = joints * 12
	local stride = joints * 48
	local first = true
	local pull = 0
	for li, loop in hero.loops do
		local w = hero.mixes[li]
		if w > 0.0005 and (li < AIM_LEVEL or li > AIM_DOWN) then
			local once = li == DRAW or li == SHOOT or li == LOOSE or li >= HIT_FIRST
			local i0, i1, k = keysAt(loop, hero.loopTimes[li], once, li == DRAW)
			local wa, wb = loop.weights[i0 + 1] or 0, loop.weights[i1 + 1] or 0
			pull += (wa + (wb - wa) * k) * w
			local data = loop.data
			local a, b = loop.offset + i0 * stride, loop.offset + i1 * stride
			for j = 0, floats - 1 do
				local o = j * 4
				local x = buffer.readf32(data, a + o)
				local v = (x + (buffer.readf32(data, b + o) - x) * k) * w
				if not first then
					v += buffer.readf32(u, BONES + o)
				end
				buffer.writef32(u, BONES + o, v)
			end
			first = false
		end
	end
	hero.pull = pull
	local level, up, down = hero.loops[AIM_LEVEL], hero.loops[AIM_UP], hero.loops[AIM_DOWN]
	if level and up and down and not first then
		local drawn = (hero.mixes[HOLD] or 0) + (hero.mixes[DRAW] or 0) * clamp(pull, 0, 1)
		local loose = hero.loops[LOOSE]
		if loose and hero.mixes[LOOSE] > 0 then
			drawn += hero.mixes[LOOSE] * clamp(1 - hero.loopTimes[LOOSE] / 0.6, 0, 1)
		end
		local wu, wd = hero.aimUp * drawn, hero.aimDown * drawn
		if wu + wd > 0.001 then
			local dl, du, dd = level.data, up.data, down.data
			for j = 0, floats - 1 do
				local o = j * 4
				local l = buffer.readf32(dl, level.offset + o)
				local v = buffer.readf32(u, BONES + o)
					+ wu * (buffer.readf32(du, up.offset + o) - l)
					+ wd * (buffer.readf32(dd, down.offset + o) - l)
				buffer.writef32(u, BONES + o, v)
			end
		end
	end
end

-- His part of king.wgsl's uniforms (the host writes the rest).
function Hero.write(hero: Hero, u: buffer, s: Settings)
	local t = s.time
	writeColor(u, 224, s.inkColor, clamp(s.outline, 0, 12))
	write4(u, 240, clamp(s.paint, 0, 1), clamp(math.floor(s.bands + 0.5), 2, 6), clamp(s.inkDetail, 0, 1), clamp(s.hatching, 0, 1))
	-- Where he stands, turned about Y (column-major).
	local a = math.rad(s.turn)
	local c, sn = math.cos(a), math.sin(a)
	write4(u, 320, c, 0, -sn, 0)
	write4(u, 336, 0, 1, 0, 0)
	write4(u, 352, sn, 0, c, 0)
	write4(u, 368, s.x, s.y, s.z, 1)
	local function place(lx: number, ly: number, lz: number): (number, number, number)
		return c * lx + sn * lz + s.x, ly + s.y, -sn * lx + c * lz + s.z
	end
	writeBones(hero, u)

	-- The release: the string snaps home and shivers still. In the shoot
	-- and the loose it comes when the clip lets go of the string.
	local release = clamp(s.release, 0, 1)
	local since = Hero.sinceLetGo(hero)
	if since then
		release = math.max(release, math.min(since / 3, 1))
	end
	local snap = if release > 0 then math.min(release / 0.02, 1) else 0
	local secs = release * 3
	local shiver = math.sin(secs * 2 * math.pi * 7) * math.exp(-secs * 4.5) * 0.35
	local pull = clamp(hero.pull, 0, 1)
	local shape = pull * (1 - snap) + shiver * snap
	-- The nock returns to the grip with the string.
	local axis = hero.bowAxis
	if snap > 0 and #axis >= 9 and axis[8] >= 0 and axis[9] >= 0 then
		local grip, nock = BONES + axis[8] * 48, BONES + axis[9] * 48
		for o = 0, 44, 4 do
			local g = buffer.readf32(u, grip + o)
			local n = buffer.readf32(u, nock + o)
			buffer.writef32(u, nock + o, n + (g - n) * snap)
		end
	end

	-- The eyes, and where the earrings' gems are now: the head bone's skin
	-- matrix (just written) and where he stands.
	local h = hero.head
	local function skinned(row: number, x: number, y: number, z: number): (number, number, number)
		local function dot(o: number): number
			return buffer.readf32(u, row + o) * x + buffer.readf32(u, row + o + 4) * y
				+ buffer.readf32(u, row + o + 8) * z + buffer.readf32(u, row + o + 12)
		end
		return dot(0), dot(16), dot(32)
	end
	if #h >= 18 then
		write4(u, 480, h[1], h[2], h[3], 0)
		write4(u, 496, h[4], h[5], h[6], clamp(s.eyes, 0, 1))
		write4(u, 512, h[7], h[8], h[9], 0)
		write4(u, 528, h[10], h[11], h[12], 0)
		local row = BONES + hero.headJoint * 48
		local gx, gy, gz = place(skinned(row, h[13], h[14], h[15]))
		write4(u, 544, gx, gy, gz, clamp(s.earringGlow, 0, 3))
		gx, gy, gz = place(skinned(row, h[16], h[17], h[18]))
		write4(u, 560, gx, gy, gz, 0.5 + 0.5 * math.sin(t * 2.1) * math.sin(t * 0.7 + 1))
	end
	writeColor(u, 576, s.earringColor, 0)
	if #h >= 21 then
		write4(u, 592, h[19], h[20], h[21], clamp(s.blink, 0, 1))
	end

	-- The aura: it kindles as he raises the bow and burns at full draw; at
	-- the release it flares, then fades over the release.
	local amount = clamp(s.aura, 0, 2)
	local kindled = 0.15 * (hero.mixes[3] + (hero.mixes[4] or 0)) + 0.85 * pull
	if release > 0 then
		kindled = math.max(kindled * (1 - snap), (1 - release) ^ 1.5 * math.max(pull, 0.6))
	end
	local flash = if release > 0 then 2.5 * math.exp(-secs * 9) else 0
	hero.auraOn = amount * kindled > 0.005 or (release > 0 and release < 1)
	hero.haloOn = s.earringGlow > 0 and #h >= 18
	write4(u, 608, amount * kindled * (1 + flash), shape, release, flash)
	writeColor(u, 624, s.auraColor, amount)
	if #axis >= 7 then
		write4(u, 640, axis[1], axis[2], axis[3], axis[7])
		write4(u, 656, axis[4], axis[5], axis[6], 0)
	end
	-- The wind in his hair and cloth.
	local wl = math.sqrt(s.windX * s.windX + s.windZ * s.windZ)
	local blowX, blowZ = if wl > 1e-6 then s.windX / wl else 1, if wl > 1e-6 then s.windZ / wl else 0
	write4(u, 896, blowX, blowZ, clamp(s.windStrength, 0, 4), s.windPhase)
	write4(u, 912, clamp(s.hairWind, 0, 3), clamp(s.clothWind, 0, 3), clamp(s.gustiness, 0, 1), 0)
	-- Points along the bow, where they are now: each skinned by its bones
	-- (as the GPU skins the bow) and placed with him.
	local bs = hero.bowSamples
	for k = 0, math.min(#bs // 14, BOW_SAMPLES + 1) - 1 do
		local o = k * 14
		local px = bs[o + 1] + bs[o + 4] * shape
		local py = bs[o + 2] + bs[o + 5] * shape
		local pz = bs[o + 3] + bs[o + 6] * shape
		local lx, ly, lz = 0, 0, 0
		for m = 0, 3 do
			local w = bs[o + 11 + m]
			if w > 0 then
				local x, y, z = skinned(BONES + math.floor(bs[o + 7 + m]) * 48, px, py, pz)
				lx += x * w
				ly += y * w
				lz += z * w
			end
		end
		local wx, wy, wz = place(lx, ly, lz)
		write4(u, 672 + k * 16, wx, wy, wz, 0)
		if k == 6 then
			hero.gripX, hero.gripY, hero.gripZ = wx, wy, wz
		end
	end
end

---------------------------------------------------------------------------
-- Pipelines and drawing

-- His pipelines for a target: king.wgsl, the target's colour format (a
-- canvas's `format`) and sample count, depth32float with reverse Z (greater
-- is nearer); the shadow pass's depth is plain (less is nearer).
function Hero.pipelines(hero: Hero, shader: Shader, format: any, samples: number)
	local target: { ColorTarget } = { { format = format } }
	local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
	local glow: { ColorTarget } = {
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
	}
	local glowDepth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = false }
	local body: { VertexBufferLayout } = {
		{
			stride = VERTEX_STRIDE,
			attributes = {
				{ format = 'float32x3', slot = 0, offset = 0 },
				{ format = 'snorm8x4', slot = 1, offset = 12 },
				{ format = 'float32x2', slot = 2, offset = 16 },
				{ format = 'uint8x4', slot = 3, offset = 24 },
				{ format = 'unorm8x4', slot = 4, offset = 28 },
			},
		},
		{
			stride = 20,
			attributes = {
				{ format = 'float32x3', slot = 5, offset = 0 },
				{ format = 'snorm8x4', slot = 6, offset = 12 },
				{ format = 'unorm8x4', slot = 7, offset = 16 },
			},
		},
	}
	local idLayout: { VertexBufferLayout } = {
		{ stride = 4, stepMode = 'instance', attributes = { { format = 'float32', slot = 0, offset = 0 } } },
	}
	hero.kingPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_king' },
		fragment = { module = shader, entryPoint = 'fs_king' },
		vertexLayout = body,
		colorTargets = target,
		depthStencil = depth,
		cullMode = 'none',
		sampleCount = samples,
	})
	-- The outline: the body inside out, so only its rim shows past him.
	hero.outlinePipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_outline' },
		fragment = { module = shader, entryPoint = 'fs_outline' },
		vertexLayout = body,
		colorTargets = target,
		depthStencil = depth,
		cullMode = 'front',
		sampleCount = samples,
	})
	hero.motePipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_motes' },
		fragment = { module = shader, entryPoint = 'fs_motes' },
		vertexLayout = idLayout,
		colorTargets = glow,
		depthStencil = glowDepth,
		sampleCount = samples,
	})
	hero.auraPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_aura' },
		fragment = { module = shader, entryPoint = 'fs_aura' },
		vertexLayout = idLayout,
		colorTargets = glow,
		depthStencil = glowDepth,
		sampleCount = samples,
	})
	hero.shadowPipeline = GPUPipeline.new({
		vertex = { module = shader, entryPoint = 'vs_king_shadow' },
		vertexLayout = body,
		depthStencil = { format = DEPTH_FORMAT, compare = 'less', write = true },
		cullMode = 'none',
	})
	hero.kingBindings = nil
	hero.boundUbo = nil
end

-- A pipeline's bindings: only what it uses, as WebGPU's layouts list. Some
-- runtimes list every binding in the module for every pipeline instead;
-- then the full set (the shadow map, and the body's textures or their
-- placeholders) is bound.
local function bindings(hero: Hero, pipeline: GPUPipeline, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler, useShadow: boolean, textures: { GPUTextureView }?): GPUBindGroup
	local function make(withShadow: boolean, views: { GPUTextureView }?): GPUBindGroup
		local entries: { TextureEntry } = {}
		local samplers: { SamplerEntry } = {}
		if withShadow then
			table.insert(entries, { slot = 1, view = shadowView })
			table.insert(samplers, { slot = 2, sampler = shadowSampler })
		end
		if views then
			for i, v in views do
				table.insert(entries, { slot = 2 + i, view = v })
			end
			table.insert(samplers, { slot = 6, sampler = hero.textureSampler })
		end
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = entries,
			samplers = samplers,
		})
	end
	local ok, group = pcall(make, useShadow, textures)
	if ok then
		return group
	end
	return make(true, textures or hero.placeholderViews)
end

local function bind(hero: Hero, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler): boolean
	local kingP, outlineP, shadowP = hero.kingPipeline, hero.outlinePipeline, hero.shadowPipeline
	local moteP, auraP = hero.motePipeline, hero.auraPipeline
	if not (kingP and outlineP and shadowP and moteP and auraP) then
		return false
	end
	if hero.boundUbo ~= ubo or hero.kingBindings == nil then
		hero.boundUbo = ubo
		hero.outlineBindings = bindings(hero, outlineP, ubo, shadowView, shadowSampler, false)
		hero.shadowBindings = bindings(hero, shadowP, ubo, shadowView, shadowSampler, false)
		hero.moteBindings = bindings(hero, moteP, ubo, shadowView, shadowSampler, false)
		hero.auraBindings = bindings(hero, auraP, ubo, shadowView, shadowSampler, false)
		hero.kingBindings = nil
	end
	if hero.kingBindings == nil or (hero.texturesReady and not hero.boundReal) then
		hero.boundReal = hero.texturesReady
		local views = if hero.texturesReady then hero.textureViews else hero.placeholderViews
		hero.kingBindings = bindings(hero, kingP, ubo, shadowView, shadowSampler, true, views)
	end
	return true
end

local function body(hero: Hero, pass: GPURenderPass)
	pass:setVertexBuffer(0, hero.vertexBuffer)
	pass:setVertexBuffer(1, hero.morphBuffer)
	pass:setIndexBuffer(hero.indexBuffer, 'uint16')
	pass:drawIndexed(hero.indexCount)
end

-- Him, into a shadow pass (depth only, his ubo's lightViewProj).
function Hero.drawShadow(hero: Hero, pass: GPURenderPass, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler)
	if not bind(hero, ubo, shadowView, shadowSampler) then
		return
	end
	local shadowP, shadowB = hero.shadowPipeline, hero.shadowBindings
	if shadowP and shadowB then
		pass:setPipeline(shadowP)
		pass:setBindGroup(0, shadowB)
		body(hero, pass)
	end
end

-- Him, into the scene's pass: his ink outline, his body, the earrings'
-- halos and the bow's aura.
function Hero.draw(hero: Hero, pass: GPURenderPass, ubo: GPUBuffer, shadowView: GPUTextureView, shadowSampler: GPUSampler, outline: boolean)
	if not bind(hero, ubo, shadowView, shadowSampler) then
		return
	end
	local kingP, kingB = hero.kingPipeline, hero.kingBindings
	local outlineP, outlineB = hero.outlinePipeline, hero.outlineBindings
	local moteP, moteB = hero.motePipeline, hero.moteBindings
	local auraP, auraB = hero.auraPipeline, hero.auraBindings
	if outline and outlineP and outlineB then
		pass:setPipeline(outlineP)
		pass:setBindGroup(0, outlineB)
		body(hero, pass)
	end
	if kingP and kingB then
		pass:setPipeline(kingP)
		pass:setBindGroup(0, kingB)
		body(hero, pass)
	end
	if hero.haloOn and moteP and moteB then
		pass:setPipeline(moteP)
		pass:setBindGroup(0, moteB)
		pass:setVertexBuffer(0, hero.haloIds)
		pass:draw(6, 2)
	end
	if hero.auraOn and auraP and auraB then
		pass:setPipeline(auraP)
		pass:setBindGroup(0, auraB)
		pass:setVertexBuffer(0, hero.auraIds)
		pass:draw(6, AURA_PIECES)
	end
end

return Hero
