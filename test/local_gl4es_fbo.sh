#!/bin/bash
# csARM — on-device regression test for the gl4es framebuffer-deletion crash.
#
#   test/gl4es_fbo_delete.c reproduces the exact engine sequence
#   (bind render-target FBO -> delete it while bound -> SetViewport):
#
#     libGL.so glViewport+35        <- SIGSEGV at 0x0 before the fix
#     libtogl.so IDirect3DDevice9::SetViewport
#     libshaderapidx9.so CommitSetViewports
#     libshaderapidx9.so ClearBuffers
#     libmaterialsystem.so CTexture::ReconstructTexture
#
# Upstream gl4es NULLs glstate->fbo.current_fb when the bound FBO is deleted;
# patches/gl4es/0001-fbo-delete-rebind-default.patch restores the default
# framebuffer instead.  Runs in ~2s, no game content, no window -> cheap
# enough to gate every CI boot job.
#
#   usage: NDKROOT=/path/to/ndk test/local_gl4es_fbo.sh [gl4es-dir] [swiftshader-dir]
#   env:   ADB, DEV, ABI=x86_64, PJ=/data/local/tmp/gl4es-fbo
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GL4ES=${1:-$R/thirdparty/gl4es-x86_64}
SW=${2:-$R/android/libs-swiftshader/x86_64}
NDKROOT=${NDKROOT:?NDKROOT must be set}
ABI=${ABI:-x86_64}
ADB=${ADB:-${ANDROID_HOME:-$HOME/android-sdk}/platform-tools/adb}
DEV=${DEV:-emulator-5554}
PJ=${PJ:-/data/local/tmp/gl4es-fbo}
CC="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/${ABI/x86_64/x86_64}-linux-android24-clang"
[ "$ABI" = "arm64-v8a" ] && CC="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
ADB() { "$ADB" -s "$DEV" "$@"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$CC" -O1 -w -o "$tmp/gl4es_fbo_delete" "$R/test/gl4es_fbo_delete.c" -ldl || exit 1
cp "$GL4ES/libGL.so" "$tmp/libGL.so"
cp "$GL4ES/libGL.so" "$tmp/libGL.so.1"        # gl4es SONAME needed by the EGL wrapper
cp "$GL4ES/libEGLgl4es.so" "$tmp/libEGLgl4es.so"
cp "$SW/libEGL.so" "$tmp/libEGL.so"
cp "$SW/libGLESv2.so" "$tmp/libGLESv2.so"

ADB shell "rm -rf $PJ && mkdir -p $PJ" || exit 1
for f in gl4es_fbo_delete libGL.so libGL.so.1 libEGLgl4es.so libEGL.so libGLESv2.so; do
  ADB push "$tmp/$f" "$PJ/$f" >/dev/null || { echo "push $f failed"; exit 1; }
done
ADB shell "chmod -R 755 $PJ"

out=$(ADB shell "cd $PJ && LIBGL_EGL=$PJ/libEGL.so LIBGL_GLES=$PJ/libGLESv2.so ./gl4es_fbo_delete . 2>&1")
rc=$?
echo "$out" | tail -6
if [ $rc -eq 0 ] && echo "$out" | grep -q "^PASS: glViewport after deleting the bound FBO"; then
  echo "OK: gl4es survives deleting the bound framebuffer"
  exit 0
fi
echo "FAIL: gl4es crashed/failed on the bound-FBO deletion path (rc=$rc)"
ADB logcat -d 2>/dev/null | grep -aA6 "Fatal signal" | tail -12
exit 1
