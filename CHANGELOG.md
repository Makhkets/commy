# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are cut from tags matching `v*`; the release workflow reads the section
matching the tag out of this file and uses it as the release notes.

## [Unreleased]

Nothing is released yet. The project is at milestone M0 — see
[docs/07-roadmap.md](docs/07-roadmap.md).

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

[Unreleased]: https://github.com/Makhkets/commy/commits/main
