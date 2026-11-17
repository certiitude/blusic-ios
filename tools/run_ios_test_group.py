"""Run deterministic native tests separately from explicitly named live-network probes.

Both groups really execute their tests. Network failures get a separate xcresult;
they are not silently skipped or turned into successful playback evidence.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def groups(source):
    names = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
    if not names or len(names) != len(set(names)):
        raise ValueError("Missing or duplicated XCTest names")
    live = [name for name in names if name.startswith("testLive")]
    return {"deterministic": [name for name in names if name not in live], "network": live}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=["deterministic", "network"], required=True)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--exclude", action="append", default=[])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    selected = groups((root / "BlusicTests/BlusicTests.swift").read_text(encoding="utf-8"))[args.group]
    if any(name not in selected for name in args.exclude):
        raise ValueError("An exclusion is not part of the selected group")
    selected = [name for name in selected if name not in args.exclude]
    if not selected:
        raise ValueError("Cannot run an empty test group")
    print(json.dumps({"group": args.group, "count": len(selected), "tests": selected}, indent=2), flush=True)
    if args.list:
        return
    simulator = os.environ["SIMULATOR_ID"]
    result = "build/BlusicTests.xcresult" if args.group == "deterministic" else "build/SorynNetworkTests.xcresult"
    command = ["xcodebuild", "test", "-project", "Blusic.xcodeproj", "-scheme", "Blusic",
               "-destination", f"platform=iOS Simulator,id={simulator}",
               "-derivedDataPath", "build/DerivedData", "-resultBundlePath", result,
               "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO"]
    command += [f"-only-testing:BlusicTests/BlusicTests/{name}" for name in selected]
    subprocess.run(command, cwd=root, check=True)


if __name__ == "__main__":
    main()
