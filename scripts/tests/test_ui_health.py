"""Regression checks for detecting a Simulator crash after XCTest succeeds."""

from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("check_apple_ui", Path(__file__).resolve().parents[1] / "check-apple-ui.py")
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class SimulatorHealthChecks(unittest.TestCase):
    def test_segmentation_fault_is_failure_even_when_xctest_succeeds(self):
        status = ui.parse_service_status('{ "LastExitStatus" = 11; "PID" = 61385; }')
        self.assertTrue(ui.abnormal_exit(status))
        health = {"xcodeExitStatus": 0, "testsStarted": True,
                  "errors": [str(status)], "crashes": {}}
        self.assertFalse(ui.checks_passed(health))

    def test_crash_report_is_failure_even_after_device_shuts_down(self):
        health = {"xcodeExitStatus": 0, "testsStarted": True, "errors": [],
                  "crashes": {"SpringBoard.ips": {"process": "SpringBoard"}}}
        self.assertFalse(ui.checks_passed(health))

    def test_success_requires_tests_and_a_healthy_environment(self):
        health = {"xcodeExitStatus": 0, "testsStarted": True, "errors": [], "crashes": {}}
        self.assertTrue(ui.checks_passed(health))
        health["xcodeExitStatus"] = 65
        self.assertFalse(ui.checks_passed(health))
        health["xcodeExitStatus"] = 0
        health["testsStarted"] = False
        self.assertFalse(ui.checks_passed(health))

    def test_normal_xcode_setup_and_shutdown(self):
        self.assertFalse(ui.abnormal_exit(ui.parse_service_status('{ "PID" = 70406; "LastExitStatus" = 9; }')))
        self.assertFalse(ui.abnormal_exit(ui.parse_service_status('{ "PID" = 70406; }')))
        self.assertFalse(ui.abnormal_exit(None))
        with self.assertRaises(ValueError):
            ui.parse_service_status('{ "LastExitStatus" = 11; }')

    def test_reports_are_scoped_to_device_and_crash_time(self):
        # Apple writes a metadata JSON line followed by a separate report object.
        data = {"coalitionName": "com.apple.CoreSimulator.SimDevice.test-ipad",
                "captureTime": "2026-09-27 16:33:38.5853 +0900",
                "procName": "SpringBoard", "exception": {"signal": "SIGSEGV"}}
        report = '{}\n' + json.dumps(data)
        before = datetime(2026, 9, 27, 7, 33, tzinfo=timezone.utc)
        after = datetime(2026, 9, 27, 7, 34, tzinfo=timezone.utc)
        self.assertEqual(ui.relevant_crash(report, "test-ipad", before)["exception"]["signal"], "SIGSEGV")
        self.assertIsNone(ui.relevant_crash(report, "another-ipad", before))
        self.assertIsNone(ui.relevant_crash(report, "test-ipad", after))


if __name__ == "__main__":
    unittest.main()
