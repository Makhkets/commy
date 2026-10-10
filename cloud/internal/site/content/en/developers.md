---
title: Developers
summary: What Commy is made of, how to build it, and where decisions are recorded.
---

## Layout

```text
Flutter · Dart     UI, state, business logic (5 packages, melos)
Kotlin | Swift     a thin platform layer: VpnService, NEPacketTunnelProvider
Go · sing-box      network, protocols, TUN, DNS (libbox)
```

Packages: `commy_domain` (entities and use cases, no Flutter), `commy_config`
(link and subscription parsers, the sing-box config builder), `commy_core`
(talking to the core), `commy_data` (database, keystore, HTTP), `commy_ui`
(design system).

Every significant decision is an ADR in
[docs/adr](https://github.com/Makhkets/Commy/tree/main/docs/adr).

## Build for Android

```bash
melos bootstrap
scripts/build_core.sh android
cd apps/commy && fvm flutter build apk --release --target-platform android-arm,android-arm64
```

Details, including the reproducible build:
[docs/08-build-release.md](https://github.com/Makhkets/Commy/blob/main/docs/08-build-release.md).

## Tests

```bash
melos run analyze
melos run test
```

## Licence

GPL-3.0-or-later, inherited from sing-box. A fork must publish its source.
