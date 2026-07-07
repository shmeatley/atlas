--!strict

local Curve = require(script.Curve)
local Noise = require(script.Noise)
local Sampling = require(script.Sampling)
local Visualizer = require(script.Visualizer)

export type Perlin = Noise.Perlin
export type Simplex = Noise.Simplex
export type Voronoi = Noise.Voronoi
export type Island = Noise.Island
export type NoiseSampler2D = Noise.NoiseSampler2D
export type NoiseSampler3D = Noise.NoiseSampler3D
export type NoiseSampler2DWithDerivative = Noise.NoiseSampler2DWithDerivative
export type NoiseSampler3DWithDerivative = Noise.NoiseSampler3DWithDerivative
export type Curve = Curve.Curve
export type Visualizer = Visualizer.Visualizer
export type VisualizerOptions = Visualizer.VisualizerOptions
export type PixelCallback = Visualizer.PixelCallback
export type DrawCallback = Visualizer.DrawCallback

--[=[
	@class Atlas

	A procedural generation toolkit for Roblox: seeded noise with analytical
	derivatives ([Noise]), point scattering ([Sampling]), response curves
	([Curve]), and on-screen debugging ([Visualizer]).

	```lua
	local Atlas = require(path.to.Atlas)

	local simplex = Atlas.Noise.Simplex.new(42)
	local falloff = Atlas.Curve.new({
		Vector2.new(0, 0),
		Vector2.new(0.6, 0.15),
		Vector2.new(1, 1),
	})

	local height = falloff:evaluate(Atlas.Noise.fbm2D(simplex, x * 0.01, z * 0.01, 4) * 0.5 + 0.5)
	```
]=]
local Atlas = {
	Noise = Noise,
	Sampling = Sampling,
	Curve = Curve,
	Visualizer = Visualizer,
}

return Atlas
