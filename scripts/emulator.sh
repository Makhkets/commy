#!/usr/bin/env bash
#
# A light Android emulator for a weak machine: headless, two cores, a 720p
# screen, no cameras, no audio, no animations.
#
#   scripts/emulator.sh create [avd] [image]   # e.g. commy_lite "system-images;android-36;google_apis;x86_64"
#   scripts/emulator.sh start  [avd]           # boots headless, waits for it, tunes it
#   scripts/emulator.sh stop
#
# start and stop address one emulator by its serial: emulator-5554, or
# emulator-$EMULATOR_PORT when that is set (an even port, 5554-5584), which is
# also how a second AVD runs next to the first.
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

# Every adb call below goes to this serial and nowhere else. Without one, adb
# takes "the" device, and there often is another: the owner's phone on USB or
# wireless debugging, or the other AVD. `wait-for-device` then returned at once
# for the phone, the phone got its animations switched off and its screen held
# on, and "up:" reported the phone's Android version while the emulator was
# still booting. The console port fixes the serial, and adb and
# `adb wait-for-device` both read ANDROID_SERIAL.
readonly PORT="${EMULATOR_PORT:-5554}"
readonly SERIAL="emulator-${PORT}"
export ANDROID_SERIAL="${SERIAL}"

die() { printf '\n\033[31merror:\033[0m %s\n\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

# The emulator refuses any other console port and exits at once, and the
# boot wait below would then watch for a serial that never appears — fifteen
# minutes before "did not boot". adb finds emulators on its own only up to
# 5584, the last console port of its sixteen.
[[ "${PORT}" =~ ^[0-9]+$ ]] && (( PORT >= 5554 && PORT <= 5584 && PORT % 2 == 0 )) \
  || die "EMULATOR_PORT must be an even number from 5554 to 5584, not '${PORT}'"

adb() { "${SDK}/platform-tools/adb" "$@"; }

# Whether adb knows an emulator at SERIAL, booted or not. Not `grep -q`: it
# stops reading at the match, and under pipefail adb's SIGPIPE would then
# read as "not listed".
listed() { adb devices 2>/dev/null | grep "^${SERIAL}[[:space:]]" > /dev/null; }

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
  adb start-server > /dev/null 2>&1
  # Whatever answers at SERIAL now is not the emulator about to start, and
  # the tuning below would go to it.
  if listed; then
    die "${SERIAL} is already running; scripts/emulator.sh stop, or pick another port:
   EMULATOR_PORT=5556 scripts/emulator.sh start ${name}"
  fi
  # setsid and a log file: the emulator must outlive this shell, and adb's
  # server must not inherit its stdout.
  setsid "${SDK}/emulator/emulator" -avd "${name}" -no-window -no-audio -no-boot-anim \
    -port "${PORT}" -gpu swiftshader_indirect -cores 2 -netdelay none -netspeed full \
    > "${log}" 2>&1 < /dev/null &
  say "booting ${name} headless at ${SERIAL} (log: ${log})"
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
  # This used to be `adb emu kill || true` and then "stopped" whatever adb
  # had said, including that it did not know which of two emulators to kill.
  # The check comes first because adb, asked to kill a serial it does not
  # know, waits for it instead of failing.
  if ! listed; then
    say "${SERIAL} is not running"
    return
  fi
  adb emu kill > /dev/null || die "adb did not stop ${SERIAL}"
  say "stopped ${SERIAL}"
}

case "${1:-}" in
  create) shift; create "$@" ;;
  start) shift; start "$@" ;;
  stop) stop ;;
  *) die "usage: scripts/emulator.sh create [avd] [image] | start [avd] | stop" ;;
esac
