# Atlas

[![CI](https://github.com/shmeatley/atlas/actions/workflows/ci.yml/badge.svg)](https://github.com/shmeatley/atlas/actions/workflows/ci.yml)
[![Wally](https://img.shields.io/badge/wally-shmeatley%2Fatlas-blue)](https://wally.run/package/shmeatley/atlas)
[![Docs](https://img.shields.io/badge/docs-moonwave-blue)](https://shmeatley.github.io/atlas)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Atlas is a procedural generation toolkit for Roblox, written in fully-typed
Luau. The math-dense modules compile with `--!native --!optimize 2`.

- **Noise** — seeded Perlin, simplex, and Voronoi (Worley) samplers in 2D and
  3D, with analytical derivatives for slope-aware generation, plus fBm helpers
  for layering octaves.
- **Sampling** — uniform random and Poisson disc (blue noise) point
  scattering, deterministic per seed.
- **Curves** — monotone cubic response curves built from control points, for
  remapping noise (or any value) without overshoot.
- **Visualization** — draggable on-screen `EditableImage` windows rendered
  through pixel buffers, with built-in presets for noise, curves, and point
  sets.

> **Status: pre-release.** Not yet published to Wally; the API may still
> change before the first release.

## Installation

Atlas will be published to the public Wally registry as `shmeatley/atlas`.
Once available, add it to your project's `wally.toml`:

```toml
[dependencies]
Atlas = "shmeatley/atlas@0.1.0"
```

Then run:

```sh
wally install
```

## Quick start

```lua
local Atlas = require(path.to.Atlas)

-- Seeded noise: same seed, same world.
local simplex = Atlas.Noise.Simplex.new(42)

-- Shape the raw noise with a response curve.
local falloff = Atlas.Curve.new({
	Vector2.new(0, 0),
	Vector2.new(0.4, 0.1),
	Vector2.new(0.7, 0.8),
	Vector2.new(1, 1),
})

local function terrainHeight(x: number, z: number): number
	local noise = Atlas.Noise.fbm2D(simplex, x * 0.01, z * 0.01, 4)
	return falloff:evaluate(noise * 0.5 + 0.5) * 100
end

-- Slope-aware placement using analytical derivatives (no extra samples).
local _, dx, dz = simplex:sample2DWithDerivative(10, 20)
local steepness = math.sqrt(dx * dx + dz * dz)

-- Blue-noise scatter for trees, rocks, spawn points…
local trees = Atlas.Sampling.poissonDisc(512, 512, 8, 42)

-- See what you're generating (client-side).
local window = Atlas.Visualizer.new({ title = "Terrain preview" })
window:render(Atlas.Visualizer.Presets.noise(simplex, { scale = 0.02, curve = falloff }))
```

Full API reference: [shmeatley.github.io/atlas](https://shmeatley.github.io/atlas)

## Performance notes

- Every sampler builds its seeded state once at construction; sampling methods
  are allocation-free.
- In your own hot loops, localize the method once:
  `local sample2D = noise.sample2D` then call `sample2D(noise, x, y)`.

The test place ships with benchmarks: build it with
`rojo build test.project.json -o AtlasTest.rbxl`, open in Studio, and press
Play — smoke tests plus per-call timings print to the output, and demo

Here is my benchmarks output from my machine:

```
ROBLOX-PERLIN-2d                               4.036 ms      0.040 us/op  [n=100000, checksum=2.5069]
ROBLOX-PERLIN-2d-cached                        4.074 ms      0.041 us/op  [n=100000, checksum=2.5069]
Perlin.sample2D                                3.831 ms      0.038 us/op  [n=100000, checksum=-37.5011]
Perlin.sample2DWithDerivative                  4.751 ms      0.048 us/op  [n=100000, checksum=-85.4268]
ROBLOX-PERLIN-3d                               4.032 ms      0.040 us/op  [n=100000, checksum=247.1669]
ROBLOX-PERLIN-3d-cached                        3.990 ms      0.040 us/op  [n=100000, checksum=247.1669]
Perlin.sample3D                                5.575 ms      0.056 us/op  [n=100000, checksum=-111.1922]
Perlin.sample3DWithDerivative                  8.299 ms      0.083 us/op  [n=100000, checksum=-201.7996]
Simplex.sample2D                               0.052 ms      0.052 us/op  [n=1000, checksum=-1.8560]
Simplex.sample3D                               0.079 ms      0.079 us/op  [n=1000, checksum=4.9210]
Simplex.sample2DWithDerivative                 0.062 ms      0.062 us/op  [n=1000, checksum=-3.0656]
Simplex.sample3DWithDerivative                 0.088 ms      0.088 us/op  [n=1000, checksum=-7.1269]
Voronoi.sample2D                               0.139 ms      0.139 us/op  [n=1000, checksum=401.1743]
Voronoi.sample3D                               0.417 ms      0.417 us/op  [n=1000, checksum=500.4743]
Voronoi.cell2D                                 0.171 ms      0.171 us/op  [n=1000, checksum=1105.7253]
Noise.fbm2D (4 octaves, simplex)               0.207 ms      0.207 us/op  [n=1000, checksum=13.5161]
Curve.evaluate (8 points)                      0.076 ms      0.076 us/op  [n=1000, checksum=428.3051]
Sampling.uniform (256 points)                  4.806 ms      4.806 us/op  [n=1000, checksum=256000.0000]
Sampling.poissonDisc (100x100, r=5)         1171.568 ms   1171.568 us/op  [n=1000, checksum=262935.0000]
Sampling.blueNoiseGrid (100x100, cellSize=3)  25.427 ms     25.427 us/op  [n=1000, checksum=1089000.0000]
Visualizer render math (128x128)             112.179 ms   1121.792 us/op  [n=100]
```

## License

Atlas is licensed under the [MIT License](LICENSE).
