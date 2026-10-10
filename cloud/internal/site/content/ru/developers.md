---
title: Разработчикам
summary: Из чего сделан Commy, как его собрать и где обсуждаются решения.
---

## Устройство

```text
Flutter · Dart     UI, состояние, бизнес-логика (5 пакетов, melos)
Kotlin | Swift     тонкий платформенный слой: VpnService, NEPacketTunnelProvider
Go · sing-box      сеть, протоколы, TUN, DNS (libbox)
```

Пакеты: `commy_domain` (сущности и use-case'ы, без Flutter), `commy_config`
(парсеры ссылок и подписок, сборщик конфига sing-box), `commy_core` (связь с
ядром), `commy_data` (база, хранилище ключей, HTTP), `commy_ui` (дизайн-система).

Каждое крупное решение записано как ADR в
[docs/adr](https://github.com/Makhkets/Commy/tree/main/docs/adr).

## Сборка Android

```bash
melos bootstrap
scripts/build_core.sh android
cd apps/commy && fvm flutter build apk --release --target-platform android-arm,android-arm64
```

Подробности, включая воспроизводимую сборку, —
[docs/08-build-release.md](https://github.com/Makhkets/Commy/blob/main/docs/08-build-release.md).

## Тесты

```bash
melos run analyze
melos run test
```

## Лицензия

GPL-3.0-or-later — наследуется от sing-box. Форк обязан публиковать исходники.
