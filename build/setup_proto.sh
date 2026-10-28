#!/bin/bash
# csARM — regenerate genproto with protobuf 2.5.0 protoc
# Valve's cstrike15 code was written against protobuf 2.5.0 (bundled in
# thirdparty/protobuf-2.5.0), so generated code must match its API.
# usage: setup_proto.sh [workspace_root] [protoc-cache-dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
SRC="$R/c15"
OUT="$R/genproto"

mkdir -p "$CACHE" "$OUT"

# --- build protoc 2.5.0 for host (cached) ---
PROTOC="$CACHE/protoc25/bin/protoc"
if [ ! -x "$PROTOC" ]; then
  echo "building protoc 2.5.0 (host)..."
  cd "$CACHE"
  if [ ! -d protobuf-2.5.0 ]; then
    curl -sL -o pb25.tar.bz2 https://github.com/protocolbuffers/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.bz2
    tar xjf pb25.tar.bz2
  fi
  cd protobuf-2.5.0
  ./configure --disable-shared --prefix="$CACHE/protoc25" \
    CXXFLAGS="-O1 -std=gnu++03 -Wno-error" CFLAGS="-O1" > /dev/null
  make -C src protoc -j"$(nproc)" > /dev/null
  make -C src install-exec > /dev/null
  test -x "$PROTOC"
  echo "protoc 2.5.0 ready: $PROTOC"
else
  echo "using cached protoc: $PROTOC"
fi
"$PROTOC" --version

# --- locate Valve .proto files in c15 ---
# expected: netmessages, network_connection, base_gcmessages, steammessages,
#           engine_gcmessages, cstrike15_gcmessages, cstrike15_usermessages
PROTOS=$(find "$SRC/common" "$SRC/engine" "$SRC/game/shared" "$SRC/gcsdk" -name '*.proto' 2>/dev/null \
  | grep -v "_ps3.proto" | grep -v "thirdparty" | sort || true)
if [ -z "$PROTOS" ]; then
  echo "ERROR: no .proto files found in c15 (sparse checkout updated? run setup_source.sh)"; exit 1
fi
echo "found protos:"; echo "$PROTOS"

# --- generate (flat into genproto/, includes resolved against c15 + protoc std) ---
# NOTE: per-file dir roots come FIRST so protoc maps each proto flat into OUT;
# $SRC root last would create common/, game/... subdirs in OUT.
INC_ARGS=""
# most-specific roots first (game/shared/cstrike15 BEFORE game/shared) so
# protoc maps every proto FLAT into OUT
for d in "$SRC/common" "$SRC/engine" "$SRC/game/shared/cstrike15" "$SRC/game/shared" "$SRC/gcsdk" "$SRC/gcsdk/steamextra" "$SRC/public"; do
  [ -d "$d" ] && INC_ARGS="$INC_ARGS -I$d"
done
[ -d "$SRC/thirdparty/protobuf-2.5.0/src" ] && INC_ARGS="$INC_ARGS -I$SRC/thirdparty/protobuf-2.5.0/src"
[ -d "$SRC" ] && INC_ARGS="$INC_ARGS -I$SRC"
rm -rf "$OUT"/common "$OUT"/game "$OUT"/gcsdk "$OUT"/cstrike15 "$OUT"/*.pb.h "$OUT"/*.pb.cc
for f in $PROTOS; do
  echo "protoc $(basename "$f")"
  "$PROTOC" $INC_ARGS --cpp_out="$OUT" "$f"
done

echo "generated:"; ls "$OUT"/*.pb.h | xargs -n1 basename
