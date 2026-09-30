#!/usr/bin/env bash
#
# Builds the sing-box network core for one platform.
#
#   scripts/build_core.sh android    -> core/build/libbox.aar
#   scripts/build_core.sh apple      -> core/build/Libbox.xcframework
#   scripts/build_core.sh windows    -> core/build/commy_core.dll
#   scripts/build_core.sh linux      -> core/build/libcommy_core.so
#   scripts/build_core.sh macos      -> core/build/libcommy_core.dylib
#
# We do not wrap sing-box by hand. It already ships experimental/libbox, which is
# built for exactly this and is what the official sing-box Android app binds with
# gomobile. core/ exists to pin the version, choose build tags, and add the one
# transport sing-box does not have: XHTTP (core/xhttp, reached through a few
# edits to patched copies of sing-box — see prepare_modules below and
# docs/adr/0010-xhttp-transport.md, docs/adr/0018-core-module-copies.md).
#
# Every value below is verified against the sing-box source, not copied from a
# blog post. See docs/13-libbox-reference.md.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CORE_DIR="${REPO_ROOT}/core"
readonly BUILD_DIR="${CORE_DIR}/build"

# Pinned deliberately. Bumping it is its own PR with its own matrix run (rule R8).
readonly SINGBOX_VERSION="v1.13.21"
readonly LIBBOX_PKG="github.com/sagernet/sing-box/experimental/libbox"
# Ours, bound into the same library: what Commy adds to the libbox API (today,
# measuring servers with no tunnel up). A package of its own rather than an
# edit to libbox: the edits to upstream are kept to what cannot live anywhere
# else, and each is one more thing a sing-box bump has to re-base. With
# -javapkg it is io.nekohasekai.mobile.Mobile.
readonly MOBILE_PKG="github.com/Makhkets/commy/core/mobile"

# Shorter than upstream's list on purpose.
#
#   dropped  with_naive_outbound  -> pulls cronet-go, an entire Chromium net stack
#   dropped  with_tailscale       -> pulls the whole Tailscale client
#
# Neither protocol is in the product's protocol list, and both are heavy — which
# matters for rule R7 (the iOS extension lives in 50 MiB). Verified against
# include/registry.go at the pinned tag that nothing we advertise is lost:
# VLESS, VMess, Trojan, Shadowsocks, ShadowTLS and AnyTLS register
# unconditionally; Hysteria2/TUIC need with_quic; WireGuard needs with_wireguard.
#
# badlinkname + tfogo_checklinkname0 + -checklinkname=0 are NOT optional:
# sing-box uses go:linkname against runtime internals and Go 1.23+ rejects that
# by default. Drop them and the link step fails with an opaque error.
readonly TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0"
readonly LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=${SINGBOX_VERSION} -s -w -buildid= -checklinkname=0"

readonly ANDROID_API=24
readonly ANDROID_ABIS="${COMMY_ANDROID_ABIS:-android/arm64,android/arm,android/amd64}"

die() { printf '\n\033[31merror:\033[0m %s\n\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

need_go() {
  command -v go >/dev/null 2>&1 || die "go is not on PATH. Install Go 1.26+ (or any Go that can fetch the toolchain core/go.mod names)."
}

# gomobile shells out to javac to compile the generated Java bindings, and it
# looks it up through the OS, not through the shell. Under Git Bash on Windows a
# PATH entry written Unix-style (C:/dev/jdk17/bin) is invisible to that lookup,
# so the build gets all the way to "aar: classes.jar" and then dies with
#   exec: "javac": executable file not found in %PATH%
# after having compiled the entire core. Resolve javac ourselves and put its
# directory on PATH in a form the OS understands.
need_javac() {
  if command -v javac >/dev/null 2>&1; then
    return
  fi
  local home="${JAVA_HOME:-}"
  [[ -n "${home}" ]] || die \
    "javac not found and JAVA_HOME is not set. gomobile needs a JDK (17+) to
   compile the generated Java bindings."
  # msys/cygwin: translate C:\... into /c/... so PATH lookup works both ways
  if command -v cygpath >/dev/null 2>&1; then
    home="$(cygpath -u "${home}")"
  fi
  [[ -x "${home}/bin/javac" || -x "${home}/bin/javac.exe" ]] || die \
    "JAVA_HOME=${JAVA_HOME} does not contain bin/javac."
  export PATH="${home}/bin:${PATH}"
  say "javac: ${home}/bin"
}

# go mod tidy does NOT accept -tags, and it only records go.sum entries for the
# default build configuration. with_clash_api and with_quic pull in modules that
# are not in it, so the build fails at COMPILE time with
#   missing go.sum entry for module providing package github.com/go-chi/render
# which reads like a broken sing-box version rather than a missing tidy flag.
# Passing the tags through GOFLAGS is the fix.
sync_modules() {
  say "syncing go.sum with build tags"
  ( cd "${CORE_DIR}" && GOFLAGS="-tags=${TAGS}" go mod tidy )
}

# Teaches the pinned sing-box the XHTTP transport without forking it — and
# carries the fixes that ride the same mechanism: the REALITY ClientHello
# (ADR-0011) and client version (ADR-0013), the selector that started on its
# cache (ADR-0014), and the gVisor reader that outlived its stack (ADR-0012).
#
# core/cmd/overlaygen copies the two upstream modules it edits — four files of
# sing-box, one of sing-tun — out of the module cache, patches the copies, and
# writes a go.mod that replaces the published modules with them. The go.mod in
# core/ keeps naming the published versions; the transport itself is ordinary
# code in core/xhttp.
#
# gomobile is run from a copy of core/ whose own go.mod is that one. It lists
# the module it runs in, writes a go.mod of its own for the binding and builds
# in a temporary directory — so the replacements have to be in the module's
# go.mod: a -modfile flag would travel into that temporary build and point it
# at the wrong module. This used to be `go build -overlay` over the cached
# files, which Go 1.25 refuses ("Files beneath GOMODCACHE must not be
# replaced"), and which held the core to a Go line without security fixes
# (docs/adr/0018-core-module-copies.md).
readonly XHTTP_MARKER='commy/core/xhttp.NewClient'
readonly CORE_COPY="${BUILD_DIR}/_core"

prepare_modules() {
  [[ "${BUILD_DIR}" != *[[:space:]]* ]] || die \
    "the build directory contains whitespace: ${BUILD_DIR}
   The patched go.mod names absolute paths, unquoted. Build from a directory without spaces."
  say "patching the upstream modules (XHTTP, REALITY, selector default, gVisor reader)"
  local modfile
  modfile="$(cd "${CORE_DIR}" && go run ./cmd/overlaygen -out "${BUILD_DIR}/_overlay")" \
    || die "could not patch the upstream modules; the message above says which
   upstream file changed. A sing-box bump has to re-base core/cmd/overlaygen."
  [[ -f "${modfile}" ]] || die "overlaygen reported ${modfile}, which does not exist."
  # A fresh copy of core/ — its build directory left behind — under that go.mod.
  rm -rf "${CORE_COPY}"
  mkdir -p "${CORE_COPY}"
  ( cd "${CORE_DIR}" && tar --exclude=./build -cf - . ) | ( cd "${CORE_COPY}" && tar -xf - )
  cp "${modfile}" "${CORE_COPY}/go.mod"
  cp "$(dirname "${modfile}")/go.sum" "${CORE_COPY}/go.sum"
}

# A core built without the edits still builds, and runs. The only honest
# check is to look inside the artefact: Go keeps function names in the binary
# even with -s -w, and this one exists only if the transport was linked in.
# One map carries every edit, so the marker stands for all of them.
verify_xhttp_in() {
  local label="$1" found
  shift
  # Counted, not `grep -q`: -q leaves at the first match, the producer dies of
  # SIGPIPE, and under `pipefail` a library that HAS the transport reads as one
  # that has not. That is not a guess — it is how this check first failed.
  found="$("$@" | grep -a -c "${XHTTP_MARKER}" || true)"
  if [[ "${found:-0}" -eq 0 ]]; then
    die "${label} was built WITHOUT the XHTTP transport: the patched modules did
   not apply. Nothing else would have told you — the core runs, and refuses
   every xhttp server at connect time."
  fi
  say "XHTTP transport is in ${label}"
}

# SagerNet's fork, pinned to the version sing-box's own Makefile installs.
#
# NOT golang.org/x/mobile. Upstream gomobile does not understand -libname, and
# its response to the flag is to print its usage text and exit 0 — a build that
# reports success and produces no file. Installing the wrong one is the single
# most expensive mistake available here, because nothing about the output says
# "wrong tool".
readonly GOMOBILE_PKG="github.com/sagernet/gomobile"
readonly GOMOBILE_VERSION="v0.1.12"

ensure_gomobile() {
  local gobin
  gobin="$(go env GOPATH)/bin"
  export PATH="${gobin}:${PATH}"

  # Installed unconditionally, on purpose.
  #
  # Detecting which gomobile is already there is harder than it looks and got
  # this wrong twice. `command -v gomobile` cannot tell the two apart — upstream
  # and the fork live at the same path under the same name — and the fork does
  # NOT list -libname in `bind -h`, so probing the help text rejects the correct
  # tool. `go version -m` reads the module path, but needs a binary path the
  # host OS understands, which differs between Git Bash and a Linux runner.
  #
  # `go install` is idempotent and cheap once the module is in the cache, so the
  # reliable move is to stop guessing and just pin it every time.
  say "installing ${GOMOBILE_PKG}@${GOMOBILE_VERSION}"
  go install "${GOMOBILE_PKG}/cmd/gomobile@${GOMOBILE_VERSION}"
  go install "${GOMOBILE_PKG}/cmd/gobind@${GOMOBILE_VERSION}"

  gomobile init
}

resolve_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    echo "${ANDROID_NDK_HOME}"; return
  fi
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT}" ]]; then
    echo "${ANDROID_NDK_ROOT}"; return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [[ -n "${sdk}" && -d "${sdk}/ndk" ]] || return 1
  # newest installed NDK
  find "${sdk}/ndk" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1
}

build_android() {
  need_go
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [[ -n "${sdk}" ]] || die "ANDROID_HOME is not set. Point it at your Android SDK."

  local ndk
  ndk="$(resolve_ndk)" || die \
    "Android NDK not found. Install it with:
     \$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --install 'ndk;28.0.13004108'
   then set ANDROID_NDK_HOME to the installed directory."
  export ANDROID_NDK_HOME="${ndk}"
  say "NDK: ${ndk}"

  need_javac
  sync_modules
  ensure_gomobile
  mkdir -p "${BUILD_DIR}"
  prepare_modules

  say "gomobile bind ${LIBBOX_PKG} ${MOBILE_PKG} for ${ANDROID_ABIS}"
  say "this compiles the whole core once per ABI and is slow on a weak machine;"
  say "set COMMY_ANDROID_ABIS=android/arm64 to build only what a phone needs."
  ( cd "${CORE_COPY}" && gomobile bind -v \
      -target="${ANDROID_ABIS}" \
      -androidapi "${ANDROID_API}" \
      -javapkg=io.nekohasekai \
      -libname=box \
      -tags "${TAGS}" \
      -ldflags "${LDFLAGS}" \
      -trimpath \
      -o "${BUILD_DIR}/libbox.aar" \
      "${LIBBOX_PKG}" "${MOBILE_PKG}" )

  local lib
  for lib in $(unzip -Z1 "${BUILD_DIR}/libbox.aar" 'jni/*/libbox.so'); do
    verify_xhttp_in "${lib}" unzip -p "${BUILD_DIR}/libbox.aar" "${lib}"
  done

  # The Gradle build reads it from here.
  local dest="${REPO_ROOT}/apps/commy/android/app/libs"
  mkdir -p "${dest}"
  cp "${BUILD_DIR}/libbox.aar" "${dest}/libbox.aar"
  say "done: ${dest}/libbox.aar ($(du -h "${dest}/libbox.aar" | cut -f1))"
}

build_apple() {
  need_go
  need_javac
  sync_modules
  ensure_gomobile
  mkdir -p "${BUILD_DIR}"
  [[ "$(uname -s)" == "Darwin" ]] || die "the Apple target needs macOS with Xcode."
  prepare_modules
  say "gomobile bind ${LIBBOX_PKG} ${MOBILE_PKG} for Apple"
  ( cd "${CORE_COPY}" && gomobile bind -v \
      -target=ios,iossimulator,macos \
      -tags "${TAGS},with_low_memory" \
      -ldflags "${LDFLAGS}" \
      -trimpath \
      -o "${BUILD_DIR}/Libbox.xcframework" \
      "${LIBBOX_PKG}" "${MOBILE_PKG}" )
  local binary
  while IFS= read -r binary; do
    verify_xhttp_in "${binary#"${BUILD_DIR}/"}" cat "${binary}"
  done < <(find "${BUILD_DIR}/Libbox.xcframework" -type f -name Libbox)
  say "done: ${BUILD_DIR}/Libbox.xcframework"
}

# The desktop targets use the C ABI in core/cshared via dart:ffi. They are not
# part of 1.0 (Android + iOS) and exist so the layout is real rather than
# aspirational — see docs/07-roadmap.md M5-M7.
build_cshared() {
  local goos="$1" out="$2"
  need_go
  sync_modules
  mkdir -p "${BUILD_DIR}"
  prepare_modules
  say "building c-shared core for ${goos}"
  ( cd "${CORE_COPY}" && CGO_ENABLED=1 GOOS="${goos}" go build \
      -buildmode=c-shared \
      -tags "${TAGS}" \
      -ldflags "${LDFLAGS}" \
      -trimpath \
      -o "${BUILD_DIR}/${out}" \
      ./cshared )
  verify_xhttp_in "${out}" cat "${BUILD_DIR}/${out}"
  say "done: ${BUILD_DIR}/${out}"
}

main() {
  local target="${1:-}"
  case "${target}" in
    android) build_android ;;
    apple)   build_apple ;;
    windows) build_cshared windows commy_core.dll ;;
    linux)   build_cshared linux   libcommy_core.so ;;
    macos)   build_cshared darwin  libcommy_core.dylib ;;
    *)
      cat >&2 <<EOF
usage: scripts/build_core.sh <android|apple|windows|linux|macos>

  sing-box ${SINGBOX_VERSION}
  tags     ${TAGS}

  env:
    ANDROID_HOME        required for the android target
    ANDROID_NDK_HOME    optional; otherwise the newest NDK under \$ANDROID_HOME is used
    COMMY_ANDROID_ABIS  optional; default ${ANDROID_ABIS}
EOF
      exit 2
      ;;
  esac
}

main "$@"
