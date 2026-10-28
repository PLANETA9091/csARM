#!/bin/bash
# csARM — build SDL 2.0.2 static library for aarch64 Android
# c15/thirdparty/SDL2 ships only headers (2.0.2); sources are downloaded and
# built with the file list from SDL's own Android.mk (android backend only).
# Result: thirdparty/SDL2-lib/libSDL2.a
# usage: setup_sdl2.sh [workspace_root] [cache_dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
SRCDIR="$CACHE/SDL-release-2.0.2"
OUTDIR="$R/thirdparty/SDL2-lib"

mkdir -p "$CACHE" "$OUTDIR"

if [ ! -d "$SRCDIR" ]; then
  echo "downloading SDL 2.0.2..."
  curl -sL --retry 3 -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.2.tar.gz"
  tar xzf "$CACHE/sdl.tgz" -C "$CACHE"
fi

# SDL_config_android.h is the canonical config for this target; the mirror's
# SDL_config.h is a placeholder. Overlay mirror headers, then force the
# android config.
cp "$SRCDIR/include/SDL_config_android.h" "$SRCDIR/include/SDL_config.h.new"
cp -r "$R/c15/thirdparty/SDL2/." "$SRCDIR/include/" 2>/dev/null || true
mv "$SRCDIR/include/SDL_config.h.new" "$SRCDIR/include/SDL_config.h"

export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=aarch64-linux-android24-clang

# File list mirroring SDL 2.0.2's Android.mk (android backend set)
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
src/render/*.c
src/render/opengles/*.c
src/render/opengles2/*.c
src/render/psp/*.c
src/render/software/*.c
src/stdlib/*.c
src/thread/*.c
src/thread/pthread/*.c
src/timer/*.c
src/timer/unix/*.c
src/video/*.c
src/video/android/*.c
src/video/dummy/*.c
src/video/yuv2rgb/*.c
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

mkdir -p "$SRCDIR/build-obj" "$SRCDIR/build-err"
rm -f "$SRCDIR/build-err/fails.txt"
build_one() {
  f="$1"
  obj="$SRCDIR/build-obj/$(echo "$f" | md5sum | cut -c1-10)_$(basename "$f").o"
  [ -s "$obj" ] && return 0
  $CC -c -fPIC -O2 -w \
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

rm -f "$OUTDIR/libSDL2.a"
ar rcs "$OUTDIR/libSDL2.a" "$SRCDIR/build-obj"/*.o
echo "libSDL2.a: $(du -h "$OUTDIR/libSDL2.a" | cut -f1)"
