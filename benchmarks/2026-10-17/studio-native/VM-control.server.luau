
--!optimize 2
-- Run as a server Script in the isolated place built by tools/studio_native.py.
local root = game.ReplicatedStorage.AtlasNativeExperiments
local variants = {}
for _, label in { "baseline_vm", "final_vm" } do
	local folder = root[label]
	variants[label] = {
		Perlin = require(folder.Perlin).new(42),
		Simplex = require(folder.Simplex).new(42),
	}
end
local raw = {}
local function measure(fn, count)
	local checksum = 0
	local start = os.clock()
	for i = 1, count do
		checksum += fn(i)
	end
	return (os.clock() - start) * 1e6 / count, checksum
end
local function bench(label, before, after, builtin, count)
	local methods = { before, after, builtin }
	for _, fn in methods do
		for i = 1, 30 do
			fn(i)
		end
	end
	local times = { {}, {}, {} }
	local orders = { { 1, 2, 3 }, { 3, 2, 1 }, { 2, 3, 1 }, { 1, 3, 2 }, { 3, 1, 2 }, { 2, 1, 3 } }
	for trial = 1, 7 do
		task.wait()
		local sums = {}
		for _, k in orders[(trial - 1) % 6 + 1] do
			times[k][trial], sums[k] = measure(methods[k], count)
		end
		assert(sums[1] == sums[2], label .. " exact checksum")
		raw[#raw + 1] = string.format(
			"TRIAL|%s|%d|%.9f|%.9f|%.9f|%.17g|%.17g",
			label,
			trial,
			times[1][trial],
			times[2][trial],
			times[3][trial],
			sums[1],
			sums[3]
		)
	end
	for k, name in { "release", "optimized", "math.noise" } do
		table.sort(times[k])
		print(
			string.format("VM|%s|%s|%d|%.9f|%.9f|%.9f", label, name, count, times[k][4], times[k][1], times[k][7])
		)
	end
end
local function builtin2D(w, h, sx, sy, dx, dy)
	local values = table.create(w * h)
	local index = 0
	for row = 0, h - 1 do
		local y = sy + row * dy
		for col = 0, w - 1 do
			index += 1
			values[index] = math.noise(sx + col * dx, y)
		end
	end
	return values
end
local function builtin3D(w, h, d, sx, sy, sz, dx, dy, dz)
	local values = table.create(w * h * d)
	local index = 0
	for slice = 0, d - 1 do
		local z = sz + slice * dz
		for row = 0, h - 1 do
			local y = sy + row * dy
			for col = 0, w - 1 do
				index += 1
				values[index] = math.noise(sx + col * dx, y, z)
			end
		end
	end
	return values
end
for _, name in { "Perlin", "Simplex" } do
	local a, b = variants.baseline_vm[name], variants.final_vm[name]
	local a2, b2 = a.sample2D, b.sample2D
	bench(name .. " scalar2D", function(i)
		return a2(a, i * 0.137, i * 0.291)
	end, function(i)
		return b2(b, i * 0.137, i * 0.291)
	end, function(i)
		return math.noise(i * 0.137, i * 0.291)
	end, 100000)
	local a3, b3 = a.sample3D, b.sample3D
	bench(name .. " scalar3D", function(i)
		return a3(a, i * 0.137, i * 0.291, i * 0.173)
	end, function(i)
		return b3(b, i * 0.137, i * 0.291, i * 0.173)
	end, function(i)
		return math.noise(i * 0.137, i * 0.291, i * 0.173)
	end, 100000)
	bench(name .. " grid2D 128x128", function(i)
		local v = a:sampleGrid2D(128, 128, -0.7 + i * 0.03, -3.5, 0.137, -0.137)
		return v[1] + v[#v]
	end, function(i)
		local v = b:sampleGrid2D(128, 128, -0.7 + i * 0.03, -3.5, 0.137, -0.137)
		return v[1] + v[#v]
	end, function(i)
		local v = builtin2D(128, 128, -0.7 + i * 0.03, -3.5, 0.137, -0.137)
		return v[1] + v[#v]
	end, 10)
	bench(name .. " grid3D 32x32x32", function(i)
		local v = a:sampleGrid3D(32, 32, 32, -0.7 + i * 0.03, -3.5, 0.2, 0.137, -0.137, 0.137)
		return v[1] + v[#v]
	end, function(i)
		local v = b:sampleGrid3D(32, 32, 32, -0.7 + i * 0.03, -3.5, 0.2, 0.137, -0.137, 0.137)
		return v[1] + v[#v]
	end, function(i)
		local v = builtin3D(32, 32, 32, -0.7 + i * 0.03, -3.5, 0.2, 0.137, -0.137, 0.137)
		return v[1] + v[#v]
	end, 10)
end
local data = table.concat(raw, "\n")
local result = Instance.new("StringValue")
result.Name = "AtlasNativeResults"
result.Value = data
result.Parent = workspace
print("NATIVE BENCHMARK COMPLETE")
workspace:SetAttribute("AtlasNativeDone", true)
