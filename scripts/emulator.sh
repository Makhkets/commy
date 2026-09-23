#!/usr/bin/env bash
#
# A light Android emulator for a weak machine: headless, two cores, a 720p
# screen, no cameras, no audio, no animations.
#
#   scripts/emulator.sh create [avd] [image]   # e.g. commy_lite "system-images;android-36;google_apis;x86_64"
#   scripts/emulator.sh start  [avd]           # boots headless, waits for it, tunes it
#   scripts/emulator.sh stop
#
# Built for the owner's machine — a two-core Pentium with 32 GB — where the
# stock AVD (1080p, 4 cores' worth of rendering in a window) left nothing for a
# build. The savings are in what the emulator draws, not in memory: the host
# has plenty of RAM, and a guest that swaps is slower, not lighter.
#
#   -no-window            nothing is rendered on the host
#   -gpu swiftshader_indirect   the only renderer that works without a window
#   720x1600 @ 280 dpi    the same 411 dp wide phone as a Pixel, 2.25× fewer pixels
#   -cores 2              leaves the other two threads to Gradle and Dart
#   animations off        the UI settles in one frame instead of 300 ms
#
# Screenshots are `adb exec-out screencap -p > shot.png`; taps are
# `adb shell input tap X Y`, or by label through `adb shell uiautomator dump`
# (Flutter exposes its semantics labels there).
#
# Which image. google_apis images are rootable (`adb root`) and ship tcpdump
# and iptables — which is what the leak checklist runs on — and include ARM
# translation, so the arm-only release APK installs too (slowly). AOSP ATD
# images are the lightest there are and good for a second API level; they
# have neither Google services nor, on API 30, a launcher worth the name.
# Nothing is downloaded here: install an image with
#   sdkmanager "system-images;android-36;google_apis;x86_64"
#
# The app itself is best built for the emulator's ABI, which is faster than
# translation and still a release build:
#   cd apps/commy && fvm flutter build apk --release --target-platform android-x64

set -euo pipefail

readonly SDK="${ANDROID_HOME:-${HOME}/Android/Sdk}"
readonly AVD_HOME="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
readonly LOG_DIR="${TMPDIR:-/tmp}"

die() { printf '\n\033[31merror:\033[0m %s\n\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

adb() { "${SDK}/platform-tools/adb" "$@"; }

create() {
  local name="${1:-commy_lite}"
  local image="${2:-system-images;android-36;google_apis;x86_64}"
  local dir="${SDK}/${image//;//}"
  [[ -d "${dir}" ]] || die "${image} is not installed.
   sdkmanager \"${image}\""
  local avdmanager="${SDK}/cmdline-tools/latest/bin/avdmanager"
  [[ -x "${avdmanager}" ]] || die "avdmanager not found under ${SDK}/cmdline-tools/latest."
  echo no | "${avdmanager}" create avd -n "${name}" -k "${image}" -d pixel_6 --force >/dev/null
  local config="${AVD_HOME}/${name}.avd/config.ini"
  [[ -f "${config}" ]] || die "avdmanager did not write ${config}."
  python3 - "${config}" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().splitlines()
order, values = [], {}
for line in lines:
    if "=" in line:
        key, value = line.split("=", 1)
        key = key.strip()
        if key not in values:
            order.append(key)
        values[key] = value.strip()
wanted = {
    "hw.lcd.width": "720", "hw.lcd.height": "1600", "hw.lcd.density": "280",
    "hw.ramSize": "3072", "vm.heapSize": "256", "hw.cpu.ncore": "2",
    "hw.camera.back": "none", "hw.camera.front": "none",
    "hw.audioInput": "no", "hw.audioOutput": "no", "hw.gps": "no",
    "hw.gpu.enabled": "yes", "hw.gpu.mode": "swiftshader_indirect",
    "showDeviceFrame": "no", "disk.dataPartition.size": "6G",
    "hw.keyboard": "yes", "PlayStore.enabled": "no",
}
for key, value in wanted.items():
    if key not in values:
        order.append(key)
    values[key] = value
open(path, "w").write("\n".join(f"{k}={values[k]}" for k in order) + "\n")
PY
  say "created ${name} from ${image}"
}

start() {
  local name="${1:-commy_lite}"
  [[ -d "${AVD_HOME}/${name}.avd" ]] || die "no AVD called ${name}; scripts/emulator.sh create ${name}"
  local log="${LOG_DIR}/emulator-${name}.log"
  # setsid and a log file: the emulator must outlive this shell, and adb's
  # server must not inherit its stdout.
  setsid "${SDK}/emulator/emulator" -avd "${name}" -no-window -no-audio -no-boot-anim \
    -gpu swiftshader_indirect -cores 2 -netdelay none -netspeed full \
    > "${log}" 2>&1 < /dev/null &
  adb start-server > /dev/null 2>&1
  say "booting ${name} headless (log: ${log})"
  timeout 900 "${SDK}/platform-tools/adb" wait-for-device shell \
    'while [ -z "$(getprop sys.boot_completed)" ]; do sleep 2; done' \
    || die "the emulator did not boot in 15 minutes; see ${log}"
  for key in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb shell settings put global "${key}" 0
  done
  adb shell settings put system screen_off_timeout 1800000
  adb shell svc power stayon true
  say "up: $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"
}

stop() {
  adb emu kill > /dev/null 2>&1 || true
  say "stopped"
}

case "${1:-}" in
  create) shift; create "$@" ;;
  start) shift; start "$@" ;;
  stop) stop ;;
  *) die "usage: scripts/emulator.sh create [avd] [image] | start [avd] | stop" ;;
esac
