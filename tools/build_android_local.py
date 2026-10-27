"""Build the Android APK locally with the isolated tools, without printing access."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TEMP = Path(r"C:\Users\elome\AppData\Local\Temp\opencode")
TOOLS = TEMP / "blusic-android-tools"


def main():
    env = os.environ.copy()
    env.update(JAVA_HOME=str(TOOLS / "jdk"), ANDROID_HOME=str(TOOLS / "sdk"), ANDROID_SDK_ROOT=str(TOOLS / "sdk"),
               GRADLE_USER_HOME=str(TOOLS / "gradle-home"), NODE_OPTIONS="--use-system-ca")
    env["PATH"] = str(TOOLS / "jdk/bin") + os.pathsep + str(TEMP / "blusic-node/node-v22.23.4-win-x64") + os.pathsep + env["PATH"]
    node = str(TEMP / "blusic-node/node-v22.23.4-win-x64/node.exe")
    subprocess.run([node, "build.mjs"], cwd=ROOT / "native-resolver", env=env, check=True)
    assets = ROOT / "android/app/src/main/assets"
    assets.mkdir(parents=True, exist_ok=True)
    for filename in ["YouTubeiResolver.js", "ThirdPartyResolverLicenses.txt"]:
        shutil.copyfile(ROOT / "Blusic" / filename, assets / filename)
    private = json.loads((TEMP / "blusic-relay-deployment-private.json").read_text(encoding="utf-8"))
    env["BLUSIC_ANDROID_RELAY_ACCESS"] = "app.android." + hmac.new(private["key"].encode(), b"application:android|v1", hashlib.sha256).hexdigest()
    subprocess.run(["python", "tools/configure_relay.py"], cwd=ROOT / "android", env=env, check=True)
    env.pop("BLUSIC_ANDROID_RELAY_ACCESS")
    subprocess.run([str(TOOLS / "gradle-8.11.1/bin/gradle.bat"), "--no-daemon", ":app:assembleDebug", ":app:testDebugUnitTest", ":app:lintDebug", ":app:assembleDebugAndroidTest"],
                   cwd=ROOT / "android", env=env, check=True)
    sdk = TOOLS / "sdk/build-tools/35.0.0"
    apk = ROOT / "android/app/build/outputs/apk/debug/app-debug.apk"
    subprocess.run([str(sdk / "apksigner.bat"), "verify", "--verbose", str(apk)], env=env, check=True)
    subprocess.run(["python", "tools/verify_apk.py", str(apk)], cwd=ROOT, env=env, check=True)
    target = ROOT / "dist/local/android-1.9.2"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(apk, target / "Blusic-1.9.2.apk")
    print("Local APK ready: " + str(target / "Blusic-1.9.2.apk"))


if __name__ == "__main__":
    main()
