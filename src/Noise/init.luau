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
