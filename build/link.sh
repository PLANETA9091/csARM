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

# g_bInitMemory stub (see EXCLUDE_RE note) — referenced by tier0/tier1 objects.
# tier0/mem_helpers.cpp ALSO defines CalcHeapUsed() and DoApplyMemoryInitializations()
# which memoverride/memstd reference — it is excluded (duplicate g_pszModule), so the
# stub provides those two as well.
cat > "$OUTDIR/gbinit.cpp" <<'EOF'
#include <stddef.h>
bool g_bInitMemory = true;
void DoApplyMemoryInitializations( void *pMem, size_t nSize ) { (void)pMem; (void)nSize; }
size_t CalcHeapUsed() { return 0; }
EOF
$CC -c -fPIC -O1 -w -o "$OUTDIR/gbinit.cpp.o" "$OUTDIR/gbinit.cpp" 2>>"$LOG"

# --- per-module glue objects -------------------------------------------------
# interfaces.cpp (Valve links this tiny static lib into EVERY module; each .so
# gets its own copy of the global interface pointers, filled at Connect() time)
INTERFACES_O=""
for cand in obj/interfaces/interfaces_interfaces.cpp.o "$OUTDIR/interfaces.cpp.o"; do
  [ -f "$cand" ] && { INTERFACES_O="$cand"; break; }
done
[ -n "$INTERFACES_O" ] && echo "[glue] interfaces.o: $INTERFACES_O" | tee -a "$LOG" || echo "[glue] WARN: interfaces.o missing" | tee -a "$LOG"
# Steamworks stub (no Steam on Android) — needed by engine/client/server/inputsystem/vgui_controls
STEAM_O=""
$CC -c -fPIC -O1 -w -o "$OUTDIR/stub_steam_api.cpp.o" "$SCRIPT_DIR/stub_steam_api.c" 2>>"$LOG" && STEAM_O="$OUTDIR/stub_steam_api.cpp.o"
# C++ glue stubs (Phonon thread, SDR transport, ScaleformUI probe) — engine/client/server
GLUE_O=""
$CC -c -fPIC -O1 -w -std=gnu++17 -o "$OUTDIR/glue_stubs.cpp.o" "$SCRIPT_DIR/glue_stubs.cpp" 2>>"$LOG" && GLUE_O="$OUTDIR/glue_stubs.cpp.o"
# materialsystem glue: g_pHardwareConfig is owned by shaderapidx9 (not ported yet)
GLUE_MS_O=""
$CC -c -fPIC -O1 -w -std=gnu++17 -o "$OUTDIR/glue_materialsystem.cpp.o" "$SCRIPT_DIR/glue_materialsystem.cpp" 2>>"$LOG" && GLUE_MS_O="$OUTDIR/glue_materialsystem.cpp.o"
# bionic has no glibc __xstat — pathmatch's __real___xstat family shims (tier0/tier1)
XSTAT_O=""
$CC -c -fPIC -O1 -w -o "$OUTDIR/glue_xstat.cpp.o" "$SCRIPT_DIR/glue_xstat.c" 2>>"$LOG" && XSTAT_O="$OUTDIR/glue_xstat.cpp.o"
# bzip2.c (C) cannot inline C++ V_isspace from strtools.h
BZGLUE_O=""
$CC -c -fPIC -O1 -w -o "$OUTDIR/glue_bzip2.cpp.o" "$SCRIPT_DIR/glue_bzip2.c" 2>>"$LOG" && BZGLUE_O="$OUTDIR/glue_bzip2.cpp.o"
# fontconfig stub (Android has no fontconfig; linuxfont.cpp enumerates fonts via it)
FCSTUB_O=""
$CC -c -fPIC -O1 -w -I "$SCRIPT_DIR/fontconfig_shim" -o "$OUTDIR/fcstub.cpp.o" "$SCRIPT_DIR/fontconfig_shim/fcstub.c" 2>>"$LOG" && FCSTUB_O="$OUTDIR/fcstub.cpp.o"
# filesystem glue for appframework/vgui (engine has the real implementation)
GLUE_FS_O=""
$CC -c -fPIC -O1 -w -std=gnu++17 -o "$OUTDIR/glue_fs.cpp.o" "$SCRIPT_DIR/glue_fs.cpp" 2>>"$LOG" && GLUE_FS_O="$OUTDIR/glue_fs.cpp.o"
# engine middleware stubs (jpeg / Phonon / DSound voice capture)
GLUE_ENG_O=""
$CC -c -fPIC -O1 -w -std=gnu++17 -o "$OUTDIR/glue_engine.cpp.o" "$SCRIPT_DIR/glue_engine.cpp" 2>>"$LOG" && GLUE_ENG_O="$OUTDIR/glue_engine.cpp.o"
# soundsystem glue (windows-only device factories)
GLUE_SND_O=""
$CC -c -fPIC -O1 -w -std=gnu++17 -o "$OUTDIR/glue_soundsystem.cpp.o" "$SCRIPT_DIR/glue_soundsystem.cpp" 2>>"$LOG" && GLUE_SND_O="$OUTDIR/glue_soundsystem.cpp.o"
# FreeType static lib (vguimatsurface font stack)
FREETYPE_A="$R/thirdparty/freetype-lib/libfreetype.a"
[ -f "$FREETYPE_A" ] && echo "[glue] freetype: $FREETYPE_A" | tee -a "$LOG" || FREETYPE_A=""
# Valve wraps libc file calls inside tier0/tier1 via tier1/pathmatch.cpp
# (UTF-8 path massaging).  Without the --wrap list the linker leaves __real_*
# UND and bionic dlopen fails.
WRAPLIST="-Wl,--wrap=fopen -Wl,--wrap=fopen64 -Wl,--wrap=freopen -Wl,--wrap=open -Wl,--wrap=open64 \
 -Wl,--wrap=opendir -Wl,--wrap=mkdir -Wl,--wrap=mkfifo -Wl,--wrap=mknod -Wl,--wrap=mount \
 -Wl,--wrap=rename -Wl,--wrap=link -Wl,--wrap=lstat -Wl,--wrap=chmod -Wl,--wrap=chown \
 -Wl,--wrap=lchown -Wl,--wrap=access -Wl,--wrap=realpath -Wl,--wrap=__xstat -Wl,--wrap=__xstat64 \
 -Wl,--wrap=__lxstat -Wl,--wrap=__lxstat64 -Wl,--wrap=stat -Wl,--wrap=scandir -Wl,--wrap=symlink \
 -Wl,--wrap=unlink -Wl,--wrap=utime -Wl,--wrap=utimes -Wl,--wrap=rmdir"
if [ "${STRIP:-0}" = "1" ]; then
  STRIPBIN="${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
fi

# objects to drop (duplicate/overridden definitions inside one .so):
#   tier0: mem_helpers.cpp defines g_pszModule which memoverride.cpp also defines;
#          nothing references mem_helpers' symbols (verified via llvm-nm) -> drop it.
#   client: weapon_parse_default.cpp + c_mod_lesson_stubs.cpp are mod-defaults that
#           cstrike15 overrides (cs_weapon_parse.cpp / c_cs_lesson.cpp).
#   server: game/server/player_pickup.cpp overridden by game/shared/cstrike15 version.
#   tier0: mem_helpers.cpp excluded — duplicate g_pszModule; its g_bInitMemory
#          (the only symbol others reference) is provided by the GBINIT stub.
EXCLUDE_RE='tier0_mem_helpers\.cpp\.o$|game_shared_weapon_parse_default\.cpp\.o$|game_client_c_mod_lesson_stubs\.cpp\.o$|game_server_player_pickup\.cpp\.o$'

# ---------------------------------------------------------------------------
# Automatic cross-lib dependency resolution (2-pass linking).
# bionic resolves a dlopen'ed lib's UND symbols ONLY through its DT_NEEDED
# graph (System.loadLibrary is RTLD_LOCAL) — so every cross-reference between
# our .so must be a DT_NEEDED. Manual dep tables drift; instead we scan the
# linked libs' dynamic symbols and relink with the complete -l set, then
# FAIL the link if any UND symbol remains that neither a port lib nor an
# Android system lib defines (those are guaranteed dlopen failures).
# ---------------------------------------------------------------------------
declare -A R_OBJS R_DEPS R_TAIL
record_link() {
  R_OBJS[$1]="$2"; R_DEPS[$1]="$3"; R_TAIL[$1]="$4"
}

# dsyms mode "def": STRONG or WEAK defined globals both count.
#   - port libs: a WEAK def (e.g. inline template instantiation) still satisfies
#     relocations at runtime (bionic resolves weak defined symbols)
#   - system libs: NDK r30 libc++_shared.so exports operator delete(void*,size_t)
#     / std::string instantiations as WEAK; they are guaranteed DT_NEEDED providers
# dsyms mode "defstrong": GLOBAL only — used for cross-lib DT_NEEDED inference so
#   weak inline-template defs in every lib don't fabricate a full dependency web.
# dsyms mode "und": STRONG undefined (WEAK UND legally resolve to NULL — not a dep)
dsyms() {  # $1 = lib, $2 = "def"|"defstrong"|"und"
  llvm-readelf -W --dyn-syms "$1" 2>/dev/null | awk -v mode="$2" '
    NF >= 8 && $4 != "SECTION" {
      if (mode=="def" && ($5=="GLOBAL" || $5=="WEAK") && $7!="UND") { n=$8; sub(/@.*/, "", n); if (n!="") print n }
      if (mode=="defstrong" && $5=="GLOBAL" && $7!="UND") { n=$8; sub(/@.*/, "", n); if (n!="") print n }
      if (mode=="und" && $7=="UND" && $5!="WEAK")   { n=$8; sub(/@.*/, "", n); if (n!="") print n }
    }'
}

build_symmap() {
  : > "$OUTDIR/.symmap"
  : > "$OUTDIR/.symmap_strong"
  local so base
  for so in "$OUTDIR"/lib*.so; do
    base=$(basename "$so" .so)
    dsyms "$so" def | awk -v b="$base" '{print $1, b}' >> "$OUTDIR/.symmap"
    dsyms "$so" defstrong | awk -v b="$base" '{print $1, b}' >> "$OUTDIR/.symmap_strong"
  done
  sort -u -o "$OUTDIR/.symmap" "$OUTDIR/.symmap"
  sort -u -o "$OUTDIR/.symmap_strong" "$OUTDIR/.symmap_strong"
}

auto_extra_deps() {
  local base="$1"
  dsyms "$OUTDIR/$base.so" und | sort -u \
    | awk -v B="$base" 'NR==FNR { defs[$1]=$2; next } $0 in defs && defs[$0] != B { print defs[$0] }' \
        "$OUTDIR/.symmap_strong" - | sort -u
}

relink_with() {
  local name="$1"; shift
  local extra="$1"; shift
  local objs ldeps lextra d WRAPS FT
  read -r -a objs <<< "${R_OBJS[$name]}"
  ldeps=""; for d in ${R_DEPS[$name]};  do ldeps="$ldeps -L$OUTDIR -l$d"; done
  lextra=""; for d in $extra; do lextra="$lextra -L$OUTDIR -l$d"; done
  # reapply the per-lib flags from the original link (wraps, freetype, snd glue)
  WRAPS=""; case "$name" in libtier0.so|libtier1.so) WRAPS="$WRAPLIST" ;; esac
  FT=""; case "$name" in libvguimatsurface.so) [ -n "$FREETYPE_A" ] && FT="$FREETYPE_A"; [ -n "$FCSTUB_O" ] && FT="$FT $FCSTUB_O" ;; esac
  SNDG=""; case "$name" in libsoundsystem.so) [ -n "$GLUE_SND_O" ] && SNDG="$GLUE_SND_O" ;; esac
  echo "[auto-dep] relink $name extra_libs=[$extra]" | tee -a "$LOG"
  $CC $LFLAGS $WRAPS -Wl,-soname,"$name" -o "$OUTDIR/$name" "${objs[@]}" $ldeps $lextra $FT $SNDG ${R_TAIL[$name]} 2>>"$LOG" \
    && echo "   OK: $name (auto-dep relink)" | tee -a "$LOG" \
    || { echo "   LINK FAILED: $name (auto-dep relink)" | tee -a "$LOG"; return 1; }
}

auto_dep_rounds() {
  local round so base extra changed
  for round in 1 2 3; do
    build_symmap
    changed=0
    for so in "$OUTDIR"/lib*.so; do
      base=$(basename "$so" .so)
      [ -n "${R_OBJS[$base]:-}" ] || continue   # libSDL2 is a copy — no relink data
      extra=$(auto_extra_deps "$base")
      [ -z "$extra" ] && continue
      case "$extra" in *$base*) echo "[auto-dep] SKIP $base (self-reference)" | tee -a "$LOG"; continue;; esac
      if relink_with "$base" "$extra"; then changed=1; fi
    done
    [ "$changed" -eq 0 ] && break
  done
}

und_gate() {
  build_symmap
  # system libs that legitimately provide symbols at runtime (GLOBAL or WEAK defs)
  local TRIP SYS
  TRIP=$(echo "$CC" | sed -E 's/[0-9]+-clang$//')
  SYS="${NDKROOT%/}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/$TRIP"
  : > "$OUTDIR/.allowed"
  local lib
  for lib in "$SYS"/*.so \
             "$SYS"/*/libc.so "$SYS"/*/libm.so "$SYS"/*/libdl.so "$SYS"/*/libdl_android.so \
             "$SYS"/*/liblog.so "$SYS"/*/libz.so "$SYS"/*/libstdc++.so \
             "$SYS"/*/libandroid.so "$SYS"/*/libEGL.so "$SYS"/*/libGLESv2.so "$SYS"/*/libGLESv1_CM.so \
             "$SYS"/*/libOpenSLES.so "$SYS"/*/libnativewindow.so "$SYS"/*/libmediandk.so \
             "$SYS"/*/libaaudio.so "$SYS"/*/libunwind.so "$SYS"/*/libc++_shared.so; do
    [ -e "$lib" ] || continue
    case "$lib" in
      *.a) llvm-readelf -W --syms "$lib" 2>/dev/null | awk '$5=="GLOBAL" && $7!="UND" {n=$8; sub(/@.*/,"",n); print n}' ;;
      *)   dsyms "$lib" def ;;
    esac
  done | sort -u > "$OUTDIR/.allowed"
  cat "$OUTDIR/.symmap" | awk '{print $1}' >> "$OUTDIR/.allowed"
  sort -u -o "$OUTDIR/.allowed" "$OUTDIR/.allowed"
  echo "[und-gate] symmap=$(wc -l < "$OUTDIR/.symmap") allowed=$(wc -l < "$OUTDIR/.allowed")" | tee -a "$LOG"

  # boot-path libs gate STRICTLY: a single unresolvable symbol here is a
  # guaranteed dlopen failure and kills the engine launch.
  # libclient/libserver are CONTENT-path (loaded only at map load) — report
  # but do not fail the boot pipeline until their content stack is ported.
  local so base BAD TOTAL
  : > "$OUTDIR/.unresolved"
  : > "$OUTDIR/.unresolved_warn"
  for so in "$OUTDIR"/lib*.so; do
    base=$(basename "$so" .so)
    BAD=$(dsyms "$so" und | sort -u \
          | awk 'NR==FNR{a[$1]=1;next} !($0 in a)' "$OUTDIR/.allowed" -)
    if [ -n "$BAD" ]; then
      TOTAL=$(echo "$BAD" | wc -l)
      case "$base" in
        libclient|libserver)
          echo "[und-gate] WARN $base: $TOTAL unresolved (game DLL, content-path)" | tee -a "$LOG"
          echo "$BAD" | head -10 | sed 's/^/    UND /' | tee -a "$LOG"
          echo "$BAD" | sed "s/^/$base /" >> "$OUTDIR/.unresolved_warn"
          ;;
        *)
          echo "[und-gate] $base: $TOTAL unresolved symbol(s)" | tee -a "$LOG"
          echo "$BAD" | head -50 | sed 's/^/    UND /' | tee -a "$LOG"
          echo "$BAD" | sed "s/^/$base /" >> "$OUTDIR/.unresolved"
          ;;
      esac
    fi
  done
  if [ -s "$OUTDIR/.unresolved" ]; then
    echo "link.sh: UNRESOLVED symbols remain on the boot path (guaranteed dlopen failures)" | tee -a "$LOG"
    exit 2
  fi
  echo "[und-gate] boot path: all dynamic symbols resolvable (port libs + system)" | tee -a "$LOG"
}

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
    # tier0 needs g_bInitMemory from mem_helpers.cpp — but that file also has a
    # duplicate g_pszModule and its objects are LTO bitcode (llvm-objcopy can't
    # localize symbols in bitcode), so the file is excluded and a one-symbol
    # stub (GBINIT, compiled below) provides exactly what others reference.
    [ "$tag" = "tier0" ] && [ -f "$OUTDIR/gbinit.cpp.o" ] && { objs+=("$OUTDIR/gbinit.cpp.o"); total=$((total+1)); }
  done
  # Valve links interfaces.lib into every module — do the same (own copy of the
  # global interface pointers per .so, initialized by ConnectTier*Libraries).
  if [ -n "$INTERFACES_O" ] && [ -f "$INTERFACES_O" ]; then objs+=("$INTERFACES_O"); total=$((total+1)); fi
  # Steamworks / platform glue only where the sources actually reference it
  case "$name" in
    libengine.so|libclient.so|libserver.so)
      [ -n "$STEAM_O" ] && { objs+=("$STEAM_O"); total=$((total+1)); }
      [ -n "$GLUE_O" ] && { objs+=("$GLUE_O"); total=$((total+1)); }
      [ -n "$GLUE_ENG_O" ] && { objs+=("$GLUE_ENG_O"); total=$((total+1)); } ;;
    libappframework.so)
      # sdlmgr.cpp resolves the ToGL entry-point table (see glue_stubs.cpp);
      # filesystem_init.cpp needs FileSystem_UpdateAddonSearchPaths (glue_fs)
      [ -n "$GLUE_O" ] && { objs+=("$GLUE_O"); total=$((total+1)); }
      [ -n "$GLUE_FS_O" ] && { objs+=("$GLUE_FS_O"); total=$((total+1)); } ;;
    libvgui.so)
      [ -n "$GLUE_FS_O" ] && { objs+=("$GLUE_FS_O"); total=$((total+1)); } ;;
    libmatsys_controls.so)
      [ -n "$GLUE_FS_O" ] && { objs+=("$GLUE_FS_O"); total=$((total+1)); } ;;
    libinputsystem.so|libvgui_controls.so)
      [ -n "$STEAM_O" ] && { objs+=("$STEAM_O"); total=$((total+1)); } ;;
    libmaterialsystem.so)
      [ -n "$GLUE_MS_O" ] && { objs+=("$GLUE_MS_O"); total=$((total+1)); } ;;
    libtier0.so|libtier1.so)
      [ -n "$XSTAT_O" ] && { objs+=("$XSTAT_O"); total=$((total+1)); } ;;
    libbzip2.so)
      [ -n "$BZGLUE_O" ] && { objs+=("$BZGLUE_O"); total=$((total+1)); } ;;
  esac
  # pathmatch.cpp lives in tier0 AND tier1 — apply Valve's wrap list there
  local WRAPS=""
  case "$name" in libtier0.so|libtier1.so) WRAPS="$WRAPLIST" ;; esac
  # fonts: vguimatsurface carries the FreeType-based font stack + fontconfig stub
  local FT=""
  case "$name" in libvguimatsurface.so) [ -n "$FREETYPE_A" ] && FT="$FREETYPE_A"; [ -n "$FCSTUB_O" ] && FT="$FT $FCSTUB_O" ;; esac
  local ldeps=""
  for d in $deps; do ldeps="$ldeps -L$OUTDIR -l$d"; done
  local SNDG=""
  case "$name" in libsoundsystem.so) [ -n "$GLUE_SND_O" ] && SNDG="$GLUE_SND_O" ;; esac
  echo "[link] $name  objs=$total  deps=[$deps]" | tee -a "$LOG"
  $CC $LFLAGS $WRAPS -Wl,-soname,"$name" -o "$OUTDIR/$name" "${objs[@]}" $ldeps $FT $SNDG -ldl -llog -lm -lc -lz 2>>"$LOG"
  record_link "$name" "${objs[*]} $SNDG" "$deps" "-ldl -llog -lm -lc -lz"
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
link_so libmathlib.so "tier0 tier1" mathlib mathlib_extra || true
link_so libtier2.so  "tier0 tier1" tier2 || true

# 2. Subsystems
link_so libappframework.so "tier0 tier1" appframework || true
link_so libdatacache.so    "tier0 tier1 vstdlib" datacache || true
link_so libstudiorender.so "tier0 tier1 mathlib vstdlib" studiorender || true
link_so libsoundemittersystem.so "tier0 tier1 mathlib vstdlib" soundemittersystem || true
link_so libvguimatsurface.so "tier0 tier1 mathlib vstdlib tier2 SDL2" vguimatsurface vgui_surfacelib || true
link_so libvgui.so "tier0 tier1 mathlib vstdlib tier2 SDL2" vgui_dll || true
link_so libvgui_controls.so "tier0 tier1 mathlib vstdlib tier2 vgui" vgui_controls || true
link_so libmaterialsystem.so "tier0 tier1 mathlib vstdlib tier2" materialsystem || true
link_so libshaderlib.so "tier0 tier1 mathlib vstdlib" shaderlib || true
link_so libinputsystem.so "tier0 tier1 vstdlib SDL2" inputsystem || true
link_so libbzip2.so "" bzip2 || true
link_so libfilesystem_stdio.so "tier0 tier1 vstdlib" filesystem_stdio vpklib || true
link_so libtier3.so "tier0 tier1 vstdlib" tier3 || true
link_so libdmxloader.so "tier0 tier1" dmxloader || true
link_so libbitmap.so "tier0 tier1 mathlib" bitmap || true
link_so libvtf.so "tier0 tier1 mathlib bitmap" vtf || true
link_so libscenefilecache.so "tier0 tier1 vstdlib" scenefilecache || true
link_so libbonesetup.so "tier0 tier1 mathlib vstdlib" bonesetup || true
link_so libchoreo.so "tier0 tier1 vstdlib" choreo || true
link_so libsoundsystem.so "tier0 tier1 mathlib vstdlib tier2" soundsystem || true
link_so libsoundsystem_lowlevel.so "tier0 tier1 vstdlib mathlib SDL2" soundsystem_lowlevel || true
link_so libmatsys_controls.so "tier0 tier1 mathlib vstdlib tier2 vgui vgui_controls SDL2" matsys_controls || true
link_so libvideocfg.so "tier0 tier1 vstdlib" videocfg || true
link_so libcrypto++.so "" cryptopp || true
link_so libquickhull.so "" quickhull || true
# (soundsystem glue is wired inside link_so via GLUE_SND_O)

# 3. Engine (+ protobuf messages + SDL2)
GENPROTO_OBJS=$(ls obj/genproto/*.o 2>/dev/null)
if [ -n "$GENPROTO_OBJS" ] && [ -f "$OUTDIR/libmathlib.so" ]; then
  echo "[link] libengine.so (engine + genproto)" | tee -a "$LOG"
  ENGINE_TAIL="-ldl -llog -lm -lc -lz -landroid -lEGL -lGLESv2 -lOpenSLES"
  ENGINE_BASE_OBJS=$(ls obj/engine/*.o 2>/dev/null)
  $CC $LFLAGS -Wl,-soname,"libengine.so" -o "$OUTDIR/libengine.so" obj/engine/*.o $GENPROTO_OBJS \
     $INTERFACES_O $STEAM_O $GLUE_O $GLUE_ENG_O \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf -lSDL2 -lbzip2 \
     $ENGINE_TAIL 2>>"$LOG" \
     && { echo "   OK: libengine.so" | tee -a "$LOG"; [ "${STRIP:-0}" = "1" ] && [ -n "${STRIPBIN:-}" ] && "$STRIPBIN" --strip-debug "$OUTDIR/libengine.so" || true; } || echo "   LINK FAILED: libengine.so" | tee -a "$LOG"
  record_link "libengine.so" "$ENGINE_BASE_OBJS $GENPROTO_OBJS $INTERFACES_O $STEAM_O $GLUE_O $GLUE_ENG_O" "tier0 tier1 tier2 vstdlib mathlib protobuf SDL2 bzip2" "$ENGINE_TAIL"
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
     $INTERFACES_O $STEAM_O $GLUE_O $GLUE_ENG_O \
     -L$OUTDIR -ltier0 -ltier1 -ltier2 -lvstdlib -lmathlib -lprotobuf -lSDL2 -lbzip2 \
     -ldl -llog -lm -lc -lz 2>>"$LOG" \
     && { echo "   OK: lib$GAMEDLL.so" | tee -a "$LOG"; [ "${STRIP:-0}" = "1" ] && [ -n "${STRIPBIN:-}" ] && "$STRIPBIN" --strip-debug "$OUTDIR/lib$GAMEDLL.so" || true; } || echo "   LINK FAILED: lib$GAMEDLL.so" | tee -a "$LOG"
  record_link "lib$GAMEDLL.so" "$GAMEOBJS $GENPROTO_OBJS $INTERFACES_O $STEAM_O $GLUE_O $GLUE_ENG_O" "tier0 tier1 tier2 vstdlib mathlib protobuf SDL2 bzip2" "-ldl -llog -lm -lc -lz"
done

# resolve every cross-lib reference into a real DT_NEEDED, then gate
auto_dep_rounds || true
und_gate || true

echo "=== linked results ===" | tee -a "$LOG"
ls -la "$OUTDIR" 2>/dev/null | tee -a "$LOG"

# count failures from the log and propagate a proper exit code
FAILS=$(grep -c "LINK FAILED" "$LOG" || true)
if [ "$FAILS" -gt 0 ]; then
  echo "link.sh: $FAILS library link(s) failed" | tee -a "$LOG"
  exit 1
fi
exit 0
