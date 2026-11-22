#!/bin/bash
# csARM — local map-load probe (the same thing CI's "Map-load probe" step does,
# but runnable on a developer box against a booted emulator).
#
#   usage: test/local_probe.sh [map]        (default: ar_dizzy, else first .bsp)
#   env:   ABI=x86_64 ADB=/path/to/adb APP=com.csarm.port WAIT=700
#
# It reuses the APK already installed on the device and the cstrike content
# already staged in the app sandbox (see test/local_stage.sh), pushes
# files/csarm.args, relaunches CSARMActivity and prints a verdict.
set -uo pipefail
A="${ADB:-$ANDROID_HOME/platform-tools/adb}"
DEV=${DEV:-emulator-5554}
APP=${APP:-com.csarm.port}
WAIT=${WAIT:-700}
WANT="${1:-}"
OUT=${OUT:-$PWD/.local/probe}
mkdir -p "$OUT"
ADB() { "$A" -s "$DEV" "$@"; }

ADB root >/dev/null 2>&1 || true
sleep 2; ADB wait-for-device

MAPS=$(ADB shell "ls -s /data/data/$APP/files/cstrike/maps/*.bsp" 2>/dev/null | tr -d '\r')
[ -n "${MAPS// }" ] || MAPS=$(ADB shell run-as "$APP" sh -c "ls -s files/cstrike/maps/*.bsp" 2>/dev/null | tr -d '\r')
echo "bsp files on device: $(printf '%s\n' "$MAPS" | grep -c '\.bsp')"
if [ -z "${MAPS// }" ]; then
  echo "no .bsp staged — run test/local_stage.sh first"
  exit 1
fi
MAP="$WANT"
if [ -z "$MAP" ]; then
  for want in ar_dizzy ar_baggage de_lake de_dust2; do
    printf '%s\n' "$MAPS" | grep -q "/${want}\.bsp" && { MAP=$want; break; }
  done
fi
[ -n "$MAP" ] || MAP=$(printf '%s\n' "$MAPS" | awk '/bsp$/{print $2}' | sed 's|.*/||;s|\.bsp$||' | sort | head -1)
echo "probe map: $MAP"

cat > "$OUT/probe.args" <<EOF
-novid -windowed -w 1280 -h 720 -nobreakpad -nojoy -no_scaleform_menu_on_boot
-basedir /data/data/$APP/files -game cstrike
+host_thread_mode 2 +mat_queue_mode 2 +cl_threaded_bone_setup 1
+developer 1
+net_showudp_oob 1
+con_logfile console.log
+sv_lan 1 +map $MAP
EOF
ADB push "$OUT/probe.args" /data/local/tmp/csarm_probe.args >/dev/null
ADB shell "cp /data/local/tmp/csarm_probe.args /data/data/$APP/files/csarm.args && rm /data/local/tmp/csarm_probe.args" \
  || ADB shell run-as "$APP" sh -c 'cp /data/local/tmp/csarm_probe.args files/csarm.args && rm /data/local/tmp/csarm_probe.args'
APPUID=$(ADB shell dumpsys package "$APP" | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r')
[ -n "$APPUID" ] && ADB shell "chown $APPUID:$APPUID /data/data/$APP/files/csarm.args && chmod 644 /data/data/$APP/files/csarm.args && restorecon /data/data/$APP/files/csarm.args" >/dev/null 2>&1 || true

ADB shell "ls /data/app/*/$APP-*/lib/*/libEGLgl4es.so" 2>/dev/null | grep -q libEGLgl4es.so \
  || echo "::warning::libEGLgl4es.so missing from the installed APK — real renderer will not start"

ADB shell am force-stop "$APP" || true
sleep 2
ADB logcat -c || true
ADB shell rm -f "/data/data/$APP/files/cstrike/console.log" 2>/dev/null || true
ADB shell am start -n "$APP/.CSARMActivity" >/dev/null || true

LOG="$OUT/logcat_map.txt"
START=$SECONDS; LAUNCH_S=""; PROGRESS=0
while [ $((SECONDS - START)) -lt "$WAIT" ]; do
  ADB logcat -d > "$LOG" 2>/dev/null || true
  if grep -qa "CSARM_MAIN_FAIL" "$LOG"; then echo "MAIN_FAIL at t=$((SECONDS-START))s"; break; fi
  # the process needs a moment to even exist: only trust pidof after the
  # launcher reported itself (same rule as the CI probe)
  if [ -z "$LAUNCH_S" ] && grep -qa "CSARM_LAUNCHER_CALL" "$LOG"; then
    LAUNCH_S=$SECONDS; echo "LauncherMain at t=$((SECONDS-START))s"
  fi
  ADB shell "cat /data/data/$APP/files/cstrike/console.log" > "$OUT/console_live.txt" 2>/dev/null || true
  if [ "$PROGRESS" = "0" ] && grep -qaE "Host_NewGame|Loading map|Spawning server|LevelAllowsPVS|CGameClient|FULLY CONNECTED" "$OUT/console_live.txt" "$LOG" 2>/dev/null; then
    PROGRESS=1; echo "map progress at t=$((SECONDS-START))s"
  fi
  if grep -qa "Fatal signal" "$LOG"; then echo "tombstone at t=$((SECONDS-START))s"; sleep 2; ADB logcat -d > "$LOG"; break; fi
  if [ -n "$LAUNCH_S" ] && ! ADB shell pidof "$APP" >/dev/null 2>&1; then
    echo "process gone after LauncherMain at t=$((SECONDS-START))s"; sleep 1; ADB logcat -d > "$LOG"; break
  fi
  sleep 3
done

ADB logcat -d > "$LOG" 2>/dev/null || true
ADB shell "cat /data/data/$APP/files/cstrike/console.log" > "$OUT/console.log" 2>/dev/null || true
echo "=================== verdict ==================="
echo "csarm args:"
ADB shell "cat /data/data/$APP/files/csarm.args" || true
echo "--- exit/err markers ---"
grep -aE "CSARM_EXIT_HIT|CSARM_MAIN_FAIL|Fatal signal|Sys_Error|unable to load version" "$LOG" | head -5
echo "--- engine errors ---"
grep -aE "Fatal signal|SIGSEGV|SIGABRT|CSARM_MAIN_FAIL|Error!|Sys_Error|overflow" "$LOG" | head -20
echo "--- backtrace ---"
grep -aE "#0[0-9] pc |>>> $APP" "$LOG" | head -12
echo "--- map markers ---"
grep -acE "Host_NewGame|Loading map|Spawning server" "$OUT/console.log" "$LOG" 2>/dev/null
echo "--- console.log tail ---"
tail -25 "$OUT/console.log" 2>/dev/null
echo "logs: $OUT/"
