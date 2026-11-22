#!/bin/bash
# csARM — build the whole x86_64 (or arm64-v8a) shared-library set locally,
# the same module list the CI matrix uses.  No GitHub round trip.
#
#   usage: NDKROOT=/path/to/ndk test/local_build.sh [abi] [files-in-parallel]
#   out:   obj/<tag>/*.o  ->  build/link.sh  ->  out/*.so
#
# Modules build sequentially, each with $JOBS compiler processes in parallel.
# trybuild.sh skips objects that already exist, so re-running after editing a
# few files only recompiles those.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABI=${1:-x86_64}
JOBS=${2:-6}
NDKROOT=${NDKROOT:?NDKROOT must be set}
if [ "$ABI" = "x86_64" ]; then CC=x86_64-linux-android24-clang; else CC=aarch64-linux-android24-clang; fi
export NDKROOT CC JOBS
export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
cd "$R"

GAME_DEFS="DGAME_DLL=1 DCSTRIKE_DLL=1 DCSTRIKE15=1 DVERSION_SAFE_STEAM_API_INTERFACES=1 DPROTECTED_THINGS_ENABLE=1"
CLIENT_DEFS="DCLIENT_DLL=1 DCSTRIKE_CLIENT_DLL=1 DCSTRIKE_DLL=1 DCSTRIKE15=1 DGAMEUI_EMBEDDED=1 DGAMEUI_EXPORTS=1 DVERSION_SAFE_STEAM_API_INTERFACES=1 DUSE_ECONOMY_FEATURES=1"

DATA_MODULES="datacache/datacache.vpc soundemittersystem/soundemittersystem.vpc filesystem/filesystem_stdio.vpc inputsystem/inputsystem.vpc lists/launcher.txt tier3/tier3.vpc dmxloader/dmxloader.vpc bitmap/bitmap.vpc vtf/vtf.vpc scenefilecache/scenefilecache.vpc interfaces/interfaces.vpc vpklib/vpklib.vpc bonesetup/bonesetup.vpc kv3lib/kv3lib.vpc lists/choreo.txt lists/mathlib_extra.txt lists/libpng.txt soundsystem/soundsystem.vpc soundsystem/lowlevel/soundsystem_lowlevel.vpc materialsystem/shaderapiempty/shaderapiempty.vpc"

FAILED=""
build() {   # build <defs> <module...>
  local defs="$1"; shift
  local m
  for m in "$@"; do
    local tag; tag=$(basename "$m"); tag=${tag%.*}
    local before; before=$(date +%s)
    DEFX="$defs" bash build/trybuild.sh "$m" 2>&1 | tail -1 | sed "s/^/[$tag] /"
    [ "${PIPESTATUS[0]}" != "0" ] && FAILED="$FAILED $m"
  done
}

echo "== $ABI with $CC, $JOBS parallel compiles per module =="
build "" tier0/tier0.vpc tier1/tier1.vpc tier2/tier2.vpc vstdlib/vstdlib.vpc \
         mathlib/mathlib.vpc appframework/appframework.vpc utils/bzip2/bzip2.vpc
build "" lists/protobuf25.txt
build "" lists/togl.txt lists/shaderapidx9.txt lists/stdshader_dx9.txt
build "" engine/engine.vpc videocfg/videocfg.vpc vgui2/matsys_controls/matsys_controls.vpc \
         lists/cryptopp.txt lists/quickhull.txt
build "" materialsystem/materialsystem.vpc materialsystem/shaderlib/shaderlib.vpc \
         studiorender/studiorender.vpc vguimatsurface/vguimatsurface.vpc particles/particles.vpc raytrace/raytrace.vpc
build "" vgui2/src/vgui_dll.vpc vgui2/vgui_controls/vgui_controls.vpc vgui2/vgui_surfacelib/vgui_surfacelib.vpc
# shellcheck disable=SC2086
build "" $DATA_MODULES
build "" responserules/runtime/responserules_runtime.vpc localize/localize.vpc
build "$GAME_DEFS"   game/server/server_cstrike15.vpc
build "$CLIENT_DEFS" game/client/client_cstrike15.vpc

echo "== compile errors =="
if compgen -G "err/*/*.log" > /dev/null; then
  hits=$(grep -l "error:" err/*/*.log 2>/dev/null | head -10)
  if [ -n "$hits" ]; then echo "$hits"; else echo "none"; fi
fi
[ -n "$FAILED" ] && echo "FAILED modules:$FAILED"

echo "== linking =="
bash build/link.sh 2>&1 | grep -E "LINK FAILED|\[link\] lib(engine|client|server)\.so" | head -6
bash build/build_main.sh "$R" "$R/.cache" 2>&1 | tail -1
echo "== out: $(ls out/*.so 2>/dev/null | wc -l) shared libraries =="
