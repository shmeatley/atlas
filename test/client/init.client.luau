-- Visual demo: pops up one Visualizer window per Atlas feature.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(ReplicatedStorage.Atlas)

local Noise = Atlas.Noise

local simplex = Noise.Simplex.new(1337)


-- Any table with a sample2D method works as a sampler, so fBm composes in.

local terrainWindow = Atlas.Visualizer.new({ title = "Terrain demo" })

-- Response curves reshape the normalized fBm before it's summed into the
-- height field. Continent carves flat ocean shelves and inland plains with a
-- steep coastline between them, instead of a linear gradient. Hills flattens
-- valleys and sharpens peaks so the mid-frequency detail reads as rolling
-- hills rather than uniform noise.
local continentCurve = Atlas.Curve.new({
	Vector2.new(0, 0),
	Vector2.new(0.3, 0.05),
	Vector2.new(0.45, 0.15),
	Vector2.new(0.55, 0.55),
	Vector2.new(0.75, 0.68),
	Vector2.new(1, 1),
})

local hillsCurve = Atlas.Curve.new({
	Vector2.new(0, 0),
	Vector2.new(0.5, 0.3),
	Vector2.new(0.8, 0.75),
	Vector2.new(1, 1),
})

-- fbm2DWithDerivative gives us the slope of each noise layer for free (fBm's
-- derivative is just the same amplitude/frequency-weighted sum used for the
-- value), so getHeight returns dx/dy alongside h instead of getSlope
-- resampling the whole field four times via finite differences.
local function getHeight(x: number, y: number): (number, number, number)
	-- large continent shape (low frequency), normalized to [0, 1] and shaped
	-- through the continent curve
	local continentRaw, continentRawDx, continentRawDy = Noise.fbm2DWithDerivative(simplex, x * 0.004, y * 0.004, 4)
	local continent, continentSlope = continentCurve:evaluateWithDerivative(continentRaw * 0.5 + 0.5)

	-- medium detail, normalized to [0, 1] and shaped through the hills curve
	local hillsRaw, hillsRawDx, hillsRawDy = Noise.fbm2DWithDerivative(simplex, x * 0.01, y * 0.01, 3)
	local hillsShaped, hillsSlope = hillsCurve:evaluateWithDerivative(hillsRaw * 0.5 + 0.5)
	local hills = hillsShaped * 0.35

	-- small detail (very subtle, optional)
	local detailRaw, detailRawDx, detailRawDy = Noise.fbm2DWithDerivative(simplex, x * 0.02, y * 0.02, 2)
	local detail = detailRaw * 0.15

	local h = continent + hills + detail

	-- chain rule through each layer's coordinate scale and curve, then sum --
	-- same additive structure as fBm itself
	local dx = continentSlope * (continentRawDx * 0.004) * 0.5
		+ hillsSlope * (hillsRawDx * 0.01) * 0.5 * 0.35
		+ (detailRawDx * 0.02) * 0.15
	local dy = continentSlope * (continentRawDy * 0.004) * 0.5
		+ hillsSlope * (hillsRawDy * 0.01) * 0.5 * 0.35
		+ (detailRawDy * 0.02) * 0.15

	return h, dx, dy
end

local function getSlope(dx: number, dy: number): number
	return math.sqrt(dx * dx + dy * dy)
end

local function terrainShader(x: number, y: number): (number, number, number)
	local h, dx, dy = getHeight(x, y)
	local s = getSlope(dx, dy)

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