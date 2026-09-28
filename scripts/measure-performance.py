#!/usr/bin/env python3
"""Measure a release Crew process using an isolated temporary library."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import platform
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time


def cpu_seconds(value):
    minutes, seconds = value.strip().split(":")
    return int(minutes) * 60 + float(seconds)


def process_sample(pid):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "rss=,vsz=,time="],
        capture_output=True, text=True, check=True,
    )
    rss, virtual, cpu = result.stdout.strip().split()
    return {"rss_kib": int(rss), "virtual_kib": int(virtual), "cpu_seconds": cpu_seconds(cpu)}


def distribution(values):
    ordered = sorted(values)
    def percentile(percent):
        return round(ordered[max(0, math.ceil(percent * len(ordered)) - 1)], 2)
    return {
        "count": len(ordered), "min": round(ordered[0], 2),
        "p50": percentile(0.5), "p90": percentile(0.9),
        "p95": percentile(0.95), "max": round(ordered[-1], 2),
    }


def read_ready_marker(marker, pid):
    data = json.loads(marker.read_text())
    if not isinstance(data, dict) or type(data.get("pid")) is not int or data["pid"] != pid:
        raise ValueError("Startup marker does not identify the measured process")
    milliseconds = data.get("ready_ms")
    if type(milliseconds) not in (int, float) or not math.isfinite(milliseconds) or milliseconds < 0:
        raise ValueError("Startup marker has an invalid ready_ms")
    if type(data.get("agents")) is not int or data["agents"] != 4:
        raise ValueError("Startup marker does not confirm the four seeded agents")
    return data


def write_report(path, report):
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(path)


def measure(binary, runs, settle_seconds=2, idle_seconds=3, library_mode="existing", output=None):
    samples = []
    report = {
        "status": "running",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "requested_runs": runs,
        "binary": str(binary),
        "host": {"platform": platform.platform(), "architecture": platform.machine()},
        "method": f"Direct process launch to app-ready marker; {settle_seconds:g} s settle, {idle_seconds:g} s idle CPU sample; ps RSS and VSZ. Nearest-rank percentiles.",
        "library_mode": library_mode,
        "notes": "VSZ includes shared mappings and reserved address space; it is not physical consumption. CPU time has 10 ms resolution. This is not a cold disk-cache benchmark. Fewer than 20 runs give weak p90/p95 tail estimates.",
        "attempts": [],
        "samples": samples,
    }
    write_report(output, report)
    try:
        report["binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="crew-performance-") as directory:
            root = Path(directory)
            for index in range(runs):
                attempt = {"run": index + 1, "status": "running"}
                report["attempts"].append(attempt)
                write_report(output, report)
                marker = root / f"ready-{index}.json"
                started = time.perf_counter()
                process = None
                try:
                    process = subprocess.Popen(
                        [str(binary), "--data-dir", str(root / (f"library-{index}" if library_mode == "fresh" else "library")), "--startup-marker", str(marker)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                    )
                    attempt["pid"] = process.pid
                    while not marker.exists():
                        if process.poll() is not None:
                            raise RuntimeError(f"Crew exited before ready: {process.stderr.read()}")
                        if time.perf_counter() - started > 15:
                            raise TimeoutError("Crew did not write its startup marker within 15 seconds")
                        time.sleep(0.01)
                    ready_ms = (time.perf_counter() - started) * 1000
                    marker_data = read_ready_marker(marker, process.pid)
                    time.sleep(settle_seconds)
                    before = process_sample(process.pid)
                    idle_started = time.perf_counter()
                    time.sleep(idle_seconds)
                    after = process_sample(process.pid)
                    idle_elapsed = time.perf_counter() - idle_started
                    samples.append({
                        "run": index + 1,
                        "library": "first launch" if index == 0 or library_mode == "fresh" else "existing library",
                        "process_to_ready_ms": round(ready_ms, 1),
                        "idle_cpu_percent_one_core": round(100 * (after["cpu_seconds"] - before["cpu_seconds"])/idle_elapsed, 2),
                        "rss_mib": round(after["rss_kib"] / 1024, 2),
                        "virtual_mib": round(after["virtual_kib"] / 1024, 2),
                        "app_marker": marker_data,
                    })
                    attempt["status"] = "complete"
                except BaseException as error:
                    attempt.update(status="failed", error=f"{type(error).__name__}: {error}")
                    raise
                finally:
                    if process is not None:
                        if process.poll() is None:
                            process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                        process.stderr.close()
                write_report(output, report)
                if (index + 1) % 10 == 0:
                    print(f"Measured {index + 1}/{runs} launches", file=sys.stderr, flush=True)
        report.update(status="complete", median_ready_ms=round(statistics.median(s["process_to_ready_ms"] for s in samples), 1),
            summary={key: distribution([sample[key] for sample in samples])
                     for key in ("process_to_ready_ms", "rss_mib", "virtual_mib", "idle_cpu_percent_one_core")})
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        write_report(output, report)
        raise
    write_report(output, report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[1] / "dist/Crew.app/Contents/MacOS/Crew")
    parser.add_argument("--runs", type=int, default=40)
    parser.add_argument("--settle-seconds", type=float, default=2)
    parser.add_argument("--idle-seconds", type=float, default=3)
    parser.add_argument("--library-mode", choices=["existing", "fresh"], default="existing")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be at least 1")
    if args.settle_seconds < 0 or args.idle_seconds <= 0:
        parser.error("settle must be nonnegative and idle must be positive")
    report = json.dumps(measure(args.binary.resolve(), args.runs, args.settle_seconds, args.idle_seconds, args.library_mode, args.output), indent=2) + "\n"
    print(report, end="")
