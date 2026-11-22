#!/bin/bash
# csARM — local emulator control (x86_64 AOSP ATD, KVM) for fast iteration.
#
#   test/local_emu.sh up|down|status
#
# env: ANDROID_HOME (default ~/android-sdk), AVD_NAME=csarm, DATA_SIZE=16G
#
# Why this exists: `avdmanager create avd` writes
#       disk.dataPartition.path=<temp>
# and current emulator builds then boot with NO /data at all — zygote
# crash-loops with "Error creating cache dir /data/dalvik-cache/x86_64" and
# sys.boot_completed never flips.  The script rewrites that key to a real
# image before the first boot, which is what CI's runner image already has.
set -uo pipefail
SDK=${ANDROID_HOME:-$HOME/android-sdk}
export ANDROID_HOME=$SDK ANDROID_SDK_ROOT=$SDK
ADB=$SDK/platform-tools/adb
EMU=$SDK/emulator/emulator
AVD=${AVD_NAME:-csarm}
AVD_HOME=${ANDROID_AVD_HOME:-$HOME/.android/avd}
IMG=${IMG:-system-images;android-30;aosp_atd;x86_64}
DATA_SIZE=${DATA_SIZE:-16G}
PIDF=${PIDF:-$PWD/.local/emu.pid}
LOG=${LOG:-$PWD/.local/emulator.log}
mkdir -p "$AVD_HOME" "$(dirname "$LOG")"

up() {
  if "$ADB" devices 2>/dev/null | grep -q "emulator-5554.*device"; then
    echo "emulator-5554 already running"; return 0
  fi
  if [ ! -f "$AVD_HOME/$AVD.ini" ]; then
    echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n "$AVD" -k "$IMG" -d pixel_4 --force >/dev/null
  fi
  sed -i "s|^disk.dataPartition.path=.*|disk.dataPartition.path=userdata-qemu.img|; s|^disk.dataPartition.size=.*|disk.dataPartition.size=$DATA_SIZE|" \
    "$AVD_HOME/$AVD.avd/config.ini"
  ( ANDROID_AVD_HOME="$AVD_HOME" nohup "$EMU" -avd "$AVD" \
      -no-window -no-audio -no-boot-anim -no-snapshot \
      -gpu swiftshader_indirect -accel on -memory 3072 -cores 4 -port 5554 \
      ${WIPE:+-wipe-data} > "$LOG" 2>&1 & echo $! > "$PIDF" )
  for _ in $(seq 1 100); do
    B=$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
    [ "$B" = "1" ] && { echo "booted"; "$ADB" -s emulator-5554 root >/dev/null 2>&1; sleep 2; return 0; }
    sleep 3
  done
  echo "emulator did not boot — tail of $LOG:"; tail -20 "$LOG"; return 1
}

down() {
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
  "$ADB" -s emulator-5554 emu kill >/dev/null 2>&1
  pkill -f "qemu-system-x86_64.*-avd $AVD" 2>/dev/null
  sleep 2; "$ADB" devices
}

status() { "$ADB" devices; }

case "${1:-up}" in
  up|start) up ;;
  down|stop|kill) down ;;
  status) status ;;
  *) echo "usage: $0 up|down|status"; exit 2 ;;
esac
