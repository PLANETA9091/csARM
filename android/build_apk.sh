#!/bin/bash
# csARM — build the visual-test APK without gradle:
# aapt2 (manifest) -> javac -> d8 -> zip (dex + lib/arm64-v8a) -> zipalign -> apksigner.
# Input:  android/libs/*.so            (flat; script places them into lib/arm64-v8a/)
#         android/AndroidManifest.xml, android/src/**/*.java
# Output: android/out/csARM.apk  (debug-signed, installable)
set -euo pipefail
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK=${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}

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

# 1. manifest -> apk skeleton + R.java
"$BT/aapt2" link -o "$OUT/base.apk" \
  --manifest "$A/AndroidManifest.xml" -I "$AJAR" --java "$GEN"

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
cp "$OUT/base.apk" "$OUT/unsigned.apk"
cp "$DEX/classes.dex" "$DEX/classes.dex" 2>/dev/null || true
(cd "$DEX" && zip -q -u "$OUT/unsigned.apk" classes.dex)
mkdir -p "$A/lib/arm64-v8a"
# our .so files have DT_NEEDED libc++_shared.so — take it from the NDK sysroot
if [ ! -f "$A/libs/libc++_shared.so" ]; then
  for cand in "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_HOME:-}" "$ANDROID_SDK_ROOT/ndk/"*/ ; do
    [ -n "$cand" ] || continue
    f="$cand/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
    if [ -f "$f" ]; then cp "$f" "$A/libs/libc++_shared.so"; echo "libc++_shared.so from $cand"; break; fi
  done
fi
if ls "$A"/libs/*.so >/dev/null 2>&1; then
  cp "$A"/libs/*.so "$A/lib/arm64-v8a/"
fi
NLIB=$(ls "$A"/lib/arm64-v8a/*.so 2>/dev/null | wc -l)
echo "native libs: $NLIB"
[ "$NLIB" -ge 18 ] || { echo "ERROR: expected >=18 native libs (17 port libs + libc++_shared), got $NLIB"; exit 1; }
(cd "$A" && zip -q -u "$OUT/unsigned.apk" lib/arm64-v8a/*.so)

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
