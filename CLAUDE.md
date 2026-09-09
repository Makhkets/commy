# Commy — контракт агента

> Читается каждую сессию. Держим коротко и точно.
> Детали — в `docs/`. Если ответа тут нет, иди в `docs/`, а не выдумывай.
> Оглавление документации: [docs/README.md](docs/README.md)

---

## 1. Что мы строим

**Commy** — кроссплатформенный опенсорсный **прокси-клиент** (класс Happ / INCY /
Hiddify / Karing). Пользователь подключается к **своим собственным серверам** по
VLESS/Reality, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, ShadowTLS.

Платформы: **Android → iOS → Windows → macOS → Linux** (порядок выпуска).
**Релиз 1.0 = Android + iOS.** Десктопы выходят как 1.1 и 1.2.
UI: **Flutter**. Сетевое ядро: **sing-box** через `experimental/libbox`.
Лицензия: **GPL-3.0-or-later** (наследуется от sing-box).

### Commy — НЕ VPN-сервис

Это не маркетинговая формулировка, а инженерное и юридическое ограничение продукта:

- мы **не держим серверы** и не продаём доступ;
- в приложении **нет и не будет встроенных бесплатных конфигов** или каталога
  публичных серверов;
- **нет аккаунтов, нет бэкенда, нет телеметрии** — приложение общается только с
  теми хостами, которые ввёл пользователь.

Любая задача, которая ломает хоть один пункт, — не наша задача. Остановись и спроси.

---

## 2. Жёсткие правила

Нарушение любого — это баг, даже если тесты зелёные.

| # | Правило |
|---|---|
| R1 | **Никакой сети «от себя».** Ни аналитики, ни crash-репортов, ни проверки обновлений. Разрешены только подписки и прокси-серверы пользователя плюс **три исключения** (E-1 IP-чек по кнопке, E-2 geoip/geosite по кнопке, E-3 списки блокировки при включённой функции). Список закрытый — см. [docs/09-security-privacy.md](docs/09-security-privacy.md#тишина-в-сети--правило-r1-и-его-исключения). Четвёртое исключение добавляется только решением владельца проекта. |
| R2 | **Секреты не пишутся в открытую БД.** UUID, пароли, ссылки подписок, сгенерированный конфиг ядра — только в зашифрованное хранилище. См. [docs/06-data-model.md](docs/06-data-model.md#шифрование). |
| R3 | **Логи редактируются.** Перед выводом и экспортом из логов вырезаются креды, токены подписок и полные URL. См. [docs/09-security-privacy.md](docs/09-security-privacy.md#редакция-логов). |
| R4 | **Цвета, отступы, радиусы, тайминги — только из токенов** `commy_ui`. Ни одного `Color(0xFF...)`, `EdgeInsets.all(13)` или `Duration(milliseconds: 237)` в фиче-коде. ⚠️ Набор токенов сейчас **на утверждении** — `commy_ui` не строим, пока владелец не принял направление. |
| R5 | **Домен не знает про Flutter.** `commy_domain` не импортирует `package:flutter/*`. Проверяется линтом. |
| R6 | **Утечки трафика недопустимы.** Любое изменение туннеля/маршрутизации/DNS обязано пройти чек-лист утечек из [docs/09-security-privacy.md](docs/09-security-privacy.md#чек-лист-утечек). |
| R7 | **iOS-расширение живёт в 50 MiB.** Всё, что попадает в target `CommyTunnel`, оценивается по памяти. См. [docs/03-platform-tunnel.md](docs/03-platform-tunnel.md#ios--macos-app-store). |
| R8 | **Не обновляем sing-box «мимоходом».** Бамп версии ядра — отдельный PR со своим прогоном матрицы. |
| R9 | **Никаких сгенерированных файлов в diff вручную.** `*.g.dart`, `*.freezed.dart`, `*.ffi.dart` правятся только через кодоген. |
| R10 | **Не коммитим и не пушим без явной просьбы.** |

---

## 3. Карта репозитория

```
Commy/
├─ CLAUDE.md                 ← ты здесь
├─ docs/                     ТЗ и решения (см. docs/README.md)
│
├─ apps/commy/             Flutter-приложение (5 платформенных папок)
│  ├─ lib/                   composition root, роутинг, экраны
│  ├─ android/ ios/ windows/ macos/ linux/
│
├─ packages/                 Dart-пакеты монорепо (melos)
│  ├─ commy_domain/        чистые сущности + use-case'ы. БЕЗ Flutter.
│  ├─ commy_config/        парсеры ссылок/подписок + сборщик sing-box JSON
│  ├─ commy_core/          CoreClient: FFI + platform channels + Clash API
│  ├─ commy_data/          Drift, dio, secure storage, репозитории
│  └─ commy_ui/            дизайн-система: токены, тема, виджеты
│
├─ core/                     Go-модуль: обёртка sing-box
│  ├─ mobile/                API под gomobile (AAR / XCFramework)
│  ├─ cshared/               C ABI под dart:ffi (dll / so / dylib)
│  └─ internal/              общая логика ядра
│
├─ native/                   платформенный код туннеля
│  ├─ android/               Kotlin: VpnService + PlatformInterface
│  ├─ apple/                 Swift: NEPacketTunnelProvider (общий для iOS/macOS)
│  ├─ windows/               CommyService: elevated-хелпер + Wintun
│  └─ linux/                 commy-helper: polkit + CAP_NET_ADMIN
│
├─ scripts/                  build_core, codegen, release
└─ .github/workflows/        CI-матрица
```

**Границы зависимостей** (нарушать нельзя):

```
apps/commy  →  commy_ui  →  commy_domain
      │         commy_data →  commy_domain
      │         commy_core →  commy_domain
      └────────→ commy_config → commy_domain

commy_domain → ничего
```

---

## 4. Команды

> Скрипты — часть контракта. Если скрипта нет, его надо создать под это имя,
> а не изобретать альтернативный вызов.

```bash
melos bootstrap              # установить зависимости во всём монорепо
melos run gen                # кодоген: freezed, riverpod, drift, slang, ffigen
melos run analyze            # статический анализ всех пакетов
melos run test               # юнит- и виджет-тесты
melos run test:golden        # golden-тесты дизайн-системы
melos run fix                # dart fix + format
```

```bash
scripts/build_core.sh android      # → core/build/libbox.aar
scripts/build_core.sh apple        # → core/build/Libbox.xcframework
scripts/build_core.sh windows      # → core/build/commy_core.dll
scripts/build_core.sh linux        # → core/build/libcommy_core.so
scripts/build_core.sh macos        # → core/build/libcommy_core.dylib
```

```bash
cd apps/commy && flutter run -d <device>
```

Версия Flutter пинится через **FVM** (`.fvmrc`). Не запускай глобальный `flutter`,
если `.fvmrc` есть — используй `fvm flutter`.

---

## 5. Конвенции кода

**Общее.** Идентификаторы, комментарии, сообщения коммитов, тексты ошибок в коде —
**на английском**. Документация в `docs/` и `CLAUDE.md` — **на русском**.
`README.md` — на английском (публичное лицо проекта). UI-строки — только через
`slang`, хардкод текста в виджетах запрещён.

**Dart**
- Линт: `very_good_analysis`. Предупреждения — это ошибки.
- Состояние: **Riverpod 3** с кодогеном (`@riverpod`). Никаких глобальных синглтонов.
- Модели: **freezed** + `json_serializable`. Иммутабельность по умолчанию.
- Ошибки: use-case'ы возвращают `Result<T, CommyFailure>`, не бросают исключения
  через слои. Исключения ловятся на границе (I/O, FFI, каналы).
- Файл — одна публичная сущность. Имена файлов `snake_case`.
- Никаких `print`. Только `AppLogger` из `commy_core`.

**Go (`core/`)**
- Go 1.24+, `gofumpt`, `golangci-lint`.
- Публичный API `mobile/` ограничен типами, которые переваривает **gomobile**:
  `string`, числа, `bool`, `[]byte`, интерфейсы и структуры без дженериков.
  Сложные данные передаём **JSON-строкой**.
- `cshared/` — только `//export`-функции, C-совместимые сигнатуры, ручное
  освобождение памяти (`free_string`). Каждая аллокация имеет парный free.
- Ошибки возвращаются как строка (пустая = успех), не паникуем через границу FFI.

**Kotlin (`native/android/`)**
- Ktlint. Корутины, никаких `Thread`. VpnService живёт в foreground-сервисе.

**Swift (`native/apple/`)**
- SwiftFormat. Код туннеля общий для iOS и macOS, различия — через `#if os()`.
- В расширении: никаких тяжёлых зависимостей, следим за R7.

**Коммиты.** Conventional Commits: `feat(core): ...`, `fix(android): ...`,
`docs: ...`, `chore(deps): ...`. Скоупы: `core`, `android`, `apple`, `windows`,
`linux`, `ui`, `domain`, `data`, `config`, `ci`, `docs`.

---

## 6. Definition of Done

Изменение готово, только когда выполнено всё:

- [ ] `melos run analyze` чист;
- [ ] `melos run test` зелёный; новая логика покрыта тестом;
- [ ] изменения UI покрыты golden-тестом в **обеих темах** (dark + light);
- [ ] новые строки заведены в `slang` для `ru` и `en`;
- [ ] если тронут туннель, маршрутизация или DNS — пройден
      [чек-лист утечек](docs/09-security-privacy.md#чек-лист-утечек);
- [ ] если менялся публичный API `core/` — пересобраны артефакты под все
      затронутые платформы;
- [ ] если менялось архитектурное решение — обновлён или добавлен ADR в `docs/adr/`;
- [ ] проверено вручную минимум на одной реальной платформе, а не только в тестах.

---

## 7. Что решает человек, а не агент

Останавливайся и спрашивай, если задача требует:

1. **Бампа версии sing-box** или смены сетевого ядра.
2. **Новой зависимости** в `pubspec.yaml` / `go.mod` — особенно тянущей сеть,
   аналитику или нативный код.
3. **Любого исходящего запроса** к домену, который не ввёл пользователь.
4. **Изменения модели угроз, хранения секретов или лицензии.**
5. **Публикации**: релизные теги, загрузка в сторы, подписи, работа с секретами CI.
6. **Смены дизайн-токенов** (палитра, шрифты, шкала) — это меняет идентичность.

---

## 8. Текущее состояние

**M0 закрыт. M1 написан целиком и не принят.** Выпущено `v0.1.0-alpha.2`.

Что есть: шесть пакетов, 699 тестов плюс 99 golden (только на Linux), чистый
анализ, ядро sing-box под три ABI, Android-туннель (`VpnService`,
`PlatformInterface` 15/15, `BootReceiver`, плитка, Doze), все экраны
приложения, deep links, APK с ядром внутри.

**Чего не хватает:** приложение доведено примерно до половины (диагностика, «О программе»,
тесты приложения — см. [docs/15-handoff.md § 0](docs/15-handoff.md#очередь-работ-по-убыванию-пользы)).

**Живой туннель:** есть инфраструктура для тестирования. Создай тестового пользователя:
```bash
python scripts/panel_test_setup.py --setup
```
Подробнее: [docs/16-local-testing.md](docs/16-local-testing.md).

**Последний прогресс:** 2026-09-09 — закрыты задачи #1–5 очереди (E-1,
live reload, `startOnBoot`, пустые состояния диагностики, `clockProvider`),
починен CI на `main`, приняты 6 из 7 PR dependabot. Затем закрыта **#10**:
буфер `AppLogger` переливается в репозиторий логов при подписке, поэтому
строки времени старта видны на экране логов. Следующему: начинать с **#6**,
детали и что не проверено — в docs/17-agent-handoff.md, «Сессия 2» и «Сессия 3».

**Для следующей сессии — прочитай в этом порядке:**
1. **[docs/17-agent-handoff.md](docs/17-agent-handoff.md)** ← начни отсюда (план работ и инструкции для агента)
2. **[docs/15-handoff.md](docs/15-handoff.md#очередь-работ-по-убыванию-пользы)** — очередь работ, приоритеты, грабли
3. **[docs/16-local-testing.md](docs/16-local-testing.md)** — как тестировать против живой подписки
4. **[docs/02-architecture.md](docs/02-architecture.md)** — перед кодированием
