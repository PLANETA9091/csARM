#!/bin/bash
# csARM — turn the raw "CSARM_EXIT_BT nn <lib>.so+<off>" / tombstone frames in a
# logcat dump into file:line symbols, using the unstripped libs from the build.
#
#   usage: test/symbolize.sh <libs-dir> <logcat.txt>
#   env:   ADDR2LINE (default: NDK r27d llvm-addr2line)
set -uo pipefail
LIBS=${1:?libs dir (e.g. android/libs/x86_64)}
LOG=${2:?logcat/console dump}
A2L=${ADDR2LINE:-$PWD/.local/android-ndk-r27d/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-addr2line}
[ -x "$A2L" ] || A2L=$(command -v llvm-addr2line) || { echo "addr2line not found (set ADDR2LINE=)"; exit 1; }

# CSARM_EXIT_BT nn /data/app/.../lib/x86_64/libengine.so+a03387
# tombstone     #03 pc 000000000009ee1c  .../libshaderapidx9.so (CShaderAPIDx8::ClearBuffers+204)
grep -ahoE "CSARM_EXIT_BT [0-9]+ .*/lib[A-Za-z0-9_+.-]+\.so\+[0-9a-f]+" "$LOG" |
  sed -E 's/.*BT ([0-9]+) .*\/(lib[A-Za-z0-9_+.-]+\.so)\+([0-9a-f]+)/\1 \2 \3/' |
  while read -r n lib off; do
    f="$LIBS/$lib"; [ -f "$f" ] || continue
    printf '%2s %-20s %-8s %s\n' "$n" "$lib" "$off" "$("$A2L" -f -C -i -e "$f" "0x$off" 2>/dev/null | paste -sd' | ' -)"
  done
grep -ahoE "#[0-9]+ pc [0-9a-f]+  [^ ]*/lib[A-Za-z0-9_+.-]+\.so" "$LOG" |
  sed -E 's/#([0-9]+) pc [0-9a-f]+ +.*\/(lib[A-Za-z0-9_+.-]+\.so)/\1 \2 0/' |
  sort -u | while read -r n lib _; do
    echo "  (tombstone frame #$n in $lib — offsets are tombstone-relative)"
  done
