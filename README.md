# Atlas

[![CI](https://github.com/shmeatley/atlas/actions/workflows/ci.yml/badge.svg)](https://github.com/shmeatley/atlas/actions/workflows/ci.yml)
[![Wally](https://img.shields.io/badge/wally-shmeatley%2Fatlas-blue)](https://wally.run/package/shmeatley/atlas)
[![Docs](https://img.shields.io/badge/docs-moonwave-blue)](https://shmeatley.github.io/atlas)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Atlas is a procedural generation toolkit for Roblox, written in fully-typed
Luau.

- **Noise** â€” seeded Perlin, simplex, and Voronoi (Worley) samplers in 2D and
  3D, with derivatives (analytical for Perlin and Simplex), binary island
  masks, plus fBm helpers for layering octaves.
- **Sampling** â€” uniform random and Poisson disc (blue noise) point
  scattering, deterministic per seed.
- **Curves** â€” monotone cubic response curves built from control points, for
  remapping noise (or any value) without overshoot.
- **Visualization** â€” draggable on-screen `EditableImage` windows rendered
  through pixel buffers, with built-in presets for noise, curves, and point
  sets.

## Installation

```toml
[dependencies]
Atlas = "shmeatley/atlas@0.2.1"
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

-- Binary island mask: 1 for land, 0 for water.
local island = Atlas.Noise.Island.new({ seed = 42, breakage = 0.5, detail = 0.75 })
local function isIslandLand(x: number, z: number): boolean
	return island:sample2D(x * 0.002, z * 0.002) == 1
end

-- Slope-aware placement using analytical derivatives (no extra samples).
local _, dx, dz = simplex:sample2DWithDerivative(10, 20)
local steepness = math.sqrt(dx * dx + dz * dz)

-- Blue-noise scatter for trees, rocks, spawn pointsâ€¦
local trees = Atlas.Sampling.poissonDisc(512, 512, 8, 42)

-- See what you're generating (client-side).
local window = Atlas.Visualizer.new({ title = "Terrain preview" })
window:render(Atlas.Visualizer.Presets.noise(simplex, { scale = 0.02, curve = falloff }))
```

Full API reference: [shmeatley.github.io/atlas](https://shmeatley.github.io/atlas)

## Performance

### Studio native (0.2.1)

Measured in a separate Roblox Studio **server play session**, with `--!native`
on the benchmark Script and Perlin/Simplex ModuleScripts. Studio's profiler
recorded native execution of the sampled kernels. Medians of 31 trials,
rotating the order of released Atlas 0.2.0, the optimized code, and
`math.noise`. CPU: AMD Ryzen 5 7600X; Studio 0.743.0.7431133.

| Workload | Optimized Atlas | math.noise | Atlas / built-in time |
|---|---:|---:|---:|
| Perlin scalar 2D | 0.0306 us | 0.0407 us | 0.75x |
| Perlin scalar 3D | 0.0416 us | 0.0405 us | 1.03x |
| Simplex scalar 2D | 0.0412 us | 0.0405 us | 1.02x |
| Simplex scalar 3D | 0.0558 us | 0.0405 us | 1.38x |
| Perlin grid 128x128 | 0.230 ms | 0.617 ms | 0.37x |
| Perlin grid 32x32x32 | 0.819 ms | 1.240 ms | 0.66x |
| Simplex grid 128x128 | 0.386 ms | 0.622 ms | 0.62x |
| Simplex grid 32x32x32 | 1.375 ms | 1.237 ms | 1.11x |

Lower ratios are better. Bulk references use specialized 2D/3D loops filling
the same-sized arrays. Atlas preserves its own seeded outputs; these are
different noise fields from `math.noise`. Relative to 0.2.0 in the same run,
scalar Perlin improved 5–12%, scalar Simplex 20–22%, and Simplex grids
29–31%. Perlin grid implementations are unchanged. Interpreter controls
showed Simplex taking about 2–9% longer than 0.2.0, so these changes target
native execution rather than a universal runtime improvement.

[Full Studio native report, exact validation and raw trials](benchmarks/2026-10-17/studio-native/README.md).
Reproduce with `python tools/studio_native.py`, open the generated place,
and press Play. Add `--validate` for the exact-output suite.
These changes are included in 0.2.1; the historical tables below describe 0.2.0.

### Released 0.2.0: CLI and Studio interpreter

Measured October 17, 2026 on an AMD Ryzen 5 7600X. Tables show medians of
11 trials, including closure-call overhead. **Native CLI** uses Luau O2 with
native code generation; **Studio interpreter** is a fresh measurement inside
Roblox Studio Edit mode. The Studio native measurements above are separate
from these historical release measurements.
Compare ratios within one runtime: **lower is better; 1.00x equals that
runtime's `math.noise` cost**. These algorithms produce different fields;
derivative, cell and fBm rows also return more information or do more work.

### Scalar noise

Microseconds per call, 100,000 calls per trial. Atlas samplers use seed 42.
Each ratio uses the matching-dimensional `math.noise` reference.

| Workload | Native CLI us/call | vs math.noise | Studio interpreter us/call | vs math.noise |
|---|---:|---:|---:|---:|
| math.noise 2D | 0.043 | 1.00x | 0.040 | 1.00x |
| Perlin 2D | 0.033 | 0.77x | 0.120 | 2.99x |
| Perlin 2D + derivatives | 0.043 | 1.00x | 0.274 | 6.81x |
| Simplex 2D | 0.046 | 1.07x | 0.153 | 3.80x |
| Simplex 2D + derivatives | 0.054 | 1.26x | 0.224 | 5.57x |
| Voronoi 2D | 0.108 | 2.51x | 0.405 | 10.07x |
| Voronoi cell2D (F1, F2, ID) | 0.133 | 3.11x | 0.447 | 11.10x |
| Island 2D | 0.043 | 1.00x | 0.093 | 2.32x |
| fBm 2D (4 Simplex octaves) | 0.198 | 4.62x | 0.634 | 15.77x |
| math.noise 3D | 0.042 | 1.00x | 0.043 | 1.00x |
| Perlin 3D | 0.043 | 1.01x | 0.312 | 7.27x |
| Perlin 3D + derivatives | 0.060 | 1.43x | 0.597 | 13.93x |
| Simplex 3D | 0.060 | 1.43x | 0.280 | 6.52x |
| Simplex 3D + derivatives | 0.073 | 1.74x | 0.483 | 11.28x |
| Voronoi 3D | 0.335 | 7.94x | 1.515 | 35.34x |

### Bulk grids and volumes

Milliseconds per **whole result array**, including allocation. Every path
fills the same number of entries at the same coordinates. Ratios compare
with a loop of `math.noise` calls producing that same array; outputs differ
between noise algorithms. These gains require using the bulk APIs.

| Workload | Native CLI ms/grid | vs math.noise | Studio interpreter ms/grid | vs math.noise |
|---|---:|---:|---:|---:|
| math.noise grid2D (128x128) | 0.676 | 1.00x | 0.808 | 1.00x |
| Perlin.sampleGrid2D (128x128) | 0.209 | 0.31x | 1.218 | 1.51x |
| Simplex.sampleGrid2D (128x128) | 0.479 | 0.71x | 2.407 | 2.98x |
| math.noise grid3D (32x32x32) | 1.350 | 1.00x | 1.703 | 1.00x |
| Perlin.sampleGrid3D (32x32x32) | 0.787 | 0.58x | 8.071 | 4.74x |
| Simplex.sampleGrid3D (32x32x32) | 1.599 | 1.18x | 8.803 | 5.17x |

Native CLI Perlin's 128x128 bulk path took about **31% of the `math.noise`
loop's time** in this run. This is not a Studio native result; the actual
Studio interpreter results above are slower than its built-in `math.noise`.

### Other operations

Microseconds per complete operation; these units differ from one noise sample.

| Operation | Native CLI us/op | Studio interpreter us/op |
|---|---:|---:|
| Curve.evaluate (8 points) | 0.074 | 0.124 |
| Sampling.uniform (256 points) | 4.340 | 13.286 |
| Sampling.poissonDisc (100x100, r=5) | 2559.592 | 2505.496 |
| Sampling.blueNoiseGrid (100x100, cellSize=3) | 28.074 | 183.560 |
| Visualizer render math (128x128) | 1057.525 | 3592.990 |

### Usage and reproducibility

```lua
local perlin = Atlas.Noise.Perlin.new(42)
local simplex = Atlas.Noise.Simplex.new(42)
local heights = perlin:sampleGrid2D(128, 128, 0, 0, 0.02, 0.02)
local surface = simplex:sampleGrid2D(128, 128, 0, 0, 0.02, 0.02)
local volume = perlin:sampleGrid3D(32, 32, 32, 0, 0, 0, 0.02, 0.02, 0.02)
-- simplex:sampleGrid3D takes the same arguments.
-- 2D index: row * width + column + 1 (zero-based row/column).
-- 3D index: (slice * height + row) * width + column + 1.
```

- Scalar samples are allocation-free. Bulk calls allocate their result arrays;
  Perlin uses an additional temporary buffer of 24 bytes per column.
- Perlin and Simplex prepare 20 KiB of gradient buffers per instance. Construct
  samplers once and reuse them; keep repeated method calls localized in hot loops.
- Bulk outputs match the corresponding Atlas scalar methods exactly, including
  negative/zero steps. This does not mean Atlas matches Roblox's noise field.
- Benchmarks vary by runtime, native settings, workload and hardware. Raw logs
  retain trial ranges and checksums; small differences should not be generalized.

[Complete release measurements and methodology](benchmarks/2026-10-17/release-v0.2.0/README.md),
[optimization history](benchmarks/2026-10-16/README.md),
[Perlin 2D trials](benchmarks/2026-10-16/research/README.md), and
[Simplex/3D trials](benchmarks/2026-10-17/bulk-noise/README.md).

Build the test place with `rojo build test.project.json -o AtlasTest.rbxl` and
press Play in Studio to run smoke checks and the original benchmark suite.
The release benchmark harness is `test/release-performance.luau`.

## License

Atlas is licensed under the [MIT License](LICENSE).
