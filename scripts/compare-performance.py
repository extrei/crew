#!/usr/bin/env python3
"""Compare two Crew binaries with alternating, fresh-library launches."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import runpy
import sys
import tempfile


measurement = runpy.run_path(str(Path(__file__).with_name("measure-performance.py")))


def compare(baseline, candidate, rounds, output):
    variants = {"baseline": baseline.resolve(), "candidate": candidate.resolve()}
    report = {
        "status": "running", "started_at": datetime.now(timezone.utc).isoformat(),
        "rounds": rounds, "host": platform.platform(),
        "method": "Alternating baseline/candidate order each round. One fresh four-agent library per launch, warm OS caches, 1 s settle plus 1 s idle sample. Nearest-rank percentiles. Includes startup initialization; not a cold disk-cache test.",
        "inputs": {}, "samples": [], "failures": [],
    }
    save = lambda: measurement["write_report"](output, report)
    save()
    try:
        for name, path in variants.items():
            report["inputs"][name] = {"binary": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        with tempfile.TemporaryDirectory(prefix="crew-comparison-") as directory:
            for index in range(rounds):
                order = ["baseline", "candidate"] if index % 2 == 0 else ["candidate", "baseline"]
                for position, name in enumerate(order):
                    attempt_path = Path(directory) / f"{index}-{name}.json"
                    try:
                        result = measurement["measure"](variants[name], 1, 1, 1, "fresh", attempt_path)
                    except BaseException:
                        report["failures"].append({"round": index + 1, "variant": name,
                            "attempt": json.loads(attempt_path.read_text()) if attempt_path.exists() else None})
                        raise
                    report["samples"].append({**result["samples"][0], "round": index + 1,
                                              "variant": name, "order_in_round": position + 1})
                if (index + 1) % 10 == 0:
                    save()
                    print(f"Compared {index + 1}/{rounds} launch pairs", file=sys.stderr, flush=True)
        for name, path in variants.items():
            if hashlib.sha256(path.read_bytes()).hexdigest() != report["inputs"][name]["sha256"]:
                raise RuntimeError(f"{name} binary changed during comparison")
        report["summary"] = {
            name: {metric: measurement["distribution"]([sample[metric] for sample in report["samples"] if sample["variant"] == name])
                   for metric in ("process_to_ready_ms", "rss_mib", "virtual_mib", "idle_cpu_percent_one_core")}
            for name in variants
        }
        report["status"] = "complete"
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}")
        save()
        raise
    save()
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--rounds", type=int, default=40)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    result = compare(args.baseline, args.candidate, args.rounds, args.output)
    print(json.dumps(result["summary"], indent=2))
