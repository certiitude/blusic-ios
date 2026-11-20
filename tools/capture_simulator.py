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


def run(*args, capture=False, check=True, timeout=60):
    return subprocess.run(["xcrun", "simctl", *args], check=check, text=True,
                          stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE if capture else None,
                          timeout=timeout)


def compact_device(devices, sdk_version):
    candidates = []
    for runtime, phones in devices.items():
        match = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
        if not match:
            continue
        version = tuple(map(int, match.groups()))
        if version > sdk_version[:2]:
            continue
        for phone in phones:
            if "iPhone SE" in phone["name"] and phone.get("isAvailable", True):
                candidates.append((version, phone["udid"]))
    if not candidates:
        raise RuntimeError("No compatible compact iPhone SE is installed; its layout cannot be claimed as checked.")
    return max(candidates)[1]


def launch_verified(device, launch_args):
    # On a freshly booted simulator, terminating an absent application can hang
    # in some runtimes. Only terminate a PID confirmed by the process list.
    # A termination/launch timeout still fails; it is never capture evidence.
    processes = run("spawn", device, "launchctl", "list", capture=True, timeout=30).stdout
    if running_app_pid(processes) is not None:
        run("terminate", device, "app.blusic.ios", capture=True, timeout=20)
    launched = run("launch", device, "app.blusic.ios", *launch_args, capture=True, timeout=90)
    match = re.search(r"app\.blusic\.ios:\s*(\d+)", launched.stdout)
    if not match:
        raise RuntimeError("simctl did not confirm an app process: " + launched.stdout)
    return int(match.group(1))


def png_dimensions(path):
    with path.open("rb") as image:
        header = image.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise RuntimeError("Screenshot is not a valid PNG: " + str(path))
    width, height = struct.unpack(">II", header[16:24])
    if width < 320 or height < 480:
        raise RuntimeError("Screenshot is smaller than an iPhone screen")
    return width, height


def running_app_pid(output):
    for line in output.splitlines():
        columns = line.split(None, 2)
        if len(columns) == 3 and columns[0].isdigit() and re.search(r"app\.blusic\.ios(?:\[|\s|$)", columns[2]):
            return int(columns[0])
    return None


def app_running(output, pid):
    return running_app_pid(output) == pid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build/screenshots"))
    parser.add_argument("--focus-audio", action="store_true", help="Capture audio settings and downloads without waiting for unrelated live searches")
    parser.add_argument("--local-fixture", action="store_true", help="Use an isolated in-memory offline demo library; never claim it tests live catalogue playback")
    parser.add_argument("--isolate-devices", action="store_true", help="CI only: shut down the previous target before booting the compact simulator")
    args = parser.parse_args()
    if not args.app.is_dir():
        raise RuntimeError("The simulator app has not been built.")
    args.output.mkdir(parents=True, exist_ok=True)
    data = json.loads(run("list", "devices", "available", "-j", capture=True).stdout)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
    targets = [("large", args.device), ("compact", compact_device(data["devices"], tuple(map(int, sdk.split(".")))))]
    report = []
    for label, device in targets:
        if args.isolate_devices and label == "compact":
            run("shutdown", args.device, capture=True, check=False)
        if args.isolate_devices:
            # Start with a clean process graph after XCTest; keep app data intact.
            run("shutdown", device, capture=True, check=False)
        run("bootstatus", device, "-b", timeout=150)
        run("install", device, str(args.app))
        run("status_bar", device, "override", "--time", "9:41", "--batteryLevel", "100", "--batteryState", "charged", "--wifiMode", "active", "--wifiBars", "3")
        screens = [
            ("home", ["--blusic-preview-mini"], 13),
            ("search", ["--blusic-screen=search", "--blusic-query=Niska", "--blusic-preview-mini"], 13),
            ("player", ["--blusic-preview-player"], 4),
            ("lyrics", ["--blusic-preview-player", "--blusic-lyrics"], 4),
            ("lyrics-later", ["--blusic-preview-player", "--blusic-lyrics"], 13),
            ("quality", ["--blusic-preview-settings", "--blusic-high-quality"], 4),
            ("opus", ["--blusic-preview-settings", "--blusic-opus"], 4),
            ("downloads", ["--blusic-preview-downloads"], 4),
        ]
        if label == "large":
            screens += [("artists", ["--blusic-screen=search", "--blusic-query=Niska", "--blusic-kind=artists"], 13),
                        ("artist-profile", ["--blusic-preview-artist"], 13),
                         ("sound", ["--blusic-preview-sound"], 4)]
        if args.focus_audio:
            screens = [("home", ["--blusic-preview-mini"], 4),
                       ("player", ["--blusic-preview-player"], 4),
                       ("opus", ["--blusic-preview-settings", "--blusic-opus"], 4),
                       ("sound", ["--blusic-preview-sound"], 4),
                       ("radio", ["--blusic-preview-radio"], 4),
                       ("downloads", ["--blusic-preview-downloads"], 4)]
        if args.local_fixture:
            screens = [("home", ["--blusic-preview-mini"], 3),
                       ("search", ["--blusic-screen=search"], 3),
                       ("library", ["--blusic-screen=library"], 3),
                       ("player", ["--blusic-preview-player"], 3),
                       ("queue", ["--blusic-preview-player", "--blusic-queue"], 3),
                       ("lyrics", ["--blusic-preview-player", "--blusic-lyrics"], 3),
                       ("sound", ["--blusic-preview-sound"], 3),
                       ("library-light", ["--blusic-screen=library", "--blusic-light"], 3),
                       ("search-large-text", ["--blusic-screen=search", "--blusic-large-text"], 3)]
        for screen, launch_args, wait in screens:
            print(f"Capturing {label}/{screen} on {device}", flush=True)
            if args.local_fixture:
                launch_args = ["--blusic-fixture", *launch_args]
            pid = launch_verified(device, launch_args)
            time.sleep(wait)
            processes = run("spawn", device, "launchctl", "list", capture=True).stdout
            if not app_running(processes, pid):
                raise RuntimeError(f"App process {pid} exited before {label}/{screen}; do not capture SpringBoard as app evidence")
            path = args.output / f"{label}-{screen}.png"
            run("io", device, "screenshot", "--type=png", str(path))
            width, height = png_dimensions(path)
            report.append({"device": device, "size": label, "screen": screen, "file": path.name, "pixels": [width, height],
                           "pid": pid, "evidence": "offline demo layout only" if args.local_fixture else "live metadata layout; player uses local demo"})
            (args.output / "capture-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        processes = run("spawn", device, "launchctl", "list", capture=True).stdout
        if running_app_pid(processes) is not None:
            run("terminate", device, "app.blusic.ios", capture=True, timeout=20)
    (args.output / "capture-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
