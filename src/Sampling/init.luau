--!strict
--!native
--!optimize 2

local Permutation = require(script.Parent.Noise.Permutation)

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
	local points: { Vector3 } = table.create(64)
	local active: { number } = table.create(64)

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

				local ok = true

				for ix = max(cgx - 2, 0), min(cgx + 2, gridW - 1) do
					local base = ix * gridH

					for iy = max(cgy - 2, 0), min(cgy + 2, gridH - 1) do
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
