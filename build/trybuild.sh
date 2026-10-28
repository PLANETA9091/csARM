#!/bin/bash
# csARM — build one VPC module for Android aarch64
# usage: trybuild.sh <vpc-rel-path>   e.g. tier0/tier0.vpc
# env: R (workspace root, default = script dir/..), CC, OPT, JOBS, DEFX, INCX, TIMEOUT
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R=${R:-$(dirname "$SCRIPT_DIR")}
cd "$R"
PROJ="$1"
TAG=$(basename "$PROJ" .vpc)
OUT="$R/obj/$TAG"; ERR="$R/err/$TAG"; mkdir -p "$OUT" "$ERR"
LST="$R/lists/$TAG.txt"; mkdir -p "$R/lists"
python3 "$SCRIPT_DIR/vpcmini.py" c15 "$PROJ" 2>/dev/null | grep -E '\.(cpp|cc|cxx|c)$' | grep -vE 'openal|voice_record_dsound|voice_mixer_controls' > "$LST"

VDEFS=$(python3 "$SCRIPT_DIR/vpcmini.py" c15 "$PROJ" --defs 2>/dev/null | tr ';' '\n' | grep -vE '\$|\(|\)|^$|^DEBUG$|^_DEBUG$|^NDEBUG$' | sort -u | sed 's/^/-D/' | tr '\n' ' ' 2>/dev/null)
VINC=$(python3 "$SCRIPT_DIR/vpcmini.py" c15 "$PROJ" --inc 2>/dev/null | grep -vE '\$|\(' | while read -r i; do [ -d "c15/$i" ] && printf ' -I c15/%s' "$i"; done 2>/dev/null)

CC=${CC:-aarch64-linux-android27-clang}
OPT=${OPT:--O1}
JOBS=${JOBS:-4}
NDKROOT=${NDKROOT:-$R/../ndk}

INC="-I "$SCRIPT_DIR/glshim" -I pbshim -I "${PBSRC:-$R/thirdparty/protobuf/include}" -I "$R/thirdparty/protobuf/include/utf8_range" -I c15 -I c15/public -I c15/public/tier0 -I c15/public/tier1 -I c15/public/tier2 -I c15/common -I c15/tier0 -I c15/tier1 -I c15/tier2 -I c15/vstdlib -I c15/mathlib -I c15/thirdparty/telemetry/include -I c15/thirdparty -I c15/public/mathlib -I c15/external -I c15/public/steam -I c15/thirdparty/SDL2 -I c15/thirdparty/sse2neon -I genproto -I pbshim -I c15/gcsdk -I c15/gcsdk/steamextra/tier1 -I c15/gcsdk/steamextra -I c15/game/shared -I c15/game/shared/cstrike15 -I c15/game/shared/econ -I c15/game/client -I c15/game/server -I c15/engine/audio/public -I c15/engine/audio -I c15/engine/audio/private -I c15/external/crypto++-5.61 -I c15/thirdparty/quickhull -I c15/engine -I c15/soundemittersystem -I "${FTINC:-$R/thirdparty/freetype/include}" -I c15/public/vgui_controls -I c15/game/client/cstrike15 -I c15/game/client/cstrike15/gameui -I c15/game/client/cstrike15/Scaleform -I c15/game/client/game_controls"
DEFX=${DEFX:-}
INCX=${INCX:-}
DEF="-std=gnu++17 -include $R/build/protocompat.h -Wno-narrowing -Wno-register -DDX_TO_GL_ABSTRACTION -DCSARM_GL_SHIM -DX64BITS -DPOSIX=1 -DLINUX=1 -D_LINUX=1 -DGNUC=1 -DPLATFORM_64BITS=1 -DCOMPILER_GCC=1 -D_POSIX=1 -D__ANDROID__=1 -DANDROID=1 -DENGINE_DLL=1 -DUSE_SDL=1 -Dpthread_yield=sched_yield -Dstricmp=strcasecmp -D_stricmp=strcasecmp -Dstrnicmp=strncasecmp -D_strnicmp=strncasecmp $DEFX"
INC="$INC $INCX $VINC"
DEF="$DEF $VDEFS"

# Per-module header resolution: client.h lives in BOTH engine/ and game/server/.
# Engine+client modules need engine/client.h (CClientState); server needs its own.
case "$TAG" in
  server*) INC="-I c15/game/server $INC" ;;
  *)       INC="-I c15/engine $INC" ;;
esac

export R CC INC DEF OUT ERR OPT
build_one() {
  local F="$1"
  [ -z "$F" ] && return 0
  [ -f "$R/c15/$F" ] || return 0
  local obj="$OUT/$(echo "$F" | tr '/' '_').o"
  [ -s "$obj" ] && return 0
  local st="$DEF"; case "$F" in *.c) st="${DEF/-std=gnu++17/-std=gnu11}" ;; esac
  timeout ${TIMEOUT:-200} $CC -c -fPIC $OPT -w $INC $st "$R/c15/$F" -o "$obj" > "$ERR/$(echo "$F" | tr '/' '_').log" 2>&1
}
export -f build_one

grep -v '^$' "$LST" | xargs -P "$JOBS" -n1 bash -c 'build_one "$0"'

ok=$(ls "$OUT" 2>/dev/null | wc -l)
fail=0; for f in "$ERR"/*.log; do grep -qE 'error:' "$f" 2>/dev/null && fail=$((fail+1)); done
echo "TAG=$TAG ok=$ok fail=$fail"
