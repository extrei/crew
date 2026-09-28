#!/usr/bin/env python3
"""Regression checks for benchmark arithmetic and failure reporting."""

import json
from pathlib import Path
import runpy
import sys
import tempfile
import unittest


MEASUREMENT = runpy.run_path(str(Path(__file__).with_name("measure-performance.py")))


class PerformanceRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="crew-performance-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def executable(self, body):
        path = self.root / "fake-crew"
        path.write_text(f"#!{sys.executable}\nimport json,os,sys,time\nfrom pathlib import Path\n" + body)
        path.chmod(0o700)
        return path

    def test_nearest_rank_percentiles(self):
        result = MEASUREMENT["distribution"](list(range(1, 41)))
        self.assertEqual((result["p50"], result["p90"], result["p95"]), (20, 36, 38))

    def test_marker_requires_valid_process_and_readiness(self):
        marker = self.root / "ready.json"
        valid = {"pid": 123, "ready_ms": 10, "agents": 4}
        for invalid in ["not-json", "[]", json.dumps({**valid, "pid": 999}),
                        json.dumps({**valid, "ready_ms": float("nan")}),
                        json.dumps({**valid, "agents": 0})]:
            marker.write_text(invalid)
            with self.assertRaises(ValueError):
                MEASUREMENT["read_ready_marker"](marker, 123)
        marker.write_text(json.dumps(valid))
        self.assertEqual(MEASUREMENT["read_ready_marker"](marker, 123), valid)

    def test_malformed_marker_replaces_stale_success_with_failure(self):
        binary = self.executable("marker=Path(sys.argv[sys.argv.index('--startup-marker')+1])\nmarker.write_text('malformed')\ntime.sleep(10)\n")
        output = self.root / "report.json"
        output.write_text('{"status":"complete","samples":["old"]}')
        with self.assertRaises(ValueError):
            MEASUREMENT["measure"](binary, 1, 0, 0.01, output=output)
        report = json.loads(output.read_text())
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["samples"], [])
        self.assertEqual(report["attempts"][0]["status"], "failed")
        self.assertNotIn("summary", report)

    def test_exit_before_ready_is_recorded(self):
        binary = self.executable("sys.exit(7)\n")
        output = self.root / "report.json"
        with self.assertRaises(RuntimeError):
            MEASUREMENT["measure"](binary, 1, 0, 0.01, output=output)
        report = json.loads(output.read_text())
        self.assertEqual(report["status"], "failed")
        self.assertIn("exited before ready", report["error"])
        self.assertEqual(len(report["attempts"]), 1)

    def test_missing_binary_cannot_leave_previous_success(self):
        output = self.root / "report.json"
        output.write_text('{"status":"complete"}')
        with self.assertRaises(FileNotFoundError):
            MEASUREMENT["measure"](self.root / "missing", 1, output=output)
        self.assertEqual(json.loads(output.read_text())["status"], "failed")

    def test_valid_run_has_one_sample_per_completed_attempt(self):
        binary = self.executable("marker=Path(sys.argv[sys.argv.index('--startup-marker')+1])\nmarker.write_text(json.dumps({'pid':os.getpid(),'ready_ms':0,'agents':4}))\ntime.sleep(10)\n")
        output = self.root / "report.json"
        report = MEASUREMENT["measure"](binary, 2, 0, 0.01, output=output)
        self.assertEqual(report["status"], "complete")
        self.assertEqual(len(report["samples"]), 2)
        self.assertTrue(all(item["status"] == "complete" for item in report["attempts"]))
        self.assertEqual(report["summary"]["rss_mib"]["count"], 2)
        self.assertEqual(json.loads(output.read_text()), report)


if __name__ == "__main__":
    unittest.main()
