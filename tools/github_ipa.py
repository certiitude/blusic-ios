"""Drive the real Xcode GitHub Actions build from Windows using official GitHub CLI.

This utility does not create a repository, commit, or push code. It only sets up
GitHub CLI, signs in on request, and builds the code already on GitHub.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import urllib.request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.103.0"
CLI_SHA256 = "80c846a5b8432672ca6373b34ce9de998c9686aaa1885c845f2e1ee81f713726"
ARTIFACT = "Blusic-iPhone-unsigned-needs-signing"


def cli_directory() -> Path:
    return Path(os.environ.get("TEMP", str(Path.home()))) / "opencode" / "blusic-tools" / f"gh-{VERSION}"


def ensure_gh() -> str:
    installed = shutil.which("gh")
    if installed:
        return installed
    if sys.platform != "win32" or platform.machine().lower() not in {"amd64", "x86_64"}:
        raise RuntimeError("Installe GitHub CLI depuis https://cli.github.com puis relance cette commande.")
    folder = cli_directory()
    executable = folder / "bin" / "gh.exe"
    if executable.is_file():
        return str(executable)
    print("Téléchargement de GitHub CLI officiel (portable, sans installation système)...", flush=True)
    url = f"https://github.com/cli/cli/releases/download/v{VERSION}/gh_{VERSION}_windows_amd64.zip"
    request = urllib.request.Request(url, headers={"User-Agent": "Blusic-build-helper/1.0"})
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read(50_000_000)
    if hashlib.sha256(data).hexdigest() != CLI_SHA256:
        raise RuntimeError("Le SHA-256 du téléchargement GitHub CLI ne correspond pas à la version officielle attendue.")
    import io
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for entry in archive.infolist():
            parts = Path(entry.filename).parts
            if entry.filename.startswith(("/", "\\")) or ".." in parts:
                raise RuntimeError("Chemin inattendu dans l’archive GitHub CLI.")
        folder.mkdir(parents=True, exist_ok=True)
        archive.extractall(folder)
    if not executable.is_file():
        raise RuntimeError("L’archive GitHub CLI ne contient pas bin/gh.exe.")
    return str(executable)


def run(gh: str, *arguments: str, capture=False, check=True):
    return subprocess.run([gh, *arguments], cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None, check=check)


def start_login(gh: str, detached: bool):
    if run(gh, "auth", "status", capture=True, check=False).returncode == 0:
        print("Un compte GitHub est déjà connecté.")
        run(gh, "auth", "status")
        return
    arguments = [gh, "auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web", "--scopes", "workflow"]
    if not detached:
        subprocess.run(arguments, cwd=ROOT, check=True)
        return
    # Let the browser login finish while the coding agent keeps preparing the build.
    log = cli_directory().parent / "github-login.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("wb") as output:
        process = subprocess.Popen(arguments, cwd=ROOT, stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS)
        try:
            process.stdin.write(b"\n")
            process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
    print(f"Connexion démarrée (PID {process.pid}). Lis le code dans : {log}")


def build(gh: str, repo: str | None, branch: str):
    run(gh, "auth", "status")
    if not repo:
        repo = run(gh, "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", capture=True).stdout.strip()
    request_id = uuid.uuid4().hex
    print(f"Demande de compilation : {request_id}", flush=True)
    run(gh, "workflow", "run", "ios.yml", "--repo", repo, "--ref", branch, "-f", f"request_id={request_id}")
    run_id = None
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        result = run(gh, "run", "list", "--repo", repo, "--workflow", "ios.yml", "--branch", branch,
                     "--event", "workflow_dispatch", "--limit", "30", "--json", "databaseId,displayTitle,url", capture=True)
        for item in json.loads(result.stdout):
            if request_id in item["displayTitle"]:
                run_id = item["databaseId"]
                print(item["url"], flush=True)
                break
        if run_id:
            break
        time.sleep(4)
    if not run_id:
        raise RuntimeError("La demande a été envoyée, mais l’exécution n’est pas encore visible. Vérifie l’onglet Actions du dépôt.")
    watched = run(gh, "run", "watch", str(run_id), "--repo", repo, "--exit-status", check=False)
    folder = ROOT / "dist" / "github" / str(run_id)
    folder.mkdir(parents=True, exist_ok=True)
    downloaded = run(gh, "run", "download", str(run_id), "--repo", repo, "--name", ARTIFACT, "--dir", str(folder), check=False)
    if downloaded.returncode:
        run(gh, "run", "view", str(run_id), "--repo", repo, "--log-failed", check=False)
        raise RuntimeError("La compilation n’a pas produit d’IPA. Les erreurs Xcode sont affichées ci-dessus.")
    ipa = folder / "Blusic-unsigned.ipa"
    subprocess.run([sys.executable, str(ROOT / "tools" / "verify_ipa.py"), str(ipa)], cwd=ROOT, check=True)
    print(f"IPA compilée récupérée : {ipa}")
    print("Signature requise avant installation, par exemple avec AltStore Classic sous Windows.")
    if watched.returncode:
        print("ATTENTION : l’IPA existe, mais les tests ou une autre étape ont échoué. Consulte le rapport Actions avant usage.")
        return 2
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="Télécharger la CLI officielle portable si nécessaire")
    commands.add_parser("status", help="Voir si GitHub est connecté (sans afficher le jeton)")
    login = commands.add_parser("login", help="Connexion via le navigateur GitHub")
    login.add_argument("--detached", action="store_true", help="Laisser la connexion continuer en arrière-plan")
    compile_ = commands.add_parser("build", help="Compiler le code déjà présent dans un dépôt GitHub")
    compile_.add_argument("--repo", help="proprietaire/depot ; détecté depuis Git si omis")
    compile_.add_argument("--branch", default="main")
    args = parser.parse_args()
    gh = ensure_gh()
    if args.command == "setup":
        print(gh)
        run(gh, "--version")
    elif args.command == "status":
        return run(gh, "auth", "status", check=False).returncode
    elif args.command == "login":
        start_login(gh, args.detached)
    else:
        return build(gh, args.repo, args.branch)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(f"Erreur : {error}", file=sys.stderr)
        sys.exit(1)
