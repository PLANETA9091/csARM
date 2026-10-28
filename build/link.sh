#!/bin/bash
# csARM — link module objects into Android shared libraries
# Model: real separate .so files with DT_NEEDED deps (like Valve Linux build).
# Android app-namespace linker resolves cross-lib symbols via SONAME.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R=${R:-$(dirname "$SCRIPT_DIR")}
cd "$R"
export PATH="${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=${CC:-aarch64-linux-android27-clang}
OUTDIR="$R/out"; mkdir -p "$OUTDIR"
PBLIB=""  # protobuf 2.5.0 is built from source as obj/protobuf25 and linked as libprotobuf.so
SDL2LIB="${SDL2LIB:-$R/thirdparty/SDL2-lib/libSDL2.a}"
LOG="$R/link.log"; : > "$LOG"

# genproto objects (protobuf messages) — compile if missing (protobuf 2.5.0 API)
PBINC="-I c15/thirdparty/protobuf-2.5.0/src -I $R/thirdparty/pb25shim -I genproto"
mkdir -p obj/genproto err/genproto
for pb in genproto/*.pb.cc; do
  [ -e "$pb" ] || continue
  obj="obj/genproto/$(basename "$pb" .cc).o"
  [ -s "$obj" ] && continue
  echo "[genproto] $(basename "$pb")" | tee -a "$LOG"
  $CC -c -fPIC -O1 -w -std=gnu++17 $PBINC -D_POSIX=1 -DLINUX=1 -DGNUC=1 -DENGINE_DLL=1 "$pb" -o "$obj" >> "$LOG" 2>&1
done

LFLAGS="-shared -fPIC -fuse-ld=lld -Wl,--gc-sections -Wl,-soname,"

link_so() {
  local name="$1"; shift
  local deps="$1"; shift   # list of previously linked libs, e.g. "tier0 tier1"
  local tags=()
  local objs=()
  local total=0
  for tag in "$@"; do
    local n=$(ls obj/$tag/*.o 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then echo "!! module $tag has no objects -> skip $name" | tee -a "$LOG"; return 1; fi
    objs+=("obj/$tag"/*.o); total=$((total+n))
  done
  local ldeps=""
  for d in $deps; do ldeps="$ldeps -L$OUTDIR -l$d"; done
  echo "[link] $name  objs=$total  deps=[$deps]" | tee -a "$LOG"
  $CC $LFLAGS"$name" -o "$OUTDIR/$name" "${objs[@]}" $ldeps -ldl -llog -lm -lc -lz 2>>"$LOG"
  local rc=$?
  if [ $rc -ne 0 ]; then echo "   LINK FAILED: $name" | tee -a "$LOG"; else echo "   OK: $name" | tee -a "$LOG"; fi
  return $rc
}

# 1. protobuf 2.5.0 runtime + Foundation
link_so libprotobuf.so "" protobuf25 || true
link_so libtier0.so  ""            tier0 || true
link_so libtier1.so  "tier0"       tier1 || true
link_so libvstdlib.so "tier0 tier1" vstdlib || true
link_so libmathlib.so "tier0 tier1" mathlib || true
link_so libtier2.so  "tier0 tier1" tier2 || true

# 2. Subsystems
link_so libappframework.so "tier0 tier1" appframework || true
link_so libdatacache.so    "tier0 tier1 vstdlib" datacache || true
link_so libstudiorender.so "tier0 tier1 mathlib vstdlib" studiorender || true
link_so libsoundemittersystem.so "tier0 tier1 mathlib vstdlib" soundemittersystem || true
link_so libvguimatsurface.so "tier0 tier1 mathlib vstdlib tier2" vguimatsurface || true
link_so libvgui.so "tier0 tier1 mathlib vstdlib tier2" vgui_dll || true
link_so libvgui_controls.so "tier0 tier1 mathlib vstdlib tier2 vgui" vgui_controls || true
link_so libmaterialsystem.so "tier0 tier1 mathlib vstdlib tier2" materialsystem || true

# 3. Engine (+ protobuf messages + SDL2)
GENPROTO_OBJS=$(ls obj/genproto/*.o 2>/dev/null)
if [ -n "$GENPROTO_OBJS" ] && [ -f "$OUTDIR/libmathlib.so" ]; then
  echo "[link] libengine.so (engine + genproto)" | tee -a "$LOG"
  $CC $LFLAGS"libengine.so" -o "$OUTDIR/libengine.so" obj/engine/*.o $GENPROTO_OBJS \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf \
     $( [ -f "$SDL2LIB" ] && echo "$SDL2LIB" ) \
     -ldl -llog -lm -lc -lz -landroid -lEGL -lGLESv2 -lOpenSLES 2>>"$LOG" \
     && echo "   OK: libengine.so" | tee -a "$LOG" || echo "   LINK FAILED: libengine.so" | tee -a "$LOG"
fi

# 4. Client / Server (game DLLs)
for GAMEDLL in client server; do
  TAGS=$(ls -d obj/$GAMEDLL* 2>/dev/null | grep -v genproto | tr '\n' ' ')
  [ -z "$TAGS" ] && continue
  echo "[link] lib$GAMEDLL.so (tags: $TAGS)" | tee -a "$LOG"
  OBJSETS=""
  for t in $TAGS; do OBJSETS="$OBJSETS $t/*.o"; done
  $CC $LFLAGS"lib$GAMEDLL.so" -o "$OUTDIR/lib$GAMEDLL.so" $OBJSETS $GENPROTO_OBJS \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf \
     -ldl -llog -lm -lc -lz 2>>"$LOG" \
     && echo "   OK: lib$GAMEDLL.so" | tee -a "$LOG" || echo "   LINK FAILED: lib$GAMEDLL.so" | tee -a "$LOG"
done

echo "=== linked results ===" | tee -a "$LOG"
ls -la "$OUTDIR" 2>/dev/null | tee -a "$LOG"
