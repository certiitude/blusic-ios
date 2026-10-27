"""Run the actual Android instrumentation suite with the isolated emulator."""
import os
from pathlib import Path
import subprocess
import time
import shutil

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(r"C:\Users\elome\AppData\Local\Temp\opencode\blusic-android-tools")


def main():
    env = os.environ.copy()
    env.update(JAVA_HOME=str(TOOLS / "jdk"), ANDROID_HOME=str(TOOLS / "sdk"), ANDROID_SDK_ROOT=str(TOOLS / "sdk"),
               ANDROID_AVD_HOME=str(TOOLS / "avd"), GRADLE_USER_HOME=str(TOOLS / "gradle-home"))
    env["PATH"] = str(TOOLS / "jdk/bin") + os.pathsep + str(TOOLS / "sdk/platform-tools") + os.pathsep + env["PATH"]
    (TOOLS / "avd").mkdir(exist_ok=True)
    name = "blusic-local-35"
    if not (TOOLS / "avd" / (name + ".ini")).exists():
        subprocess.run([str(TOOLS / "sdk/cmdline-tools/latest/bin/avdmanager.bat"), "create", "avd", "-n", name,
                        "-k", "system-images;android-35;google_apis;x86_64", "--device", "pixel_6"], input="no\n", text=True, env=env, check=True)
    evidence = ROOT / "dist/tests/android-local-1.9.2"
    evidence.mkdir(parents=True, exist_ok=True)
    adb = str(TOOLS / "sdk/platform-tools/adb.exe")
    subprocess.run([adb, "start-server"], env=env, check=True)
    log = (evidence / "emulator.log").open("w", encoding="utf-8")
    emulator = subprocess.Popen([str(TOOLS / "sdk/emulator/emulator.exe"), "-avd", name, "-port", "5556", "-no-window", "-gpu", "swiftshader_indirect", "-no-snapshot", "-noaudio", "-no-boot-anim", "-camera-back", "none", "-memory", "2048"], env=env, stdout=log, stderr=subprocess.STDOUT)
    def device(*args, **kwargs):
        return subprocess.run([adb, "-s", "emulator-5556", *args], env=env, **kwargs)
    result = 1
    try:
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if emulator.poll() is not None:
                raise RuntimeError("Local emulator exited; inspect " + str(evidence / "emulator.log"))
            status = device("shell", "getprop", "sys.boot_completed", capture_output=True, text=True, timeout=15)
            if status.stdout.strip() == "1":
                break
            time.sleep(3)
        else:
            raise TimeoutError("Local emulator did not finish booting in five minutes")
        print("Local Android 15 emulator booted", flush=True)
        device("shell", "input", "keyevent", "82", check=True)
        for key in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]:
            device("shell", "settings", "put", "global", key, "0", check=True)
        result = subprocess.run([str(TOOLS / "gradle-8.11.1/bin/gradle.bat"), "--no-daemon", ":app:connectedDebugAndroidTest"], cwd=ROOT / "android", env=env).returncode
    finally:
        device("pull", "/data/local/tmp/blusic-screenshots", str(evidence / "screenshots"), timeout=60)
        with (evidence / "logcat.txt").open("w", encoding="utf-8") as output:
            device("logcat", "-d", stdout=output, timeout=30)
        for source, target in [("outputs/androidTest-results", "androidTest-results"), ("test-results", "test-results"), ("reports", "reports")]:
            folder = ROOT / "android/app/build" / source
            if folder.exists():
                shutil.copytree(folder, evidence / target, dirs_exist_ok=True)
        device("emu", "kill", timeout=20)
        try:
            emulator.wait(timeout=25)
        except subprocess.TimeoutExpired:
            emulator.terminate()
        log.close()
    raise SystemExit(result)


if __name__ == "__main__":
    main()
