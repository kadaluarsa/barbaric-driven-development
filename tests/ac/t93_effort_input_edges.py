"""Supplemental schema regressions; the GENERATE-frozen t93 oracle remains unchanged."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("effort", ROOT / "tests/lib/effort.py")
effort = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = effort
spec.loader.exec_module(effort)

CONTEXT = {"schema_version": 1, "route": "feature"}
PROFILE = {
    "schema_version": 1, "provider": "fictional", "model": "fixture-model",
    "platform": "fixture-api", "source_url": "https://example.test/effort",
    "verified_on": "2026-11-04", "supported_values": ["low", "medium", "high"],
    "mapping": {"low": "low", "medium": "medium", "high": "high"},
    "control": "reasoning.effort", "update_mode": "unknown", "cache_effect": "unknown",
}


class InputEdges(unittest.TestCase):
    def assert_rejected(self, context, profile=None):
        with tempfile.TemporaryDirectory() as temp:
            ctx = Path(temp) / "context.json"
            ctx.write_text(json.dumps(context), encoding="utf-8")
            argv = [sys.executable, "-B", str(ROOT / "tests/lib/effort.py"), "--context", str(ctx)]
            if profile is not None:
                prof = Path(temp) / "profile.json"
                prof.write_text(json.dumps(profile), encoding="utf-8")
                argv += ["--profile", str(prof)]
            result = subprocess.run(argv, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("effort: input error:"), result.stderr)
        self.assertLess(len(result.stderr), 240)
        self.assertNotIn("Traceback", result.stderr)

    def test_context_enum_types_return_bounded_input_errors(self):
        for field in ("hop", "stage", "phase", "complexity", "uncertainty"):
            for value in ([], {}, True, 1, None):
                with self.subTest(field=field, value=value):
                    self.assert_rejected(dict(CONTEXT, **{field: value}))

    def test_previous_target_types_return_bounded_input_errors(self):
        for value in ([], {}, True, 1, None):
            with self.subTest(value=value):
                previous = {"task_id": "fixture-task", "quality_target": value,
                            "failure_fingerprint": None, "evidence_fingerprint": None}
                self.assert_rejected(dict(CONTEXT, previous=previous))

    def test_profile_enum_types_return_bounded_input_errors(self):
        for field in ("control", "update_mode", "cache_effect"):
            for value in ([], {}, True, 1, None):
                with self.subTest(field=field, value=value):
                    profile = copy.deepcopy(PROFILE)
                    profile[field] = value
                    self.assert_rejected(CONTEXT, profile)

    def test_profile_dates_require_calendar_iso_format(self):
        for date in ("20261104", "2026-W45-3", "2026-02-30"):
            with self.subTest(date=date):
                self.assert_rejected(CONTEXT, dict(PROFILE, verified_on=date))
        self.assertEqual(effort.parse_profile(PROFILE).verified_on, "2026-11-04")

    def test_oversized_input_is_rejected_without_reading_entire_stream(self):
        class CountedStream(io.BytesIO):
            consumed = 0

            def read(self, size=-1):
                result = super().read(size)
                self.consumed += len(result)
                return result

        stream = CountedStream(b" " * (1024 * 1024))
        with patch("builtins.open", return_value=stream):
            with self.assertRaises(effort.Bad):
                effort.load("fixture.json")
        self.assertLessEqual(stream.consumed, 65537)


if __name__ == "__main__":
    unittest.main()
