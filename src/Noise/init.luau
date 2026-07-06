--!strict
--!native
--!optimize 2

local Perlin = require(script.Perlin)
local Simplex = require(script.Simplex)
local Voronoi = require(script.Voronoi)

export type Perlin = Perlin.Perlin
export type Simplex = Simplex.Simplex
export type Voronoi = Voronoi.Voronoi

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

return Noise
