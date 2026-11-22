#!/bin/bash
# csARM — assemble an APK from LOCALLY built libraries and install it.
#
#   usage: test/local_apk.sh [abi] [install]
#          (needs out/*.so from test/local_build.sh + build_main.sh,
#           thirdparty/gl4es-<abi>/ from build/setup_gl4es.sh,
#           android/libs-swiftshader/<abi>/ from the swiftshader job/artifact)
#   env:   ANDROID_HOME, ANDROID_NDK_HOME/ANDROID_NDK_LATEST_HOME, JAVA_HOME
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI=${1:-x86_64}
DO_INSTALL=${2:-install}
SDK=${ANDROID_HOME:-$HOME/android-sdk}
NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}}
export ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK ANDROID_NDK_HOME=$NDK
export PATH="${JAVA_HOME:-$HOME/jdk-17.0.12+7}/bin:$PATH"
cd "$R"

[ -d out ] || { echo "no out/ — run test/local_build.sh first"; exit 1; }
mkdir -p "android/libs/$ABI"
rm -f "android/libs/$ABI"/*.so
cp out/*.so "android/libs/$ABI/"
# libmain.so comes from build_main.sh (also into out/); libc++_shared is added
# by build_apk.sh from the NDK sysroot.
[ -f "thirdparty/gl4es-$ABI/libGL.so" ] || { echo "no gl4es build; run build/setup_gl4es.sh"; exit 1; }
mkdir -p "android/libs-gl4es/$ABI"
cp "thirdparty/gl4es-$ABI"/lib*.so "android/libs-gl4es/$ABI/"

OUT="android/out-local-$ABI"
mkdir -p "$OUT"
CSARM_OUT="$PWD/$OUT" bash android/build_apk.sh "$ABI" swiftshader | tail -2
if [ "$DO_INSTALL" = "install" ]; then
  ADB=${ADB:-$SDK/platform-tools/adb}
  "$ADB" -s "${DEV:-emulator-5554}" install -r -t "$OUT/csARM.apk" | tail -1
fi
