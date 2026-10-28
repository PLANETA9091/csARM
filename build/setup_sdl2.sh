#!/bin/bash
# csARM — build SDL 2.0.2 static library for aarch64 Android
# c15/thirdparty/SDL2 ships only headers (2.0.2); sources are downloaded and
# built with the file list from SDL's own Android.mk (android backend only).
# Result: thirdparty/SDL2-lib/libSDL2.a
#
# NOTE: SDL is compiled against ITS OWN pristine headers. Valve's bundled
# headers (c15/thirdparty/SDL2) are a modified variant and are NOT ABI-identical
# for SDL-internal structs (SDL_rwops union etc.); overlaying them on the SDL
# tree breaks SDL's own .c files (missing SDL_RWops.androidio, missing 2.0.x
# hints). The engine only consumes SDL's public C ABI, which is stable.
# dynapi is patched OFF (it #error's on -D override; sed the header) so the
# static lib needs no SDL_Render* symbols: the engine renders via ToGL.
# usage: setup_sdl2.sh [workspace_root] [cache_dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
SRCDIR="$CACHE/SDL-2.0.2"
OUTDIR="$R/thirdparty/SDL2-lib"

mkdir -p "$CACHE" "$OUTDIR"

if [ ! -f "$SRCDIR/src/SDL.c" ]; then
  rm -rf "$CACHE/sdl.tgz"
  echo "downloading SDL 2.0.2 (libsdl.org, fallback GitHub)..."
  curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://libsdl.org/release/SDL2-2.0.2.tar.gz" \
    || curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/releases/download/release-2.0.2/SDL2-2.0.2.tar.gz" \
    || curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.2.tar.gz"
  tar xzf "$CACHE/sdl.tgz" -C "$CACHE"
  # tarball names differ (SDL2-2.0.2 vs SDL-release-2.0.2) — normalize
  for d in "$CACHE/SDL2-2.0.2" "$CACHE/SDL-release-2.0.2"; do
    [ -d "$d" ] && [ "$d" != "$SRCDIR" ] && rm -rf "$SRCDIR" && mv "$d" "$SRCDIR"
  done
fi
[ -f "$SRCDIR/src/SDL.c" ] || { echo "SDL source extraction failed"; exit 1; }

# dynapi off (engine links SDL symbols directly; no full-symbol-table needed)
sed -i 's/#define SDL_DYNAMIC_API 1/#define SDL_DYNAMIC_API 0/' "$SRCDIR/src/dynapi/SDL_dynapi.h"
grep -q "#define SDL_DYNAMIC_API 0" "$SRCDIR/src/dynapi/SDL_dynapi.h" || { echo "dynapi patch failed"; exit 1; }

export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=aarch64-linux-android24-clang

# File list mirroring SDL 2.0.2's Android.mk (android backend set).
# src/render/* and src/video/yuv2rgb excluded: engine renders via ToGL and
# never calls SDL_Render*; this also drops the gles2/psp proc-pointer code
# that clang 18 rejects outright.
SRCS=$(cat <<'EOF'
src/*.c
src/audio/*.c
src/audio/android/*.c
src/audio/dummy/*.c
src/atomic/SDL_atomic.c
src/atomic/SDL_spinlock.c
src/core/android/*.c
src/cpuinfo/*.c
src/dynapi/*.c
src/events/*.c
src/file/*.c
src/haptic/*.c
src/haptic/dummy/*.c
src/joystick/*.c
src/joystick/android/*.c
src/loadso/dlopen/*.c
src/power/*.c
src/power/android/*.c
src/filesystem/dummy/*.c
src/stdlib/*.c
src/thread/*.c
src/thread/pthread/*.c
src/timer/*.c
src/timer/unix/*.c
src/video/*.c
src/video/android/*.c
src/video/dummy/*.c
src/main/android/SDL_android_main.c
EOF
)

FILES=""
for pat in $SRCS; do
  for f in "$SRCDIR"/$pat; do
    [ -f "$f" ] && FILES="$FILES $f"
  done
done
echo "SDL sources: $(echo $FILES | wc -w)"
[ "$(echo $FILES | wc -w)" -lt 60 ] && { echo "too few SDL sources — file list broken"; exit 1; }

mkdir -p "$SRCDIR/build-obj" "$SRCDIR/build-err"
rm -f "$SRCDIR/build-err/fails.txt"
build_one() {
  f="$1"
  obj="$SRCDIR/build-obj/$(echo "$f" | md5sum | cut -c1-10)_$(basename "$f").o"
  [ -s "$obj" ] && return 0
  $CC -c -fPIC -O2 -w \
    -DANDROID=1 \
    -Wno-error=incompatible-function-pointer-types \
    -Wno-incompatible-function-pointer-types \
    -Wno-error=implicit-function-declaration \
    -I"$SRCDIR/include" \
    -DGL_GLEXT_PROTOTYPES \
    "$f" -o "$obj" 2> "$SRCDIR/build-err/$(basename "$f").log" || echo "FAIL $f" >> "$SRCDIR/build-err/fails.txt"
}
export -f build_one
export CC SRCDIR

echo "$FILES" | tr ' ' '\n' | grep -v '^$' | xargs -P4 -n1 bash -c 'build_one "$0"'
if [ -f "$SRCDIR/build-err/fails.txt" ]; then
  echo "SDL2 build failures:"; cat "$SRCDIR/build-err/fails.txt"
  for f in $(cat "$SRCDIR/build-err/fails.txt" | sed 's/FAIL //' | xargs -n1 basename 2>/dev/null); do
    [ -f "$SRCDIR/build-err/$f.log" ] && { echo "--- $f"; head -6 "$SRCDIR/build-err/$f.log"; }
  done
  exit 1
fi

rm -f "$OUTDIR/libSDL2.a" "$OUTDIR/libSDL2.so"
ar rcs "$OUTDIR/libSDL2.a" "$SRCDIR/build-obj"/*.o
# shared build: single SDL instance shared by engine/vgui/vguimatsurface (DT_NEEDED)
$CC -shared -fPIC -fuse-ld=lld -Wl,-soname,libSDL2.so \
  -o "$OUTDIR/libSDL2.so" "$SRCDIR/build-obj"/*.o \
  -lGLESv1_CM -lGLESv2 -lEGL -llog -landroid -ldl -lm -lc 2>> "$SRCDIR/build-err/link-so.log" \
  || { echo "libSDL2.so link failed:"; cat "$SRCDIR/build-err/link-so.log" | head -20; exit 1; }
echo "libSDL2.a: $(du -h "$OUTDIR/libSDL2.a" | cut -f1)"
echo "libSDL2.so: $(du -h "$OUTDIR/libSDL2.so" | cut -f1)"
