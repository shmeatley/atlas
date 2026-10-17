--!strict
--!native
--!optimize 2

local Permutation = require(script.Parent.Permutation)

local band = bit32.band
local floor = math.floor
local random = math.random
local readu8 = buffer.readu8
local readf64 = buffer.readf64
local writef64 = buffer.writef64

-- Unit-length gradients keep the theoretical output range at exactly
-- ±sqrt(N)/2, so these constants rescale to [-1, 1].
local NORM2 = 1.4142135623730951
local NORM3 = 1.1547005383792515

local GRAD2 = buffer.create(128)
local GRAD3 = buffer.create(288)

do
	local s = 0.7071067811865476
	local grad2 = { 1, 0, -1, 0, 0, 1, 0, -1, s, s, -s, s, s, -s, -s, -s }
	for i = 0, 7 do
		writef64(GRAD2, i * 16, grad2[i * 2 + 1])
		writef64(GRAD2, i * 16 + 8, grad2[i * 2 + 2])
	end

	-- stylua: ignore
	local grad3 = {
		s, s, 0, -s, s, 0, s, -s, 0, -s, -s, 0,
		s, 0, s, -s, 0, s, s, 0, -s, -s, 0, -s,
		0, s, s, 0, -s, s, 0, s, -s, 0, -s, -s,
	}
	for i = 0, 11 do
		writef64(GRAD3, i * 24, grad3[i * 3 + 1])
		writef64(GRAD3, i * 24 + 8, grad3[i * 3 + 2])
		writef64(GRAD3, i * 24 + 16, grad3[i * 3 + 3])
	end
end

--[=[
	@class Perlin

	Seeded improved Perlin noise. Construct one sampler per seed; the permutation
	table is built once and every sample reuses it.

	```lua
	local perlin = Atlas.Noise.Perlin.new(42)
	local height = perlin:sample2D(x * 0.01, z * 0.01)
	```
]=]
local Perlin = {}
Perlin.__index = Perlin

export type Perlin = typeof(setmetatable({} :: { seed: number, _perm: buffer, _grad2: buffer, _grad3: buffer }, Perlin))

--[=[
	@prop seed number
	@within Perlin
	@readonly
	The seed this sampler was constructed with.
]=]

--[=[
	Creates a new Perlin sampler. Equal seeds always produce identical noise.

	@function new
	@within Perlin
	@param seed number? -- Any number. Defaults to a random seed.
	@return Perlin
]=]
function Perlin.new(seed: number?): Perlin
	local resolved = seed or random(1, 2147483646)
	local perm = Permutation.build(resolved)
	return setmetatable({
		seed = resolved,
		_perm = perm,
		_grad2 = Permutation.gradients(perm, GRAD2, 16, 8),
		_grad3 = Permutation.gradients(perm, GRAD3, 24, 12),
	}, Perlin)
end

--[=[
	Samples 2D Perlin noise.

	@method sample2D
	@within Perlin
	@param x number
	@param y number
	@return number -- Noise value in [-1, 1].
]=]
function Perlin.sample2D(self: Perlin, x: number, y: number): number
	local perm = self._perm
	local gradients = self._grad2

	local fx = floor(x)
	local fy = floor(y)
	local xf = x - fx
	local yf = y - fy
	local xf1 = xf - 1
	local yf1 = yf - 1

	local X = band(fx, 255)
	local Y = band(fy, 255)
	local a = readu8(perm, X) + Y
	local b = readu8(perm, X + 1) + Y

	local i00 = a * 16
	local i01 = (a + 1) * 16
	local i10 = b * 16
	local i11 = (b + 1) * 16

	local n00 = readf64(gradients, i00) * xf + readf64(gradients, i00 + 8) * yf
	local n10 = readf64(gradients, i10) * xf1 + readf64(gradients, i10 + 8) * yf
	local n01 = readf64(gradients, i01) * xf + readf64(gradients, i01 + 8) * yf1
	local n11 = readf64(gradients, i11) * xf1 + readf64(gradients, i11 + 8) * yf1

	local u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
	local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)

	local nx0 = n00 + u * (n10 - n00)
	local nx1 = n01 + u * (n11 - n01)
	return (nx0 + v * (nx1 - nx0)) * NORM2
end

--[=[
	Samples 2D Perlin noise along with its analytical derivative — the exact
	slope of the noise field, with no extra noise samples.

	@method sample2DWithDerivative
	@within Perlin
	@param x number
	@param y number
	@return number -- Noise value in [-1, 1].
	@return number -- d/dx.
	@return number -- d/dy.
]=]
function Perlin.sample2DWithDerivative(self: Perlin, x: number, y: number): (number, number, number)
	local perm = self._perm
	local gradients = self._grad2

	local fx = floor(x)
	local fy = floor(y)
	local xf = x - fx
	local yf = y - fy
	local xf1 = xf - 1
	local yf1 = yf - 1

	local a = readu8(perm, band(fx, 255)) + band(fy, 255)
	local b = readu8(perm, band(fx, 255) + 1) + band(fy, 255)

	local i00 = a * 16
	local i01 = (a + 1) * 16
	local i10 = b * 16
	local i11 = (b + 1) * 16

	local g00x, g00y = readf64(gradients, i00), readf64(gradients, i00 + 8)
	local g10x, g10y = readf64(gradients, i10), readf64(gradients, i10 + 8)
	local g01x, g01y = readf64(gradients, i01), readf64(gradients, i01 + 8)
	local g11x, g11y = readf64(gradients, i11), readf64(gradients, i11 + 8)

	local n00 = g00x * xf + g00y * yf
	local n10 = g10x * xf1 + g10y * yf
	local n01 = g01x * xf + g01y * yf1
	local n11 = g11x * xf1 + g11y * yf1

	local u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
	local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
	local du = 30 * xf * xf * (xf - 1) * (xf - 1)
	local dv = 30 * yf * yf * (yf - 1) * (yf - 1)

	local k1 = n10 - n00
	local k2 = n01 - n00
	local k3 = n00 - n10 - n01 + n11
	local uv = u * v

	local value = n00 + u * k1 + v * k2 + uv * k3
	local gx = g00x + u * (g10x - g00x) + v * (g01x - g00x) + uv * (g00x - g10x - g01x + g11x)
	local gy = g00y + u * (g10y - g00y) + v * (g01y - g00y) + uv * (g00y - g10y - g01y + g11y)

	local dx = gx + du * (k1 + v * k3)
	local dy = gy + dv * (k2 + u * k3)
	return value * NORM2, dx * NORM2, dy * NORM2
end

--[=[
	Samples 3D Perlin noise.

	@method sample3D
	@within Perlin
	@param x number
	@param y number
	@param z number
	@return number -- Noise value in [-1, 1].
]=]
function Perlin.sample3D(self: Perlin, x: number, y: number, z: number): number
	local perm = self._perm
	local gradients = self._grad3

	local fx = floor(x)
	local fy = floor(y)
	local fz = floor(z)
	local xf = x - fx
	local yf = y - fy
	local zf = z - fz
	local xf1 = xf - 1
	local yf1 = yf - 1
	local zf1 = zf - 1

	local X = band(fx, 255)
	local Y = band(fy, 255)
	local Z = band(fz, 255)

	local a = readu8(perm, X) + Y
	local b = readu8(perm, X + 1) + Y
	local aa = readu8(perm, a) + Z
	local ab = readu8(perm, a + 1) + Z
	local ba = readu8(perm, b) + Z
	local bb = readu8(perm, b + 1) + Z

	-- Consume each corner immediately to keep native register pressure low.
	local i000 = aa * 24
	local n000 = readf64(gradients, i000) * xf + readf64(gradients, i000 + 8) * yf + readf64(gradients, i000 + 16) * zf
	local i100 = ba * 24
	local n100 = readf64(gradients, i100) * xf1 + readf64(gradients, i100 + 8) * yf + readf64(gradients, i100 + 16) * zf
	local i010 = ab * 24
	local n010 = readf64(gradients, i010) * xf + readf64(gradients, i010 + 8) * yf1 + readf64(gradients, i010 + 16) * zf
	local i110 = bb * 24
	local n110 = readf64(gradients, i110) * xf1
		+ readf64(gradients, i110 + 8) * yf1
		+ readf64(gradients, i110 + 16) * zf
	local i001 = (aa + 1) * 24
	local n001 = readf64(gradients, i001) * xf + readf64(gradients, i001 + 8) * yf + readf64(gradients, i001 + 16) * zf1
	local i101 = (ba + 1) * 24
	local n101 = readf64(gradients, i101) * xf1
		+ readf64(gradients, i101 + 8) * yf
		+ readf64(gradients, i101 + 16) * zf1
	local i011 = (ab + 1) * 24
	local n011 = readf64(gradients, i011) * xf
		+ readf64(gradients, i011 + 8) * yf1
		+ readf64(gradients, i011 + 16) * zf1
	local i111 = (bb + 1) * 24
	local n111 = readf64(gradients, i111) * xf1
		+ readf64(gradients, i111 + 8) * yf1
		+ readf64(gradients, i111 + 16) * zf1

	local u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
	local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
	local w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)

	local nx00 = n000 + u * (n100 - n000)
	local nx10 = n010 + u * (n110 - n010)
	local nx01 = n001 + u * (n101 - n001)
	local nx11 = n011 + u * (n111 - n011)
	local nxy0 = nx00 + v * (nx10 - nx00)
	local nxy1 = nx01 + v * (nx11 - nx01)
	return (nxy0 + w * (nxy1 - nxy0)) * NORM3
end

--[=[
	Samples 3D Perlin noise along with its analytical derivative.

	@method sample3DWithDerivative
	@within Perlin
	@param x number
	@param y number
	@param z number
	@return number -- Noise value in [-1, 1].
	@return number -- d/dx.
	@return number -- d/dy.
	@return number -- d/dz.
]=]
function Perlin.sample3DWithDerivative(self: Perlin, x: number, y: number, z: number): (number, number, number, number)
	local perm = self._perm
	local gradients = self._grad3

	local fx = floor(x)
	local fy = floor(y)
	local fz = floor(z)
	local xf = x - fx
	local yf = y - fy
	local zf = z - fz
	local xf1 = xf - 1
	local yf1 = yf - 1
	local zf1 = zf - 1

	local X = band(fx, 255)
	local Y = band(fy, 255)
	local Z = band(fz, 255)

	local a = readu8(perm, X) + Y
	local b = readu8(perm, X + 1) + Y
	local aa = readu8(perm, a) + Z
	local ab = readu8(perm, a + 1) + Z
	local ba = readu8(perm, b) + Z
	local bb = readu8(perm, b + 1) + Z

	local i000 = aa * 24
	local i100 = ba * 24
	local i010 = ab * 24
	local i110 = bb * 24
	local i001 = (aa + 1) * 24
	local i101 = (ba + 1) * 24
	local i011 = (ab + 1) * 24
	local i111 = (bb + 1) * 24

	local g000x, g000y, g000z = readf64(gradients, i000), readf64(gradients, i000 + 8), readf64(gradients, i000 + 16)
	local g100x, g100y, g100z = readf64(gradients, i100), readf64(gradients, i100 + 8), readf64(gradients, i100 + 16)
	local g010x, g010y, g010z = readf64(gradients, i010), readf64(gradients, i010 + 8), readf64(gradients, i010 + 16)
	local g110x, g110y, g110z = readf64(gradients, i110), readf64(gradients, i110 + 8), readf64(gradients, i110 + 16)
	local g001x, g001y, g001z = readf64(gradients, i001), readf64(gradients, i001 + 8), readf64(gradients, i001 + 16)
	local g101x, g101y, g101z = readf64(gradients, i101), readf64(gradients, i101 + 8), readf64(gradients, i101 + 16)
	local g011x, g011y, g011z = readf64(gradients, i011), readf64(gradients, i011 + 8), readf64(gradients, i011 + 16)
	local g111x, g111y, g111z = readf64(gradients, i111), readf64(gradients, i111 + 8), readf64(gradients, i111 + 16)

	local n000 = g000x * xf + g000y * yf + g000z * zf
	local n100 = g100x * xf1 + g100y * yf + g100z * zf
	local n010 = g010x * xf + g010y * yf1 + g010z * zf
	local n110 = g110x * xf1 + g110y * yf1 + g110z * zf
	local n001 = g001x * xf + g001y * yf + g001z * zf1
	local n101 = g101x * xf1 + g101y * yf + g101z * zf1
	local n011 = g011x * xf + g011y * yf1 + g011z * zf1
	local n111 = g111x * xf1 + g111y * yf1 + g111z * zf1

	local u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
	local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
	local w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
	local du = 30 * xf * xf * (xf - 1) * (xf - 1)
	local dv = 30 * yf * yf * (yf - 1) * (yf - 1)
	local dw = 30 * zf * zf * (zf - 1) * (zf - 1)

	local b1 = n100 - n000
	local b2 = n010 - n000
	local b3 = n001 - n000
	local b4 = n110 - n100 - n010 + n000
	local b5 = n101 - n100 - n001 + n000
	local b6 = n011 - n010 - n001 + n000
	local b7 = n111 - n110 - n101 - n011 + n100 + n010 + n001 - n000

	local uv = u * v
	local uw = u * w
	local vw = v * w
	local uvw = uv * w

	local value = n000 + u * b1 + v * b2 + w * b3 + uv * b4 + uw * b5 + vw * b6 + uvw * b7

	local gx00 = g000x + u * (g100x - g000x)
	local gx10 = g010x + u * (g110x - g010x)
	local gx01 = g001x + u * (g101x - g001x)
	local gx11 = g011x + u * (g111x - g011x)
	local gx0 = gx00 + v * (gx10 - gx00)
	local gx1 = gx01 + v * (gx11 - gx01)
	local gx = gx0 + w * (gx1 - gx0)

	local gy00 = g000y + u * (g100y - g000y)
	local gy10 = g010y + u * (g110y - g010y)
	local gy01 = g001y + u * (g101y - g001y)
	local gy11 = g011y + u * (g111y - g011y)
	local gy0 = gy00 + v * (gy10 - gy00)
	local gy1 = gy01 + v * (gy11 - gy01)
	local gy = gy0 + w * (gy1 - gy0)

	local gz00 = g000z + u * (g100z - g000z)
	local gz10 = g010z + u * (g110z - g010z)
	local gz01 = g001z + u * (g101z - g001z)
	local gz11 = g011z + u * (g111z - g011z)
	local gz0 = gz00 + v * (gz10 - gz00)
	local gz1 = gz01 + v * (gz11 - gz01)
	local gz = gz0 + w * (gz1 - gz0)

	local dx = gx + du * (b1 + v * b4 + w * b5 + vw * b7)
	local dy = gy + dv * (b2 + u * b4 + w * b6 + uw * b7)
	local dz = gz + dw * (b3 + u * b5 + v * b6 + uv * b7)
	return value * NORM3, dx * NORM3, dy * NORM3, dz * NORM3
end

-- Sample a row-major rectangular grid with exact scalar-sampling coordinates.
local function sampleGrid2DUncached(
	self: Perlin,
	width: number,
	height: number,
	startX: number,
	startY: number,
	stepX: number,
	stepY: number
): { number }
	assert(width >= 0 and width % 1 == 0, "width must be a non-negative integer")
	assert(height >= 0 and height % 1 == 0, "height must be a non-negative integer")
	local values: { number } = table.create(width * height)
	if width == 0 or height == 0 then
		return values
	end
	local perm = self._perm
	local gradients = self._grad2
	local columns = buffer.create(width * 24)
	for column = 0, width - 1 do
		local x = startX + column * stepX
		local fx = floor(x)
		local xf = x - fx
		local X = band(fx, 255)
		local offset = column * 24
		writef64(columns, offset, xf)
		writef64(columns, offset + 8, xf * xf * xf * (xf * (xf * 6 - 15) + 10))
		buffer.writeu8(columns, offset + 16, readu8(perm, X))
		buffer.writeu8(columns, offset + 17, readu8(perm, X + 1))
	end
	local index = 0
	for row = 0, height - 1 do
		local y = startY + row * stepY
		local fy = floor(y)
		local yf = y - fy
		local yf1 = yf - 1
		local Y = band(fy, 255)
		local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
		for column = 0, width - 1 do
			local offset = column * 24
			local xf = readf64(columns, offset)
			local xf1 = xf - 1
			local u = readf64(columns, offset + 8)
			local a = readu8(columns, offset + 16) + Y
			local b = readu8(columns, offset + 17) + Y
			local i00 = a * 16
			local i01 = (a + 1) * 16
			local i10 = b * 16
			local i11 = (b + 1) * 16
			local n00 = readf64(gradients, i00) * xf + readf64(gradients, i00 + 8) * yf
			local n10 = readf64(gradients, i10) * xf1 + readf64(gradients, i10 + 8) * yf
			local n01 = readf64(gradients, i01) * xf + readf64(gradients, i01 + 8) * yf1
			local n11 = readf64(gradients, i11) * xf1 + readf64(gradients, i11 + 8) * yf1
			local nx0 = n00 + u * (n10 - n00)
			local nx1 = n01 + u * (n11 - n01)
			index += 1
			values[index] = (nx0 + v * (nx1 - nx0)) * NORM2
		end
	end
	return values
end

--[=[
 Samples a rectangular grid into a new row-major array. Entry
 `row * width + column + 1` is exactly `sample2D(startX + column * stepX,
 startY + row * stepY)` for zero-based rows and columns. Negative and zero
 steps are supported. Width and height must be non-negative integers.

 Reuses column coordinates and row fades; dense grids also reuse gradients
 within a lattice cell. Scratch storage is 24 bytes per column. This is a
 bulk throughput API; individual sample2D calls retain their existing behavior.

 @method sampleGrid2D
 @within Perlin
 @param width number -- Number of columns.
 @param height number -- Number of rows.
 @param startX number
 @param startY number
 @param stepX number
 @param stepY number
 @return {number} -- Row-major samples.
]=]
function Perlin.sampleGrid2D(
	self: Perlin,
	width: number,
	height: number,
	startX: number,
	startY: number,
	stepX: number,
	stepY: number
): { number }
	if width < 32 or math.abs(stepX) >= 0.25 then
		return sampleGrid2DUncached(self, width, height, startX, startY, stepX, stepY)
	end
	assert(width >= 0 and width % 1 == 0, "width must be a non-negative integer")
	assert(height >= 0 and height % 1 == 0, "height must be a non-negative integer")
	local values: { number } = table.create(width * height)
	if width == 0 or height == 0 then
		return values
	end
	local perm = self._perm
	local gradients = self._grad2
	local columns = buffer.create(width * 24)
	for column = 0, width - 1 do
		local x = startX + column * stepX
		local fx = floor(x)
		local xf = x - fx
		local X = band(fx, 255)
		local offset = column * 24
		writef64(columns, offset, xf)
		writef64(columns, offset + 8, xf * xf * xf * (xf * (xf * 6 - 15) + 10))
		buffer.writeu8(columns, offset + 16, readu8(perm, X))
		buffer.writeu8(columns, offset + 17, readu8(perm, X + 1))
	end
	local index = 0
	for row = 0, height - 1 do
		local y = startY + row * stepY
		local fy = floor(y)
		local yf = y - fy
		local yf1 = yf - 1
		local Y = band(fy, 255)
		local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
		local previousA = -1
		local g00x, g10x, g01x, g11x = 0, 0, 0, 0
		local ny00, ny10, ny01, ny11 = 0, 0, 0, 0
		for column = 0, width - 1 do
			local offset = column * 24
			local xf = readf64(columns, offset)
			local xf1 = xf - 1
			local u = readf64(columns, offset + 8)
			local a = readu8(columns, offset + 16) + Y
			local b = readu8(columns, offset + 17) + Y
			if a ~= previousA then
				previousA = a
				local i00 = a * 16
				local i01 = (a + 1) * 16
				local i10 = b * 16
				local i11 = (b + 1) * 16
				g00x = readf64(gradients, i00)
				g10x = readf64(gradients, i10)
				g01x = readf64(gradients, i01)
				g11x = readf64(gradients, i11)
				ny00 = readf64(gradients, i00 + 8) * yf
				ny10 = readf64(gradients, i10 + 8) * yf
				ny01 = readf64(gradients, i01 + 8) * yf1
				ny11 = readf64(gradients, i11 + 8) * yf1
			end
			local n00 = g00x * xf + ny00
			local n10 = g10x * xf1 + ny10
			local n01 = g01x * xf + ny01
			local n11 = g11x * xf1 + ny11
			local nx0 = n00 + u * (n10 - n00)
			local nx1 = n01 + u * (n11 - n01)
			index += 1
			values[index] = (nx0 + v * (nx1 - nx0)) * NORM2
		end
	end
	return values
end

--[=[
 Samples a rectangular grid into a new flat volume (X fastest, then Y, then Z).
 Coordinates use start + zero-based index * step on each axis, exactly as
 repeated sample3D calls. Negative and zero steps are supported. Dimensions
 must be non-negative integers; any zero dimension returns an empty array.
 Array index: `(slice * height + row) * width + column + 1`.

 @method sampleGrid3D
 @within Perlin
 @param width number -- X samples.
 @param height number -- Y samples.
 @param depth number -- Z samples.
 @param startX number
 @param startY number
 @param startZ number
 @param stepX number
 @param stepY number
 @param stepZ number
 @return {number} -- Samples in grid order.
]=]
function Perlin.sampleGrid3D(
	self: Perlin,
	width: number,
	height: number,
	depth: number,
	startX: number,
	startY: number,
	startZ: number,
	stepX: number,
	stepY: number,
	stepZ: number
): { number }
	assert(width >= 0 and width % 1 == 0, "width must be a non-negative integer")
	assert(height >= 0 and height % 1 == 0, "height must be a non-negative integer")
	assert(depth >= 0 and depth % 1 == 0, "depth must be a non-negative integer")
	local values: { number } = table.create(width * height * depth)
	if width * height * depth == 0 then
		return values
	end
	local perm = self._perm
	local gradients = self._grad3
	local columns = buffer.create(width * 24)
	for column = 0, width - 1 do
		local x = startX + column * stepX
		local fx = floor(x)
		local xf = x - fx
		local X = band(fx, 255)
		local offset = column * 24
		writef64(columns, offset, xf)
		writef64(columns, offset + 8, xf * xf * xf * (xf * (xf * 6 - 15) + 10))
		buffer.writeu8(columns, offset + 16, readu8(perm, X))
		buffer.writeu8(columns, offset + 17, readu8(perm, X + 1))
	end
	local index = 0
	for slice = 0, depth - 1 do
		local z = startZ + slice * stepZ
		local fz = floor(z)
		local zf = z - fz
		local zf1 = zf - 1
		local Z = band(fz, 255)
		local w = zf * zf * zf * (zf * (zf * 6 - 15) + 10)
		for row = 0, height - 1 do
			local y = startY + row * stepY
			local fy = floor(y)
			local yf = y - fy
			local yf1 = yf - 1
			local Y = band(fy, 255)
			local v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
			for column = 0, width - 1 do
				index += 1
				local offset = column * 24
				local xf = readf64(columns, offset)
				local u = readf64(columns, offset + 8)
				local xf1 = xf - 1

				local a = readu8(columns, offset + 16) + Y
				local b = readu8(columns, offset + 17) + Y
				local aa = readu8(perm, a) + Z
				local ab = readu8(perm, a + 1) + Z
				local ba = readu8(perm, b) + Z
				local bb = readu8(perm, b + 1) + Z

				-- Consume each corner immediately to keep native register pressure low.
				local i000 = aa * 24
				local n000 = readf64(gradients, i000) * xf
					+ readf64(gradients, i000 + 8) * yf
					+ readf64(gradients, i000 + 16) * zf
				local i100 = ba * 24
				local n100 = readf64(gradients, i100) * xf1
					+ readf64(gradients, i100 + 8) * yf
					+ readf64(gradients, i100 + 16) * zf
				local i010 = ab * 24
				local n010 = readf64(gradients, i010) * xf
					+ readf64(gradients, i010 + 8) * yf1
					+ readf64(gradients, i010 + 16) * zf
				local i110 = bb * 24
				local n110 = readf64(gradients, i110) * xf1
					+ readf64(gradients, i110 + 8) * yf1
					+ readf64(gradients, i110 + 16) * zf
				local i001 = (aa + 1) * 24
				local n001 = readf64(gradients, i001) * xf
					+ readf64(gradients, i001 + 8) * yf
					+ readf64(gradients, i001 + 16) * zf1
				local i101 = (ba + 1) * 24
				local n101 = readf64(gradients, i101) * xf1
					+ readf64(gradients, i101 + 8) * yf
					+ readf64(gradients, i101 + 16) * zf1
				local i011 = (ab + 1) * 24
				local n011 = readf64(gradients, i011) * xf
					+ readf64(gradients, i011 + 8) * yf1
					+ readf64(gradients, i011 + 16) * zf1
				local i111 = (bb + 1) * 24
				local n111 = readf64(gradients, i111) * xf1
					+ readf64(gradients, i111 + 8) * yf1
					+ readf64(gradients, i111 + 16) * zf1

				local nx00 = n000 + u * (n100 - n000)
				local nx10 = n010 + u * (n110 - n010)
				local nx01 = n001 + u * (n101 - n001)
				local nx11 = n011 + u * (n111 - n011)
				local nxy0 = nx00 + v * (nx10 - nx00)
				local nxy1 = nx01 + v * (nx11 - nx01)
				values[index] = (nxy0 + w * (nxy1 - nxy0)) * NORM3
			end
		end
	end
	return values
end

return Perlin
