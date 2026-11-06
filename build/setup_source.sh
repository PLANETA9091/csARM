#!/bin/bash
# csARM — fetch the cstrike15_src 2019 partner tree and apply the port patch
# usage: setup_source.sh [workspace_root]  (default = repo root)
#
# 2019 retarget (2026-11-03):
#   - main tree: RileyKun/cstrike15_src-2019 @ a4c7aaea (2019 partner build,
#     NOT the 2018 build seen previously)
#   - thirdparty/ (SDL2 headers, protobuf-2.5.0, telemetry, quickhull,
#     libpng, zlib) is absent from the 2019 dump — sparse-cloned from the
#     2018 mirror (perilouswithadollarsign/cstrike15_src @ f82112a) and
#     copied into c15/thirdparty
#   - patches/all_patches.diff is ONE consolidated diff (port + boot probes +
#     sdlmgr GL gate + tier2 guards) regenerated against the 2019 base; the
#     old multi-diff layering (all_patches + csarm_boot + csarm_sdlmgr_gl +
#     csarm_tier2_connect) is gone together with its normalization dance
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
MIRROR=${MIRROR:-https://github.com/RileyKun/cstrike15_src-2019.git}
PINNED_SHA=a4c7aaea259319aca272839f688a3f4d9fe1cb2c
OLD_MIRROR=${OLD_MIRROR:-https://github.com/perilouswithadollarsign/cstrike15_src.git}
OLD_SHA=f82112a2388b841d72cb62ca48ab1846dfcc11c8
SRC="$R/c15"
TPCACHE="$R/.cache/c15-thirdparty"
PATTERNS="$REPO_DIR/build/sparse-patterns.txt"
TP_PATTERNS="$REPO_DIR/build/thirdparty-patterns.txt"
TP_DIRS="SDL2 libpng-1.5.2 protobuf-2.5.0 zlib-1.2.5 quickhull telemetry JSON_parser"

# Completeness gate: every directory the module build compiles/links from must
# exist and be non-empty.  Guards against a STALE actions/cache (a cache saved
# before a newly added module dir entered the sparse list): the 2026-10-30 run
# failed exactly this way — videocfg/tier3/vpklib/soundsystem/... "produced 0
# objects" because the restored cache predated those dirs and
# `git checkout -q HEAD -- <dirs>` silently did nothing.
# NOTE: thirdparty/* is NOT part of the 2019 git tree (copied from the 2018
# mirror below), so the post-clone gate only covers the main tree.
NEEDED_DIRS="particles raytrace resourcefile appframework bitmap bonesetup common datacache dmxloader engine external filesystem gcsdk inputsystem interfaces launcher materialsystem mathlib public responserules localize scaleformui scenefilecache soundemittersystem soundsystem studiorender tier0 tier1 tier2 tier3 togl vgui2 vguimatsurface vstdlib videocfg vpc_scripts vpklib game/client game/server game/shared utils/bzip2"
NEEDED_TP_DIRS="thirdparty/SDL2 thirdparty/protobuf-2.5.0 thirdparty/telemetry thirdparty/quickhull"

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

check_tp() {
  MISSING_TP=""
  local d
  for d in $NEEDED_TP_DIRS; do
    if [ ! -d "$SRC/$d" ] || [ -z "$(ls -A "$SRC/$d" 2>/dev/null)" ]; then
      MISSING_TP="$MISSING_TP $d"
    fi
  done
  [ -z "$MISSING_TP" ]
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
    git checkout -q "$PINNED_SHA" 2>/dev/null || git checkout -q origin/main || git checkout -q main || git checkout -q origin/master || git checkout -q master
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

# --- thirdparty: the 2019 dump has none; take it from the 2018 mirror -----
if [ ! -d "$TPCACHE/.git" ]; then
  echo "cloning 2018 mirror (thirdparty-only sparse) -> $TPCACHE"
  rm -rf "$TPCACHE"
  git clone --filter=blob:none --no-checkout "$OLD_MIRROR" "$TPCACHE"
  (
    cd "$TPCACHE"
    git sparse-checkout init --no-cone 2>/dev/null || true
    cp "$TP_PATTERNS" "$(git rev-parse --absolute-git-dir)/info/sparse-checkout"
    git checkout -q "$OLD_SHA" 2>/dev/null || git checkout -q origin/master || git checkout -q master
    echo "thirdparty source commit: $(git rev-parse HEAD)"
  )
fi
mkdir -p "$SRC/thirdparty"
for d in $TP_DIRS; do
  if [ ! -d "$TPCACHE/thirdparty/$d" ] || [ -z "$(ls -A "$TPCACHE/thirdparty/$d" 2>/dev/null)" ]; then
    echo "FATAL: thirdparty/$d missing in the 2018-mirror sparse checkout"; exit 1
  fi
  rm -rf "$SRC/thirdparty/$d"
  cp -r "$TPCACHE/thirdparty/$d" "$SRC/thirdparty/$d"
done
check_tp || { echo "FATAL: thirdparty copy incomplete:$MISSING_TP"; exit 1; }

# --- patches: ONE consolidated diff, deterministic --------------------------
cd "$SRC"
if git apply --whitespace=nowarn --reverse --check "$REPO_DIR/patches/all_patches.diff" 2>/dev/null; then
  echo "PATCH APPLY: current patches already applied"
else
  echo "Applying patches (FRESH=$FRESH)..."
  # Reset tracked files to pristine; drop untracked strays.  thirdparty/ is
  # untracked BY DESIGN (copied from the 2018 mirror, not part of the 2019
  # git tree) — exclude it from the clean and re-copy it fresh so the diff
  # always applies onto the exact thirdparty revision it was generated with.
  # run #181 lesson: `git checkout -q -- . 2>/dev/null || true` can silently
  # no-op on a stale blobless-clone cache (missing pristine blobs), leaving
  # patched content in the worktree; the forward apply then fails for every
  # hunk whose context touches line 1 and the failure is opaque.  Force the
  # checkout, VERIFY pristine-ness, and fall back to a fresh sparse re-clone
  # instead of a confusing "patch does not apply" cascade.
  git checkout -q -f -- . || git checkout -q -f HEAD -- . || true
  git clean -fdq -e thirdparty
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "c15 not pristine after reset (stale partial-clone cache) -> fresh re-clone"
    do_clone
  fi
  for d in $TP_DIRS; do
    rm -rf "thirdparty/$d"
    cp -r "$TPCACHE/thirdparty/$d" "thirdparty/$d"
  done
  git apply --whitespace=nowarn "$REPO_DIR/patches/all_patches.diff" || { echo "PATCH APPLY FAILED"; exit 1; }
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
