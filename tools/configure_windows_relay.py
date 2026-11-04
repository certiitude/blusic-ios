"""Bundle only an existing non-expiring application capability, never the master key."""
import argparse
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--application-access-file", type=Path)
    args = parser.parse_args()
    access = os.environ.get("SORYN_RELAY_ACCESS", "")
    if args.application_access_file:
        # This file contains only the already-issued application capability.
        data = json.loads(args.application_access_file.read_text(encoding="utf-8"))
        access = data["capability"]
        if data.get("expiry") != 0:
            raise ValueError("Application access must not expire")
    address = os.environ.get("SORYN_RELAY_URL", "https://blusic-audio-relay.onrender.com").rstrip("/")
    parsed = urlsplit(address)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
        raise ValueError("Invalid relay address")
    if not re.fullmatch(r"app\.(ios|android|windows)\.[a-f0-9]{64}", access):
        raise ValueError("Missing application capability; no secret printed")
    folder = ROOT / "windows/assets"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "relay-config.json").write_text(json.dumps({"url": address, "applicationAccess": access, "expiresAt": 0}), encoding="utf-8")
    print("Windows relay preconfigured with non-expiring application access; no master/admin key included")


if __name__ == "__main__":
    main()
