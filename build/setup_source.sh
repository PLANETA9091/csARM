#!/bin/bash
# csARM — fetch pristine cstrike15_src from public mirror and apply our port patches
# usage: setup_source.sh [workspace_root]  (default = repo root)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
MIRROR=${MIRROR:-https://github.com/perilouswithadollarsign/cstrike15_src.git}
SRC="$R/c15"
PINNED_SHA=f82112a2388b841d72cb62ca48ab1846dfcc11c8
PATTERNS="$REPO_DIR/build/sparse-patterns.txt"

# Completeness gate: every directory the module build compiles/links from must
# exist and be non-empty.  Guards against a STALE actions/cache (a cache saved
# before a newly added module dir entered the sparse list): the 2026-10-30 run
# failed exactly this way — videocfg/tier3/vpklib/soundsystem/... "produced 0
# objects" because the restored 80 MB cache predated those dirs and
# `git checkout -q HEAD -- <dirs>` silently did nothing.
NEEDED_DIRS="appframework bitmap bonesetup common datacache dmxloader engine external filesystem gcsdk inputsystem interfaces launcher materialsystem mathlib public responserules localize scaleformui scenefilecache soundemittersystem soundsystem studiorender tier0 tier1 tier2 tier3 vgui2 vguimatsurface vstdlib videocfg vpc_scripts vpklib game/client game/server game/shared utils/bzip2 thirdparty/SDL2 thirdparty/protobuf-2.5.0 thirdparty/telemetry thirdparty/quickhull"

check_complete() {
  MISSING=""
  local d
  for d in $NEEDED_DIRS; do
    if [ ! -d "$SRC/$d" ] || [ -z "$(ls -A "$SRC/$d" 2>/dev/null)" ]; then
      MISSING="$MISSING $d"
    fi
  done
  [ -z "$MISSING" ]
}

apply_sparse() {
  # NOTE ordering: `git sparse-checkout init` may (re)write the pattern file,
  # so our patterns are copied AFTER it.
  git sparse-checkout init --no-cone 2>/dev/null || true
  cp "$PATTERNS" "$(git rev-parse --absolute-git-dir)/info/sparse-checkout"
}

do_clone() {
  FRESH=1
  rm -rf "$SRC"
  git clone --filter=blob:none --no-checkout "$MIRROR" "$SRC"
  (
    cd "$SRC"
    apply_sparse
    git checkout -q "$PINNED_SHA" 2>/dev/null || git checkout -q origin/master || git checkout -q master
    echo "source commit: $(git rev-parse HEAD)"
  )
}

FRESH=0
if [ -d "$SRC/.git" ] && check_complete; then
  echo "c15 already present and complete, skipping clone"
elif [ -d "$SRC/.git" ]; then
  echo "cached c15 missing dirs:$MISSING"
  echo " -> re-materializing from sparse patterns (lazy blob fetch)"
  ( cd "$SRC" && apply_sparse && git read-tree -mu HEAD ) || true
  if check_complete; then
    echo "re-materialized OK"
  else
    echo " -> read-tree insufficient (still missing:$MISSING), forcing fresh sparse clone"
    do_clone
  fi
else
  do_clone
fi

# Post-clone/cached verification: a missing dir here silently becomes a
# "module X produced 0 objects" failure minutes later — fail fast instead.
if ! check_complete; then
  echo "sparse tree incomplete after setup:$MISSING -> read-tree retry"
  ( cd "$SRC" && apply_sparse && git read-tree -mu HEAD ) || true
  check_complete || { echo "FATAL: still missing:$MISSING (sparse patterns vs source tree mismatch)"; exit 1; }
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

# csARM engine boot/frame proof (separate diff: applies after all_patches).
# The boot diff is REGENERATED whenever the probe set changes, so a cached
# tree can hold any older revision of it (or none).  Restore the files the
# boot diff owns (all_patches does not touch them — verified: only
# engine/sys_dll2.cpp overlaps, and the boot hunks there sit in regions
# all_patches never modifies) to pristine, drop the generated header, and
# apply the current revision cleanly.
BOOT_PRISTINE="engine/sys_engine.cpp appframework/AppSystemGroup.cpp launcher/launcher.cpp"
if git apply --whitespace=nowarn --reverse --check "$REPO_DIR/patches/extras/csarm_boot.diff" 2>/dev/null; then
  echo "csarm_boot.diff already applied"
else
  echo "csarm_boot.diff revision change -> normalizing probe files"
  git checkout -f -- $BOOT_PRISTINE 2>/dev/null || git checkout -- $BOOT_PRISTINE || true
  rm -f "$SRC/common/csarm_log.h"
  git apply --whitespace=nowarn "$REPO_DIR/patches/extras/csarm_boot.diff" || { echo "csarm_boot.diff APPLY FAILED"; exit 1; }
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
