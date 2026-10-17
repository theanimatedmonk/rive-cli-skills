-- Pinaka: Lord Shiva's celestial bow, wielded by Lord Ram, from a GLB, in
-- gold with an aura radiating from it.
--
-- The bow is rendered in 3D (GPU canvas, bow.wgsl) from the GLB's parts, each
-- with its own material:
--   limbs                   red-brown wood inlaid with brass filigree: the
--                           raised relief is metal, grooves hold shadow
--   collars, spurs          antique brass in deep relief
--   grip                    wood with two white cord wraps
--   bowstring               a thin line of light
--   arrow                   hidden until `showArrow` (for the later states)
-- The carving is found at load time: each vertex's depth below its
-- neighbours ("cavity", as in Ten Rings) goes in the vertex data, and the
-- shader lights the grooves with light that flows from the grip to the tips.
--
-- Around it, drawn in 2D from the bow's projected spine:
--   radiance   a breathing glow behind the bow
--   rays       slow god rays fanning out from it
--   halo       glow hugging the bow's arc
--   wisps      divine fire rising off the bow
--   sparks     bright motes twinkling around it, in front
--   dust       motes drifting in the dark
--
-- rotationX/Y/Z (degrees) turn the bow about its centre, and spinX/Y/Z
-- (degrees per second) keep it turning; both add to the gentle sway (set
-- `sway` to 0 for exact angles). At 0 the bow is held level, belly up.
--
-- `stretch` (0-10) draws the bow: the string pulls back into a V and the
-- limbs flex (in the vertex shader). `charge` (0-1) agitates the aura while
-- drawn. `release` (0-1, keyed over the TestFire animation) plays the
-- release: the string vibrates and settles, a ripple expands from the bow in
-- all three planes and motes are thrown off in 3D.
--
-- Place at the artboard's centre. `power` (0-1, later states) intensifies
-- everything; `aura` scales the 2D aura.
--
-- The arrow (the Astra artboard): `arrow` (0-1) forms it out of light on
-- the string, nock to tip; it rides the string as it draws, its head glows
-- and a helix of light winds round the shaft, in `arrowColor`. `flight`
-- (0-1) looses it: it streaks up to stand upright with its tip at
-- `flightTipY` (px from the node, up is negative) while the bow falls away
-- below. `zoom` scales the bow, `offsetY` (px, down) shifts it, and
-- `drawDepth` scales how far it draws.
--
-- `auraStyle` picks the aura that wraps the bow and arrow as it charges:
-- 0 the gold waves, 1 mist, 2 pollen, 3 lightning, 4 fire (the astras).
-- `astraFade` (0-1) blends from the bow's resting look (`restAura`,
-- `restImprint`, the waves) to the astra's (`auraColor`, `imprintColor`,
-- `auraStyle`); it is a number, so it tweens in every runtime.

local GLB = require('GLB')

export type Pinaka = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	power: Input<number>,
	aura: Input<number>,
	sway: Input<number>,
	rotationX: Input<number>,
	rotationY: Input<number>,
	rotationZ: Input<number>,
	spinX: Input<number>,
	spinY: Input<number>,
	spinZ: Input<number>,
	showArrow: Input<boolean>,
	arrow: Input<number>,
	flight: Input<number>,
	flightTipY: Input<number>,
	zoom: Input<number>,
	offsetY: Input<number>,
	drawDepth: Input<number>,
	arrowColor: Input<Color>,
	auraStyle: Input<number>,
	astraFade: Input<number>,
	restAura: Input<Color>,
	restImprint: Input<Color>,
	stretch: Input<number>,
	charge: Input<number>,
	release: Input<number>,
	goldColor: Input<Color>,
	woodColor: Input<Color>,
	auraColor: Input<Color>,
	imprintColor: Input<Color>,

	context: Context?,
	shader: Shader?,
	failed: boolean,
	time: number,
	parts: { Part },
	spine: { { number } },
	center: { number },
	halfLength: number,
	gripHalf: number,
	stringHalf: number,
	tipFollow: number,
	-- Springs (see `advance`): the draw (0 at brace, 1 at full draw) and the
	-- bow's shift away from the string, with their velocities.
	drawPos: number,
	drawVel: number,
	shift: number,
	shiftVel: number,
	-- The arrow: its length along local +x from the nock (at 0), the
	-- string's x (bow model space), its roll in flight, and where its nock
	-- and tip land on screen this frame (node space).
	-- Agni's fire pass (auraStyle 4): a GPU canvas at FIRE_SCALE.
	firePipeline: GPUPipeline?,
	fireCanvas: GPUCanvas?,
	fireUniforms: GPUBuffer?,
	fireBindings: GPUBindGroup?,
	fireParams: buffer,
	fireFailed: boolean,
	-- This frame's aura and imprint colours (see `astraFade`).
	auraNow: Color,
	imprintNow: Color,
	arrowLength: number,
	stringX: number,
	roll: number,
	arrowWorld: Mat4,
	arrowVisible: boolean,
	arrowNockS: Vector,
	arrowTipS: Vector,
	burst: { Burst },
	model: Mat4,
	viewProj: Mat4,
	screenSpine: { Vector },
	wisps: { Wisp },
	dust: { Mote },
	sparks: { Mote },
	canvas: GPUCanvas?,
	pipeline: GPUPipeline?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	scratch: buffer,
	drawSampler: ImageSampler,
	fill: Paint,
	stroke: Paint,
}

type Kind = 'limb' | 'gold' | 'wood' | 'string' | 'arrow'

type Part = {
	kind: Kind,
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	uniforms: GPUBuffer,
	bindings: GPUBindGroup?,
}

type Wisp = { t: number, side: number, life: number, age: number, size: number, drift: number, rise: number }
type Mote = { x: number, y: number, r: number, phase: number, speed: number }
-- A particle thrown off the bow on release: born at a point on the spine
-- (model space), flying along a 3D direction.
type Burst = { t: number, dx: number, dy: number, dz: number, speed: number, r: number, phase: number }

local UNIFORM_SIZE = 304
-- Drawing: at `draw` 10 the nock is pulled this far back (model units, the
-- bow is about 1.6 long) and the tips flex this much.
local PULL_MAX = 0.95
local BEND_MAX = 0.36
-- The limbs and string: stiff and lightly damped, so they follow the pull
-- closely, and on release whip forward and ring out. Past brace the string
-- goes taut, so there the spring is much stiffer: a small overshoot and a
-- quick rebound. The bow's shift is slower and near critically damped: it
-- glides back to centre after the shot with a little recoil.
local DRAW_HZ, DRAW_DAMPING = 6, 0.25
local TAUT_HZ, TAUT_DAMPING = 18, 0.45
local SHIFT_HZ, SHIFT_DAMPING = 1.4, 0.55
local BURSTS = 240
-- The arrow is lengthened (shaft only) to this, in model units, so that at
-- a full draw at `drawDepth` 0.8 its head still clears the grip; and made
-- this much thicker, so it reads at the bow's scale.
local ARROW_LENGTH = 1.24
local ARROW_GIRTH = 2.2
-- Aloft, the arrow recedes to this fraction of its size.
local ALOFT_SCALE = 0.6
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local FOV = math.rad(26)
-- Far enough back that the bow (half-length 1) fits the square artboard
-- at any rotation, upright included, with room for the flex and the aura.
local CAM_Z = 5.6
local SPINE_BINS = 64
local CARVED_DEPTH = 0.12
local WISPS = 260

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function linear(c: Color): (number, number, number)
	local r, g, b = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return (r / 255) ^ 2.2, (g / 255) ^ 2.2, (b / 255) ^ 2.2
end

local function rgba(c: Color, alpha: number): Color
	return Color.rgba(Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number, math.floor(clamp(alpha, 0, 1) * 255))
end

local seed = 1
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function range(lo: number, hi: number): number
	return lo + (hi - lo) * rand()
end

local KAPPA = 0.5522848
local function addCircle(path: Path, cx: number, cy: number, r: number)
	local k = r * KAPPA
	path:moveTo(Vector.xy(cx + r, cy))
	path:cubicTo(Vector.xy(cx + r, cy + k), Vector.xy(cx + k, cy + r), Vector.xy(cx, cy + r))
	path:cubicTo(Vector.xy(cx - k, cy + r), Vector.xy(cx - r, cy + k), Vector.xy(cx - r, cy))
	path:cubicTo(Vector.xy(cx - r, cy - k), Vector.xy(cx - k, cy - r), Vector.xy(cx, cy - r))
	path:cubicTo(Vector.xy(cx + k, cy - r), Vector.xy(cx + r, cy - k), Vector.xy(cx + r, cy))
	path:close()
end

---------------------------------------------------------------------------
-- Loading

local function kindOf(name: string): Kind
	local n = string.lower(name)
	if string.find(n, 'arrow') then
		return 'arrow'
	elseif string.find(n, 'string') then
		return 'string'
	elseif string.find(n, 'grip') then
		return 'wood'
	elseif string.find(n, 'limb') then
		return 'limb'
	end
	return 'gold'
end

-- Cavity per vertex (how far it sits below its neighbours, over the mean
-- edge length) into the vertex's spare uv.x, lightly smoothed. -1 marks a
-- part with no real carving, so its edges never glow.
local function measureCavity(p: GLB.Primitive)
	local n = p.vertexCount
	local v = p.vertices
	local stride = GLB.VERTEX_STRIDE
	local sx, sy, sz = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local count, edge = table.create(n, 0), table.create(n, 0)
	local idx = p.indices
	for t = 0, p.indexCount - 1, 3 do
		local tri = { buffer.readu32(idx, t * 4), buffer.readu32(idx, t * 4 + 4), buffer.readu32(idx, t * 4 + 8) }
		for e = 1, 3 do
			local a, b = tri[e], tri[e % 3 + 1]
			local ao, bo = a * stride, b * stride
			local ax, ay, az = buffer.readf32(v, ao), buffer.readf32(v, ao + 4), buffer.readf32(v, ao + 8)
			local bx, by, bz = buffer.readf32(v, bo), buffer.readf32(v, bo + 4), buffer.readf32(v, bo + 8)
			local len = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
			sx[a + 1] += bx
			sy[a + 1] += by
			sz[a + 1] += bz
			count[a + 1] += 1
			edge[a + 1] += len
			sx[b + 1] += ax
			sy[b + 1] += ay
			sz[b + 1] += az
			count[b + 1] += 1
			edge[b + 1] += len
		end
	end
	local cav = table.create(n, 0)
	local deepest = 0
	for i = 1, n do
		local c = count[i]
		if c > 0 then
			local o = (i - 1) * stride
			local x, y, z = buffer.readf32(v, o), buffer.readf32(v, o + 4), buffer.readf32(v, o + 8)
			local nx, ny, nz = buffer.readf32(v, o + 12), buffer.readf32(v, o + 16), buffer.readf32(v, o + 20)
			local dx, dy, dz = sx[i] / c - x, sy[i] / c - y, sz[i] / c - z
			cav[i] = (dx * nx + dy * ny + dz * nz) / math.max(edge[i] / c, 1e-9)
			deepest = math.max(deepest, cav[i])
		end
	end
	if deepest <= CARVED_DEPTH then
		for i = 1, n do
			buffer.writef32(v, (i - 1) * stride + 24, -1)
		end
		return
	end
	-- One smoothing pass: average each vertex with its neighbours' cavity.
	local nsum, ncount = table.create(n, 0), table.create(n, 0)
	for t = 0, p.indexCount - 1, 3 do
		local a = buffer.readu32(idx, t * 4) + 1
		local b = buffer.readu32(idx, t * 4 + 4) + 1
		local c = buffer.readu32(idx, t * 4 + 8) + 1
		nsum[a] += cav[b] + cav[c]
		nsum[b] += cav[a] + cav[c]
		nsum[c] += cav[a] + cav[b]
		ncount[a] += 2
		ncount[b] += 2
		ncount[c] += 2
	end
	for i = 1, n do
		local smooth = if ncount[i] > 0 then nsum[i] / ncount[i] else cav[i]
		buffer.writef32(v, (i - 1) * stride + 24, cav[i] * 0.6 + smooth * 0.4)
		buffer.writef32(v, (i - 1) * stride + 28, 3)
	end
end

-- The limbs' almond "eye" inlays: in the mesh, a smooth oval panel set in
-- the brass sleeve on the back of each limb, near the grip. For each vertex
-- this stores (uv.y) how far it is from that almond's edge: < 1 inside,
-- > 1 outside. It is a smooth field, so the shader's cut-off draws a clean
-- curve whatever the triangles. The shape was measured from the mesh's
-- smooth panel: centred a quarter of the way along the limb, about 0.27 of
-- the limb long, about 1.1 radians wide around it.
local EYE_T, EYE_HALF_T, EYE_HALF_ANGLE = 0.24, 0.15, 0.6
local function markEye(self: Pinaka, p: GLB.Primitive)
	local n = p.vertexCount
	local v = p.vertices
	local stride = GLB.VERTEX_STRIDE
	local span = math.max(self.halfLength - self.gripHalf, 1e-3)
	local cy = self.center[2]
	-- This limb's centre line: mean x, z per slice along its length.
	local BINS = 48
	local sx, sz, sc = table.create(BINS, 0), table.create(BINS, 0), table.create(BINS, 0)
	local function tOf(o: number): number
		return (math.abs(buffer.readf32(v, o + 4) - cy) - self.gripHalf) / span
	end
	for i = 0, n - 1 do
		local o = i * stride
		local b = clamp(math.floor(tOf(o) * BINS) + 1, 1, BINS)
		sx[b] += buffer.readf32(v, o)
		sz[b] += buffer.readf32(v, o + 8)
		sc[b] += 1
	end
	for b = 1, BINS do
		if sc[b] > 0 then
			sx[b] /= sc[b]
			sz[b] /= sc[b]
		end
	end
	for i = 0, n - 1 do
		local o = i * stride
		local t = tOf(o)
		local b = clamp(math.floor(t * BINS) + 1, 1, BINS)
		local angle = math.atan2(buffer.readf32(v, o + 8) - sz[b], buffer.readf32(v, o) - sx[b])
		local u = (t - EYE_T) / EYE_HALF_T
		local width = EYE_HALF_ANGLE * (1 - u * u) -- pointed at both ends
		local f = if width > 0.01 then math.abs(angle) / width else 3
		buffer.writef32(v, o + 28, math.min(f, 3))
	end
end

-- The GLB's bowstring is a thin box with vertices only at its two ends, so
-- it cannot bend. Replace it with a round tube of many segments along the
-- same line, which the vertex shader can pull into a V and vibrate.
local STRING_SEGMENTS = 40
local STRING_SIDES = 6
local function rebuildString(p: GLB.Primitive)
	local v = p.vertices
	local stride = GLB.VERTEX_STRIDE
	local minY, maxY = math.huge, -math.huge
	local sx, sz = 0, 0
	local minX, maxX = math.huge, -math.huge
	for i = 0, p.vertexCount - 1 do
		local o = i * stride
		local x, y, z = buffer.readf32(v, o), buffer.readf32(v, o + 4), buffer.readf32(v, o + 8)
		minY = math.min(minY, y)
		maxY = math.max(maxY, y)
		minX = math.min(minX, x)
		maxX = math.max(maxX, x)
		sx += x
		sz += z
	end
	local cx, cz = sx / p.vertexCount, sz / p.vertexCount
	local radius = math.max((maxX - minX) * 0.5, 0.0012)
	local rings = STRING_SEGMENTS + 1
	local count = rings * STRING_SIDES
	local verts = buffer.create(count * stride)
	for r = 0, STRING_SEGMENTS do
		local y = minY + (maxY - minY) * r / STRING_SEGMENTS
		for k = 0, STRING_SIDES - 1 do
			local a = k / STRING_SIDES * math.pi * 2
			local nx, nz = math.cos(a), math.sin(a)
			local o = (r * STRING_SIDES + k) * stride
			buffer.writef32(verts, o, cx + nx * radius)
			buffer.writef32(verts, o + 4, y)
			buffer.writef32(verts, o + 8, cz + nz * radius)
			buffer.writef32(verts, o + 12, nx)
			buffer.writef32(verts, o + 16, 0)
			buffer.writef32(verts, o + 20, nz)
			buffer.writef32(verts, o + 24, -1)
			buffer.writef32(verts, o + 28, 3)
		end
	end
	local quads = STRING_SEGMENTS * STRING_SIDES
	local indices = buffer.create(quads * 6 * 4)
	local w = 0
	for r = 0, STRING_SEGMENTS - 1 do
		for k = 0, STRING_SIDES - 1 do
			local a = r * STRING_SIDES + k
			local b = r * STRING_SIDES + (k + 1) % STRING_SIDES
			local c = a + STRING_SIDES
			local d = b + STRING_SIDES
			for _, idx in { a, c, b, b, c, d } do
				buffer.writeu32(indices, w, idx)
				w += 4
			end
		end
	end
	p.vertices = verts
	p.vertexCount = count
	p.indices = indices
	p.indexCount = quads * 6
end

-- The arrow, realigned: in the GLB it lies a little askew and is shorter
-- than a full draw. Put every arrow part on one axis (local +x, the nock at
-- 0, the tip at ARROW_LENGTH) and lengthen the shaft between the fletching
-- and the head, leaving those as modelled.
local function prepareArrow(self: Pinaka, primitives: { GLB.Primitive })
	local arrows: { GLB.Primitive } = {}
	for _, p in primitives do
		if kindOf(p.nodeName .. p.meshName) == 'arrow' then
			table.insert(arrows, p)
		end
	end
	if #arrows == 0 then
		return
	end
	local body = arrows[1]
	for _, p in arrows do
		if p.vertexCount > body.vertexCount then
			body = p
		end
	end
	local stride = GLB.VERTEX_STRIDE
	-- The axis: least squares y(x) and z(x) over the body.
	local n, sx, sy, sz, sxx, sxy, sxz = 0, 0, 0, 0, 0, 0, 0
	for i = 0, body.vertexCount - 1 do
		local o = i * stride
		local x, y, z = buffer.readf32(body.vertices, o), buffer.readf32(body.vertices, o + 4), buffer.readf32(body.vertices, o + 8)
		n += 1
		sx += x
		sy += y
		sz += z
		sxx += x * x
		sxy += x * y
		sxz += x * z
	end
	local den = n * sxx - sx * sx
	if n < 2 or math.abs(den) < 1e-9 then
		return
	end
	local ky, kz = (n * sxy - sx * sy) / den, (n * sxz - sx * sz) / den
	local y0, z0 = (sy - ky * sx) / n, (sz - kz * sx) / n
	local al = math.sqrt(1 + ky * ky + kz * kz)
	local ax, ay, az = 1 / al, ky / al, kz / al
	-- A frame across it: e2 = axis x Z, e3 = axis x e2.
	local el = math.sqrt(ay * ay + ax * ax)
	local e2x, e2y, e2z = ay / el, -ax / el, 0
	local e3x, e3y, e3z = ay * e2z - az * e2y, az * e2x - ax * e2z, ax * e2y - ay * e2x
	local umin, umax = math.huge, -math.huge
	for _, p in arrows do
		for i = 0, p.vertexCount - 1 do
			local o = i * stride
			local x, y, z = buffer.readf32(p.vertices, o), buffer.readf32(p.vertices, o + 4) - y0, buffer.readf32(p.vertices, o + 8) - z0
			local u = x * ax + y * ay + z * az
			umin = math.min(umin, u)
			umax = math.max(umax, u)
		end
	end
	local L0 = umax - umin
	local extra = ARROW_LENGTH - L0
	local shaftStart, headStart = 0.25 * L0, L0 - 0.17
	local k = (headStart + extra - shaftStart) / (headStart - shaftStart)
	for _, p in arrows do
		local v = p.vertices
		for i = 0, p.vertexCount - 1 do
			local o = i * stride
			local x, y, z = buffer.readf32(v, o), buffer.readf32(v, o + 4) - y0, buffer.readf32(v, o + 8) - z0
			local u = x * ax + y * ay + z * az - umin
			if u > headStart then
				u += extra
			elseif u > shaftStart then
				u = shaftStart + (u - shaftStart) * k
			end
			buffer.writef32(v, o, u)
			buffer.writef32(v, o + 4, (x * e2x + y * e2y + z * e2z) * ARROW_GIRTH)
			buffer.writef32(v, o + 8, (x * e3x + y * e3y + z * e3z) * ARROW_GIRTH)
			local nx, ny, nz = buffer.readf32(v, o + 12), buffer.readf32(v, o + 16), buffer.readf32(v, o + 20)
			buffer.writef32(v, o + 12, nx * ax + ny * ay + nz * az)
			buffer.writef32(v, o + 16, nx * e2x + ny * e2y + nz * e2z)
			buffer.writef32(v, o + 20, nx * e3x + ny * e3y + nz * e3z)
		end
	end
	self.arrowLength = ARROW_LENGTH
end

local function load(self: Pinaka): boolean
	local context = self.context
	assert(context)
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`Pinaka: no blob asset named '{self.asset}'`)
		return false
	end
	local model, err = GLB.parse(blob.data)
	if model == nil then
		print(`Pinaka: could not load '{self.asset}': {err}`)
		return false
	end
	-- Bounds and spine from the bow itself (not the arrow).
	local minX: number = math.huge
	local maxX: number = -math.huge
	local minY: number = math.huge
	local maxY: number = -math.huge
	local minZ: number = math.huge
	local maxZ: number = -math.huge
	for _, p in model.primitives do
		if kindOf(p.nodeName .. p.meshName) ~= 'arrow' then
			for i = 0, p.vertexCount - 1 do
				local o = i * GLB.VERTEX_STRIDE
				local x, y, z = buffer.readf32(p.vertices, o), buffer.readf32(p.vertices, o + 4), buffer.readf32(p.vertices, o + 8)
				minX = math.min(minX, x)
				maxX = math.max(maxX, x)
				minY = math.min(minY, y)
				maxY = math.max(maxY, y)
				minZ = math.min(minZ, z)
				maxZ = math.max(maxZ, z)
			end
		end
	end
	self.center = { (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2 }
	for _, p in model.primitives do
		if kindOf(p.nodeName .. p.meshName) == 'string' then
			local sh, sxSum = 0, 0
			for i = 0, p.vertexCount - 1 do
				sh = math.max(sh, math.abs(buffer.readf32(p.vertices, i * GLB.VERTEX_STRIDE + 4) - self.center[2]))
				sxSum += buffer.readf32(p.vertices, i * GLB.VERTEX_STRIDE)
			end
			self.stringHalf = sh
			self.stringX = sxSum / math.max(p.vertexCount, 1)
		end
	end
	prepareArrow(self, model.primitives)
	for _, p in model.primitives do
		if kindOf(p.nodeName .. p.meshName) == 'wood' then
			local gy = 0
			for i = 0, p.vertexCount - 1 do
				gy = math.max(gy, math.abs(buffer.readf32(p.vertices, i * GLB.VERTEX_STRIDE + 4) - self.center[2]))
			end
			self.gripHalf = gy
		end
	end
	self.halfLength = (maxY - minY) / 2

	-- The spine: the centre line of the limbs and grip, bin by bin along Y.
	local bx, bz, bn = table.create(SPINE_BINS, 0), table.create(SPINE_BINS, 0), table.create(SPINE_BINS, 0)
	for _, p in model.primitives do
		local k = kindOf(p.nodeName .. p.meshName)
		if k == 'gold' or k == 'wood' or k == 'limb' then
			for i = 0, p.vertexCount - 1, 3 do
				local o = i * GLB.VERTEX_STRIDE
				local x, y, z = buffer.readf32(p.vertices, o), buffer.readf32(p.vertices, o + 4), buffer.readf32(p.vertices, o + 8)
				local bin = clamp(math.floor((y - minY) / (maxY - minY) * SPINE_BINS) + 1, 1, SPINE_BINS)
				bx[bin] += x
				bz[bin] += z
				bn[bin] += 1
			end
		end
	end
	self.spine = {}
	for i = 1, SPINE_BINS do
		if bn[i] > 0 then
			table.insert(self.spine, { bx[i] / bn[i], minY + (i - 0.5) / SPINE_BINS * (maxY - minY), bz[i] / bn[i] })
		end
	end
	-- Smooth it: collars and carving make the slice centres bumpy, which
	-- would make the aura waves (laid out along its normal) zig-zag.
	for _ = 1, 6 do
		local smoothed = {}
		for i, p in self.spine do
			local a = self.spine[math.max(i - 1, 1)]
			local b = self.spine[math.min(i + 1, #self.spine)]
			smoothed[i] = { (a[1] + 2 * p[1] + b[1]) / 4, p[2], (a[3] + 2 * p[3] + b[3]) / 4 }
		end
		self.spine = smoothed
	end

	for _, p in model.primitives do
		local kind = kindOf(p.nodeName .. p.meshName)
		if kind == 'string' then
			rebuildString(p)
		end
		if kind == 'gold' or kind == 'limb' then
			measureCavity(p)
			if kind == 'limb' then
				markEye(self, p)
			else
				for i = 0, p.vertexCount - 1 do
					buffer.writef32(p.vertices, i * GLB.VERTEX_STRIDE + 28, 0)
				end
			end
		else
			for i = 0, p.vertexCount - 1 do
				buffer.writef32(p.vertices, i * GLB.VERTEX_STRIDE + 24, -1)
			end
		end
		table.insert(self.parts, {
			kind = kind,
			vertexBuffer = GPUBuffer.new({ size = buffer.len(p.vertices), usage = 'vertex', data = p.vertices, immutable = true }),
			indexBuffer = GPUBuffer.new({ size = buffer.len(p.indices), usage = 'index', data = p.indices, immutable = true }),
			indexCount = p.indexCount,
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
		})
	end
	-- The string's ends sit part way along the limbs; they follow that much
	-- of the tip flex (which grows with the square of the distance).
	local span = math.max(self.halfLength - self.gripHalf, 1e-3)
	local f = clamp((self.stringHalf - self.gripHalf) / span, 0, 1)
	self.tipFollow = f * f
	print(`Pinaka: {#self.parts} parts, {model.triangleCount} triangles, spine {#self.spine} points`)
	return #self.parts > 0
end

local function buildParticles(self: Pinaka)
	seed = 30181
	self.wisps = {}
	for _ = 1, WISPS do
		local w: Wisp = { t = 0, side = 0, life = 1, age = 0, size = 1, drift = 0, rise = 0 }
		w.t = rand()
		w.side = if rand() < 0.5 then -1 else 1
		w.life = range(1.6, 3.4)
		w.age = range(0, w.life)
		w.size = range(0.6, 2.2)
		w.drift = range(-14, 14)
		w.rise = range(40, 110)
		table.insert(self.wisps, w)
	end
	self.dust = {}
	for _ = 1, 110 do
		table.insert(self.dust, { x = range(-0.5, 0.5), y = range(-0.5, 0.5), r = range(0.3, 0.9), phase = range(0, 6.28), speed = range(4, 14) })
	end
	self.sparks = {}
	for _ = 1, 46 do
		table.insert(self.sparks, { x = rand(), y = range(-1, 1), r = range(0.5, 1.3), phase = range(0, 6.28), speed = range(1.5, 4) })
	end
	self.burst = {}
	for _ = 1, BURSTS do
		-- A random direction in 3D.
		local z = range(-1, 1)
		local a = range(0, math.pi * 2)
		local k = math.sqrt(1 - z * z)
		table.insert(self.burst, {
			t = rand(),
			dx = k * math.cos(a),
			dy = k * math.sin(a),
			dz = z,
			speed = range(0.6, 2.4),
			r = range(0.5, 1.8),
			phase = range(0, 6.28),
		})
	end
end

function init(self: Pinaka, context: Context): boolean
	self.context = context
	self.shader = context:shader('bow')
	if self.shader == nil then
		print('Pinaka: shader "bow" not found')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('Pinaka: setup failed: ' .. tostring(err))
		self.failed = true
	end
	buildParticles(self)
	return true
end

local function spring(x: number, v: number, target: number, hz: number, damping: number, dt: number): (number, number)
	local w = 2 * math.pi * hz
	v += (w * w * (target - x) - 2 * damping * w * v) * dt
	return x + v * dt, v
end

function advance(self: Pinaka, seconds: number): boolean
	self.time += seconds
	local dt = math.min(seconds, 0.05)
	-- `stretch` sets where the archer holds the string; the bow follows on
	-- springs, in small steps so the stiff one stays stable.
	self.roll += dt * 9 * clamp(self.flight, 0, 1)
	local target = clamp(self.stretch, 0, 10) / 10
	local steps = math.max(1, math.ceil(dt * 480))
	local h = dt / steps
	for _ = 1, steps do
		local taut = self.drawPos < 0
		self.drawPos, self.drawVel = spring(
			self.drawPos,
			self.drawVel,
			target,
			if taut then TAUT_HZ else DRAW_HZ,
			if taut then TAUT_DAMPING else DRAW_DAMPING,
			h
		)
		self.shift, self.shiftVel = spring(self.shift, self.shiftVel, target, SHIFT_HZ, SHIFT_DAMPING, h)
	end
	local power = clamp(self.power, 0, 1.5)
	for _, w in self.wisps do
		w.age += dt * (1 + power + 2.2 * clamp(self.charge, 0, 1.5))
		if w.age > w.life then
			w.age -= w.life
			w.t = rand()
			w.side = if rand() < 0.5 then -1 else 1
			w.drift = range(-14, 14)
		end
	end
	return true
end

---------------------------------------------------------------------------
-- 3D render

local function ensureTargets(self: Pinaka): GPUCanvas?
	local context = self.context
	assert(context)
	local res = clamp(self.resolution, 0.25, 3)
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
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = canvas.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.pipeline == nil then
		local shader = self.shader
		assert(shader)
		self.pipeline = GPUPipeline.new({
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
			cullMode = 'none',
			sampleCount = samples,
		})
		for _, part in self.parts do
			part.bindings = nil
		end
	end
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return canvas
end

-- How far the nock is pulled and the tips flex (model units), from the draw
-- spring. Past brace (after release) the limbs flex forward a little. Held
-- at full draw the string trembles with the strain; after release it twangs:
-- a fast, quickly damped wobble read from `release` (0 at the release, 1
-- once settled).
local function deform(self: Pinaka): (number, number)
	local d = clamp(self.drawPos, -0.25, 1.1) * math.max(self.drawDepth, 0)
	local pull = d * PULL_MAX
	local strain = clamp(d, 0, 1) ^ 6
	pull += strain * 0.006 * (math.sin(self.time * 41) + 0.6 * math.sin(self.time * 67 + 1.3))
	local release = clamp(self.release, 0, 1)
	if release > 0 and release < 1 then
		pull += math.sin(self.time * 75) * 0.035 * math.exp(-release * 9)
	end
	return pull, d * BEND_MAX
end

-- Per-part material, written into that part's uniforms.
local function writeUniforms(self: Pinaka, part: Part, mvp: Mat4, model: Mat4)
	local u = self.scratch
	local power = clamp(self.power, 0, 1.5)
	mvp:writeToBuffer(u, 0)
	model:writeToBuffer(u, 64)
	-- Antique brass, wood with brass filigree, a wooden grip, or light.
	local base = { linear(self.goldColor) }
	local metallic, roughness, emissive, rimK, imprintK, mode = 1, 0.4, 0, 0.3, 0.45, 0
	if part.kind == 'limb' then
		mode = 1
	elseif part.kind == 'wood' then
		metallic, roughness, rimK, imprintK, mode = 0.1, 0.5, 0.18, 0, 2
	elseif part.kind == 'string' then
		base = { linear(Color.rgb(255, 236, 190)) }
		metallic, roughness, emissive, rimK, imprintK, mode = 0, 0.6, 2.2, 0, 0, 3
	elseif part.kind == 'arrow' then
		metallic, roughness, rimK, imprintK, mode = 1, 0.3, 0.5, 0, 4
	end
	buffer.writef32(u, 128, base[1])
	buffer.writef32(u, 132, base[2])
	buffer.writef32(u, 136, base[3])
	buffer.writef32(u, 140, 1)
	local ar, ag, ab = linear(if part.kind == 'arrow' then self.arrowColor else self.auraNow)
	local er, eg, eb = linear(Color.rgb(255, 228, 170))
	local glow = emissive * (1 + power)
	buffer.writef32(u, 144, er * glow)
	buffer.writef32(u, 148, eg * glow)
	buffer.writef32(u, 152, eb * glow)
	buffer.writef32(u, 156, 1)
	buffer.writef32(u, 160, ar)
	buffer.writef32(u, 164, ag)
	buffer.writef32(u, 168, ab)
	buffer.writef32(u, 172, rimK * (1 + power))
	-- Key light from the upper left, in front.
	local lx, ly, lz = -0.45, 0.65, 0.62
	local ll = math.sqrt(lx * lx + ly * ly + lz * lz)
	buffer.writef32(u, 176, lx / ll)
	buffer.writef32(u, 180, ly / ll)
	buffer.writef32(u, 184, lz / ll)
	buffer.writef32(u, 188, 2.4)
	buffer.writef32(u, 192, 0)
	buffer.writef32(u, 196, 0)
	buffer.writef32(u, 200, CAM_Z)
	buffer.writef32(u, 204, 0.3)
	buffer.writef32(u, 208, metallic)
	buffer.writef32(u, 212, roughness)
	buffer.writef32(u, 216, self.time)
	buffer.writef32(u, 220, 1.1) -- exposure
	local ir, ig, ib = linear(self.imprintNow)
	buffer.writef32(u, 224, ir)
	buffer.writef32(u, 228, ig)
	buffer.writef32(u, 232, ib)
	buffer.writef32(u, 236, imprintK * (1 + power))
	buffer.writef32(u, 240, 0.8) -- environment
	buffer.writef32(u, 244, 1) -- opacity
	buffer.writef32(u, 248, 0.16)
	buffer.writef32(u, 252, 0.34)
	local wr, wg, wb = linear(self.woodColor)
	buffer.writef32(u, 256, wr)
	buffer.writef32(u, 260, wg)
	buffer.writef32(u, 264, wb)
	buffer.writef32(u, 268, 0.16) -- grain strength
	buffer.writef32(u, 272, mode)
	buffer.writef32(u, 276, self.center[2])
	-- The limbs run from the grip's ends out to the tips: start and length.
	buffer.writef32(u, 280, self.gripHalf)
	buffer.writef32(u, 284, math.max(self.halfLength - self.gripHalf, 1e-3))
	local pull, bend = deform(self)
	buffer.writef32(u, 288, pull)
	buffer.writef32(u, 292, bend)
	buffer.writef32(u, 296, self.stringHalf)
	buffer.writef32(u, 300, self.tipFollow)
	if part.kind == 'arrow' then
		-- The arrow: its length, how far it has formed (from the nock), and
		-- how hot its head glows.
		local formed = if self.showArrow then 1 else clamp(self.arrow, 0, 1)
		buffer.writef32(u, 276, self.arrowLength)
		buffer.writef32(u, 280, formed * self.arrowLength * 1.02)
		buffer.writef32(u, 284, 0.6 + 1.4 * clamp(self.charge, 0, 1.5) + 1.6 * clamp(self.flight, 0, 1))
	end
	part.uniforms:write(u)
end

local function render(self: Pinaka): Image?
	local canvas = ensureTargets(self)
	local pipeline, depthView = self.pipeline, self.depthView
	if canvas == nil or pipeline == nil or depthView == nil then
		return nil
	end
	local t = self.time
	local sway = math.rad(self.sway)
	-- Held level, the belly rising to the centre and the tips curving down;
	-- floating and turning slowly so light runs over the gold.
	local s = math.max(self.zoom, 0.05) / math.max(self.halfLength, 1e-6)
	local c = self.center
	-- As it draws, the bow shifts away from the string by half the pull, so
	-- the bow and the drawn string stay centred together.
	local recentre = self.shift * PULL_MAX * 0.5 * math.max(self.drawDepth, 0)
	-- World units per node pixel at the bow's depth.
	local wpp = CAM_Z * math.tan(FOV / 2) / (self.height / 2)
	-- In flight the arrow snaps away fast, overshoots a touch and settles
	-- (an ease-out-back), and the bow falls away below the frame and tilts
	-- back, as if the eye turned up to follow the arrow.
	local f = clamp(self.flight, 0, 1)
	local launch = 1 + 1.8 * (f - 1) ^ 3 + 0.8 * (f - 1) ^ 2
	local away = 1 - (1 - f) ^ 3
	local drop = away * 3.8
	-- Rotation inputs (degrees) plus spin (degrees per second), applied
	-- X, then Y, then Z, about the bow's centre, on top of the sway.
	local rx = math.rad(self.rotationX + self.spinX * t)
	local ry = math.rad(self.rotationY + self.spinY * t)
	local rz = math.rad(self.rotationZ + self.spinZ * t)
	local model = Mat4.fromTranslation(0, math.sin(t * 0.8) * 0.035 - self.offsetY * wpp - drop, 0)
		* Mat4.fromRotationX(-math.rad(35) * away)
		* Mat4.fromRotationZ(rz)
		* Mat4.fromRotationY(ry)
		* Mat4.fromRotationX(rx)
		* Mat4.fromRotationY(math.sin(t * 0.37) * sway)
		* Mat4.fromRotationX(math.sin(t * 0.29 + 1) * sway * 0.35)
		* Mat4.fromRotationZ(math.pi / 2)
		* Mat4.fromScale(s, s, s)
		* Mat4.fromTranslation(-c[1] + recentre, -c[2], -c[3])
	local aspect = self.targetW / self.targetH
	local proj = Mat4.perspective(FOV, aspect, 0.5, 20)
	local view = Mat4.lookAt(Vector.xyz(0, 0, CAM_Z), Vector.origin(), Vector.xyz(0, 1, 0))
	local viewProj = proj * view
	self.model, self.viewProj = model, viewProj
	local mvp = viewProj * model

	-- The arrow: nocked on the string (riding it as it draws), or loosed:
	-- streaking to stand upright with its tip at `flightTipY`.
	local arrowOn = self.showArrow or self.arrow > 0.001
	self.arrowVisible = arrowOn
	local arrowMvp = mvp
	if arrowOn then
		local pull = deform(self)
		local L = self.arrowLength
		local nock = model:transformPoint(self.stringX - pull, c[2], c[3])
		local tip = model:transformPoint(self.stringX - pull + L, c[2], c[3])
		local e = launch
		local tipY = -self.flightTipY * wpp
		-- Aloft it drifts and sways a little, as if riding the air.
		local aloft = f * f
		local swayTip = math.sin(t * 1.1) * 0.03 * aloft
		local swayNock = math.sin(t * 1.1 - 0.7) * 0.06 * aloft
		local bob = math.sin(t * 0.8) * 0.025 * aloft
		-- And it recedes as it flies away, to ALOFT_SCALE of its size,
		-- leaving room below for its tail.
		local nx = nock.x * (1 - e) + swayNock
		local ny = nock.y + (tipY - L * s * ALOFT_SCALE - nock.y) * e + bob
		local nz = nock.z * (1 - e)
		local tx = tip.x * (1 - e) + swayTip
		local ty = tip.y + (tipY - tip.y) * e + bob
		local tz = tip.z * (1 - e)
		local dx, dy, dz = tx - nx, ty - ny, tz - nz
		local len = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
		local ax, ay, az = dx / len, dy / len, dz / len
		-- Across it: axis x Z, then axis x that, turned by the roll.
		local el = math.max(math.sqrt(ay * ay + ax * ax), 1e-6)
		local px, py, pz = ay / el, -ax / el, 0
		local qx, qy, qz = ay * pz - az * py, az * px - ax * pz, ax * py - ay * px
		local cr, sr = math.cos(self.roll), math.sin(self.roll)
		local bx, by, bz = px * cr + qx * sr, py * cr + qy * sr, pz * cr + qz * sr
		local gx, gy, gz = qx * cr - px * sr, qy * cr - py * sr, qz * cr - pz * sr
		local k = len / L
		local world = Mat4.values(
			ax * k, ay * k, az * k, 0,
			bx * k, by * k, bz * k, 0,
			gx * k, gy * k, gz * k, 0,
			nx, ny, nz, 1
		)
		self.arrowWorld = world
		arrowMvp = viewProj * world
		local qn = viewProj:transformPoint(nx, ny, nz)
		local qt = viewProj:transformPoint(tx, ty, tz)
		self.arrowNockS = Vector.xy(qn.x * 0.5 * self.width, -qn.y * 0.5 * self.height)
		self.arrowTipS = Vector.xy(qt.x * 0.5 * self.width, -qt.y * 0.5 * self.height)
	end

	for _, part in self.parts do
		if part.kind == 'arrow' and arrowOn then
			writeUniforms(self, part, arrowMvp, self.arrowWorld)
			if part.bindings == nil then
				part.bindings = GPUBindGroup.new({ layout = pipeline:getBindGroupLayout(0), ubos = { { slot = 0, buffer = part.uniforms } } })
			end
		elseif part.kind ~= 'arrow' then
			writeUniforms(self, part, mvp, model)
			if part.bindings == nil then
				part.bindings = GPUBindGroup.new({ layout = pipeline:getBindGroupLayout(0), ubos = { { slot = 0, buffer = part.uniforms } } })
			end
		end
	end

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = canvas:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 0 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } }
	local pass = canvas:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 1 },
	})
	pass:setPipeline(pipeline)
	for _, part in self.parts do
		local bindings = part.bindings
		if bindings and (part.kind ~= 'arrow' or arrowOn) then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, part.vertexBuffer)
			pass:setIndexBuffer(part.indexBuffer, 'uint32')
			pass:drawIndexed(part.indexCount)
		end
	end
	pass:finish()

	-- The spine on screen (node space, origin at the artboard centre), bent
	-- with the limbs as in the vertex shader, so the aura follows the draw.
	local m = viewProj * model
	local _, bend = deform(self)
	local limb = math.max(self.halfLength - self.gripHalf, 1e-3)
	local shorten = 2 / 3 * bend * bend / limb
	self.screenSpine = {}
	for _, p in self.spine do
		local dy = p[2] - self.center[2]
		local side = if dy < 0 then -1 else 1
		local lf = clamp((math.abs(dy) - self.gripHalf) / limb, 0, 1)
		local q = m:transformPoint(p[1] - bend * lf * lf, p[2] - side * shorten * lf * lf * lf, p[3])
		table.insert(self.screenSpine, Vector.xy(q.x * 0.5 * self.width, -q.y * 0.5 * self.height))
	end
	return canvas.image
end

---------------------------------------------------------------------------
-- 2D aura

local function spineAt(self: Pinaka, t: number): Vector
	local pts = self.screenSpine
	local n = #pts
	if n == 0 then
		return Vector.origin()
	end
	local f = clamp(t, 0, 1) * (n - 1) + 1
	local i = math.floor(f)
	local j = math.min(i + 1, n)
	local k = f - i
	local a, b = pts[i], pts[j]
	return Vector.xy(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k)
end

local function drawRadiance(self: Pinaka, renderer: Renderer, amount: number)
	local t = self.time
	local breathe = 1 + 0.06 * math.sin(t * 1.3)
	local w = self.width
	local center = spineAt(self, 0.5)
	local f = self.fill
	-- A wide warm field, then a hotter core behind the grip.
	for i, spec in { { 0.62, 0.20 }, { 0.32, 0.30 }, { 0.14, 0.45 } } do
		local r = w * spec[1] * breathe
		f.gradient = Gradient.radial(Vector.xy(center.x, center.y + 10), r, {
			{ position = 0, color = rgba(self.auraNow, spec[2] * amount) },
			{ position = 0.5, color = rgba(self.auraNow, spec[2] * 0.35 * amount) },
			{ position = 1, color = rgba(self.auraNow, 0) },
		})
		local box = Path.new()
		box:moveTo(Vector.xy(center.x - r, center.y + 10 - r))
		box:lineTo(Vector.xy(center.x + r, center.y + 10 - r))
		box:lineTo(Vector.xy(center.x + r, center.y + 10 + r))
		box:lineTo(Vector.xy(center.x - r, center.y + 10 + r))
		box:close()
		renderer:save()
		renderer:transform(Mat2D.withTranslation(center.x, center.y + 10) * Mat2D.withScale(1, 0.62) * Mat2D.withTranslation(-center.x, -center.y - 10))
		renderer:drawPath(box, f)
		renderer:restore()
		local _ = i
	end
	f.gradient = nil
end

local function drawRays(self: Pinaka, renderer: Renderer, amount: number)
	local t = self.time
	local center = spineAt(self, 0.5)
	local f = self.fill
	local count = 30
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + t * 0.05 + math.sin(i * 12.9) * 0.08
		local len = self.width * (0.28 + 0.22 * (0.5 + 0.5 * math.sin(i * 7.3 + t * 0.6)))
		local spread = 0.022 + 0.012 * math.sin(i * 3.1)
		local alpha = (0.05 + 0.05 * math.sin(t * 0.9 + i * 2.3)) * amount
		local tip = Vector.xy(center.x + math.cos(a) * len, center.y + math.sin(a) * len * 0.7)
		local l = Vector.xy(center.x + math.cos(a - spread) * len, center.y + math.sin(a - spread) * len * 0.7)
		local r = Vector.xy(center.x + math.cos(a + spread) * len, center.y + math.sin(a + spread) * len * 0.7)
		f.gradient = Gradient.linear(center, tip, {
			{ position = 0, color = rgba(self.auraNow, alpha) },
			{ position = 1, color = rgba(self.auraNow, 0) },
		})
		local ray = Path.new()
		ray:moveTo(center)
		ray:lineTo(l)
		ray:lineTo(r)
		ray:close()
		f.feather = 6
		renderer:drawPath(ray, f)
	end
	f.gradient = nil
	f.feather = 0
end

local function drawDust(self: Pinaka, renderer: Renderer, amount: number)
	local f = self.fill
	local w, h = self.width, self.height
	for _, d in self.dust do
		local y = ((d.y * h - self.time * d.speed) % h) - h / 2
		local x = d.x * w + math.sin(self.time * 0.4 + d.phase) * 10
		local tw = 0.35 + 0.35 * math.sin(self.time * 1.3 + d.phase)
		local dot = Path.new()
		addCircle(dot, x, y, d.r)
		f.color = rgba(self.auraNow, tw * 0.5 * amount)
		renderer:drawPath(dot, f)
	end
end

-- A point in the bow's world (after its pose) on screen, in node space, and
-- how much nearer than the bow's centre it is (1 = same depth). nil behind
-- or too near the camera.
local function project(self: Pinaka, x: number, y: number, z: number): (Vector?, number)
	if z > CAM_Z - 0.35 then
		return nil, 0
	end
	local q = self.viewProj:transformPoint(x, y, z)
	return Vector.xy(q.x * 0.5 * self.width, -q.y * 0.5 * self.height), CAM_Z / (CAM_Z - z)
end

-- Unit normal to the screen spine at t.
local function spineNormal(self: Pinaka, t: number): Vector
	local a = spineAt(self, math.max(t - 0.04, 0))
	local b = spineAt(self, math.min(t + 0.04, 1))
	local dx, dy = b.x - a.x, b.y - a.y
	local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-6)
	return Vector.xy(dy / len, -dx / len)
end

-- Aura waves, as in Ten Rings: light ribbons that follow the bow and
-- undulate in and out from it, with bright pulses travelling along them.
-- When charged they swell, speed up and tremble; on release they are blown
-- outward from the bow.
type Ribbon = { freq: number, speed: number, amp: number, lift: number, phase: number }
local RIBBONS: { Ribbon } = {
	{ freq = 3.0, speed = 1.3, amp = 16, lift = 6, phase = 0.0 },
	{ freq = 4.5, speed = -1.7, amp = 12, lift = -8, phase = 1.9 },
	{ freq = 2.2, speed = 0.9, amp = 22, lift = 14, phase = 3.7 },
	{ freq = 5.5, speed = -2.3, amp = 9, lift = -16, phase = 5.1 },
	{ freq = 3.6, speed = 1.9, amp = 18, lift = 22, phase = 2.6 },
}
local RIBBON_POINTS = 56

local function drawWaves(self: Pinaka, renderer: Renderer, amount: number, front: boolean)
	if #self.screenSpine < 2 then
		return
	end
	local t = self.time
	local charge = clamp(self.charge, 0, 1.5)
	local release = clamp(self.release, 0, 1)
	local active = release > 0 and release < 1
	local blow = if active then math.sin(release * math.pi) * 90 else 0
	local fade = if active then 1 - 0.7 * math.sin(release * math.pi) else 1
	local st = self.stroke
	st.cap = 'round'
	st.join = 'round'
	for r, rib in RIBBONS do
		-- Alternate ribbons behind the bow and in front of it.
		if (r % 2 == 0) == front then
			local amp = rib.amp * (1 + 1.6 * charge)
			local speed = rib.speed * (1 + 2.5 * charge)
			local points: { Vector } = {}
			for k = 0, RIBBON_POINTS do
				local u = k / RIBBON_POINTS
				local base = spineAt(self, u)
				local n = spineNormal(self, u)
				-- Charged: a fast shiver that stays smooth along the ribbon.
				local tremble = charge * 7 * math.sin(t * 17 + u * 11 + r * 1.3)
				local off = rib.lift * (1 + charge) + amp * math.sin(u * rib.freq * math.pi * 2 + t * speed + rib.phase) + tremble
				off += blow * (if rib.lift >= 0 then 1 else -1)
				table.insert(points, Vector.xy(base.x + n.x * off, base.y + n.y * off))
			end
			local glow = Path.new()
			for k, pt in points do
				if k == 1 then
					glow:moveTo(pt)
				else
					glow:lineTo(pt)
				end
			end
			st.thickness = 5 + 4 * charge
			st.feather = 10
			st.color = rgba(self.auraNow, (0.16 + 0.18 * charge) * amount * fade)
			renderer:drawPath(glow, st)
			-- Pulses: short bright stretches running along it.
			for pulse = 0, 2 do
				local dir = if rib.speed > 0 then 1 else -1
				local head = (t * (0.18 + 0.12 * charge) * dir + pulse / 3 + rib.phase) % 1
				local a = math.floor(head * RIBBON_POINTS) + 1
				local seg = Path.new()
				local started = false
				for k = a, math.min(a + 7, #points) do
					if not started then
						seg:moveTo(points[k])
						started = true
					else
						seg:lineTo(points[k])
					end
				end
				st.thickness = 1.6 + 1.4 * charge
				st.feather = 3
				st.color = Color.rgba(255, 238, 200, math.floor(clamp((0.55 + 0.35 * charge) * amount * fade, 0, 1) * 255))
				renderer:drawPath(seg, st)
			end
		end
	end
	st.feather = 0
end

-- Divine fire: tiny motes born along the bow that rise, sway and fade. When
-- charged they swarm and jitter; on release they are flung away.
local function drawWisps(self: Pinaka, renderer: Renderer, amount: number)
	local f = self.fill
	local charge = clamp(self.charge, 0, 1.5)
	local release = clamp(self.release, 0, 1)
	local active = release > 0 and release < 1
	local center = spineAt(self, 0.5)
	local push = if active then (1 - (1 - release) ^ 3) * 260 else 0
	local pushFade = if active then 1 - release else 1
	for _, w in self.wisps do
		local k = w.age / w.life
		local base = spineAt(self, w.t)
		local jitter = charge * 7
		local x = base.x + w.drift * k + math.sin(self.time * 2 + w.t * 20) * 6 * k + math.sin(self.time * 23 + w.t * 90) * jitter
		local y = base.y - w.rise * k * (1.6 + 1.2 * charge) + w.side * 4 + math.cos(self.time * 19 + w.t * 70) * jitter
		if push > 0 then
			local dx, dy = x - center.x, y - center.y
			local d = math.max(math.sqrt(dx * dx + dy * dy), 1)
			x += dx / d * push * (0.6 + w.t * 0.8)
			y += dy / d * push * (0.6 + w.t * 0.8)
		end
		local r = w.size * (1 - k * 0.5) * (1 + 0.5 * charge)
		local alpha = math.sin(k * math.pi) * (0.8 + 0.2 * charge) * amount * pushFade
		local blob = Path.new()
		addCircle(blob, x, y, r)
		local core = Color.rgb(255, 226, 160)
		f.color = Color.rgba(
			math.floor((Color.red(core) :: number) * (1 - k) + (Color.red(self.auraNow) :: number) * k),
			math.floor((Color.green(core) :: number) * (1 - k) + (Color.green(self.auraNow) :: number) * k),
			math.floor((Color.blue(core) :: number) * (1 - k) + (Color.blue(self.auraNow) :: number) * k),
			math.floor(clamp(alpha, 0, 1) * 255)
		)
		f.feather = r * 1.2
		renderer:drawPath(blob, f)
	end
	f.feather = 0
end

local function drawSparks(self: Pinaka, renderer: Renderer, amount: number)
	local f = self.fill
	local charge = clamp(self.charge, 0, 1.5)
	for _, sp in self.sparks do
		local base = spineAt(self, sp.x)
		local tw = math.max(0, math.sin(self.time * sp.speed * (1 + 2 * charge) + sp.phase))
		if tw > 0.05 then
			local x = base.x + math.cos(sp.phase * 3) * 26 * sp.y
			local y = base.y + math.sin(sp.phase * 5) * 30 * sp.y - 6
			local glow = Path.new()
			addCircle(glow, x, y, sp.r * 3)
			f.color = rgba(self.auraNow, tw * 0.35 * amount)
			f.feather = sp.r * 3
			renderer:drawPath(glow, f)
			local core = Path.new()
			addCircle(core, x, y, sp.r * tw)
			f.color = Color.rgba(255, 246, 222, math.floor(clamp(tw * amount, 0, 1) * 255))
			f.feather = 0
			renderer:drawPath(core, f)
		end
	end
end

-- On release: rings of light expanding from the bow in all three planes
-- (XY, XZ, YZ), wavy like the aura, fading as they grow.
-- Three mutually perpendicular rings (XY, XZ, YZ), tipped together like a
-- gyroscope so none is seen edge-on from the front.
local function tip(v: { number }): { number }
	local ax, ay = 0.55, 0.7
	local x, y, z = v[1], v[2], v[3]
	y, z = y * math.cos(ax) - z * math.sin(ax), y * math.sin(ax) + z * math.cos(ax)
	x, z = x * math.cos(ay) + z * math.sin(ay), -x * math.sin(ay) + z * math.cos(ay)
	return { x, y, z }
end
local PLANES = {
	{ tip({ 1, 0, 0 }), tip({ 0, 1, 0 }) },
	{ tip({ 1, 0, 0 }), tip({ 0, 0, 1 }) },
	{ tip({ 0, 1, 0 }), tip({ 0, 0, 1 }) },
}

local function drawRipple(self: Pinaka, renderer: Renderer, amount: number)
	local release = clamp(self.release, 0, 1)
	if release <= 0 or release >= 1 then
		return
	end
	local c = self.center
	local o = self.model:transformPoint(c[1], c[2], c[3])
	local grow = 1 - (1 - release) ^ 2.4
	local st = self.stroke
	st.cap = 'round'
	st.join = 'round'
	for ring = 0, 1 do
		local radius = (0.15 + 2.6 * grow) * (1 - 0.28 * ring)
		local alpha = (1 - release) ^ 1.4 * (if ring == 0 then 0.85 else 0.5) * amount
		for pi, pl in PLANES do
			local a, b = pl[1], pl[2]
			local path = Path.new()
			local started = false
			for k = 0, 96 do
				local th = k / 96 * math.pi * 2
				local wobble = 1 + 0.025 * math.sin(th * 11 + self.time * 9 + pi * 2)
				local cr, sr = math.cos(th) * radius * wobble, math.sin(th) * radius * wobble
				local p = project(self, o.x + a[1] * cr + b[1] * sr, o.y + a[2] * cr + b[2] * sr, o.z + a[3] * cr + b[3] * sr)
				if p then
					if not started then
						path:moveTo(p)
						started = true
					else
						path:lineTo(p)
					end
				else
					started = false
				end
			end
			st.thickness = 10 * (1 - release) + 2
			st.feather = 14
			st.color = rgba(self.auraNow, alpha * 0.8)
			renderer:drawPath(path, st)
			st.thickness = 2.2 * (1 - release) + 0.8
			st.feather = 2
			st.color = Color.rgba(255, 240, 210, math.floor(clamp(alpha, 0, 1) * 255))
			renderer:drawPath(path, st)
		end
	end
	st.feather = 0
end

-- On release: motes thrown off the bow in every direction in 3D, nearer
-- ones larger, fading as they fly.
local function drawBurst(self: Pinaka, renderer: Renderer, amount: number)
	local release = clamp(self.release, 0, 1)
	if release <= 0 or release >= 1 or #self.spine == 0 then
		return
	end
	local f = self.fill
	local fly = 1 - (1 - release) ^ 2.2
	local fade = (1 - release) ^ 1.2
	for _, b in self.burst do
		local i = math.floor(b.t * (#self.spine - 1)) + 1
		local sp = self.spine[i]
		local o = self.model:transformPoint(sp[1], sp[2], sp[3])
		local d = b.speed * fly
		local p, near = project(self, o.x + b.dx * d, o.y + b.dy * d, o.z + b.dz * d)
		if p then
			local r = b.r * near * (1 - 0.4 * release)
			local tw = 0.7 + 0.3 * math.sin(self.time * 20 + b.phase)
			local glow = Path.new()
			addCircle(glow, p.x, p.y, r * 3)
			f.color = rgba(self.auraNow, 0.45 * fade * tw * amount)
			f.feather = r * 3
			renderer:drawPath(glow, f)
			local core = Path.new()
			addCircle(core, p.x, p.y, r)
			f.color = Color.rgba(255, 244, 214, math.floor(clamp(fade * tw * amount, 0, 1) * 255))
			f.feather = 0
			renderer:drawPath(core, f)
		end
	end
end

---------------------------------------------------------------------------
-- The arrow's light

local function lighten(c: Color, k: number, alpha: number): Color
	local r, g, b = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return Color.rgba(
		math.floor(r + (255 - r) * k),
		math.floor(g + (255 - g) * k),
		math.floor(b + (255 - b) * k),
		math.floor(255 * clamp(alpha, 0, 1))
	)
end

local function arrowFormed(self: Pinaka): number
	return if self.showArrow then 1 else clamp(self.arrow, 0, 1)
end

-- A helix of light winding round the shaft, two strands half a turn apart;
-- the half of each turn nearer us is drawn in front of the arrow. Brighter
-- and faster as the bow charges and in flight; in flight a trail streams
-- back from the nock.
local function drawArrowLight(self: Pinaka, renderer: Renderer, front: boolean)
	if not self.arrowVisible then
		return
	end
	local a, b = self.arrowNockS, self.arrowTipS
	local dx, dy = b.x - a.x, b.y - a.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then
		return
	end
	local formed = arrowFormed(self)
	local f = clamp(self.flight, 0, 1)
	local charge = clamp(self.charge, 0, 1.5)
	local strength = formed * (0.4 + 0.6 * math.max(charge, f))
	local col = self.arrowColor
	local st = self.stroke
	st.cap = 'round'
	st.join = 'round'
	local px, py = -dy / len, dx / len
	local ux, uy = dx / len, dy / len
	local zoom = math.max(self.zoom, 0.05)

	if not front and f > 0.01 then
		-- The comet tail: a wide soft glow and a hot core, streaming back
		-- from the whole arrow, longest right after the launch.
		local tl = len * (1.1 + 0.9 * f)
		local fl = self.fill
		for layer = 1, 2 do
			local w = (if layer == 1 then 40 else 9) * zoom
			local alpha = (if layer == 1 then 0.45 else 0.75) * f * formed
			local from = Vector.xy(a.x + ux * len * 0.55, a.y + uy * len * 0.55)
			local to = Vector.xy(a.x - ux * tl, a.y - uy * tl)
			fl.gradient = Gradient.linear(from, to, {
				{ position = 0, color = rgba(col, 0) },
				{ position = 0.25, color = lighten(col, if layer == 2 then 0.5 else 0, alpha) },
				{ position = 1, color = rgba(col, 0) },
			})
			local trail = Path.new()
			trail:moveTo(from)
			trail:lineTo(Vector.xy(a.x + px * w, a.y + py * w))
			trail:lineTo(to)
			trail:lineTo(Vector.xy(a.x - px * w, a.y - py * w))
			trail:close()
			fl.feather = w
			renderer:drawPath(trail, fl)
		end
		fl.feather = 0
		fl.gradient = nil
		-- Sparks shed off the tail, falling behind it as it flies.
		for i = 1, 46 do
			local life = 0.7 + 0.6 * ((i * 0.618) % 1)
			local age = (self.time / life + (i * 0.371) % 1) % 1
			local back = age * tl * 1.1
			local spread = (((i * 0.791) % 1) - 0.5) * 2 * (6 + 34 * age) * zoom
			local x = a.x - ux * back + px * spread
			local y = a.y - uy * back + py * spread
			local r = (1 + 2.2 * ((i * 0.433) % 1)) * zoom * (1 - age * 0.6)
			fl.color = lighten(col, 0.6, f * formed * (1 - age) * 0.9)
			local dot = Path.new()
			addCircle(dot, x, y, r)
			renderer:drawPath(dot, fl)
		end
	end

	if strength < 0.01 then
		return
	end
	local radius = (7 + 5 * charge + 5 * f) * zoom
	local turns = 4.5
	local spin = self.time * (6 + 12 * f)
	local N = 56
	for strand = 0, 1 do
		for k = 0, N - 1 do
			local u0, u1 = k / N, (k + 1) / N
			if u1 <= formed then
				local ph0 = u0 * turns * math.pi * 2 - spin + strand * math.pi
				local ph1 = u1 * turns * math.pi * 2 - spin + strand * math.pi
				local depth = math.cos((ph0 + ph1) / 2)
				if (depth > 0) == front then
					local env0 = math.sin(math.pi * u0) ^ 0.6
					local env1 = math.sin(math.pi * u1) ^ 0.6
					local r0, r1 = radius * env0 * math.sin(ph0), radius * env1 * math.sin(ph1)
					local path = Path.new()
					path:moveTo(Vector.xy(a.x + dx * u0 + px * r0, a.y + dy * u0 + py * r0))
					path:lineTo(Vector.xy(a.x + dx * u1 + px * r1, a.y + dy * u1 + py * r1))
					local alpha = strength * (env0 + env1) * 0.5 * (0.35 + 0.65 * math.abs(depth))
					st.thickness = 5 * zoom
					st.color = rgba(col, alpha * 0.3)
					renderer:drawPath(path, st)
					st.thickness = 1.5 * zoom
					st.color = lighten(col, 0.55, alpha)
					renderer:drawPath(path, st)
				end
			end
		end
	end
end

-- The glowing tip: a halo, a slowly turning star of rays and a white-hot
-- core, once the arrow has formed. Hotter as the bow charges and in flight.
local function drawTipGlow(self: Pinaka, renderer: Renderer)
	if not self.arrowVisible then
		return
	end
	local formed = arrowFormed(self)
	-- Fades in as the arrow finishes forming; in flight it fades with it.
	local on = if self.flight > 0.5 then formed else clamp((formed - 0.85) / 0.15, 0, 1)
	if on <= 0 then
		return
	end
	local f = clamp(self.flight, 0, 1)
	local charge = clamp(self.charge, 0, 1.5)
	local pulse = 0.85 + 0.15 * math.sin(self.time * 7)
	local k = on * (0.6 + 0.4 * charge + 0.5 * f) * pulse
	local tip = self.arrowTipS
	local col = self.arrowColor
	local zoom = math.max(self.zoom, 0.05)
	local fl = self.fill

	local radius = (40 + 16 * charge + 60 * f) * zoom * pulse
	fl.gradient = Gradient.radial(tip, radius, {
		{ position = 0, color = lighten(col, 0.75, k) },
		{ position = 0.22, color = rgba(col, k * 0.6) },
		{ position = 1, color = rgba(col, 0) },
	})
	local halo = Path.new()
	addCircle(halo, tip.x, tip.y, radius)
	renderer:drawPath(halo, fl)

	for i = 0, 7 do
		local ang = i * math.pi / 4 + self.time * 0.5
		local long = i % 2 == 0
		local l = (if long then 74 + 60 * f else 34 + 24 * f) * zoom * (0.8 + 0.4 * k)
		local w = (if long then 3.2 else 2.2) * zoom
		local cs, sn = math.cos(ang), math.sin(ang)
		local ex, ey = tip.x + cs * l, tip.y + sn * l
		fl.gradient = Gradient.linear(tip, Vector.xy(ex, ey), {
			{ position = 0, color = lighten(col, 0.85, k) },
			{ position = 1, color = rgba(col, 0) },
		})
		local ray = Path.new()
		ray:moveTo(Vector.xy(tip.x - sn * w, tip.y + cs * w))
		ray:lineTo(Vector.xy(ex, ey))
		ray:lineTo(Vector.xy(tip.x + sn * w, tip.y - cs * w))
		ray:close()
		renderer:drawPath(ray, fl)
	end
	fl.gradient = nil

	-- Aloft: a wide anamorphic flare across the tip, breathing slowly.
	if f > 0.01 then
		local fw = (220 + 60 * math.sin(self.time * 1.7)) * zoom * f
		local fh = 2.2 * zoom
		for side = -1, 1, 2 do
			fl.gradient = Gradient.linear(tip, Vector.xy(tip.x + side * fw, tip.y), {
				{ position = 0, color = lighten(col, 0.8, k * 0.9) },
				{ position = 0.3, color = rgba(col, k * 0.35) },
				{ position = 1, color = rgba(col, 0) },
			})
			local flare = Path.new()
			flare:moveTo(Vector.xy(tip.x, tip.y - fh))
			flare:lineTo(Vector.xy(tip.x + side * fw, tip.y))
			flare:lineTo(Vector.xy(tip.x, tip.y + fh))
			flare:close()
			fl.feather = 3 * zoom
			renderer:drawPath(flare, fl)
		end
		fl.feather = 0
		fl.gradient = nil
	end

	fl.color = Color.rgba(255, 255, 255, math.floor(255 * clamp(k, 0, 1)))
	local core = Path.new()
	addCircle(core, tip.x, tip.y, 4.5 * zoom)
	renderer:drawPath(core, fl)
end

---------------------------------------------------------------------------
-- The astras' auras, in place of the waves (`auraStyle` 1-3)

local TAU = math.pi * 2

-- Repeatable noise in 0..1 for a seed.
local function hash01(n: number): number
	local x = math.sin(n * 127.1 + 311.7) * 43758.5453
	return x - math.floor(x)
end

-- A colour pulled toward an rgb by k, at alpha.
local function mixColor(c: Color, r: number, g: number, b: number, k: number, alpha: number): Color
	local cr, cg, cb = Color.red(c) :: number, Color.green(c) :: number, Color.blue(c) :: number
	return Color.rgba(
		math.floor(cr + (r - cr) * k),
		math.floor(cg + (g - cg) * k),
		math.floor(cb + (b - cb) * k),
		math.floor(255 * clamp(alpha, 0, 1))
	)
end

-- Where an aura particle lives: `u` (0..1) along the bow's spine, or along
-- the arrow's shaft when `onArrow` and the arrow is out. The point and the
-- unit normal there, on screen.
local function anchor(self: Pinaka, u: number, onArrow: boolean): (Vector, Vector)
	if onArrow and self.arrowVisible then
		local a, b = self.arrowNockS, self.arrowTipS
		local dx, dy = b.x - a.x, b.y - a.y
		local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-3)
		return Vector.xy(a.x + dx * u, a.y + dy * u), Vector.xy(-dy / len, dx / len)
	end
	return spineAt(self, u), spineNormal(self, u)
end

-- How strong an astra's aura is: it builds as the bow charges; on the
-- arrow it stays full in flight, riding with it.
local function auraStrength(self: Pinaka, amount: number, onArrow: boolean?): number
	local k = clamp(self.charge, 0, 1)
	if onArrow then
		k = math.max(k, clamp(self.flight, 0, 1))
	end
	return amount * (0.35 + 0.65 * k)
end

-- Mist (the blue astra): soft glowing fog billowing off the bow and arrow,
-- each puff swelling and drifting up as it fades, faster as it charges.
local MIST = 72
local function drawMist(self: Pinaka, renderer: Renderer, amount: number, front: boolean)
	local strength = auraStrength(self, amount, true)
	if strength < 0.01 or #self.screenSpine == 0 then
		return
	end
	local k = clamp(self.charge, 0, 1)
	local zoom = math.max(self.zoom, 0.05)
	local col = self.auraNow
	local fl = self.fill
	local t = self.time
	local onBow = auraStrength(self, amount)
	for i = 1, MIST do
		if (i % 3 == 0) == front then
			local life = 3.2 + 2.6 * hash01(i)
			local age = (t * (1 + 0.8 * k) / life + hash01(i + 7)) % 1
			local onArrow = i % 4 == 0
			local u = if onArrow then 0.08 + 0.84 * hash01(i + 13) else hash01(i + 13)
			local p, n = anchor(self, u, onArrow)
			local side = if hash01(i + 29) < 0.5 then -1 else 1
			local off = (8 + 70 * age) * side * zoom
			local x = p.x + n.x * off + math.sin(t * 0.7 + i * 1.7) * 18 * zoom
			local y = p.y + n.y * off - age * 80 * zoom
			local r = (28 + 62 * age + 22 * hash01(i + 41)) * zoom * (0.85 + 0.3 * k)
			local a = (if onArrow then strength else onBow) * math.sin(math.pi * age) * (if front then 0.2 else 0.34)
			fl.gradient = Gradient.radial(Vector.xy(x, y), r, {
				{ position = 0, color = mixColor(col, 225, 242, 255, 0.7, a) },
				{ position = 0.45, color = mixColor(col, 225, 242, 255, 0.35, a * 0.6) },
				{ position = 1, color = rgba(col, 0) },
			})
			local puff = Path.new()
			addCircle(puff, x, y, r)
			renderer:drawPath(puff, fl)
		end
	end
	fl.gradient = nil
end

-- Pollen (the green astra): fine glowing grains floating in slow loops round
-- the bow and arrow, drifting up and glinting; they swirl faster as it
-- charges.
local POLLEN = 190
local function drawPollen(self: Pinaka, renderer: Renderer, amount: number, front: boolean)
	local strength = auraStrength(self, amount, true)
	if strength < 0.01 or #self.screenSpine == 0 then
		return
	end
	local k = clamp(self.charge, 0, 1)
	local zoom = math.max(self.zoom, 0.05)
	local col = self.auraNow
	local fl = self.fill
	local t = self.time
	local swirl = 1 + 1.6 * k
	local onBow = auraStrength(self, amount)
	for i = 1, POLLEN do
		if (i % 2 == 0) == front then
			local onArrow = i % 4 == 0
			local u = if onArrow then 0.05 + 0.9 * hash01(i * 3.1) else hash01(i * 3.1)
			local p, n = anchor(self, u, onArrow)
			local ph = hash01(i + 5) * TAU
			local sp = 0.35 + 0.5 * hash01(i + 9)
			local spread = (14 + 64 * hash01(i + 17)) * zoom
			local across = (hash01(i + 21) - 0.5) * 2 * spread
			local life = 4 + 3 * hash01(i + 25)
			local age = (t / life + hash01(i + 27)) % 1
			local x = p.x + n.x * across + math.sin(t * sp * swirl + ph) * spread * 0.5
			local y = p.y + n.y * across + math.cos(t * sp * 0.8 * swirl + ph * 1.3) * spread * 0.35 - age * 55 * zoom
			local fade = math.sin(math.pi * age)
			local glint = math.max(0, math.sin(t * (2 + 3 * hash01(i + 31)) + ph)) ^ 6
			local r = (1.8 + 2.2 * hash01(i + 35)) * zoom * (0.9 + 0.2 * math.sin(t * 3 + ph))
			local a = (if onArrow then strength else onBow) * fade * (0.55 + 0.45 * glint)
			-- Halo, then the grain: green-gold, lit at the glint.
			fl.gradient = Gradient.radial(Vector.xy(x, y), r * 4.5, {
				{ position = 0, color = rgba(col, a * 0.6) },
				{ position = 1, color = rgba(col, 0) },
			})
			local halo = Path.new()
			addCircle(halo, x, y, r * 4.5)
			renderer:drawPath(halo, fl)
			fl.gradient = nil
			fl.color = mixColor(col, 255, 246, 150, 0.35 + 0.5 * glint, a)
			local grain = Path.new()
			addCircle(grain, x, y, r)
			renderer:drawPath(grain, fl)
		end
	end
end

-- A jagged bolt from a to b: midpoint displacement, rougher on longer
-- segments. Returns the points.
local function bolt(a: Vector, b: Vector, seed: number, rough: number): { Vector }
	local pts = { a, b }
	for level = 1, 5 do
		local nextPts: { Vector } = { pts[1] }
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local dx, dy = q.x - p.x, q.y - p.y
			local len = math.sqrt(dx * dx + dy * dy)
			local d = (hash01(seed + level * 17.3 + i * 3.7) - 0.5) * len * rough
			local nx, ny = -dy / math.max(len, 1e-3), dx / math.max(len, 1e-3)
			table.insert(nextPts, Vector.xy((p.x + q.x) / 2 + nx * d, (p.y + q.y) / 2 + ny * d))
			table.insert(nextPts, q)
		end
		pts = nextPts
	end
	return pts
end

local function strokeBolt(self: Pinaka, renderer: Renderer, pts: { Vector }, alpha: number, width: number)
	local path = Path.new()
	path:moveTo(pts[1])
	for i = 2, #pts do
		path:lineTo(pts[i])
	end
	local st = self.stroke
	local col = self.auraNow
	st.cap = 'round'
	st.join = 'round'
	st.thickness = 9 * width
	st.feather = 10 * width
	st.color = rgba(col, alpha * 0.45)
	renderer:drawPath(path, st)
	st.feather = 0
	st.thickness = 2.6 * width
	st.color = rgba(col, alpha * 0.8)
	renderer:drawPath(path, st)
	st.thickness = 1.1 * width
	st.color = mixColor(col, 255, 255, 255, 0.8, alpha)
	renderer:drawPath(path, st)
end

-- Lightning (the violet astra): electric arcs crackling along the bow,
-- leaping from the limbs to the arrow and forking out into the dark. They
-- re-strike many times a second, more of them as it charges.
local function drawLightning(self: Pinaka, renderer: Renderer, amount: number)
	local strength = auraStrength(self, amount, true)
	if strength < 0.01 or #self.screenSpine == 0 then
		return
	end
	-- In flight the bow is gone: the arcs crawl along the arrow instead.
	local aloft = self.arrowVisible and self.flight > 0.4
	local k = math.max(clamp(self.charge, 0, 1), if aloft then 0.7 else 0)
	local zoom = math.max(self.zoom, 0.05)
	local frame = math.floor(self.time * (12 + 10 * k))
	local count = math.floor(3 + 8 * k)
	for b = 1, count do
		local s = frame * 31.7 + b * 7.3
		if hash01(s + 0.5) < 0.8 then
			local kind = hash01(s + 1.1)
			local p0: Vector
			local p1: Vector
			if aloft then
				-- Along the arrow, or flicking off it.
				local u0 = hash01(s + 2.2)
				local a, n = anchor(self, u0, true)
				p0 = a
				if kind < 0.5 then
					p1 = anchor(self, clamp(u0 + (hash01(s + 3.3) - 0.5) * 0.6, 0, 1), true)
				else
					local side = if hash01(s + 4.4) < 0.5 then -1 else 1
					local l = (30 + 60 * hash01(s + 5.5)) * zoom
					p1 = Vector.xy(a.x + n.x * side * l, a.y + n.y * side * l + l * 0.6)
				end
			elseif kind < 0.4 or not self.arrowVisible then
				-- Along the bow, arcing between two points on it.
				local u0 = hash01(s + 2.2)
				local u1 = clamp(u0 + (hash01(s + 3.3) - 0.5) * 0.45, 0, 1)
				p0 = anchor(self, u0, false)
				p1 = anchor(self, u1, false)
			elseif kind < 0.7 then
				-- From a limb to the arrow.
				p0 = anchor(self, hash01(s + 2.2), false)
				p1 = anchor(self, 0.15 + 0.75 * hash01(s + 3.3), true)
			else
				-- Out into the dark, from the bow or the arrow.
				local onArrow = kind > 0.88
				local a, n = anchor(self, hash01(s + 2.2), onArrow)
				local side = if hash01(s + 4.4) < 0.5 then -1 else 1
				local l = (40 + 90 * hash01(s + 5.5)) * zoom
				local tx, ty = -n.y, n.x
				local slant = (hash01(s + 6.6) - 0.5) * l
				p0 = a
				p1 = Vector.xy(a.x + n.x * side * l + tx * slant, a.y + n.y * side * l + ty * slant)
			end
			local flick = 0.6 + 0.4 * hash01(s + 7.7)
			local pts = bolt(p0, p1, s, 0.42)
			strokeBolt(self, renderer, pts, strength * flick, zoom * (0.8 + 0.4 * hash01(s + 8.8)))
			-- A fork off the middle now and then.
			if hash01(s + 9.9) < 0.45 then
				local m = pts[math.floor(#pts / 2)]
				local ang = hash01(s + 10.1) * TAU
				local l = (20 + 40 * hash01(s + 11.1)) * zoom
				local fork = bolt(m, Vector.xy(m.x + math.cos(ang) * l, m.y + math.sin(ang) * l), s + 50, 0.5)
				strokeBolt(self, renderer, fork, strength * flick * 0.7, zoom * 0.6)
			end
		end
	end
end

local function blend(a: Color, b: Color, k: number): Color
	local function ch(x: number, y: number): number
		return math.floor(x + (y - x) * k + 0.5)
	end
	return Color.rgba(
		ch(Color.red(a) :: number, Color.red(b) :: number),
		ch(Color.green(a) :: number, Color.green(b) :: number),
		ch(Color.blue(a) :: number, Color.blue(b) :: number),
		ch(Color.alpha(a) :: number, Color.alpha(b) :: number)
	)
end

-- Fire (Agni, auraStyle 4): roaring, turbulent flames engulfing the bow and
-- arrow, from fire.wgsl. The bow's spine and the arrow's shaft go to the
-- shader as polylines; it builds a heat field round them that climbs in the
-- rise direction (up; back along the arrow once it flies) and breaks it up
-- with streaming noise. Rendered at 3/4 resolution, then drawn behind the
-- bow and again, fainter, in front of it, so the bow sits in the fire.
local FIRE_SCALE = 0.75

local function ensureFire(self: Pinaka): boolean
	if self.fireFailed then
		return false
	end
	if self.fireCanvas then
		return true
	end
	local context = self.context
	local shader = context and context:shader('fire')
	if context == nil or shader == nil then
		print('Pinaka: shader "fire" not found; Agni has no fire')
		self.fireFailed = true
		return false
	end
	local ok, err = pcall(function()
		local canvas = context:gpuCanvas({
			width = math.max(1, math.floor(self.width * FIRE_SCALE)),
			height = math.max(1, math.floor(self.height * FIRE_SCALE)),
		})
		local pipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_main' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = canvas.format } },
		})
		local uniforms = GPUBuffer.new({ size = 432, usage = 'uniform' })
		self.fireBindings = GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = uniforms } },
		})
		self.fireCanvas = canvas
		self.firePipeline = pipeline
		self.fireUniforms = uniforms
	end)
	if not ok then
		print('Pinaka: fire pass unavailable: ' .. tostring(err))
		self.fireFailed = true
		return false
	end
	return true
end

local function renderFire(self: Pinaka, amount: number): Image?
	if #self.screenSpine == 0 or not ensureFire(self) then
		return nil
	end
	local canvas, pipeline, uniforms, bindings = self.fireCanvas, self.firePipeline, self.fireUniforms, self.fireBindings
	if canvas == nil or pipeline == nil or uniforms == nil or bindings == nil then
		return nil
	end
	local bowW = auraStrength(self, amount)
	local arrowW = if self.arrowVisible then auraStrength(self, amount, true) else 0
	if bowW < 0.01 and arrowW < 0.01 then
		return nil
	end
	local sx, sy = canvas.width / self.width, canvas.height / self.height
	local hw, hh = self.width / 2, self.height / 2
	local f = clamp(self.flight, 0, 1)
	local k = clamp(self.charge, 0, 1)
	local zoom = math.max(self.zoom, 0.05)
	-- Up the screen; back along the arrow once it flies.
	local rx, ry = 0, -1
	if self.arrowVisible then
		local a, b = self.arrowNockS, self.arrowTipS
		local dx, dy = a.x - b.x, a.y - b.y
		local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-3)
		rx, ry = (dx / len) * f, -1 + (dy / len + 1) * f
		local rl = math.max(math.sqrt(rx * rx + ry * ry), 1e-3)
		rx, ry = rx / rl, ry / rl
	end
	local u = self.fireParams
	buffer.writef32(u, 0, canvas.width)
	buffer.writef32(u, 4, canvas.height)
	buffer.writef32(u, 8, self.time)
	buffer.writef32(u, 12, (15 + 8 * k + 6 * f) * zoom * sx)
	buffer.writef32(u, 16, rx)
	buffer.writef32(u, 20, ry)
	buffer.writef32(u, 24, 16)
	buffer.writef32(u, 28, if self.arrowVisible then 8 else 0)
	buffer.writef32(u, 32, math.min(bowW, 1.15))
	buffer.writef32(u, 36, math.min(arrowW, 1.1))
	for i = 0, 15 do
		local q = spineAt(self, i / 15)
		buffer.writef32(u, 48 + i * 16, (q.x + hw) * sx)
		buffer.writef32(u, 52 + i * 16, (q.y + hh) * sy)
	end
	if self.arrowVisible then
		local a, b = self.arrowNockS, self.arrowTipS
		local formed = arrowFormed(self)
		for i = 0, 7 do
			local t = i / 7 * formed
			buffer.writef32(u, 48 + (16 + i) * 16, (a.x + (b.x - a.x) * t + hw) * sx)
			buffer.writef32(u, 52 + (16 + i) * 16, (a.y + (b.y - a.y) * t + hh) * sy)
		end
	end
	uniforms:write(u)
	local pass = canvas:beginRenderPass({
		color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } } },
	})
	pass:setPipeline(pipeline)
	pass:setBindGroup(0, bindings)
	pass:draw(3)
	pass:finish()
	return canvas.image
end

local function drawFire(self: Pinaka, renderer: Renderer, image: Image, opacity: number)
	local canvas = self.fireCanvas
	if canvas == nil then
		return
	end
	renderer:save()
	renderer:transform(
		Mat2D.withTranslation(-self.width / 2, -self.height / 2)
			* Mat2D.withScale(self.width / canvas.width, self.height / canvas.height)
	)
	renderer:drawImage(image, self.drawSampler, 'srcOver', opacity)
	renderer:restore()
end

function draw(self: Pinaka, renderer: Renderer)
	if self.failed then
		return
	end
	local astra = clamp(self.astraFade, 0, 1)
	self.auraNow = blend(self.restAura, self.auraColor, astra)
	self.imprintNow = blend(self.restImprint, self.imprintColor, astra)
	local ok, result = pcall(render, self)
	if not ok then
		print('Pinaka: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	local charge = clamp(self.charge, 0, 1.5)
	local amount = clamp(self.aura, 0, 2) * (1 + 0.6 * clamp(self.power, 0, 1.5)) * (1 + 0.5 * charge)
	drawRadiance(self, renderer, amount)
	drawRays(self, renderer, amount)
	drawDust(self, renderer, amount * (1 - clamp(self.flight, 0, 1)))
	-- The astra's aura crossfades with the resting waves by `astraFade`.
	local style = math.floor(self.auraStyle + 0.5)
	local styled = if style > 0 then amount * astra else 0
	local waves = if style > 0 then amount * (1 - astra) else amount
	if style == 1 then
		drawMist(self, renderer, styled, false)
	elseif style == 2 then
		drawPollen(self, renderer, styled, false)
	end
	local fire: Image? = nil
	if style == 4 and styled > 0.001 then
		local fired, img = pcall(renderFire, self, styled)
		fire = if fired then img else nil
		if fire then
			drawFire(self, renderer, fire, 1)
		end
	end
	if waves > 0.001 then
		drawWaves(self, renderer, waves, false)
	end
	drawWisps(self, renderer, if style == 2 then waves else amount)
	drawArrowLight(self, renderer, false)
	if image then
		renderer:save()
		renderer:transform(
			Mat2D.withTranslation(-self.width / 2, -self.height / 2)
				* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
		)
		renderer:drawImage(image, self.drawSampler, 'srcOver', 1)
		renderer:restore()
	end
	if style == 1 then
		drawMist(self, renderer, styled, true)
	elseif style == 2 then
		drawPollen(self, renderer, styled, true)
	elseif style == 3 then
		drawLightning(self, renderer, styled)
	end
	if fire then
		drawFire(self, renderer, fire, 0.15)
	end
	if waves > 0.001 then
		drawWaves(self, renderer, waves, true)
	end
	drawArrowLight(self, renderer, true)
	drawTipGlow(self, renderer)
	drawSparks(self, renderer, amount)
	drawRipple(self, renderer, amount)
	drawBurst(self, renderer, amount)
end

return function(): Node<Pinaka>
	return {
		asset = 'pinaka',
		width = 1280,
		height = 1280,
		resolution = 1.25,
		msaa = 4,
		power = 0,
		aura = 1,
		sway = 14,
		rotationX = 0,
		rotationY = 0,
		rotationZ = 0,
		spinX = 0,
		spinY = 0,
		spinZ = 0,
		showArrow = false,
		arrow = 0,
		flight = 0,
		flightTipY = -160,
		zoom = 1,
		offsetY = 0,
		drawDepth = 1,
		arrowColor = Color.rgb(255, 190, 90),
		auraStyle = 0,
		astraFade = 1,
		restAura = Color.rgb(255, 176, 64),
		restImprint = Color.rgb(255, 210, 140),
		stretch = 0,
		charge = 0,
		release = 0,
		goldColor = Color.rgb(196, 160, 88),
		woodColor = Color.rgb(92, 38, 20),
		auraColor = Color.rgb(255, 176, 64),
		imprintColor = Color.rgb(255, 210, 140),

		context = nil,
		shader = nil,
		failed = false,
		time = 0,
		parts = {},
		spine = {},
		center = { 0, 0, 0 },
		halfLength = 1,
		gripHalf = 0.14,
		stringHalf = 0.68,
		tipFollow = 0.6,
		drawPos = 0,
		drawVel = 0,
		shift = 0,
		shiftVel = 0,
		firePipeline = nil,
		fireCanvas = nil,
		fireUniforms = nil,
		fireBindings = nil,
		fireParams = buffer.create(432),
		fireFailed = false,
		auraNow = Color.rgb(255, 176, 64),
		imprintNow = Color.rgb(255, 210, 140),
		arrowLength = ARROW_LENGTH,
		stringX = -0.17,
		roll = 0,
		arrowWorld = Mat4.identity(),
		arrowVisible = false,
		arrowNockS = Vector.xy(0, 0),
		arrowTipS = Vector.xy(0, 0),
		burst = {},
		model = Mat4.identity(),
		viewProj = Mat4.identity(),
		screenSpine = {},
		wisps = {},
		dust = {},
		sparks = {},
		canvas = nil,
		pipeline = nil,
		depthView = nil,
		msaaView = nil,
		targetW = 0,
		targetH = 0,
		targetSamples = 0,
		scratch = buffer.create(UNIFORM_SIZE),
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),
		fill = Paint.with({ style = 'fill', color = Color.rgb(255, 255, 255) }),
		stroke = Paint.with({ style = 'stroke', color = Color.rgb(255, 255, 255), thickness = 1 }),

		init = init,
		advance = advance,
		draw = draw,
	}
end
