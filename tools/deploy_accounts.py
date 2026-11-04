"""Deploy only the optional Soryn account service, on the authorized free plan.

Credentials stay in the private deployment file, outside the repository.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(r"C:\Users\elome\AppData\Local\Temp\opencode")
PRIVATE = ROOT / "soryn-accounts-deployment-private.json"


def main():
    private = json.loads(PRIVATE.read_text(encoding="utf-8"))
    assert private.get("databaseURL"), "Persistent database must be configured first"
    env = {**os.environ, "RENDER_CLI_DISABLE_ANALYTICS": "1", "RENDER_CLI_CONFIG_DIR": str(ROOT / "blusic-render-config")}
    cli = str(ROOT / "blusic-render-2.31.0" / "render.exe")

    def run(args):
        result = subprocess.run([cli, *args, "--output", "json", "--confirm"], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode:
            text = result.stderr + result.stdout
            for value in [private.get("supabasePassword"), private.get("databaseURL")]:
                if value:
                    text = text.replace(value, "[redacted]")
            raise RuntimeError(text)
        return json.loads(result.stdout)

    existing = run(["services"])
    matches = [item.get("service", item) for item in existing if item.get("service", item).get("name") == "soryn-accounts"]
    if matches:
        service = matches[0]
    else:
        result = run(["services", "create", "--name", "soryn-accounts", "--type", "web_service", "--plan", "free",
                      "--region", "frankfurt", "--repo", "https://github.com/certiitude/blusic-ios", "--branch", "main",
                      "--runtime", "node", "--build-command", "npm --prefix account-server ci --omit=dev --ignore-scripts --no-audit --no-fund",
                      "--start-command", "node account-server/server.mjs", "--health-check-path", "/health", "--auto-deploy=false",
                      "--env-var", "DATABASE_URL=" + private["databaseURL"], "--env-var", "TRUST_PROXY=1", "--env-var", "NODE_VERSION=22"])
        service = result.get("service", result)
    assert service.get("serviceDetails", {}).get("plan") == "free", "Never enable a paid plan"
    private["serviceId"] = service["id"]
    private["serviceURL"] = service.get("serviceDetails", {}).get("url")
    PRIVATE.write_text(json.dumps(private), encoding="utf-8")
    print(json.dumps({"id": private["serviceId"], "url": private["serviceURL"], "plan": "free", "alreadyCreated": bool(matches)}))


if __name__ == "__main__":
    main()
