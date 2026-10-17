# Atlas optimization measurements — October 16, 2026

A subsequent [Perlin/Simplex pass](noise/README.md) adds seeded gradient
precomputation and records its sampling gains, memory cost and construction cost.
The results below describe the preceding pass.

Baseline: commit `506e2030c291184ddafeae634cab5ceae1b69729`, with a clean working tree before measurement.
Machine: Windows, AMD Ryzen 5 7600X. Local Luau CLI sandbox, `-O2`, interpreter and `--codegen` modes. Runtime SHA256: `4E86C0399ACA661753D918BB775A152E35FD8F7A788B67076E1E03F81BC43703`.

## Paired results

Median of 11 trials, alternating baseline/candidate order in one process. Units are **microseconds per operation**, including closure overhead. Noise: 200,000 calls/trial; Poisson: 100 complete scatters/trial. Both implementations use the same seed and coordinates. Positive percentages mean less elapsed time.

| Workload | Native before | Native after | Time reduction | Interpreter reduction |
|---|---:|---:|---:|---:|
| Perlin.sample2D | 0.039612 | 0.039174 | 1.10% | 4.84% |
| Perlin.sample2DWithDerivative (unchanged control) | 0.040747 | 0.041543 | -1.95% | 7.73% |
| Voronoi.sample2D | 0.142951 | 0.114673 | 19.78% | 13.93% |
| Voronoi.sample3D | 0.449210 | 0.353632 | 21.28% | 11.82% |
| Voronoi.cell2D | 0.180717 | 0.143906 | 20.37% | 14.85% |
| Voronoi.cell3D | 0.590761 | 0.461630 | 21.86% | 8.00% |
| Sampling.poissonDisc (100×100, radius 5) | 2830.254 | 2703.490 | 4.48% | 5.49% |

Treat small differences as noise. The unchanged derivative control illustrates residual timing variance even with paired ordering. No confidence intervals were calculated. The consistent Voronoi gains across both modes are the strongest result.

## Iterations

All exploratory runs use seven trials, reporting the median. The full original workload suite is retained in the adjacent raw logs. These sequential runs are noisier than the paired comparison above.

| Native microseconds/op | Baseline | Iteration 1 | Iteration 2 | Iteration 3 |
|---|---:|---:|---:|---:|
| Voronoi.sample2D | 0.137324 | 0.135901 | 0.154980 | 0.109019 |
| Voronoi.sample3D | 0.438403 | 0.425561 | 0.510560 | 0.344966 |
| Voronoi.cell2D | 0.175984 | 0.178038 | 0.183966 | 0.136898 |
| Sampling.poissonDisc | 2812.449 | 2561.700 | 2627.403 | 2579.935 |

1. Hoisted repeated Perlin 2D lattice masking and Poisson Y-neighbor bounds. Perlin scalar bytecode shrank from 161 to 153 instructions (including fallback instructions). A corresponding Perlin derivative rewrite produced a native checksum mismatch while interpreter checksums matched; that rewrite was reverted. Its iteration 1/2 derivative timings are **invalid**, not performance improvements.
2. Tested partial-distance pruning in Voronoi. It added branches and regressed native timings, so it was reverted.
3. Hoisted Voronoi shared-axis hashes and unrolled the three-cell inner loop. This removes repeated hash arithmetic and loop setup/dispatch while preserving feature visitation, floating-point operation order, F2 ties and cell IDs. Static bytecode grows (sample3D: 66 to 119 instructions); less work executes per sample. The outer loops remain compact. Tradeoff: larger source/bytecode for faster sampling.

## Validation

- 503,019 **exact** output comparisons passed separately in interpreter and native modes. Five seeds, 3,000 coordinate sets/seed, negative coordinates, integer positions, ±65536 wrap cases, all Perlin/Simplex/Voronoi scalar and derivative returns, both Voronoi cell queries including IDs, and complete uniform/Poisson/grid scatter arrays.
- All 30 existing numerical smoke checks passed in both modes after fixing an existing false seed assertion: one half-integer coordinate matched in the original implementation too. The check now compares several off-grid coordinates.
- Removed the duplicate Studio benchmark invocation.
- `selene src`: no errors or warnings. StyLua passes for changed source files and the parity harness. The repository-wide format check still reports a pre-existing difference in `src/Curve.luau`; that file was left unchanged.
- `rojo build test.project.json -o build/performance/AtlasTest.rbxl`: succeeded. The rebuilt place was not executed in Roblox Studio.

## Reproduce and interpret

```powershell
python tools/performance.py --bin PATH_TO_LUAU_BIN --label baseline
# Apply the source changes, retaining build/performance/baseline.luau.
python tools/performance.py --bin PATH_TO_LUAU_BIN --label candidate --reference baseline
```

The tool bundles modules in dependency order, replacing Roblox `require(script...)` with lexical dependencies. Roblox Vector2/Vector3 construction maps to native Luau vectors; GUI code is excluded. Sources under `src/` are not rewritten by the runner. `luau.exe` and `luau-compile.exe` must be in the supplied directory. `--checks-only` disassembles and runs smoke checks without benchmarks. Generated scripts and disassemblies live in ignored `build/performance/`.

The main suite uses 100,000 calls for noise/curves, 100 calls for scattering and 30 full 128×128 render-math operations, with 100 warm-up calls. Coordinates and seeds match the existing workload definitions; counts differ from the README's historical run. Checksums are retained. [comparison.csv](comparison.csv) contains the full sequential baseline/final comparison, while [paired-native.txt](paired-native.txt) and [paired-vm.txt](paired-vm.txt) contain the stronger paired evidence. Baseline/final disassemblies for changed modules are saved alongside these results.

Historical README native figures include Voronoi 2D 0.139 µs, 3D 0.417 µs, cell2D 0.171 µs and Poisson 1171.568 µs. These came from Roblox with different counts and environment; they are context, not a controlled comparison. In particular, the CLI Poisson absolute timing is substantially slower than that historical result. Use the fresh same-runtime paired baseline to attribute improvements. Fresh Roblox Studio timing remains outstanding.
