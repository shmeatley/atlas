-- Visual demo: pops up one Visualizer window per Atlas feature.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(ReplicatedStorage.Atlas)

local Noise = Atlas.Noise
local Presets = Atlas.Visualizer.Presets

local simplex = Noise.Simplex.new(1337)
local voronoi = Noise.Voronoi.new(1337)

local falloff = Atlas.Curve.new({
	Vector2.new(0, 0),
	Vector2.new(0.35, 0.08),
	Vector2.new(0.6, 0.75),
	Vector2.new(1, 1),
})

-- Any table with a sample2D method works as a sampler, so fBm composes in.
local fbmSampler = {
	sample2D = function(_, x: number, y: number): number
		return Noise.fbm2D(simplex, x, y, 4)
	end,
}

local noiseWindow = Atlas.Visualizer.new({ title = "fBm simplex × falloff curve" })
noiseWindow:render(Presets.noise(fbmSampler, { scale = 0.015, curve = falloff }))

local voronoiWindow = Atlas.Visualizer.new({ title = "Voronoi F1" })
voronoiWindow:render(Presets.noise(voronoi, { scale = 0.04, rangeMin = 0, rangeMax = 1 }))

local curveWindow = Atlas.Visualizer.new({ title = "Falloff curve" })
curveWindow:draw(Presets.curve(falloff))

local points = Atlas.Sampling.poissonDisc(100, 100, 4, 2026)
local pointsWindow = Atlas.Visualizer.new({ title = `Poisson disc ({#points} points)` })
pointsWindow:draw(Presets.points(points, { width = 100, height = 100 }))

local uniformPoints = Atlas.Sampling.uniform(100, 100, 500, 42)
local uniformWindow = Atlas.Visualizer.new({ title = `Uniform ({#uniformPoints} points)` })
uniformWindow:draw(Presets.points(uniformPoints, { width = 100, height = 100 }))

local blueNoisePoints = Atlas.Sampling.blueNoiseGrid(100, 100, 5, 42, 1)
local blueNoiseWindow = Atlas.Visualizer.new({ title = `Blue noise grid ({#blueNoisePoints} points)` })
blueNoiseWindow:draw(Presets.points(blueNoisePoints, { width = 100, height = 100 }))

local terrainWindow = Atlas.Visualizer.new({ title = "Terrain demo" })

local function getHeight(x: number, y: number): number
	-- large continent shape (low frequency)
	local continent = Noise.fbm2D(simplex, x * 0.004, y * 0.004, 4)

	-- medium detail
	local hills = Noise.fbm2D(simplex, x * 0.01, y * 0.01, 3) * 0.35

	-- small detail (very subtle, optional)
	local detail = Noise.fbm2D(simplex, x * 0.02, y * 0.02, 2) * 0.15

	-- normalize from roughly [-1, 1] → [0, 1]
	local h = (continent + 1) * 0.5 + hills + detail

	return h
end

local function getSlope(x: number, y: number): number
	local e = 0.002

	local hL = getHeight(x - e, y)
	local hR = getHeight(x + e, y)
	local hD = getHeight(x, y - e)
	local hU = getHeight(x, y + e)

	local dx = hR - hL
	local dy = hU - hD

	return math.sqrt(dx * dx + dy * dy)
end

local function terrainShader(x: number, y: number): (number, number, number)
	local h = getHeight(x, y)
	local s = getSlope(x, y)

	-- water (now actually meaningful range)
	if h < 0.45 then
		local t = math.clamp(h / 0.45, 0, 1)
		return 0.02 * t, 0.15 * t, 0.5 + 0.35 * t
	end

	-- beach
	if h < 0.5 then
		return 0.76, 0.72, 0.55
	end

	-- grass
	if h < 0.7 then
		local t = (h - 0.5) / 0.2
		return 0.12 + 0.08 * t, 0.45 + 0.25 * t, 0.12
	end

	-- rock (slope-based)
	if s > 0.18 then
		local t = math.clamp((s - 0.18) / 0.4, 0, 1)
		local g = 0.35 + 0.25 * (1 - t)
		return g, g, g
	end

	-- mountain
	if h < 0.85 then
		local t = (h - 0.7) / 0.15
		local g = 0.25 + 0.2 * t
		return g, g, g
	end

	-- snow
	local t = math.clamp((h - 0.85) / 0.15, 0, 1)
	return 0.9, 0.9, 0.95
end

terrainWindow:render(terrainShader)