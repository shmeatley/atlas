# Actual Roblox Studio native experiments — October 17, 2026

Atlas 0.2.1 beats `math.noise` for scalar Perlin 2D, both
Perlin grids and Simplex 2D grids in this run. It does **not** beat the built-in
for scalar 3D noise or Simplex 3D grids. Simplex scalar 2D is close, but still
slower. The baseline is `v0.2.0`, commit
`9b9c02c13ed953ba8000b3285d7abc1b82da2090`.

## Measurement

AMD Ryzen 5 7600X, Windows, Roblox Studio `0.743.0.7431133`. A separate local
benchmark place ran server Scripts and actual ModuleScripts with `--!native`.
No production game was changed. The earlier Edit-mode MCP execution measured
the interpreter; it was not used to time these native kernels.

31 trials rotate all six execution orders among release, candidate and
built-in. Each method gets 30 warm-up calls. Scalar trials make 500,000 calls;
2D grids make 50 calls producing 128x128 arrays; 3D grids make 30 calls producing
32x32x32 arrays. Timing includes closure calls and grid allocation. Yielding
occurs between trials, outside timing. Built-in loops are specialized for
their dimension, with identical coordinate expressions and allocation shapes.
Construction is outside timing; samplers use seed 42.

[Confirmation raw trials](confirmation-trials.txt),
[medians/min/max](confirmation-summary.txt), [CSV](results.csv).
The first longer run is also archived; the confirmation ran after CLI checks
finished, without concurrent validation or profiler collection. Results vary
with machine load and compiler version. Small margins are not reliable wins.

| Workload | 0.2.0 us | Optimized us | math.noise us | Cost ratio |
|---|---:|---:|---:|---:|
| Perlin scalar2D | 0.03463 | 0.03057 | 0.04067 | 0.75x |
| Perlin scalar3D | 0.04378 | 0.04159 | 0.04049 | 1.03x |
| Perlin grid2D 128x128 | 228.776 | 229.758 | 616.712 | 0.37x |
| Perlin grid3D 32x32x32 | 816.553 | 818.713 | 1240.230 | 0.66x |
| Simplex scalar2D | 0.05128 | 0.04123 | 0.04055 | 1.02x |
| Simplex scalar3D | 0.07163 | 0.05579 | 0.04045 | 1.38x |
| Simplex grid2D 128x128 | 561.152 | 385.824 | 622.148 | 0.62x |
| Simplex grid3D 32x32x32 | 1935.950 | 1375.273 | 1236.753 | 1.11x |

Cost ratio is candidate / matching built-in; lower is better. Fields differ
between algorithms. Exactness means preserving Atlas 0.2.0 outputs, not
matching Roblox's noise field. Perlin grids are unchanged controls; their
small before/after timing differences are measurement variation.

## Native execution evidence

`ScriptProfilerService` sampled a separate validation session at 10,000 Hz.
[Recorded functions](native-profiler-functions.json) include candidate scalar,
derivative and bulk functions with the native flag (`Flags: 1`). Native
compilation was observed, rather than inferred just from elapsed time.
The initial profiler also captured native Perlin grid2D; that implementation
is unchanged. `debug.dumpcodesize()` was attempted, but Studio restricts it
to the actual Command Bar and rejected the MCP call.

Roblox documents native execution, compiler fallback, profiler verification
and code-size reporting in its [native code generation guide](https://create.roblox.com/docs/luau/native-code-gen).

## Iterations and decisions

All experiment sources are recoverable as diffs from 0.2.0 in
[experiments.patch](experiments.patch). Round harnesses and raw logs are retained.
Early experiments used 15 alternating baseline/candidate trials, 200,000 scalar
calls and 20 grids per trial. They are screening results, not the final table.

1. [Round 1](round1.txt): padded 3D gradient strides gave small, inconsistent
   changes; immediate interpolation was neutral. Deferring Simplex hashes
   until a kernel was active regressed 6–16%. Rejected.
2. [Round 2](round2.txt): paired `readu16` permutation reads improved scalar
   Perlin; arithmetic sharing of Simplex hashes was neutral. Replacing nested
   simplex ranking branches improved 3D sampling. Retained the useful ideas.
3. [Round 3](round3.txt): converting three comparisons to numeric indicators
   reduced simplex rank control flow further. Clamping inactive value kernels
   removed unpredictable contribution branches. Retained, with a final NaN
   guard to preserve the old zero result for non-finite coordinates.
4. [Round 4](round4-guarded.txt): confirmed the guarded kernels. A separate
   combined-buffer fixture had no compelling scalar gain and failed a grid
   parity assertion because its generator missed multiline gradient reads;
   it was rejected and never copied to source. Perlin grid/derivative hash
   changes did not show a repeatable gain, so the final change only affects
   its two scalar value methods.
5. [Round 5](round5-prehash-with-validation.txt): a 257x257 hash cache added
   66,049 bytes per sampler without a convincing benefit. This screening run
   overlapped validation, so its timings are not used for conclusions. Rejected.
6. [Round 6](round6-minrank.txt): min/max rank arithmetic was approximately
   neutral for the grid and inconclusive for scalar sampling. Rejected.

The retained changes add no sampler storage, do not change permutation
generation, and keep gradient coefficients and contributing arithmetic in
their original double-precision order. The [CLI bytecode diff](cli-bytecode.diff)
is a compiler diagnostic, not a claim to be Studio's generated machine code.

## Exactness and interpreter tradeoff

[Studio native validation](studio-native-parity.txt): 503,019 existing numerical
comparisons plus 213,752 bulk comparisons, including signed zero. An additional
3,872 scalar/derivative calls cover extreme coordinates, infinities, NaNs and
matching error success/failure. Five seeds and boundary, negative, zero-step,
large-coordinate and differently shaped grids are covered. The final source
also passed 716,771 comparisons and 42 smoke checks in each CLI mode.
These checks are broad sampled evidence, not an exhaustive proof over doubles.

[Actual Studio interpreter control](studio-interpreter-control.txt) strips
native directives from both copies and runner: seven trials, 100,000 scalar
calls, ten grids per trial. Simplex medians regressed approximately 2–9%;
Perlin scalar2D regressed about 4%. These changes prioritize native server
execution. The historical release interpreter table should not be read as
the interpreter performance of this working tree.

## Reproduction

```powershell
python tools/studio_native.py
python tools/studio_native.py --validate
python tools/studio_native.py --interpreter
```

Each command builds its own ignored place under `build/studio-native/`.
Open that place in Studio and press Play. Performance Scripts print summary
rows and save every trial in `Workspace.AtlasNativeResults.Value`. Validation
prints its counts and sets `Workspace.AtlasValidationDone`. Retrieve native
profiler data in a separate session to avoid perturbing timings. The builder
requires the `v0.2.0` Git tag and Rojo. See [source hashes](source-sha256.txt).
