--!strict
--!native
--!optimize 2

local Simplex = require(script.Parent.Simplex)
local Permutation = require(script.Parent.Permutation)

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
