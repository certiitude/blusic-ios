#!/usr/bin/env bash
# The emulator action executes each script line in its own shell. Keep cleanup
# and the test exit status together here so failed network tests retain evidence.
set +e
gradle --no-daemon :app:connectedDebugAndroidTest
result=$?
adb pull /data/local/tmp/blusic-screenshots app/build/screenshots
capture_result=$?
adb logcat -d > app/build/logcat.txt
if [ "$result" -eq 0 ] && [ "$capture_result" -ne 0 ]; then exit "$capture_result"; fi
python3 tools/check_screenshots.py
image_result=$?
if [ "$result" -eq 0 ] && [ "$image_result" -ne 0 ]; then exit "$image_result"; fi
exit "$result"
