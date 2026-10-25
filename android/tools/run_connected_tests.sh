#!/usr/bin/env bash
# The emulator action executes each script line in its own shell. Keep cleanup
# and the test exit status together here so failed network tests retain evidence.
set +e
gradle --no-daemon :app:connectedDebugAndroidTest
result=$?
adb pull /sdcard/Android/data/app.blusic.android/files/screenshots app/build/screenshots
adb logcat -d > app/build/logcat.txt
exit "$result"
