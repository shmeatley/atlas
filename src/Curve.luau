--!strict
--!native
--!optimize 2

local sort = table.sort
local sqrt = math.sqrt

--[=[
	@class Curve

	A response curve: control points interpolated with a monotone cubic Hermite
	spline (Fritsch–Carlson), evaluated as `y = curve:evaluate(x)`. The spline
	never overshoots its control points, which makes it safe for remapping
	noise into ranges like [0, 1] — shaping terrain falloff, biome thresholds,
	spawn weights, or any other value.

	```lua
	local falloff = Atlas.Curve.new({
		Vector2.new(0, 0),
		Vector2.new(0.4, 0.1),
		Vector2.new(0.7, 0.8),
		Vector2.new(1, 1),
	})
	local height = falloff:evaluate(noiseValue * 0.5 + 0.5)
	```
]=]
local Curve = {}
Curve.__index = Curve

type CurveProps = {
	_xs: { number },
	_ys: { number },
	_tangents: { number },
	_count: number,
	_minY: number,
	_maxY: number,
}

export type Curve = typeof(setmetatable({} :: CurveProps, Curve))

--[=[
	Creates a curve through the given control points. Points are sorted by x on
	construction; x values must be distinct.

	@function new
	@within Curve
	@param points {Vector2} -- At least two control points.
	@return Curve
]=]
function Curve.new(points: { Vector2 }): Curve
	local count = #points
	if count < 2 then
		error("Curve.new requires at least two control points", 2)
	end

	local sorted = table.clone(points)
	sort(sorted, function(a, b)
		return a.X < b.X
	end)

	local xs = table.create(count)
	local ys = table.create(count)
	for i = 1, count do
		local point = sorted[i]
		xs[i] = point.X
		ys[i] = point.Y
		if i > 1 and point.X == xs[i - 1] then
			error("Curve.new control points must have distinct x values", 2)
		end
	end

	local secants = table.create(count - 1)
	for i = 1, count - 1 do
		secants[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
	end

	local tangents = table.create(count)
	tangents[1] = secants[1]
	tangents[count] = secants[count - 1]
	for i = 2, count - 1 do
		local left = secants[i - 1]
		local right = secants[i]
		tangents[i] = if left * right <= 0 then 0 else (left + right) * 0.5
	end

	-- Fritsch–Carlson limiting: pull tangents back inside the circle of radius
	-- 3 around each secant so no segment can overshoot.
	for i = 1, count - 1 do
		local secant = secants[i]
		if secant == 0 then
			tangents[i] = 0
			tangents[i + 1] = 0
		else
			local a = tangents[i] / secant
			local b = tangents[i + 1] / secant
			local lengthSq = a * a + b * b
			if lengthSq > 9 then
				local scale = 3 / sqrt(lengthSq)
				tangents[i] = scale * a * secant
				tangents[i + 1] = scale * b * secant
			end
		end
	end

	local minY = ys[1]
	local maxY = ys[1]
	for i = 2, count do
		local y = ys[i]
		if y < minY then
			minY = y
		elseif y > maxY then
			maxY = y
		end
	end

	return setmetatable({
		_xs = xs,
		_ys = ys,
		_tangents = tangents,
		_count = count,
		_minY = minY,
		_maxY = maxY,
	}, Curve)
end

--[=[
	Evaluates the curve at `x`. Inputs outside the control point domain clamp
	to the first or last point's value.

	@method evaluate
	@within Curve
	@param x number
	@return number
]=]
function Curve.evaluate(self: Curve, x: number): number
	local xs = self._xs
	local count = self._count

	if x <= xs[1] then
		return self._ys[1]
	elseif x >= xs[count] then
		return self._ys[count]
	end

	local low = 1
	local high = count
	while high - low > 1 do
		local mid = (low + high) // 2
		if xs[mid] <= x then
			low = mid
		else
			high = mid
		end
	end

	local ys = self._ys
	local tangents = self._tangents
	local x0 = xs[low]
	local width = xs[low + 1] - x0
	local t = (x - x0) / width
	local t2 = t * t
	local t3 = t2 * t

	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = 1 - h00
	local h11 = t3 - t2

	return h00 * ys[low] + h10 * width * tangents[low] + h01 * ys[low + 1] + h11 * width * tangents[low + 1]
end

--[=[
	Evaluates the curve over a whole array in one call.

	@method map
	@within Curve
	@param values {number}
	@return {number}
]=]
function Curve.map(self: Curve, values: { number }): { number }
	local evaluate = self.evaluate
	local mapped = table.create(#values)
	for i, value in values do
		mapped[i] = evaluate(self, value)
	end
	return mapped
end

--[=[
	Returns the x extent covered by the control points.

	@method domain
	@within Curve
	@return number -- Smallest control point x.
	@return number -- Largest control point x.
]=]
function Curve.domain(self: Curve): (number, number)
	return self._xs[1], self._xs[self._count]
end

--[=[
	Returns the output extent of the curve. Because the spline is monotone
	between control points, this is exactly the min and max control point y.

	@method range
	@within Curve
	@return number -- Smallest output value.
	@return number -- Largest output value.
]=]
function Curve.range(self: Curve): (number, number)
	return self._minY, self._maxY
end

return Curve
