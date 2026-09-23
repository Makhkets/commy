# Architecture Decision Records

Каждое решение, которое дорого откатывать, живёт здесь.

## Формат

```markdown
# ADR-NNNN · Заголовок

**Статус:** Accepted | Superseded by ADR-XXXX | Deprecated
**Дата:** YYYY-MM-DD

## Контекст
Что за ситуация и почему вообще пришлось выбирать.

## Решение
Что выбрали. Одним абзацем.

## Альтернативы
Что рассматривали и почему отклонили. Честно, с плюсами отклонённого.

## Последствия
Что стало проще, что стало сложнее, за что теперь платим.
```

## Правила

- Принятый ADR **не редактируется** по существу. Передумали — пишете новый и
  ставите старому `Superseded by ADR-XXXX`. История решений ценнее их аккуратности.
- Номера сквозные, не переиспользуются.
- Если изменение в коде противоречит ADR — сначала ADR, потом код.

## Список

| # | Решение | Статус |
|---|---|---|
| [0001](0001-flutter-ui.md) | Flutter как UI-фреймворк | Accepted |
| [0002](0002-singbox-core.md) | sing-box как сетевое ядро | Accepted |
| [0003](0003-gplv3-license.md) | GPL-3.0-or-later и распространение | Accepted |
| [0004](0004-mobile-first-order.md) | Mobile-first порядок выпуска платформ | Accepted |
| [0005](0005-core-ipc.md) | Единый `CoreClient` и транспорты IPC | Accepted |
| [0006](0006-codegen-and-native-layout.md) | Минимум кодогена и место Kotlin-кода туннеля | Accepted |
| [0007](0007-database-encryption.md) | Два хранилища вместо шифрования всей БД | Accepted |
| [0008](0008-subscription-identity.md) | Что значит «та же подписка» и что делает повторное добавление | Accepted |
| [0009](0009-device-identifier.md) | Идентификатор устройства для подписки (HWID) и заглушки панели | Accepted |
| [0010](0010-xhttp-transport.md) | Транспорт XHTTP: свой клиент в `core/xhttp`, в sing-box — оверлеем сборки | Accepted |
| [0011](0011-reality-client-hello.md) | ClientHello REALITY: сначала современный, обрезанный — после отказа сервера; для REALITY всегда отпечаток `chrome` | Accepted (владелец, 2026-09-23) |
| [0012](0012-gvisor-reader-stop.md) | Читатель gVisor, переживший стек: правка sing-tun оверлеем | Accepted (2026-09-23) |
