#!/bin/bash
# csARM — build the visual-test APK without gradle:
# aapt2 (manifest) -> javac -> d8 -> zip (dex + lib/arm64-v8a) -> zipalign -> apksigner.
# Input:  android/libs/*.so            (flat; script places them into lib/arm64-v8a/)
#         android/AndroidManifest.xml, android/src/**/*.java
# Output: android/out/csARM.apk  (debug-signed, installable)
set -euo pipefail
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}

[ -d "$SDK" ] || { echo "Android SDK not found at $SDK"; exit 1; }

BT=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1 || true)
[ -n "$BT" ] || { echo "no build-tools; install via sdkmanager"; exit 1; }
PLAT=$(ls -d "$SDK"/platforms/android-*/ 2>/dev/null | sort -t- -k2 -n | tail -1 || true)
if [ -z "$PLAT" ]; then
  yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" "platforms;android-31" >/dev/null
  PLAT=$(ls -d "$SDK"/platforms/android-*/ | sort -t- -k2 -n | tail -1)
fi
AJAR="$PLAT/android.jar"
echo "SDK: build-tools=$BT platform=$PLAT"

OUT="$A/out"; GEN="$A/gen"; CLS="$A/classes"; DEX="$A/dex"
rm -rf "$OUT" "$GEN" "$CLS" "$DEX"; mkdir -p "$OUT" "$GEN" "$CLS" "$DEX"

# 0. SDL2 Java glue: SDLActivity + SDLSurface come from the SAME pinned SDL
#    tarball setup_sdl2.sh compiles (order of loadLibrary calls is untouched —
#    libmain.so carries the JNI entry, so bionic resolves it whenever loaded).
SDLJDIR="$A/src/org/libsdl/app"
if [ ! -f "$SDLJDIR/SDLActivity.java" ]; then
  mkdir -p "$SDLJDIR"
  SDLSRC="$A/../.cache/SDL-2.0.2/android-project/src/org/libsdl/app/SDLActivity.java"
  if [ ! -f "$SDLSRC" ]; then
    mkdir -p /tmp/csarm-sdl && cd /tmp/csarm-sdl
    curl -sfL --retry 3 -o sdl.tgz "https://libsdl.org/release/SDL2-2.0.2.tar.gz" \
      || curl -sfL --retry 3 -o sdl.tgz "https://github.com/libsdl-org/SDL/releases/download/release-2.0.2/SDL2-2.0.2.tar.gz"
    tar xzf sdl.tgz SDL2-2.0.2/android-project/src/org/libsdl/app/SDLActivity.java 2>/dev/null || true
    SDLSRC=/tmp/csarm-sdl/SDL2-2.0.2/android-project/src/org/libsdl/app/SDLActivity.java
  fi
  cp -v "$SDLSRC"* "$SDLJDIR/" || { echo "SDLActivity.java extraction failed"; exit 1; }
fi

# 1. manifest -> apk skeleton + R.java (assets: game content skeleton)
"$BT/aapt2" link -o "$OUT/base.apk" \
  --manifest "$A/AndroidManifest.xml" -I "$AJAR" --java "$GEN" \
  $([ -d "$A/assets" ] && echo "-A $A/assets")

# 2. java -> class (android toolchain way: source/target 1.8 + android.jar bootclasspath)
find "$A/src" "$GEN" -name "*.java" > /tmp/csarm-javac.list
javac -source 1.8 -target 1.8 -nowarn -Xlint:none \
  -bootclasspath "$AJAR" -classpath "$AJAR" \
  -d "$CLS" @/tmp/csarm-javac.list

# 3. class -> dex
find "$CLS" -name "*.class" > /tmp/csarm-d8.list
"$BT/d8" --release --min-api 24 --lib "$AJAR" \
  --output "$DEX" @/tmp/csarm-d8.list

# 4. pack dex + native libs
# usage: build_apk.sh [abi]  — abi: x86_64 (boot-test) | universal (default: all ABIs present)
APKABI=${1:-universal}
cp "$OUT/base.apk" "$OUT/unsigned.apk"
cp "$DEX/classes.dex" "$DEX/classes.dex" 2>/dev/null || true
(cd "$DEX" && zip -q -u "$OUT/unsigned.apk" classes.dex)

# our .so files have DT_NEEDED libc++_shared.so — take it from the NDK sysroot
HOSTTAG=linux-x86_64; [ "$(uname)" = "Darwin" ] && HOSTTAG=darwin-x86_64
for ABI in arm64-v8a x86_64; do
  [ "$APKABI" = "universal" ] || [ "$APKABI" = "$ABI" ] || continue
  if ls "$A"/libs/$ABI/*.so >/dev/null 2>&1; then
    mkdir -p "$A/lib/$ABI"
    cp "$A"/libs/$ABI/*.so "$A/lib/$ABI/"
    # libc++_shared per ABI
    LIBDIRNAME=aarch64-linux-android; [ "$ABI" = "x86_64" ] && LIBDIRNAME=x86_64-linux-android
    if ! ls "$A/lib/$ABI/libc++_shared.so" >/dev/null 2>&1; then
      for cand in "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_HOME:-}" "$SDK/ndk/"*/ ; do
        [ -n "$cand" ] || continue
        f="$cand/toolchains/llvm/prebuilt/$HOSTTAG/sysroot/usr/lib/$LIBDIRNAME/libc++_shared.so"
        if [ -f "$f" ]; then cp "$f" "$A/lib/$ABI/libc++_shared.so"; echo "libc++_shared.so($ABI) from $cand"; break; fi
      done
    fi
    NLIB=$(ls "$A/lib/$ABI"/*.so 2>/dev/null | wc -l)
    echo "native libs [$ABI]: $NLIB"
    [ "$NLIB" -ge 21 ] || { echo "ERROR: expected >=21 native libs for $ABI (20 port libs incl. main/SDL2/launcher/inputsystem + libc++_shared), got $NLIB"; exit 1; }
    (cd "$A" && zip -q -u "$OUT/unsigned.apk" lib/$ABI/*.so)
  else
    echo "no libs for $ABI (skipping; APKABI=$APKABI)"
    [ "$APKABI" = "universal" ] || { echo "ERROR: requested ABI $ABI has no libs"; exit 1; }
  fi
done

# 5. align + sign (debug key)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
KS="$A/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -alias androiddebugkey \
    -storepass android -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android \
  --key-pass pass:android --out "$OUT/csARM.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT/csARM.apk" | head -3
echo "APK: $OUT/csARM.apk ($(du -h "$OUT/csARM.apk" | cut -f1))"
