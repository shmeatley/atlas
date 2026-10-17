--!strict
--!native
--!optimize 2

local Permutation = require(script.Parent.Permutation)

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
	differences. The distance field is not differentiable on cell borders.

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
