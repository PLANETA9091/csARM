#!/bin/bash
# csARM — fetch pristine cstrike15_src from public mirror and apply our port patches
# usage: setup_source.sh [workspace_root]  (default = repo root)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
MIRROR=${MIRROR:-https://github.com/perilouswithadollarsign/cstrike15_src.git}
SRC="$R/c15"

FRESH=0
if [ -d "$SRC/.git" ] && [ -f "$SRC/.git/info/sparse-checkout" ]; then
  echo "c15 already present, skipping clone"
else
  FRESH=1
  rm -rf "$SRC"
  PINNED_SHA=f82112a2388b841d72cb62ca48ab1846dfcc11c8
  git clone --filter=blob:none --no-checkout "$MIRROR" "$SRC"
  cd "$SRC"
  # sparse checkout FIRST (before any checkout) — only modules we need (61% of repo)
  cat > .git/info/sparse-checkout <<'EOF'
/*
!/*/
/game/
!/game/*/
/thirdparty/
!/thirdparty/*/
/utils/
!/utils/*/
/appframework/
/common/
/datacache/
/engine/
/external/
/filesystem/
/game/client/
/game/server/
/game/shared/
/gcsdk/
/materialsystem/
/mathlib/
/public/
/scaleformui/
/soundemittersystem/
/studiorender/
/inputsystem/
/launcher/
/thirdparty/SDL2/
/thirdparty/libpng-1.5.2/
/thirdparty/protobuf-2.5.0/
/thirdparty/zlib-1.2.5/
/thirdparty/quickhull/
/thirdparty/telemetry/
/tier0/
/tier1/
/tier2/
/tier3/
/vgui2/
/vguimatsurface/
/vgui_controls/
/vstdlib/
/vpc_scripts/
/utils/common/
/utils/bzip2/
/interfaces/
/dmxloader/
/bitmap/
/vtf/
/scenefilecache/
/vpklib/
/bonesetup/
/soundsystem/
/videocfg/
EOF
  git sparse-checkout init --no-cone 2>/dev/null || true
  cp .git/info/sparse-checkout "$(git rev-parse --git-dir)/info/sparse-checkout" 2>/dev/null || true
  git sparse-checkout list 2>/dev/null | head -3 || true
  git checkout -q "$PINNED_SHA" 2>/dev/null || git checkout -q origin/master || git checkout -q master
  echo "source commit: $(git rev-parse HEAD)"
fi

# Sparse patterns may have gained new dirs (launcher/, inputsystem/, tier3/,
# dmxloader/, bitmap/, vtf/, interfaces/, scenefilecache/) since the cached
# tree was materialized — extend the sparse file and materialize (idempotent).
NEW_SPARSE_DIRS=""
for d in launcher inputsystem tier3 dmxloader bitmap vtf interfaces scenefilecache vpklib bonesetup soundsystem videocfg; do
  [ -d "$SRC/$d" ] || NEW_SPARSE_DIRS="$NEW_SPARSE_DIRS $d"
done
if [ -d "$SRC/.git" ] && [ -n "$NEW_SPARSE_DIRS" ]; then
  echo "Refreshing sparse checkout for:$NEW_SPARSE_DIRS"
  SP="$SRC/.git/info/sparse-checkout"
  [ -f "$SP" ] || SP="$(git -C "$SRC" rev-parse --git-dir)/info/sparse-checkout"
  touch "$SP"
  for d in $NEW_SPARSE_DIRS; do grep -q "^/$d/$" "$SP" || echo "/$d/" >> "$SP"; done
  (cd "$SRC" && git checkout -q HEAD -- $NEW_SPARSE_DIRS 2>/dev/null || true)
fi

cd "$SRC"
echo "Applying patches (FRESH=$FRESH)..."
if [ "$FRESH" = "1" ]; then
  git apply --whitespace=nowarn "$REPO_DIR/patches/all_patches.diff" || { echo "PATCH APPLY FAILED"; exit 1; }
else
  if git apply --whitespace=nowarn --reverse --check "$REPO_DIR/patches/all_patches.diff" 2>/dev/null; then
    echo "PATCH APPLY: current patches already applied"
  elif git apply --whitespace=nowarn --check "$REPO_DIR/patches/all_patches.diff" 2>/dev/null; then
    git apply --whitespace=nowarn "$REPO_DIR/patches/all_patches.diff"
  else
    # Patch-state mismatch (e.g. cached c15 has an older patch revision):
    # reset tracked files + drop untracked extras, then apply the current diff.
    echo "PATCH STATE MISMATCH -> resetting source tree to pristine"
    git checkout -- .
    git clean -fdq
    git apply --whitespace=nowarn "$REPO_DIR/patches/all_patches.diff" || { echo "PATCH APPLY FAILED"; exit 1; }
  fi
fi

# csARM engine boot/frame proof (separate diff: applies after all_patches)
if git apply --whitespace=nowarn --reverse --check "$REPO_DIR/patches/extras/csarm_boot.diff" 2>/dev/null; then
  echo "csarm_boot.diff already applied"
elif git apply --whitespace=nowarn --check "$REPO_DIR/patches/extras/csarm_boot.diff" 2>/dev/null; then
  git apply --whitespace=nowarn "$REPO_DIR/patches/extras/csarm_boot.diff" || { echo "csarm_boot.diff APPLY FAILED"; exit 1; }
else
  echo "csarm_boot.diff does not apply (context drift?)"; exit 1
fi

echo "Copying extra files..."
cp -v "$REPO_DIR/patches/extras/gameeventlistener.h" "$SRC/game/shared/gameeventlistener.h"
cp -v "$REPO_DIR/patches/extras/IVGUI.h" "$SRC/public/vgui/IVGUI.h"
cp -v "$REPO_DIR/patches/extras/unicode_native.h" "$SRC/tier1/unicode_native.h"
cp -v "$REPO_DIR/patches/extras/spawn_helper_nut.h" "$SRC/game/server/spawn_helper_nut.h"
cp -v "$REPO_DIR/patches/extras/vscript_server_nut.h" "$SRC/game/server/vscript_server_nut.h"
rm -rf "$SRC/thirdparty/sse2neon"
cp -rv "$REPO_DIR/patches/extras/sse2neon" "$SRC/thirdparty/sse2neon"
echo "Source setup complete: $SRC"
