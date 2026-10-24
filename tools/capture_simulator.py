"""Capture the real SwiftUI app on a large and a compact iPhone simulator.

Screens use the app's real metadata requests; the mini/player preview uses the
bundled demo to inspect layout without making a playback availability claim.
"""
import argparse
import json
from pathlib import Path
import re
import struct
import subprocess
import time


def run(*args, capture=False, check=True):
    return subprocess.run(["xcrun", "simctl", *args], check=check, text=True,
                          stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE if capture else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/screenshots"))
    args = parser.parse_args()
    if not args.app.is_dir():
        raise RuntimeError("The simulator app has not been built.")
    args.output.mkdir(parents=True, exist_ok=True)
    data = json.loads(run("list", "devices", "available", "-j", capture=True).stdout)
    compact = []
    for runtime, devices in data["devices"].items():
        match = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
        if not match:
            continue
        for device in devices:
            if "iPhone SE" in device["name"] and device.get("isAvailable", True):
                compact.append((tuple(map(int, match.groups())), device["udid"]))
    targets = [("large", args.device)]
    if compact:
        targets.append(("compact", max(compact)[1]))
    else:
        raise RuntimeError("No compact iPhone SE simulator is installed; do not claim its layout was checked.")
    report = []
    for label, device in targets:
        run("bootstatus", device, "-b")
        run("install", device, str(args.app))
        run("status_bar", device, "override", "--time", "9:41", "--batteryLevel", "100", "--batteryState", "charged", "--wifiMode", "active", "--wifiBars", "3")
        screens = [
            ("home", ["--blusic-preview-mini"], 13),
            ("search", ["--blusic-screen=search", "--blusic-query=Niska", "--blusic-preview-mini"], 13),
            ("player", ["--blusic-preview-player"], 4),
        ]
        if label == "large":
            screens += [("artists", ["--blusic-screen=search", "--blusic-query=Niska", "--blusic-kind=artists"], 13),
                        ("artist-profile", ["--blusic-preview-artist"], 13),
                        ("sound", ["--blusic-preview-sound"], 4),
                        ("lyrics", ["--blusic-preview-player", "--blusic-lyrics"], 4)]
        for screen, launch_args, wait in screens:
            run("launch", "--terminate-running-process", device, "app.blusic.ios", *launch_args)
            time.sleep(wait)
            path = args.output / f"{label}-{screen}.png"
            run("io", device, "screenshot", "--type=png", str(path))
            with path.open("rb") as image:
                header = image.read(24)
            width, height = struct.unpack(">II", header[16:24])
            report.append({"device": device, "size": label, "screen": screen, "file": path.name, "pixels": [width, height]})
        run("terminate", device, "app.blusic.ios", check=False)
    (args.output / "capture-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
