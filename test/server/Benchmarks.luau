--!native
--!optimize 2

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(ReplicatedStorage.Atlas)

local clock = os.clock
local format = string.format
local clamp = math.clamp
local floor = math.floor
local writeu32 = buffer.writeu32

local Benchmarks = {}

local function bench(name: string, iterations: number, fn: (i: number) -> number)
	for i = 1, 50 do
		fn(i)
	end

	local checksum = 0
	local start = clock()
	for i = 1, iterations do
		checksum += fn(i)
	end
	local elapsed = clock() - start

	print(
		format(
			"%-42s %9.3f ms  %9.3f us/op  [n=%d, checksum=%.4f]",
			name,
			elapsed * 1000,
			elapsed / iterations * 1e6,
			iterations,
			checksum
		)
	)
end

function Benchmarks.run()
	print("Atlas benchmarks (times include closure-call overhead; run on a live")
	print("server or with Studio native codegen enabled for --!native speeds)")

	local perlin = Atlas.Noise.Perlin.new(42)
	local simplex = Atlas.Noise.Simplex.new(42)
	local voronoi = Atlas.Noise.Voronoi.new(42)
	local island = Atlas.Noise.Island.new({ seed = 42 })
	local fbm2D = Atlas.Noise.fbm2D
	local curve = Atlas.Curve.new({
		Vector2.new(0, 0),
		Vector2.new(0.15, 0.02),
		Vector2.new(0.3, 0.1),
		Vector2.new(0.45, 0.3),
		Vector2.new(0.6, 0.55),
		Vector2.new(0.75, 0.8),
		Vector2.new(0.9, 0.95),
		Vector2.new(1, 1),
	})

	local perlinSample2D = perlin.sample2D
	local perlinSample3D = perlin.sample3D
	local perlinDerivative2D = perlin.sample2DWithDerivative
	local perlinDerivative3D = perlin.sample3DWithDerivative
	local simplexSample2D = simplex.sample2D
	local simplexSample3D = simplex.sample3D
	local simplexDerivative2D = simplex.sample2DWithDerivative
	local simplexDerivative3D = simplex.sample3DWithDerivative
	local voronoiSample2D = voronoi.sample2D
	local voronoiSample3D = voronoi.sample3D
	local voronoiCell2D = voronoi.cell2D
	local islandSample2D = island.sample2D
	local evaluate = curve.evaluate
	local uniform = Atlas.Sampling.uniform
	local poissonDisc = Atlas.Sampling.poissonDisc
	local blueNoiseGrid = Atlas.Sampling.blueNoiseGrid
	local mnoise = math.noise

	bench("ROBLOX-PERLIN-2d", 100000, function(i)
		return math.noise(i * 0.137, i * 0.291)
	end)

	bench("ROBLOX-PERLIN-2d-cached", 100000, function(i)
		return mnoise(i * 0.137, i * 0.291)
	end)
	bench("Perlin.sample2D", 100000, function(i)
		return perlinSample2D(perlin, i * 0.137, i * 0.291)
	end)
	bench("Perlin.sample2DWithDerivative", 100000, function(i)
		local value, dx, dy = perlinDerivative2D(perlin, i * 0.137, i * 0.291)
		return value + dx + dy
	end)

	bench("ROBLOX-PERLIN-3d", 100000, function(i)
		return math.noise(i * 0.137, i * 0.291, i * 0.173)
	end)
	bench("ROBLOX-PERLIN-3d-cached", 100000, function(i)
		return mnoise(i * 0.137, i * 0.291, i * 0.173)
	end)
	bench("Perlin.sample3D", 100000, function(i)
		return perlinSample3D(perlin, i * 0.137, i * 0.291, i * 0.173)
	end)

	bench("Perlin.sample3DWithDerivative", 100000, function(i)
		local value, dx, dy, dz = perlinDerivative3D(perlin, i * 0.137, i * 0.291, i * 0.173)
		return value + dx + dy + dz
	end)

	bench("Simplex.sample2D", 1000, function(i)
		return simplexSample2D(simplex, i * 0.137, i * 0.291)
	end)
	bench("Simplex.sample3D", 1000, function(i)
		return simplexSample3D(simplex, i * 0.137, i * 0.291, i * 0.173)
	end)
	bench("Simplex.sample2DWithDerivative", 1000, function(i)
		local value, dx, dy = simplexDerivative2D(simplex, i * 0.137, i * 0.291)
		return value + dx + dy
	end)
	bench("Simplex.sample3DWithDerivative", 1000, function(i)
		local value, dx, dy, dz = simplexDerivative3D(simplex, i * 0.137, i * 0.291, i * 0.173)
		return value + dx + dy + dz
	end)

	bench("Voronoi.sample2D", 1000, function(i)
		return voronoiSample2D(voronoi, i * 0.137, i * 0.291)
	end)
	bench("Voronoi.sample3D", 1000, function(i)
		return voronoiSample3D(voronoi, i * 0.137, i * 0.291, i * 0.173)
	end)
	bench("Voronoi.cell2D", 1000, function(i)
		local f1, f2 = voronoiCell2D(voronoi, i * 0.137, i * 0.291)
		return f1 + f2
	end)

	bench("Island.sample2D", 1000, function(i)
		return islandSample2D(island, (i % 128 - 64) * 0.02, (floor(i / 128) - 4) * 0.08)
	end)

	bench("Noise.fbm2D (4 octaves, simplex)", 1000, function(i)
		return fbm2D(simplex, i * 0.037, i * 0.059, 4)
	end)

	bench("Curve.evaluate (8 points)", 1000, function(i)
		return evaluate(curve, (i % 100) * 0.01)
	end)

	bench("Sampling.uniform (256 points)", 1000, function(i)
		return #uniform(100, 100, 256, i)
	end)
	bench("Sampling.poissonDisc (100x100, r=5)", 1000, function(i)
		return #poissonDisc(100, 100, 5, i)
	end)
	bench("Sampling.blueNoiseGrid (100x100, cellSize=3)", 1000, function(i)
		return #blueNoiseGrid(100, 100, 3, i)
	end)

	local pixelCallback = Atlas.Visualizer.Presets.noise(simplex, { scale = 0.05 })
	local canvas = buffer.create(128 * 128 * 4)
	bench("Visualizer render math (128x128)", 100, function(i)
		local offset = 0
		for y = 0, 127 do
			for x = 0, 127 do
				local r, g, b = pixelCallback(x + i, y)
				writeu32(
					canvas,
					offset,
					floor(clamp(r, 0, 1) * 255 + 0.5)
						+ floor(clamp(g, 0, 1) * 255 + 0.5) * 0x100
						+ floor(clamp(b, 0, 1) * 255 + 0.5) * 0x10000
						+ 0xFF000000
				)
				offset += 4
			end
		end
		return buffer.readu8(canvas, 0)
	end)
end

return Benchmarks
