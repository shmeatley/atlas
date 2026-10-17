-- Appended to the CLI bundle by tools/performance.py --reference baseline.
-- Baseline and Candidate are isolated copies of the complete numerical API.
local checked = 0
local function equalResults(a, b, label)
	assert(a.n == b.n, label .. " arity")
	for i = 1, a.n do
		assert(a[i] == b[i], string.format("%s result %d: %.17g ~= %.17g", label, i, a[i], b[i]))
		checked += 1
	end
end

for _, seed in { -2147483648, -1, 0, 42, 2147483646 } do
	for _, name in { "Perlin", "Simplex", "Voronoi" } do
		local a = Baseline.Noise[name].new(seed)
		local b = Candidate.Noise[name].new(seed)
		for i = 1, 3000 do
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
			assert(a[i] == b[i], method .. " point " .. i)
			checked += 1
		end
	end
end
print("PARITY: " .. checked .. " exact output comparisons passed")

-- Alternate baseline/candidate order within every trial to reduce timing drift.
local function paired(name, a, b, iterations)
	local before, after = {}, {}
	local function time(fn)
		local sum = 0
		local start = os.clock()
		for i = 1, iterations do
			sum += fn(i)
		end
		return (os.clock() - start) / iterations * 1e6, sum
	end
	for i = 1, 100 do
		a(i)
		b(i)
	end
	for trial = 1, 11 do
		local ca, cb
		if trial % 2 == 0 then
			before[trial], ca = time(a)
			after[trial], cb = time(b)
		else
			after[trial], cb = time(b)
			before[trial], ca = time(a)
		end
		assert(ca == cb, name .. " benchmark checksum")
	end
	table.sort(before)
	table.sort(after)
	print(string.format("PAIRED|%s|%.6f|%.6f|%.2f%%", name, before[6], after[6], (1 - after[6] / before[6]) * 100))
end
for _, name in { "Perlin", "Simplex", "Voronoi" } do
	local a, b = Baseline.Noise[name].new(42), Candidate.Noise[name].new(42)
	local methods = if name ~= "Voronoi"
		then { "sample2D", "sample3D", "sample2DWithDerivative", "sample3DWithDerivative" }
		else { "sample2D", "sample3D", "cell2D", "cell3D" }
	for _, method in methods do
		local fa, fb = a[method], b[method]
		paired(name .. "." .. method, function(i)
			return fa(a, i * 0.137, i * 0.291, i * 0.173)
		end, function(i)
			return fb(b, i * 0.137, i * 0.291, i * 0.173)
		end, 200000)
	end
end
paired("Sampling.poissonDisc", function(i)
	return #Baseline.Sampling.poissonDisc(100, 100, 5, i)
end, function(i)
	return #Candidate.Sampling.poissonDisc(100, 100, 5, i)
end, 100)

for _, name in { "Perlin", "Simplex" } do
	paired(name .. ".new", function(i)
		return Baseline.Noise[name].new(i).seed
	end, function(i)
		return Candidate.Noise[name].new(i).seed
	end, 500)
	local a, b = Baseline.Noise[name].new(42), Candidate.Noise[name].new(42)
	paired(name .. " fbm2D (4 octaves)", function(i)
		return Baseline.Noise.fbm2D(a, i * 0.037, i * 0.059, 4)
	end, function(i)
		return Candidate.Noise.fbm2D(b, i * 0.037, i * 0.059, 4)
	end, 100000)
end
