<div align="center">

# Commy

**An open-source proxy client for your own servers.**
Android · iOS · Windows · macOS · Linux

[![CI](https://github.com/Makhkets/commy/actions/workflows/ci.yml/badge.svg)](https://github.com/Makhkets/commy/actions/workflows/ci.yml)
[![Core](https://github.com/Makhkets/commy/actions/workflows/core.yml/badge.svg)](https://github.com/Makhkets/commy/actions/workflows/core.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-in%20development-orange.svg)](docs/07-roadmap.md)
[![sing-box](https://img.shields.io/badge/sing--box-v1.13.16-2FD98A.svg)](https://github.com/SagerNet/sing-box)

</div>

---

> **🚧 Early development.** There is no release yet. The project is at milestone M0 —
> specification and scaffolding. Follow [the roadmap](docs/07-roadmap.md) for progress.

## What Commy is

A client that connects you to **your own** servers over VLESS/Reality, VMess, Trojan,
Shadowsocks, Hysteria2, TUIC, WireGuard and ShadowTLS — with an interface that does
not feel like filling in a JSON form.

Built on the [sing-box](https://github.com/SagerNet/sing-box) core with a
[Flutter](https://flutter.dev) interface, so every platform runs the same code and
behaves the same way.

## What Commy is not

**Commy is not a VPN service.** This is a hard product boundary, not marketing:

- we do not run servers and do not sell access;
- there are no built-in free configs and no catalogue of public servers — the app is
  empty until you import something;
- there are no accounts, no backend, no telemetry.

## Why another client

| Client | The gap |
|---|---|
| v2rayNG, NekoBox | Android only |
| sing-box official | Excellent core, minimal interface |
| Hiddify | All platforms, but a dense interface |
| Happ, INCY | Great UX — **closed source** |

Nothing today combines good UX, all five platforms **and** open source. For software
that carries all of your traffic, being auditable is not a nice-to-have.

## Principles

1. **Your servers or nothing.** No bundled configs, no affiliate integrations.
2. **Quiet on the network.** Zero outbound requests you did not ask for. Exactly three
   optional exceptions, all user-triggered, all listed on one settings screen.
3. **Transparency over convenience.** Every generated config can be opened and read.
4. **Same behaviour everywhere.** A routing rule written on your phone works
   identically on your laptop.
5. **No ads, no paid tiers, no accounts.**

## Planned features

Connect to your own servers with live traffic stats · subscription import with quota
and expiry tracking · QR, deep link and file import · latency testing and automatic
best-node selection · rule-based routing with geoip/geosite · per-app split
tunnelling · DNS control with leak protection · kill switch · live logs and active
connection inspection · dark and light themes · Russian and English.

Full catalogue with milestones: [docs/07-roadmap.md](docs/07-roadmap.md)

## Documentation

| | |
|---|---|
| [Vision](docs/00-vision.md) | Product, audience, explicit non-goals |
| [Stack](docs/01-stack.md) | Every dependency and why |
| [Architecture](docs/02-architecture.md) | Layers, data flow, `CoreClient` |
| [Platform tunnels](docs/03-platform-tunnel.md) | How the tunnel works on each OS |
| [Roadmap](docs/07-roadmap.md) | Milestones with acceptance criteria |
| [Security & privacy](docs/09-security-privacy.md) | Threat model, leak checklist |
| [Decisions](docs/adr/) | Architecture Decision Records |

Specification documents are written in Russian; code, identifiers and commit messages
are in English.

## Building

**Requirements**

| | |
|---|---|
| Flutter | 3.44.8 (ships Dart 3.12.2) |
| Go | 1.24+ |
| JDK | 17 — Android Gradle Plugin will not accept 21 |
| Android SDK | platform 36, build-tools 36.0.0 |
| Android NDK | **28.0.13004108** — the version sing-box builds with |

**Build**

```bash
# 1. the sing-box core -> apps/commy/android/app/libs/libbox.aar
#    gomobile recompiles the whole core once per ABI, so start with one
COMMY_ANDROID_ABIS=android/arm64 scripts/build_core.sh android

# 2. the Dart side. melos must be on PATH, not merely a dev_dependency: its
#    scripts shell out to `melos exec`, and `dart run melos run <script>` cannot
#    resolve that from inside itself. Activate the version pubspec.yaml pins.
dart pub get
dart pub global activate melos 6.3.3   # then add ~/.pub-cache/bin to PATH
melos bootstrap
melos run gen --no-select              # drift + slang codegen

# 3. run it
cd apps/commy && flutter run -d <device>
```

`--no-select` is only needed in a non-interactive shell: any `melos run` whose
script has package filters otherwise stops to prompt. On Windows run melos from
PowerShell rather than Git Bash, where it dies decoding a child process's output
on a non-UTF-8 locale.

The APK will not link without step 1: the core is a native library, not a pub
package. `scripts/build_core.sh` installs `gomobile` itself and fails with an
actionable message if the NDK is missing.

**If the core build fails**, check [docs/13-libbox-reference.md](docs/13-libbox-reference.md)
first. It documents the four traps that account for nearly every failure here —
among them that upstream `golang.org/x/mobile` is the *wrong* gomobile (sing-box
needs SagerNet's fork), and that `go mod tidy` silently ignores `-tags`, which
produces a `go.sum` that only breaks later, at compile time.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). There is no CLA:
contributions are accepted under GPL-3.0-or-later, the same licence as the project,
which means it can never be quietly relicensed or closed.

Found a security issue? Please read [SECURITY.md](SECURITY.md) first — do not open a
public issue.

## Licence

[GPL-3.0-or-later](LICENSE). Inherited from sing-box, and a good fit: a client that
carries all your traffic should stay open, including in forks.

Third-party components and licence compatibility: [docs/11-licensing.md](docs/11-licensing.md).

## Acknowledgements

[sing-box](https://github.com/SagerNet/sing-box) by SagerNet, without which this
project would be a multi-year effort rather than a client. [Hiddify](https://github.com/hiddify/hiddify-app)
and [Karing](https://github.com/KaringX/karing) proved the Flutter + sing-box path
across all five platforms.
