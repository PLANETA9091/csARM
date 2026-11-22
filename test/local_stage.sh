#!/bin/bash
# csARM — stage game content into the installed app's private sandbox.
#
#   test/local_stage.sh <content-root>      # a dir that contains cstrike/
#
# Mirrors the CI "part 0" staging: adb root (aosp_atd is userdebug) so the
# depot is pushed straight into /data/data/<app>/files — one copy, no
# /data/local/tmp doubling.  Falls back to run-as for non-root images.
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <content-root-with-cstrike>"; exit 2; }
SRC=${1%/}
APP=${APP:-com.csarm.port}
A=${ADB:-${ANDROID_HOME:-$HOME/android-sdk}/platform-tools/adb}
DEV=${DEV:-emulator-5554}
ADB() { "$A" -s "$DEV" "$@"; }

[ -d "$SRC/cstrike" ] || { echo "no $SRC/cstrike — pass the dir that contains it"; exit 1; }
# CS:GO keeps steam.inf inside the VPK set; the engine's Sys_Version() hard
# errors without it when the paks are not staged.  A minimal 5-key file is
# enough for the probe (the depot ships the same keys).
if [ ! -f "$SRC/cstrike/steam.inf" ]; then
  # NOTE the exact format: KEY=VALUE lines, no quotes/KeyValues — the engine
  # matches "PatchVersion=", "ClientVersion=", "ServerVersion=",
  # "ProductName=", "AppID=" and demands all five (sys_dll2.cpp:2172).
  cat > "$SRC/cstrike/steam.inf" <<'INF'
PatchVersion=1.38.7.3
ProductName=Counter-Strike: Global Offensive
appID=730
ClientVersion=2000258
ServerVersion=2000258
INF
  echo "wrote minimal cstrike/steam.inf (engine Sys_Version needs it)"
fi

ADB root >/dev/null 2>&1 || true
sleep 3; ADB wait-for-device
T0=$SECONDS
if ADB shell id 2>/dev/null | grep -q uid=0; then
  echo "adb root OK — pushing into the app sandbox"
  ADB shell "mkdir -p /data/data/$APP/files"
  ADB push "$SRC/cstrike" "/data/data/$APP/files/cstrike" | tail -1
  [ -d "$SRC/platform" ] && ADB push "$SRC/platform" "/data/data/$APP/files/cstrike/platform" | tail -1
  UID_=$(ADB shell dumpsys package "$APP" | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r')
  [ -n "$UID_" ] && ADB shell "chown -R $UID_:$UID_ /data/data/$APP/files/cstrike"
  ADB shell restorecon -R /data/data/$APP/files/cstrike >/dev/null 2>&1 || true
else
  echo "no adb root — run-as staging (small packs only)"
  ADB shell "rm -rf /data/local/tmp/csarm_a"
  ADB push "$SRC" /data/local/tmp/csarm_a | tail -1
  ADB shell "run-as $APP sh -c 'mkdir -p files/cstrike && cp -r /data/local/tmp/csarm_a/cstrike/. files/cstrike/'" || exit 1
  ADB shell "rm -rf /data/local/tmp/csarm_a"
fi
echo "staged in $((SECONDS - T0))s:"
ADB shell "ls /data/data/$APP/files/cstrike | head -15"
