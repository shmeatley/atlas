"""Run Atlas in the Luau CLI sandbox; retain timings and disassembly.

Usage: python tools/performance.py --bin PATH_TO_LUAU_BIN --label baseline
Requires luau and luau-compile in that directory. Generated files go to build/.
Roblox vectors are mapped to Luau native vectors; GUI code is not executed.
"""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bin", type=pathlib.Path, required=True)
parser.add_argument("--label", required=True)
parser.add_argument("--reference", help="Previously saved label to check exact parity and paired timings against")
parser.add_argument("--checks-only", action="store_true", help="Disassemble and run smoke checks without timing")
parser.add_argument("--paired-only", action="store_true", help="Run smoke/parity/paired checks without the full timing suite")
parser.add_argument("--harness", default="test/performance-parity.luau", help="Parity/paired harness relative to the repository")
args = parser.parse_args()
out = ROOT / "build" / "performance"
out.mkdir(parents=True, exist_ok=True)
modules = ["Noise/Permutation", "Noise/Perlin", "Noise/Simplex", "Noise/Voronoi",
           "Noise/Island", "Noise/init", "Curve", "Sampling/init", "Visualizer/Presets"]
names = {m: m.split("/")[-1] if not m.endswith("/init") else m.split("/")[0] for m in modules}
parts = ['--!optimize 2\nlocal Vector2 = {new = function(x,y) return vector.create(x,y,0) end}\nlocal Vector3 = Vector2\n']
for module in modules:
    source = (ROOT / "src" / (module + ".luau")).read_text(encoding="utf-8")
    # Dependencies have already been evaluated in topological order.
    source = re.sub(r"local (\w+) = require\([^\n]+\)", r"local \1 = \1", source)
    parts.append(f'local {names[module]} = (function()\n{source}\nend)()\n')
    dis = subprocess.run([str(args.bin / "luau-compile.exe"), "-O2", "--text",
                          str(ROOT / "src" / (module + ".luau"))], capture_output=True, text=True, check=True)
    (out / f'{args.label}-{module.replace("/", "-")}.bytecode.txt').write_text(dis.stdout, encoding="utf-8")
parts.append('local Atlas = {Noise=Noise, Curve=Curve, Sampling=Sampling, Visualizer={Presets=Presets}}\n')
smoke = (ROOT / 'test/server/init.server.luau').read_text(encoding="utf-8")
smoke = smoke[smoke.index('local passed = 0'):smoke.index('print(`Atlas smoke tests:')]
smoke = '\n'.join(parts) + '\nlocal warn = print\n' + smoke + '\nassert(failed == 0, "smoke test failure")\nprint("SMOKE: " .. passed .. " passed")\n'
smoke_path = out / f'{args.label}-smoke.luau'
smoke_path.write_text(smoke, encoding="utf-8")
for mode, flags in [("vm", []), ("native", ["--codegen"])]:
    result = subprocess.run([str(args.bin / "luau.exe"), "-O2", *flags, str(smoke_path)], capture_output=True, text=True)
    (out / f'{args.label}-smoke-{mode}.txt').write_text(result.stdout + result.stderr, encoding="utf-8")
    print(mode, result.stdout, result.stderr, flush=True)
    result.check_returncode()
if args.checks_only:
    sys.exit(0)
(out / f'{args.label}.luau').write_text('\n'.join(parts), encoding="utf-8")
if args.reference:
    reference = (out / f'{args.reference}.luau').read_text(encoding="utf-8").split('local clock = os.clock')[0]
    candidate = '\n'.join(parts)
    parity = out / f'{args.label}-parity.luau'
    parity.write_text('local Baseline = (function()\n' + reference + '\nreturn Atlas\nend)()\n'
                      + 'local Candidate = (function()\n' + candidate + '\nreturn Atlas\nend)()\n'
                      + (ROOT / args.harness).read_text(encoding="utf-8"), encoding="utf-8")
    for mode, flags in [("vm", []), ("native", ["--codegen"])]:
        result = subprocess.run([str(args.bin / "luau.exe"), "-O2", *flags, str(parity)], capture_output=True, text=True)
        (out / f'{args.label}-parity-{mode}.txt').write_text(result.stdout + result.stderr, encoding="utf-8")
        print(mode, result.stdout, result.stderr, flush=True)
        result.check_returncode()
if args.paired_only:
    sys.exit(0)
bench = (ROOT / "test/server/Benchmarks.luau").read_text(encoding="utf-8")
bench = re.sub(r'local ReplicatedStorage = .*\nlocal Atlas = .*\n', '', bench)
start = bench.index('local function bench(')
end = bench.index('\nfunction Benchmarks.run()', start)
bench = bench[:start] + '''local function bench(name, iterations, fn)
    if iterations == 1000 then iterations = if string.find(name, "Sampling") then 100 else 100000 end
    if iterations == 100 then iterations = if string.find(name, "Visualizer") then 30 else iterations end
    for i=1,100 do fn(i) end
    local times = {}
    local checksum = 0
    for trial=1,7 do
        local sum = 0
        local start = clock()
        for i=1,iterations do sum += fn(i) end
        times[trial] = (clock()-start)/iterations*1e6
        checksum = sum
    end
    table.sort(times)
    print(string.format("RESULT|%s|%d|%.6f|%.6f|%.6f|%.12g", name, iterations, times[4], times[1], times[7], checksum))
end
''' + bench[end:]
bench = bench.replace('return Benchmarks', 'Benchmarks.run()')
parts.append(bench)
bundle = out / f'{args.label}.luau'
bundle.write_text('\n'.join(parts), encoding="utf-8")
for mode, flags in [("vm", []), ("native", ["--codegen"])]:
    result = subprocess.run([str(args.bin / "luau.exe"), "-O2", *flags, str(bundle)], capture_output=True, text=True, check=True)
    (out / f'{args.label}-{mode}.txt').write_text(result.stdout, encoding="utf-8")
    print(mode, result.stdout, flush=True)
