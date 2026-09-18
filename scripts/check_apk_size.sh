#!/usr/bin/env bash
#
# check_apk_size.sh — holds the release APKs to their size budget (rule R11).
#
#   scripts/check_apk_size.sh [directory with app-<abi>-release.apk files]
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
# Exit codes: 0 within budget, 1 over budget or a forbidden artifact is
# present, 2 nothing to check.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DIR="${1:-${REPO_ROOT}/apps/commy/build/app/outputs/flutter-apk}"

# Budgets, in bytes of APK as downloaded. Measured on 2026-09-18 (sing-box
# 1.13.16, Flutter 3.44.8): arm64-v8a 27.6 MB, armeabi-v7a 27.1 MB,
# x86_64 29.0 MB.
budget_for() {
  case "$1" in
    arm64-v8a)   echo $((32 * 1024 * 1024)) ;;
    armeabi-v7a) echo $((31 * 1024 * 1024)) ;;
    x86_64)      echo $((34 * 1024 * 1024)) ;;
    *)           echo 0 ;;
  esac
}

mb() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

failed=0
checked=0

# The universal APK is the app three times over. Gradle still produces one for
# `flutter run`, which looks for that file name; it must never be among the
# artifacts of a release.
if [[ -f "${DIR}/app-release.apk" ]]; then
  echo "error: ${DIR}/app-release.apk is a universal release APK" \
       "($(mb "$(stat -c %s "${DIR}/app-release.apk")"))."
  echo "       Build releases with: flutter build apk --release --split-per-abi"
  failed=1
fi

shopt -s nullglob
for apk in "${DIR}"/app-*-release.apk; do
  abi="$(basename "${apk}" | sed -E 's/^app-(.*)-release\.apk$/\1/')"
  budget="$(budget_for "${abi}")"
  size="$(stat -c %s "${apk}")"
  checked=$((checked + 1))
  if [[ "${budget}" -eq 0 ]]; then
    echo "error: ${abi}: no budget is set for this ABI — add one to $(basename "$0")"
    failed=1
    continue
  fi
  if [[ "${size}" -gt "${budget}" ]]; then
    echo "error: ${abi}: $(mb "${size}") is over the budget of $(mb "${budget}")"
    echo "       the largest entries, as stored in the APK:"
    unzip -lv "${apk}" \
      | awk '$1 ~ /^[0-9]+$/ && NF >= 8 { printf "         %8.1f MB  %s\n", $3 / 1048576, $8 }' \
      | sort -rn | head -8
    failed=1
  else
    echo "ok:    ${abi}: $(mb "${size}") of $(mb "${budget}")"
  fi
done

if [[ "${checked}" -eq 0 ]]; then
  echo "error: no app-<abi>-release.apk found in ${DIR}"
  echo "       Build them with: flutter build apk --release --split-per-abi"
  exit 2
fi

exit "${failed}"
