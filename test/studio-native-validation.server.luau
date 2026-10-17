--!native
--!optimize 2
local root = game.ReplicatedStorage.AtlasNativeExperiments
local Baseline = table.clone(require(game.ReplicatedStorage.Atlas))
Baseline.Noise = table.clone(Baseline.Noise)
Baseline.Noise.Perlin = require(root.baseline.Perlin)
Baseline.Noise.Simplex = require(root.baseline.Simplex)
local Candidate = table.clone(Baseline)
Candidate.Noise = table.clone(Baseline.Noise)
Candidate.Noise.Perlin = require(root.final.Perlin)
Candidate.Noise.Simplex = require(root.final.Simplex)
-- The builder installs released and candidate noise modules in separate folders.
local checked = 0
local function equalResults(a, b, label)
	assert(a.n == b.n, label .. " arity")
	for i = 1, a.n do
		assert(
			a[i] == b[i] or (a[i] ~= a[i] and b[i] ~= b[i]),
			string.format("%s result %d: %.17g ~= %.17g", label, i, a[i], b[i])
		)
		if a[i] == 0 then
			assert(1 / a[i] == 1 / b[i], label .. " signed zero")
		end
		checked += 1
	end
end

for _, seed in { -2147483648, -1, 0, 42, 2147483646 } do
	for _, name in { "Perlin", "Simplex", "Voronoi" } do
		local a = Baseline.Noise[name].new(seed)
		local b = Candidate.Noise[name].new(seed)
		for i = 1, 3000 do
			if i % 300 == 0 then
				task.wait()
			end
			local x = (i - 1500) * 0.137
			local y = (i - 1000) * -0.291
			local z = (i - 2000) * 0.173
			if i % 5 == 0 then
				x = 65536 + i
			end
			if i % 7 == 0 then
				y = -65536 - i
			end
			if i % 11 == 0 then
				z = 0
			end
			for _, method in { "sample2D", "sample3D", "sample2DWithDerivative", "sample3DWithDerivative" } do
				if string.find(method, "2D") then
					equalResults(table.pack(a[method](a, x, y)), table.pack(b[method](b, x, y)), name .. "." .. method)
				else
					equalResults(
						table.pack(a[method](a, x, y, z)),
						table.pack(b[method](b, x, y, z)),
						name .. "." .. method
					)
				end
			end
			if name == "Voronoi" then
				for _, method in { "cell2D", "cell3D" } do
					equalResults(table.pack(a[method](a, x, y, z)), table.pack(b[method](b, x, y, z)), method)
				end
			end
		end
	end
	for _, method in { "uniform", "poissonDisc", "blueNoiseGrid" } do
		local count = if method == "uniform" then 256 elseif method == "poissonDisc" then 5 else 3
		local a = Baseline.Sampling[method](100, 100, count, seed)
		local b = Candidate.Sampling[method](100, 100, count, seed)
		assert(#a == #b, method .. " count")
		for i = 1, #a do
			assert(a[i] == b[i] or (a[i] ~= a[i] and b[i] ~= b[i]), method .. " point " .. i)
			if a[i] == 0 then
				assert(1 / a[i] == 1 / b[i], label .. " signed zero")
			end
			checked += 1
		end
	end
end
print("PARITY: " .. checked .. " exact output comparisons passed")

local function scalarGrid2D(sampler, w, h, sx, sy, dx, dy)
	local values = table.create(w * h)
	local sample = sampler.sample2D
	local index = 0
	for row = 0, h - 1 do
		local y = sy + row * dy
		for col = 0, w - 1 do
			index += 1
			values[index] = sample(sampler, sx + col * dx, y)
		end
	end
	return values
end
local function scalarGrid3D(sampler, w, h, d, sx, sy, sz, dx, dy, dz)
	local values = table.create(w * h * d)
	local sample = sampler.sample3D
	local index = 0
	for slice = 0, d - 1 do
		local z = sz + slice * dz
		for row = 0, h - 1 do
			local y = sy + row * dy
			for col = 0, w - 1 do
				index += 1
				values[index] = sample(sampler, sx + col * dx, y, z)
			end
		end
	end
	return values
end
local gridChecks = 0
local function same(a, b)
	assert(#a == #b, "grid length")
	for i = 1, #a do
		assert(
			a[i] == b[i] or (a[i] ~= a[i] and b[i] ~= b[i]),
			string.format("grid index %d: %.17g ~= %.17g", i, a[i], b[i])
		)
		-- Also distinguish signed zero.
		if a[i] == 0 then
			assert(1 / a[i] == 1 / b[i], "grid signed zero")
		end
		gridChecks += 1
	end
end
for _, seed in { 0, -1, 42, 2147483646 } do
	local configs = {
		{ -0.7, -3.5, 0.2, 0.01, 0.03, 0.07 },
		{ 65535.9, -65536.2, 255.9, -0.137, 0.291, -0.173 },
		{ 0, 0, 0, 1, 1, 1 },
		{ 0.3, 0.7, -0.3, 0, 0, 0 },
		{ -1e6, 1e6, -65536, 0.249, -0.25, 0.5 },
		{ 0.2, -0.3, 0.7, 1.3, -2.1, 0.99 },
	}
	for _, name in { "Perlin", "Simplex" } do
		local a, b = Baseline.Noise[name].new(seed), Candidate.Noise[name].new(seed)
		for _, shape in
			{
				{ 0, 4, 3 },
				{ 4, 0, 3 },
				{ 4, 3, 0 },
				{ 1, 1, 1 },
				{ 1, 7, 3 },
				{ 7, 1, 3 },
				{ 3, 7, 1 },
				{ 7, 5, 3 },
				{
					16,
					16,
					16,
				},
			}
		do
			local w, h, d = table.unpack(shape)
			for _, c in configs do
				task.wait()
				same(scalarGrid3D(a, w, h, d, table.unpack(c)), b:sampleGrid3D(w, h, d, table.unpack(c)))
				if name == "Simplex" then
					same(scalarGrid2D(a, w, h, c[1], c[2], c[4], c[5]), b:sampleGrid2D(w, h, c[1], c[2], c[4], c[5]))
				end
			end
		end
		for _, bad in { -1, 0.5 } do
			assert(not pcall(function()
				b:sampleGrid3D(bad, 1, 1, 0, 0, 0, 0.1, 0.1, 0.1)
			end), "invalid width")
			assert(not pcall(function()
				b:sampleGrid3D(1, bad, 1, 0, 0, 0, 0.1, 0.1, 0.1)
			end), "invalid height")
			assert(not pcall(function()
				b:sampleGrid3D(1, 1, bad, 0, 0, 0, 0.1, 0.1, 0.1)
			end), "invalid depth")
		end
	end
	local a, b = Baseline.Noise.Perlin.new(seed), Candidate.Noise.Perlin.new(seed)
	same(a:sampleGrid2D(32, 7, -0.7, 1.3, 0.137, -0.291), b:sampleGrid2D(32, 7, -0.7, 1.3, 0.137, -0.291))
end
print("BULK PARITY: " .. gridChecks .. " exact comparisons passed (including signed zero)")

local extra = 0
local coords = {
	0,
	-0,
	1,
	-1,
	255,
	256,
	-256,
	1e6,
	-1e6,
	2 ^ 31,
	-2 ^ 31,
	2 ^ 53,
	-2 ^ 53,
	1e16,
	-1e16,
	1e100,
	-1e100,
	1e308,
	-1e308,
	math.huge,
	-math.huge,
	0 / 0,
}
for _, name in { "Perlin", "Simplex" } do
	local a, b = Baseline.Noise[name].new(42), Candidate.Noise[name].new(42)
	for _, x in coords do
		for _, y in coords do
			for _, method in { "sample2D", "sample3D", "sample2DWithDerivative", "sample3DWithDerivative" } do
				local ar = table.pack(pcall(a[method], a, x, y, -y))
				local br = table.pack(pcall(b[method], b, x, y, -y))
				assert(ar[1] == br[1], name .. method .. " error parity")
				if ar[1] then
					table.remove(ar, 1)
					ar.n -= 1
					table.remove(br, 1)
					br.n -= 1
					equalResults(ar, br, name .. method .. " extreme " .. tostring(x) .. " " .. tostring(y))
				end
				extra += 1
			end
			task.wait()
		end
	end
end
print("EXTREME PARITY: " .. extra .. " calls passed")
workspace:SetAttribute("AtlasValidationDone", true)
