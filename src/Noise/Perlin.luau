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

export type Perlin = typeof(setmetatable({} :: { seed: number, _perm: buffer }, Perlin))

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
	return setmetatable({
		seed = resolved,
		_perm = Permutation.build(resolved),
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

	local fx = floor(x)
	local fy = floor(y)
	local xf = x - fx
	local yf = y - fy
	local xf1 = xf - 1
	local yf1 = yf - 1

	local a = readu8(perm, band(fx, 255)) + band(fy, 255)
	local b = readu8(perm, band(fx, 255) + 1) + band(fy, 255)

	local i00 = band(readu8(perm, a), 7) * 16
	local i01 = band(readu8(perm, a + 1), 7) * 16
	local i10 = band(readu8(perm, b), 7) * 16
	local i11 = band(readu8(perm, b + 1), 7) * 16

	local n00 = readf64(GRAD2, i00) * xf + readf64(GRAD2, i00 + 8) * yf
	local n10 = readf64(GRAD2, i10) * xf1 + readf64(GRAD2, i10 + 8) * yf
	local n01 = readf64(GRAD2, i01) * xf + readf64(GRAD2, i01 + 8) * yf1
	local n11 = readf64(GRAD2, i11) * xf1 + readf64(GRAD2, i11 + 8) * yf1

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

	local fx = floor(x)
	local fy = floor(y)
	local xf = x - fx
	local yf = y - fy
	local xf1 = xf - 1
	local yf1 = yf - 1

	local a = readu8(perm, band(fx, 255)) + band(fy, 255)
	local b = readu8(perm, band(fx, 255) + 1) + band(fy, 255)

	local i00 = band(readu8(perm, a), 7) * 16
	local i01 = band(readu8(perm, a + 1), 7) * 16
	local i10 = band(readu8(perm, b), 7) * 16
	local i11 = band(readu8(perm, b + 1), 7) * 16

	local g00x, g00y = readf64(GRAD2, i00), readf64(GRAD2, i00 + 8)
	local g10x, g10y = readf64(GRAD2, i10), readf64(GRAD2, i10 + 8)
	local g01x, g01y = readf64(GRAD2, i01), readf64(GRAD2, i01 + 8)
	local g11x, g11y = readf64(GRAD2, i11), readf64(GRAD2, i11 + 8)

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

	local i000 = readu8(perm, aa) % 12 * 24
	local i100 = readu8(perm, ba) % 12 * 24
	local i010 = readu8(perm, ab) % 12 * 24
	local i110 = readu8(perm, bb) % 12 * 24
	local i001 = readu8(perm, aa + 1) % 12 * 24
	local i101 = readu8(perm, ba + 1) % 12 * 24
	local i011 = readu8(perm, ab + 1) % 12 * 24
	local i111 = readu8(perm, bb + 1) % 12 * 24

	local n000 = readf64(GRAD3, i000) * xf + readf64(GRAD3, i000 + 8) * yf + readf64(GRAD3, i000 + 16) * zf
	local n100 = readf64(GRAD3, i100) * xf1 + readf64(GRAD3, i100 + 8) * yf + readf64(GRAD3, i100 + 16) * zf
	local n010 = readf64(GRAD3, i010) * xf + readf64(GRAD3, i010 + 8) * yf1 + readf64(GRAD3, i010 + 16) * zf
	local n110 = readf64(GRAD3, i110) * xf1 + readf64(GRAD3, i110 + 8) * yf1 + readf64(GRAD3, i110 + 16) * zf
	local n001 = readf64(GRAD3, i001) * xf + readf64(GRAD3, i001 + 8) * yf + readf64(GRAD3, i001 + 16) * zf1
	local n101 = readf64(GRAD3, i101) * xf1 + readf64(GRAD3, i101 + 8) * yf + readf64(GRAD3, i101 + 16) * zf1
	local n011 = readf64(GRAD3, i011) * xf + readf64(GRAD3, i011 + 8) * yf1 + readf64(GRAD3, i011 + 16) * zf1
	local n111 = readf64(GRAD3, i111) * xf1 + readf64(GRAD3, i111 + 8) * yf1 + readf64(GRAD3, i111 + 16) * zf1

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

	local i000 = readu8(perm, aa) % 12 * 24
	local i100 = readu8(perm, ba) % 12 * 24
	local i010 = readu8(perm, ab) % 12 * 24
	local i110 = readu8(perm, bb) % 12 * 24
	local i001 = readu8(perm, aa + 1) % 12 * 24
	local i101 = readu8(perm, ba + 1) % 12 * 24
	local i011 = readu8(perm, ab + 1) % 12 * 24
	local i111 = readu8(perm, bb + 1) % 12 * 24

	local g000x, g000y, g000z = readf64(GRAD3, i000), readf64(GRAD3, i000 + 8), readf64(GRAD3, i000 + 16)
	local g100x, g100y, g100z = readf64(GRAD3, i100), readf64(GRAD3, i100 + 8), readf64(GRAD3, i100 + 16)
	local g010x, g010y, g010z = readf64(GRAD3, i010), readf64(GRAD3, i010 + 8), readf64(GRAD3, i010 + 16)
	local g110x, g110y, g110z = readf64(GRAD3, i110), readf64(GRAD3, i110 + 8), readf64(GRAD3, i110 + 16)
	local g001x, g001y, g001z = readf64(GRAD3, i001), readf64(GRAD3, i001 + 8), readf64(GRAD3, i001 + 16)
	local g101x, g101y, g101z = readf64(GRAD3, i101), readf64(GRAD3, i101 + 8), readf64(GRAD3, i101 + 16)
	local g011x, g011y, g011z = readf64(GRAD3, i011), readf64(GRAD3, i011 + 8), readf64(GRAD3, i011 + 16)
	local g111x, g111y, g111z = readf64(GRAD3, i111), readf64(GRAD3, i111 + 8), readf64(GRAD3, i111 + 16)

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
