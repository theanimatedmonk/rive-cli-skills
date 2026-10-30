-- Vikram and Vetal: the night scene. A moonlit cremation ground from the
-- Blender GLB, in Shishupalgarh's visual language: a stylized toon ramp,
-- wind through the grass and leaves, real shadows (here cast by the moon),
-- moonbeam shafts, bloom and depth of field; and for the night, mist that
-- hugs the ground and drifts in wisps, a starry sky with the moon, and
-- fireflies that wander low and blink.
--
-- Rendered in 3D on the GPU (world.wgsl), then finished in a second pass
-- (blur.wgsl, post.wgsl). The geometry is the blob `asset` (world.bin,
-- written by ../tools/export_world.py).
--
-- Camera: cameraX/Y/Z (metres, Y up), rotationX (tilt), rotationY (turn),
-- rotationZ (roll), `fov` (vertical, degrees), `drift` (a floating sway).
-- Navigation as in Blender: drag to orbit, two fingers to pan, pinch to
-- zoom, double-tap to reset; a host maps `navMode`, `zoom`, `resetView`,
-- `dragX` / `dragY`.
--
-- Moon (the "sun" inputs): `sunAzimuth`, `sunElevation`, `sunIntensity`,
-- `sunColor`; it casts shadows, `shafts` sets its beams and `lightLeak` its
-- glow on screen.
--
-- Wind: `windStrength`, `windSpeed`, `windDirection`, `gustiness`,
-- `flutter`. Air: `haze` (the mist's density), `clouds`, `bloom`, `glow`,
-- `depthOfField`, `focusDistance`, `exposure`, `grain` (film grain, 0-1;
-- 0 is none). Hills: `mountains`,
-- `mountainColor`. `moon` (0-1, keep it low) is the moonlight: its light,
-- shadows, disc and beams; 0 is amavas, the new-moon night, lit only by a
-- faint starlight and the fireflies.
--
-- Fireflies: `fireflies` (how many, up to 3000), `fireflySize` (metres),
-- `fireflySpeed`, `fireflyColor`. `heroFireflies` (0-1) is the share that
-- gather round the hero tree (the peepal, its base at heroX/Y/Z).
--
-- Ghost lights: `ghostLights` (0-16) pale will-o'-wisps circling the hero
-- tree, each trailing a fading tail and lighting what it passes in
-- `ghostColor`. `ghostsFlee` (0 or 1): when it turns on (Vikram's astra),
-- they break their orbits and flee the tree, out and up, faster and
-- faster, flickering wildly and fading into the jungle in a few seconds;
-- off, they circle again.
--
-- King Vikram (`king`: his blob's name, king.bin; empty for none) walks the
-- scene, drawn by the Hero module (Hero.luau, king.wgsl) in the same passes:
-- trees hide him, the moon casts his shadow, the mist takes him. He stands
-- on the ground at `kingX` / `kingZ`, facing the way he walks (plus
-- `kingTurn`, degrees); `kingPose` (0 idle, 1 walk, 2 draw his bow),
-- `kingSpeed`, `kingAura`, `kingAuraColor`, `kingRelease` (0-1, loosing the
-- string) and `kingBlink` as on his own page; `kingFill` is a soft warm
-- light from the camera's side, so he reads on the darkest night, and
-- `kingGlow` the warm pool of light his earrings cast round him (his bow's
-- aura adds to it when he draws). The scene's wind blows his hair and
-- cloth; `kingHairWind` and `kingClothWind` say how much each takes it.
--
-- The golden wave: `blast` (0-1) sends a ring of gold out from his bow's
-- grip (where it is when the blast starts) across `blastRange` metres,
-- lighting every surface and the mist it passes, with an afterglow behind,
-- and shoving the grass and leaves outward as it goes; `blastStrength`,
-- `blastColor`.
--
-- The Vetal (`vetal`: his blob's name, vetal.bin; empty for none) hangs
-- from the peepal's branch where he hangs in Blender, drawn by the Spirit
-- module (Spirit.luau, vetal.wgsl) in the same passes; the scene's wind
-- takes his hair and cloth. `vetalEyes` (0-4), his eyes' burning, and
-- `vetalSpirit` (0-3) with `vetalSpiritColor`, the white spirit light on
-- him and in the halo round him.
--
-- The cinematic camera: `cinematic` (0-1) blends from the free camera to
-- one that orbits a target: `camTargetX/Y/Z`, `camAngle` (degrees round it;
-- 0 looks from +Z), `camDistance`, `camHeight` (above the target);
-- `camFollow` (0-1) moves the target onto King Vikram (his chest).
-- `clearNear` (metres) clears trunks and leaves that close to the
-- cinematic camera, so it can move through the jungle.
--
-- The game: with `play` on, King Vikram is the player's. The arrows walk
-- him (`keyUp`, `keyDown`, `keyLeft`, `keyRight`: 1 held, 0 not), as seen
-- from the camera: up walks away from it, left to its left; he turns to
-- the way he walks and keeps to the path (world.bin's walkable grid),
-- sliding along its edges. The camera follows `camDistance` behind him,
-- and the keypad turns it round him and tilts it (`lookUp`, `lookDown`,
-- `lookLeft`, `lookRight`). He starts at `kingX` / `kingZ`, the camera at
-- `camAngle` round him (0 looks from +Z), facing away from it. A drag
-- (or the host's `dragX` / `dragY`: a touchpad's swipe, mouse-look) turns
-- and tilts the camera too. It keeps over the path, pulling in toward him
-- where it would go into the bushes.
-- His bow: a target circle follows the pointer, gold over the peepal's
-- wood. Space (`fire` held) draws an arrow and holds it at full draw, his
-- bow following the circle (turning to it, and pitching up or down as the
-- GLB's aim poses blend); let go, it looses (the `arrowLoose` sound), rings of gold rippling from the bow. An
-- arrow that meets the peepal's trunk or branches (world.bin's wood)
-- pierces it and stays (`arrowHit`); the rest fly on into the night and are
-- gone. A click (a tap) is the astra, with no arrow: the whole shoot, his
-- bow's golden aura and rings, the twang (`bowRelease`), and the golden
-- wave rolling out over the scene. The string is heard drawn (`bowPull`)
-- either way.
--
-- Place the node at the artboard's centre and set width/height to the
-- artboard's size.

local Hero = require('Hero')
local Spirit = require('Spirit')

export type World = {
	asset: Input<string>,
	width: Input<number>,
	height: Input<number>,
	resolution: Input<number>,
	msaa: Input<number>,
	cameraX: Input<number>,
	cameraY: Input<number>,
	cameraZ: Input<number>,
	rotationX: Input<number>,
	rotationY: Input<number>,
	rotationZ: Input<number>,
	fov: Input<number>,
	drift: Input<number>,
	sunAzimuth: Input<number>,
	sunElevation: Input<number>,
	sunIntensity: Input<number>,
	lightLeak: Input<number>,
	shafts: Input<number>,
	glory: Input<number>,
	navigation: Input<boolean>,
	navMode: Input<number>,
	zoom: Input<number>,
	resetView: Input<number>,
	dragX: Input<number>,
	dragY: Input<number>,
	windStrength: Input<number>,
	windSpeed: Input<number>,
	windDirection: Input<number>,
	gustiness: Input<number>,
	flutter: Input<number>,
	haze: Input<number>,
	clouds: Input<number>,
	bloom: Input<number>,
	glow: Input<number>,
	depthOfField: Input<number>,
	focusDistance: Input<number>,
	exposure: Input<number>,
	fireflies: Input<number>,
	fireflySize: Input<number>,
	fireflySpeed: Input<number>,
	fireflyColor: Input<Color>,
	flowerColor: Input<Color>,
	sunColor: Input<Color>,
	shadowColor: Input<Color>,
	skyColor: Input<Color>,
	skyMidColor: Input<Color>,
	mountains: Input<number>,
	mountainColor: Input<Color>,
	moon: Input<number>,
	grain: Input<number>,
	heroX: Input<number>,
	heroY: Input<number>,
	heroZ: Input<number>,
	heroFireflies: Input<number>,
	ghostLights: Input<number>,
	ghostColor: Input<Color>,
	ghostsFlee: Input<number>,
	horizonColor: Input<Color>,
	hazeColor: Input<Color>,
	king: Input<string>,
	vetal: Input<string>,
	vetalEyes: Input<number>,
	vetalSpirit: Input<number>,
	vetalSpiritColor: Input<Color>,
	kingX: Input<number>,
	kingZ: Input<number>,
	kingTurn: Input<number>,
	kingPose: Input<number>,
	kingSpeed: Input<number>,
	kingAura: Input<number>,
	kingAuraColor: Input<Color>,
	kingRelease: Input<number>,
	kingHairWind: Input<number>,
	kingClothWind: Input<number>,
	kingBlink: Input<number>,
	kingFill: Input<number>,
	kingGlow: Input<number>,
	blast: Input<number>,
	blastRange: Input<number>,
	blastStrength: Input<number>,
	blastColor: Input<Color>,
	cinematic: Input<number>,
	camTargetX: Input<number>,
	camTargetY: Input<number>,
	camTargetZ: Input<number>,
	camAngle: Input<number>,
	camDistance: Input<number>,
	camHeight: Input<number>,
	camFollow: Input<number>,
	clearNear: Input<number>,
	play: Input<boolean>,
	keyUp: Input<number>,
	keyDown: Input<number>,
	keyLeft: Input<number>,
	keyRight: Input<number>,
	lookUp: Input<number>,
	lookDown: Input<number>,
	lookLeft: Input<number>,
	lookRight: Input<number>,
	fire: Input<number>,

	context: Context?,
	-- King Vikram, when there is one: the Hero module's state, his shader,
	-- his uniforms (king.wgsl's block), and where he faces.
	hero: Hero.Hero?,
	kingShader: Shader?,
	kingUbo: GPUBuffer?,
	kingFrame: buffer,
	kingSettings: Hero.Settings,
	spirit: Spirit.Spirit?,
	vetalShader: Shader?,
	vetalUbo: GPUBuffer?,
	vetalFrame: buffer,
	vetalSettings: Spirit.Settings,
	kingFacing: number,
	lastKingX: number,
	lastKingZ: number,
	-- Where he is now: the inputs', or in the game the player's.
	kx: number,
	kz: number,
	-- The game: whether it has begun, and the camera's angle round him and
	-- tilt (degrees), turning at these speeds (degrees a second).
	gameOn: boolean,
	gameYaw: number,
	gamePitch: number,
	yawSpeed: number,
	pitchSpeed: number,
	-- How far behind him the camera is now (metres): pulled in to stay over
	-- the path, out of the bushes.
	chaseDistance: number,
	-- The peepal's wood, for arrows: a grid of cells over lo..hi (1 bark).
	wood: buffer?,
	woodDims: { number },
	woodLo: { number },
	woodHi: { number },
	-- His arrows: those in flight and those stuck in the peepal; their
	-- ribbons (rebuilt each frame) and how they are drawn.
	arrows: { Arrow },
	arrowVerts: buffer,
	arrowBuffer: GPUBuffer?,
	arrowPipeline: GPUPipeline?,
	arrowBindings: GPUBindGroup?,
	-- The target circle (node pixels from its centre), whether it is over
	-- the wood, how it kicks as he looses; the next loose (scene time), and
	-- the shot he is in (SHOT_*; from the draw to the follow-through), the
	-- last he began, the pose it has him in, whether Space is held, whether
	-- it has gone and the string been heard; the bow's and arrows' sounds.
	aimX: number,
	aimY: number,
	aimOnWood: boolean,
	aimKick: number,
	lastFire: number,
	shot: number,
	lastShot: number,
	shotPose: number,
	holding: boolean,
	loosed: boolean,
	-- Where the shot went (degrees), for him to turn to after.
	shotYaw: number,
	pulled: boolean,
	-- The golden wave the astra sends out (0-1, as `blast`; 0 when none).
	gameBlast: number,
	pullSound: AudioSource?,
	looseSound: AudioSource?,
	arrowSound: AudioSource?,
	hitSound: AudioSource?,
	reticle: Path,
	reticlePaint: Paint,
	reticleDot: Paint,
	-- Where one may walk: an N x N grid over lo..hi (x, z), 1 on the path.
	walkable: buffer?,
	walkN: number,
	walkLo: { number },
	walkHi: { number },
	-- The golden wave: where it began (latched as it starts).
	blastOn: boolean,
	blastX: number,
	blastY: number,
	blastZ: number,
	-- The ground's heights: an N x N grid over lo..hi (x, z).
	heights: buffer?,
	heightN: number,
	heightLo: { number },
	heightHi: { number },
	shader: Shader?,
	postShader: Shader?,
	blurShader: Shader?,
	failed: boolean,
	time: number,
	windPhase: number,
	draws: { Draw },
	shared: { Shared },
	visible: { Draw },
	camera: Camera,
	-- The lighting fireflies: where each wanders, how fast, and its blink.
	agents: { { number } },
	-- Navigation, on top of the camera inputs: orbit (degrees), pan (metres,
	-- moving the pivot) and zoom (times the orbit distance).
	navYaw: number,
	navPitch: number,
	navPanX: number,
	navPanY: number,
	navPanZ: number,
	navZoom: number,
	-- Easing back to the inputs after a reset (1 to 0).
	navReset: number,
	lastResetView: number,
	lastDragX: number,
	lastDragY: number,
	-- Pointers down: id -> position.
	pointers: { [number]: Vector },
	pointerCount: number,
	lastTapTime: number,
	lastTapPosition: Vector,
	tapMoved: number,
	skyUbo: GPUBuffer?,
	skyBindings: GPUBindGroup?,
	pollenUbo: GPUBuffer?,
	pollenBindings: GPUBindGroup?,
	pollenIds: GPUBuffer?,
	ghostIds: GPUBuffer?,
	-- When the ghost lights took flight (the scene's time), or nil.
	fleeStart: number?,
	postUbo: GPUBuffer?,
	postBindings: GPUBindGroup?,
	nearBindings: GPUBindGroup?,
	wideBindings: GPUBindGroup?,
	sceneCanvas: GPUCanvas?,
	outCanvas: GPUCanvas?,
	nearCanvas: GPUCanvas?,
	wideCanvas: GPUCanvas?,
	depthView: GPUTextureView?,
	msaaView: GPUTextureView?,
	staticPipeline: GPUPipeline?,
	instPipeline: GPUPipeline?,
	skyPipeline: GPUPipeline?,
	pollenPipeline: GPUPipeline?,
	staticShadowPipeline: GPUPipeline?,
	instShadowPipeline: GPUPipeline?,
	shadowTexture: GPUTexture?,
	shadowTarget: GPUTextureView?,
	shadowView: GPUTextureView?,
	shadowSampler: GPUSampler?,
	sunScreen: { number },
	postPipeline: GPUPipeline?,
	nearPipeline: GPUPipeline?,
	widePipeline: GPUPipeline?,
	sampler: GPUSampler?,
	targetW: number,
	targetH: number,
	targetSamples: number,
	frame: buffer,
	postParams: buffer,
	drawSampler: ImageSampler,
}

-- An object from the animation: its track (position xyz, rotation xyzw,
-- scale xyz per sample) over [t0, t1] seconds, and its shape key's weight
-- over [w0, w1]. Outside a window it holds the first or last sample.
type Track = {
	data: buffer,
	offset: number,
	samples: number,
	t0: number,
	t1: number,
	weightOffset: number,
	weightSamples: number,
	w0: number,
	w1: number,
	rest: { number },
	-- Glows gold as it is restored (pillars as they re-form, fragments in
	-- flight).
	glows: boolean,
}

-- One per material (and pipeline), shared by every draw of it; an object
-- has its own, for its pose.
type Shared = {
	material: number,
	instanced: boolean,
	track: Track?,
	-- Set each frame for an object: whether it has any size at all.
	visible: boolean,
	uniforms: GPUBuffer,
	bindings: GPUBindGroup?,
	shadowBindings: GPUBindGroup?,
}

-- An arrow: loosed from (ox, oy, oz) along (dx, dy, dz), its tip `tip`
-- metres on; it sticks where it meets the wood (`stopAt` metres, or -1).
type Arrow = {
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	tip: number,
	stopAt: number,
	stuck: boolean,
	age: number,
}

type Draw = {
	material: number,
	instanced: boolean,
	vertexBuffer: GPUBuffer,
	indexBuffer: GPUBuffer,
	indexCount: number,
	instanceBuffer: GPUBuffer?,
	instanceCount: number,
	-- Shape key deltas (objects), or the shared zero buffer.
	morphBuffer: GPUBuffer?,
	shared: Shared,
	-- Instanced draws are one tile of the meadow: a bounding sphere, and how
	-- far away they are still drawn. Sort key, set each frame.
	cx: number,
	cy: number,
	cz: number,
	radius: number,
	maxDistance: number,
	depth: number,
}

-- The camera, as last set up, for culling.
type Camera = {
	x: number, y: number, z: number,
	fx: number, fy: number, fz: number,
	rx: number, ry: number, rz: number,
	ux: number, uy: number, uz: number,
	tanX: number, tanY: number,
}

local UNIFORM_SIZE = 1568
-- Ghost lights round the hero tree: at most, and how many instances each
-- (a head and its trail; world.wgsl).
local MAX_GHOSTS = 16
local GHOST_TRAIL = 4
local GHOST_BASE = 3000
-- Fireflies that light the scene (the first motes; world.wgsl).
local FIREFLY_LIGHTS = 12
local POST_SIZE = 96
-- The sun's shadow map: its size, and how much of the world it covers (a
-- square this many metres across, centred on the ruins).
local SHADOW_SIZE = 2048
local SHADOW_SPAN = 68
local DEPTH_FORMAT: 'depth32float' = 'depth32float'
local MAX_POLLEN = 3000
-- How far each instanced material is drawn (metres); past that the haze
-- and the ground's own colour carry it.
local MAX_DISTANCE: { [number]: number } = { [10] = 70, [11] = 200, [12] = 200, [13] = 32, [14] = 26, [15] = 120, [16] = 300, [21] = 40, [22] = 30 }
-- Leaves, blades and wind reach this far past their instance positions.
local TILE_MARGIN = 0.8

-- Blob section kinds (see tools/export_anim.py): 1-8 merged static meshes,
-- by material; 40 an object of the animation.
local STATIC_MATERIAL = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [7] = 7, [8] = 8 }
local OBJECT = 40
-- The game: his walk covers this much ground a second (at speed 1), as on
-- his own page; the camera looks at this height over his feet, from this
-- tilt (degrees) to start with, between these; the keypad turns it and
-- tilts it this fast (degrees a second).
local WALK_PACE = 0.9
local CHASE_HEIGHT = 1.6
local CHASE_PITCH = 12
local PITCH_MIN, PITCH_MAX = -8, 60
local LOOK_TURN, LOOK_TILT = 110, 60
-- Dragged (or swiped, or mouse-looked through `dragX` / `dragY`), the
-- camera turns and tilts this much (degrees) a pixel.
local LOOK_PER_PX = 0.25
-- The camera comes no nearer him than this (metres), keeping to the path;
-- it looks past his right shoulder, this far to his side (metres), so what
-- he aims at is clear of him.
local CHASE_NEAR = 1.6
local CHASE_SIDE = 0.6
-- His arrows: how long (metres), how fast (metres a second), how far they
-- fly before they are lost in the night, how deep they bite into the wood,
-- and how many are kept (the oldest stuck one goes first). Each is drawn as
-- 15 vertices of 16 bytes. His shoot plays this much faster than authored
-- in the game, and the arrow's draw this much faster; he can walk off this
-- long after he looses.
local ARROW_LENGTH = 0.95
local ARROW_SPEED = 30
local ARROW_RANGE = 70
local ARROW_EMBED = 0.2
local SHOOT_SPEED = 1.5
local DRAW_SPEED = 1.6
-- At full draw his bow aims this far (degrees) from where he faces (the
-- shoot and the arrow's hold both stand him side-on, the shoot more); he
-- faces that far off the circle so the bow is on it.
local BOW_OFFSET = -34
local ARROW_OFFSET = -19
-- The shots: none, an arrow (Space), the astra (a click).
local SHOT_NONE, SHOT_ARROW, SHOT_ASTRA = 0, 1, 2
-- The astra's golden wave crosses the scene in this long (seconds).
local BLAST_TIME = 5
local FOLLOW_THROUGH = 0.35
local MAX_ARROWS = 24
local ARROW_VERTS = 15
local ARROW_STRIDE = 16
-- The WorldToGlory animation's length: `glory` 1 is its end.
local DURATION = 10
local ENTRY = 192
-- Enough zeros to stand in for the shape key of any static chunk.
local MAX_VERTICES = 65536
local MORPH_STRIDE = 16
-- Instance kind -> material drawn (ruins.wgsl), template kind.
-- 30 bushes and 32 tree crowns are soft clumps, with leaves over them (35,
-- 36); 31 the ivy; 33 grass; 34 pink flowers; 37 sunflowers, 38 daisies.
local INSTANCE_MATERIAL = { [30] = 15, [31] = 11, [32] = 16, [33] = 13, [34] = 14, [35] = 10, [36] = 12, [37] = 21, [38] = 22 }

-- Colour ramps for the instanced kinds (linear): dark, mid, light.
-- Each plant's family of greens (linear): dark, mid, light. Jade ivy,
-- emerald bush leaves over deep forest-teal cores, olive-sage crowns and
-- warm chartreuse grass; ruins.wgsl drifts them all warmer or cooler.
local RAMPS: { [number]: { { number } } } = {
	-- Leaves at night: deep greens that only the fireflies bring up.
	[10] = { { 0.008, 0.03, 0.016 }, { 0.025, 0.08, 0.04 }, { 0.07, 0.15, 0.08 } },
	[11] = { { 0.02, 0.12, 0.07 }, { 0.07, 0.3, 0.16 }, { 0.24, 0.5, 0.3 } },
	[12] = { { 0.1, 0.18, 0.06 }, { 0.28, 0.4, 0.14 }, { 0.52, 0.6, 0.26 } },
	-- Dry grass: dark olive at the root to straw at the tips.
	[13] = { { 0.05, 0.07, 0.03 }, { 0.18, 0.2, 0.07 }, { 0.42, 0.4, 0.17 } },
	[15] = { { 0.02, 0.1, 0.05 }, { 0.08, 0.26, 0.1 }, { 0.22, 0.44, 0.16 } },
	[16] = { { 0.06, 0.14, 0.05 }, { 0.2, 0.34, 0.12 }, { 0.44, 0.54, 0.22 } },
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

-- A GPU buffer from a slice of the blob, padded to a multiple of 4 bytes.
local function slice(data: buffer, offset: number, length: number, usage: 'vertex' | 'index'): GPUBuffer
	local size = math.max(4, math.ceil(length / 4) * 4)
	local bytes = buffer.create(size)
	buffer.copy(bytes, 0, data, offset, length)
	return GPUBuffer.new({ size = size, usage = usage, data = bytes, immutable = true })
end

local function load(self: World): boolean
	local context = self.context
	assert(context)
	local blob = context:blob(self.asset)
	if blob == nil then
		print(`World: no blob asset named '{self.asset}'`)
		return false
	end
	local data = blob.data
	if buffer.len(data) < 12 or buffer.readstring(data, 0, 4) ~= 'SHRN' then
		print('World: the blob is not a world.bin')
		return false
	end
	local count = buffer.readu32(data, 8)
	local templates: { [number]: { vb: GPUBuffer, ib: GPUBuffer, indexCount: number } } = {}
	local sections = {}
	for i = 0, count - 1 do
		local o = 12 + i * ENTRY
		local function u32(word: number): number
			return buffer.readu32(data, o + word * 4)
		end
		local function f32(word: number): number
			return buffer.readf32(data, o + word * 4)
		end
		local lx, ly, lz, hx, hy, hz = f32(8), f32(9), f32(10), f32(11), f32(12), f32(13)
		local rest = table.create(10, 0)
		for k = 1, 10 do
			rest[k] = f32(23 + k)
		end
		table.insert(sections, {
			kind = u32(0),
			count = u32(1),
			indexCount = u32(2),
			vbOffset = u32(3),
			vbLength = u32(4),
			ibOffset = u32(5),
			ibLength = u32(6),
			material = u32(7),
			cx = (lx + hx) / 2,
			cy = (ly + hy) / 2,
			cz = (lz + hz) / 2,
			radius = math.sqrt((hx - lx) ^ 2 + (hy - ly) ^ 2 + (hz - lz) ^ 2) / 2 + TILE_MARGIN,
			morphOffset = u32(14),
			morphLength = u32(15),
			track = {
				data = data,
				offset = u32(16),
				samples = u32(17),
				t0 = f32(18),
				t1 = f32(19),
				weightOffset = u32(20),
				weightSamples = u32(21),
				w0 = f32(22),
				w1 = f32(23),
				rest = rest,
				glows = u32(34) == 1,
			},
		})
	end
	local function shared(material: number, instanced: boolean): Shared
		for _, sh in self.shared do
			if sh.material == material and sh.instanced == instanced and sh.track == nil then
				return sh
			end
		end
		local sh: Shared = {
			material = material,
			instanced = instanced,
			track = nil,
			visible = true,
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
			shadowBindings = nil,
		}
		table.insert(self.shared, sh)
		return sh
	end
	local function own(material: number, track: Track): Shared
		local sh: Shared = {
			material = material,
			instanced = false,
			track = track,
			visible = true,
			uniforms = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' }),
			bindings = nil,
			shadowBindings = nil,
		}
		table.insert(self.shared, sh)
		return sh
	end
	local zeros = GPUBuffer.new({
		size = MAX_VERTICES * MORPH_STRIDE,
		usage = 'vertex',
		data = buffer.create(MAX_VERTICES * MORPH_STRIDE),
		immutable = true,
	})
	for i, s in sections do
		if s.kind == 50 and s.count > 1 then
			-- The ground's heights (kind 50): an N x N grid.
			local o = 12 + (i - 1) * ENTRY
			local grid = buffer.create(s.vbLength)
			buffer.copy(grid, 0, data, s.vbOffset, s.vbLength)
			self.heights = grid
			self.heightN = s.count
			self.heightLo = { buffer.readf32(data, o + 32), buffer.readf32(data, o + 40) }
			self.heightHi = { buffer.readf32(data, o + 44), buffer.readf32(data, o + 52) }
		elseif s.kind == 51 and s.count > 1 then
			-- Where one may walk (kind 51): an N x N grid, as the heights.
			local o = 12 + (i - 1) * ENTRY
			local grid = buffer.create(s.vbLength)
			buffer.copy(grid, 0, data, s.vbOffset, s.vbLength)
			self.walkable = grid
			self.walkN = s.count
			self.walkLo = { buffer.readf32(data, o + 32), buffer.readf32(data, o + 40) }
			self.walkHi = { buffer.readf32(data, o + 44), buffer.readf32(data, o + 52) }
		elseif s.kind == 52 and s.vbLength > 12 then
			-- The peepal's wood (kind 52): its grid's size, then a byte a cell.
			local o = 12 + (i - 1) * ENTRY
			self.woodDims = { buffer.readu32(data, s.vbOffset), buffer.readu32(data, s.vbOffset + 4), buffer.readu32(data, s.vbOffset + 8) }
			local grid = buffer.create(s.vbLength - 12)
			buffer.copy(grid, 0, data, s.vbOffset + 12, s.vbLength - 12)
			self.wood = grid
			self.woodLo = { buffer.readf32(data, o + 32), buffer.readf32(data, o + 36), buffer.readf32(data, o + 40) }
			self.woodHi = { buffer.readf32(data, o + 44), buffer.readf32(data, o + 48), buffer.readf32(data, o + 52) }
		end
	end
	for _, s in sections do
		if s.kind >= 20 and s.kind < 30 then
			templates[s.kind] = {
				vb = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				ib = slice(data, s.ibOffset, s.ibLength, 'index'),
				indexCount = s.indexCount,
			}
		end
	end
	for _, s in sections do
		local material = if s.kind == OBJECT then s.material else STATIC_MATERIAL[s.kind]
		if material then
			table.insert(self.draws, {
				material = material,
				instanced = false,
				vertexBuffer = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				indexBuffer = slice(data, s.ibOffset, s.ibLength, 'index'),
				indexCount = s.indexCount,
				instanceBuffer = nil,
				instanceCount = 0,
				morphBuffer = if s.morphLength > 0 then slice(data, s.morphOffset, s.morphLength, 'vertex') else zeros,
				-- An object that moves, morphs or glows has its own uniforms; the
				-- rest share their material's.
				shared = if s.kind == OBJECT and (s.track.samples > 0 or s.track.weightSamples > 0 or s.track.glows)
					then own(material, s.track)
					else shared(material, false),
				cx = 0,
				cy = 0,
				cz = 0,
				radius = math.huge,
				maxDistance = math.huge,
				depth = 0,
			})
		end
	end
	for _, s in sections do
		local material = INSTANCE_MATERIAL[s.kind]
		-- For instances, indexCount holds the template's kind.
		local template = templates[s.indexCount]
		if material and template and s.count > 0 then
			table.insert(self.draws, {
				material = material,
				instanced = true,
				vertexBuffer = template.vb,
				indexBuffer = template.ib,
				indexCount = template.indexCount,
				instanceBuffer = slice(data, s.vbOffset, s.vbLength, 'vertex'),
				instanceCount = s.count,
				morphBuffer = nil,
				shared = shared(material, true),
				cx = s.cx,
				cy = s.cy,
				cz = s.cz,
				radius = s.radius,
				maxDistance = MAX_DISTANCE[material] or math.huge,
				depth = 0,
			})
		end
	end
	self.arrowBuffer = GPUBuffer.new({ size = (MAX_ARROWS + 1) * ARROW_VERTS * ARROW_STRIDE, usage = 'vertex' })
	self.skyUbo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.pollenUbo = GPUBuffer.new({ size = UNIFORM_SIZE, usage = 'uniform' })
	self.postUbo = GPUBuffer.new({ size = POST_SIZE, usage = 'uniform' })
	local ids = buffer.create(MAX_POLLEN * 4)
	for i = 0, MAX_POLLEN - 1 do
		buffer.writef32(ids, i * 4, i)
	end
	self.pollenIds = GPUBuffer.new({ size = MAX_POLLEN * 4, usage = 'vertex', data = ids, immutable = true })
	local gids = buffer.create(MAX_GHOSTS * GHOST_TRAIL * 4)
	for i = 0, MAX_GHOSTS * GHOST_TRAIL - 1 do
		buffer.writef32(gids, i * 4, GHOST_BASE + i)
	end
	self.ghostIds = GPUBuffer.new({ size = MAX_GHOSTS * GHOST_TRAIL * 4, usage = 'vertex', data = gids, immutable = true })
	self.sampler = GPUSampler.new({ min = 'linear', mag = 'linear', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	local shadow = GPUTexture.new({ width = SHADOW_SIZE, height = SHADOW_SIZE, format = DEPTH_FORMAT, renderTarget = true, label = 'sun shadow' })
	self.shadowTexture = shadow
	self.shadowTarget = shadow:view()
	self.shadowView = shadow:view({ aspect = 'depth-only' })
	self.shadowSampler = GPUSampler.new({ min = 'linear', mag = 'linear', compare = 'less-equal', wrapU = 'clamp-to-edge', wrapV = 'clamp-to-edge' })
	return #self.draws > 0
end

function init(self: World, context: Context): boolean
	self.context = context
	self.pullSound = context:audio('bowPull')
	self.looseSound = context:audio('bowRelease')
	self.arrowSound = context:audio('arrowLoose')
	self.hitSound = context:audio('arrowHit')
	self.shader = context:shader('world')
	self.postShader = context:shader('post')
	self.blurShader = context:shader('blur')
	if self.shader == nil or self.postShader == nil or self.blurShader == nil then
		print('World: shaders "world", "blur" and "post" are needed')
		self.failed = true
		return true
	end
	local ok, err = pcall(function()
		if not load(self) then
			self.failed = true
		end
	end)
	if not ok then
		print('World: setup failed: ' .. tostring(err))
		self.failed = true
	end
	-- King Vikram, when the scene has him.
	if self.king ~= '' and not self.failed then
		self.kingShader = context:shader('king')
		local hero, herr = Hero.load(context, self.king)
		if hero == nil or self.kingShader == nil then
			print('World: King Vikram is missing: ' .. tostring(herr or 'no "king" shader'))
		else
			self.hero = hero
			self.kingUbo = GPUBuffer.new({ size = Hero.UNIFORM_SIZE, usage = 'uniform' })
			self.lastKingX, self.lastKingZ = self.kingX, self.kingZ
			self.kx, self.kz = self.kingX, self.kingZ
		end
	end
	-- The Vetal, when the scene has him.
	if self.vetal ~= '' and not self.failed then
		self.vetalShader = context:shader('vetal')
		local spirit, verr = Spirit.load(context, self.vetal)
		if spirit == nil or self.vetalShader == nil then
			print('World: the Vetal is missing: ' .. tostring(verr or 'no "vetal" shader'))
		else
			self.spirit = spirit
			self.vetalUbo = GPUBuffer.new({ size = Spirit.UNIFORM_SIZE, usage = 'uniform' })
		end
	end
	return true
end

-- The ground's height at (x, z), from the grid (0 off it, or with none).
local function groundAt(self: World, x: number, z: number): number
	local grid = self.heights
	if grid == nil then
		return 0
	end
	local n = self.heightN
	local lo, hi = self.heightLo, self.heightHi
	local fx = clamp((x - lo[1]) / math.max(hi[1] - lo[1], 1e-3), 0, 1) * (n - 1)
	local fz = clamp((z - lo[2]) / math.max(hi[2] - lo[2], 1e-3), 0, 1) * (n - 1)
	local ix, iz = math.min(math.floor(fx), n - 2), math.min(math.floor(fz), n - 2)
	local kx, kz = fx - ix, fz - iz
	local function at(i: number, k: number): number
		return buffer.readf32(grid, ((iz + k) * n + ix + i) * 4)
	end
	local a = at(0, 0) + (at(1, 0) - at(0, 0)) * kx
	local b = at(0, 1) + (at(1, 1) - at(0, 1)) * kx
	return a + (b - a) * kz
end

-- Whether (x, z) is on the path (anywhere, with no grid; nowhere off it).
local function onPath(self: World, x: number, z: number): boolean
	local grid = self.walkable
	if grid == nil then
		return true
	end
	local n = self.walkN
	local lo, hi = self.walkLo, self.walkHi
	local fx = (x - lo[1]) / math.max(hi[1] - lo[1], 1e-3) * (n - 1)
	local fz = (z - lo[2]) / math.max(hi[2] - lo[2], 1e-3) * (n - 1)
	if fx < 0 or fz < 0 or fx > n - 1 or fz > n - 1 then
		return false
	end
	local ix, iz = math.min(math.floor(fx), n - 2), math.min(math.floor(fz), n - 2)
	local kx, kz = fx - ix, fz - iz
	local function at(i: number, k: number): number
		return buffer.readu8(grid, (iz + k) * n + ix + i)
	end
	local a = at(0, 0) + (at(1, 0) - at(0, 0)) * kx
	local b = at(0, 1) + (at(1, 1) - at(0, 1)) * kx
	return a + (b - a) * kz > 0.5
end

-- The game begins: he stands at the inputs' spot, the camera at `camAngle`
-- round him, and he faces away from it.
local function startGame(self: World)
	self.gameOn = true
	self.kx, self.kz = self.kingX, self.kingZ
	self.gameYaw, self.gamePitch = self.camAngle, CHASE_PITCH
	self.yawSpeed, self.pitchSpeed = 0, 0
	self.kingFacing = self.camAngle + 180
	self.chaseDistance = math.max(self.camDistance, 0.5)
end

-- The camera keeps over the path: as far back as `camDistance` while the
-- ground under it is path, else no further than where it leaves it (but
-- never nearer than CHASE_NEAR); it pulls in quickly and eases back out.
local function chase(self: World, dt: number)
	local far = math.max(self.camDistance, 0.5)
	local ya, pa = math.rad(self.gameYaw), math.rad(self.gamePitch)
	local gx, gz = math.sin(ya) * math.cos(pa), math.cos(ya) * math.cos(pa)
	local want = far
	local d = CHASE_NEAR
	while d < far do
		if not onPath(self, self.kx + gx * d, self.kz + gz * d) then
			want = math.max(d - 0.25, CHASE_NEAR)
			break
		end
		d += 0.25
	end
	local rate = if want < self.chaseDistance then 12 else 2
	self.chaseDistance += (want - self.chaseDistance) * (1 - math.exp(-dt * rate))
end

-- The keys: the keypad turns and tilts the camera round him, easing in and
-- out; the arrows turn him to walk the way they point, as the camera sees
-- it. Returns his pose (0 stands, 1 walks).
local function steer(self: World, dt: number): number
	local lx = clamp(self.lookRight - self.lookLeft, -1, 1)
	local ly = clamp(self.lookUp - self.lookDown, -1, 1)
	local ease = 1 - math.exp(-dt * 10)
	self.yawSpeed += (-lx * LOOK_TURN - self.yawSpeed) * ease
	self.pitchSpeed += (-ly * LOOK_TILT - self.pitchSpeed) * ease
	self.gameYaw = (self.gameYaw + self.yawSpeed * dt) % 360
	self.gamePitch = clamp(self.gamePitch + self.pitchSpeed * dt, PITCH_MIN, PITCH_MAX)
	local mx = clamp(self.keyRight - self.keyLeft, -1, 1)
	local my = clamp(self.keyUp - self.keyDown, -1, 1)
	-- The camera's forward on the ground, and its right.
	local ya = math.rad(self.gameYaw)
	local fx, fz = -math.sin(ya), -math.cos(ya)
	local wx, wz = fx * my - fz * mx, fz * my + fx * mx
	if wx * wx + wz * wz < 0.01 then
		return 0
	end
	local want = math.deg(math.atan2(wx, wz))
	local diff = (want - self.kingFacing + 540) % 360 - 180
	self.kingFacing += diff * (1 - math.exp(-dt * 10))
	return 1
end

-- He walks the way he faces, as fast as his walk has blended in, and only
-- on the path: blocked, he slides along its edge.
local function walk(self: World, hero: Hero.Hero?, dt: number)
	local pace = WALK_PACE * clamp(self.kingSpeed, 0, 3) * (if hero then Hero.mix(hero, 1) else 1) * dt
	if pace <= 0 then
		return
	end
	local fa = math.rad(self.kingFacing)
	local x, z = self.kx, self.kz
	local nx, nz = x + math.sin(fa) * pace, z + math.cos(fa) * pace
	if onPath(self, nx, nz) then
		x, z = nx, nz
	elseif onPath(self, nx, z) then
		x = nx
	elseif onPath(self, x, nz) then
		z = nz
	end
	self.kx, self.kz = x, z
end

-- How far along a ray (from o, along a unit d) it first meets the peepal's
-- wood, within `range` metres; nil if it never does.
local function rayWood(self: World, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, range: number): number?
	local grid = self.wood
	if grid == nil then
		return nil
	end
	local lo, hi, dims = self.woodLo, self.woodHi, self.woodDims
	-- Only where the ray is inside the wood's box.
	local t0, t1 = 0, range
	local function slab(o: number, d: number, l: number, h: number)
		if math.abs(d) < 1e-6 then
			if o < l or o > h then
				t1 = -1
			end
		else
			local a, b = (l - o) / d, (h - o) / d
			t0, t1 = math.max(t0, math.min(a, b)), math.min(t1, math.max(a, b))
		end
	end
	slab(ox, dx, lo[1], hi[1])
	slab(oy, dy, lo[2], hi[2])
	slab(oz, dz, lo[3], hi[3])
	local nx, ny, nz = dims[1], dims[2], dims[3]
	local cx, cy, cz = nx / (hi[1] - lo[1]), ny / (hi[2] - lo[2]), nz / (hi[3] - lo[3])
	local t = t0
	while t <= t1 do
		local i = math.floor((ox + dx * t - lo[1]) * cx)
		local j = math.floor((oy + dy * t - lo[2]) * cy)
		local k = math.floor((oz + dz * t - lo[3]) * cz)
		if i >= 0 and j >= 0 and k >= 0 and i < nx and j < ny and k < nz and buffer.readu8(grid, (k * ny + j) * nx + i) ~= 0 then
			return t
		end
		t += 0.06
	end
	return nil
end

-- The ray from the camera through the target circle (node pixels from the
-- node's centre), as last drawn.
local function aimRay(self: World): (number, number, number)
	local cam = self.camera
	local sx = self.aimX / math.max(self.width / 2, 1) * cam.tanX
	local sy = -self.aimY / math.max(self.height / 2, 1) * cam.tanY
	local dx = cam.fx + cam.rx * sx + cam.ux * sy
	local dy = cam.fy + cam.ry * sx + cam.uy * sy
	local dz = cam.fz + cam.rz * sx + cam.uz * sy
	local l = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 1e-6)
	return dx / l, dy / l, dz / l
end

-- A point along his bow, as last drawn (king.wgsl's bow points, in the
-- uniforms Hero writes: the grip is the 7th, the nock, the string's middle
-- and its own bone, the 14th).
local GRIP, NOCK = 6, 13
local function bowPoint(self: World, k: number): (number, number, number)
	local u, o = self.kingFrame, 672 + k * 16
	return buffer.readf32(u, o), buffer.readf32(u, o + 4), buffer.readf32(u, o + 8)
end

-- The arrow on his string as he draws an arrow: its nock on the string,
-- through the grip; nil until the string is back far enough to hold it (or
-- once it has gone).
local function nockedArrow(self: World): Arrow?
	local hero = self.hero
	if not (self.shot == SHOT_ARROW and not self.loosed and hero) then
		return nil
	end
	local nx, ny, nz = bowPoint(self, NOCK)
	local gx, gy, gz = bowPoint(self, GRIP)
	local dx, dy, dz = gx - nx, gy - ny, gz - nz
	local l = math.sqrt(dx * dx + dy * dy + dz * dz)
	if l < 0.2 then
		return nil
	end
	return { ox = nx, oy = ny, oz = nz, dx = dx / l, dy = dy / l, dz = dz / l, tip = ARROW_LENGTH, stopAt = -1, stuck = false, age = 0 }
end

-- What the circle is on: the wood it meets, or a point far off.
local function aimPoint(self: World): (number, number, number)
	local cam = self.camera
	local dx, dy, dz = aimRay(self)
	local t = rayWood(self, cam.x, cam.y, cam.z, dx, dy, dz, ARROW_RANGE) or ARROW_RANGE
	return cam.x + dx * t, cam.y + dy * t, cam.z + dz * t
end

-- He begins a shot (an arrow, or the astra), unless he is in one.
local function startShot(self: World, kind: number)
	if self.shot ~= SHOT_NONE then
		return
	end
	self.shot, self.lastShot = kind, kind
	self.shotPose = if kind == SHOT_ARROW then 2 else 3
	self.loosed, self.pulled = false, false
	self.aimKick = 1
end

local function play(source: AudioSource?)
	if source then
		Audio.play(source)
	end
end

-- An arrow's string lets go: the arrow on it flies from the nock (his
-- shoulder, with no bow drawn) for what the circle is on, with its sound.
local function loose(self: World)
	local on = nockedArrow(self)
	self.loosed = true
	self.aimKick = 1
	play(self.arrowSound)
	local tx, ty, tz = aimPoint(self)
	local gx, gy, gz = self.kx, groundAt(self, self.kx, self.kz) + 1.45, self.kz
	if on then
		gx, gy, gz = on.ox, on.oy, on.oz
	end
	local ax, ay, az = tx - gx, ty - gy, tz - gz
	local l = math.max(math.sqrt(ax * ax + ay * ay + az * az), 1e-4)
	ax, ay, az = ax / l, ay / l, az / l
	self.shotYaw = math.deg(math.atan2(tx - self.kx, tz - self.kz))
	-- Where it meets the wood on its own way there, if it does.
	local hit = rayWood(self, gx, gy, gz, ax, ay, az, ARROW_RANGE)
	local arrows = self.arrows
	if #arrows >= MAX_ARROWS then
		table.remove(arrows, 1)
	end
	table.insert(arrows, {
		ox = gx,
		oy = gy,
		oz = gz,
		dx = ax,
		dy = ay,
		dz = az,
		tip = ARROW_LENGTH,
		stopAt = if hit then hit + ARROW_EMBED else -1,
		stuck = false,
		age = 0,
	})
end

-- The astra's string lets go, with no arrow: the twang, and the golden wave
-- rolls out from his bow over the whole scene.
local function looseAstra(self: World)
	local tx, _, tz = aimPoint(self)
	self.loosed = true
	self.aimKick = 1
	self.shotYaw = math.deg(math.atan2(tx - self.kx, tz - self.kz))
	play(self.looseSound)
	self.gameBlast = 0.0001
end

-- In a shot. He turns so his drawn bow is on the circle (an arrow's also
-- pitches up or down to it), the string is heard drawn, and at the clip's
-- letting-go key it goes: an arrow (drawn while Space is held, then held at
-- full draw; loosed once it is let go) or the astra (the whole shoot, on a
-- click). Once the clip has played out (or a moment after it lets go, if
-- the arrows are pressed) he is the player's again, facing where it went.
-- Returns whether he is still in it.
local function shooting(self: World, hero: Hero.Hero?, dt: number): boolean
	local arrow = self.shot == SHOT_ARROW
	local tx, ty, tz = aimPoint(self)
	local want = self.shotYaw
	if not self.loosed then
		want = math.deg(math.atan2(tx - self.kx, tz - self.kz)) - (if arrow then ARROW_OFFSET else BOW_OFFSET)
	end
	local diff = (want - self.kingFacing + 540) % 360 - 180
	self.kingFacing = (self.kingFacing + diff * (1 - math.exp(-dt * (if self.loosed then 3 else 7))) + 540) % 360 - 180
	if hero == nil then
		if arrow then
			loose(self)
		else
			looseAstra(self)
		end
		return false
	end
	-- An arrow's bow pitches to the circle (from about his shoulder).
	local by = groundAt(self, self.kx, self.kz) + 1.5
	local reach = math.sqrt((tx - self.kx) ^ 2 + (tz - self.kz) ^ 2)
	Hero.aim(hero, if arrow then math.deg(math.atan2(ty - by, math.max(reach, 0.5))) else 0)
	-- The clip he is in, and where it lets go.
	local li = if arrow then 6 else 4
	if arrow and not self.loosed then
		local drawing = hero.loops[3]
		if self.shotPose == 2 and drawing and hero.loopTimes[3] * drawing.fps >= drawing.frames - 1 then
			self.shotPose = 4
		end
		-- Let go (and drawn enough to hold an arrow), it looses.
		if not self.holding and self.shotPose ~= 5 and hero.pull > 0.8 then
			self.shotPose = 5
		end
	end
	local speed = if self.shotPose == 3 then SHOOT_SPEED elseif self.shotPose == 2 then DRAW_SPEED else 1
	Hero.advance(hero, dt, self.shotPose, speed)
	if not self.pulled and hero.pull > 0.15 then
		self.pulled = true
		play(self.pullSound)
	end
	local loop = hero.loops[li]
	if loop == nil or loop.letGo < 0 then
		if arrow then
			loose(self)
		else
			looseAstra(self)
		end
		return false
	end
	local t = if self.shotPose == li - 1 then hero.loopTimes[li] else -1
	local letGo = loop.letGo / loop.fps
	if not self.loosed and t >= letGo then
		if arrow then
			loose(self)
		else
			looseAstra(self)
		end
	end
	local moving = self.keyUp + self.keyDown + self.keyLeft + self.keyRight > 0
	return not (self.loosed and (t >= (loop.frames - 1) / loop.fps or (moving and t >= letGo + FOLLOW_THROUGH * speed)))
end

-- The arrows fly; one that reaches the wood sticks, the rest are gone once
-- they are far off or under the ground.
local function flyArrows(self: World, dt: number)
	local arrows = self.arrows
	for i = #arrows, 1, -1 do
		local a = arrows[i]
		a.age += dt
		if not a.stuck then
			a.tip += ARROW_SPEED * dt
			if a.stopAt >= 0 and a.tip >= a.stopAt then
				a.tip, a.stuck, a.age = a.stopAt, true, 0
				play(self.hitSound)
			else
				local x, y, z = a.ox + a.dx * a.tip, a.oy + a.dy * a.tip, a.oz + a.dz * a.tip
				if a.tip > ARROW_RANGE or y < groundAt(self, x, z) - 0.3 then
					table.remove(arrows, i)
				end
			end
		end
	end
end

-- The arrows' ribbons, facing the camera: the shaft, the fletching at its
-- tail and the head. Returns how many arrows were written.
local function arrowRibbons(self: World): number
	local v = self.arrowVerts
	local cam = self.camera
	local n = 0
	local function vert(x: number, y: number, z: number, r: number, g: number, b: number, glow: number)
		buffer.writef32(v, n, x)
		buffer.writef32(v, n + 4, y)
		buffer.writef32(v, n + 8, z)
		buffer.writeu8(v, n + 12, r)
		buffer.writeu8(v, n + 13, g)
		buffer.writeu8(v, n + 14, b)
		buffer.writeu8(v, n + 15, math.floor(clamp(glow, 0, 1) * 255))
		n += ARROW_STRIDE
	end
	local count = 0
	local list = self.arrows
	local on = nockedArrow(self)
	if on then
		list = table.clone(list)
		table.insert(list, on)
	end
	for _, a in list do
		local hx, hy, hz = a.ox + a.dx * a.tip, a.oy + a.dy * a.tip, a.oz + a.dz * a.tip
		local mx, my, mz = hx - a.dx * ARROW_LENGTH * 0.5, hy - a.dy * ARROW_LENGTH * 0.5, hz - a.dz * ARROW_LENGTH * 0.5
		-- Across the arrow, as the camera sees it.
		local vx, vy, vz = cam.x - mx, cam.y - my, cam.z - mz
		local sx, sy, sz = a.dy * vz - a.dz * vy, a.dz * vx - a.dx * vz, a.dx * vy - a.dy * vx
		local sl = math.max(math.sqrt(sx * sx + sy * sy + sz * sz), 1e-6)
		sx, sy, sz = sx / sl, sy / sl, sz / sl
		-- Golden in flight; stuck, the glow settles to an ember, so it can
		-- be found again in the dark.
		-- On the string it takes the bow's aura instead.
		local glow = if a == on then 0.25 elseif a.stuck then 0.6 * math.exp(-a.age * 1.5) + 0.12 else 0.9
		-- Never thinner than about two pixels, however far.
		local dist = math.sqrt(vx * vx + vy * vy + vz * vz)
		local px = 2 * cam.tanY * dist / math.max(self.targetH, 1)
		local thick = math.max(1, 2 * px / 0.016)
		local function quad(from: number, to: number, w: number, r: number, g: number, b: number, gl: number)
			local ax, ay, az = hx - a.dx * from, hy - a.dy * from, hz - a.dz * from
			local bx, by, bz = hx - a.dx * to, hy - a.dy * to, hz - a.dz * to
			local ox, oy, oz = sx * w / 2, sy * w / 2, sz * w / 2
			vert(ax - ox, ay - oy, az - oz, r, g, b, gl)
			vert(ax + ox, ay + oy, az + oz, r, g, b, gl)
			vert(bx + ox, by + oy, bz + oz, r, g, b, gl)
			vert(ax - ox, ay - oy, az - oz, r, g, b, gl)
			vert(bx + ox, by + oy, bz + oz, r, g, b, gl)
			vert(bx - ox, by - oy, bz - oz, r, g, b, gl)
		end
		-- The shaft (cane), the fletching (pale feathers) and the iron head.
		quad(0.08, ARROW_LENGTH, 0.016 * thick, 120, 84, 46, glow * 0.6)
		quad(ARROW_LENGTH - 0.17, ARROW_LENGTH - 0.02, 0.045 * thick, 225, 214, 190, glow * 0.4)
		local bx, by, bz = hx - a.dx * 0.1, hy - a.dy * 0.1, hz - a.dz * 0.1
		local hw = 0.025 * thick
		vert(hx, hy, hz, 170, 170, 180, glow)
		vert(bx + sx * hw, by + sy * hw, bz + sz * hw, 170, 170, 180, glow)
		vert(bx - sx * hw, by - sy * hw, bz - sz * hw, 170, 170, 180, glow)
		count += 1
	end
	return count
end

-- Set below, with the navigation.
local hostDrag: (self: World, dx: number, dy: number) -> () = function() end

local function startReset(self: World)
	self.navReset = 1
end

function advance(self: World, seconds: number): boolean
	if self.resetView ~= self.lastResetView then
		self.lastResetView = self.resetView
		startReset(self)
	end
	local dx, dy = self.dragX - self.lastDragX, self.dragY - self.lastDragY
	if dx ~= 0 or dy ~= 0 then
		self.lastDragX, self.lastDragY = self.dragX, self.dragY
		if self.navigation or self.play then
			self.navReset = 0
			hostDrag(self, dx, dy)
		end
	end
	if self.navReset > 0 then
		-- Glide home: each step takes the same share of what is left.
		local k = 1 - math.exp(-math.min(seconds, 0.1) * 9)
		self.navYaw -= self.navYaw * k
		self.navPitch -= self.navPitch * k
		self.navPanX -= self.navPanX * k
		self.navPanY -= self.navPanY * k
		self.navPanZ -= self.navPanZ * k
		self.navZoom += (1 - self.navZoom) * k
		self.navReset = math.max(self.navReset - seconds * 1.5, 0)
		if self.navReset == 0 then
			self.navYaw, self.navPitch, self.navZoom = 0, 0, 1
			self.navPanX, self.navPanY, self.navPanZ = 0, 0, 0
		end
	end
	local dt = math.min(seconds, 0.1)
	self.time += dt
	-- The wind's phase runs at its speed, so changing the speed never jumps.
	self.windPhase += dt * math.max(self.windSpeed, 0)
	-- King Vikram: his pose, and he turns to face the way he walks (a jump,
	-- as when the story starts over, is not a step).
	local spirit = self.spirit
	if spirit then
		Spirit.advance(spirit, dt, 0, 1)
	end
	local hero = self.hero
	if self.play then
		if not self.gameOn then
			startGame(self)
		end
		-- The bow: Space (`fire`) held draws an arrow and holds it; let go,
		-- it looses.
		self.holding = self.fire ~= 0
		if self.fire ~= self.lastFire then
			self.lastFire = self.fire
			if self.fire ~= 0 then
				startShot(self, SHOT_ARROW)
			end
		end
		if self.shot ~= SHOT_NONE then
			if not shooting(self, hero, dt) then
				self.shot = SHOT_NONE
			end
		else
			local pose = steer(self, dt)
			if hero then
				Hero.advance(hero, dt, pose, self.kingSpeed)
			end
		end
		walk(self, hero, dt)
		chase(self, dt)
		-- The circle shows when it is on the wood, and settles after a kick.
		local cam = self.camera
		local ax, ay, az = aimRay(self)
		self.aimOnWood = rayWood(self, cam.x, cam.y, cam.z, ax, ay, az, ARROW_RANGE) ~= nil
		self.aimKick = math.max(self.aimKick - dt * 5, 0)
	else
		self.gameOn = false
		self.kx, self.kz = self.kingX, self.kingZ
		if hero then
			Hero.advance(hero, dt, self.kingPose, self.kingSpeed)
			local mx, mz = self.kx - self.lastKingX, self.kz - self.lastKingZ
			local moved = math.sqrt(mx * mx + mz * mz)
			if moved > 0.0005 and moved < 1 then
				local want = math.deg(math.atan2(mx, mz))
				local diff = (want - self.kingFacing + 540) % 360 - 180
				self.kingFacing += diff * (1 - math.exp(-dt * 6))
			end
		end
	end
	self.lastKingX, self.lastKingZ = self.kx, self.kz
	flyArrows(self, dt)
	-- The golden wave starts from the bow's grip, wherever it is then.
	-- The astra's wave runs its course, then is gone.
	if self.gameBlast > 0 then
		self.gameBlast += dt / BLAST_TIME
		if self.gameBlast >= 1 then
			self.gameBlast = 0
		end
	end
	local blast = math.max(self.blast, self.gameBlast)
	if blast > 0 and not self.blastOn then
		self.blastOn = true
		if hero then
			self.blastX, self.blastY, self.blastZ = hero.gripX, hero.gripY, hero.gripZ
		else
			self.blastX, self.blastY, self.blastZ = self.kx, groundAt(self, self.kx, self.kz) + 1.2, self.kz
		end
	elseif blast <= 0 then
		self.blastOn = false
	end
	return true
end

---------------------------------------------------------------------------
-- Targets and pipelines

local function ensureTargets(self: World): boolean
	local context = self.context
	assert(context)
	local res = clamp(self.resolution, 0.25, 3)
	local w = math.max(1, math.floor(self.width * res))
	local h = math.max(1, math.floor(self.height * res))
	local samples = if self.msaa >= 2 then 4 else 1
	if self.sceneCanvas and self.outCanvas and w == self.targetW and h == self.targetH and samples == self.targetSamples then
		return true
	end
	local scene = self.sceneCanvas
	if scene == nil then
		scene = context:gpuCanvas({ width = w, height = h })
		self.sceneCanvas = scene
	else
		scene:resize(w, h)
	end
	local out = self.outCanvas
	if out == nil then
		out = context:gpuCanvas({ width = w, height = h })
		self.outCanvas = out
	else
		out:resize(w, h)
	end
	-- The blurs: half and a quarter of the size.
	local nw, nh = math.max(1, w // 2), math.max(1, h // 2)
	local near = self.nearCanvas
	if near == nil then
		near = context:gpuCanvas({ width = nw, height = nh })
		self.nearCanvas = near
	else
		near:resize(nw, nh)
	end
	local ww, wh = math.max(1, w // 4), math.max(1, h // 4)
	local wide = self.wideCanvas
	if wide == nil then
		wide = context:gpuCanvas({ width = ww, height = wh })
		self.wideCanvas = wide
	else
		wide:resize(ww, wh)
	end
	assert(scene and out)
	self.depthView = GPUTexture.new({ width = w, height = h, format = DEPTH_FORMAT, renderTarget = true, sampleCount = samples }):view()
	self.msaaView = if samples > 1
		then GPUTexture.new({ width = w, height = h, format = scene.format, renderTarget = true, sampleCount = samples }):view()
		else nil
	if samples ~= self.targetSamples or self.staticPipeline == nil then
		local shader = self.shader
		local postShader = self.postShader
		assert(shader and postShader)
		local target: { ColorTarget } = { { format = scene.format } }
		local depth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'greater', write = true }
		self.skyPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_sky' },
			fragment = { module = shader, entryPoint = 'fs_sky' },
			vertexLayout = {},
			colorTargets = target,
			depthStencil = { format = DEPTH_FORMAT, compare = 'always', write = false },
			sampleCount = samples,
		})
		self.staticPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_static' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {
				{
					stride = 24,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'snorm8x4', slot = 1, offset = 12 },
						{ format = 'unorm8x4', slot = 2, offset = 16 },
						{ format = 'unorm8x4', slot = 5, offset = 20 },
					},
				},
				{
					stride = MORPH_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 12 },
					},
				},
			},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.instPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst' },
			fragment = { module = shader, entryPoint = 'fs_main' },
			vertexLayout = {
				{
					stride = 28,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'float32x3', slot = 1, offset = 12 },
						{ format = 'float32', slot = 2, offset = 24 },
					},
				},
				{
					stride = 16,
					stepMode = 'instance',
					attributes = {
						{ format = 'float16x4', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 8 },
						{ format = 'snorm8x4', slot = 5, offset = 12 },
					},
				},
			},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		self.pollenPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_pollen' },
			fragment = { module = shader, entryPoint = 'fs_pollen' },
			vertexLayout = {
				{ stride = 4, stepMode = 'instance', attributes = { { format = 'float32', slot = 0, offset = 0 } } },
			},
			colorTargets = {
				{
					format = scene.format,
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
			sampleCount = samples,
		})
		self.arrowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_arrow' },
			fragment = { module = shader, entryPoint = 'fs_arrow' },
			vertexLayout = {
				{
					stride = ARROW_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'unorm8x4', slot = 1, offset = 12 },
					},
				},
			},
			colorTargets = target,
			depthStencil = depth,
			cullMode = 'none',
			sampleCount = samples,
		})
		-- The shadow pass: depth only, from the sun.
		local shadowDepth: DepthStencilState = { format = DEPTH_FORMAT, compare = 'less', write = true }
		self.staticShadowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_static_shadow' },
			vertexLayout = {
				{
					stride = 24,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'snorm8x4', slot = 1, offset = 12 },
						{ format = 'unorm8x4', slot = 2, offset = 16 },
						{ format = 'unorm8x4', slot = 5, offset = 20 },
					},
				},
				{
					stride = MORPH_STRIDE,
					attributes = {
						{ format = 'float32x3', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 12 },
					},
				},
			},
			depthStencil = shadowDepth,
			cullMode = 'none',
		})
		self.instShadowPipeline = GPUPipeline.new({
			vertex = { module = shader, entryPoint = 'vs_inst_shadow' },
			vertexLayout = {
				{
					stride = 28,
					attributes = {
						{ format = 'float32x3', slot = 0, offset = 0 },
						{ format = 'float32x3', slot = 1, offset = 12 },
						{ format = 'float32', slot = 2, offset = 24 },
					},
				},
				{
					stride = 16,
					stepMode = 'instance',
					attributes = {
						{ format = 'float16x4', slot = 3, offset = 0 },
						{ format = 'snorm8x4', slot = 4, offset = 8 },
						{ format = 'snorm8x4', slot = 5, offset = 12 },
					},
				},
			},
			depthStencil = shadowDepth,
			cullMode = 'none',
		})
		local blurShader = self.blurShader
		assert(blurShader)
		self.nearPipeline = GPUPipeline.new({
			vertex = { module = blurShader, entryPoint = 'vs_main' },
			fragment = { module = blurShader, entryPoint = 'fs_near' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		self.widePipeline = GPUPipeline.new({
			vertex = { module = blurShader, entryPoint = 'vs_main' },
			fragment = { module = blurShader, entryPoint = 'fs_wide' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		self.postPipeline = GPUPipeline.new({
			vertex = { module = postShader, entryPoint = 'vs_main' },
			fragment = { module = postShader, entryPoint = 'fs_main' },
			vertexLayout = {},
			colorTargets = { { format = out.format } },
		})
		for _, sh in self.shared do
			sh.bindings = nil
			sh.shadowBindings = nil
		end
		self.skyBindings = nil
		self.pollenBindings = nil
		self.arrowBindings = nil
		local hero, kingShader = self.hero, self.kingShader
		if hero and kingShader then
			Hero.pipelines(hero, kingShader, scene.format, samples)
		end
		local spirit, vetalShader = self.spirit, self.vetalShader
		if spirit and vetalShader then
			Spirit.pipelines(spirit, vetalShader, scene.format, samples)
		end
	end
	-- The post pass reads the scene canvas, which has just been remade.
	self.postBindings = nil
	self.nearBindings = nil
	self.wideBindings = nil
	self.targetW, self.targetH, self.targetSamples = w, h, samples
	return true
end

---------------------------------------------------------------------------
-- Frame uniforms

local function frameUniforms(self: World)
	local u = self.frame
	local t = self.time
	local drift = clamp(self.drift, 0, 2)
	-- The camera, with a slow floating sway.
	local ex = self.cameraX + math.sin(t * 0.13) * 0.08 * drift
	local ey = self.cameraY + math.sin(t * 0.17 + 1) * 0.04 * drift
	local ez = self.cameraZ + math.cos(t * 0.11) * 0.08 * drift
	local yaw = math.rad(self.rotationY + math.sin(t * 0.09) * 0.7 * drift)
	local pitch = math.rad(self.rotationX + math.sin(t * 0.12 + 2) * 0.35 * drift)
	local roll = math.rad(self.rotationZ + math.sin(t * 0.07) * 0.25 * drift)
	-- Navigation: orbit the eye about a pivot `focusDistance` ahead (moved
	-- by the pan), at that distance times the zoom.
	local cp = math.cos(pitch)
	local orbit = clamp(self.focusDistance, 2, 60)
	local px = ex - math.sin(yaw) * cp * orbit + self.navPanX
	local py = ey + math.sin(pitch) * orbit + self.navPanY
	local pz = ez - math.cos(yaw) * cp * orbit + self.navPanZ
	yaw += math.rad(self.navYaw)
	pitch = clamp(pitch + math.rad(self.navPitch), math.rad(-85), math.rad(85))
	cp = math.cos(pitch)
	local fx, fy, fz = -math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp
	local dist = orbit * self.navZoom * clamp(self.zoom, 0.05, 20)
	ex, ey, ez = px - fx * dist, py - fy * dist, pz - fz * dist
	-- The cinematic camera: orbiting a target (or King Vikram), blended in.
	local cine = clamp(self.cinematic, 0, 1)
	local focus = clamp(self.focusDistance, 0.5, 200)
	if cine > 0 then
		local follow = clamp(self.camFollow, 0, 1)
		local kx, kz = self.kx, self.kz
		local ky = groundAt(self, kx, kz) + 1.25
		local tx = self.camTargetX + (kx - self.camTargetX) * follow
		local ty = self.camTargetY + (ky - self.camTargetY) * follow
		local tz = self.camTargetZ + (kz - self.camTargetZ) * follow
		local ca = math.rad(self.camAngle)
		local cd = math.max(self.camDistance, 0.5)
		local cx, cz = tx + math.sin(ca) * cd, tz + math.cos(ca) * cd
		local cy = math.max(ty + self.camHeight, groundAt(self, cx, cz) + 0.4)
		local gx, gy, gz = tx - cx, ty - cy, tz - cz
		local gl = math.max(math.sqrt(gx * gx + gy * gy + gz * gz), 1e-4)
		ex, ey, ez = ex + (cx - ex) * cine, ey + (cy - ey) * cine, ez + (cz - ez) * cine
		fx, fy, fz = fx + (gx / gl - fx) * cine, fy + (gy / gl - fy) * cine, fz + (gz / gl - fz) * cine
		local fl = math.max(math.sqrt(fx * fx + fy * fy + fz * fz), 1e-4)
		fx, fy, fz = fx / fl, fy / fl, fz / fl
		focus += (gl - focus) * cine
	end
	-- The game's camera: behind him, turned and tilted by the keypad,
	-- looking over his head; it rises off the ground rather than sink in.
	if self.play then
		local ya, pa = math.rad(self.gameYaw), math.rad(self.gamePitch)
		local d = math.max(self.chaseDistance, 0.5)
		local tx, tz = self.kx + math.cos(ya) * CHASE_SIDE, self.kz - math.sin(ya) * CHASE_SIDE
		local ty = groundAt(self, self.kx, self.kz) + CHASE_HEIGHT
		fx, fy, fz = -math.sin(ya) * math.cos(pa), -math.sin(pa), -math.cos(ya) * math.cos(pa)
		ex, ey, ez = tx - fx * d, ty - fy * d, tz - fz * d
		ey = math.max(ey, groundAt(self, ex, ez) + 0.3)
		focus = d
	end
	-- Never under the meadow.
	ey = math.max(ey, 0.35)
	-- right = fwd x worldUp, up = right x fwd, then the roll.
	local rx, rz = -fz, fx
	local rl = math.max(math.sqrt(rx * rx + rz * rz), 1e-6)
	rx, rz = rx / rl, rz / rl
	local ry = 0
	local ux = ry * fz - rz * fy
	local uy = rz * fx - rx * fz
	local uz = rx * fy - ry * fx
	local cr, sr = math.cos(roll), math.sin(roll)
	local Rx, Ry, Rz = rx * cr + ux * sr, ry * cr + uy * sr, rz * cr + uz * sr
	local Ux, Uy, Uz = ux * cr - rx * sr, uy * cr - ry * sr, uz * cr - rz * sr

	local aspect = self.targetW / math.max(self.targetH, 1)
	local fovY = math.rad(clamp(self.fov, 10, 120))
	local tanY = math.tan(fovY / 2)
	local proj = Mat4.perspectiveReverseZ(fovY, aspect, 0.05)
	local view = Mat4.lookAt(Vector.xyz(ex, ey, ez), Vector.xyz(ex + fx, ey + fy, ez + fz), Vector.xyz(Ux, Uy, Uz))
	local viewProj = proj * view
	viewProj:writeToBuffer(u, 0)
	-- Glory: brighter sun, thinner haze, a warmer horizon, more pollen.
	local g = clamp(self.glory, 0, 1)
	g = g * g * (3 - 2 * g)
	write4(u, 64, ex, ey, ez, t)
	-- The sun: its compass direction (0 = +X, 90 = +Z) and height.
	local az = math.rad(self.sunAzimuth)
	local el = math.rad(clamp(self.sunElevation, -10, 90))
	-- The moon: `moon` (0-1) is how much there is, its light, disc and
	-- beams; under it a faint starlight that never goes out.
	-- At 0 (amavas) it is all but pitch dark: only the fireflies and the ghost
	-- lights show anything.
	local moonAmount = clamp(self.moon, 0, 1)
	local moonlight = math.max(self.sunIntensity, 0) * (0.02 + 1.6 * moonAmount)
	-- How lit the night is (0.1 on amavas, 1 from moon 0.3 up): the moon's
	-- colour, the sky and the mist all fade with it, so everything the moon
	-- lights (the mist's glow, the clouds' rims) goes out together.
	local lit = 0.1 + 0.9 * math.min(moonAmount / 0.3, 1)
	write4(u, 80, math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el), moonlight)
	-- The sky's fill light fades with the moon too.
	do
		local mr, mg, mb = linear(self.sunColor)
		write4(u, 96, mr * lit, mg * lit, mb * lit, 0.2 * (0.08 + 0.92 * math.min(moonAmount / 0.3, 1)))
	end
	writeColor(u, 112, self.shadowColor, 0.08)
	-- Without the moon the sky and the mist lose their light too: unlit
	-- mist does not glow, and on amavas the night is near black.
	local function dim(c: Color, k: number, w: number, at: number)
		local r, gg, b = linear(c)
		write4(u, at, r * k, gg * k, b * k, w)
	end
	dim(self.skyColor, 0.35 + 0.65 * lit, clamp(self.clouds, 0, 1), 128)
	dim(self.skyMidColor, 0.3 + 0.7 * lit, math.max(self.mountains, 0), 528)
	writeColor(u, 544, self.mountainColor, clamp(self.moon, 0, 1))
	-- The fireflies that light the scene: each wanders in slow loops about
	-- its own spot in the box, and blinks (a slow swell, now and then a
	-- double flash), as the motes do in world.wgsl.
	local agents = self.agents
	if #agents == 0 then
		local seed = 7
		local function rnd(): number
			seed = (seed * 16807) % 2147483647
			return seed / 2147483647
		end
		for i = 1, FIREFLY_LIGHTS do
			-- Every other one keeps to the hero tree.
			local nearTree = i % 2 == 0
			local a, r = rnd() * 6.283, 1.8 + rnd() * 4.5
			table.insert(agents, {
				if nearTree then self.heroX + math.cos(a) * r else -2 + (rnd() - 0.5) * 20,
				if nearTree then self.heroY + 0.6 + rnd() * 4 else 0.5 + rnd() * rnd() * 2.2,
				if nearTree then self.heroZ + math.sin(a) * r else 2 + (rnd() - 0.5) * 18,
				0.25 + rnd() * 0.2, 0.7 + rnd() * 0.4, 0.35 + rnd() * 0.25, 0.22 + rnd() * 0.2,
				rnd() * 6.283, rnd() * 6.283, rnd() * 6.283, rnd() * 6.283,
				0.35 + rnd() * 0.45, rnd() * 37, rnd(),
			})
		end
	end
	local ft = self.time * math.max(self.fireflySpeed, 0)
	local count = clamp(self.fireflies, 0, MAX_POLLEN)
	for i, a in agents do
		local x = a[1] + math.sin(ft * a[4] + a[8]) * 1.4 + math.sin(ft * a[5] + a[9]) * 0.35
		local y = a[2] + math.sin(ft * a[6] + a[10]) * 0.35
		local z = a[3] + math.cos(ft * a[7] + a[11]) * 1.4 + math.cos(ft * a[5] * 0.9 + a[8]) * 0.35
		local beat = self.time * a[12] * (0.7 + 0.3 * math.max(self.fireflySpeed, 0)) + a[13]
		local pulse = math.max(math.sin(beat), 0) ^ 3
		if a[14] > 0.6 then
			pulse += 0.6 * math.max(math.sin(beat * 2.7 + a[13]), 0) ^ 12
		end
		if i > count then
			pulse = 0
		end
		write4(u, 560 + (i - 1) * 16, x, y, z, pulse)
	end
	-- The hero tree, and the ghost lights' orbits round it: each its own
	-- radius, height, starting angle and speed (some go the other way).
	write4(u, 944, self.heroX, self.heroY, self.heroZ, clamp(self.heroFireflies, 0, 1))
	local gr, gg, gb = linear(self.ghostColor)
	write4(u, 960, clamp(math.floor(self.ghostLights + 0.5), 0, MAX_GHOSTS), gr, gg, gb)
	local gseed = 11
	local function grnd(): number
		gseed = (gseed * 16807) % 2147483647
		return gseed / 2147483647
	end
	-- Fleeing: from when `ghostsFlee` turned on.
	if self.ghostsFlee > 0.5 then
		self.fleeStart = self.fleeStart or self.time
	else
		self.fleeStart = nil
	end
	local fleeStart = self.fleeStart
	write4(u, 1552, fleeStart or 0, if fleeStart then 1 else 0, 0, 0)
	local fled = if fleeStart then math.max(self.time - fleeStart, 0) else 0
	for i = 0, MAX_GHOSTS - 1 do
		local radius = 2.8 + grnd() * 4.2
		local height = 0.8 + grnd() * 5.5
		local phase = grnd() * 6.283
		local speed = (0.16 + grnd() * 0.22) * (if grnd() < 0.3 then -1 else 1)
		write4(u, 976 + i * 16, radius, height, phase, speed)
		-- And where it is now, with its flicker, as world.wgsl's ghostPos
		-- and ghostFlicker would put it.
		local now = self.time
		local f = fled
		local a = phase + now * speed + f * f * speed * 1.5
		local r = radius + f * (2.5 + f * 2.2)
		local bob = math.sin(now * 0.9 + phase * 3) * 0.35 + math.sin(now * 2.3 + phase) * 0.08
		local calm = 0.8 + 0.12 * math.sin(now * 7.3 + i * 1.7) + 0.08 * math.sin(now * 13.1 + i * 4.1)
		local wild = 0.75 + 0.25 * math.sin(now * 23 + i * 3.1)
		local flicker = (calm + (calm * wild - calm) * math.min(f * 2, 1)) * math.exp(-f * 0.75)
		write4(u, 1232 + i * 16, self.heroX + math.cos(a) * r, self.heroY + height + bob + f * (0.8 + f * 0.5), self.heroZ + math.sin(a) * r, flicker)
	end
	do
		local hr, hg, hb = linear(self.horizonColor)
		hr *= 0.25 + 0.75 * lit
		hg *= 0.25 + 0.75 * lit
		hb *= 0.25 + 0.75 * lit
		write4(u, 144, hr + (1.0 - hr) * g * 0.5, hg + (0.78 - hg) * g * 0.5, hb + (0.55 - hb) * g * 0.5, math.max(self.haze, 0) * 0.014 * (1 - 0.35 * g))
	end
	-- The mist's height falloff: it hugs the ground (about a metre deep).
	dim(self.hazeColor, lit, 0.9, 160)
	local wa = math.rad(self.windDirection)
	write4(u, 176, math.cos(wa), math.sin(wa), clamp(self.windStrength, 0, 3), clamp(self.gustiness, 0, 1))
	write4(u, 192, self.windPhase, clamp(self.flutter, 0, 3), self.windPhase * 0.03, 0)
	write4(u, 208, 0, 1, 0, 0)
	write4(u, 272, clamp(self.fireflies * (1 + 0.5 * g), 0, MAX_POLLEN), math.max(self.fireflySize, 0.001), math.max(self.fireflySpeed, 0), 1)
	writeColor(u, 288, self.fireflyColor, 0.9)
	local cam = self.camera
	cam.x, cam.y, cam.z = ex, ey, ez
	cam.fx, cam.fy, cam.fz = fx, fy, fz
	cam.rx, cam.ry, cam.rz = Rx, Ry, Rz
	cam.ux, cam.uy, cam.uz = Ux, Uy, Uz
	cam.tanX, cam.tanY = tanY * aspect, tanY
	write4(u, 304, Rx, Ry, Rz, tanY * aspect)
	write4(u, 320, Ux, Uy, Uz, tanY)
	write4(u, 336, fx, fy, fz, focus)
	-- Pollen fills a box from the camera to beyond the ruins.
	write4(u, 352, -2, 0, 2, clamp(self.depthOfField, 0, 2) * 2.5)
	write4(u, 368, 0, math.max(self.fireflySize, 0.001) * 2.2, 0, 0)
	write4(u, 448, g, math.max(self.clearNear, 0) * (if self.play then 1 else clamp(self.cinematic, 0, 1)), 0, 0)
	-- The sun's view for the shadow map: orthographic, over the ruins.
	local sx, sy, sz = math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)
	local half = SHADOW_SPAN / 2
	local up = if math.abs(sy) > 0.97 then Vector.xyz(1, 0, 0) else Vector.xyz(0, 1, 0)
	local lightView = Mat4.lookAt(Vector.xyz(sx * 80, 1.5 + sy * 80, sz * 80), Vector.xyz(0, 1.5, 0), up)
	local lightViewProj = Mat4.ortho(-half, half, -half, half, 1, 170) * lightView
	lightViewProj:writeToBuffer(u, 464)
	-- Where the sun is on screen, for the light shafts and glow.
	local ahead = sx * fx + sy * fy + sz * fz
	local q = viewProj:transformPoint(ex + sx * 1000, ey + sy * 1000, ez + sz * 1000)
	local screen = self.sunScreen
	screen[1] = q.x * 0.5 + 0.5
	screen[2] = 0.5 - q.y * 0.5
	screen[3] = if ahead > 0.05 then 1 else 0
	-- The golden wave: out from where it began, fast then slowing, fading as
	-- it goes.
	local b = clamp(math.max(self.blast, self.gameBlast), 0, 1)
	local radius = math.max(self.blastRange, 1) * (1 - (1 - b) ^ 2)
	local strength = if b > 0 and b < 1 then math.max(self.blastStrength, 0) * (1 - b) ^ 0.8 * math.min(b / 0.02, 1) else 0
	write4(u, 1488, self.blastX, self.blastY, self.blastZ, radius)
	writeColor(u, 1504, self.blastColor, strength)
	-- King Vikram's own light: his earrings' glow, and his bow's aura
	-- (last frame's) when he draws.
	if self.hero then
		local aura = buffer.readf32(self.kingFrame, 608)
		local ky = groundAt(self, self.kx, self.kz) + 1.3
		write4(u, 1520, self.kx, ky, self.kz, math.max(self.kingGlow, 0) + aura * 0.9)
		local k = clamp(aura, 0, 1)
		write4(u, 1536, 1, 0.62 + 0.1 * k, 0.28 + 0.05 * k, 0)
	else
		write4(u, 1520, 0, 0, 0, 0)
	end
end

-- King Vikram's uniforms (king.wgsl's block): the scene's camera, moon and
-- mist, then his own part from the Hero module.
-- The host's part of king.wgsl's (and vetal.wgsl's) uniforms: the scene's
-- camera, moon, mist and sky, and a soft warm fill.
local function characterUniforms(self: World, u: buffer)
	local f = self.frame
	buffer.copy(u, 0, f, 0, 64)
	buffer.copy(u, 64, f, 464, 64)
	buffer.copy(u, 128, f, 64, 16)
	buffer.copy(u, 144, f, 80, 16)
	local lit = math.min(clamp(self.moon, 0, 1) / 0.3, 1)
	buffer.copy(u, 160, f, 96, 12)
	buffer.writef32(u, 172, 0.15 + 0.85 * lit)
	-- A soft warm fill from the camera's side, so he reads on the darkest
	-- night.
	local fx, fz = buffer.readf32(f, 336), buffer.readf32(f, 344)
	local fl = math.max(math.sqrt(fx * fx + fz * fz + 0.35 * 0.35), 1e-4)
	write4(u, 176, -fx / fl, 0.35 / fl, -fz / fl, clamp(self.kingFill, 0, 2))
	write4(u, 192, 1, 0.72, 0.45, 0)
	write4(u, 208, 0.061, 0.044, 0.223, 0.4 + 0.4 * lit)
	write4(u, 256, self.targetW, self.targetH, 1 / self.targetW, 1 / self.targetH)
	buffer.copy(u, 272, f, 128, 16)
	buffer.copy(u, 288, f, 144, 16)
	buffer.copy(u, 304, f, 160, 12)
	buffer.writef32(u, 316, math.max(self.haze, 0) * 1.1)
	buffer.copy(u, 384, f, 304, 48)
	write4(u, 432, 0, 0, 1, 0)
end

local function kingUniforms(self: World, hero: Hero.Hero)
	local u = self.kingFrame
	characterUniforms(self, u)
	local s = self.kingSettings
	s.x, s.z = self.kx, self.kz
	s.y = groundAt(self, self.kx, self.kz)
	s.turn = self.kingFacing + self.kingTurn
	s.blink = self.kingBlink
	-- In the game the bow's golden aura is the astra's; an arrow's draw has
	-- none, but its loose sends out the rings.
	s.aura = if self.play and self.lastShot ~= SHOT_ASTRA and not self.loosed then 0 else self.kingAura
	s.auraColor, s.release = self.kingAuraColor, self.kingRelease
	local wa = math.rad(self.windDirection)
	s.windX, s.windZ = math.cos(wa), math.sin(wa)
	s.windStrength, s.windPhase, s.gustiness = self.windStrength, self.windPhase, self.gustiness
	s.hairWind, s.clothWind = self.kingHairWind, self.kingClothWind
	s.outline = 1.8 * clamp(self.resolution, 0.25, 3)
	s.time = self.time
	Hero.write(hero, u, s)
end

-- The Vetal's: where he hangs (vetal.bin's placement), his eyes, his
-- spirit light and the wind.
local function vetalUniforms(self: World, spirit: Spirit.Spirit)
	local u = self.vetalFrame
	characterUniforms(self, u)
	local s = self.vetalSettings
	local at = spirit.placement
	s.x, s.y, s.z, s.turn = at[1] or 0, at[2] or 0, at[3] or 0, at[4] or 0
	s.eyeGlow, s.eyeColor = self.vetalEyes, Color.rgb(255, 60, 25)
	s.spirit, s.spiritColor = self.vetalSpirit, self.vetalSpiritColor
	local wa = math.rad(self.windDirection)
	s.windX, s.windZ = math.cos(wa), math.sin(wa)
	s.windStrength, s.windPhase, s.gustiness = self.windStrength, self.windPhase, self.gustiness
	s.outline = 1.8 * clamp(self.resolution, 0.25, 3)
	s.time = self.time
	-- Under the post pass's bloom threshold (0.8), or the moon's shafts
	-- stream from him.
	s.ceiling = 0.7
	Spirit.write(spirit, u, s)
end

-- Where an object is at `time` seconds into the animation: its model matrix
-- goes into the uniforms, with its shape key's weight in mode.w. Returns
-- whether it has any size (a scale of 0 hides it).
local function writeTrack(u: buffer, track: Track, time: number): boolean
	local r = track.rest
	local px: number = r[1]
	local py: number = r[2]
	local pz: number = r[3]
	local qx: number = r[4]
	local qy: number = r[5]
	local qz: number = r[6]
	local qw: number = r[7]
	local sx: number = r[8]
	local sy: number = r[9]
	local sz: number = r[10]
	if track.samples > 0 then
		local d, o = track.data, track.offset
		local f = clamp((time - track.t0) / math.max(track.t1 - track.t0, 1e-6), 0, 1) * (track.samples - 1)
		local i = math.min(math.floor(f), track.samples - 2)
		if track.samples < 2 then
			i = 0
		end
		local k = if track.samples < 2 then 0 else f - i
		local a = o + i * 40
		local b = if track.samples < 2 then a else a + 40
		local function lerp(at: number): number
			local x = buffer.readf32(d, a + at)
			return x + (buffer.readf32(d, b + at) - x) * k
		end
		px = lerp(0)
		py = lerp(4)
		pz = lerp(8)
		qx = lerp(12)
		qy = lerp(16)
		qz = lerp(20)
		qw = lerp(24)
		sx = lerp(28)
		sy = lerp(32)
		sz = lerp(36)
		local l = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if l > 0 then
			qx /= l
			qy /= l
			qz /= l
			qw /= l
		end
	end
	local weight = 0
	if track.weightSamples > 0 then
		local f = clamp((time - track.w0) / math.max(track.w1 - track.w0, 1e-6), 0, 1) * (track.weightSamples - 1)
		local i = math.min(math.floor(f), math.max(track.weightSamples - 2, 0))
		local a = track.weightOffset + i * 4
		local x = buffer.readf32(track.data, a)
		local y = if track.weightSamples > 1 then buffer.readf32(track.data, a + 4) else x
		weight = x + (y - x) * (f - i)
	end
	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local wx, wy, wz = qw * qx, qw * qy, qw * qz
	write4(u, 384, (1 - 2 * (yy + zz)) * sx, (2 * (xy + wz)) * sx, (2 * (xz - wy)) * sx, 0)
	write4(u, 400, (2 * (xy - wz)) * sy, (1 - 2 * (xx + zz)) * sy, (2 * (yz + wx)) * sy, 0)
	write4(u, 416, (2 * (xz + wy)) * sz, (2 * (yz - wx)) * sz, (1 - 2 * (xx + yy)) * sz, 0)
	write4(u, 432, px, py, pz, 1)
	buffer.writef32(u, 220, weight)
	-- The glow (mode.z): rising as a pillar re-forms, then an afterglow
	-- that fades over a few seconds; a fragment glows in flight.
	local glow = 0
	if track.glows then
		if track.weightSamples > 0 then
			if time >= track.w0 then
				local fade = math.exp(-math.max(time - track.w1, 0) * 0.9)
				glow = math.sqrt(clamp(weight, 0, 1)) * fade
			end
		elseif track.samples > 0 then
			local f = clamp((time - track.t0) / math.max(track.t1 - track.t0, 1e-6), 0, 1)
			glow = math.sin(f * math.pi) ^ 0.7
		end
	end
	buffer.writef32(u, 216, glow)
	return math.abs(sx) + math.abs(sy) + math.abs(sz) > 1e-4
end

local function materialUniforms(self: World, d: Shared)
	local u = self.frame
	-- How much light passes through: leaves more than grass.
	local through = if d.material == 13
		then 0.5
		elseif d.material == 10 then 0.35
		elseif d.material >= 10 and d.material <= 18 then 1
		elseif d.material == 21 or d.material == 22 then 0.7
		elseif d.material == 27 or d.material == 28 then 0.6
		else 0
	write4(u, 208, d.material, through, 0, 0)
	local track = d.track
	if track then
		d.visible = writeTrack(u, track, clamp(self.glory, 0, 1) * DURATION)
	else
		write4(u, 384, 1, 0, 0, 0)
		write4(u, 400, 0, 1, 0, 0)
		write4(u, 416, 0, 0, 1, 0)
		write4(u, 432, 0, 0, 0, 1)
	end
	local ramp = RAMPS[d.material]
	if d.material == 14 then
		write4(u, 224, 0.95, 0.94, 0.9, 1)
		writeColor(u, 240, self.flowerColor, 1)
		write4(u, 256, 1, 0.86, 0.45, 1)
	elseif ramp then
		write4(u, 224, ramp[1][1], ramp[1][2], ramp[1][3], 1)
		write4(u, 240, ramp[2][1], ramp[2][2], ramp[2][3], 1)
		write4(u, 256, ramp[3][1], ramp[3][2], ramp[3][3], 1)
	end
	d.uniforms:write(u)
end

-- Whether a tile's bounding sphere is in front of the camera, inside the
-- view and near enough; sets its depth for sorting.
local function inView(cam: Camera, d: Draw): boolean
	local dx, dy, dz = d.cx - cam.x, d.cy - cam.y, d.cz - cam.z
	local z = dx * cam.fx + dy * cam.fy + dz * cam.fz
	local r = d.radius
	if z < -r or z - r > d.maxDistance then
		return false
	end
	local x = dx * cam.rx + dy * cam.ry + dz * cam.rz
	local y = dx * cam.ux + dy * cam.uy + dz * cam.uz
	-- Distance from the sphere's centre to each side plane, along its normal.
	if math.abs(x) - z * cam.tanX > r * math.sqrt(1 + cam.tanX * cam.tanX) then
		return false
	end
	if math.abs(y) - z * cam.tanY > r * math.sqrt(1 + cam.tanY * cam.tanY) then
		return false
	end
	d.depth = z
	return true
end

local function byDepth(a: Draw, b: Draw): boolean
	return a.depth < b.depth
end

---------------------------------------------------------------------------
-- Render

local function render(self: World): Image?
	if not ensureTargets(self) then
		return nil
	end
	local scene, out = self.sceneCanvas, self.outCanvas
	local depthView = self.depthView
	local skyPipeline, staticPipeline, instPipeline = self.skyPipeline, self.staticPipeline, self.instPipeline
	local pollenPipeline, postPipeline = self.pollenPipeline, self.postPipeline
	local skyUbo, pollenUbo, postUbo, sampler = self.skyUbo, self.pollenUbo, self.postUbo, self.sampler
	if not (scene and out and depthView and skyPipeline and staticPipeline and instPipeline and pollenPipeline and postPipeline) then
		return nil
	end
	if not (skyUbo and pollenUbo and postUbo and sampler) then
		return nil
	end

	frameUniforms(self)
	skyUbo:write(self.frame)
	pollenUbo:write(self.frame)
	local hero, kingUbo = self.hero, self.kingUbo
	if hero and kingUbo then
		kingUniforms(self, hero)
		kingUbo:write(self.kingFrame)
	end
	local spirit, vetalUbo = self.spirit, self.vetalUbo
	if spirit and vetalUbo then
		vetalUniforms(self, spirit)
		vetalUbo:write(self.vetalFrame)
	end
	local shadowView, shadowSampler, shadowTarget = self.shadowView, self.shadowSampler, self.shadowTarget
	local staticShadow, instShadow = self.staticShadowPipeline, self.instShadowPipeline
	if not (shadowView and shadowSampler and shadowTarget and staticShadow and instShadow) then
		return nil
	end
	local function withShadow(pipeline: GPUPipeline, ubo: GPUBuffer): GPUBindGroup
		return GPUBindGroup.new({
			layout = pipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = ubo } },
			textures = { { slot = 1, view = shadowView } },
			samplers = { { slot = 2, sampler = shadowSampler } },
		})
	end
	local function plain(pipeline: GPUPipeline, ubo: GPUBuffer): GPUBindGroup
		return GPUBindGroup.new({ layout = pipeline:getBindGroupLayout(0), ubos = { { slot = 0, buffer = ubo } } })
	end
	for _, sh in self.shared do
		materialUniforms(self, sh)
		if sh.bindings == nil then
			sh.bindings = withShadow(if sh.instanced then instPipeline else staticPipeline, sh.uniforms)
			sh.shadowBindings = plain(if sh.instanced then instShadow else staticShadow, sh.uniforms)
		end
	end
	-- The tiles of foliage in view, nearest first so the ones behind fail
	-- the depth test early.
	local visible = self.visible
	table.clear(visible)
	for _, d in self.draws do
		if d.instanced and inView(self.camera, d) then
			table.insert(visible, d)
		end
	end
	table.sort(visible, byDepth)
	if self.skyBindings == nil then
		local ok, b = pcall(plain, skyPipeline, skyUbo)
		self.skyBindings = if ok then b else withShadow(skyPipeline, skyUbo)
	end
	if self.pollenBindings == nil then
		local ok, b = pcall(plain, pollenPipeline, pollenUbo)
		self.pollenBindings = if ok then b else withShadow(pollenPipeline, pollenUbo)
	end
	local arrowPipeline, arrowBuffer = self.arrowPipeline, self.arrowBuffer
	if self.arrowBindings == nil and arrowPipeline then
		local ok, b = pcall(plain, arrowPipeline, pollenUbo)
		self.arrowBindings = if ok then b else withShadow(arrowPipeline, pollenUbo)
	end
	local arrowCount = if arrowBuffer and (#self.arrows > 0 or self.shot ~= SHOT_NONE) then arrowRibbons(self) else 0
	if arrowBuffer and arrowCount > 0 then
		arrowBuffer:write(self.arrowVerts)
	end

	-- The sun's shadow map: what blocks the sun (the stone, the objects, the
	-- bush and tree clumps; not the grass, flowers or leaf cards).
	local shadowPass = scene:beginRenderPass({
		depthStencil = { view = shadowTarget, depthLoadOp = 'clear', depthStoreOp = 'store', depthClearValue = 1 },
	})
	shadowPass:setPipeline(staticShadow)
	for _, d in self.draws do
		local b = d.shared.shadowBindings
		local morph = d.morphBuffer
		if not d.instanced and b and morph and d.shared.visible and d.material ~= 4 and d.material ~= 5 and d.material ~= 8 then
			shadowPass:setBindGroup(0, b)
			shadowPass:setVertexBuffer(0, d.vertexBuffer)
			shadowPass:setVertexBuffer(1, morph)
			shadowPass:setIndexBuffer(d.indexBuffer, 'uint16')
			shadowPass:drawIndexed(d.indexCount)
		end
	end
	shadowPass:setPipeline(instShadow)
	for _, d in self.draws do
		local b = d.shared.shadowBindings
		local instances = d.instanceBuffer
		if d.instanced and b and instances and (d.material == 15 or d.material == 16) then
			shadowPass:setBindGroup(0, b)
			shadowPass:setVertexBuffer(0, d.vertexBuffer)
			shadowPass:setVertexBuffer(1, instances)
			shadowPass:setIndexBuffer(d.indexBuffer, 'uint16')
			shadowPass:drawIndexed(d.indexCount, d.instanceCount)
		end
	end
	if hero and kingUbo then
		Hero.drawShadow(hero, shadowPass, kingUbo, shadowView, shadowSampler)
	end
	if spirit and vetalUbo then
		Spirit.drawShadow(spirit, shadowPass, vetalUbo, shadowView, shadowSampler)
	end
	shadowPass:finish()

	local color: ColorAttachment = if self.targetSamples > 1
		then { view = self.msaaView, resolveTarget = scene:colorView(), loadOp = 'clear', storeOp = 'discard', clearColor = { 0, 0, 0, 1 } }
		else { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } }
	local pass = scene:beginRenderPass({
		color = { color },
		depthStencil = { view = depthView, depthLoadOp = 'clear', depthStoreOp = 'discard', depthClearValue = 0 },
	})
	local skyBindings = self.skyBindings
	assert(skyBindings)
	pass:setPipeline(skyPipeline)
	pass:setBindGroup(0, skyBindings)
	pass:draw(3)
	pass:setPipeline(staticPipeline)
	for _, d in self.draws do
		local bindings = d.shared.bindings
		local morph = d.morphBuffer
		if not d.instanced and bindings and morph and d.shared.visible then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, d.vertexBuffer)
			pass:setVertexBuffer(1, morph)
			pass:setIndexBuffer(d.indexBuffer, 'uint16')
			pass:drawIndexed(d.indexCount)
		end
	end
	pass:setPipeline(instPipeline)
	for _, d in visible do
		local bindings = d.shared.bindings
		local instances = d.instanceBuffer
		if bindings and instances then
			pass:setBindGroup(0, bindings)
			pass:setVertexBuffer(0, d.vertexBuffer)
			pass:setVertexBuffer(1, instances)
			pass:setIndexBuffer(d.indexBuffer, 'uint16')
			pass:drawIndexed(d.indexCount, d.instanceCount)
		end
	end
	if hero and kingUbo then
		Hero.draw(hero, pass, kingUbo, shadowView, shadowSampler, true)
	end
	if spirit and vetalUbo then
		Spirit.draw(spirit, pass, vetalUbo, shadowView, shadowSampler, true)
	end
	local arrowBindings = self.arrowBindings
	if arrowCount > 0 and arrowPipeline and arrowBindings and arrowBuffer then
		pass:setPipeline(arrowPipeline)
		pass:setBindGroup(0, arrowBindings)
		pass:setVertexBuffer(0, arrowBuffer)
		pass:draw(arrowCount * ARROW_VERTS)
	end
	local pollen = math.ceil(clamp(self.fireflies, 0, MAX_POLLEN))
	local pollenBindings = self.pollenBindings
	local pollenIds = self.pollenIds
	if pollen > 0 and pollenBindings and pollenIds then
		pass:setPipeline(pollenPipeline)
		pass:setBindGroup(0, pollenBindings)
		pass:setVertexBuffer(0, pollenIds)
		pass:draw(6, pollen)
	end
	-- The ghost lights, through the same pipeline: their ids start at
	-- GHOST_BASE, so world.wgsl flies them round the hero tree.
	local ghosts = clamp(math.floor(self.ghostLights + 0.5), 0, MAX_GHOSTS)
	local ghostIds = self.ghostIds
	if ghosts > 0 and pollenBindings and ghostIds then
		pass:setPipeline(pollenPipeline)
		pass:setBindGroup(0, pollenBindings)
		pass:setVertexBuffer(0, ghostIds)
		pass:draw(6, ghosts * GHOST_TRAIL)
	end
	pass:finish()

	-- The finish.
	local p = self.postParams
	write4(p, 0, 1 / self.targetW, 1 / self.targetH, self.targetW / self.targetH, self.time)
	write4(p, 16, math.max(self.bloom, 0), clamp(self.glow, 0, 1), clamp(self.depthOfField, 0, 1), math.max(self.exposure, 0))
	write4(p, 32, 0.95, 1.0, 1.07, 1.04)
	write4(p, 48, 0.35, clamp(self.grain, 0, 1), 0.8, 0.0045)
	-- The moon's glow on screen fades with the moon.
	local lr, lg, lb = linear(self.sunColor)
	local leak = math.min(clamp(self.moon, 0, 1) / 0.3, 1)
	write4(p, 64, lr, lg * 0.92, lb * 0.85, (clamp(self.lightLeak + 0.3 * clamp(self.glory, 0, 1), 0, 1.5)) * leak)
	local sun = self.sunScreen
	write4(p, 80, sun[1], sun[2], math.max(self.shafts, 0) * clamp(self.moon, 0, 1), sun[3])
	postUbo:write(p)
	local near, wide = self.nearCanvas, self.wideCanvas
	local nearPipeline, widePipeline = self.nearPipeline, self.widePipeline
	if not (near and wide and nearPipeline and widePipeline) then
		return nil
	end
	if self.postBindings == nil then
		self.nearBindings = GPUBindGroup.new({
			layout = nearPipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = scene:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		-- The wide blur spreads the half-size one further.
		self.wideBindings = GPUBindGroup.new({
			layout = widePipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = { { slot = 1, view = near:colorView() } },
			samplers = { { slot = 2, sampler = sampler } },
		})
		self.postBindings = GPUBindGroup.new({
			layout = postPipeline:getBindGroupLayout(0),
			ubos = { { slot = 0, buffer = postUbo } },
			textures = {
				{ slot = 1, view = scene:colorView() },
				{ slot = 3, view = near:colorView() },
				{ slot = 4, view = wide:colorView() },
			},
			samplers = { { slot = 2, sampler = sampler } },
		})
	end
	local postBindings, nearBindings, wideBindings = self.postBindings, self.nearBindings, self.wideBindings
	assert(postBindings and nearBindings and wideBindings)
	local blurPass = near:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	blurPass:setPipeline(nearPipeline)
	blurPass:setBindGroup(0, nearBindings)
	blurPass:draw(3)
	blurPass:finish()
	local widePass = wide:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	widePass:setPipeline(widePipeline)
	widePass:setBindGroup(0, wideBindings)
	widePass:draw(3)
	widePass:finish()
	local post = out:beginRenderPass({ color = { { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 1 } } } })
	post:setPipeline(postPipeline)
	post:setBindGroup(0, postBindings)
	post:draw(3)
	post:finish()
	return out.image
end

---------------------------------------------------------------------------
-- Navigation

local ORBIT_DEGREES_PER_PX = 0.3

-- Moves the pivot by a drag of (dx, dy) node pixels: the scene follows the
-- pointer, as in Blender.
local function pan(self: World, dx: number, dy: number)
	local cam = self.camera
	local orbit = clamp(self.focusDistance, 2, 60) * self.navZoom * clamp(self.zoom, 0.05, 20)
	local perPx = 2 * orbit * cam.tanY / math.max(self.height, 1)
	self.navPanX += (-cam.rx * dx + cam.ux * dy) * perPx
	self.navPanY += (-cam.ry * dx + cam.uy * dy) * perPx
	self.navPanZ += (-cam.rz * dx + cam.uz * dy) * perPx
end

local function zoomBy(self: World, factor: number)
	self.navZoom = clamp(self.navZoom * factor, 0.08, 6)
end

-- A one-pointer drag of (dx, dy) node pixels, by `navMode`: turntable orbit
-- (the scene turns with the pointer), pan or zoom.
local function applyDrag(self: World, dx: number, dy: number)
	-- In the game, a drag looks round him: right turns right, up looks up.
	if self.play then
		self.gameYaw = (self.gameYaw - dx * LOOK_PER_PX) % 360
		self.gamePitch = clamp(self.gamePitch + dy * LOOK_PER_PX, PITCH_MIN, PITCH_MAX)
		return
	end
	local mode = math.floor(self.navMode + 0.5)
	if mode == 1 then
		pan(self, dx, dy)
	elseif mode == 2 then
		zoomBy(self, math.exp(dy * 0.005))
	else
		self.navYaw -= dx * ORBIT_DEGREES_PER_PX
		self.navPitch -= dy * ORBIT_DEGREES_PER_PX
		local base = self.rotationX
		self.navPitch = clamp(self.navPitch, -85 - base, 85 - base)
	end
end

hostDrag = applyDrag

local function pointerDown(self: World, event: PointerEvent)
	if self.play then
		self.aimX, self.aimY = event.position.x, event.position.y
	end
	if not self.navigation and not self.play then
		return
	end
	if self.pointers[event.id] == nil then
		self.pointerCount += 1
	end
	self.pointers[event.id] = event.position
	self.navReset = 0
	if self.pointerCount == 1 then
		-- A second tap soon after, near the first: back home.
		local near = Vector.length(event.position - self.lastTapPosition) < 30
		if self.time - self.lastTapTime < 0.35 and near and not self.play then
			startReset(self)
			self.lastTapTime = -1
		else
			self.lastTapTime = self.time
			self.lastTapPosition = event.position
		end
		self.tapMoved = 0
	end
	event:hit()
end

local function pointerMove(self: World, event: PointerEvent)
	-- The target circle follows the pointer, pressed or not.
	if self.play then
		self.aimX, self.aimY = event.position.x, event.position.y
	end
	local last = self.pointers[event.id]
	if (not self.navigation and not self.play) or last == nil then
		return
	end
	local d = event.position - last
	self.tapMoved += Vector.length(d)
	if self.tapMoved > 12 then
		self.lastTapTime = -1
	end
	if self.pointerCount >= 2 then
		-- Two fingers: the midpoint pans, the spread zooms.
		local other: Vector? = nil
		for id, p in self.pointers do
			if id ~= event.id then
				other = p
				break
			end
		end
		if other then
			local before = Vector.length(last - other)
			local after = Vector.length(event.position - other)
			if before > 1 and after > 1 then
				zoomBy(self, before / after)
			end
			pan(self, d.x / 2, d.y / 2)
		end
	else
		applyDrag(self, d.x, d.y)
	end
	self.pointers[event.id] = event.position
	event:hit()
end

local function pointerUp(self: World, event: PointerEvent)
	-- In the game a tap (not a drag) looses an arrow.
	if self.play and self.pointers[event.id] ~= nil and self.pointerCount == 1 and self.tapMoved < 8 then
		self.aimX, self.aimY = event.position.x, event.position.y
		startShot(self, SHOT_ASTRA)
	end
	if self.pointers[event.id] ~= nil then
		self.pointers[event.id] = nil
		self.pointerCount = math.max(self.pointerCount - 1, 0)
		event:hit()
	end
end

local function pointerExit(self: World, event: PointerEvent)
	pointerUp(self, event)
end

function draw(self: World, renderer: Renderer)
	if self.failed then
		return
	end
	local ok, result = pcall(render, self)
	if not ok then
		print('World: render failed: ' .. tostring(result))
		self.failed = true
		return
	end
	local image = result
	if image then
		renderer:save()
		renderer:transform(
			Mat2D.withTranslation(-self.width / 2, -self.height / 2)
				* Mat2D.withScale(self.width / self.targetW, self.height / self.targetH)
		)
		renderer:drawImage(image, self.drawSampler, 'srcOver', 1)
		renderer:restore()
	end
	-- The target circle: a ring and a dot, gold over the peepal's wood; it
	-- opens as he looses.
	if self.play then
		local path = self.reticle
		local x, y = self.aimX, self.aimY
		local function circle(r: number)
			local k = r * 0.5523
			path:moveTo(Vector.xy(x + r, y))
			path:cubicTo(Vector.xy(x + r, y + k), Vector.xy(x + k, y + r), Vector.xy(x, y + r))
			path:cubicTo(Vector.xy(x - k, y + r), Vector.xy(x - r, y + k), Vector.xy(x - r, y))
			path:cubicTo(Vector.xy(x - r, y - k), Vector.xy(x - k, y - r), Vector.xy(x, y - r))
			path:cubicTo(Vector.xy(x + k, y - r), Vector.xy(x + r, y - k), Vector.xy(x + r, y))
			path:close()
		end
		local color = if self.aimOnWood then Color.rgba(255, 196, 92, 235) else Color.rgba(240, 240, 255, 200)
		path:reset()
		circle(15 + 9 * self.aimKick)
		self.reticlePaint.color = color
		renderer:drawPath(path, self.reticlePaint)
		path:reset()
		circle(2.2)
		self.reticleDot.color = color
		renderer:drawPath(path, self.reticleDot)
	end
end

return function(): Node<World>
	return {
		asset = 'world',
		width = 1280,
		height = 720,
		resolution = 1,
		msaa = 4,
		cameraX = -14,
		cameraY = 2,
		cameraZ = 17.5,
		rotationX = 2,
		rotationY = -38,
		rotationZ = 0,
		fov = 46,
		drift = 1,
		sunAzimuth = -40,
		sunElevation = 26,
		sunIntensity = 1,
		lightLeak = 0.15,
		shafts = 0.6,
		glory = 0,
		navigation = true,
		navMode = 0,
		zoom = 1,
		resetView = 0,
		dragX = 0,
		dragY = 0,
		windStrength = 1,
		windSpeed = 1,
		windDirection = 30,
		gustiness = 0.6,
		flutter = 1,
		haze = 1.2,
		clouds = 0.35,
		bloom = 0.9,
		glow = 0.22,
		depthOfField = 0.5,
		focusDistance = 18,
		exposure = 1.3,
		fireflies = 750,
		fireflySize = 0.02,
		fireflySpeed = 0.6,
		fireflyColor = Color.rgb(210, 255, 120),
		flowerColor = Color.rgb(255, 170, 200),
		sunColor = Color.rgb(150, 175, 245),
		shadowColor = Color.rgb(36, 44, 92),
		skyColor = Color.rgb(3, 5, 14),
		skyMidColor = Color.rgb(14, 18, 48),
		mountains = 1,
		moon = 0.3,
		grain = 0.1,
		heroX = 1.95,
		heroY = -0.16,
		heroZ = -4.93,
		heroFireflies = 0.5,
		ghostLights = 8,
		ghostColor = Color.rgb(150, 220, 255),
		ghostsFlee = 0,
		mountainColor = Color.rgb(8, 11, 24),
		horizonColor = Color.rgb(24, 40, 60),
		hazeColor = Color.rgb(34, 46, 76),
		king = '',
		vetal = '',
		vetalEyes = 1.5,
		vetalSpirit = 0,
		vetalSpiritColor = Color.rgb(242, 246, 255),
		kingX = -9.5,
		kingZ = 9,
		kingTurn = 0,
		kingPose = 0,
		kingSpeed = 1,
		kingAura = 1,
		kingAuraColor = Color.rgb(255, 190, 90),
		kingRelease = 0,
		kingHairWind = 1,
		kingClothWind = 1,
		kingBlink = 0,
		kingFill = 0.3,
		kingGlow = 0.25,
		blast = 0,
		blastRange = 45,
		blastStrength = 1,
		blastColor = Color.rgb(255, 180, 80),
		cinematic = 0,
		camTargetX = 1.95,
		camTargetY = 2.5,
		camTargetZ = -4.93,
		camAngle = 0,
		camDistance = 14,
		camHeight = 2,
		camFollow = 0,
		clearNear = 0,
		play = false,
		keyUp = 0,
		keyDown = 0,
		keyLeft = 0,
		keyRight = 0,
		lookUp = 0,
		lookDown = 0,
		lookLeft = 0,
		lookRight = 0,
		fire = 0,

		context = nil,
		hero = nil,
		kingShader = nil,
		kingUbo = nil,
		kingFrame = buffer.create(Hero.UNIFORM_SIZE),
		spirit = nil,
		vetalShader = nil,
		vetalUbo = nil,
		vetalFrame = buffer.create(Spirit.UNIFORM_SIZE),
		vetalSettings = {
			x = 0,
			y = 0,
			z = 0,
			turn = 0,
			eyeGlow = 1.5,
			eyeColor = Color.rgb(255, 60, 25),
			spirit = 0.8,
			spiritColor = Color.rgb(242, 246, 255),
			windX = 1,
			windZ = 0,
			windStrength = 0,
			windPhase = 0,
			gustiness = 0.6,
			hairWind = 1,
			clothWind = 1,
			paint = 0.75,
			bands = 3,
			outline = 1.8,
			inkColor = Color.rgb(16, 10, 24),
			inkDetail = 0.6,
			hatching = 0.5,
			time = 0,
		},
		kingSettings = {
			x = 0,
			y = 0,
			z = 0,
			turn = 0,
			eyes = 1,
			blink = 0,
			earringGlow = 1,
			earringColor = Color.rgb(255, 176, 70),
			aura = 1,
			auraColor = Color.rgb(255, 190, 90),
			release = 0,
			windX = 1,
			windZ = 0,
			windStrength = 0,
			windPhase = 0,
			gustiness = 0.6,
			hairWind = 1,
			clothWind = 1,
			paint = 0.75,
			bands = 3,
			outline = 1.8,
			inkColor = Color.rgb(16, 10, 24),
			inkDetail = 0.6,
			hatching = 0.5,
			time = 0,
		},
		kingFacing = 135,
		lastKingX = 0,
		lastKingZ = 0,
		kx = 0,
		kz = 0,
		gameOn = false,
		gameYaw = 0,
		gamePitch = 0,
		yawSpeed = 0,
		pitchSpeed = 0,
		chaseDistance = 0,
		wood = nil,
		woodDims = { 0, 0, 0 },
		woodLo = { 0, 0, 0 },
		woodHi = { 0, 0, 0 },
		arrows = {},
		arrowVerts = buffer.create((MAX_ARROWS + 1) * ARROW_VERTS * ARROW_STRIDE),
		arrowBuffer = nil,
		arrowPipeline = nil,
		arrowBindings = nil,
		aimX = 0,
		aimY = 0,
		aimOnWood = false,
		aimKick = 0,
		lastFire = 0,
		shot = 0,
		lastShot = 0,
		shotPose = 0,
		holding = false,
		loosed = false,
		shotYaw = 0,
		pulled = false,
		gameBlast = 0,
		pullSound = nil,
		looseSound = nil,
		arrowSound = nil,
		hitSound = nil,
		reticle = Path.new(),
		reticlePaint = Paint.with({ style = 'stroke', thickness = 1.8, color = Color.rgba(240, 240, 255, 200) }),
		reticleDot = Paint.with({ style = 'fill', color = Color.rgba(240, 240, 255, 200) }),
		walkable = nil,
		walkN = 0,
		walkLo = { 0, 0 },
		walkHi = { 0, 0 },
		blastOn = false,
		blastX = 0,
		blastY = 0,
		blastZ = 0,
		heights = nil,
		heightN = 0,
		heightLo = { 0, 0 },
		heightHi = { 1, 1 },
		shader = nil,
		postShader = nil,
		blurShader = nil,
		failed = false,
		time = 0,
		windPhase = 0,
		draws = {},
		shared = {},
		visible = {},
		navYaw = 0,
		navPitch = 0,
		navPanX = 0,
		navPanY = 0,
		navPanZ = 0,
		navZoom = 1,
		navReset = 0,
		lastResetView = 0,
		lastDragX = 0,
		lastDragY = 0,
		pointers = {},
		pointerCount = 0,
		lastTapTime = -1,
		lastTapPosition = Vector.xy(0, 0),
		tapMoved = 0,
		agents = {},
		camera = { x = 0, y = 0, z = 0, fx = 0, fy = 0, fz = -1, rx = 1, ry = 0, rz = 0, ux = 0, uy = 1, uz = 0, tanX = 1, tanY = 1 },
		skyUbo = nil,
		skyBindings = nil,
		pollenUbo = nil,
		pollenBindings = nil,
		pollenIds = nil,
		ghostIds = nil,
		fleeStart = nil,
		postUbo = nil,
		postBindings = nil,
		nearBindings = nil,
		wideBindings = nil,
		sceneCanvas = nil,
		outCanvas = nil,
		nearCanvas = nil,
		wideCanvas = nil,
		depthView = nil,
		msaaView = nil,
		staticPipeline = nil,
		instPipeline = nil,
		skyPipeline = nil,
		pollenPipeline = nil,
		staticShadowPipeline = nil,
		instShadowPipeline = nil,
		shadowTexture = nil,
		shadowTarget = nil,
		shadowView = nil,
		shadowSampler = nil,
		sunScreen = { 0.5, 0.5, 0, 0 },
		postPipeline = nil,
		nearPipeline = nil,
		widePipeline = nil,
		sampler = nil,
		targetW = 0,
		targetH = 0,
		targetSamples = 0,
		frame = buffer.create(UNIFORM_SIZE),
		postParams = buffer.create(POST_SIZE),
		drawSampler = ImageSampler('clamp', 'clamp', 'bilinear'),

		init = init,
		advance = advance,
		draw = draw,
		pointerDown = pointerDown,
		pointerMove = pointerMove,
		pointerUp = pointerUp,
		pointerExit = pointerExit,
	}
end
