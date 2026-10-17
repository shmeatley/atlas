# Perlin and Simplex follow-up — October 16, 2026

Seeded gradient precomputation removes the final permutation read and gradient-selection arithmetic from each lattice corner. The constructor copies the original double-precision gradients into two expanded buffers; interpolation, derivatives and seeded fields remain unchanged. Perlin 3D also consumes each corner immediately to reduce native register pressure.

These are **additional** improvements relative to the end of the [previous optimization pass](../README.md), using its saved `iteration3-verified` snapshot as the reference. Same machine and Luau binaries. Eleven paired trials with alternating order, medians below. Units: microseconds per operation. Noise uses 200,000 calls/trial; fBm uses 100,000; constructors use 500. Positive percentages mean less elapsed time.

| Workload | Native before | Native after | Native time reduction | Interpreter reduction |
|---|---:|---:|---:|---:|
| Perlin.sample2D | 0.036963 | 0.033053 | 10.58% | 13.36% |
| Perlin.sample3D | 0.057301 | 0.042670 | 25.53% | 12.57% |
| Perlin.sample2DWithDerivative | 0.040013 | 0.036675 | 8.34% | 8.30% |
| Perlin.sample3DWithDerivative | 0.062590 | 0.051269 | 18.09% | 2.09% |
| Simplex.sample2D | 0.054947 | 0.048194 | 12.29% | 13.39% |
| Simplex.sample3D | 0.073890 | 0.062417 | 15.53% | 19.37% |
| Simplex.sample2DWithDerivative | 0.053924 | 0.048469 | 10.12% | 6.50% |
| Simplex.sample3DWithDerivative | 0.078004 | 0.067522 | 13.44% | 14.05% |
| Perlin fBm2D, 4 octaves | 0.175688 | 0.168676 | 3.99% | 13.36% |
| Simplex fBm2D, 4 octaves | 0.278973 | 0.242658 | 13.02% | 12.69% |

Unchanged Voronoi/scattering controls were within approximately 1.5% in the final native run. Small differences, including the 4% Perlin fBm result, deserve more caution than the larger scalar sampling gains. No confidence intervals were calculated. These are CLI sandbox results; fresh Roblox Studio timing remains outstanding.

## Cost and evidence

- Additional buffer storage: **20,480 bytes (20 KiB) per Perlin or Simplex instance**, plus two buffer/table-field overheads. Both dimensionalities are prepared eagerly; ordinary samples remain allocation-free. The existing 512-byte permutation buffer remains.
- Native constructor medians: Perlin **3.3874 → 16.1200 µs**, Simplex **3.7078 → 21.3818 µs**. Constructor timing includes allocation/GC effects. At these sampling rates the Perlin setup overhead is amortized after roughly 870 3D samples or 3,260 2D samples. Reuse samplers rather than constructing them per point.
- Static Perlin scalar bytecode: 2D **153 → 120** instructions; 3D **332 → 289**. Counts include fallback instructions. Both derivative routines and all Simplex sampling routines also shrink.
- The first expanded-buffer layout made Perlin scalar 3D fail native lowering (`can't lower`) and regress to interpreted speed. Reordering the corner calculations fixed that. The failed experiment and final native diagnostic excerpts are retained alongside the timings.
- After reordering, **503,019 exact output comparisons passed separately in interpreter and native modes**, covering all scalar/derivative outputs, negative and boundary coordinates, multiple seeds, Voronoi IDs and complete scatter arrays. All **30 smoke checks** also passed in both modes. Selene, formatting for changed Luau files, and the rebuilt Rojo test place passed.

The extra construction work builds only the first 256 gradient entries, then duplicates each half with one buffer copy. Gradient components are copied verbatim, preserving their double representation. The cache fields are internal implementation details; the public sampler methods and seed behavior are unchanged.

Run after saving the pre-change reference:

```powershell
python tools/performance.py --bin PATH_TO_LUAU_BIN --label noise-final --reference iteration3-verified --paired-only
```

[Final native results](noise-final-native.txt), [final interpreter results](noise-final-vm.txt), [initial experiment](noise-expanded-native.txt). Before/after disassemblies are in this folder. The earlier report's results and disassemblies remain an historical record of the preceding pass.
