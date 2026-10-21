"""Tests of cloud-build helpers, not evidence of an actual iOS compilation."""
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from select_simulator import choose
from verify_ipa import validate_ipa


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_latest_sdk_compatible_iphone(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [{"name": "iPhone 17 Pro", "udid": "correct", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 18", "udid": "too-new", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [{"name": "iPhone 16", "udid": "old", "isAvailable": True}],
        }
        self.assertEqual(choose(devices, (26, 2)), "correct")

    def test_does_not_use_ipad_or_unavailable_devices(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"name": "iPhone 17", "udid": "broken", "isAvailable": False},
            {"name": "iPad Pro", "udid": "ipad", "isAvailable": True},
        ]}
        with self.assertRaises(RuntimeError):
            choose(devices, (26, 2))


class IPARejectionTests(unittest.TestCase):
    """Synthetic headers are negative test fixtures only; never distributed as builds."""
    def fixture(self, folder, *, platforms=None, cpu=0x0100000C, macho_platform=2):
        path = Path(folder) / "invalid-fixture.zip"
        info = {"CFBundleExecutable": "Fixture", "CFBundleSupportedPlatforms": platforms or ["iPhoneOS"]}
        header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
        command = struct.pack("<6I", 0x32, 24, macho_platform, 0, 0, 0)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Fixture.app/Info.plist", plistlib.dumps(info))
            archive.writestr("Payload/Fixture.app/Fixture", header + command)
        return path

    def test_rejects_source_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "sources.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Blusic/BlusicApp.swift", "// source only")
            with self.assertRaisesRegex(ValueError, "Payload"):
                validate_ipa(path)

    def test_rejects_simulator_plist(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "iPhoneOS"):
                validate_ipa(self.fixture(folder, platforms=["iPhoneSimulator"]))

    def test_rejects_simulator_binary_even_if_plist_claims_iphone(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "Plateforme Mach-O"):
                validate_ipa(self.fixture(folder, macho_platform=7))

    def test_rejects_intel_binary(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "arm64"):
                validate_ipa(self.fixture(folder, cpu=0x01000007))

    def test_rejects_bundle_without_compiled_assets(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "Assets.car"):
                validate_ipa(self.fixture(folder))


if __name__ == "__main__":
    unittest.main(verbosity=2)
