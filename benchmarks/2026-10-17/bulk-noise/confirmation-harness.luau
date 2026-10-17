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
		assert(a[i] == b[i], string.format("grid index %d: %.17g ~= %.17g", i, a[i], b[i]))
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
for _, name in { "Perlin", "Simplex" } do
	local a, b = Baseline.Noise[name].new(42), Candidate.Noise[name].new(42)
	local sampleA, sampleB = a.sample3D, b.sample3D
	paired(name .. " scalar3D control", function(i)
		return sampleA(a, i * 0.137, i * 0.291, i * 0.173)
	end, function(i)
		return sampleB(b, i * 0.137, i * 0.291, i * 0.173)
	end, 100000)
	for _, shape in { { 32, 32, 32 }, { 256, 1, 1 } } do
		local w, h, d = table.unpack(shape)
		for _, step in { 0.137, 1.3 } do
			paired(name .. " grid3D " .. w .. "x" .. h .. "x" .. d .. " step " .. step, function(i)
				local v = scalarGrid3D(a, w, h, d, -0.7 + i * 0.03, -3.5, 0.2, step, -step, step)
				return v[1] + v[#v]
			end, function(i)
				local v = b:sampleGrid3D(w, h, d, -0.7 + i * 0.03, -3.5, 0.2, step, -step, step)
				return v[1] + v[#v]
			end, if w == 32 then 10 else 20)
		end
	end
	if name == "Simplex" then
		for _, size in { 128 } do
			for _, step in { 0.137, 1.3 } do
				paired("Simplex grid2D " .. size .. " step " .. step, function(i)
					local v = scalarGrid2D(a, size, size, -0.7 + i * 0.03, -3.5, step, -step)
					return v[1] + v[#v]
				end, function(i)
					local v = b:sampleGrid2D(size, size, -0.7 + i * 0.03, -3.5, step, -step)
					return v[1] + v[#v]
				end, 20)
			end
		end
	end
end
