#!/bin/bash
# csARM — local "engine boot" smoke test (CI: step "Engine boot test").
#
#   test/local_boot.sh [seconds]
#
# Launches CSARMActivity with the default (noshaderapi) argument set and checks
# the same markers CI checks: CSARM_LAUNCHER_CALL reached, no CSARM_MAIN_FAIL,
# no self-exit inside the window.  Prints the exit stack, symbolized, if any.
set -uo pipefail
WAIT=${1:-90}
APP=${APP:-com.csarm.port}
A=${ADB:-${ANDROID_HOME:-$HOME/android-sdk}/platform-tools/adb}
DEV=${DEV:-emulator-5554}
LIBS=${LIBS:-$PWD/android/libs/x86_64}
OUT=${OUT:-$PWD/.local/boot}
ADB() { "$A" -s "$DEV" "$@"; }
mkdir -p "$OUT"

ADB root >/dev/null 2>&1 || true; sleep 2; ADB wait-for-device
ADB shell "rm -f /data/data/$APP/files/csarm.args" 2>/dev/null
ADB shell am force-stop "$APP"
ADB logcat -c
ADB shell am start -n "$APP/.CSARMActivity" >/dev/null

LOG="$OUT/logcat_boot.txt"; START=$SECONDS; SAW=0
while [ $((SECONDS - START)) -lt "$WAIT" ]; do
  ADB logcat -d > "$LOG" 2>/dev/null || true
  grep -qa "CSARM_LAUNCHER_CALL" "$LOG" && SAW=$((SECONDS - START))
  grep -qaE "CSARM_MAIN_FAIL|CSARM_MAIN_EXIT|Fatal signal" "$LOG" && break
  sleep 3
done
ADB logcat -d > "$LOG" 2>/dev/null || true

echo "--- args ---";             grep -a "CSARM_ARGS " "$LOG" | head -1
echo "--- launcher ---";         grep -a "CSARM_LAUNCHER_CALL" "$LOG" | head -2
echo "--- failures ---";         grep -aE "CSARM_MAIN_FAIL|CSARM_EXIT_HIT|Fatal signal|overflow|Sys_Error" "$LOG" | head -10
if grep -qa "CSARM_EXIT_HIT\|Fatal signal" "$LOG"; then
  echo "--- frames ---"
  bash "$(dirname "$0")/symbolize.sh" "$LIBS" "$LOG" | head -15
fi
echo "--- verdict ---"
if ! grep -qa "CSARM_LAUNCHER_CALL" "$LOG"; then echo "FAIL: LauncherMain never called"; exit 1; fi
if grep -qa "CSARM_MAIN_FAIL" "$LOG"; then echo "FAIL: CSARM_MAIN_FAIL"; exit 1; fi
if grep -qa "CSARM_EXIT_HIT" "$LOG"; then echo "FAIL: engine self-exited inside the boot window"; exit 1; fi
if grep -qa "Fatal signal" "$LOG"; then echo "FAIL: tombstone"; exit 1; fi
echo "OK: LauncherMain reached at +${SAW}s, no crash inside ${WAIT}s (full log: $LOG)"
