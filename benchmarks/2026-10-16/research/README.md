# Research-driven trials — October 16, 2026

Reference: the complete numerical implementation **at the start of this request**, including the previous Perlin/Simplex gradient optimization. This is not the original Git HEAD baseline. The preserved [baseline.luau](baseline.luau) bundle makes this otherwise uncommitted reference reproducible. Same Windows machine, Ryzen 5 7600X, Luau binaries and O2 interpreter/native settings as the [preceding pass](../noise/README.md).

## Kept: exact bulk Perlin 2D sampling

`perlin:sampleGrid2D(width, height, startX, startY, stepX, stepY)` returns a new row-major number array. Width/height are non-negative integers. Each entry is exactly the existing scalar method evaluated at `(startX + column * stepX, startY + row * stepY)`; coordinates are never advanced by repeated addition. Negative and zero steps are supported.

The implementation caches column fractions/permutations/fades and row Y calculations. For widths of at least 32 with `abs(stepX) < 0.25`, it also reuses corner gradients within each lattice cell, retaining the original multiply/add order. Small or coarsely spaced grids use the simpler column-cache path. The extra scratch buffer is **24 bytes per column per call**, plus the result array that both benchmark paths allocate. Existing scalar methods, seeded fields, fBm and derivatives are unchanged.

Selected final paired results below measure **whole-grid microseconds**, including result allocation and scratch setup. Both paths allocate and fill every array entry. The reference uses a cached scalar method inside ordinary row/column loops; the candidate uses the new bulk method.

| Grid / spacing | Native scalar loop | Native bulk | Time reduction |
|---|---:|---:|---:|
| 16×16 / 0.137 | 6.320 | 2.417 | 61.76% |
| 64×64 / 0.137 | 117.047 | 53.243 | 54.51% |
| 128×128 / 0.137 | 436.697 | 209.490 | 52.03% |
| 128×128 / 1.3 | 448.477 | 217.607 | 51.48% |
| 256×256 / 0.137 | 2041.580 | 906.440 | 55.60% |
| 256×256 / 1.3 | 1911.860 | 872.920 | 54.34% |

Across the final 20 square-grid workloads (sizes 16, 64, 128, 256; steps 0.01, 0.137, 0.5, 0.99, 1.3), native elapsed-time reduction was **49–62%**, interpreter **35–54%**. These gains require using the new bulk API; isolated scalar calls are unchanged. Thin grids are supported, but the performance claims above concern the measured square workloads.

A separate confirmation process repeated 128/256 grids at steps 0.137 and 1.3: native time reduction was **53–59%**, interpreter **37–52%**. Native scalar controls were within 1.3%. For example, the 128×128 fine grid measured **467.600 → 214.193 µs**, and 256×256 measured **1736.820 → 704.880 µs**. See [confirmation native](research-confirmation-native.txt) and [confirmation interpreter](research-confirmation-vm.txt).

## Experiments and rejected changes

1. **Packed intermediate hashes:** a 256×256 packed table passed exact parity but cost another 256 KiB per Perlin instance. Native scalar 3D improved only 2.92%; 3D derivatives regressed 1.63%. Rejected.
2. **Reusable fBm, precomputed arrays:** common low octave counts improved, but 6/8-octave native Perlin regressed about 10/15%. Rejected.
3. **Reusable fBm, arithmetic fallback:** removed those array reads. Larger octave results remained weak or inconsistent; Simplex 8 octaves regressed 4.43% in this trial. Rejected.
4. **Fully unrolled common-count fBm closures:** Perlin sometimes improved considerably, but Simplex 6/8 octaves still regressed 3.69/4.36%. Rejected as a general API change.
5. **Column-cache grid:** consistently substantial wins versus scalar sampling; retained as the basic bulk path.
6. **Cell-gradient cache grid:** direct paired comparison against the column-cache version showed another roughly 5–16% native improvement on most measured fine grids, but 40–63% regression on coarse spacing. Retained only behind conservative width/spacing selection; small grids keep the basic path.
7. **Unroll the existing four-octave fbm2D function:** only 0.97% Perlin / 0.74% Simplex native gain in the relevant four-octave rows, within observed noise. Reverted.

No new hash/gradient scheme, reduced-precision vector math, approximate falloff or changed noise algorithm was retained. No compiled-fBm API was added. The fBm rows in the final results are unchanged controls.

## Method and checks

- Eleven paired trials, alternating order; medians reported. Grids use 30 calls/trial, except 256×256 uses 10. Both paths warm up 100 calls. Scalar/fBm controls use 100,000 calls/trial. Grid origins vary per call to avoid benchmarking one coordinate repeatedly.
- **935,385 exact comparisons passed in each runtime mode**: 503,019 prior numerical comparisons, 90,000 fBm comparisons across octave/settings combinations, and 342,366 grid values. Grid checks cover three seeds, negatives, integer/wrap boundaries, sizes around the dispatch boundary, zero/negative steps and rectangular shapes.
- The Studio smoke harness includes the new grid checks. All **33 smoke checks** pass in CLI interpreter and native modes. Selene, formatting of changed Luau files, Rojo build and Wally package listing pass. The pre-existing unrelated Curve formatting difference remains outside scope.
- Timings have system and native-layout noise: unchanged controls sometimes show several percent differences, including larger outliers. No confidence intervals were computed. The large grid wins recur across iterations; small differences were not used to justify retained changes. Fresh Roblox Studio timings remain outstanding.

## Reproduce

```powershell
New-Item -ItemType Directory -Force build/performance | Out-Null
Copy-Item benchmarks/2026-10-16/research/baseline.luau build/performance/research-baseline.luau
python tools/performance.py --bin PATH_TO_LUAU_BIN --label candidate --reference research-baseline --paired-only --harness test/research-performance.luau
```

[Full comparison CSV](comparison.csv), [final native log](research-final-native.txt), [final interpreter log](research-final-vm.txt). The folder also retains intermediate logs, before/after Perlin bytecode and the focused comparison harnesses. Generated candidate bundles live under ignored `build/performance/`.

The confirmation run can be reproduced with `--harness benchmarks/2026-10-16/research/confirmation-harness.luau`. The isolated cell-cache versus column-cache harness is also retained; that comparison requires its original `research-grid1` reference bundle under `build/performance/`.

The trials were informed by [NVIDIA's hash/gradient table optimization](https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-26-implementing-improved-perlin-noise), [KdotJPG's whole-area generation](https://github.com/KdotJPG/Noise-VertexQueue-AreaGen), and [FastNoise2's fused pipelines](https://github.com/Auburn/FastNoise2). Their results are not treated as expected Luau speedups. This bulk implementation reuses Atlas's exact scalar arithmetic rather than adopting the area generator's approximate precomputed falloffs.
