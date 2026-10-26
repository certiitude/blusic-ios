"""Provision Android-only, non-expiring application access; never print secrets."""
import hashlib
import hmac
import json
from pathlib import Path
import subprocess

def main():
    temp = Path(r"C:\Users\elome\AppData\Local\Temp\opencode")
    private = json.loads((temp / "blusic-relay-deployment-private.json").read_text(encoding="utf-8"))
    access = "app.android." + hmac.new(private["key"].encode(), b"application:android|v1", hashlib.sha256).hexdigest()
    gh = str(temp / "blusic-tools/gh-2.103.0/bin/gh.exe")
    result = subprocess.run([gh, "secret", "set", "BLUSIC_ANDROID_RELAY_ACCESS", "--repo", "certiitude/blusic-ios"],
                            input=access, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Impossible de provisionner l’accès Android ; aucun secret affiché")
    print("Android application access configured; non-expiring; server master key excluded")

if __name__ == "__main__":
    main()
