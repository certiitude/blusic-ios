"""Static/package checks. This is NOT an iOS build or an on-device playback test.

python -m pip install -r tools/requirements-qa.txt
python tools/check_project.py
"""
from pathlib import Path
import array
import json
import math
import plistlib
import re
import sys
import wave
import xml.etree.ElementTree as ET

from openstep_parser import OpenStepDecoder
from PIL import Image
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


def main():
    pbx = OpenStepDecoder.ParseFromString((ROOT / "Blusic.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = pbx["objects"]
    project = objects[pbx["rootObject"]]
    check(project["isa"] == "PBXProject", "Missing PBXProject")
    resolved = {}

    def walk(identifier, parent):
        obj = objects[identifier]
        path = parent / obj.get("path", "")
        if obj["isa"] == "PBXGroup":
            for child in obj.get("children", []):
                walk(child, path)
        elif obj["isa"] == "PBXFileReference" and obj.get("sourceTree") != "BUILT_PRODUCTS_DIR":
            check(path.exists(), f"Xcode reference does not exist: {path.relative_to(ROOT)}")
            resolved[identifier] = path

    walk(project["mainGroup"], ROOT)
    compiled, resources = [], []
    for target_id in project["targets"]:
        target = objects[target_id]
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            for build_id in phase.get("files", []):
                ref = objects[build_id]["fileRef"]
                check(ref in resolved, f"Ungrouped build reference: {ref}")
                if ref not in resolved:
                    continue
                if phase["isa"] == "PBXSourcesBuildPhase":
                    compiled.append(resolved[ref])
                if phase["isa"] == "PBXResourcesBuildPhase":
                    resources.append(resolved[ref])
    swift_files = sorted((ROOT/"Blusic").glob("*.swift")) + sorted((ROOT/"BlusicTests").glob("*.swift"))
    for source in swift_files:
        check(compiled.count(source) == 1, f"Swift source not built exactly once: {source.name}")

    parser = Parser(Language(tree_sitter_swift.language()))
    for source in swift_files:
        data = source.read_bytes()
        tree = parser.parse(data)
        if tree.root_node.has_error:
            def descend(node):
                if node.type == "ERROR" or node.is_missing:
                    line = node.start_point.row + 1
                    errors.append(f"Swift parse error {source.name}:{line}: {data[node.start_byte:node.end_byte][:160]!r}")
                else:
                    for child in node.children:
                        descend(child)
            descend(tree.root_node)
    print(f"Swift syntax parsed: {len(swift_files)} files (not type-checked)")

    for name in ["Info.plist", "PrivacyInfo.xcprivacy"]:
        with (ROOT/"Blusic"/name).open("rb") as f:
            content = plistlib.load(f)
        if name == "Info.plist":
            check("audio" in content.get("UIBackgroundModes", []), "Background audio entitlement missing")
            check(content["CFBundleDisplayName"] == "Blusic", "Wrong app name")
            check(content.get("CFBundleShortVersionString") == "$(MARKETING_VERSION)", "App version must follow the Xcode marketing version")
            check(content.get("CFBundleVersion") == "$(CURRENT_PROJECT_VERSION)", "App build number must follow Xcode")
    ET.parse(ROOT/"Blusic.xcodeproj/xcshareddata/xcschemes/Blusic.xcscheme")
    print("Xcode object references, plist files and shared scheme checked")

    assets = ROOT/"Blusic/Assets.xcassets"
    for catalog in assets.rglob("Contents.json"):
        spec = json.loads(catalog.read_text(encoding="utf-8"))
        for image in spec.get("images", []):
            if "filename" in image:
                check((catalog.parent/image["filename"]).exists(), f"Missing asset: {image['filename']}")
    with Image.open(assets/"AppIcon.appiconset/AppIcon.png") as icon:
        check(icon.size == (1024, 1024), "Icon must be 1024x1024")
        check(icon.mode == "RGB", "iOS icon must not have alpha")
    for name in re.findall(r'location: "([a-z-]+\.wav)"', (ROOT/"Blusic/LibraryStore.swift").read_text(encoding="utf-8")):
        path = ROOT/"Blusic/Audio"/name
        check(path in resources, f"Audio not copied into bundle: {name}")
        with wave.open(str(path), "rb") as file:
            check(file.getnchannels() == 2, f"Not stereo: {name}")
            check(file.getframerate() == 44100, f"Wrong sample rate: {name}")
            check(abs(file.getnframes()/file.getframerate()-48) < .01, f"Wrong duration: {name}")
            pcm = array.array("h", file.readframes(file.getnframes()))
            peak = max(abs(x) for x in pcm)
            rms = math.sqrt(sum(x*x for x in pcm)/len(pcm))
            check(1000 < peak < 32767, f"Silent or clipped audio: {name}")
            check(rms > 100, f"Audio RMS too low: {name}")
            print(f"Audio checked: {name}, 48s stereo, peak={peak}, RMS={rms:.0f}")
    if errors:
        for error in errors:
            print("FAIL:", error)
        return 1
    print("PASS: static checks and resources. Xcode compilation and device QA still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
