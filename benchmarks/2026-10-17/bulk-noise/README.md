# Simplex and 3D Perlin bulk sampling — October 17, 2026

The reference is Atlas **at the start of this request**, including the previous gradient optimizations and Perlin 2D bulk sampler. The [baseline bundle](baseline.luau) preserves that uncommitted state; this is not a comparison against the original Git HEAD. Same Windows Ryzen 5 7600X and Luau CLI binaries as the preceding reports, at O2 in interpreter and native-codegen modes.

## Retained APIs

- `simplex:sampleGrid2D(width, height, startX, startY, stepX, stepY)`
- `simplex:sampleGrid3D(width, height, depth, startX, startY, startZ, stepX, stepY, stepZ)`
- `perlin:sampleGrid3D(width, height, depth, startX, startY, startZ, stepX, stepY, stepZ)`

Each returns a new flat number array. X varies fastest, followed by Y and then Z: zero-based `(column, row, slice)` maps to `(slice * height + row) * width + column + 1`. Coordinates use `start + index * step`, matching scalar calls exactly. Dimensions must be non-negative integers; any zero dimension returns an empty array. Negative and zero steps are supported.

Perlin 3D precomputes X fractions, fades and permutation entries into a **24-byte-per-column temporary buffer**, and computes Y/Z fractions and fades at their row/slice boundaries. Simplex uses inline scalar kernels with sampler buffers localized outside the loops; its coupled skew arithmetic, corner ranking and contribution order are preserved. No new persistent sampler storage is introduced. Existing scalar, derivative, fBm and Perlin 2D grid implementations are unchanged.

## Fresh paired comparison

Representative final native results measure **microseconds for an entire grid/volume**, including allocation and cache setup. The reference allocates and fills the same output array using a cached scalar method inside ordinary loops.

| Workload | Scalar loop µs | Bulk µs | Time reduction |
|---|---:|---:|---:|
| Perlin 16³, step 0.137 | 160.210 | 104.520 | 34.76% |
| Perlin 32³, step 0.137 | 1217.970 | 798.670 | 34.43% |
| Perlin 32³, step 1.3 | 1231.950 | 806.350 | 34.55% |
| Simplex 32³, step 0.137 | 1866.100 | 1552.660 | 16.80% |
| Simplex 32³, step 1.3 | 1776.560 | 1417.410 | 20.22% |
| Simplex 128², step 0.137 | 609.280 | 422.930 | 30.59% |
| Simplex 128², step 1.3 | 586.870 | 407.455 | 30.57% |

Across all measured native workloads: Perlin volumes **13–39%**, Simplex volumes **15–24%**, Simplex 2D grids **30–34%** less time. Perlin's thin 256×1×1 grids have the smaller gains; ordinary volumes were approximately 29–39%. Interpreter results are more modest: Perlin ordinary volumes roughly 15–22%, Simplex 2D usually a few percent; Simplex 3D differences are mostly small and noisy, including some slightly slower rows. These are throughput APIs, not faster isolated scalar calls. Fresh Roblox Studio timing remains outstanding.

A separate confirmation process reproduced **34–36%** native reduction for Perlin 32³, **16–19%** for Simplex 32³, and **28–29%** for Simplex 128² at steps 0.137 and 1.3. Native scalar controls varied by about 1% for Perlin and 5% for Simplex in that process, illustrating the residual timing noise. [Confirmation native log](volume-confirmation-native.txt), [confirmation interpreter log](volume-confirmation-vm.txt).

## Iterations and decisions

1. **Inline bulk kernels:** all three APIs passed exact parity. Native gains were already substantial. Retained for Simplex.
2. **Axis/permutation caching:** Perlin axis caching improved the ordinary-volume results in both modes and was retained. Simplex permutation caches were mixed. Direct comparison with the inline versions found Simplex 2D caching 5–18% slower natively; Simplex 3D caching had small fine-grid benefits but roughly 8–12% regressions on coarse grids. Both Simplex caches were dropped.
3. **Perlin XY hash plane:** precomputes four hash bytes per XY location and reuses them over depth. Ordinary-volume native throughput improved, but setup used another `4 * width * height` bytes and harmed thin grids: interpreter time regressed about 5–16% versus scalar loops, and the direct native comparison regressed about 25% versus the inline bulk kernel on thin grids. Dropped in favor of the simpler axis cache, which has consistent gains versus scalar loops.
4. **Final selection and confirmation:** restored the selected kernels, added public API documentation and Studio smoke coverage, then reran against the original request baseline.

## Exactness and verification

**716,771 comparisons passed per runtime mode:** 503,019 existing numerical comparisons plus 213,752 grid/volume values. New bulk checks additionally distinguish positive and negative zero by comparing reciprocals. Coverage includes four seeds, all three APIs, existing Perlin 2D grid compatibility, empty dimensions, thin and rectangular volumes, integer/wrap boundaries, negative coordinates, zero/negative/coarse steps, and invalid dimensions. Analytical derivative checks remain in the original smoke suite.

All **42 smoke checks** pass in both CLI modes. Selene and formatting of changed Luau files pass; Rojo builds the test place and Wally lists the intended package contents. Native compiler diagnostics confirm all three bulk kernels lower successfully. The unrelated pre-existing Curve formatting mismatch remains outside scope.

## Method and reproduction

Eleven paired trials alternate baseline/candidate order; medians are reported. Grids warm up 100 calls per path. Volume trials use 20 calls, except 32³ uses 10; 2D grids use 20 calls. Scalar controls use 100,000 calls. Origins shift per call. Both paths produce every value; full-array correctness tests are separate from the timing checksum. No approximation, floating-point reassociation, new hash function or reduced-precision gradient was used.

Unchanged controls and repeated runs show timing noise, especially in interpreter mode; no confidence intervals were computed. Small differences did not justify retained caching changes. The raw logs retain outliers rather than hiding them.

```powershell
New-Item -ItemType Directory -Force build/performance | Out-Null
Copy-Item benchmarks/2026-10-17/bulk-noise/baseline.luau build/performance/volume-baseline.luau
python tools/performance.py --bin PATH_TO_LUAU_BIN --label candidate --reference volume-baseline --paired-only --harness test/volume-performance.luau
```

[Full CSV](comparison.csv), [final native log](volume-final-native.txt), [final interpreter log](volume-final-vm.txt). Intermediate logs, before/after disassemblies and focused comparison harnesses are in this folder. Generated candidate bundles remain under ignored `build/performance/`. The direct cache-versus-inline run uses the original `volume-inline` candidate bundle as its reference.

To repeat the focused confirmation, substitute `--harness benchmarks/2026-10-17/bulk-noise/confirmation-harness.luau` in the command above. It repeats the full correctness checks while timing a smaller representative workload set.
