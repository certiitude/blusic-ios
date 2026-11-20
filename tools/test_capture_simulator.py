"""Deterministic tests for capture validation; not an iPhone gameplay/UI test."""
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import capture_simulator as capture


class CaptureTests(unittest.TestCase):
    def test_compact_respects_sdk_and_availability(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [{"name": "iPhone SE", "udid": "compatible"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone SE", "udid": "too-new"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [{"name": "iPhone SE", "udid": "unavailable", "isAvailable": False}],
        }
        self.assertEqual(capture.compact_device(devices, (26, 3)), "compatible")
        with self.assertRaises(RuntimeError):
            capture.compact_device(devices, (17, 0))

    def test_requires_real_launch_pid(self):
        with patch.object(capture, "run", side_effect=[subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0, "app.blusic.ios: 123\n")]) as run:
            self.assertEqual(capture.launch_verified("device", ["--blusic-fixture"]), 123)
            self.assertEqual(run.call_args.args[:2], ("launch", "device"))
        with patch.object(capture, "run", side_effect=[subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0, "not launched")]):
            with self.assertRaises(RuntimeError):
                capture.launch_verified("device", [])

    def test_launch_timeout_never_becomes_success(self):
        with patch.object(capture, "run", side_effect=[subprocess.CompletedProcess([], 0), subprocess.TimeoutExpired("simctl launch", 90)]):
            with self.assertRaises(subprocess.TimeoutExpired):
                capture.launch_verified("device", [])

    def test_requires_app_still_running_before_screenshot(self):
        self.assertTrue(capture.app_running("123\t0\tUIKitApplication:app.blusic.ios[0x123]\n", 123))
        self.assertFalse(capture.app_running("123\t0\tcom.apple.springboard\n", 123))
        self.assertFalse(capture.app_running("-\t0\tUIKitApplication:app.blusic.ios\n", 123))

    def test_rejects_truncated_or_invalid_screenshot_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "screen.png"
            path.write_bytes(b"not an image")
            with self.assertRaises(RuntimeError):
                capture.png_dimensions(path)
            path.write_bytes(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 750, 1334))
            self.assertEqual(capture.png_dimensions(path), (750, 1334))


if __name__ == "__main__":
    unittest.main()
