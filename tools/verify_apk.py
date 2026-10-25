"""Inspect a real Android package. Cryptographic verification runs via apksigner in CI."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def manifest_values(data):
    strings = []
    elements = {}
    offset = 8
    def length8(position):
        n = data[position]; position += 1
        if n & 128:
            n = ((n & 127) << 8) | data[position]; position += 1
        return n, position
    while offset + 8 <= len(data):
        kind, header, size = struct.unpack_from("<HHI", data, offset)
        if size < header or size < 8 or offset + size > len(data):
            raise ValueError("Malformed Android binary XML")
        if kind == 1:
            count, _, flags, start, _ = struct.unpack_from("<IIIII", data, offset + 8)
            positions = struct.unpack_from(f"<{count}I", data, offset + header)
            for relative in positions:
                p = offset + start + relative
                if flags & 256:
                    _, p = length8(p)
                    length, p = length8(p)
                    strings.append(data[p:p+length].decode("utf-8"))
                else:
                    length = struct.unpack_from("<H", data, p)[0]; p += 2
                    if length & 32768:
                        length = ((length & 32767) << 16) | struct.unpack_from("<H", data, p)[0]; p += 2
                    strings.append(data[p:p+length*2].decode("utf-16-le"))
        elif kind == 0x102:
            _, name, attribute_start, attribute_size, count = struct.unpack_from("<IIHHH", data, offset + 16)
            values = {}
            for i in range(count):
                p = offset + 16 + attribute_start + i * attribute_size
                _, key, raw, _, _, value_type, value = struct.unpack_from("<IIIHBBI", data, p)
                values[strings[key]] = strings[raw] if raw != 0xFFFFFFFF else strings[value] if value_type == 3 else value
            elements.setdefault(strings[name], []).append(values)
        offset += size
    return elements


def inspect(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "APK CRC mismatch"
        names = set(archive.namelist())
        assert archive.read("classes.dex").startswith(b"dex\n"), "No Android DEX executable"
        for name in ["bleu-nuit.wav", "apres-la-pluie.wav", "orbite.wav", "dernier-metro.wav"]:
            assert archive.getinfo("assets/" + name).file_size > 100_000
        elements = manifest_values(archive.read("AndroidManifest.xml"))
        app = elements["manifest"][0]
        sdk = elements["uses-sdk"][0]
        assert app["package"] == "app.blusic.android"
        assert sdk["minSdkVersion"] == 26
        assert sdk["targetSdkVersion"] == 35
        assert any(v.get("name") == "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" for v in elements["uses-permission"])
    data = path.read_bytes()
    eocd = data.rfind(b"PK\x05\x06")
    assert eocd >= 0
    central = struct.unpack_from("<I", data, eocd + 16)[0]
    assert data[central-16:central] == b"APK Sig Block 42", "APK signing block missing"
    return {"package": app["package"], "version": app["versionName"], "version_code": app["versionCode"],
        "minimum_android_api": sdk["minSdkVersion"], "target_android_api": sdk["targetSdkVersion"],
        "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "signing_block_present": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.apk), indent=2))
    print("Structure and resources verified; use the CI apksigner result for signature verification, emulator/device tests for runtime.")
