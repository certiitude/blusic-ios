"""Inject the app resolver credential into an ephemeral CI Info.plist.

This is a client credential and is recoverable from an IPA. It is not the
relay master key. Do not print its value or commit the generated plist.
"""
import os
from pathlib import Path
import plistlib
import re
import time
import urllib.parse


def configure(environ, path):
    address = environ.get("BLUSIC_IOS_RELAY_URL", "").strip().rstrip("/")
    token = environ.get("BLUSIC_IOS_RELAY_ACCESS", "")
    expiry = int(environ.get("BLUSIC_IOS_RELAY_EXPIRES", "0"))
    revision = environ.get("BLUSIC_IOS_RELAY_REVISION", "")
    url = urllib.parse.urlsplit(address)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment or url.path:
        raise ValueError("Adresse du relais de build absente ou invalide")
    match = re.fullmatch(r"app\.ios\.[a-f0-9]{64}", token)
    if not match or expiry != 0 or not revision:
        raise ValueError("Accès application du relais absent ou invalide ; aucun secret affiché")
    data = plistlib.loads(path.read_bytes())
    data["BlusicBundledRelay"] = {"url": address, "access": token, "expiresAt": expiry, "revision": revision}
    path.write_bytes(plistlib.dumps(data, sort_keys=False))
    return {"relay": address, "revision": revision, "configured": True, "master_key_in_build": False}


if __name__ == "__main__":
    import json
    print(json.dumps(configure(os.environ, Path("Blusic/Info.plist"))))
