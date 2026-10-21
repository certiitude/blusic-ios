"""Select an installed iPhone runtime compatible with the selected Xcode SDK."""
import json
import re
import subprocess


def choose(devices, sdk_version):
    candidates = []
    for runtime, phones in devices.items():
        match = re.search(r"\.iOS-(\d+)-(\d+)", runtime)
        if not match:
            continue
        version = tuple(map(int, match.groups()))
        if version > sdk_version[:2]:
            continue
        for phone in phones:
            if phone.get("isAvailable", True) and phone["name"].startswith("iPhone"):
                candidates.append((version, "Pro" in phone["name"], phone["name"], phone["udid"]))
    if not candidates:
        raise RuntimeError("Aucun simulateur iPhone installé compatible avec le SDK Xcode sélectionné.")
    return max(candidates)[-1]


if __name__ == "__main__":
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
    sdk_version = tuple(int(part) for part in sdk.split("."))
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
    print("SIMULATOR_ID=" + choose(devices["devices"], sdk_version))
