"""Install isolated, free Android build tools under the approved temp folder.

Uses official distribution metadata and checksums. No system installation,
administrator access, billing, or global environment changes.
"""
import hashlib
import json
from pathlib import Path
import ssl
import subprocess
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(r"C:\Users\elome\AppData\Local\Temp\opencode\blusic-android-tools")


def fetch(address):
    with urllib.request.urlopen(urllib.request.Request(address, headers={"User-Agent": "Blusic-local-build/1.9.2"}), timeout=90) as response:
        return response.read()


def package(address, filename, checksum, algorithm="sha256"):
    target = ROOT / filename
    if not target.exists() or hashlib.new(algorithm, target.read_bytes()).hexdigest() != checksum:
        print("Downloading " + filename, flush=True)
        digest = hashlib.new(algorithm)
        with urllib.request.urlopen(address, timeout=90) as response, target.open("wb") as output:
            while block := response.read(1024 * 1024):
                digest.update(block); output.write(block)
        if digest.hexdigest() != checksum:
            raise RuntimeError("Official checksum mismatch: " + filename)
    return target


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    java = ROOT / "jdk"
    if not (java / "bin/java.exe").exists():
        release = json.loads(fetch("https://api.github.com/repos/adoptium/temurin17-binaries/releases/tags/jdk-17.0.16%2B8"))
        item = next(asset for asset in release["assets"] if asset["name"].startswith("OpenJDK17U-jdk_x64_windows_hotspot_") and asset["name"].endswith(".zip"))
        checksum = next(asset for asset in release["assets"] if asset["name"] == item["name"] + ".sha256.txt")
        archive = package(item["browser_download_url"], "jdk17.zip", fetch(checksum["browser_download_url"]).decode().split()[0])
        with zipfile.ZipFile(archive) as source:
            prefix = source.namelist()[0].split("/")[0] + "/"
            for member in source.infolist():
                if member.filename.startswith(prefix) and not member.is_dir():
                    relative = member.filename[len(prefix):]
                    target = java / relative; target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(source.read(member))
    gradle = ROOT / "gradle-8.11.1"
    if not (gradle / "bin/gradle.bat").exists():
        base = "https://downloads.gradle.org/distributions/gradle-8.11.1-bin.zip"
        archive = package(base, "gradle.zip", fetch(base + ".sha256").decode().strip())
        with zipfile.ZipFile(archive) as source:
            source.extractall(ROOT)
    sdk = ROOT / "sdk"
    if not (sdk / "cmdline-tools/latest/bin/sdkmanager.bat").exists():
        metadata = ET.fromstring(fetch("https://dl.google.com/android/repository/repository2-1.xml"))
        remote = next(node for node in metadata if node.tag.endswith("remotePackage") and node.get("path") == "cmdline-tools;latest")
        archives = remote.find("archives")
        archive = next(node for node in archives if node.findtext("host-os") == "windows")
        item = archive.find("complete")
        filename = item.findtext("url")
        downloaded = package("https://dl.google.com/android/repository/" + filename, "commandline-tools.zip", item.findtext("checksum").strip(), item.find("checksum").get("type", "sha1"))
        with zipfile.ZipFile(downloaded) as source:
            for member in source.infolist():
                if member.filename.startswith("cmdline-tools/") and not member.is_dir():
                    target = sdk / "cmdline-tools/latest" / member.filename[len("cmdline-tools/"):]
                    target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read(member))
    # This private JDK trusts the same public roots as Windows. Only this
    # temporary JDK's trust store is changed; no operating-system cert changes.
    marker = ROOT / "windows-roots-imported"
    if not marker.exists():
        for index, (certificate, encoding, trust) in enumerate(ssl.enum_certificates("ROOT")):
            if encoding != "x509_asn":
                continue
            cert = ROOT / "root.cer"; cert.write_bytes(certificate)
            result = subprocess.run([str(java / "bin/keytool.exe"), "-importcert", "-noprompt", "-trustcacerts", "-cacerts", "-storepass", "changeit", "-alias", f"windows-root-{index}", "-file", str(cert)], capture_output=True)
            if result.returncode:
                raise RuntimeError("Cannot import Windows public root into isolated JDK")
        (ROOT / "root.cer").unlink(missing_ok=True); marker.write_text("done")
    print(json.dumps({"java": str(java), "gradle": str(gradle), "sdk": str(sdk)}), flush=True)


if __name__ == "__main__":
    main()
