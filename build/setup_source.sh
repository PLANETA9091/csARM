#!/bin/bash
# csARM — fetch pristine cstrike15_src from public mirror and apply our port patches
# usage: setup_source.sh [workspace_root]  (default = repo root)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
MIRROR=${MIRROR:-https://github.com/perilouswithadollarsign/cstrike15_src.git}
SRC="$R/c15"

if [ -d "$SRC/.git" ] && [ -f "$SRC/.git/info/sparse-checkout" ]; then
  echo "c15 already present, skipping clone"
else
  rm -rf "$SRC"
  git clone --depth 1 --filter=blob:none --no-checkout --branch master "$MIRROR" "$SRC"
  cd "$SRC"
  # sparse checkout — only modules we need (61% of repo)
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
/thirdparty/SDL2/
/thirdparty/libpng-1.5.2/
/thirdparty/quickhull/
/thirdparty/telemetry/
/tier0/
/tier1/
/tier2/
/vgui2/
/vguimatsurface/
/vgui_controls/
/vstdlib/
/vpc_scripts/
/utils/common/
/utils/bzip2/
EOF
  git checkout master 2>&1 | tail -1
fi

cd "$SRC"
echo "Applying patches..."
git apply --whitespace=nowarn "$REPO_DIR/patches/all_patches.diff" || echo "PATCH APPLY: some hunks may already be applied"
echo "Copying extra files..."
cp -v "$REPO_DIR/patches/extras/gameeventlistener.h" "$SRC/game/shared/gameeventlistener.h"
cp -v "$REPO_DIR/patches/extras/IVGUI.h" "$SRC/public/vgui/IVGUI.h"
cp -v "$REPO_DIR/patches/extras/unicode_native.h" "$SRC/tier1/unicode_native.h"
if [ ! -d "$SRC/thirdparty/sse2neon" ]; then
  cp -rv "$REPO_DIR/patches/extras/sse2neon" "$SRC/thirdparty/sse2neon"
fi
echo "Source setup complete: $SRC"
