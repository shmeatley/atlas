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

--[=[
 Samples a rectangular grid into a new row-major array (X varies fastest).
 Coordinates use start + zero-based index * step on each axis, exactly as
 repeated sample2D calls. Negative and zero steps are supported. Dimensions
 must be non-negative integers; any zero dimension returns an empty array.
 Array index: `row * width + column + 1`.

 @method sampleGrid2D
 @within Simplex
 @param width number -- X samples.
 @param height number -- Y samples.
 @param startX number
 @param startY number
 @param stepX number
 @param stepY number
 @return {number} -- Samples in grid order.
]=]
function Simplex.sampleGrid2D(
	self: Simplex,
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
	if width * height == 0 then
		return values
	end
	local perm = self._perm
	local gradients = self._grad2
	local index = 0
	for row = 0, height - 1 do
		local y = startY + row * stepY
		for column = 0, width - 1 do
			local x = startX + column * stepX
			index += 1
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

			values[index] = n * SCALE2
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
 @within Simplex
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
function Simplex.sampleGrid3D(
	self: Simplex,
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
	local index = 0
	for slice = 0, depth - 1 do
		local z = startZ + slice * stepZ
		for row = 0, height - 1 do
			local y = startY + row * stepY
			for column = 0, width - 1 do
				local x = startX + column * stepX
				index += 1
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
					n += t02 * t02 * (readf64(gradients, gi0) * x0 + readf64(gradients, gi0 + 8) * y0 + readf64(
						gradients,
						gi0 + 16
					) * z0)
				end

				local t1 = 0.5 - x1 * x1 - y1 * y1 - z1 * z1
				if t1 > 0 then
					local t12 = t1 * t1
					n += t12 * t12 * (readf64(gradients, gi1) * x1 + readf64(gradients, gi1 + 8) * y1 + readf64(
						gradients,
						gi1 + 16
					) * z1)
				end

				local t2 = 0.5 - x2 * x2 - y2 * y2 - z2 * z2
				if t2 > 0 then
					local t22 = t2 * t2
					n += t22 * t22 * (readf64(gradients, gi2) * x2 + readf64(gradients, gi2 + 8) * y2 + readf64(
						gradients,
						gi2 + 16
					) * z2)
				end

				local t3 = 0.5 - x3 * x3 - y3 * y3 - z3 * z3
				if t3 > 0 then
					local t32 = t3 * t3
					n += t32 * t32 * (readf64(gradients, gi3) * x3 + readf64(gradients, gi3 + 8) * y3 + readf64(
						gradients,
						gi3 + 16
					) * z3)
				end

				values[index] = n * SCALE3
			end
		end
	end
	return values
end

return Simplex
