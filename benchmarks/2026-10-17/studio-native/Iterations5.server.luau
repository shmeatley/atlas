--!native
--!optimize 2
local root=game.ReplicatedStorage.AtlasNativeExperiments
local variants={}
for _,name in {'guarded','prehash'} do
 local folder=root[name]
 variants[name]={Perlin=require(folder.Perlin).new(42), Simplex=require(folder.Simplex).new(42)}
end
local function timed(fn, count)
 local sum=0
 local start=os.clock()
 for i=1,count do sum+=fn(i) end
 return (os.clock()-start)*1e6/count,sum
end
local function compare(label,a,b,count)
 for i=1,50 do assert(a(i)==b(i),label..' warmup parity') end
 local ta,tb={},{}
 local raw={}
 for trial=1,15 do
  task.wait()
  local ca,cb
  if trial%2==0 then ta[trial],ca=timed(a,count); tb[trial],cb=timed(b,count)
  else tb[trial],cb=timed(b,count); ta[trial],ca=timed(a,count) end
  assert(ca==cb,label..' checksum parity')
  raw[trial]=string.format('%.6f/%.6f',ta[trial],tb[trial])
 end
 table.sort(ta);table.sort(tb)
 print(string.format('PAIRED|%s|%.9f|%.9f|%.3f%%|%s',label,ta[8],tb[8],(1-tb[8]/ta[8])*100,table.concat(raw,',')))
end
for _,variant in {'prehash'} do
 for _,name in {'Perlin','Simplex'} do
  
  local a,b=variants.guarded[name],variants[variant][name]
  for _,dim in {3} do
   
   
   local method='sample'..dim..'D'
   local fa,fb=a[method],b[method]
   compare(variant..' '..name..'.'..method,function(i) return fa(a,i*.137,i*.291,i*.173) end,function(i) return fb(b,i*.137,i*.291,i*.173) end,200000)
   local grid='sampleGrid'..dim..'D'
   
   compare(variant..' '..name..'.'..grid,function(i)
    local v=if dim==2 then a:sampleGrid2D(128,128,-.7+i*.03,-3.5,.137,-.137) else a:sampleGrid3D(32,32,32,-.7+i*.03,-3.5,.2,.137,-.137,.137)
    return v[1]+v[#v]
   end,function(i)
    local v=if dim==2 then b:sampleGrid2D(128,128,-.7+i*.03,-3.5,.137,-.137) else b:sampleGrid3D(32,32,32,-.7+i*.03,-3.5,.2,.137,-.137,.137)
    return v[1]+v[#v]
   end,20)
  end
 end
end
workspace:SetAttribute('AtlasIterationDone',true)
