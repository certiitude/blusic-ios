"""CI-only bundled public endpoint and client access; no server master secret."""
import json
import os
from pathlib import Path
import re

access = os.environ.get("BLUSIC_ANDROID_RELAY_ACCESS", "")
if not re.fullmatch(r"app\.android\.[a-f0-9]{64}", access):
    raise RuntimeError("Android application access missing or invalid")
path = Path("app/src/main/assets")
path.mkdir(parents=True, exist_ok=True)
(path / "bundled-relay.json").write_text(json.dumps({"url": "https://blusic-audio-relay.onrender.com",
    "access": access, "expiresAt": 0, "revision": "android-1.9.1"}), encoding="utf-8")
print("Bundled Android access configured (no expiry, no master key)")
