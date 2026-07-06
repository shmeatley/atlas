--!strict
--!native
--!optimize 2

local Curve = require(script.Parent.Parent.Curve)
local Noise = require(script.Parent.Parent.Noise)

local floor = math.floor
local max = math.max
local min = math.min
local writeu32 = buffer.writeu32

type Curve = Curve.Curve
type NoiseSampler2D = Noise.NoiseSampler2D

export type PixelCallback = (x: number, y: number) -> (number, number, number)
export type DrawCallback = (buf: buffer, width: number, height: number) -> ()

local function pack(r: number, g: number, b: number): number
	return r + g * 0x100 + b * 0x10000 + 0xFF000000
end

local COLOR_BACKGROUND = pack(24, 25, 31)
local COLOR_GRID = pack(52, 54, 66)
local COLOR_LINE = pack(126, 231, 135)
local COLOR_POINT = pack(255, 196, 87)

local function fill(buf: buffer, width: number, height: number, color: number)
	for offset = 0, width * height * 4 - 4, 4 do
		writeu32(buf, offset, color)
	end
end

--[=[
	@interface NoisePresetOptions
	@within Presets
	.scale number? -- Noise-space units per pixel. Defaults to 0.05.
	.offsetX number? -- Noise-space x offset. Defaults to 0.
	.offsetY number? -- Noise-space y offset. Defaults to 0.
	.rangeMin number? -- Sampler output mapped to black. Defaults to -1.
	.rangeMax number? -- Sampler output mapped to white. Defaults to 1.
	.curve Curve? -- Optional response curve applied after range mapping.
]=]
export type NoisePresetOptions = {
	scale: number?,
	offsetX: number?,
	offsetY: number?,
	rangeMin: number?,
	rangeMax: number?,
	curve: Curve?,
}

--[=[
	@interface PointsPresetOptions
	@within Presets
	.width number -- Width of the region the points were sampled from.
	.height number -- Height of the region the points were sampled from.
	.radius number? -- Dot radius in pixels. Defaults to 2.
]=]
export type PointsPresetOptions = {
	width: number,
	height: number,
	radius: number?,
}

--[=[
	@class Presets

	Ready-made callbacks for [Visualizer], covering the three things you most
	often want to look at while tuning generation: noise fields, response
	curves, and scattered points.

	```lua
	local viz = Atlas.Visualizer.new({ title = "Terrain" })
	viz:render(Atlas.Visualizer.Presets.noise(simplex, { scale = 0.02 }))
	```
]=]
local Presets = {}

--[=[
	Builds a grayscale [PixelCallback] for any 2D noise sampler. Sampler output
	is mapped from `[rangeMin, rangeMax]` to black–white, optionally shaped
	through a [Curve] — handy for previewing exactly the remap your terrain
	will use. Pass `rangeMin = 0` for [Voronoi] distances.

	@function noise
	@within Presets
	@param sampler NoiseSampler2D
	@param options NoisePresetOptions?
	@return PixelCallback
]=]
function Presets.noise(sampler: NoiseSampler2D, options: NoisePresetOptions?): PixelCallback
	local scale = if options then options.scale or 0.05 else 0.05
	local offsetX = if options then options.offsetX or 0 else 0
	local offsetY = if options then options.offsetY or 0 else 0
	local rangeMin = if options then options.rangeMin or -1 else -1
	local rangeMax = if options then options.rangeMax or 1 else 1
	local curve = if options then options.curve else nil
	local invRange = 1 / (rangeMax - rangeMin)
	local sample2D = sampler.sample2D

	if curve then
		return function(x: number, y: number): (number, number, number)
			local value = (sample2D(sampler, offsetX + x * scale, offsetY + y * scale) - rangeMin) * invRange
			value = curve:evaluate(value)
			return value, value, value
		end
	end

	return function(x: number, y: number): (number, number, number)
		local value = (sample2D(sampler, offsetX + x * scale, offsetY + y * scale) - rangeMin) * invRange
		return value, value, value
	end
end

--[=[
	Builds a [DrawCallback] that plots a [Curve] over a quarter grid, scaled to
	the curve's own domain and range.

	@function curve
	@within Presets
	@param curve Curve
	@return DrawCallback
]=]
function Presets.curve(curve: Curve): DrawCallback
	return function(buf: buffer, width: number, height: number)
		fill(buf, width, height, COLOR_BACKGROUND)

		for quarter = 1, 3 do
			local gridX = min(floor(width * quarter * 0.25 + 0.5), width - 1)
			for y = 0, height - 1 do
				writeu32(buf, (y * width + gridX) * 4, COLOR_GRID)
			end
			local gridY = min(floor(height * quarter * 0.25 + 0.5), height - 1)
			local rowOffset = gridY * width * 4
			for x = 0, width - 1 do
				writeu32(buf, rowOffset + x * 4, COLOR_GRID)
			end
		end

		local minX, maxX = curve:domain()
		local minY, maxY = curve:range()
		local spanY = maxY - minY
		if spanY < 1e-12 then
			minY -= 0.5
			spanY = 1
		end

		local margin = 4
		local plotHeight = height - 1 - margin * 2
		local stepX = (maxX - minX) / (width - 1)
		local previous = -1

		for px = 0, width - 1 do
			local value = curve:evaluate(minX + px * stepX)
			local py = margin + floor((1 - (value - minY) / spanY) * plotHeight + 0.5)
			if previous < 0 then
				previous = py
			end
			for y = min(previous, py), max(previous, py) do
				writeu32(buf, (y * width + px) * 4, COLOR_LINE)
			end
			previous = py
		end
	end
end

--[=[
	Builds a [DrawCallback] that plots sample points as dots, mapping the
	sampled region onto the full image.

	@function points
	@within Presets
	@param points {Vector2}
	@param options PointsPresetOptions
	@return DrawCallback
]=]
function Presets.points(points: { Vector2 }, options: PointsPresetOptions): DrawCallback
	local regionWidth = options.width
	local regionHeight = options.height
	local radius = options.radius or 2
	local radiusSq = radius * radius

	return function(buf: buffer, width: number, height: number)
		fill(buf, width, height, COLOR_BACKGROUND)

		local scaleX = (width - 1) / regionWidth
		local scaleY = (height - 1) / regionHeight

		for _, point in points do
			local centerX = floor(point.X * scaleX + 0.5)
			local centerY = floor(point.Y * scaleY + 0.5)
			for offsetY = -radius, radius do
				local y = centerY + offsetY
				if y >= 0 and y < height then
					local rowOffset = y * width * 4
					for offsetX = -radius, radius do
						local x = centerX + offsetX
						if x >= 0 and x < width and offsetX * offsetX + offsetY * offsetY <= radiusSq then
							writeu32(buf, rowOffset + x * 4, COLOR_POINT)
						end
					end
				end
			end
		end
	end
end

return Presets
