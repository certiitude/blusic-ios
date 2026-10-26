"""Configure non-expiring app access without printing or embedding the relay master key."""
import hashlib
import hmac
import json
from pathlib import Path
import subprocess
import time

TEMP = Path(r"C:\Users\elome\AppData\Local\Temp\opencode")
GH = TEMP / "blusic-tools/gh-2.103.0/bin/gh.exe"
REPO = "certiitude/blusic-ios"


def main():
    private = json.loads((TEMP / "blusic-relay-deployment-private.json").read_text(encoding="utf-8"))
    expiry = 0
    signature = hmac.new(private["key"].encode(), b"application:ios|v1", hashlib.sha256).hexdigest()
    capability = f"app.ios.{signature}"
    revision = hashlib.sha256(capability.encode()).hexdigest()[:16]
    result = subprocess.run([str(GH), "secret", "set", "BLUSIC_IOS_RELAY_ACCESS", "--repo", REPO],
        input=capability, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError("GitHub a refusé l’enregistrement de l’accès iOS ; aucun secret affiché.")
    for name, value in {
        "BLUSIC_IOS_RELAY_URL": "https://blusic-audio-relay.onrender.com",
        "BLUSIC_IOS_RELAY_EXPIRES": str(expiry), "BLUSIC_IOS_RELAY_REVISION": revision
    }.items():
        subprocess.run([str(GH), "variable", "set", name, "--repo", REPO, "--body", value], check=True)
    (TEMP / "blusic-ios-relay-capability-private.json").write_text(json.dumps({"capability": capability, "expiry": expiry, "revision": revision}), encoding="utf-8")
    print(json.dumps({"configured": True, "relay": "https://blusic-audio-relay.onrender.com", "expires_at_ms": expiry, "revision": revision, "master_key_in_build": False}))


if __name__ == "__main__":
    main()
