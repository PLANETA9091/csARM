#!/bin/bash
# csARM — build FreeType for the vgui_surfacelib font stack.
# fontmanager.h includes <ft2build.h>; fontmanager.cpp links FT_Init_FreeType,
# FT_New_Face, ... — so both the BUILD job (headers) and the LINK job (static
# lib) need FreeType under thirdparty/.
#   usage: setup_freetype.sh [workspace_root] [cache_dir]
#   env:   NDKROOT, CC (target clang, e.g. aarch64-linux-android24-clang)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R=${1:-$REPO_DIR/..}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=${CC:-aarch64-linux-android24-clang}
FTVER=2.13.2
SRCDIR="$CACHE/freetype-$FTVER"
OUTDIR="$R/thirdparty/freetype-lib"
INC="$R/thirdparty/freetype/include"

mkdir -p "$CACHE"

if [ ! -f "$SRCDIR/src/base/ftinit.c" ]; then
  rm -f "$CACHE/freetype.tgz"
  echo "downloading freetype $FTVER..."
  curl -sfL --retry 3 -o "$CACHE/freetype.tgz" \
    "https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz" \
    || curl -sfL --retry 3 -o "$CACHE/freetype.tgz" \
    "https://download.savannah.gnu.org/releases/freetype/freetype-$FTVER.tar.gz"
  rm -rf "$SRCDIR"
  tar xzf "$CACHE/freetype.tgz" -C "$CACHE"
  # tarball dir is freetype-VER-2.13.2 — normalize
  for d in "$CACHE"/freetype-*; do
    [ -d "$d" ] && [ "$d" != "$SRCDIR" ] && rm -rf "$SRCDIR" && mv "$d" "$SRCDIR"
  done
fi
[ -f "$SRCDIR/src/base/ftinit.c" ] || { echo "freetype source extraction failed"; exit 1; }

# headers where trybuild's FTINC expects them (idempotent)
if [ ! -f "$INC/ft2build.h" ]; then
  rm -rf "$R/thirdparty/freetype"
  mkdir -p "$R/thirdparty/freetype"
  cp -r "$SRCDIR/include" "$R/thirdparty/freetype/include"
fi

mkdir -p "$OUTDIR" "$SRCDIR/build-obj"
FTCFLAGS="-c -fPIC -O2 -w -DFT2_BUILD_LIBRARY -DFT_CONFIG_OPTION_ERROR_STRINGS \
 -I$SRCDIR/include \
 -I$SRCDIR/src/autofit -I$SRCDIR/src/base -I$SRCDIR/src/cff -I$SRCDIR/src/psaux \
 -I$SRCDIR/src/psnames -I$SRCDIR/src/pshinter -I$SRCDIR/src/raster \
 -I$SRCDIR/src/sfnt -I$SRCDIR/src/smooth -I$SRCDIR/src/truetype -I$SRCDIR/src/gzip"

# full single-file amalgamation build: the official baseline is src/base/ftbase.c
# plus per-module "module.c" amalgams — this avoids listing ~60 files by hand.
FILES="
src/base/ftsystem.c
src/base/ftinit.c
src/base/ftdebug.c
src/base/ftbase.c
src/base/ftbbox.c
src/base/ftglyph.c
src/base/ftbitmap.c
src/base/ftmm.c
src/base/fttype1.c
src/base/ftsynth.c
src/base/ftfstype.c
src/autofit/autofit.c
src/cff/cff.c
src/psaux/psaux.c
src/psnames/psnames.c
src/pshinter/pshinter.c
src/raster/raster.c
src/sfnt/sfnt.c
src/smooth/smooth.c
src/truetype/truetype.c
src/gzip/ftgzip.c
src/type1/type1.c
src/cid/type1cid.c
src/pfr/pfr.c
src/type42/type42.c
src/winfonts/winfnt.c
src/pcf/pcf.c
src/bdf/bdf.c
src/sdf/sdf.c
src/svg/svg.c
src/lzw/ftlzw.c
"

rm -f "$OUTDIR/libfreetype.a"
FAILS=0
for f in $FILES; do
  src="$SRCDIR/$f"
  [ -f "$src" ] || { echo "missing freetype source: $f"; FAILS=1; continue; }
  obj="$SRCDIR/build-obj/$(echo "$f" | tr '/' '_').o"
  [ -s "$obj" ] && continue
  if ! $CC $FTCFLAGS "$src" -o "$obj" 2> "$SRCDIR/build-err_$(basename $f).log"; then
    echo "COMPILE FAIL: $f"; head -5 "$SRCDIR/build-err_$(basename $f).log"; FAILS=1
  fi
done
[ "$FAILS" = "0" ] || exit 1

ar rcs "$OUTDIR/libfreetype.a" "$SRCDIR/build-obj"/*.o
echo "libfreetype.a: $(du -h "$OUTDIR/libfreetype.a" | cut -f1)"
[ -s "$OUTDIR/libfreetype.a" ]
