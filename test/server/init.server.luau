local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(ReplicatedStorage.Atlas)
local Benchmarks = require(script.Benchmarks)

local passed = 0
local failed = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		--print(`[PASS] {name}`)
	else
		failed += 1
		warn(`[FAIL] {name}{if detail then ` — {detail}` else ""}`)
	end
end

-- Determinism
do
	local a = Atlas.Noise.Perlin.new(42)
	local b = Atlas.Noise.Perlin.new(42)
	local c = Atlas.Noise.Perlin.new(43)
	check("Perlin: same seed matches", a:sample2D(1.5, 2.5) == b:sample2D(1.5, 2.5))
	check("Perlin: different seed differs", a:sample2D(1.5, 2.5) ~= c:sample2D(1.5, 2.5))

	local s1 = Atlas.Noise.Simplex.new(7)
	local s2 = Atlas.Noise.Simplex.new(7)
	check("Simplex: same seed matches", s1:sample3D(1.5, 2.5, 3.5) == s2:sample3D(1.5, 2.5, 3.5))

	local v1 = Atlas.Noise.Voronoi.new(7)
	local v2 = Atlas.Noise.Voronoi.new(7)
	check("Voronoi: same seed matches", v1:sample2D(1.5, 2.5) == v2:sample2D(1.5, 2.5))

	local i1 = Atlas.Noise.Island.new({ seed = 7 })
	local i2 = Atlas.Noise.Island.new({ seed = 7 })
	check("Island: same seed matches", i1:sample2D(0.85, 0.15) == i2:sample2D(0.85, 0.15))

	local i3 = Atlas.Noise.Island.new({ seed = 8 })
	local islandSeedDiffers = false
	for sample = 1, 80 do
		local x = -1.2 + (sample % 16) * 0.15
		local y = -0.6 + math.floor(sample / 16) * 0.2
		if i1:sample2D(x, y) ~= i3:sample2D(x, y) then
			islandSeedDiffers = true
			break
		end
	end
	check("Island: different seed differs", islandSeedDiffers)
end

-- Output ranges
do
	local perlin = Atlas.Noise.Perlin.new(1)
	local simplex = Atlas.Noise.Simplex.new(1)
	local voronoi = Atlas.Noise.Voronoi.new(1)
	local island = Atlas.Noise.Island.new({ seed = 1 })

	local maxPerlin, maxSimplex2, maxSimplex3, minVoronoi = 0, 0, 0, math.huge
	local islandBinary = true
	for i = 1, 10000 do
		local x = i * 0.1237
		local y = i * 0.0719
		local z = i * 0.0413
		maxPerlin = math.max(maxPerlin, math.abs(perlin:sample2D(x, y)), math.abs(perlin:sample3D(x, y, z)))
		maxSimplex2 = math.max(maxSimplex2, math.abs(simplex:sample2D(x, y)))
		maxSimplex3 = math.max(maxSimplex3, math.abs(simplex:sample3D(x, y, z)))
		minVoronoi = math.min(minVoronoi, voronoi:sample2D(x, y))

		local islandValue = island:sample2D((i % 200 - 100) * 0.0125, (math.floor(i / 200) - 25) * 0.05)
		if islandValue ~= 0 and islandValue ~= 1 then
			islandBinary = false
		end
	end

	check("Perlin: output within [-1, 1]", maxPerlin <= 1 + 1e-6, `max |value| = {maxPerlin}`)
	check("Simplex 2D: output within [-1, 1]", maxSimplex2 <= 1.05, `max |value| = {maxSimplex2}`)
	check("Simplex 3D: output approximately [-1, 1]", maxSimplex3 <= 1.1, `max |value| = {maxSimplex3}`)
	check("Voronoi: distances non-negative", minVoronoi >= 0)
	check("Island: output is binary", islandBinary)
	check("Island: default center is land", island:sample2D(0, 0) == 1)
	check("Island: far outside radius is water", island:sample2D(2, 2) == 0)
	print(`  observed maxima — perlin {maxPerlin}, simplex2D {maxSimplex2}, simplex3D {maxSimplex3}`)
end

-- Island controls
do
	local smooth = Atlas.Noise.Island.new({ seed = 123, breakage = 0, detail = 0 })
	local broken = Atlas.Noise.Island.new({ seed = 123, breakage = 1, detail = 0 })
	local simple = Atlas.Noise.Island.new({ seed = 123, breakage = 0.35, detail = 0 })
	local detailed = Atlas.Noise.Island.new({ seed = 123, breakage = 0.35, detail = 1 })

	local breakageChangesMask = false
	local detailChangesMask = false
	for i = 1, 96 do
		local angle = i * 0.39269908169872414
		local radius = 0.78 + (i % 8) * 0.055
		local x = math.cos(angle) * radius
		local y = math.sin(angle) * radius

		if smooth:sample2D(x, y) ~= broken:sample2D(x, y) then
			breakageChangesMask = true
		end
		if simple:sample2D(x, y) ~= detailed:sample2D(x, y) then
			detailChangesMask = true
		end
	end

	check("Island: breakage changes shoreline", breakageChangesMask)
	check("Island: detail changes shoreline", detailChangesMask)
end

-- Analytical derivatives vs central finite differences
do
	local perlin = Atlas.Noise.Perlin.new(99)
	local simplex = Atlas.Noise.Simplex.new(99)
	local eps = 1e-4
	local worst = 0

	for i = 1, 200 do
		local x = i * 0.2117
		local y = i * 0.1291
		local z = i * 0.0871

		local _, pdx, pdy = perlin:sample2DWithDerivative(x, y)
		worst = math.max(worst, math.abs(pdx - (perlin:sample2D(x + eps, y) - perlin:sample2D(x - eps, y)) / (2 * eps)))
		worst = math.max(worst, math.abs(pdy - (perlin:sample2D(x, y + eps) - perlin:sample2D(x, y - eps)) / (2 * eps)))

		local _, pdx3, _, pdz3 = perlin:sample3DWithDerivative(x, y, z)
		worst = math.max(
			worst,
			math.abs(pdx3 - (perlin:sample3D(x + eps, y, z) - perlin:sample3D(x - eps, y, z)) / (2 * eps))
		)
		worst = math.max(
			worst,
			math.abs(pdz3 - (perlin:sample3D(x, y, z + eps) - perlin:sample3D(x, y, z - eps)) / (2 * eps))
		)

		local _, sdx, sdy = simplex:sample2DWithDerivative(x, y)
		worst =
			math.max(worst, math.abs(sdx - (simplex:sample2D(x + eps, y) - simplex:sample2D(x - eps, y)) / (2 * eps)))
		worst =
			math.max(worst, math.abs(sdy - (simplex:sample2D(x, y + eps) - simplex:sample2D(x, y - eps)) / (2 * eps)))

		local _, sdx3, sdy3 = simplex:sample3DWithDerivative(x, y, z)
		worst = math.max(
			worst,
			math.abs(sdx3 - (simplex:sample3D(x + eps, y, z) - simplex:sample3D(x - eps, y, z)) / (2 * eps))
		)
		worst = math.max(
			worst,
			math.abs(sdy3 - (simplex:sample3D(x, y + eps, z) - simplex:sample3D(x, y - eps, z)) / (2 * eps))
		)
	end

	check("Derivatives match finite differences", worst < 1e-3, `worst error = {worst}`)
end

-- fBm
do
	local simplex = Atlas.Noise.Simplex.new(5)
	local worst = 0
	for i = 1, 2000 do
		worst = math.max(worst, math.abs(Atlas.Noise.fbm2D(simplex, i * 0.0173, i * 0.0311, 4)))
	end
	check("fbm2D: renormalized output stays in range", worst <= 1.1, `max |value| = {worst}`)
	check("fbm2D: deterministic", Atlas.Noise.fbm2D(simplex, 3.7, 1.2, 4) == Atlas.Noise.fbm2D(simplex, 3.7, 1.2, 4))
end

-- Sampling
do
	local points = Atlas.Sampling.uniform(200, 100, 500, 42)
	local inBounds = true
	for _, point in points do
		if point.X < 0 or point.X >= 200 or point.Y < 0 or point.Y >= 100 then
			inBounds = false
			break
		end
	end
	check("uniform: returns count", #points == 500)
	check("uniform: points in bounds", inBounds)

	local radius = 6
	local disc = Atlas.Sampling.poissonDisc(60, 60, radius, 42)
	local discInBounds = true
	local minDistanceSq = math.huge
	for i = 1, #disc do
		local p = disc[i]
		if p.X < 0 or p.X >= 60 or p.Y < 0 or p.Y >= 60 then
			discInBounds = false
		end
		for j = i + 1, #disc do
			local q = disc[j]
			local dx = p.X - q.X
			local dy = p.Y - q.Y
			minDistanceSq = math.min(minDistanceSq, dx * dx + dy * dy)
		end
	end
	check("poissonDisc: produces points", #disc > 10, `count = {#disc}`)
	check("poissonDisc: points in bounds", discInBounds)
	check(
		"poissonDisc: pairwise distance >= radius",
		minDistanceSq >= radius * radius - 1e-9,
		`min distance = {math.sqrt(minDistanceSq)}`
	)
	check("poissonDisc: deterministic", Atlas.Sampling.poissonDisc(60, 60, radius, 42)[1] == disc[1])
end

-- Curve
do
	local controls = {
		Vector2.new(0, 0),
		Vector2.new(0.4, 0.1),
		Vector2.new(0.7, 0.8),
		Vector2.new(1, 1),
	}
	local curve = Atlas.Curve.new(controls)

	local throughPoints = true
	for _, point in controls do
		if math.abs(curve:evaluate(point.X) - point.Y) > 1e-9 then
			throughPoints = false
		end
	end
	check("Curve: passes through control points", throughPoints)
	check("Curve: clamps below domain", curve:evaluate(-5) == 0)
	check("Curve: clamps above domain", curve:evaluate(5) == 1)

	local overshoot = false
	for i = 0, 1000 do
		local value = curve:evaluate(i * 0.001)
		if value < -1e-9 or value > 1 + 1e-9 then
			overshoot = true
		end
	end
	check("Curve: monotone spline never overshoots", not overshoot)

	local mapped = curve:map({ 0, 0.4, 0.7, 1 })
	check("Curve: map matches evaluate", mapped[2] == curve:evaluate(0.4) and #mapped == 4)

	local minY, maxY = curve:range()
	local minX, maxX = curve:domain()
	check("Curve: domain and range", minX == 0 and maxX == 1 and minY == 0 and maxY == 1)
end

print(`Atlas smoke tests: {passed} passed, {failed} failed`)
if failed == 0 then
	print("")
	Benchmarks.run()
end

task.wait(1)

local benchmarks = require(script.Benchmarks)
benchmarks.run()
