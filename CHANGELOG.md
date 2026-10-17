# Changelog

## 0.2.0 — 2026-10-17

### Added

- Exact bulk sampling: `Perlin:sampleGrid2D`, `Perlin:sampleGrid3D`,
  `Simplex:sampleGrid2D` and `Simplex:sampleGrid3D`.
- Row-major 2D arrays and flat 3D volumes with X varying fastest, followed by
  Y and Z. Negative and zero steps are supported; dimensions are validated.
- Reproducible benchmark/parity harnesses, retained experiment logs, bytecode
  comparisons and fresh `math.noise` comparisons for CLI native and Roblox
  Studio interpreter execution.

### Improved

- Seeded gradient precomputation for Perlin/Simplex, eliminating final
  permutation lookups and gradient selection from sampling corners. This
  adds 20 KiB per sampler and construction work; reuse instances.
- Voronoi neighbor hash reuse and inner-loop unrolling.
- Poisson-disc neighbor-bound reuse.
- Bulk Perlin coordinate/fade reuse across rows and slices; bounded scratch
  storage of 24 bytes per column per call.
- README installation version, full performance tables and bulk API examples.
  API comments now distinguish analytical and finite-difference derivatives
  and correctly describe scattered points as Vector3 values.

### Fixed

- Duplicate benchmark invocation in the Studio smoke runner.
- A single-coordinate seed assertion that also failed on the original code;
  it now checks multiple off-grid coordinates.
- Existing Curve formatting so the repository-wide formatting check passes.
- Package contents now include README and the MIT license.

### Compatibility and validation

Existing scalar/derivative/fBm interfaces and seeded outputs are preserved.
Bulk outputs equal the corresponding Atlas scalar calls; they do not equal
Roblox's different noise field. Rejected hash, fBm and cache experiments are
not included in the library.

Release checks passed 716,771 exact numerical comparisons in each CLI mode,
42 smoke checks in both CLI modes, and 42 smoke checks in Roblox Studio.
Studio native-codegen performance remains unmeasured; the README labels each
runtime separately and includes results that are slower than `math.noise`.
