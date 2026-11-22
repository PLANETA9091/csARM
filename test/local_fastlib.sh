#!/bin/bash
# csARM — fastest code->device loop (seconds, not minutes):
#   recompile one module, relink ONLY that library, push it into the installed
#   APK's native lib dir (adb root) and restart the activity.  No APK rebuild,
#   no install, no emulator restart.
#
#   usage: NDKROOT=... test/local_fastlib.sh <module.vpc|lists/x.txt> <lib.so> [map]
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE=${1:?module (engine/engine.vpc | lists/togl.txt ...)}
LIB=${2:?library to relink, e.g. libengine.so}
MAP=${3:-ar_dizzy}
NDKROOT=${NDKROOT:?}
export NDKROOT
CC=x86_64-linux-android24-clang; export CC JOBS=${JOBS:-8} OPT=${OPT:--O2} LTO=${LTO:-1}
export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
A=${ADB:-${ANDROID_HOME:-$HOME/android-sdk}/platform-tools/adb}
DEV=${DEV:-emulator-5554}
cd "$R"

t0=$SECONDS
case "$MODULE" in
  *client_cstrike15*) export DEFX="DCLIENT_DLL=1 DCSTRIKE_CLIENT_DLL=1 DCSTRIKE_DLL=1 DCSTRIKE15=1 DGAMEUI_EMBEDDED=1 DGAMEUI_EXPORTS=1 DVERSION_SAFE_STEAM_API_INTERFACES=1 DUSE_ECONOMY_FEATURES=1" ;;
  *server_cstrike15*) export DEFX="DGAME_DLL=1 DCSTRIKE_DLL=1 DCSTRIKE15=1 DVERSION_SAFE_STEAM_API_INTERFACES=1 DPROTECTED_THINGS_ENABLE=1" ;;
  *) unset DEFX || true ;;
esac
bash build/trybuild.sh "$MODULE" | tail -1
QUICK_LIB="$LIB" CC=x86_64-linux-android27-clang bash build/link.sh >/dev/null 2>&1
echo "[fast] build+link $((SECONDS - t0))s"

LIBDIR=$("$A" -s "$DEV" shell "ls -d /data/app/*/com.csarm.port-*/lib/x86_64 2>/dev/null | head -1" | tr -d '\r')
[ -n "$LIBDIR" ] || { echo "app not installed?"; exit 1; }
"$A" -s "$DEV" root >/dev/null 2>&1 || true
"$A" -s "$DEV" shell "am force-stop com.csarm.port" >/dev/null 2>&1 || true
"$A" -s "$DEV" push "out/$LIB" "$LIBDIR/$LIB" >/dev/null
"$A" -s "$DEV" shell "chmod 644 $LIBDIR/$LIB; chown 1000:1000 $LIBDIR/$LIB; restorecon $LIBDIR/$LIB >/dev/null 2>&1 || true"
echo "[fast] pushed $LIB -> $LIBDIR"

printf '%s\n' "-novid -windowed -w 1280 -h 720 -nobreakpad -nojoy -no_scaleform_menu_on_boot" \
  "-basedir /data/data/com.csarm.port/files -game cstrike" "+developer 1" "+sv_lan 1" "+map $MAP" \
  > /tmp/csarm_fast.args
"$A" -s "$DEV" push /tmp/csarm_fast.args /data/data/com.csarm.port/files/csarm.args >/dev/null
"$A" -s "$DEV" logcat -c
"$A" -s "$DEV" shell "am start -n com.csarm.port/.CSARMActivity" >/dev/null
echo "[fast] launched; total $((SECONDS - t0))s"
