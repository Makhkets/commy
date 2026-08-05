# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are cut from tags matching `v*`; the release workflow reads the section
matching the tag out of this file and uses it as the release notes.

## [Unreleased]

Nothing since the last pre-release.

## [0.1.0-alpha.3]

`alpha.2` built every artifact and then failed its own verification step: the
pattern that checks each APK carries `libbox.so` used a character class with no
underscore, so `lib/x86_64/libbox.so` could never match. The two ABIs that
passed are the two whose directory names contain no underscore. Fixed.

### Fixed

- **Release verification.** See above. The APKs were always fine.

## [0.1.0-alpha.2]

`v0.1.0-alpha.1` never produced a downloadable file: every APK built and then
`bundleRelease` failed, because ABI splits and an app bundle cannot both be on
while resource shrinking is. Fixed, and the bundle now builds first so the two
cannot interact at all.

### Added

- **Deep links work.** The manifest has always registered Commy as a handler
  for `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`,
  for JSON and YAML config files and for shared text — and nothing on the Dart
  side listened, so tapping such a link opened the app to no effect. A link now
  opens the import sheet with the text already in it, and a Quick Settings tap
  connects. The contract checker no longer excuses that channel.

### Fixed

- **Release artifacts.** See above.

## [0.1.0-alpha.1]

First build anyone can install. **The tunnel has never carried live traffic** —
no subscription has yet returned a real server to point it at — so treat this as
something to look at, not something to rely on. The APK is signed with the debug
key and named accordingly; it installs, and it is not fit for distribution.

What is actually verified: the core builds for three ABIs on a clean machine,
the APK carries `libbox.so` inside it, 649 tests pass with a clean analysis
across the workspace, the Dart↔Kotlin channel contract matches on both sides,
and subscription headers from a real Remnawave panel parse exactly as specified.

### Fixed

- **Four settings did nothing.** The kill switch, "hide unreachable", "auto
  connect" and the `checking` state each wrote or declared a value that no layer
  read. The kill switch is no longer a switch at all: the guarantee belongs to
  Android's "Always-on VPN" with "Block connections without VPN", so the row
  names it and opens the system screen instead of implying Commy provides it.
- **Routing rules were dropped in silence.** Every rule naming `geosite:` or a
  `geoip:` country is removed at build time while no rule set is on disk — which
  keeps the tunnel working, but the warnings explaining it were thrown away.
  They now reach the log and a banner on the routing screen.
- **The reachability probe said nothing.** Its result was stored and read by no
  widget, so «Проверить» ran a real probe and reported nothing at all.

### Added

- **Monorepo skeleton.** Melos workspace with five Dart packages
  (`commy_domain`, `commy_config`, `commy_core`, `commy_data`, `commy_ui`), the
  Flutter application under `apps/commy`, and the Go core under `core/`.
- **Domain layer.** Entities, `Result<T, CommyFailure>`, repository ports and use
  cases, in pure Dart with no dependencies at all — not even on Flutter (rule R5).
- **Link and subscription parsers.** `vless://` including Reality, `vmess://` in
  both the base64-JSON and query forms, `trojan://`, `ss://` including SIP002,
  `hysteria2://`, `tuic://`, `wireguard://`, `socks://` and `http://`.
  Subscription bodies are decoded as plain lists, base64, sing-box JSON or
  Clash YAML, and `subscription-userinfo`, `profile-title`,
  `profile-update-interval` and `announce` headers are read.
- **sing-box config generation.** Full configuration rebuilt from scratch on
  every start rather than patched, so the core's state always follows from the
  app's.
- **Design system.** Tokens, both themes, typography with Inter and JetBrains
  Mono vendored under the OFL, and the component library.
- **Network core.** sing-box v1.13.16 bound with gomobile into `libbox.aar`,
  built by `scripts/build_core.sh`.
- **CI.** Analyze, tests, golden tests, a debug APK, and a release pipeline that
  publishes signed artifacts with SHA-256 sums.

### Notes for anyone reading the history

Two decisions in this window deviate from the specification and are recorded as
ADRs rather than buried in commits:

- [ADR-0006](docs/adr/0006-codegen-and-native-layout.md) — code generation is
  cut down to `drift` and `slang` only; Dart 3 sealed classes replace freezed,
  and Riverpod is used without its generator.
- [ADR-0007](docs/adr/0007-database-encryption.md) — full database encryption is
  deferred. `sqlcipher_flutter_libs` and `sqlite3_flutter_libs` are both
  end-of-life; credentials now live in Keystore/Keychain through secure storage
  and the database holds metadata only.

[Unreleased]: https://github.com/Makhkets/commy/compare/v0.1.0-alpha.3...main
[0.1.0-alpha.3]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.1
