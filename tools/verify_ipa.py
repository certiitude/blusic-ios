"""Validate a compiled arm64 iPhone IPA. Never treats a simulator app as an IPA.

Runs on Windows and macOS with Python's standard library only.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


def validate_ipa(path: Path, require_youtubei: bool = False) -> dict:
    with zipfile.ZipFile(path) as archive:
        files = archive.namelist()
        invalid = archive.testzip()
        if invalid:
            raise ValueError(f"Entrée ZIP corrompue : {invalid}")
        infos = [name for name in files if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(infos) != 1:
            raise ValueError("L’IPA doit contenir exactement une application Payload/*.app.")
        root = infos[0].rsplit("/", 1)[0] + "/"
        info = plistlib.loads(archive.read(infos[0]))
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("Ce bundle n’est pas destiné à un iPhone physique (iPhoneOS absent).")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or "\\" in executable:
            raise ValueError("Nom d’exécutable invalide dans Info.plist.")
        with archive.open(root + executable) as binary:
            header = binary.read(32)
            if len(header) != 32:
                raise ValueError("Exécutable absent ou tronqué.")
            magic, cpu, _, kind, ncmds, size, _, _ = struct.unpack("<8I", header)
            if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2:
                raise ValueError("Le binaire n’est pas un exécutable Mach-O arm64 iPhone.")
            if size > 4_000_000 or ncmds > 10000:
                raise ValueError("En-tête Mach-O incohérent.")
            commands = binary.read(size)
        offset = 0
        platforms = []
        for _ in range(ncmds):
            if offset + 8 > len(commands):
                raise ValueError("Commandes Mach-O tronquées.")
            command, length = struct.unpack_from("<II", commands, offset)
            if length < 8 or offset + length > len(commands):
                raise ValueError("Taille de commande Mach-O invalide.")
            if command == 0x32:  # LC_BUILD_VERSION
                if length < 24:
                    raise ValueError("LC_BUILD_VERSION invalide.")
                platforms.append(struct.unpack_from("<I", commands, offset + 8)[0])
            offset += length
        if platforms != [2]:  # PLATFORM_IOS, not PLATFORM_IOSSIMULATOR (7)
            raise ValueError(f"Plateforme Mach-O incompatible avec un iPhone physique : {platforms}.")
        if root + "Assets.car" not in files:
            raise ValueError("Catalogue d’images compilé Assets.car absent.")
        for audio in ["bleu-nuit.wav", "apres-la-pluie.wav", "orbite.wav", "dernier-metro.wav"]:
            if root + audio not in files:
                raise ValueError(f"Média embarqué absent : {audio}")
        report = {
            "bundle_id": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"),
            "minimum_ios": info.get("MinimumOSVersion"),
            "architecture": "arm64",
            "platform": "iPhoneOS",
            "code_resources_present": root + "_CodeSignature/CodeResources" in files,
            "size": path.stat().st_size,
        }
        relay = info.get("BlusicBundledRelay")
        if require_youtubei or relay:
            import re
            import urllib.parse
            if not isinstance(relay, dict):
                raise ValueError("Configuration youtubei.js préintégrée absente de l’IPA.")
            endpoint = urllib.parse.urlsplit(relay.get("url", ""))
            if endpoint.scheme != "https" or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
                raise ValueError("Adresse du relais dans l’IPA invalide.")
            if not re.fullmatch(r"app\.ios\.[a-f0-9]{64}", relay.get("access", "")) or relay.get("expiresAt") != 0 or not relay.get("revision"):
                raise ValueError("Accès application youtubei.js absent, invalide ou expirant.")
            report.update(youtubei_preconfigured=True, youtubei_server=endpoint.hostname, youtubei_access_expires=False, youtubei_revision=relay["revision"])
        if require_youtubei:
            resolver = root + "YouTubeiResolver.js"
            if resolver not in files:
                raise ValueError("Le moteur youtubei.js/SABR embarqué est absent de l’IPA.")
            script = archive.read(resolver)
            if len(script) < 100_000 or b"__blusicResolve" not in script or b"SabrStream" not in script:
                raise ValueError("Le moteur youtubei.js embarqué est incomplet.")
            report["youtubei_on_device_resolver"] = True
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--require-youtubei", action="store_true")
    args = parser.parse_args()
    report = validate_ipa(args.ipa, require_youtubei=args.require_youtubei)
    print(f"IPA iPhone vérifiée : {args.ipa}")
    for key, value in report.items():
        print(f"  {key}: {value}")
    print("Ce contrôle valide le paquet compilé, pas son fonctionnement à l’exécution ni sa signature Apple.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, struct.error) as error:
        print(f"IPA invalide : {error}", file=sys.stderr)
        sys.exit(1)
