"""Build an isolated Studio place for native benchmarks or exact validation.

Open the generated place in Studio and press Play. Both the workload Script
and numerical ModuleScripts use --!native; MCP/Command Bar execution is not
used to time the numerical kernels. No existing game is modified.
"""
import argparse
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", default="v0.2.0", help="Git ref for the released baseline")
parser.add_argument("--validate", action="store_true", help="Run exact validation instead of timing")
parser.add_argument("--interpreter", action="store_true", help="Strip native directives from both copies and runner")
args = parser.parse_args()
mode = "interpreter" if args.interpreter else "native"
purpose = "validation" if args.validate else "performance"
out = ROOT / "build" / "studio-native" / f"{mode}-{purpose}"
out.mkdir(parents=True, exist_ok=True)
folders = {}
for label in ["baseline", "final"]:
    folder = out / label
    folder.mkdir(exist_ok=True)
    folders[label] = {"$className": "Folder"}
    for name in ["Permutation", "Perlin", "Simplex"]:
        relative = f"src/Noise/{name}.luau"
        if label == "baseline":
            source = subprocess.check_output(
                ["git", "show", f"{args.reference}:{relative}"], cwd=ROOT
            ).decode("utf-8")
        else:
            source = (ROOT / relative).read_text(encoding="utf-8")
        if args.interpreter:
            source = source.replace("--!native", "")
        target = folder / f"{name}.luau"
        target.write_text(source, encoding="utf-8")
        folders[label][name] = {"$path": str(target)}
runner = ROOT / "test" / f"studio-native-{purpose}.server.luau"
source = runner.read_text(encoding="utf-8")
if args.interpreter:
    source = source.replace("--!native", "")
target = out / "Runner.server.luau"
target.write_text(source, encoding="utf-8")
project = {
    "name": "AtlasNativeBenchmark",
    "tree": {
        "$className": "DataModel",
        "ReplicatedStorage": {
            "Atlas": {"$path": str(ROOT / "src")},
            "AtlasNativeExperiments": {"$className": "Folder", **folders},
        },
        "ServerScriptService": {"AtlasNativeRunner": {"$path": str(target)}},
        "Workspace": {"$className": "Workspace"},
    },
}
project_path = out / "benchmark.project.json"
project_path.write_text(json.dumps(project, indent=2), encoding="utf-8")
place = out / "AtlasNativeBenchmark.rbxl"
subprocess.run(["rojo", "build", str(project_path), "-o", str(place)], cwd=ROOT, check=True)
print(place)
