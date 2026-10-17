# Atlas 0.2.0 release measurements

Measured October 17, 2026 on Windows / AMD Ryzen 5 7600X using the released
source. Raw logs: [CLI native](cli-native.txt), [CLI interpreter](cli-vm.txt),
[actual Roblox Studio interpreter](studio-interpreter.txt), and
[all results with relative costs](results.csv).

The CLI uses O2, with `--codegen` for its native run. Studio measurements run
the numerical modules in the Edit-mode command execution environment, with
real Roblox Vector2/Vector3 values. They do **not** enable native codegen and
do not modify the place, scripts, instances or play state. Studio native
measurements remain outstanding. Compare each runtime with its own built-in
`math.noise`, never with another runtime's reference.

Each median covers 11 trials with 20 warm-up calls. Scalar noise/derivative,
fBm and curve rows use 100,000 calls per trial; scattering uses 50 complete
scatters; preview render math uses 20 complete 128x128 buffers. Bulk 2D uses
20 complete 128x128 grids, and bulk 3D uses 10 complete 32x32x32 volumes.
The harness yields between trials in Studio, outside the timed region.

Scalar coordinates match the original benchmark workload (multiples of
0.137, 0.291 and 0.173). Bulk axes use step 0.137, with negative Y step and
the same shifted origin for every algorithm. Every grid path allocates and
fills its complete output array. Timings include loop/callback overhead;
sampler construction is excluded. Atlas instances use seed 42. Algorithms
produce different fields, so cross-algorithm checksums intentionally differ.

`results.csv` stores medians, minimum/maximum trial times, iteration counts
and checksums. Noise ratios are elapsed cost divided by the matching
dimensional `math.noise` cost. Derivative/cell/fBm ratios are contextual cost
references: they perform more work than one scalar noise sample. Bulk ratios
use a loop of `math.noise` filling the same-sized array. Non-noise operation
ratios are left blank because their units differ. Times vary with runtime,
native settings, machine load and GC; no confidence intervals were computed.

The README replaces its old single-run numbers with these measurements.
In this CLI native run, Perlin 2D scalar cost was 0.77x `math.noise`, while
Perlin's 2D and 3D grids cost 0.31x and 0.58x their `math.noise` loops.
The actual Studio interpreter results favor the built-in function. These
numbers are not a universal Roblox performance guarantee.

CLI reproduction uses the existing saved reference bundle, needed by the
runner to bind `Candidate` for the release harness:

```powershell
New-Item -ItemType Directory -Force build/performance | Out-Null
Copy-Item benchmarks/2026-10-17/bulk-noise/baseline.luau build/performance/volume-baseline.luau
python tools/performance.py --bin PATH_TO_LUAU_BIN --label release --reference volume-baseline --paired-only --harness test/release-performance.luau
```

For Studio, bind `Candidate` to the current Atlas module and execute
`test/release-performance.luau` in that scope. The recorded run used the same
numeric modules assembled with their lexical dependencies, to avoid adding
anything to the open place. The normal test place also includes the new
bulk/reference workloads in `test/server/Benchmarks.luau`.

Release validation separately repeats 716,771 exact comparisons in each
CLI mode, including signed-zero bulk checks, plus 42 smoke checks in both
CLI modes and in Roblox Studio. See [the bulk validation methodology](../bulk-noise/README.md).
