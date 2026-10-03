-- GLB (binary glTF 2.0) importer.
--
--   local GLB = require('GLB')
--   local model, err = GLB.parse(context:blob('ring').data)
--
-- Reads the JSON and BIN chunks, walks the default scene and flattens every
-- mesh primitive into world space (node transforms are baked in). Each
-- primitive comes back as an interleaved vertex buffer ready for the GPU:
--
--   position float32x3 | normal float32x3 | uv float32x2   (32 bytes/vertex)
--
-- plus a uint32 index buffer and its material. Images are returned as raw
-- PNG/JPEG bytes for `context:decodeImage`.
--
-- Supported: triangles (mode 4), indexed or not; any component type, with
-- `normalized` (so KHR_mesh_quantization data reads correctly); interleaved
-- buffer views; node matrix or TRS; missing normals (computed smooth);
-- baseColor / metallic / roughness / emissive factors and the base colour
-- texture.
-- Not supported: .gltf with external files or data URIs, Draco / meshopt
-- compression, sparse accessors, skins, morph targets, animations, cameras,
-- lights, normal/occlusion/metal-rough textures, texture transforms.

export type Material = {
	name: string,
	baseColor: { number }, -- linear RGBA
	metallic: number,
	roughness: number,
	emissive: { number }, -- linear RGB
	baseColorImage: number?, -- index into Model.images
	doubleSided: boolean,
	alphaBlend: boolean,
}

export type Primitive = {
	meshIndex: number, -- 0-based glTF mesh index
	meshName: string,
	nodeName: string,
	vertices: buffer, -- interleaved, VERTEX_STRIDE bytes per vertex
	vertexCount: number,
	indices: buffer, -- uint32
	indexCount: number,
	material: Material,
}

export type Image = { data: buffer, mimeType: string }

export type Model = {
	primitives: { Primitive },
	images: { Image },
	min: { number }, -- world-space bounds
	max: { number },
	center: { number },
	radius: number, -- bounding-sphere radius around `center`
	vertexCount: number,
	triangleCount: number,
}

local GLB = {}

GLB.VERTEX_STRIDE = 32

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

local function decodeJson(text: string): any
	local pos = 1
	local len = #text

	local function fail(msg: string): any
		error(string.format('JSON %s at %d', msg, pos), 0)
	end

	local function skip()
		while pos <= len do
			local c = string.byte(text, pos)
			if c == 32 or c == 9 or c == 10 or c == 13 then
				pos += 1
			else
				return
			end
		end
	end

	local parseValue: () -> any

	local function parseString(): string
		pos += 1 -- opening quote
		local parts: { string } = {}
		local start = pos
		while true do
			local c = string.byte(text, pos)
			if c == nil then
				return fail('unterminated string')
			elseif c == 34 then -- "
				table.insert(parts, string.sub(text, start, pos - 1))
				pos += 1
				return table.concat(parts)
			elseif c == 92 then -- backslash
				table.insert(parts, string.sub(text, start, pos - 1))
				local e = string.sub(text, pos + 1, pos + 1)
				if e == 'u' then
					local code = tonumber(string.sub(text, pos + 2, pos + 5), 16) or 63
					table.insert(parts, utf8.char(code))
					pos += 6
				else
					local map: { [string]: string } = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' }
					local ch: string = map[e] or e
					table.insert(parts, ch)
					pos += 2
				end
				start = pos
			else
				pos += 1
			end
		end
	end

	local function parseNumber(): number
		local s, e = string.find(text, '^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
		if s == nil or e == nil then
			return fail('bad number')
		end
		local n = tonumber(string.sub(text, s, e))
		pos = e + 1
		return n or fail('bad number')
	end

	function parseValue(): any
		skip()
		local c = string.sub(text, pos, pos)
		if c == '{' then
			pos += 1
			local obj = {}
			skip()
			if string.sub(text, pos, pos) == '}' then
				pos += 1
				return obj
			end
			while true do
				skip()
				if string.sub(text, pos, pos) ~= '"' then
					return fail('expected key')
				end
				local key = parseString()
				skip()
				if string.sub(text, pos, pos) ~= ':' then
					return fail("expected ':'")
				end
				pos += 1
				obj[key] = parseValue()
				skip()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == '}' then
					return obj
				elseif d ~= ',' then
					return fail("expected ',' or '}'")
				end
			end
		elseif c == '[' then
			pos += 1
			local arr = {}
			skip()
			if string.sub(text, pos, pos) == ']' then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, parseValue())
				skip()
				local d = string.sub(text, pos, pos)
				pos += 1
				if d == ']' then
					return arr
				elseif d ~= ',' then
					return fail("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return parseString()
		elseif c == 't' then
			pos += 4
			return true
		elseif c == 'f' then
			pos += 5
			return false
		elseif c == 'n' then
			pos += 4
			return nil
		else
			return parseNumber()
		end
	end

	return parseValue()
end

GLB.decodeJson = decodeJson

-- ---------------------------------------------------------------------------
-- 4x4 matrices (column-major arrays of 16, like glTF)
-- ---------------------------------------------------------------------------

local function identity(): { number }
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

local function mul(a: { number }, b: { number }): { number }
	local o = table.create(16, 0)
	for c = 0, 3 do
		for r = 0, 3 do
			local s = 0
			for k = 0, 3 do
				s += a[k * 4 + r + 1] * b[c * 4 + k + 1]
			end
			o[c * 4 + r + 1] = s
		end
	end
	return o
end

local function fromTRS(t: { number }?, q: { number }?, s: { number }?): { number }
	local tx, ty, tz = 0, 0, 0
	if t then
		tx, ty, tz = t[1], t[2], t[3]
	end
	local x, y, z, w = 0, 0, 0, 1
	if q then
		x, y, z, w = q[1], q[2], q[3], q[4]
	end
	local sx, sy, sz = 1, 1, 1
	if s then
		sx, sy, sz = s[1], s[2], s[3]
	end
	local xx, yy, zz = x * x, y * y, z * z
	local xy, xz, yz = x * y, x * z, y * z
	local wx, wy, wz = w * x, w * y, w * z
	return {
		(1 - 2 * (yy + zz)) * sx, 2 * (xy + wz) * sx, 2 * (xz - wy) * sx, 0,
		2 * (xy - wz) * sy, (1 - 2 * (xx + zz)) * sy, 2 * (yz + wx) * sy, 0,
		2 * (xz + wy) * sz, 2 * (yz - wx) * sz, (1 - 2 * (xx + yy)) * sz, 0,
		tx, ty, tz, 1,
	}
end

-- Inverse-transpose of the upper 3x3, for transforming normals.
local function normalMatrix(m: { number }): { number }
	local a, b, c = m[1], m[5], m[9]
	local d, e, f = m[2], m[6], m[10]
	local g, h, i = m[3], m[7], m[11]
	local A, B, C = e * i - f * h, -(d * i - f * g), d * h - e * g
	local D, E, F = -(b * i - c * h), a * i - c * g, -(a * h - b * g)
	local G, H, I = b * f - c * e, -(a * f - c * d), a * e - b * d
	local det = a * A + b * B + c * C
	if math.abs(det) < 1e-12 then
		det = 1
	end
	-- cofactor matrix / det is the inverse-transpose; rows below are columns
	return { A / det, B / det, C / det, D / det, E / det, F / det, G / det, H / det, I / det }
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

local COMPONENTS = { SCALAR = 1, VEC2 = 2, VEC3 = 3, VEC4 = 4, MAT2 = 4, MAT3 = 9, MAT4 = 16 }
local COMPONENT_SIZE = { [5120] = 1, [5121] = 1, [5122] = 2, [5123] = 2, [5125] = 4, [5126] = 4 }

-- Returns a reader `get(i, k)` for element i (0-based), component k (0-based).
type Reader = (i: number, k: number) -> number

local function accessorReader(gltf: any, bin: buffer, binOffset: number, index: number): (number, number, Reader)
	local acc = gltf.accessors[index + 1]
	if acc == nil then
		error('missing accessor ' .. index, 0)
	end
	if acc.sparse then
		error('sparse accessors are not supported', 0)
	end
	local count = acc.count
	local n = COMPONENTS[acc.type] or 1
	local ctype = acc.componentType
	local csize = COMPONENT_SIZE[ctype]
	if csize == nil then
		error('unknown componentType ' .. tostring(ctype), 0)
	end
	local normalized = acc.normalized == true

	if acc.bufferView == nil then
		-- No data: all zeros (allowed by the spec).
		return count, n, function(_i: number, _k: number): number
			return 0
		end
	end

	local view = gltf.bufferViews[acc.bufferView + 1]
	if (view.buffer or 0) ~= 0 then
		error('only the GLB binary buffer (buffer 0) is supported', 0)
	end
	local stride = view.byteStride or (n * csize)
	local base = binOffset + (view.byteOffset or 0) + (acc.byteOffset or 0)

	local function read(o: number): number
		if ctype == 5126 then
			return buffer.readf32(bin, o)
		elseif ctype == 5125 then
			return buffer.readu32(bin, o)
		elseif ctype == 5123 then
			local v = buffer.readu16(bin, o)
			return if normalized then v / 65535 else v
		elseif ctype == 5122 then
			local v = buffer.readi16(bin, o)
			return if normalized then math.max(v / 32767, -1) else v
		elseif ctype == 5121 then
			local v = buffer.readu8(bin, o)
			return if normalized then v / 255 else v
		else -- 5120
			local v = buffer.readi8(bin, o)
			return if normalized then math.max(v / 127, -1) else v
		end
	end

	return count, n, function(i: number, k: number): number
		return read(base + i * stride + k * csize)
	end
end

-- ---------------------------------------------------------------------------
-- Parse
-- ---------------------------------------------------------------------------

local function linearColor(f: { number }?, n: number, default: number): { number }
	local out = table.create(n, default)
	if f then
		for i = 1, n do
			out[i] = f[i] or default
		end
	end
	return out
end

local function readMaterial(gltf: any, index: number?): Material
	local m = if index ~= nil and gltf.materials then gltf.materials[index + 1] else nil
	m = m or {}
	local pbr = m.pbrMetallicRoughness or {}
	local imageIndex: number? = nil
	if pbr.baseColorTexture and gltf.textures then
		local tex = gltf.textures[pbr.baseColorTexture.index + 1]
		if tex and tex.source ~= nil then
			imageIndex = tex.source
		end
	end
	return {
		name = m.name or 'default',
		baseColor = linearColor(pbr.baseColorFactor, 4, 1),
		metallic = if pbr.metallicFactor ~= nil then pbr.metallicFactor else 1,
		roughness = if pbr.roughnessFactor ~= nil then pbr.roughnessFactor else 1,
		emissive = linearColor(m.emissiveFactor, 3, 0),
		baseColorImage = imageIndex,
		doubleSided = m.doubleSided == true,
		alphaBlend = m.alphaMode == 'BLEND',
	}
end

local function buildPrimitive(gltf: any, bin: buffer, binOffset: number, prim: any, world: { number }, nm: { number }): Primitive?
	local mode = if prim.mode ~= nil then prim.mode else 4
	if mode ~= 4 then
		return nil -- only triangle lists
	end
	local attrs = prim.attributes
	if attrs.POSITION == nil then
		return nil
	end
	if prim.extensions and (prim.extensions.KHR_draco_mesh_compression or prim.extensions.EXT_meshopt_compression) then
		error('compressed meshes (Draco / meshopt) are not supported; re-export uncompressed', 0)
	end

	local vcount, _, getPos = accessorReader(gltf, bin, binOffset, attrs.POSITION)
	local getNrm: Reader? = nil
	if attrs.NORMAL ~= nil then
		local _, _, g = accessorReader(gltf, bin, binOffset, attrs.NORMAL)
		getNrm = g
	end
	local getUv: Reader? = nil
	if attrs.TEXCOORD_0 ~= nil then
		local _, _, g = accessorReader(gltf, bin, binOffset, attrs.TEXCOORD_0)
		getUv = g
	end

	-- Indices (generate 0..n-1 when the primitive is not indexed).
	local icount: number
	local getIdx: (i: number) -> number
	if prim.indices ~= nil then
		local c, _, g = accessorReader(gltf, bin, binOffset, prim.indices)
		icount = c
		getIdx = function(i)
			return g(i, 0)
		end
	else
		icount = vcount
		getIdx = function(i)
			return i
		end
	end

	local stride = GLB.VERTEX_STRIDE
	local verts = buffer.create(vcount * stride)
	local px = table.create(vcount, 0)
	local py = table.create(vcount, 0)
	local pz = table.create(vcount, 0)

	for i = 0, vcount - 1 do
		local x, y, z = getPos(i, 0), getPos(i, 1), getPos(i, 2)
		local wx = world[1] * x + world[5] * y + world[9] * z + world[13]
		local wy = world[2] * x + world[6] * y + world[10] * z + world[14]
		local wz = world[3] * x + world[7] * y + world[11] * z + world[15]
		px[i + 1], py[i + 1], pz[i + 1] = wx, wy, wz
		local o = i * stride
		buffer.writef32(verts, o, wx)
		buffer.writef32(verts, o + 4, wy)
		buffer.writef32(verts, o + 8, wz)
		if getNrm then
			local nx, ny, nz = getNrm(i, 0), getNrm(i, 1), getNrm(i, 2)
			local tx = nm[1] * nx + nm[4] * ny + nm[7] * nz
			local ty = nm[2] * nx + nm[5] * ny + nm[8] * nz
			local tz = nm[3] * nx + nm[6] * ny + nm[9] * nz
			local l = math.sqrt(tx * tx + ty * ty + tz * tz)
			if l > 0 then
				tx, ty, tz = tx / l, ty / l, tz / l
			end
			buffer.writef32(verts, o + 12, tx)
			buffer.writef32(verts, o + 16, ty)
			buffer.writef32(verts, o + 20, tz)
		end
		if getUv then
			buffer.writef32(verts, o + 24, getUv(i, 0))
			buffer.writef32(verts, o + 28, getUv(i, 1))
		end
	end

	-- Flip winding if the node transform mirrors the mesh.
	local det = world[1] * (world[6] * world[11] - world[10] * world[7])
		- world[5] * (world[2] * world[11] - world[10] * world[3])
		+ world[9] * (world[2] * world[7] - world[6] * world[3])
	local flip = det < 0

	local idx = buffer.create(icount * 4)
	for t = 0, icount - 1, 3 do
		local a, b, c = getIdx(t), getIdx(t + 1), getIdx(t + 2)
		if flip then
			b, c = c, b
		end
		buffer.writeu32(idx, t * 4, a)
		buffer.writeu32(idx, t * 4 + 4, b)
		buffer.writeu32(idx, t * 4 + 8, c)
	end

	-- Smooth normals when the file has none.
	if getNrm == nil then
		local nx = table.create(vcount, 0)
		local ny = table.create(vcount, 0)
		local nz = table.create(vcount, 0)
		for t = 0, icount - 1, 3 do
			local a = buffer.readu32(idx, t * 4) + 1
			local b = buffer.readu32(idx, t * 4 + 4) + 1
			local c = buffer.readu32(idx, t * 4 + 8) + 1
			local ux, uy, uz = px[b] - px[a], py[b] - py[a], pz[b] - pz[a]
			local vx, vy, vz = px[c] - px[a], py[c] - py[a], pz[c] - pz[a]
			local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
			for _, k in { a, b, c } do
				nx[k] += fx
				ny[k] += fy
				nz[k] += fz
			end
		end
		for i = 1, vcount do
			local l = math.sqrt(nx[i] * nx[i] + ny[i] * ny[i] + nz[i] * nz[i])
			if l == 0 then
				l = 1
			end
			local o = (i - 1) * stride
			buffer.writef32(verts, o + 12, nx[i] / l)
			buffer.writef32(verts, o + 16, ny[i] / l)
			buffer.writef32(verts, o + 20, nz[i] / l)
		end
	end

	return {
		meshIndex = -1,
		meshName = '',
		nodeName = '',
		vertices = verts,
		vertexCount = vcount,
		indices = idx,
		indexCount = icount,
		material = readMaterial(gltf, prim.material),
		_px = px,
		_py = py,
		_pz = pz,
	} :: any
end

export type Options = {
	-- false keeps every primitive in its mesh's own space (node transforms
	-- are not applied); bounds are then over those local positions.
	bakeTransforms: boolean?,
}

-- Parses GLB bytes. Returns the model, or nil and an error message.
function GLB.parse(data: buffer, options: Options?): (Model?, string?)
	local bake = options == nil or options.bakeTransforms ~= false
	local ok, result = pcall(function(): Model
		local size = buffer.len(data)
		if size < 20 or buffer.readu32(data, 0) ~= 0x46546C67 then
			error('not a GLB file (bad magic); only binary .glb is supported', 0)
		end
		if buffer.readu32(data, 4) ~= 2 then
			error('unsupported glTF version ' .. buffer.readu32(data, 4), 0)
		end

		-- Chunks: JSON first, then an optional BIN.
		local offset = 12
		local jsonText: string? = nil
		local binOffset = -1
		while offset + 8 <= size do
			local clen = buffer.readu32(data, offset)
			local ctype = buffer.readu32(data, offset + 4)
			if ctype == 0x4E4F534A then
				jsonText = buffer.readstring(data, offset + 8, clen)
			elseif ctype == 0x004E4942 and binOffset < 0 then
				binOffset = offset + 8
			end
			offset += 8 + clen
		end
		if jsonText == nil then
			error('GLB has no JSON chunk', 0)
		end
		local gltf = decodeJson(jsonText)

		local model: Model = {
			primitives = {},
			images = {},
			min = { math.huge, math.huge, math.huge },
			max = { -math.huge, -math.huge, -math.huge },
			center = { 0, 0, 0 },
			radius = 1,
			vertexCount = 0,
			triangleCount = 0,
		}

		local function visit(nodeIndex: number, parent: { number })
			local node = gltf.nodes[nodeIndex + 1]
			local localM = if node.matrix then node.matrix else fromTRS(node.translation, node.rotation, node.scale)
			local world = mul(parent, localM)
			if node.mesh ~= nil then
				local mesh = gltf.meshes[node.mesh + 1]
				local placed = if bake then world else identity()
				local nm = normalMatrix(placed)
				for _, prim in mesh.primitives do
					local p = buildPrimitive(gltf, data, binOffset, prim, placed, nm)
					if p then
						p.meshIndex = node.mesh
						p.meshName = mesh.name or ''
						p.nodeName = node.name or ''
						table.insert(model.primitives, p)
					end
				end
			end
			if node.children then
				for _, child in node.children do
					visit(child, world)
				end
			end
		end

		local roots: { number }
		local sceneIndex = gltf.scene or 0
		if gltf.scenes and gltf.scenes[sceneIndex + 1] then
			roots = gltf.scenes[sceneIndex + 1].nodes or {}
		else
			-- No scene: treat every node without a parent as a root.
			local isChild = {}
			for _, n in gltf.nodes or {} do
				for _, c in n.children or {} do
					isChild[c] = true
				end
			end
			roots = {}
			for i = 0, #(gltf.nodes or {}) - 1 do
				if not isChild[i] then
					table.insert(roots, i)
				end
			end
		end
		for _, r in roots do
			visit(r, identity())
		end
		if #model.primitives == 0 then
			error('no triangle meshes found', 0)
		end

		-- Bounds, then a bounding sphere around the box centre.
		local mn, mx = model.min, model.max
		for _, p in model.primitives :: { any } do
			for i = 1, p.vertexCount do
				local x, y, z = p._px[i], p._py[i], p._pz[i]
				mn[1], mn[2], mn[3] = math.min(mn[1], x), math.min(mn[2], y), math.min(mn[3], z)
				mx[1], mx[2], mx[3] = math.max(mx[1], x), math.max(mx[2], y), math.max(mx[3], z)
			end
			model.vertexCount += p.vertexCount
			model.triangleCount += p.indexCount // 3
		end
		local cx, cy, cz = (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2, (mn[3] + mx[3]) / 2
		local r2 = 0
		for _, p in model.primitives :: { any } do
			for i = 1, p.vertexCount do
				local dx, dy, dz = p._px[i] - cx, p._py[i] - cy, p._pz[i] - cz
				r2 = math.max(r2, dx * dx + dy * dy + dz * dz)
			end
			p._px, p._py, p._pz = nil, nil, nil
		end
		model.center = { cx, cy, cz }
		model.radius = math.max(math.sqrt(r2), 1e-6)

		-- Images stored in the BIN chunk.
		for _, img in gltf.images or {} do
			if img.bufferView ~= nil then
				local view = gltf.bufferViews[img.bufferView + 1]
				local bytes = buffer.create(view.byteLength)
				buffer.copy(bytes, 0, data, binOffset + (view.byteOffset or 0), view.byteLength)
				table.insert(model.images, { data = bytes, mimeType = img.mimeType or '' })
			else
				-- External or data-URI images are skipped; keep indices aligned.
				table.insert(model.images, { data = buffer.create(0), mimeType = '' })
			end
		end

		return model
	end)
	if ok then
		return result, nil
	end
	return nil, tostring(result)
end

return GLB
