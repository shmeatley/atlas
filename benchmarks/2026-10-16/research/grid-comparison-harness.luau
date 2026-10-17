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

local function scalarGrid(sampler,width,height,startX,startY,stepX,stepY)
 local values=table.create(width*height)
 local sample=sampler.sample2D
 local index=0
 for row=0,height-1 do
  local y=startY+row*stepY
  for column=0,width-1 do
   index+=1
   values[index]=sample(sampler,startX+column*stepX,y)
  end
 end
 return values
end
local gridChecks=0
for _,seed in {-1,42,1234567} do
 local a,b=Baseline.Noise.Perlin.new(seed),Candidate.Noise.Perlin.new(seed)
 for _,size in {1,8,16,64,128} do
  for _,config in {{-.7,-3.5,.01,.03},{65535.9,-65536.2,-.137,.291},{0,0,1,1},{1,2,0,0},{.3,.7,2.1,-3.2}} do
   local old=scalarGrid(a,size,size,table.unpack(config))
   local new=b:sampleGrid2D(size,size,table.unpack(config))
   assert(#old==#new,"grid length")
   for i=1,#old do assert(old[i]==new[i],"grid value "..i);gridChecks+=1 end
  end
 end
 assert(#b:sampleGrid2D(0,8,0,0,.1,.1)==0,"empty grid")
 assert(not pcall(function() b:sampleGrid2D(-1,8,0,0,.1,.1) end),"negative width")
end
print("GRID PARITY: "..gridChecks.." exact comparisons passed")
local a,b=Baseline.Noise.Perlin.new(42),Candidate.Noise.Perlin.new(42)
for _,size in {16,64,128,256} do
 for _,step in {.01,.137,1.3} do
  paired("Perlin grid "..size.." step "..step,function(i) local v=(a.sampleGrid2D or scalarGrid)(a,size,size,-.7+i*.03,-3.5,step,step);return v[1]+v[#v] end,
   function(i) local v=b:sampleGrid2D(size,size,-.7+i*.03,-3.5,step,step);return v[1]+v[#v] end,if size==256 then 10 else 30)
 end
end
