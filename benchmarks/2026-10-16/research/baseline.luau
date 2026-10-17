--!optimize 2
local Vector2 = {new = function(x,y) return vector.create(x,y,0) end}
local Vector3 = Vector2

local Permutation = (function()
--!strict
--!native
--!optimize 2

-- Seeded permutation tables and seed normalization
-- The Lehmer LCG (state * 48271 % 2147483647) stays well inside double precision,
-- so results are deterministic on every platform.

local floor = math.floor
local readu8 = buffer.readu8
local writeu8 = buffer.writeu8

local Permutation = {}

function Permutation.normalize(seed: number): number
	return floor(seed % 2147483646) + 1
end

function Permutation.build(seed: number): buffer
	local perm = buffer.create(512)
	for i = 0, 255 do
		writeu8(perm, i, i)
	end

	local state = Permutation.normalize(seed)
	for i = 255, 1, -1 do
		state = state * 48271 % 2147483647
		local j = state % (i + 1)
		local swap = readu8(perm, i)
		writeu8(perm, i, readu8(perm, j))
		writeu8(perm, j, swap)
	end

	-- Duplicate the shuffled 256 entries so nested lattice lookups like
	-- perm[perm[X] + Y] never need a wrap in the hot path.
	for i = 0, 255 do
		writeu8(perm, i + 256, readu8(perm, i))
	end

	return perm
end

-- Fold the final permutation lookup and gradient selection into seeded data.
-- Copy doubles verbatim so sampling retains exactly the original gradients.
function Permutation.gradients(perm: buffer, source: buffer, stride: number, count: number): buffer
	local expanded = buffer.create(512 * stride)
	for i = 0, 255 do
		buffer.copy(expanded, i * stride, source, (readu8(perm, i) % count) * stride, stride)
	end
	buffer.copy(expanded, 256 * stride, expanded, 0, 256 * stride)
	return expanded
end

return Permutation

end)()

local Perlin = (function()
--!strict
--!native
--!optimize 2

local Permutation = Permutation

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

return Perlin

end)()

local Simplex = (function()
--!strict
--!native
--!optimize 2

local Permutation = Permutation

local band = bit32.band
local floor = math.floor
local random = math.random
local readu8 = buffer.readu8
local readf64 = buffer.readf64
local writef64 = buffer.writef64

local F2 = 0.36602540378443865
local G2 = 0.21132486540518713
local G2_2 = 0.42264973081037427
local F3 = 0.3333333333333333
local G3 = 0.16666666666666666
local G3_2 = 0.3333333333333333

-- The 3D kernel radius is 0.5 rather than the classic 0.6: contributions then
-- vanish exactly on simplex boundaries, keeping the field C1-continuous and
-- the analytical derivatives exact. Scales are calibrated to those kernels.
local SCALE2 = 70
local SCALE3 = 100

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
	@class Simplex

	Seeded simplex noise. Cheaper than Perlin in higher dimensions and free of
	its axis-aligned artifacts. Output is approximately [-1, 1].

	```lua
	local simplex = Atlas.Noise.Simplex.new(42)
	local density = simplex:sample3D(x * 0.05, y * 0.05, z * 0.05)
	```
]=]
local Simplex = {}
Simplex.__index = Simplex

export type Simplex = typeof(setmetatable(
	{} :: { seed: number, _perm: buffer, _grad2: buffer, _grad3: buffer },
	Simplex
))

--[=[
	@prop seed number
	@within Simplex
	@readonly
	The seed this sampler was constructed with.
]=]

--[=[
	Creates a new simplex sampler. Equal seeds always produce identical noise.

	@function new
	@within Simplex
	@param seed number? -- Any number. Defaults to a random seed.
	@return Simplex
]=]
function Simplex.new(seed: number?): Simplex
	local resolved = seed or random(1, 2147483646)
	local perm = Permutation.build(resolved)
	return setmetatable({
		seed = resolved,
		_perm = perm,
		_grad2 = Permutation.gradients(perm, GRAD2, 16, 8),
		_grad3 = Permutation.gradients(perm, GRAD3, 24, 12),
	}, Simplex)
end

--[=[
	Samples 2D simplex noise.

	@method sample2D
	@within Simplex
	@param x number
	@param y number
	@return number -- Noise value in approximately [-1, 1].
]=]
function Simplex.sample2D(self: Simplex, x: number, y: number): number
	local perm = self._perm
	local gradients = self._grad2

	local skew = (x + y) * F2
	local i = floor(x + skew)
	local j = floor(y + skew)
	local unskew = (i + j) * G2
	local x0 = x - (i - unskew)
	local y0 = y - (j - unskew)

	local i1, j1
	if x0 > y0 then
		i1, j1 = 1, 0
	else
		i1, j1 = 0, 1
	end

	local x1 = x0 - i1 + G2
	local y1 = y0 - j1 + G2
	local x2 = x0 - 1 + G2_2
	local y2 = y0 - 1 + G2_2

	local ii = band(i, 255)
	local jj = band(j, 255)
	local gi0 = (ii + readu8(perm, jj)) * 16
	local gi1 = (ii + i1 + readu8(perm, jj + j1)) * 16
	local gi2 = (ii + 1 + readu8(perm, jj + 1)) * 16

	local n = 0

	local t0 = 0.5 - x0 * x0 - y0 * y0
	if t0 > 0 then
		local t02 = t0 * t0
		n += t02 * t02 * (readf64(gradients, gi0) * x0 + readf64(gradients, gi0 + 8) * y0)
	end

	local t1 = 0.5 - x1 * x1 - y1 * y1
	if t1 > 0 then
		local t12 = t1 * t1
		n += t12 * t12 * (readf64(gradients, gi1) * x1 + readf64(gradients, gi1 + 8) * y1)
	end

	local t2 = 0.5 - x2 * x2 - y2 * y2
	if t2 > 0 then
		local t22 = t2 * t2
		n += t22 * t22 * (readf64(gradients, gi2) * x2 + readf64(gradients, gi2 + 8) * y2)
	end

	return n * SCALE2
end

--[=[
	Samples 2D simplex noise along with its analytical derivative.

	@method sample2DWithDerivative
	@within Simplex
	@param x number
	@param y number
	@return number -- Noise value in approximately [-1, 1].
	@return number -- d/dx.
	@return number -- d/dy.
]=]
function Simplex.sample2DWithDerivative(self: Simplex, x: number, y: number): (number, number, number)
	local perm = self._perm
	local gradients = self._grad2

	local skew = (x + y) * F2
	local i = floor(x + skew)
	local j = floor(y + skew)
	local unskew = (i + j) * G2
	local x0 = x - (i - unskew)
	local y0 = y - (j - unskew)

	local i1, j1
	if x0 > y0 then
		i1, j1 = 1, 0
	else
		i1, j1 = 0, 1
	end

	local x1 = x0 - i1 + G2
	local y1 = y0 - j1 + G2
	local x2 = x0 - 1 + G2_2
	local y2 = y0 - 1 + G2_2

	local ii = band(i, 255)
	local jj = band(j, 255)
	local gi0 = (ii + readu8(perm, jj)) * 16
	local gi1 = (ii + i1 + readu8(perm, jj + j1)) * 16
	local gi2 = (ii + 1 + readu8(perm, jj + 1)) * 16

	local n, dx, dy = 0, 0, 0

	local t0 = 0.5 - x0 * x0 - y0 * y0
	if t0 > 0 then
		local gx, gy = readf64(gradients, gi0), readf64(gradients, gi0 + 8)
		local dot = gx * x0 + gy * y0
		local t03 = t0 * t0 * t0
		n += t03 * t0 * dot
		dx += t03 * (t0 * gx - 8 * x0 * dot)
		dy += t03 * (t0 * gy - 8 * y0 * dot)
	end

	local t1 = 0.5 - x1 * x1 - y1 * y1
	if t1 > 0 then
		local gx, gy = readf64(gradients, gi1), readf64(gradients, gi1 + 8)
		local dot = gx * x1 + gy * y1
		local t13 = t1 * t1 * t1
		n += t13 * t1 * dot
		dx += t13 * (t1 * gx - 8 * x1 * dot)
		dy += t13 * (t1 * gy - 8 * y1 * dot)
	end

	local t2 = 0.5 - x2 * x2 - y2 * y2
	if t2 > 0 then
		local gx, gy = readf64(gradients, gi2), readf64(gradients, gi2 + 8)
		local dot = gx * x2 + gy * y2
		local t23 = t2 * t2 * t2
		n += t23 * t2 * dot
		dx += t23 * (t2 * gx - 8 * x2 * dot)
		dy += t23 * (t2 * gy - 8 * y2 * dot)
	end

	return n * SCALE2, dx * SCALE2, dy * SCALE2
end

--[=[
	Samples 3D simplex noise.

	@method sample3D
	@within Simplex
	@param x number
	@param y number
	@param z number
	@return number -- Noise value in approximately [-1, 1].
]=]
function Simplex.sample3D(self: Simplex, x: number, y: number, z: number): number
	local perm = self._perm
	local gradients = self._grad3

	local skew = (x + y + z) * F3
	local i = floor(x + skew)
	local j = floor(y + skew)
	local k = floor(z + skew)
	local unskew = (i + j + k) * G3
	local x0 = x - (i - unskew)
	local y0 = y - (j - unskew)
	local z0 = z - (k - unskew)

	local i1, j1, k1, i2, j2, k2
	if x0 >= y0 then
		if y0 >= z0 then
			i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
		elseif x0 >= z0 then
			i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
		else
			i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1
		end
	else
		if y0 < z0 then
			i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
		elseif x0 < z0 then
			i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
		else
			i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0
		end
	end

	local x1 = x0 - i1 + G3
	local y1 = y0 - j1 + G3
	local z1 = z0 - k1 + G3
	local x2 = x0 - i2 + G3_2
	local y2 = y0 - j2 + G3_2
	local z2 = z0 - k2 + G3_2
	local x3 = x0 - 0.5
	local y3 = y0 - 0.5
	local z3 = z0 - 0.5

	local ii = band(i, 255)
	local jj = band(j, 255)
	local kk = band(k, 255)
	local gi0 = (ii + readu8(perm, jj + readu8(perm, kk))) * 24
	local gi1 = (ii + i1 + readu8(perm, jj + j1 + readu8(perm, kk + k1))) * 24
	local gi2 = (ii + i2 + readu8(perm, jj + j2 + readu8(perm, kk + k2))) * 24
	local gi3 = (ii + 1 + readu8(perm, jj + 1 + readu8(perm, kk + 1))) * 24

	local n = 0

	local t0 = 0.5 - x0 * x0 - y0 * y0 - z0 * z0
	if t0 > 0 then
		local t02 = t0 * t0
		n += t02 * t02 * (readf64(gradients, gi0) * x0 + readf64(gradients, gi0 + 8) * y0 + readf64(gradients, gi0 + 16) * z0)
	end

	local t1 = 0.5 - x1 * x1 - y1 * y1 - z1 * z1
	if t1 > 0 then
		local t12 = t1 * t1
		n += t12 * t12 * (readf64(gradients, gi1) * x1 + readf64(gradients, gi1 + 8) * y1 + readf64(gradients, gi1 + 16) * z1)
	end

	local t2 = 0.5 - x2 * x2 - y2 * y2 - z2 * z2
	if t2 > 0 then
		local t22 = t2 * t2
		n += t22 * t22 * (readf64(gradients, gi2) * x2 + readf64(gradients, gi2 + 8) * y2 + readf64(gradients, gi2 + 16) * z2)
	end

	local t3 = 0.5 - x3 * x3 - y3 * y3 - z3 * z3
	if t3 > 0 then
		local t32 = t3 * t3
		n += t32 * t32 * (readf64(gradients, gi3) * x3 + readf64(gradients, gi3 + 8) * y3 + readf64(gradients, gi3 + 16) * z3)
	end

	return n * SCALE3
end

--[=[
	Samples 3D simplex noise along with its analytical derivative.

	@method sample3DWithDerivative
	@within Simplex
	@param x number
	@param y number
	@param z number
	@return number -- Noise value in approximately [-1, 1].
	@return number -- d/dx.
	@return number -- d/dy.
	@return number -- d/dz.
]=]
function Simplex.sample3DWithDerivative(
	self: Simplex,
	x: number,
	y: number,
	z: number
): (number, number, number, number)
	local perm = self._perm
	local gradients = self._grad3

	local skew = (x + y + z) * F3
	local i = floor(x + skew)
	local j = floor(y + skew)
	local k = floor(z + skew)
	local unskew = (i + j + k) * G3
	local x0 = x - (i - unskew)
	local y0 = y - (j - unskew)
	local z0 = z - (k - unskew)

	local i1, j1, k1, i2, j2, k2
	if x0 >= y0 then
		if y0 >= z0 then
			i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
		elseif x0 >= z0 then
			i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
		else
			i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1
		end
	else
		if y0 < z0 then
			i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
		elseif x0 < z0 then
			i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
		else
			i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0
		end
	end

	local x1 = x0 - i1 + G3
	local y1 = y0 - j1 + G3
	local z1 = z0 - k1 + G3
	local x2 = x0 - i2 + G3_2
	local y2 = y0 - j2 + G3_2
	local z2 = z0 - k2 + G3_2
	local x3 = x0 - 0.5
	local y3 = y0 - 0.5
	local z3 = z0 - 0.5

	local ii = band(i, 255)
	local jj = band(j, 255)
	local kk = band(k, 255)
	local gi0 = (ii + readu8(perm, jj + readu8(perm, kk))) * 24
	local gi1 = (ii + i1 + readu8(perm, jj + j1 + readu8(perm, kk + k1))) * 24
	local gi2 = (ii + i2 + readu8(perm, jj + j2 + readu8(perm, kk + k2))) * 24
	local gi3 = (ii + 1 + readu8(perm, jj + 1 + readu8(perm, kk + 1))) * 24

	local n, dx, dy, dz = 0, 0, 0, 0

	local t0 = 0.5 - x0 * x0 - y0 * y0 - z0 * z0
	if t0 > 0 then
		local gx, gy, gz = readf64(gradients, gi0), readf64(gradients, gi0 + 8), readf64(gradients, gi0 + 16)
		local dot = gx * x0 + gy * y0 + gz * z0
		local t03 = t0 * t0 * t0
		n += t03 * t0 * dot
		dx += t03 * (t0 * gx - 8 * x0 * dot)
		dy += t03 * (t0 * gy - 8 * y0 * dot)
		dz += t03 * (t0 * gz - 8 * z0 * dot)
	end

	local t1 = 0.5 - x1 * x1 - y1 * y1 - z1 * z1
	if t1 > 0 then
		local gx, gy, gz = readf64(gradients, gi1), readf64(gradients, gi1 + 8), readf64(gradients, gi1 + 16)
		local dot = gx * x1 + gy * y1 + gz * z1
		local t13 = t1 * t1 * t1
		n += t13 * t1 * dot
		dx += t13 * (t1 * gx - 8 * x1 * dot)
		dy += t13 * (t1 * gy - 8 * y1 * dot)
		dz += t13 * (t1 * gz - 8 * z1 * dot)
	end

	local t2 = 0.5 - x2 * x2 - y2 * y2 - z2 * z2
	if t2 > 0 then
		local gx, gy, gz = readf64(gradients, gi2), readf64(gradients, gi2 + 8), readf64(gradients, gi2 + 16)
		local dot = gx * x2 + gy * y2 + gz * z2
		local t23 = t2 * t2 * t2
		n += t23 * t2 * dot
		dx += t23 * (t2 * gx - 8 * x2 * dot)
		dy += t23 * (t2 * gy - 8 * y2 * dot)
		dz += t23 * (t2 * gz - 8 * z2 * dot)
	end

	local t3 = 0.5 - x3 * x3 - y3 * y3 - z3 * z3
	if t3 > 0 then
		local gx, gy, gz = readf64(gradients, gi3), readf64(gradients, gi3 + 8), readf64(gradients, gi3 + 16)
		local dot = gx * x3 + gy * y3 + gz * z3
		local t33 = t3 * t3 * t3
		n += t33 * t3 * dot
		dx += t33 * (t3 * gx - 8 * x3 * dot)
		dy += t33 * (t3 * gy - 8 * y3 * dot)
		dz += t33 * (t3 * gz - 8 * z3 * dot)
	end

	return n * SCALE3, dx * SCALE3, dy * SCALE3, dz * SCALE3
end

return Simplex

end)()

local Voronoi = (function()
--!strict
--!native
--!optimize 2

local Permutation = Permutation

local floor = math.floor
local huge = math.huge
local random = math.random
local sqrt = math.sqrt

local INV_M = 1 / 2147483647

--[=[
	@class Voronoi

	Seeded Worley (cellular) noise. Each integer cell owns one jittered feature
	point; samples measure the Euclidean distance to the nearest features.

	Distances are returned raw: F1 typically falls in [0, 1] and only rarely
	exceeds it, so ridged patterns like `f2 - f1` keep their full contrast.

	```lua
	local voronoi = Atlas.Noise.Voronoi.new(42)
	local f1, f2, id = voronoi:cell2D(x * 0.1, z * 0.1)
	```
]=]
local Voronoi = {}
Voronoi.__index = Voronoi

export type Voronoi = typeof(setmetatable({} :: { seed: number, _state: number }, Voronoi))

--[=[
	@prop seed number
	@within Voronoi
	@readonly
	The seed this sampler was constructed with.
]=]

--[=[
	Creates a new Voronoi sampler. Equal seeds always produce identical noise.

	@function new
	@within Voronoi
	@param seed number? -- Any number. Defaults to a random seed.
	@return Voronoi
]=]
function Voronoi.new(seed: number?): Voronoi
	local resolved = seed or random(1, 2147483646)
	return setmetatable({
		seed = resolved,
		_state = Permutation.normalize(resolved),
	}, Voronoi)
end

--[=[
	Samples 2D Voronoi noise.

	@method sample2D
	@within Voronoi
	@param x number
	@param y number
	@return number -- F1, the distance to the nearest feature point.
]=]
function Voronoi.sample2D(self: Voronoi, x: number, y: number): number
	local state = self._state
	local ci = floor(x)
	local cj = floor(y)
	local best = huge

	-- Hash each shared neighbor coordinate once, preserving visit order.
	local hj0 = ((cj - 1) % 65536) * 668265263
	local hj1 = (cj % 65536) * 668265263
	local hj2 = ((cj + 1) % 65536) * 668265263

	for i = ci - 1, ci + 1 do
		local hx = (i % 65536) * 374761393
		do
			local j = cj - 1
			local h = (hx + hj0 + state) % 2147483647
			h = h * 48271 % 2147483647
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < best then
				best = d
			end
		end
		do
			local j = cj
			local h = (hx + hj1 + state) % 2147483647
			h = h * 48271 % 2147483647
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < best then
				best = d
			end
		end
		do
			local j = cj + 1
			local h = (hx + hj2 + state) % 2147483647
			h = h * 48271 % 2147483647
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < best then
				best = d
			end
		end
	end

	return sqrt(best)
end

--[=[
	Samples 3D Voronoi noise.

	@method sample3D
	@within Voronoi
	@param x number
	@param y number
	@param z number
	@return number -- F1, the distance to the nearest feature point.
]=]
function Voronoi.sample3D(self: Voronoi, x: number, y: number, z: number): number
	local state = self._state
	local ci = floor(x)
	local cj = floor(y)
	local ck = floor(z)
	local best = huge

	-- Hash each shared neighbor coordinate once, preserving visit order.
	local hk0 = ((ck - 1) % 65536) * 1274126177
	local hk1 = (ck % 65536) * 1274126177
	local hk2 = ((ck + 1) % 65536) * 1274126177

	for i = ci - 1, ci + 1 do
		local hx = (i % 65536) * 374761393
		for j = cj - 1, cj + 1 do
			local hxy = hx + (j % 65536) * 668265263
			do
				local k = ck - 1
				local h = (hxy + hk0 + state) % 2147483647
				h = h * 48271 % 2147483647
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < best then
					best = d
				end
			end
			do
				local k = ck
				local h = (hxy + hk1 + state) % 2147483647
				h = h * 48271 % 2147483647
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < best then
					best = d
				end
			end
			do
				local k = ck + 1
				local h = (hxy + hk2 + state) % 2147483647
				h = h * 48271 % 2147483647
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < best then
					best = d
				end
			end
		end
	end

	return sqrt(best)
end

--[=[
	Samples 2D Voronoi noise, returning the two nearest feature distances and
	a stable id for the winning cell. `f2 - f1` produces ridged cell borders;
	the id is useful for seeding per-cell content such as biomes.

	@method cell2D
	@within Voronoi
	@param x number
	@param y number
	@return number -- F1, the distance to the nearest feature point.
	@return number -- F2, the distance to the second-nearest feature point.
	@return number -- Integer id of the nearest cell.
]=]
function Voronoi.cell2D(self: Voronoi, x: number, y: number): (number, number, number)
	local state = self._state
	local ci = floor(x)
	local cj = floor(y)
	local f1 = huge
	local f2 = huge
	local id = 0

	-- Hash each shared neighbor coordinate once, preserving visit order.
	local hj0 = ((cj - 1) % 65536) * 668265263
	local hj1 = (cj % 65536) * 668265263
	local hj2 = ((cj + 1) % 65536) * 668265263

	for i = ci - 1, ci + 1 do
		local hx = (i % 65536) * 374761393
		do
			local j = cj - 1
			local h = (hx + hj0 + state) % 2147483647
			h = h * 48271 % 2147483647
			local cellId = h
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < f1 then
				f2 = f1
				f1 = d
				id = cellId
			elseif d < f2 then
				f2 = d
			end
		end
		do
			local j = cj
			local h = (hx + hj1 + state) % 2147483647
			h = h * 48271 % 2147483647
			local cellId = h
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < f1 then
				f2 = f1
				f1 = d
				id = cellId
			elseif d < f2 then
				f2 = d
			end
		end
		do
			local j = cj + 1
			local h = (hx + hj2 + state) % 2147483647
			h = h * 48271 % 2147483647
			local cellId = h
			local dx = i + h * INV_M - x
			h = h * 48271 % 2147483647
			local dy = j + h * INV_M - y
			local d = dx * dx + dy * dy
			if d < f1 then
				f2 = f1
				f1 = d
				id = cellId
			elseif d < f2 then
				f2 = d
			end
		end
	end

	return sqrt(f1), sqrt(f2), id
end

--[=[
	Samples 3D Voronoi noise, returning the two nearest feature distances and
	a stable id for the winning cell.

	@method cell3D
	@within Voronoi
	@param x number
	@param y number
	@param z number
	@return number -- F1, the distance to the nearest feature point.
	@return number -- F2, the distance to the second-nearest feature point.
	@return number -- Integer id of the nearest cell.
]=]
function Voronoi.cell3D(self: Voronoi, x: number, y: number, z: number): (number, number, number)
	local state = self._state
	local ci = floor(x)
	local cj = floor(y)
	local ck = floor(z)
	local f1 = huge
	local f2 = huge
	local id = 0

	-- Hash each shared neighbor coordinate once, preserving visit order.
	local hk0 = ((ck - 1) % 65536) * 1274126177
	local hk1 = (ck % 65536) * 1274126177
	local hk2 = ((ck + 1) % 65536) * 1274126177

	for i = ci - 1, ci + 1 do
		local hx = (i % 65536) * 374761393
		for j = cj - 1, cj + 1 do
			local hxy = hx + (j % 65536) * 668265263
			do
				local k = ck - 1
				local h = (hxy + hk0 + state) % 2147483647
				h = h * 48271 % 2147483647
				local cellId = h
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < f1 then
					f2 = f1
					f1 = d
					id = cellId
				elseif d < f2 then
					f2 = d
				end
			end
			do
				local k = ck
				local h = (hxy + hk1 + state) % 2147483647
				h = h * 48271 % 2147483647
				local cellId = h
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < f1 then
					f2 = f1
					f1 = d
					id = cellId
				elseif d < f2 then
					f2 = d
				end
			end
			do
				local k = ck + 1
				local h = (hxy + hk2 + state) % 2147483647
				h = h * 48271 % 2147483647
				local cellId = h
				local dx = i + h * INV_M - x
				h = h * 48271 % 2147483647
				local dy = j + h * INV_M - y
				h = h * 48271 % 2147483647
				local dz = k + h * INV_M - z
				local d = dx * dx + dy * dy + dz * dz
				if d < f1 then
					f2 = f1
					f1 = d
					id = cellId
				elseif d < f2 then
					f2 = d
				end
			end
		end
	end

	return sqrt(f1), sqrt(f2), id
end

--[=[
	Samples 2D Voronoi noise along with its slope, estimated by central finite
	differences. Worley noise has no clean analytical gradient, and the
	distance field is not differentiable on cell borders.

	@method sample2DWithDerivative
	@within Voronoi
	@param x number
	@param y number
	@param epsilon number? -- Finite-difference step. Defaults to 1e-3.
	@return number -- F1, the distance to the nearest feature point.
	@return number -- d/dx.
	@return number -- d/dy.
]=]
function Voronoi.sample2DWithDerivative(self: Voronoi, x: number, y: number, epsilon: number?): (number, number, number)
	local eps = epsilon or 1e-3
	local halfInv = 0.5 / eps
	local value = self:sample2D(x, y)
	local dx = (self:sample2D(x + eps, y) - self:sample2D(x - eps, y)) * halfInv
	local dy = (self:sample2D(x, y + eps) - self:sample2D(x, y - eps)) * halfInv
	return value, dx, dy
end

--[=[
	Samples 3D Voronoi noise along with its slope, estimated by central finite
	differences.

	@method sample3DWithDerivative
	@within Voronoi
	@param x number
	@param y number
	@param z number
	@param epsilon number? -- Finite-difference step. Defaults to 1e-3.
	@return number -- F1, the distance to the nearest feature point.
	@return number -- d/dx.
	@return number -- d/dy.
	@return number -- d/dz.
]=]
function Voronoi.sample3DWithDerivative(
	self: Voronoi,
	x: number,
	y: number,
	z: number,
	epsilon: number?
): (number, number, number, number)
	local eps = epsilon or 1e-3
	local halfInv = 0.5 / eps
	local value = self:sample3D(x, y, z)
	local dx = (self:sample3D(x + eps, y, z) - self:sample3D(x - eps, y, z)) * halfInv
	local dy = (self:sample3D(x, y + eps, z) - self:sample3D(x, y - eps, z)) * halfInv
	local dz = (self:sample3D(x, y, z + eps) - self:sample3D(x, y, z - eps)) * halfInv
	return value, dx, dy, dz
end

return Voronoi

end)()

local Island = (function()
--!strict
--!native
--!optimize 2

local Simplex = Simplex
local Permutation = Permutation

local clamp = math.clamp
local floor = math.floor
local random = math.random
local sqrt = math.sqrt

export type IslandOptions = {
	seed: number?,
	centerX: number?,
	centerY: number?,
	radius: number?,
	breakage: number?,
	detail: number?,
}

--[=[
	@class Island

	A deterministic binary island mask. Samples return exactly `1` for land
	and `0` for water, making the sampler useful as a terrain mask, biome gate,
	or visualizer input.

	```lua
	local island = Atlas.Noise.Island.new({ seed = 42, breakage = 0.5, detail = 0.75 })
	local isLand = island:sample2D(x * 0.002, z * 0.002) == 1
	```
]=]
local Island = {}
Island.__index = Island

export type Island = typeof(setmetatable(
	{} :: {
		seed: number,
		centerX: number,
		centerY: number,
		radius: number,
		breakage: number,
		detail: number,
		_simplex: Simplex.Simplex,
		_offsetX: number,
		_offsetY: number,
		_invRadius: number,
		_octaves: number,
	},
	Island
))

local function offset(seed: number, salt: number): number
	local state = Permutation.normalize(seed + salt)
	state = state * 48271 % 2147483647
	return state / 2147483647 * 512
end

--[=[
	@prop seed number
	@within Island
	@readonly
	The seed this island mask was constructed with.
]=]

--[=[
	@prop centerX number
	@within Island
	@readonly
	The x coordinate of the island center. Defaults to `0`.
]=]

--[=[
	@prop centerY number
	@within Island
	@readonly
	The y coordinate of the island center. Defaults to `0`.
]=]

--[=[
	@prop radius number
	@within Island
	@readonly
	The normalized island radius. Defaults to `1`.
]=]

--[=[
	@prop breakage number
	@within Island
	@readonly
	Large-scale coastline breakup in `[0, 1]`. Higher values cut deeper bays
	and can split off smaller land masses.
]=]

--[=[
	@prop detail number
	@within Island
	@readonly
	High-frequency shoreline detail in `[0, 1]`.
]=]

--[=[
	Creates a new binary island mask. Equal options and seeds always produce
	identical land/water masks.

	@function new
	@within Island
	@param options IslandOptions?
	@return Island
]=]
function Island.new(options: IslandOptions?): Island
	local resolved = if options and options.seed then options.seed else random(1, 2147483646)
	local radius = if options then options.radius or 1 else 1
	if radius <= 0 then
		error("Island radius must be greater than 0", 2)
	end

	local breakage = clamp(if options then options.breakage or 0.35 else 0.35, 0, 1)
	local detail = clamp(if options then options.detail or 0.5 else 0.5, 0, 1)

	return setmetatable({
		seed = resolved,
		centerX = if options then options.centerX or 0 else 0,
		centerY = if options then options.centerY or 0 else 0,
		radius = radius,
		breakage = breakage,
		detail = detail,
		_simplex = Simplex.new(resolved),
		_offsetX = offset(resolved, 1013),
		_offsetY = offset(resolved, 7919),
		_invRadius = 1 / radius,
		_octaves = 2 + floor(detail * 4 + 0.5),
	}, Island)
end

--[=[
	Samples the island mask.

	@method sample2D
	@within Island
	@param x number
	@param y number
	@return number -- `1` for land, `0` for water.
]=]
function Island.sample2D(self: Island, x: number, y: number): number
	local nx = (x - self.centerX) * self._invRadius
	local ny = (y - self.centerY) * self._invRadius
	local distance = sqrt(nx * nx + ny * ny)

	if distance >= 1.8 then
		return 0
	end

	local simplex = self._simplex
	local ox = self._offsetX
	local oy = self._offsetY
	local breakage = self.breakage
	local detail = self.detail

	local large = simplex:sample2D(ox + nx * 1.75, oy + ny * 1.75)
	local medium = simplex:sample2D(ox * 0.37 + nx * 4.5, oy * 0.37 + ny * 4.5)

	local detailSum = 0
	local amplitude = 1
	local total = 0
	local frequency = 9
	for _ = 1, self._octaves do
		detailSum += amplitude * simplex:sample2D(ox + nx * frequency, oy + ny * frequency)
		total += amplitude
		amplitude *= 0.5
		frequency *= 2
	end

	local shore = 1 + large * (0.08 + breakage * 0.34) + medium * breakage * 0.12 + detailSum / total * detail * 0.12
	local score = shore - distance

	if breakage > 0 then
		local cuts = simplex:sample2D(ox * 1.73 + nx * 3.2, oy * 1.73 + ny * 3.2)
		score -= clamp(cuts * breakage, 0, 1) * breakage * 0.22
	end

	return if score >= 0 then 1 else 0
end

return Island

end)()

local Noise = (function()
--!strict
--!native
--!optimize 2

local Perlin = Perlin
local Simplex = Simplex
local Voronoi = Voronoi
local Island = Island

export type Perlin = Perlin.Perlin
export type Simplex = Simplex.Simplex
export type Voronoi = Voronoi.Voronoi
export type Island = Island.Island

--[=[
	@interface NoiseSampler2D
	@within Noise
	.sample2D (self: any, x: number, y: number) -> number

	Anything with a `sample2D` method — every Atlas noise sampler qualifies, as
	do user-defined wrappers.
]=]
export type NoiseSampler2D = {
	sample2D: (self: any, x: number, y: number) -> number,
}

--[=[
	@interface NoiseSampler3D
	@within Noise
	.sample3D (self: any, x: number, y: number, z: number) -> number

	Anything with a `sample3D` method.
]=]
export type NoiseSampler3D = {
	sample3D: (self: any, x: number, y: number, z: number) -> number,
}

--[=[
	@interface NoiseSampler2DWithDerivative
	@within Noise
	.sample2DWithDerivative (self: any, x: number, y: number) -> (number, number, number)

	Anything with a `sample2DWithDerivative` method — every Atlas noise
	sampler qualifies.
]=]
export type NoiseSampler2DWithDerivative = {
	sample2DWithDerivative: (self: any, x: number, y: number) -> (number, number, number),
}

--[=[
	@interface NoiseSampler3DWithDerivative
	@within Noise
	.sample3DWithDerivative (self: any, x: number, y: number, z: number) -> (number, number, number, number)

	Anything with a `sample3DWithDerivative` method.
]=]
export type NoiseSampler3DWithDerivative = {
	sample3DWithDerivative: (self: any, x: number, y: number, z: number) -> (number, number, number, number),
}

--[=[
	@class Noise

	Noise generation. Houses the [Perlin], [Simplex], and [Voronoi] sampler
	classes plus fractal helpers that layer any sampler into fractional
	Brownian motion.

	```lua
	local simplex = Atlas.Noise.Simplex.new(42)
	local height = Atlas.Noise.fbm2D(simplex, x * 0.01, z * 0.01, 4)
	```
]=]
local Noise = {
	Perlin = Perlin,
	Simplex = Simplex,
	Voronoi = Voronoi,
	Island = Island,
}

--[=[
	Layers 2D noise octaves into fractional Brownian motion. The result is
	renormalized by total amplitude, so a sampler emitting [-1, 1] stays in
	[-1, 1] regardless of octave count.

	@function fbm2D
	@within Noise
	@param sampler NoiseSampler2D
	@param x number
	@param y number
	@param octaves number
	@param lacunarity number? -- Frequency multiplier per octave. Defaults to 2.
	@param gain number? -- Amplitude multiplier per octave. Defaults to 0.5.
	@return number
]=]
function Noise.fbm2D(
	sampler: NoiseSampler2D,
	x: number,
	y: number,
	octaves: number,
	lacunarity: number?,
	gain: number?
): number
	local frequencyStep = lacunarity or 2
	local amplitudeStep = gain or 0.5
	local sample2D = sampler.sample2D

	local sum = 0
	local total = 0
	local amplitude = 1
	local frequency = 1
	for _ = 1, octaves do
		sum += amplitude * sample2D(sampler, x * frequency, y * frequency)
		total += amplitude
		amplitude *= amplitudeStep
		frequency *= frequencyStep
	end

	return sum / total
end

--[=[
	Layers 2D noise octaves into fBm together with the analytical derivative
	of the sum. Differentiation is linear, so each octave's derivative scales
	by the same amplitude and chain-rules by the same frequency used for its
	value, and can be accumulated in the very same loop — no extra noise
	samples needed, unlike a finite-difference slope estimate.

	@function fbm2DWithDerivative
	@within Noise
	@param sampler NoiseSampler2DWithDerivative
	@param x number
	@param y number
	@param octaves number
	@param lacunarity number? -- Frequency multiplier per octave. Defaults to 2.
	@param gain number? -- Amplitude multiplier per octave. Defaults to 0.5.
	@return number -- Noise value.
	@return number -- d/dx.
	@return number -- d/dy.
]=]
function Noise.fbm2DWithDerivative(
	sampler: NoiseSampler2DWithDerivative,
	x: number,
	y: number,
	octaves: number,
	lacunarity: number?,
	gain: number?
): (number, number, number)
	local frequencyStep = lacunarity or 2
	local amplitudeStep = gain or 0.5
	local sample2DWithDerivative = sampler.sample2DWithDerivative

	local sum = 0
	local dxSum = 0
	local dySum = 0
	local total = 0
	local amplitude = 1
	local frequency = 1
	for _ = 1, octaves do
		local value, dx, dy = sample2DWithDerivative(sampler, x * frequency, y * frequency)
		sum += amplitude * value
		dxSum += amplitude * frequency * dx
		dySum += amplitude * frequency * dy
		total += amplitude
		amplitude *= amplitudeStep
		frequency *= frequencyStep
	end

	local invTotal = 1 / total
	return sum * invTotal, dxSum * invTotal, dySum * invTotal
end

--[=[
	Layers 3D noise octaves into fractional Brownian motion.

	@function fbm3D
	@within Noise
	@param sampler NoiseSampler3D
	@param x number
	@param y number
	@param z number
	@param octaves number
	@param lacunarity number? -- Frequency multiplier per octave. Defaults to 2.
	@param gain number? -- Amplitude multiplier per octave. Defaults to 0.5.
	@return number
]=]
function Noise.fbm3D(
	sampler: NoiseSampler3D,
	x: number,
	y: number,
	z: number,
	octaves: number,
	lacunarity: number?,
	gain: number?
): number
	local frequencyStep = lacunarity or 2
	local amplitudeStep = gain or 0.5
	local sample3D = sampler.sample3D

	local sum = 0
	local total = 0
	local amplitude = 1
	local frequency = 1
	for _ = 1, octaves do
		sum += amplitude * sample3D(sampler, x * frequency, y * frequency, z * frequency)
		total += amplitude
		amplitude *= amplitudeStep
		frequency *= frequencyStep
	end

	return sum / total
end

--[=[
	Layers 3D noise octaves into fBm together with the analytical derivative
	of the sum, accumulated in the same pass as [fbm3D] instead of resampling
	the field via finite differences.

	@function fbm3DWithDerivative
	@within Noise
	@param sampler NoiseSampler3DWithDerivative
	@param x number
	@param y number
	@param z number
	@param octaves number
	@param lacunarity number? -- Frequency multiplier per octave. Defaults to 2.
	@param gain number? -- Amplitude multiplier per octave. Defaults to 0.5.
	@return number -- Noise value.
	@return number -- d/dx.
	@return number -- d/dy.
	@return number -- d/dz.
]=]
function Noise.fbm3DWithDerivative(
	sampler: NoiseSampler3DWithDerivative,
	x: number,
	y: number,
	z: number,
	octaves: number,
	lacunarity: number?,
	gain: number?
): (number, number, number, number)
	local frequencyStep = lacunarity or 2
	local amplitudeStep = gain or 0.5
	local sample3DWithDerivative = sampler.sample3DWithDerivative

	local sum = 0
	local dxSum = 0
	local dySum = 0
	local dzSum = 0
	local total = 0
	local amplitude = 1
	local frequency = 1
	for _ = 1, octaves do
		local value, dx, dy, dz = sample3DWithDerivative(sampler, x * frequency, y * frequency, z * frequency)
		sum += amplitude * value
		dxSum += amplitude * frequency * dx
		dySum += amplitude * frequency * dy
		dzSum += amplitude * frequency * dz
		total += amplitude
		amplitude *= amplitudeStep
		frequency *= frequencyStep
	end

	local invTotal = 1 / total
	return sum * invTotal, dxSum * invTotal, dySum * invTotal, dzSum * invTotal
end

return Noise

end)()

local Curve = (function()
--!strict
--!native
--!optimize 2

--[=[
	@class Curve

	A response curve: control points interpolated with a monotone cubic Hermite
	spline (Fritsch–Carlson), evaluated as `y = curve:evaluate(x)`. The spline
	never overshoots its control points, which makes it safe for remapping
	noise into ranges like [0, 1] — shaping terrain falloff, biome thresholds,
	spawn weights, or any other value.

	```lua
	local falloff = Atlas.Curve.new({
		Vector2.new(0, 0),
		Vector2.new(0.4, 0.1),
		Vector2.new(0.7, 0.8),
		Vector2.new(1, 1),
	})
	local height = falloff:evaluate(noiseValue * 0.5 + 0.5)
	```
]=]
local Curve = {}
Curve.__index = Curve

type CurveProps = {
	_xs: { number },
	_ys: { number },
	_tangents: { number },
	_count: number,
	_minY: number,
	_maxY: number,
}

export type Curve = typeof(setmetatable({} :: CurveProps, Curve))

--[=[
	Creates a curve through the given control points. Points are sorted by x on
	construction; x values must be distinct.

	@function new
	@within Curve
	@param points {Vector2} -- At least two control points.
	@return Curve
]=]
function Curve.new(points: { Vector2 }): Curve
	local count = #points
	if count < 2 then
		error("Curve.new requires at least two control points", 2)
	end

	local sorted = table.clone(points)
	table.sort(sorted, function(a: Vector2, b: Vector2)
		return a.X < b.X
	end)

	local xs: { number } = table.create(count) :: { number }
	local ys: { number } = table.create(count) :: { number }
	for i = 1, count do
		local point = sorted[i]
		xs[i] = point.X
		ys[i] = point.Y
		if i > 1 and point.X == xs[i - 1] then
			error("Curve.new control points must have distinct x values", 2)
		end
	end

	local secants: { number } = table.create(count - 1) :: { number }
	for i = 1, count - 1 do
		secants[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
	end

	local tangents: { number } = table.create(count) :: { number }
	tangents[1] = secants[1]
	tangents[count] = secants[count - 1]
	for i = 2, count - 1 do
		local left: number = secants[i - 1]
		local right: number = secants[i]
		tangents[i] = if left * right <= 0 then 0 else (left + right) * 0.5
	end

	-- Fritsch–Carlson limiting: pull tangents back inside the circle of radius
	-- 3 around each secant so no segment can overshoot.
	for i = 1, count - 1 do
		local secant = secants[i]
		if secant == 0 then
			tangents[i] = 0
			tangents[i + 1] = 0
		else
			local a = tangents[i] / secant
			local b = tangents[i + 1] / secant
			local lengthSq = a * a + b * b
			if lengthSq > 9 then
				local scale = 3 / math.sqrt(lengthSq)
				tangents[i] = scale * a * secant
				tangents[i + 1] = scale * b * secant
			end
		end
	end

	local minY = ys[1]
	local maxY = ys[1]
	for i = 2, count do
		local y = ys[i]
		if y < minY then
			minY = y
		elseif y > maxY then
			maxY = y
		end
	end

	return setmetatable(({
		_xs = xs,
		_ys = ys,
		_tangents = tangents,
		_count = count,
		_minY = minY,
		_maxY = maxY,
	} :: CurveProps), Curve)
end

--[=[
	Evaluates the curve at `x`. Inputs outside the control point domain clamp
	to the first or last point's value.

	@method evaluate
	@within Curve
	@param x number
	@return number
]=]
function Curve.evaluate(self: Curve, x: number): number
	local xs = self._xs
	local count = self._count

	if x <= xs[1] then
		return self._ys[1]
	elseif x >= xs[count] then
		return self._ys[count]
	end

	local low = 1
	local high = count
	while high - low > 1 do
		local mid = (low + high) // 2
		if xs[mid] <= x then
			low = mid
		else
			high = mid
		end
	end

	local ys = self._ys
	local tangents = self._tangents
	local x0 = xs[low]
	local width = xs[low + 1] - x0
	local t = (x - x0) / width
	local t2 = t * t
	local t3 = t2 * t

	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = 1 - h00
	local h11 = t3 - t2

	return h00 * ys[low] + h10 * width * tangents[low] + h01 * ys[low + 1] + h11 * width * tangents[low + 1]
end

--[=[
	Evaluates the curve at `x` along with its derivative `dy/dx` — the local
	slope of the spline, with no extra evaluations. Useful for chain-ruling
	slope through a curve-shaped value (e.g. terrain steepened by a response
	curve) without resampling the underlying field. Outside the control point
	domain the curve is constant, so the derivative is 0 there.

	@method evaluateWithDerivative
	@within Curve
	@param x number
	@return number -- y
	@return number -- dy/dx
]=]
function Curve.evaluateWithDerivative(self: Curve, x: number): (number, number)
	local xs = self._xs
	local count = self._count

	if x <= xs[1] or x >= xs[count] then
		return self:evaluate(x), 0
	end

	local low = 1
	local high = count
	while high - low > 1 do
		local mid = (low + high) // 2
		if xs[mid] <= x then
			low = mid
		else
			high = mid
		end
	end

	local ys = self._ys
	local tangents = self._tangents
	local x0 = xs[low]
	local width = xs[low + 1] - x0
	local t = (x - x0) / width
	local t2 = t * t
	local t3 = t2 * t

	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = 1 - h00
	local h11 = t3 - t2

	local dh00 = 6 * t2 - 6 * t
	local dh10 = 3 * t2 - 4 * t + 1
	local dh11 = 3 * t2 - 2 * t

	local y0 = ys[low]
	local y1 = ys[low + 1]
	local m0 = tangents[low]
	local m1 = tangents[low + 1]

	local value = h00 * y0 + h10 * width * m0 + h01 * y1 + h11 * width * m1
	local derivative = (dh00 * (y0 - y1) + dh10 * width * m0 + dh11 * width * m1) / width

	return value, derivative
end

--[=[
	Evaluates the curve over a whole array in one call.

	@method map
	@within Curve
	@param values {number}
	@return {number}
]=]
function Curve.map(self: Curve, values: { number }): { number }
	local evaluate = self.evaluate
	local mapped = table.create(#values)
	for i, value in values do
		mapped[i] = evaluate(self, value)
	end
	return mapped :: { number }
end

--[=[
	Returns the x extent covered by the control points.

	@method domain
	@within Curve
	@return number -- Smallest control point x.
	@return number -- Largest control point x.
]=]
function Curve.domain(self: Curve): (number, number)
	return self._xs[1], self._xs[self._count]
end

--[=[
	Returns the output extent of the curve. Because the spline is monotone
	between control points, this is exactly the min and max control point y.

	@method range
	@within Curve
	@return number -- Smallest output value.
	@return number -- Largest output value.
]=]
function Curve.range(self: Curve): (number, number)
	return self._minY, self._maxY
end

return Curve

end)()

local Sampling = (function()
--!strict
--!native
--!optimize 2

local Permutation = Permutation

local floor = math.floor
local max = math.max
local min = math.min
local sin = math.sin
local cos = math.cos
local random = math.random
local vector3 = Vector3.new

local TAU = 6.283185307179586
local INV_RANGE = 1 / 2147483646

-- fast LCG step (kept simple, but reduced duplication sites matter more than micro-optimizing this further)
local function nextState(state: number): number
	return (state * 48271) % 2147483647
end

--[=[
	@class Sampling

	Point scattering over a rectangular region. All samplers are deterministic
	for a given seed and return points as `{Vector2}` with coordinates in
	`[0, width) × [0, height)`.

	```lua
	local trees = Atlas.Sampling.poissonDisc(512, 512, 8, 42)
	```
]=]
local Sampling = {}

--[=[
	Scatters `count` independent uniformly-distributed points.

	@function uniform
	@within Sampling
	@param width number
	@param height number
	@param count number
	@param seed number? -- Any number. Defaults to a random seed.
	@return {Vector3}
]=]
function Sampling.uniform(width: number, height: number, count: number, seed: number?): { Vector3 }
	local state = Permutation.normalize(seed or random(1, 2147483646))
	local points = table.create(count)

	for i = 1, count do
		state = state * 48271 % 2147483647
		local x = width * ((state - 1) * INV_RANGE)
		state = state * 48271 % 2147483647
		local y = height * ((state - 1) * INV_RANGE)
		points[i] = vector3(x, y) :: Vector3
	end

	return points :: { Vector3 }
end

--[=[
	Scatters points with blue-noise spacing using Bridson's Poisson disc
	algorithm: no two points are closer than `radius`, and the region is filled
	until no more fit. Runs in O(n) via a background acceleration grid.

	@function poissonDisc
	@within Sampling
	@param width number
	@param height number
	@param radius number -- Minimum distance between any two points.
	@param seed number? -- Any number. Defaults to a random seed.
	@param maxAttempts number? -- Candidates tried per active point. Defaults to 30.
	@return {Vector3}
]=]
function Sampling.poissonDisc(
	width: number,
	height: number,
	radius: number,
	seed: number?,
	maxAttempts: number?
): { Vector3 }
	local k = maxAttempts or 30
	local state = Permutation.normalize(seed or random(1, 2147483646))

	local cellSize = radius * 0.7071067811865476
	local invCellSize = 1 / cellSize

	local gridW = floor(width * invCellSize) + 1
	local gridH = floor(height * invCellSize) + 1

	local grid = table.create(gridW * gridH, 0)
	local radiusSq = radius * radius

	-- store points directly (no xs/ys split)
	local points: { Vector3 } = table.create(64) :: { Vector3 }
	local active: { number } = table.create(64) :: { number }

	-- first point
	state = nextState(state)
	local firstX = width * ((state - 1) * INV_RANGE)
	state = nextState(state)
	local firstY = height * ((state - 1) * INV_RANGE)

	points[1] = vector3(firstX, firstY)
	active[1] = 1

	local gx = floor(firstX * invCellSize)
	local gy = floor(firstY * invCellSize)
	grid[gx * gridH + gy + 1] = 1

	local count = 1
	local activeCount = 1

	while activeCount > 0 do
		state = nextState(state)

		local pick = 1 + floor((state - 1) * INV_RANGE * activeCount)
		local parentIndex = active[pick]
		local parent = points[parentIndex]

		local px = parent.X
		local py = parent.Y

		local placed = false

		for _ = 1, k do
			state = nextState(state)

			local angle = TAU * ((state - 1) * INV_RANGE)
			state = nextState(state)

			local dist = radius * (1 + (state - 1) * INV_RANGE)

			local cx = px + cos(angle) * dist
			local cy = py + sin(angle) * dist

			if cx >= 0 and cx < width and cy >= 0 and cy < height then
				local cgx = floor(cx * invCellSize)
				local cgy = floor(cy * invCellSize)

				local minY = max(cgy - 2, 0)
				local maxY = min(cgy + 2, gridH - 1)
				local ok = true

				for ix = max(cgx - 2, 0), min(cgx + 2, gridW - 1) do
					local base = ix * gridH

					for iy = minY, maxY do
						local idx = grid[base + iy + 1]

						if idx ~= 0 then
							local op = points[idx]
							local dx = op.X - cx
							local dy = op.Y - cy

							if dx * dx + dy * dy < radiusSq then
								ok = false
								break
							end
						end
					end

					if not ok then
						break
					end
				end

				if ok then
					count += 1
					points[count] = vector3(cx, cy)

					activeCount += 1
					active[activeCount] = count

					grid[cgx * gridH + cgy + 1] = count

					placed = true
					break
				end
			end
		end

		if not placed then
			active[pick] = active[activeCount]
			active[activeCount] = nil
			activeCount -= 1
		end
	end

	return points
end

--[=[
	Generates a blue-noise-like point distribution using a jittered grid. Outputs a vector3 because they are much faster internally.

	@param width number -- Width of the region in studs/units.
	@param height number -- Height of the region in studs/units.
	@param cellSize number -- Size of each grid cell (controls spacing).
	@param seed number? -- Optional seed for deterministic generation.
	@param density number? -- Optional [0..1] density multiplier (default 1).
	@return {Vector3} -- Array of generated points. (x, y, 0)
]=]
function Sampling.blueNoiseGrid(
	width: number,
	height: number,
	cellSize: number,
	seed: number?,
	density: number?
): { Vector3 }
	local state = Permutation.normalize(seed or random(1, 2147483646))

	local invCell = 1 / cellSize

	local gridW = floor(width * invCell)
	local gridH = floor(height * invCell)

	local points = table.create(gridW * gridH)

	local count = 0
	local d = density or 1

	for y = 0, gridH - 1 do
		for x = 0, gridW - 1 do
			state = nextState(state)

			-- density mask (blue noise approximation)
			local keep = state * INV_RANGE
			if keep <= d then
				state = nextState(state)
				local jx = state * INV_RANGE

				state = nextState(state)
				local jy = state * INV_RANGE

				local px = (x + jx) * cellSize
				local py = (y + jy) * cellSize

				if px < width and py < height then
					count += 1
					points[count] = vector3(px, py)
				end
			end
		end
	end

	return points :: { Vector3 }
end

return Sampling

end)()

local Presets = (function()
--!strict
--!native
--!optimize 2

local Curve = Curve
local Noise = Noise

local floor = math.floor
local max = math.max
local min = math.min
local writeu32 = buffer.writeu32

type Curve = Curve.Curve
type NoiseSampler2D = Noise.NoiseSampler2D

export type PixelCallback = (x: number, y: number) -> (number, number, number)
export type DrawCallback = (buf: buffer, width: number, height: number) -> ()

local function pack(r: number, g: number, b: number): number
	return r + g * 0x100 + b * 0x10000 + 0xFF000000
end

local COLOR_BACKGROUND = pack(24, 25, 31)
local COLOR_GRID = pack(52, 54, 66)
local COLOR_LINE = pack(126, 231, 135)
local COLOR_POINT = pack(255, 196, 87)

local function fill(buf: buffer, width: number, height: number, color: number)
	for offset = 0, width * height * 4 - 4, 4 do
		writeu32(buf, offset, color)
	end
end

--[=[
	@interface NoisePresetOptions
	@within Presets
	.scale number? -- Noise-space units per pixel. Defaults to 0.05.
	.offsetX number? -- Noise-space x offset. Defaults to 0.
	.offsetY number? -- Noise-space y offset. Defaults to 0.
	.rangeMin number? -- Sampler output mapped to black. Defaults to -1.
	.rangeMax number? -- Sampler output mapped to white. Defaults to 1.
	.curve Curve? -- Optional response curve applied after range mapping.
]=]
export type NoisePresetOptions = {
	scale: number?,
	offsetX: number?,
	offsetY: number?,
	rangeMin: number?,
	rangeMax: number?,
	curve: Curve?,
}

--[=[
	@interface PointsPresetOptions
	@within Presets
	.width number -- Width of the region the points were sampled from.
	.height number -- Height of the region the points were sampled from.
	.radius number? -- Dot radius in pixels. Defaults to 2.
]=]
export type PointsPresetOptions = {
	width: number,
	height: number,
	radius: number?,
}

--[=[
	@class Presets

	Ready-made callbacks for [Visualizer], covering the three things you most
	often want to look at while tuning generation: noise fields, response
	curves, and scattered points.

	```lua
	local viz = Atlas.Visualizer.new({ title = "Terrain" })
	viz:render(Atlas.Visualizer.Presets.noise(simplex, { scale = 0.02 }))
	```
]=]
local Presets = {}

--[=[
	Builds a grayscale [PixelCallback] for any 2D noise sampler. Sampler output
	is mapped from `[rangeMin, rangeMax]` to black–white, optionally shaped
	through a [Curve] — handy for previewing exactly the remap your terrain
	will use. Pass `rangeMin = 0` for [Voronoi] distances.

	@function noise
	@within Presets
	@param sampler NoiseSampler2D
	@param options NoisePresetOptions?
	@return PixelCallback
]=]
function Presets.noise(sampler: NoiseSampler2D, options: NoisePresetOptions?): PixelCallback
	local scale = if options then options.scale or 0.05 else 0.05
	local offsetX = if options then options.offsetX or 0 else 0
	local offsetY = if options then options.offsetY or 0 else 0
	local rangeMin = if options then options.rangeMin or -1 else -1
	local rangeMax = if options then options.rangeMax or 1 else 1
	local curve = if options then options.curve else nil
	local invRange = 1 / (rangeMax - rangeMin)
	local sample2D = sampler.sample2D

	if curve then
		return function(x: number, y: number): (number, number, number)
			local value = (sample2D(sampler, offsetX + x * scale, offsetY + y * scale) - rangeMin) * invRange
			value = curve:evaluate(value)
			return value, value, value
		end
	end

	return function(x: number, y: number): (number, number, number)
		local value = (sample2D(sampler, offsetX + x * scale, offsetY + y * scale) - rangeMin) * invRange
		return value, value, value
	end
end

--[=[
	Builds a [DrawCallback] that plots a [Curve] over a quarter grid, scaled to
	the curve's own domain and range.

	@function curve
	@within Presets
	@param curve Curve
	@return DrawCallback
]=]
function Presets.curve(curve: Curve): DrawCallback
	return function(buf: buffer, width: number, height: number)
		fill(buf, width, height, COLOR_BACKGROUND)

		for quarter = 1, 3 do
			local gridX = min(floor(width * quarter * 0.25 + 0.5), width - 1)
			for y = 0, height - 1 do
				writeu32(buf, (y * width + gridX) * 4, COLOR_GRID)
			end
			local gridY = min(floor(height * quarter * 0.25 + 0.5), height - 1)
			local rowOffset = gridY * width * 4
			for x = 0, width - 1 do
				writeu32(buf, rowOffset + x * 4, COLOR_GRID)
			end
		end

		local minX, maxX = curve:domain()
		local minY, maxY = curve:range()
		local spanY = maxY - minY
		if spanY < 1e-12 then
			minY -= 0.5
			spanY = 1
		end

		local margin = 4
		local plotHeight = height - 1 - margin * 2
		local stepX = (maxX - minX) / (width - 1)
		local previous = -1

		for px = 0, width - 1 do
			local value = curve:evaluate(minX + px * stepX)
			local py = margin + floor((1 - (value - minY) / spanY) * plotHeight + 0.5)
			if previous < 0 then
				previous = py
			end
			for y = min(previous, py), max(previous, py) do
				writeu32(buf, (y * width + px) * 4, COLOR_LINE)
			end
			previous = py
		end
	end
end

--[=[
	Builds a [DrawCallback] that plots sample points as dots, mapping the
	sampled region onto the full image.

	@function points
	@within Presets
	@param points {Vector2}
	@param options PointsPresetOptions
	@return DrawCallback
]=]
function Presets.points(points: { Vector2 }, options: PointsPresetOptions): DrawCallback
	local regionWidth = options.width
	local regionHeight = options.height
	local radius = options.radius or 2
	local radiusSq = radius * radius

	return function(buf: buffer, width: number, height: number)
		fill(buf, width, height, COLOR_BACKGROUND)

		local scaleX = (width - 1) / regionWidth
		local scaleY = (height - 1) / regionHeight

		for _, point in points do
			local centerX = floor(point.X * scaleX + 0.5)
			local centerY = floor(point.Y * scaleY + 0.5)
			for offsetY = -radius, radius do
				local y = centerY + offsetY
				if y >= 0 and y < height then
					local rowOffset = y * width * 4
					for offsetX = -radius, radius do
						local x = centerX + offsetX
						if x >= 0 and x < width and offsetX * offsetX + offsetY * offsetY <= radiusSq then
							writeu32(buf, rowOffset + x * 4, COLOR_POINT)
						end
					end
				end
			end
		end
	end
end

return Presets

end)()

local Atlas = {Noise=Noise, Curve=Curve, Sampling=Sampling, Visualizer={Presets=Presets}}
