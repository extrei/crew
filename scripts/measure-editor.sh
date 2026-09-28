#!/bin/sh
set -eu

CREW_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$CREW_ROOT"
python3 - "$CREW_ROOT" "${1:-$CREW_ROOT/artifacts/rename-editor/editor-performance.json}" "${2:-40}" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

root, output, runs = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
if runs < 1:
    raise SystemExit("runs must be positive")
output.parent.mkdir(parents=True, exist_ok=True)
report = {"status": "running", "requested_runs_per_case": runs,
          "started_at": datetime.now(timezone.utc).isoformat()}
def write_report():
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(output)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
write_report()
try:
    source_files = sorted((root / "Sources").rglob("*.swift")) + [root / "scripts/measure-editor.swift"]
    hashes = {str(path.relative_to(root)): digest(path) for path in source_files}
    subprocess.run(["swift", "build", "-c", "release"], cwd=root, check=True)
    products = Path(subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=root, text=True).strip())
    binary = root / "artifacts/rename-editor/editor-benchmark"
    binary.parent.mkdir(parents=True, exist_ok=True)
    flags = ["-O", "-whole-module-optimization", "-parse-as-library", "-module-name", "CrewUI"]
    subprocess.run(["swiftc", *flags, "-I", str(products),
                    *map(str, sorted((root / "Sources/CrewUI").glob("*.swift"))),
                    str(root / "scripts/measure-editor.swift"), str(products / "CrewCore.o"),
                    "-o", str(binary)], cwd=root, check=True)
    if hashes != {str(path.relative_to(root)): digest(path) for path in source_files}:
        raise RuntimeError("Sources changed while the benchmark was compiling")
    provenance = {"sources_sha256": hashes, "core_object_sha256": digest(products / "CrewCore.o"),
                  "benchmark_binary_sha256": digest(binary), "release_binary_sha256": digest(products / "Crew"),
                  "compiler": subprocess.check_output(["swiftc", "--version"], text=True).strip(),
                  "compiler_flags": flags, "host": platform.platform()}
    report["provenance"] = provenance
    write_report()
    subprocess.run([str(binary), str(output), str(runs)], cwd=root, check=True)
    measured = json.loads(output.read_text())
    if any(len(case["samples"]) != runs for case in measured["cases"].values()):
        raise RuntimeError("Benchmark returned an incomplete sample set")
    report.update(measured, status="complete")
except BaseException as error:
    report.update(status="failed", error=f"{type(error).__name__}: {error}")
    write_report()
    raise
write_report()
PY
