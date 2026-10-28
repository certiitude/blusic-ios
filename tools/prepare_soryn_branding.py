"""Export the creator's Soryn logo without renaming app storage or bundle IDs."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--logo", type=Path, required=True)
    args = parser.parse_args()
    image = Image.open(args.logo).convert("RGB")
    icon = ImageOps.fit(image, (1024, 1024), method=Image.Resampling.LANCZOS)
    branding = ROOT / "docs/branding"
    branding.mkdir(parents=True, exist_ok=True)
    icon.save(branding / "soryn-icon.png", optimize=True)
    icon.save(branding / "soryn.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    icon.save(ROOT / "Blusic/Assets.xcassets/AppIcon.appiconset/AppIcon.png", optimize=True)
    folder = ROOT / "Blusic/Assets.xcassets/SorynLogo.imageset"
    folder.mkdir(exist_ok=True)
    icon.save(folder / "SorynLogo.png", optimize=True)
    (folder / "Contents.json").write_text(json.dumps({"images": [{"filename": "SorynLogo.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    android = ROOT / "android/app/src/main/res/drawable-nodpi"
    android.mkdir(parents=True, exist_ok=True)
    icon.save(android / "blusic_icon.png", optimize=True)
    print("Soryn logo exported: opaque iOS icon, in-app artwork, Windows ICO, Android icon.")


if __name__ == "__main__":
    main()
