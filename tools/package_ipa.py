"""Package the actual Xcode-built .app as an unsigned IPA on a macOS runner."""
from pathlib import Path
import argparse
import hashlib
import sys
import zipfile

from verify_ipa import validate_ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.app.is_dir() or args.app.suffix != ".app":
        raise ValueError(f"Application Xcode compilée introuvable : {args.app}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(args.app.rglob("*")):
            if path.is_file():
                archive.write(path, Path("Payload") / args.app.name / path.relative_to(args.app))
    report = validate_ipa(args.output)
    with args.output.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    print(f"IPA créée : {args.output} ({report['size']} octets), {report['architecture']}, {report['platform']}")
    print(f"SHA-256 : {digest}")
    print("Paquet non signé : une signature de sideload est requise pour l’installation.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print(f"Packaging impossible : {error}", file=sys.stderr)
        sys.exit(1)
