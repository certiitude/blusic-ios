"""Package the source project and its original media, not an installable IPA."""
from pathlib import Path
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {"dist", "build", "DerivedData", ".git", ".venv", "__pycache__", "xcuserdata"}


def main():
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    destination = output / "Blusic-iOS-source.zip"
    paths = sorted(p for p in ROOT.rglob("*") if p.is_file() and not any(part in EXCLUDED for part in p.relative_to(ROOT).parts))
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in paths:
            archive.write(path, Path("Blusic") / path.relative_to(ROOT))
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert "Blusic/Blusic.xcodeproj/project.pbxproj" in archive.namelist()
        assert len([name for name in archive.namelist() if name.endswith(".wav")]) == 4
    with destination.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    print(f"Source archive: {destination}")
    print(f"Files: {len(paths)}, bytes: {destination.stat().st_size}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
