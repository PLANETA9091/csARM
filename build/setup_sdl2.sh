#!/bin/bash
# csARM — build SDL 2.0.2 static library for aarch64 Android
# c15/thirdparty/SDL2 ships only headers (2.0.2); sources are downloaded.
# Result: thirdparty/SDL2-lib/libSDL2.a
# usage: setup_sdl2.sh [workspace_root] [cache_dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
SRCVER=2.0.2
SRCDIR="$CACHE/SDL2-$SRCVER"
OUTDIR="$R/thirdparty/SDL2-lib"

mkdir -p "$CACHE" "$OUTDIR"

if [ ! -d "$SRCDIR" ]; then
  echo "downloading SDL $SRCVER..."
  curl -sL -o "$CACHE/sdl.tgz" "https://libsdl.org/release/SDL2-$SRCVER.tar.gz" \
    || curl -sL -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/releases/download/release-$SRCVER/SDL2-$SRCVER.tar.gz"
  tar xzf "$CACHE/sdl.tgz" -C "$CACHE"
fi

# overlay the mirror's SDL 2.0.2 headers (SDL_config.h etc. are tuned there)
cp -v "$R/c15/thirdparty/SDL2/"*.h "$SRCDIR/include/" > /dev/null

export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=aarch64-linux-android24-clang

mkdir -p "$SRCDIR/build-obj" "$SRCDIR/build-err"
SRCS=$(find "$SRCDIR/src" -name '*.c' | grep -vE '/test|/thread/pthread/SDL_systhread.c.loss' | sort)
echo "SDL sources: $(echo "$SRCS" | wc -l)"

build_one() {
  f="$1"
  obj="$SRCDIR/build-obj/$(echo "$f" | md5sum | cut -c1-10)_$(basename "$f").o"
  [ -s "$obj" ] && return 0
  $CC -c -fPIC -O2 -w \
    -I"$SRCDIR/include" \
    -DANDROID -D__ANDROID__ -DSDL_VIDEO_DRIVER_ANDROID=1 -DSDL_AUDIO_DRIVER_ANDROID=1 \
    -DSDL_STATIC_LIB -DHAVE_LIBC=1 \
    "$f" -o "$obj" 2> "$SRCDIR/build-err/$(basename "$f").log" || echo "FAIL $f" >> "$SRCDIR/build-err/fails.txt"
}
export -f build_one
export CC SRCDIR

rm -f "$SRCDIR/build-err/fails.txt"
echo "$SRCS" | xargs -P4 -n1 bash -c 'build_one "$0"'
if [ -f "$SRCDIR/build-err/fails.txt" ]; then
  echo "SDL2 build failures:"; cat "$SRCDIR/build-err/fails.txt"; exit 1
fi

ar rcs "$OUTDIR/libSDL2.a" "$SRCDIR/build-obj"/*.o
echo "libSDL2.a: $(du -h "$OUTDIR/libSDL2.a" | cut -f1)"
