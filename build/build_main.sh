#!/bin/bash
# csARM — build the native launcher (libmain.so)
# Provides: SDL2 Java glue entry (nativeInit) + SDL_main -> Valve LauncherMain.
# Requires: NDKROOT, SDL cache dir (setup_sdl2.sh), out/libSDL2.so, out/libtier0.so
# usage: build/build_main.sh [workspace_root] [cache_dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
TRIP=$(echo "${CC:-aarch64-linux-android27-clang}" | sed -E 's/-[0-9]+-clang$//')
CPPSHDIR=$(dirname "$(find "${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$TRIP" -maxdepth 2 -name libc++_shared.so 2>/dev/null | sort | tail -1)" 2>/dev/null || true)
export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=${CC:-aarch64-linux-android24-clang}
OUTDIR="$R/out"; mkdir -p "$OUTDIR"

SDLINC="$CACHE/SDL-2.0.2/include"
[ -d "$SDLINC" ] || { echo "SDL headers missing at $SDLINC (run setup_sdl2.sh first)"; exit 1; }

echo "[build_main] libmain.so"
$CC -c -fPIC -O2 -std=gnu++17 -w \
  -I "$SDLINC" -I "$R/c15/public" -I "$R/c15/public/tier0" \
  "$R/launcher_native/csarm_main.cpp" -o "$R/launcher_native/csarm_main.o"

$CC -shared -fPIC -fuse-ld=lld -Wl,-soname,libmain.so \
  -Wl,-z,max-page-size=16384 \
  -o "$OUTDIR/libmain.so" "$R/launcher_native/csarm_main.o" \
  -L"$OUTDIR" -lSDL2 -ltier0 -llog -ldl -lm -lc -landroid \
  ${CPPSHDIR:+-L$CPPSHDIR} -lc++_shared \
  2> "$R/launcher_native/link.log" \
  || { echo "libmain.so link failed:"; cat "$R/launcher_native/link.log"; exit 1; }

echo "libmain.so: $(du -h "$OUTDIR/libmain.so" | cut -f1)"
