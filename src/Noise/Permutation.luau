--!strict
--!native
--!optimize 2

-- Seeded permutation tables and seed normalization
-- The Lehmer LCG (state * 48271 % 2147483647) stays well inside double precision,
-- so results are deterministic on every platform.

local floor = math.floor
local readu8 = buffer.readu8
local writeu8 = buffer.writeu8

local Permutation = {}

function Permutation.normalize(seed: number): number
	return floor(seed % 2147483646) + 1
end

function Permutation.build(seed: number): buffer
	local perm = buffer.create(512)
	for i = 0, 255 do
		writeu8(perm, i, i)
	end

	local state = Permutation.normalize(seed)
	for i = 255, 1, -1 do
		state = state * 48271 % 2147483647
		local j = state % (i + 1)
		local swap = readu8(perm, i)
		writeu8(perm, i, readu8(perm, j))
		writeu8(perm, j, swap)
	end

	-- Duplicate the shuffled 256 entries so nested lattice lookups like
	-- perm[perm[X] + Y] never need a wrap in the hot path.
	for i = 0, 255 do
		writeu8(perm, i + 256, readu8(perm, i))
	end

	return perm
end

return Permutation
