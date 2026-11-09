-- Jelly: the blob, drawn as jelly.
--
-- `rig` is the BlobRig artboard: bones, a skinned body, and a
-- face, all in material colours (see ../tools/make_scene.py). Each frame:
--
--   1. Springs wobble the rig: the body squashes and stretches (volume kept),
--      the crown sways, the sides bulge and jiggle. Now and then it hops,
--      crouching first and splatting a little when it lands. A tap squishes
--      it, and sometimes it hops for joy.
--   2. The rig, posed by its own state machine and the springs, is drawn
--      into a 2D canvas: the material map.
--   3. jelly.wgsl turns the map into jelly in three passes (two blurs for
--      the surface's shape, then the lighting) on GPU canvases.
--   4. The mood's effects are drawn around it, some behind, some in front.
--
-- `state` (bound to the Blob view model) picks the mood:
--   0 idle        breathing, blinking, glancing about, the odd hop
--   1 thinking    eyes up and wandering, a small "o", light orbiting it
--   2 retrieving  eyes scanning side to side, cards flying in to be gulped
--   3 executing   a focused squint, busy bouncing, sparks off the top,
--                 its light pulsing with the work
--   4 planning    eyes up and to the side, leaning, a thought bubble
--   5 done        happy ^ ^ eyes, a grin, hops, confetti
--
-- Place the node at the artboard's centre; width/height are the rig's size.

export type Jelly = {
	rig: Input<Artboard>,
	state: Input<number>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	bodyColor: Input<Color>,
	deepColor: Input<Color>,
	glowColor: Input<Color>,
	inkColor: Input<Color>,
	blushColor: Input<Color>,
	backdropColor: Input<Color>,
	gloss: Input<number>,
	translucency: Input<number>,
	glow: Input<number>,
	rim: Input<number>,
	outline: Input<number>,
	paint: Input<number>,
	wobble: Input<number>,
	shadow: Input<number>,

	context: Context?,
	failed: boolean,
	time: number,
	inst: Artboard?,
	jellyNode: NodeData?,
	crownNode: NodeData?,
	blobNode: NodeData?,
	sideLNode: NodeData?,
	sideRNode: NodeData?,
	-- Springs: position and velocity.
	squash: number,
	squashV: number,
	sway: number,
	swayV: number,
	bulgeL: number,
	bulgeLV: number,
	bulgeR: number,
	bulgeRV: number,
	-- The hop: height above the floor (negative is up), its velocity, the
	-- crouch before it, and the wait until the next one.
	jumpY: number,
	jumpV: number,
	airborne: boolean,
	crouch: number,
	nextHop: number,
	hopsQueued: number,

	-- The mood, and the face it wears.
	mood: number,
	moodTime: number,
	lookNode: NodeData?,
	openNode: NodeData?,
	happyNode: NodeData?,
	smileNode: NodeData?,
	oohNode: NodeData?,
	flatNode: NodeData?,
	grinNode: NodeData?,
	blushLNode: NodeData?,
	blushRNode: NodeData?,
	lookX: number,
	lookY: number,
	glanceX: number,
	glanceY: number,
	nextGlance: number,
	wOpen: number,
	wHappy: number,
	wSmile: number,
	wOoh: number,
	wFlat: number,
	wGrin: number,
	squint: number,
	blush: number,
	-- How much of each mood's effect is showing (they fade in and out).
	fxThink: number,
	fxPlan: number,
	glowBoost: number,
	flash: number,
	spawn: number,
	beat: number,
	particles: { Particle },
	fxPaint: Paint,
	haloPaint: Paint,

	shader: Shader?,
	matCanvas: Canvas?,
	narrow: GPUCanvas?,
	mid: GPUCanvas?,
	wide: GPUCanvas?,
	out: GPUCanvas?,
	narrowPipeline: GPUPipeline?,
	midPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	finalPipeline: GPUPipeline?,
	narrowBindings: GPUBindGroup?,
	midBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	finalBindings: GPUBindGroup?,
	ubo: GPUBuffer?,
	sampler: GPUSampler?,
	params: buffer,
	targetW: number,
	targetH: number,
	drawSampler: ImageSampler,
}

-- A flying bit of effect: 1 a card (retrieving), 2 a spark (executing),
-- 3 confetti, 4 a twinkle (done).
export type Particle = {
	kind: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	sx: number,
	sy: number,
	cx: number,
	cy: number,
	age: number,
	life: number,
	size: number,
	rot: number,
	spin: number,
	color: Color,
	-- Confetti: its shape (1 puffy star, 2 bean, 3 drop), and a squish
	-- spring (0 is round; negative squashed flat, positive stretched).
	shape: number,
	sq: number,
	sqv: number,
	bounces: number,
}

-- Where the rig sits (make_scene.py).
local BASE_X = 256
local BASE_Y = 452
local HALF_W = 188 -- body half width, with its settled spread
local GRAVITY = 1500
local HOP_SPEED = 330
local PARAMS_SIZE = 11 * 16
local CENTER_UP = 92 -- base to the body's centre

local function clamp(x: number, a: number, b: number): number
	return math.min(math.max(x, a), b)
end

-- A damped spring toward `target`. Returns position, velocity.
local function spring(x: number, v: number, target: number, k: number, c: number, dt: number): (number, number)
	local a = -k * (x - target) - c * v
	v += a * dt
	x += v * dt
	return x, v
end

local function rgb(c: Color): (number, number, number)
	return (Color.red(c) :: number) / 255, (Color.green(c) :: number) / 255, (Color.blue(c) :: number) / 255
end

local function writeVec(b: buffer, slot: number, x: number, y: number, z: number, w: number)
	local o = slot * 16
	buffer.writef32(b, o, x)
	buffer.writef32(b, o + 4, y)
	buffer.writef32(b, o + 8, z)
	buffer.writef32(b, o + 12, w)
end

local function writeColor(b: buffer, slot: number, c: Color, w: number)
	local r, g, bl = rgb(c)
	writeVec(b, slot, r, g, bl, w)
end

---------------------------------------------------------------------------
-- Setup

function init(self: Jelly, context: Context): boolean
	self.context = context
	local inst = self.rig:instance()
	inst.frameOrigin = false
	self.inst = inst
	self.jellyNode = inst:node('Jelly')
	self.crownNode = inst:node('Crown')
	self.blobNode = inst:node('Blob')
	self.sideLNode = inst:node('SideL')
	self.sideRNode = inst:node('SideR')
	self.lookNode = inst:node('Look')
	self.openNode = inst:node('Open')
	self.happyNode = inst:node('Happy')
	self.smileNode = inst:node('Smile')
	self.oohNode = inst:node('Ooh')
	self.flatNode = inst:node('Flat')
	self.grinNode = inst:node('Grin')
	self.blushLNode = inst:node('BlushL')
	self.blushRNode = inst:node('BlushR')
	if self.jellyNode == nil or self.crownNode == nil then
		print('Jelly: the rig needs nodes "Jelly" and "Crown"')
	end
	self.shader = context:shader('jelly')
	if self.shader == nil then
		print('Jelly: shader "jelly" not found')
		self.failed = true
	end
	return true
end

local function ensureTargets(self: Jelly): boolean
	local context = self.context
	local shader = self.shader
	if context == nil or shader == nil then
		return false
	end
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(8, math.floor(self.width * res))
	local h = math.max(8, math.floor(self.height * res))
	if self.out ~= nil and w == self.targetW and h == self.targetH then
		return true
	end
	self.targetW, self.targetH = w, h
	self.matCanvas = context:canvas({ width = w, height = h })
	self.narrow = context:gpuCanvas({ width = math.max(4, w // 2), height = math.max(4, h // 2) })
	self.mid = context:gpuCanvas({ width = math.max(4, w // 2), height = math.max(4, h // 2) })
	self.wide = context:gpuCanvas({ width = math.max(2, w // 4), height = math.max(2, h // 4) })
	self.out = context:gpuCanvas({ width = w, height = h })
	local out = self.out
	assert(out)
	if self.finalPipeline == nil then
		local function pipe(entry: string): GPUPipeline
			return GPUPipeline.new({
				vertex = { module = shader, entryPoint = 'vs_main' },
				fragment = { module = shader, entryPoint = entry },
				vertexLayout = {},
				colorTargets = { { format = out.format } },
			})
		end
		self.narrowPipeline = pipe('fs_narrow')
		self.midPipeline = pipe('fs_mid')
		self.widePipeline = pipe('fs_wide')
		self.finalPipeline = pipe('fs_final')
		self.ubo = GPUBuffer.new({ size = PARAMS_SIZE, usage = 'uniform' })
		self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	end
	self.narrowBindings = nil
	self.midBindings = nil
	self.wideBindings = nil
	self.finalBindings = nil
	return true
end

---------------------------------------------------------------------------
-- Motion

---------------------------------------------------------------------------
-- Moods

local function approach(x: number, target: number, rate: number, dt: number): number
	return x + (target - x) * (1 - math.exp(-rate * dt))
end

local function newParticle(kind: number, x: number, y: number, color: Color): Particle
	return {
		kind = kind,
		x = x,
		y = y,
		vx = 0,
		vy = 0,
		sx = x,
		sy = y,
		cx = x,
		cy = y,
		age = 0,
		life = 1,
		size = 8,
		rot = 0,
		spin = 0,
		color = color,
		shape = 1,
		sq = 0,
		sqv = 0,
		bounces = 0,
	}
end

local function glowRGB(self: Jelly): (number, number, number)
	local r, g, b = rgb(self.glowColor)
	return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

-- The body's centre and top, in this node's space.
local function bodyCentre(self: Jelly): (number, number)
	return BASE_X - self.width / 2, BASE_Y - CENTER_UP - self.height / 2 + self.jumpY
end

-- Bright, flat confetti colours.
local CONFETTI = {
	Color.rgb(255, 64, 160),
	Color.rgb(255, 210, 0),
	Color.rgb(0, 230, 160),
	Color.rgb(40, 200, 255),
	Color.rgb(160, 90, 255),
	Color.rgb(255, 120, 30),
}

local function burst(self: Jelly)
	local cx, cy = bodyCentre(self)
	for i = 1, 30 do
		-- Thrown out to either side, so they land beside it, not on its face.
		local side = if i % 2 == 0 then 1 else -1
		local a = -math.pi / 2 + side * (0.22 + math.random() * 0.45)
		local speed = 420 + math.random() * 220
		local p = newParticle(3, cx + (math.random() - 0.5) * 100, cy - 120, CONFETTI[1 + (i % #CONFETTI)])
		p.vx = math.cos(a) * speed
		p.vy = math.sin(a) * speed
		p.life = 2.6 + math.random() * 0.8
		p.size = 6 + math.random() * 4
		p.rot = math.random() * 6.28
		p.spin = (math.random() - 0.5) * 6
		p.shape = 1 + (i % 3)
		-- Launched stretched, like it was squeezed out.
		p.sq = 0.45
		table.insert(self.particles, p)
	end
end

local function enterMood(self: Jelly, mood: number)
	local was = self.mood
	self.mood = mood
	self.moodTime = 0
	self.spawn = 0
	if mood == 5 then
		burst(self)
		self.hopsQueued = 2
		self.nextHop = 0.15
		self.glowBoost = 1.9
	elseif was == 5 then
		self.hopsQueued = 0
	end
	if mood ~= 0 then
		self.nextHop = math.max(self.nextHop, 0.15)
	end
	-- A little start, as it switches.
	self.squashV -= 1.1
end

-- What the face aims for in each mood.
local function faceTargets(self: Jelly, t: number, dt: number)
	local mood = self.mood
	local open, happy, smile, ooh, flat, grin, squint, blush = 1, 0, 1, 0, 0, 0, 1, 1
	local lx, ly = 0, 0
	if mood == 0 then
		-- Glances about, now and then.
		self.nextGlance -= dt
		if self.nextGlance <= 0 then
			if math.random() < 0.45 then
				self.glanceX, self.glanceY = 0, 0
			else
				self.glanceX = (math.random() - 0.5) * 16
				self.glanceY = (math.random() - 0.5) * 7
			end
			self.nextGlance = 1.2 + math.random() * 2.4
		end
		lx, ly = self.glanceX, self.glanceY
	elseif mood == 1 then
		smile, ooh = 0, 1
		lx, ly = math.sin(t * 0.7) * 8, -9 + math.sin(t * 1.3) * 1.5
	elseif mood == 2 then
		smile, ooh = 0, 0.85
		-- Reading: across, and back.
		local ph = (t * 0.85) % 1
		lx = if ph < 0.5 then -11 + ph * 10 else 11 - (ph - 0.5) * 10
		ly = 5
	elseif mood == 3 then
		smile, flat = 0, 1
		squint = 0.6
		lx, ly = math.sin(t * 2.2) * 2, 4
	elseif mood == 4 then
		smile, flat = 0, 1
		lx, ly = 10, -10
	elseif mood == 5 then
		open, happy, smile, grin = 0, 1, 0, 1
		blush = 1.4
		ly = -2
	end
	local r = 14
	self.wOpen = approach(self.wOpen, open, r, dt)
	self.wHappy = approach(self.wHappy, happy, r, dt)
	self.wSmile = approach(self.wSmile, smile, r, dt)
	self.wOoh = approach(self.wOoh, ooh, r, dt)
	self.wFlat = approach(self.wFlat, flat, r, dt)
	self.wGrin = approach(self.wGrin, grin, r, dt)
	self.squint = approach(self.squint, squint, 10, dt)
	self.blush = approach(self.blush, blush, 6, dt)
	self.lookX = approach(self.lookX, lx, 16, dt)
	self.lookY = approach(self.lookY, ly, 16, dt)
end

local function setScale(node: NodeData?, sx: number, sy: number)
	if node then
		node.scaleX = sx
		node.scaleY = sy
	end
end

-- An eased pop: shapes grow in with a touch of overshoot.
local function pop(w: number): number
	local x = clamp(w, 0, 1)
	return x * x * (3 - 2 * x) * (1 + 0.18 * math.sin(x * math.pi))
end

local function applyFace(self: Jelly)
	local look = self.lookNode
	if look then
		look.x = self.lookX
		look.y = self.lookY
	end
	setScale(self.openNode, pop(self.wOpen), pop(self.wOpen) * self.squint)
	setScale(self.happyNode, pop(self.wHappy), pop(self.wHappy))
	setScale(self.smileNode, pop(self.wSmile), pop(self.wSmile))
	setScale(self.oohNode, pop(self.wOoh), pop(self.wOoh))
	setScale(self.flatNode, pop(self.wFlat), pop(self.wFlat))
	setScale(self.grinNode, pop(self.wGrin), pop(self.wGrin))
	setScale(self.blushLNode, self.blush, self.blush)
	setScale(self.blushRNode, self.blush, self.blush)
end

local function updateParticles(self: Jelly, dt: number)
	local mood, t = self.mood, self.time
	local cx, cy = bodyCentre(self)
	local gr, gg, gb = glowRGB(self)
	-- Retrieving: cards fly in from either side, and are gulped.
	if mood == 2 then
		self.spawn -= dt
		if self.spawn <= 0 then
			self.spawn = 0.38
			local side = if math.random() < 0.5 then -1 else 1
			local p = newParticle(1, side * 300, cy - 40 + (math.random() - 0.5) * 160, Color.rgb(255, 255, 255))
			p.sx, p.sy = p.x, p.y
			p.cx = side * (120 + math.random() * 60)
			p.cy = cy - 200 - math.random() * 60
			p.life = 0.95 + math.random() * 0.3
			p.size = 1
			p.rot = side * 0.4
			p.spin = -side * 1.2
			table.insert(self.particles, p)
		end
	end
	-- Executing: sparks flick off the top on the beat.
	if mood == 3 then
		local b = math.sin(t * 10)
		if b > 0.9 and self.beat <= 0.9 then
			for _ = 1, 2 do
				local p = newParticle(2, cx + (math.random() - 0.5) * 120, cy - 135,
					if math.random() < 0.5 then Color.rgb(255, 255, 255) else Color.rgb(gr, gg, gb))
				p.vx = (math.random() - 0.5) * 260
				p.vy = -220 - math.random() * 140
				p.life = 0.7 + math.random() * 0.3
				p.size = 7 + math.random() * 5
				p.spin = (math.random() - 0.5) * 8
				table.insert(self.particles, p)
			end
			self.flash = math.min(self.flash + 0.25, 0.6)
		end
		self.beat = b
	end
	-- Done: twinkles about it for a while.
	if mood == 5 and self.moodTime < 3.5 then
		self.spawn -= dt
		if self.spawn <= 0 then
			self.spawn = 0.2
			local a = math.random() * math.pi * 2
			local r = 170 + math.random() * 70
			local p = newParticle(4, cx + math.cos(a) * r, cy - 30 + math.sin(a) * r * 0.6, CONFETTI[1 + math.random(0, #CONFETTI - 1)])
			p.life = 0.6 + math.random() * 0.4
			p.size = 6 + math.random() * 6
			table.insert(self.particles, p)
		end
	end

	local keep: { Particle } = {}
	for _, p in self.particles do
		p.age += dt
		if p.kind == 1 then
			-- Along a curve into the top of the body, shrinking as it goes.
			local k = clamp(p.age / p.life, 0, 1)
			local e = k * k * (3 - 2 * k)
			local tx, ty = cx, cy - 70
			local u = 1 - e
			p.x = u * u * p.sx + 2 * u * e * p.cx + e * e * tx
			p.y = u * u * p.sy + 2 * u * e * p.cy + e * e * ty
			p.rot += p.spin * dt
			if k >= 1 then
				self.flash = math.min(self.flash + 0.35, 0.8)
				self.squashV -= 0.7
			end
		elseif p.kind == 2 then
			p.vy += 700 * dt
			local drag = math.exp(-0.6 * dt)
			p.vx *= drag
			p.vy *= drag
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.rot += p.spin * dt
		elseif p.kind == 3 then
			-- Heavy jelly: falls, bounces off the floor with a splat, and
			-- wobbles back into shape.
			p.vy += 1100 * dt
			local drag = math.exp(-0.5 * dt)
			p.vx *= drag
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.rot += p.spin * dt
			-- The stage's walls: bounce back in.
			local wall = self.width / 2 - p.size
			if math.abs(p.x) > wall and p.x * p.vx > 0 then
				p.x = math.sign(p.x) * wall
				p.vx = -p.vx * 0.5
				p.sqv -= math.abs(p.vx) * 0.006
			end
			-- The floor just in front of it.
			local floor = BASE_Y - self.height / 2 + 16 - p.size * 0.6
			if p.y > floor and p.vy > 0 then
				p.y = floor
				local hit = p.vy
				p.vy = -hit * (if p.bounces == 0 then 0.42 else 0.25)
				p.vx *= 0.7
				p.spin *= 0.5
				p.sqv -= hit * 0.012
				p.bounces += 1
				if hit < 140 then
					p.vy = 0
				end
			end
			p.sq, p.sqv = spring(p.sq, p.sqv, 0, 260, 7, dt)
		end
		if p.age < p.life then
			table.insert(keep, p)
		end
	end
	self.particles = keep
end

local function land(self: Jelly)
	local impact = math.abs(self.jumpV)
	self.jumpY = 0
	self.jumpV = 0
	self.airborne = false
	-- Splat: squash, both sides spill out, and a little wobble sideways.
	self.squashV -= impact * 0.006
	self.bulgeLV += impact * 0.004
	self.bulgeRV += impact * 0.004
	self.swayV += (math.random() - 0.5) * 0.9
end

function advance(self: Jelly, seconds: number): boolean
	local dt = clamp(seconds, 0, 1 / 30)
	self.time += seconds
	local t = self.time
	local wob = math.max(self.wobble, 0)

	local mood = math.floor(clamp(self.state, 0, 5) + 0.5)
	if mood ~= self.mood then
		enterMood(self, mood)
	end
	self.moodTime += dt
	local mt = self.moodTime

	-- The hop: a crouch, a spring up (stretching), a fall, a splat.
	local stretch = 0
	if self.airborne then
		self.jumpV += GRAVITY * dt
		self.jumpY += self.jumpV * dt
		stretch = clamp(-self.jumpV / HOP_SPEED, -0.4, 1) * 0.1
		if self.jumpY >= 0 and self.jumpV > 0 then
			land(self)
		end
	elseif self.crouch > 0 then
		self.crouch -= dt
		stretch = -0.13
		if self.crouch <= 0 then
			self.airborne = true
			self.jumpV = -HOP_SPEED * (if self.mood == 5 then 1.15 else 0.85 + math.random() * 0.3)
			self.squashV += 3.4
		end
	elseif wob > 0 then
		self.nextHop -= dt
		if self.nextHop <= 0 then
			if self.hopsQueued > 0 then
				self.hopsQueued -= 1
				self.crouch = 0.14
				self.nextHop = 0.1
			elseif self.mood == 0 then
				self.crouch = 0.2
				self.nextHop = 3.5 + math.random() * 3.5
			else
				self.nextHop = 0.5
			end
		end
	end

	-- Breathing, a slow sway, and the sides' idle jiggle, as targets the
	-- springs chase. Soft springs, lightly damped: squishy, and it wiggles.
	local breathAmp, breathRate, swayAmt, lean, busy = 0.028, 1.9, 0.05, 0, 0
	local glow = 1
	if mood == 1 then
		breathAmp, breathRate, swayAmt = 0.04, 1.3, 0.03
		glow = 1.25 + math.sin(t * 2.2) * 0.2
	elseif mood == 2 then
		swayAmt, lean = 0.025, self.lookX * 0.006
		busy = math.sin(t * 6) * 0.012
		glow = 1.15
	elseif mood == 3 then
		swayAmt = 0.02
		busy = math.sin(t * 10) * 0.045
		glow = 1.2 + math.max(0, math.sin(t * 10)) * 0.4
	elseif mood == 4 then
		breathRate, swayAmt = 1.3, 0.02
		lean = 0.09 + math.sin(t * 0.9) * 0.03
		glow = 1.15
	elseif mood == 5 then
		glow = 1.15 + math.max(0, 1 - mt / 2) * 0.6
		if mt > 1.3 and mt < 2.8 then
			lean = math.sin((mt - 1.3) * 10) * 0.1 * (1 - (mt - 1.3) / 1.5)
		end
	end
	self.glowBoost = approach(self.glowBoost, glow, 5, dt)
	self.flash *= math.exp(-6 * dt)
	-- On the first frames the face and effects are already where the mood
	-- wants them, rather than easing in from idle.
	local fdt = if self.time < 0.25 then 1 else dt
	self.fxThink = approach(self.fxThink, if mood == 1 then 1 else 0, 5, fdt)
	self.fxPlan = approach(self.fxPlan, if mood == 4 then 1 else 0, 5, fdt)
	faceTargets(self, t, fdt)
	updateParticles(self, dt)

	local breath = math.sin(t * breathRate) * breathAmp * wob + busy * wob
	local drift = (math.sin(t * 0.83) * 0.7 + math.sin(t * 1.31 + 1.2) * 0.3) * swayAmt * wob + lean
	self.squash, self.squashV = spring(self.squash, self.squashV, breath + stretch * wob, 105, 3.2, dt)
	self.sway, self.swayV = spring(self.sway, self.swayV, drift, 70, 2.6, dt)
	-- Squishy, but kept on stage: at most about 1.25x as wide when it splats.
	local s = clamp(self.squash, -0.2, 0.26)
	local tilt = self.sway * 0.45
	local jigL = math.sin(t * 2.6) * 0.012 * wob
	local jigR = math.sin(t * 2.3 + 2.1) * 0.012 * wob
	self.bulgeL, self.bulgeLV = spring(self.bulgeL, self.bulgeLV, -s * 0.35 + tilt + jigL, 140, 2.9, dt)
	self.bulgeR, self.bulgeRV = spring(self.bulgeR, self.bulgeRV, -s * 0.35 - tilt + jigR, 140, 2.9, dt)

	local blob = self.blobNode
	if blob then
		blob.y = BASE_Y + self.jumpY
	end
	local jelly = self.jellyNode
	if jelly then
		jelly.scaleY = 1 + s
		jelly.scaleX = 1 - s * 0.85
	end
	local crown = self.crownNode
	if crown then
		crown.rotation = clamp(self.sway, -0.5, 0.5)
	end
	local sl, sr = self.sideLNode, self.sideRNode
	if sl then
		sl.scaleX = 1 + clamp(self.bulgeL, -0.2, 0.1)
	end
	if sr then
		sr.scaleX = 1 + clamp(self.bulgeR, -0.2, 0.1)
	end

	applyFace(self)

	local inst = self.inst
	if inst then
		inst:advance(seconds)
	end
	return true
end

-- A tap on the blob squishes it, and sways it away from the finger.
function pointerDown(self: Jelly, event: PointerEvent)
	local p = event.position
	local x = p.x + self.width / 2 - BASE_X
	local y = p.y + self.height / 2 - BASE_Y
	if math.abs(x) > HALF_W or y > 10 or y < -290 then
		return
	end
	event:hit()
	-- Squish where it was poked: the side away from the finger spills out.
	local side = clamp(x / HALF_W, -1, 1)
	self.squashV -= 3.2
	self.swayV -= side * 2.2
	self.bulgeLV += 1.2 + side * 1.4
	self.bulgeRV += 1.2 - side * 1.4
	-- Sometimes it hops for joy.
	if not self.airborne and self.crouch <= 0 and math.random() < 0.4 then
		self.nextHop = 0.35
	end
end

---------------------------------------------------------------------------
-- Drawing

local function writeParams(self: Jelly)
	local b = self.params
	local w, h = self.targetW, self.targetH
	writeVec(b, 0, 1 / w, 1 / h, w / h, self.time)
	writeVec(b, 1, -0.5, -0.82, 0.78, math.max(self.gloss, 0))
	writeColor(b, 2, self.bodyColor, clamp(self.translucency, 0, 2))
	writeColor(b, 3, self.deepColor, clamp(self.outline, 0, 1))
	writeColor(b, 4, self.glowColor, math.max(self.glow, 0) * (self.glowBoost + self.flash))
	writeVec(b, 5, 0, 0, 0, clamp(self.paint, 0, 2))
	writeColor(b, 6, self.inkColor, math.max(self.rim, 0))
	-- The shadow fades and shrinks while it's in the air.
	local lift = clamp(-self.jumpY / 120, 0, 1)
	writeColor(b, 7, self.blushColor, math.max(self.shadow, 0) * (1 - lift * 0.55))
	writeColor(b, 8, self.backdropColor, 1)
	-- The floor shadow follows the squash: wider as it squashes.
	local s = clamp(self.squash, -0.35, 0.35)
	writeVec(b, 9, BASE_X / self.width, (BASE_Y + 3) / self.height, HALF_W / self.width * (1 - s * 0.85) * (1 - lift * 0.3), 1 + s)
	-- Blur radii, as a fraction of the height.
	writeVec(b, 10, 8 / self.height, 26 / self.height, 64 / self.height, 3 / self.height)
end

local function fullPass(target: GPUCanvas, pipeline: GPUPipeline, bindings: GPUBindGroup)
	local pass = target:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipeline)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()
end

local function render(self: Jelly): Image?
	if not ensureTargets(self) then
		return nil
	end
	local inst, mat = self.inst, self.matCanvas
	local narrow, mid, wide, out = self.narrow, self.mid, self.wide, self.out
	local ubo, sampler = self.ubo, self.sampler
	local np, mp, wp, fp = self.narrowPipeline, self.midPipeline, self.widePipeline, self.finalPipeline
	if not (inst and mat and narrow and mid and wide and out and ubo and sampler and np and mp and wp and fp) then
		return nil
	end
	if mat.width <= 0 or mat.image == nil then
		return nil
	end

	-- 1. The material map.
	local r = mat:beginFrame()
	r:save()
	r:transform(Mat2D.withScale(self.targetW / self.width, self.targetH / self.height))
	inst:draw(r)
	r:restore()
	mat:endFrame()

	writeParams(self)
	ubo:write(self.params)

	if self.finalBindings == nil then
		local matView = mat.image:view()
		self.narrowBindings = GPUBindGroup.new({
			layout = np:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 1, view = matView } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.midBindings = GPUBindGroup.new({
			layout = mp:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 3, view = narrow:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.wideBindings = GPUBindGroup.new({
			layout = wp:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 5, view = mid:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.finalBindings = GPUBindGroup.new({
			layout = fp:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = {
				{ slot = 1, view = matView },
				{ slot = 3, view = narrow:colorView() },
				{ slot = 4, view = wide:colorView() },
				{ slot = 5, view = mid:colorView() },
			},
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	local nb, mb, wb, fb = self.narrowBindings, self.midBindings, self.wideBindings, self.finalBindings
	assert(nb and mb and wb and fb)

	-- 2. The surface's shape, then 3. the jelly.
	fullPass(narrow, np, nb)
	fullPass(mid, mp, mb)
	fullPass(wide, wp, wb)
	fullPass(out, fp, fb)
	return out.image
end

---------------------------------------------------------------------------
-- Effects, in this node's space

local K = 0.5523

local function circle(path: Path, x: number, y: number, r: number)
	path:moveTo(Vector.xy(x + r, y))
	path:cubicTo(Vector.xy(x + r, y + r * K), Vector.xy(x + r * K, y + r), Vector.xy(x, y + r))
	path:cubicTo(Vector.xy(x - r * K, y + r), Vector.xy(x - r, y + r * K), Vector.xy(x - r, y))
	path:cubicTo(Vector.xy(x - r, y - r * K), Vector.xy(x - r * K, y - r), Vector.xy(x, y - r))
	path:cubicTo(Vector.xy(x + r * K, y - r), Vector.xy(x + r, y - r * K), Vector.xy(x + r, y))
	path:close()
end

-- A four-pointed sparkle.
local function star(path: Path, x: number, y: number, r: number, rot: number)
	for i = 0, 7 do
		local a = rot + i * math.pi / 4
		local rr = if i % 2 == 0 then r else r * 0.34
		local v = Vector.xy(x + math.cos(a) * rr, y + math.sin(a) * rr)
		if i == 0 then
			path:moveTo(v)
		else
			path:lineTo(v)
		end
	end
	path:close()
end

local function quad(path: Path, x: number, y: number, w: number, h: number, rot: number)
	local c, sn = math.cos(rot), math.sin(rot)
	local hw, hh = w / 2, h / 2
	local pts = { { -hw, -hh }, { hw, -hh }, { hw, hh }, { -hw, hh } }
	for i, q in pts do
		local v = Vector.xy(x + q[1] * c - q[2] * sn, y + q[1] * sn + q[2] * c)
		if i == 1 then
			path:moveTo(v)
		else
			path:lineTo(v)
		end
	end
	path:close()
end

local function withAlpha(c: Color, a: number): Color
	return Color.alpha(c, math.floor(clamp(a, 0, 1) * 255)) :: Color
end

local function fill(self: Jelly, renderer: Renderer, path: Path, c: Color, halo: boolean?)
	local paint = if halo then self.haloPaint else self.fxPaint
	paint.color = c
	renderer:drawPath(path, paint)
end

-- Thinking: three motes of light circling above its head, passing behind
-- and in front.
local function drawOrbs(self: Jelly, renderer: Renderer, front: boolean)
	local w = self.fxThink
	if w < 0.01 then
		return
	end
	local cx, cy = bodyCentre(self)
	local gr, gg, gb = glowRGB(self)
	for i = 0, 2 do
		local a = self.time * 1.5 + i * 2.094
		local z = math.sin(a)
		if (z >= 0) == front then
			-- A halo above its head.
			local x = cx + math.cos(a) * 120
			local y = cy - 168 + z * 20 + math.sin(self.time * 2.4) * 3
			local r = (7 + z * 2.5) * pop(w)
			local alpha = w * (0.7 + 0.3 * z)
			local halo = Path.new()
			circle(halo, x, y, r * 2)
			fill(self, renderer, halo, Color.rgba(gr, gg, gb, math.floor(alpha * 170)), true)
			local core = Path.new()
			circle(core, x, y, r)
			fill(self, renderer, core, Color.rgba(255, 255, 255, math.floor(alpha * 255)))
		end
	end
end

-- Planning: a thought bubble rising from its head, with a plan being
-- ticked off inside it.
local function drawThought(self: Jelly, renderer: Renderer)
	local w = self.fxPlan
	if w < 0.01 then
		return
	end
	local cx, cy = bodyCentre(self)
	local gr, gg, gb = glowRGB(self)
	local ir, ig, ib = rgb(self.inkColor)
	local ink = Color.rgb(math.floor(ir * 255), math.floor(ig * 255), math.floor(ib * 255))
	local t = self.time
	local bob = math.sin(t * 2) * 4
	local trail = { { 118, -128, 7 }, { 146, -160, 11 } }
	for i, d in trail do
		local k = pop(clamp(w * 2.2 - (i - 1) * 0.5, 0, 1))
		if k > 0.01 then
			local pth = Path.new()
			circle(pth, cx + d[1], cy + d[2] + bob * 0.5, d[3] * k)
			fill(self, renderer, pth, Color.rgba(gr, gg, gb, 150), true)
			local core = Path.new()
			circle(core, cx + d[1], cy + d[2] + bob * 0.5, d[3] * k)
			fill(self, renderer, core, Color.rgba(255, 255, 255, 240))
		end
	end
	local k = pop(clamp(w * 2.2 - 1.1, 0, 1))
	if k < 0.01 then
		return
	end
	local bx, by = cx + 182, cy - 222 + bob
	-- The cloud: overlapping puffs.
	local puffs = { { 0, 0, 40 }, { -34, 8, 27 }, { 34, 8, 27 }, { -18, -22, 26 }, { 20, -20, 28 } }
	local glowPath = Path.new()
	local cloud = Path.new()
	for _, q in puffs do
		circle(glowPath, bx + q[1] * k, by + q[2] * k, q[3] * k + 4)
		circle(cloud, bx + q[1] * k, by + q[2] * k, q[3] * k)
	end
	fill(self, renderer, glowPath, Color.rgba(gr, gg, gb, 140), true)
	fill(self, renderer, cloud, Color.rgba(255, 255, 255, 245))
	-- The plan: three steps, ticked off one after another, then again.
	local step = (t * 1.1) % 4.5
	for row = 0, 2 do
		local y = by - 16 + row * 15
		local x0 = bx - 30
		local done = step > row + 0.8
		local dot = Path.new()
		circle(dot, x0, y, 4.5 * k)
		fill(self, renderer, dot, if done then Color.rgba(gr, gg, gb, 255) else Color.rgba(200, 212, 235, 255))
		local len = (if row == 1 then 34 else 44) * clamp(step - row, 0, 1)
		if len > 1 then
			local bar = Path.new()
			quad(bar, x0 + 11 + len / 2, y, len, 5, 0)
			fill(self, renderer, bar, withAlpha(ink, 0.55))
		end
	end
end

-- The outline of a candy, centred on 0,0 at radius r.
local function candyPath(path: Path, shape: number, r: number, dx: number, dy: number)
	if shape == 1 then
		-- A puffy five-pointed star: rounded points, plump middle.
		local n = 10
		for i = 0, n - 1 do
			local a0 = -math.pi / 2 + i * math.pi * 2 / n
			local rr = if i % 2 == 0 then r * 1.1 else r * 0.5
			local a1 = a0 + math.pi / n
			local rr1 = if i % 2 == 0 then r * 0.5 else r * 1.1
			local p0 = Vector.xy(dx + math.cos(a0) * rr, dy + math.sin(a0) * rr)
			local p1 = Vector.xy(dx + math.cos(a1) * rr1, dy + math.sin(a1) * rr1)
			if i == 0 then
				path:moveTo(p0)
			end
			local mid = (a0 + a1) / 2
			local bulge = r * 0.78
			path:quadTo(Vector.xy(dx + math.cos(mid) * bulge, dy + math.sin(mid) * bulge), p1)
		end
		path:close()
	elseif shape == 2 then
		-- A jelly bean.
		local w, h = r * 1.25, r * 0.78
		path:moveTo(Vector.xy(dx - w, dy))
		path:cubicTo(Vector.xy(dx - w, dy - h * 1.3), Vector.xy(dx - w * 0.2, dy - h * 0.9), Vector.xy(dx, dy - h * 0.55))
		path:cubicTo(Vector.xy(dx + w * 0.2, dy - h * 0.9), Vector.xy(dx + w, dy - h * 1.3), Vector.xy(dx + w, dy))
		path:cubicTo(Vector.xy(dx + w, dy + h * 1.3), Vector.xy(dx - w, dy + h * 1.3), Vector.xy(dx - w, dy))
		path:close()
	else
		-- A round gumdrop.
		circle(path, dx, dy, r * 0.9)
	end
end

-- A piece of confetti: flat, one bright colour, squashed and stretched
-- along its flight and splatted when it lands.
local function drawCandy(self: Jelly, renderer: Renderer, p: Particle, alpha: number)
	if alpha <= 0.01 then
		return
	end
	local r = p.size
	-- Stretch along the velocity while flying; the spring adds the splat.
	local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
	local dir = if speed > 1 then math.atan2(p.vy, p.vx) else 0
	local st = clamp(1 + speed * 0.0007 + p.sq, 0.45, 1.9)
	-- A splat squashes vertically, whatever its flight.
	local axis = if p.sq < 0 then math.pi / 2 else dir
	renderer:save()
	renderer:transform(
		Mat2D.withTranslation(p.x, p.y)
			* Mat2D.withRotation(axis)
			* Mat2D.withScale(st, 1 / st)
			* Mat2D.withRotation(p.rot - axis)
	)
	-- Mock depth with feathering, clipped to the shape: a deeper rim, the
	-- bright colour feathered over most of it from the top-left, and a soft
	-- sheen. Flat colours, soft light; no hard shading.
	local cr, cg, cb = (Color.red(p.color) :: number), (Color.green(p.color) :: number), (Color.blue(p.color) :: number)
	local a = math.floor(alpha * 255)
	local body = Path.new()
	candyPath(body, p.shape, r, 0, 0)
	fill(self, renderer, body, Color.rgba(math.floor(cr * 0.78), math.floor(cg * 0.74), math.floor(cb * 0.82), a))
	renderer:save()
	renderer:clipPath(body)
	local soft = self.haloPaint
	local lit = Path.new()
	candyPath(lit, p.shape, r * 0.9, -r * 0.14, -r * 0.18)
	soft.feather = r * 0.42
	soft.color = Color.rgba(cr, cg, cb, a)
	renderer:drawPath(lit, soft)
	local sheen = Path.new()
	circle(sheen, -r * 0.3, -r * 0.34, r * 0.3)
	soft.feather = r * 0.28
	soft.color = Color.rgba(255, 255, 255, math.floor(alpha * 150))
	renderer:drawPath(sheen, soft)
	soft.feather = 9
	renderer:restore()
	renderer:restore()
end

local function drawParticles(self: Jelly, renderer: Renderer)
	local gr, gg, gb = glowRGB(self)
	for _, p in self.particles do
		local k = clamp(p.age / p.life, 0, 1)
		local path = Path.new()
		if p.kind == 1 then
			-- A little card: fades in, shrinks as it's swallowed.
			local sc = 1 - 0.7 * k * k
			local a = clamp(k / 0.15, 0, 1) * (1 - clamp((k - 0.85) / 0.15, 0, 1))
			local halo = Path.new()
			quad(halo, p.x, p.y, 26 * sc, 32 * sc, p.rot)
			fill(self, renderer, halo, Color.rgba(gr, gg, gb, math.floor(a * 160)), true)
			quad(path, p.x, p.y, 22 * sc, 28 * sc, p.rot)
			fill(self, renderer, path, Color.rgba(255, 255, 255, math.floor(a * 255)))
			local c, sn = math.cos(p.rot), math.sin(p.rot)
			for row = 0, 2 do
				local oy = (-7 + row * 6) * sc
				local wl = (if row == 2 then 8 else 13) * sc
				local ox = -2 * sc + (wl - 13 * sc) / 2
				local line = Path.new()
				quad(line, p.x + ox * c - oy * sn, p.y + ox * sn + oy * c, wl, 2.4 * sc, p.rot)
				fill(self, renderer, line, Color.rgba(gr, gg, gb, math.floor(a * 255)))
			end
		elseif p.kind == 2 then
			local a = 1 - k * k
			star(path, p.x, p.y, p.size * (1 - 0.5 * k), p.rot)
			local halo = Path.new()
			circle(halo, p.x, p.y, p.size * 0.9)
			fill(self, renderer, halo, Color.rgba(gr, gg, gb, math.floor(a * 140)), true)
			fill(self, renderer, path, withAlpha(p.color, a))
		elseif p.kind == 3 then
			drawCandy(self, renderer, p, 1 - clamp((k - 0.8) / 0.2, 0, 1))
		elseif p.kind == 4 then
			local a = math.sin(math.pi * k)
			star(path, p.x, p.y, p.size * a, p.rot)
			fill(self, renderer, path, withAlpha(p.color, a))
		end
	end
end

function draw(self: Jelly, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('Jelly: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	drawOrbs(self, renderer, false)
	if image then
		renderer:save()
		renderer:transform(
			Mat2D.withTranslation(-self.width / 2, -self.height / 2)
				* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
		)
		renderer:drawImage(image, self.drawSampler, 'srcOver', 1)
		renderer:restore()
	end
	drawOrbs(self, renderer, true)
	drawThought(self, renderer)
	drawParticles(self, renderer)
end

return function(): Node<Jelly>
	return {
		rig = late(),
		state = 0,
		width = 512,
		height = 512,
		resolution = 1,
		bodyColor = Color.rgb(79, 155, 255),
		deepColor = Color.rgb(27, 74, 168),
		glowColor = Color.rgb(142, 227, 255),
		inkColor = Color.rgb(10, 24, 56),
		blushColor = Color.rgb(255, 141, 181),
		backdropColor = Color.rgb(243, 247, 255),
		gloss = 1,
		translucency = 1,
		glow = 1,
		rim = 1,
		outline = 0.6,
		paint = 0.3,
		wobble = 1,
		shadow = 1,

		context = nil,
		failed = false,
		time = 0,
		inst = nil,
		jellyNode = nil,
		crownNode = nil,
		blobNode = nil,
		sideLNode = nil,
		sideRNode = nil,
		squash = 0,
		squashV = 0,
		sway = 0,
		swayV = 0,
		bulgeL = 0,
		bulgeLV = 0,
		bulgeR = 0,
		bulgeRV = 0,
		jumpY = 0,
		jumpV = 0,
		airborne = false,
		crouch = 0,
		nextHop = 2.5,
		hopsQueued = 0,
		mood = 0,
		moodTime = 0,
		lookNode = nil,
		openNode = nil,
		happyNode = nil,
		smileNode = nil,
		oohNode = nil,
		flatNode = nil,
		grinNode = nil,
		blushLNode = nil,
		blushRNode = nil,
		lookX = 0,
		lookY = 0,
		glanceX = 0,
		glanceY = 0,
		nextGlance = 1.5,
		wOpen = 1,
		wHappy = 0,
		wSmile = 1,
		wOoh = 0,
		wFlat = 0,
		wGrin = 0,
		squint = 1,
		blush = 1,
		fxThink = 0,
		fxPlan = 0,
		glowBoost = 1,
		flash = 0,
		spawn = 0,
		beat = 0,
		particles = {},
		fxPaint = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		haloPaint = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255), feather = 9 }),

		shader = nil,
		matCanvas = nil,
		narrow = nil,
		mid = nil,
		wide = nil,
		out = nil,
		narrowPipeline = nil,
		midPipeline = nil,
		widePipeline = nil,
		finalPipeline = nil,
		narrowBindings = nil,
		midBindings = nil,
		wideBindings = nil,
		finalBindings = nil,
		ubo = nil,
		sampler = nil,
		params = buffer.create(PARAMS_SIZE),
		targetW = 0,
		targetH = 0,
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),

		init = init,
		advance = advance,
		draw = draw,
		pointerDown = pointerDown,
	}
end
