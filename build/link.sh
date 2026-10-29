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
SDL2LIB="${SDL2LIB:-$R/thirdparty/SDL2-lib/libSDL2.so}"
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

LFLAGS="-shared -fPIC -fuse-ld=lld -stdlib=libc++ -Wl,--gc-sections -Wl,-z,max-page-size=16384"
# Every port lib must carry DT_NEEDED libc++_shared.so (the APK ships it,
# build_apk.sh copies it from the NDK).  -stdlib=libc++_shared is NOT a real
# clang flag — without -lc++_shared the .so keep UND __gxx_personality_v0 /
# std::__ndk1 symbols and bionic dlopen fails on device.
# NDK clang naming: <triple><api>-clang (e.g. x86_64-linux-android27-clang —
# digits are glued to the triple, no dash!) -> strip "27-clang" not "-27-clang"
TRIP=$(echo "$CC" | sed -E 's/[0-9]+-clang$//')
CPPSHBASE="${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$TRIP"
CPPSHAREDDIR=""
if [ -f "$CPPSHBASE/libc++_shared.so" ]; then
  CPPSHAREDDIR="$CPPSHBASE"
else
  for d in "$CPPSHBASE"/*/; do
    [ -f "$d/libc++_shared.so" ] && { CPPSHAREDDIR="${d%/}"; break; }
  done
fi
if [ -n "$CPPSHAREDDIR" ]; then
  # link the EXPLICIT file (no -L): adding the sysroot dir to the search path
  # made lld pull other libs from it (x86_64 dir carries extras) and broke
  # PC32 relocs; a direct path just records DT_NEEDED libc++_shared.so
  LFLAGS="$LFLAGS $CPPSHAREDDIR/libc++_shared.so"
  echo "libc++_shared.so from $CPPSHAREDDIR" | tee -a "$LOG"
else
  echo "WARN: libc++_shared.so not found under $CPPSHBASE — libs will dlopen-fail on device" | tee -a "$LOG"
fi
# LTO=1 (must match trybuild.sh) -> ThinLTO at link; soname passed separately
if [ "${LTO:-0}" = "1" ]; then LFLAGS="$LFLAGS -flto=thin"; fi
if [ "${STRIP:-0}" = "1" ]; then
  STRIPBIN="${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
fi

# objects to drop (duplicate/overridden definitions inside one .so):
#   tier0: mem_helpers.cpp defines g_pszModule which memoverride.cpp also defines;
#          nothing references mem_helpers' symbols (verified via llvm-nm) -> drop it.
#   client: weapon_parse_default.cpp + c_mod_lesson_stubs.cpp are mod-defaults that
#           cstrike15 overrides (cs_weapon_parse.cpp / c_cs_lesson.cpp).
#   server: game/server/player_pickup.cpp overridden by game/shared/cstrike15 version.
EXCLUDE_RE='tier0_mem_helpers\.cpp\.o$|game_shared_weapon_parse_default\.cpp\.o$|game_client_c_mod_lesson_stubs\.cpp\.o$|game_server_player_pickup\.cpp\.o$'

link_so() {
  local name="$1"; shift
  local deps="$1"; shift   # list of previously linked libs, e.g. "tier0 tier1"
  local tags=()
  local objs=()
  local total=0
  for tag in "$@"; do
    local n=$(ls obj/$tag/*.o 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then echo "!! module $tag has no objects -> skip $name" | tee -a "$LOG"; return 1; fi
    for o in obj/$tag/*.o; do
      basename "$o" | grep -qE "$EXCLUDE_RE" || { objs+=("$o"); total=$((total+1)); }
    done
  done
  local ldeps=""
  for d in $deps; do ldeps="$ldeps -L$OUTDIR -l$d"; done
  echo "[link] $name  objs=$total  deps=[$deps]" | tee -a "$LOG"
  $CC $LFLAGS -Wl,-soname,"$name" -o "$OUTDIR/$name" "${objs[@]}" $ldeps -ldl -llog -lm -lc -lz 2>>"$LOG"
  local rc=$?
  if [ $rc -ne 0 ]; then echo "   LINK FAILED: $name" | tee -a "$LOG"; else echo "   OK: $name" | tee -a "$LOG"; fi
  if [ $rc -eq 0 ] && [ -n "${STRIPBIN:-}" ] && [ "${STRIP:-0}" = "1" ]; then "$STRIPBIN" --strip-debug "$OUTDIR/$name" || true; fi
  return $rc
}

# 1. protobuf 2.5.0 runtime + Foundation
if [ -f "$SDL2LIB" ]; then
  echo "[copy] $SDL2LIB -> $OUTDIR/" | tee -a "$LOG"
  cp "$SDL2LIB" "$OUTDIR/libSDL2.so"
fi
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
link_so libvguimatsurface.so "tier0 tier1 mathlib vstdlib tier2 SDL2" vguimatsurface || true
link_so libvgui.so "tier0 tier1 mathlib vstdlib tier2 SDL2" vgui_dll || true
link_so libvgui_controls.so "tier0 tier1 mathlib vstdlib tier2 vgui" vgui_controls || true
link_so libmaterialsystem.so "tier0 tier1 mathlib vstdlib tier2" materialsystem || true
link_so libinputsystem.so "tier0 tier1 vstdlib SDL2" inputsystem || true

# 3. Engine (+ protobuf messages + SDL2)
GENPROTO_OBJS=$(ls obj/genproto/*.o 2>/dev/null)
if [ -n "$GENPROTO_OBJS" ] && [ -f "$OUTDIR/libmathlib.so" ]; then
  echo "[link] libengine.so (engine + genproto)" | tee -a "$LOG"
  $CC $LFLAGS -Wl,-soname,"libengine.so" -o "$OUTDIR/libengine.so" obj/engine/*.o $GENPROTO_OBJS \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf -lSDL2 \
     -ldl -llog -lm -lc -lz -landroid -lEGL -lGLESv2 -lOpenSLES 2>>"$LOG" \
     && { echo "   OK: libengine.so" | tee -a "$LOG"; [ "${STRIP:-0}" = "1" ] && [ -n "${STRIPBIN:-}" ] && "$STRIPBIN" --strip-debug "$OUTDIR/libengine.so" || true; } || echo "   LINK FAILED: libengine.so" | tee -a "$LOG"
fi

# 3b. Launcher (Valve CSourceAppSystemGroup host; dlopen'ed by libmain)
link_so liblauncher.so "tier0 tier1 tier2 appframework SDL2" launcher || true

# 4. Client / Server (game DLLs) — same EXCLUDE_RE filtering as link_so
for GAMEDLL in client server; do
  TAGS=$(ls -d obj/$GAMEDLL* 2>/dev/null | grep -v genproto | tr '\n' ' ')
  [ -z "$TAGS" ] && continue
  GAMEOBJS=""
  GTOTAL=0
  for t in $TAGS; do
    for o in $t/*.o; do
      basename "$o" | grep -qE "$EXCLUDE_RE" || { GAMEOBJS="$GAMEOBJS $o"; GTOTAL=$((GTOTAL+1)); }
    done
  done
  [ "$GTOTAL" -eq 0 ] && continue
  echo "[link] lib$GAMEDLL.so (tags: $TAGS) objs=$GTOTAL" | tee -a "$LOG"
  $CC $LFLAGS -Wl,-soname,"lib$GAMEDLL.so" -o "$OUTDIR/lib$GAMEDLL.so" $GAMEOBJS $GENPROTO_OBJS \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf -lSDL2 \
     -ldl -llog -lm -lc -lz 2>>"$LOG" \
     && { echo "   OK: lib$GAMEDLL.so" | tee -a "$LOG"; [ "${STRIP:-0}" = "1" ] && [ -n "${STRIPBIN:-}" ] && "$STRIPBIN" --strip-debug "$OUTDIR/lib$GAMEDLL.so" || true; } || echo "   LINK FAILED: lib$GAMEDLL.so" | tee -a "$LOG"
done

echo "=== linked results ===" | tee -a "$LOG"
ls -la "$OUTDIR" 2>/dev/null | tee -a "$LOG"

# count failures from the log and propagate a proper exit code
FAILS=$(grep -c "LINK FAILED" "$LOG" || true)
if [ "$FAILS" -gt 0 ]; then
  echo "link.sh: $FAILS library link(s) failed" | tee -a "$LOG"
  exit 1
fi
exit 0
