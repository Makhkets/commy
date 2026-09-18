#!/usr/bin/env bash
#
# check_apk_size.sh — holds the release APKs to their size budget (rule R11).
#
#   scripts/check_apk_size.sh [directory with the release APKs]
#
# Commy is downloaded as a file from a releases page, often over the very
# connection it is meant to fix, so the size of that file is a feature. It got
# to 202 MB once without anybody deciding it should: a universal APK with three
# copies of the core, every native library stored uncompressed, and six unused
# weights of the icon font along for the ride. Nothing failed, because nothing
# was looking. This is the thing that looks.
#
# A budget is the measured size plus roughly ten percent. When a change needs
# more room, raise the number here, in the same commit, and say in the message
# what the bytes bought. That is the whole procedure, and it is deliberately a
# visible one: the diff of this file is the history of what the app weighs.
#
# Exit codes: 0 within budget, 1 over budget or x86 libraries in the release
# APK, 2 nothing to check.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIR="${1:-${REPO_ROOT}/apps/commy/build/app/outputs/flutter-apk}"

# Budgets, in bytes of APK as downloaded. Measured on 2026-09-18 (sing-box
# 1.13.16, Flutter 3.44.8): the release APK 51.1 MB; per ABI, arm64-v8a
# 27.6 MB, armeabi-v7a 27.1 MB, x86_64 29.0 MB.
#
# `release` is the one file on the releases page (owner's decision,
# 2026-09-18: three per-ABI files left people guessing). It is built with
# `--target-platform android-arm,android-arm64` and must carry nothing for
# x86_64, which only emulators run — that is checked below, because an
# "everything" APK is how the file got to 202 MB in the first place.
budget_for() {
  case "$1" in
    release)     echo $((56 * 1024 * 1024)) ;;
    arm64-v8a)   echo $((32 * 1024 * 1024)) ;;
    armeabi-v7a) echo $((31 * 1024 * 1024)) ;;
    x86_64)      echo $((34 * 1024 * 1024)) ;;
    *)           echo 0 ;;
  esac
}

mb() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

failed=0
checked=0

check() {
  local apk="$1" name="$2" budget size
  budget="$(budget_for "${name}")"
  size="$(stat -c %s "${apk}")"
  checked=$((checked + 1))
  if [[ "${budget}" -eq 0 ]]; then
    echo "error: ${name}: no budget is set — add one to $(basename "$0")"
    failed=1
    return
  fi
  if [[ "${size}" -gt "${budget}" ]]; then
    echo "error: ${name}: $(mb "${size}") is over the budget of $(mb "${budget}")"
    echo "       the largest entries, as stored in the APK:"
    unzip -lv "${apk}" \
      | awk '$1 ~ /^[0-9]+$/ && NF >= 8 { printf "         %8.1f MB  %s\n", $3 / 1048576, $8 }' \
      | sort -rn | head -8
    failed=1
  else
    echo "ok:    ${name}: $(mb "${size}") of $(mb "${budget}")"
  fi
}

if [[ -f "${DIR}/app-release.apk" ]]; then
  check "${DIR}/app-release.apk" release
  if unzip -l "${DIR}/app-release.apk" | grep -qE ' lib/x86(_64)?/'; then
    echo "error: release: carries x86 libraries. Build it with:"
    echo "       flutter build apk --release --target-platform android-arm,android-arm64"
    failed=1
  fi
fi

shopt -s nullglob
for apk in "${DIR}"/app-*-release.apk; do
  check "${apk}" "$(basename "${apk}" | sed -E 's/^app-(.*)-release\.apk$/\1/')"
done

if [[ "${checked}" -eq 0 ]]; then
  echo "error: no release APK found in ${DIR}"
  echo "       Build it with: flutter build apk --release --target-platform android-arm,android-arm64"
  exit 2
fi

exit "${failed}"
