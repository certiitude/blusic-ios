"""Verify emulator screenshot files exist and contain actual PNG image data."""
from pathlib import Path
import struct

folder = Path("app/build/screenshots")
for name in ["android-home", "android-search", "android-player", "android-lyrics", "android-settings", "android-quality", "android-sound", "android-relay", "android-compact-player", "android-compact-queue"]:
    matches = [p for p in folder.rglob(name + ".png") if p.is_file()]
    assert len(matches) == 1, f"Missing or ambiguous screenshot: {name}"
    data = matches[0].read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) > 1000, f"Invalid screenshot: {name}"
    width, height = struct.unpack(">II", data[16:24])
    assert width >= 320 and height >= 640
    print(f"Screenshot verified: {name}, {width}x{height}, {len(data)} bytes")
