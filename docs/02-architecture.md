# 02 · Архитектура

## Главная идея

**Толстое ядро, тонкая платформа, единый UI.**

Всё, что можно унести в Go (сеть, протоколы, TUN, DNS, маршрутизация) — в Go.
Всё, что можно унести в Dart (состояние, парсинг, генерация конфига, вся логика
продукта) — в Dart. Нативный код каждой ОС сводится к одному: **получить файловый
дескриптор туннеля и отдать его ядру.**

Если в Kotlin или Swift появляется бизнес-логика — это ошибка проектирования.

---

## Слои

```
┌─────────────────────────────────────────────────────────────┐
│  apps/commy                                               │
│  Composition root · роутинг · экраны · платформенные папки  │
└───────────────┬─────────────────────────────────────────────┘
                │
    ┌───────────┼───────────┬──────────────┬─────────────────┐
    ▼           ▼           ▼              ▼                 ▼
┌────────┐ ┌─────────┐ ┌──────────┐ ┌──────────────┐
│commy │ │commy  │ │ commy  │ │   commy    │
│  _ui   │ │ _data   │ │  _core   │ │   _config    │
│        │ │         │ │          │ │              │
│токены  │ │Drift    │ │CoreClient│ │парсеры ссылок│
│тема    │ │dio      │ │FFI       │ │+ подписок    │
│виджеты │ │secure   │ │channels  │ │сборщик       │
│        │ │storage  │ │Clash API │ │sing-box JSON │
└───┬────┘ └────┬────┘ └────┬─────┘ └──────┬───────┘
    │           │           │              │
    └───────────┴─────┬─────┴──────────────┘
                      ▼
             ┌──────────────────┐
             │ commy_domain   │   чистый Dart, БЕЗ Flutter
             │ сущности         │   Profile, Node, RoutingPolicy,
             │ use-case'ы       │   TunnelStatus, Result<T, Failure>
             │ порты (интерфейсы)│
             └──────────────────┘
```

**Правило зависимостей — только внутрь.** `commy_domain` не зависит ни от чего,
включая Flutter (правило R5, проверяется линтом). Внешние слои реализуют порты,
объявленные в домене.

### Кто за что отвечает

| Пакет | Отвечает | Не отвечает |
|---|---|---|
| `commy_domain` | Сущности, инварианты, use-case'ы, интерфейсы репозиториев | Хранение, сеть, UI |
| `commy_config` | Разбор пользовательского ввода в `Node[]`, сборка конфига sing-box | Отправка конфига в ядро |
| `commy_core` | Единый `CoreClient`, транспорты, нормализация событий ядра | Что делать с событиями |
| `commy_data` | БД, шифрование, HTTP, secure storage, репозитории | Бизнес-правила |
| `commy_ui` | Токены, тема, атомарные виджеты, golden-тесты | Знание о конкретных экранах |
| `apps/commy` | Экраны, провайдеры, роутинг, склейка | Низкоуровневые детали |

---

## Поток данных: от ссылки до трафика

```
① Пользователь вставляет vless://… или URL подписки
        │
        ▼
② commy_config · Parser
   ├─ определить формат (протокольная ссылка / base64 / Clash YAML / sing-box JSON)
   ├─ нормализовать в доменные Node
   └─ отбросить и объяснить то, что не распарсилось
        │
        ▼
③ commy_data · сохранить
   ├─ метаданные (имя, группа, задержка) → SQLite
   └─ креды (UUID, пароли, URL подписки) → зашифрованная часть
        │
        ▼
④ Пользователь жмёт «Подключить»
        │
        ▼
⑤ commy_config · ConfigBuilder
   Node(выбранный) + RoutingPolicy + Settings + DNS
        └──────────────► полный sing-box config (JSON)
        │
        ▼
⑥ commy_core · CoreClient.start(config)
        │
        ├─ Android  → MethodChannel → VpnService → libbox.NewService()
        ├─ Apple    → NETunnelProviderManager → расширение → libbox
        └─ Desktop  → IPC → привилегированный хелпер → ядро
        │
        ▼
⑦ Ядро поднимает TUN, applies routing, идёт трафик
        │
        ▼
⑧ Обратный поток: status / traffic / logs / connections
   libbox CommandServer (мобайл) │ Clash API (десктоп)
        │
        ▼
⑨ commy_core нормализует в доменные типы → Riverpod → UI
```

**Важная деталь шага ⑤:** конфиг собирается **целиком на каждый старт**, а не
патчится. Состояние ядра всегда однозначно выводится из состояния приложения.
Никаких «а какой конфиг сейчас реально загружен».

**Важная деталь шага ②:** парсер обязан быть снисходительным ко входу и строгим к
выходу. Реальные подписки содержат мусор, дубликаты и битые записи. Половина
списка не должна ронять импорт целиком — то, что не распарсилось, показывается
пользователю списком с причиной.

---

## `CoreClient` — единственная дверь к ядру

Полное описание и обоснование транспортов: [ADR-0005](adr/0005-core-ipc.md).

```dart
abstract interface class CoreClient {
  Future<void> start(CoreConfig config);
  Future<void> stop();
  Future<void> reload(CoreConfig config);

  Stream<TunnelStatus>     get status;
  Stream<TrafficSample>    get traffic;
  Stream<LogLine>          get logs;
  Stream<List<Connection>> get connections;

  Future<List<ProxyGroup>> proxies();
  Future<void>             select(String group, String tag);
  Future<Duration?>        urlTest(String tag, Uri probe);
}
```

Фичи **никогда** не обращаются к platform channels или FFI напрямую. Только через
этот интерфейс. Это то, что позволяет писать тесты подключения без реального
туннеля (`FakeCoreClient`).

### Машина состояний туннеля

```
      ┌─────────┐  start()   ┌──────────┐  ядро готово  ┌───────────┐
      │  idle   │───────────►│ starting │──────────────►│ connected │
      └─────────┘            └──────────┘               └───────────┘
           ▲                       │                          │
           │                       │ ошибка                   │ stop()
           │                       ▼                          ▼
           │                  ┌─────────┐               ┌──────────┐
           └──────────────────│  error  │◄──────────────│ stopping │
              сброс/повтор    └─────────┘   сбой ядра   └──────────┘
                                                              │
                                                              ▼
                                                          (idle)
```

Состояние — `sealed class` во freezed. Компилятор заставит обработать все ветки
в UI, включая `error` с причиной. Никаких `bool isConnected`.

Отдельно: **`connected` не означает «трафик идёт».** Есть подсостояние проверки
доступности (первый успешный `urlTest` после подключения). UI различает
«туннель поднят» и «интернет через туннель работает» — это разные вещи, и
пользователь должен видеть разницу.

---

## Go-ядро: два выхода наружу

Один Go-модуль, две разные обёртки над одним и тем же внутренним кодом.

```
core/
├─ internal/            общая логика: сборка сервиса, менеджер жизненного цикла
├─ mobile/              для gomobile → AAR / XCFramework
└─ cshared/             для dart:ffi → dll / so / dylib
```

**`mobile/`** — ограничен типами, которые понимает gomobile: `string`, числа,
`bool`, `[]byte`, интерфейсы, структуры без дженериков. Всё сложное передаётся
**JSON-строкой**. Это неудобно, но это цена gomobile, и она известна заранее.

**`cshared/`** — только `//export`-функции с C-совместимыми сигнатурами:

```go
//export commy_start
func commy_start(configJSON *C.char) *C.char   // "" = ok, иначе текст ошибки

//export commy_stop
func commy_stop() *C.char

//export commy_free_string
func commy_free_string(s *C.char)
```

Два жёстких правила границы FFI:
1. **Каждая аллокация имеет парный free.** Строка, возвращённая из Go,
   освобождается через `commy_free_string`, и никак иначе.
2. **Паника не пересекает границу.** Любой `recover()` превращается в строку
   ошибки. Паника через FFI — это мгновенный краш процесса без стека.

Биндинги на стороне Dart генерируются `ffigen` из заголовка. Руками не правятся.

---

## Что живёт в нативном коде

Ровно четыре вещи. Всё остальное — ошибка слоя.

1. **Получить дескриптор TUN** у системного API.
2. **Реализовать `PlatformInterface`** для `libbox`: защитить сокет от петли,
   определить владельца соединения (для per-app правил), сообщить о смене сети,
   отдать системные сертификаты.
3. **Управлять жизненным циклом** привилегированного процесса или сервиса.
4. **Показать системный UI**, которого нет в Flutter: постоянное уведомление
   Android, пункт меню в статус-баре macOS.

Детали по каждой платформе — [03-platform-tunnel.md](03-platform-tunnel.md).

---

## Состояние в UI

**Riverpod 3** с кодогеном. Никаких глобальных синглтонов и `GetIt`.

Слои провайдеров:

```
Infrastructure   coreClientProvider, databaseProvider, secureStorageProvider
                 (переопределяются в тестах)
        │
Repository       profileRepositoryProvider, nodeRepositoryProvider,
                 settingsRepositoryProvider
        │
Domain / UseCase connectUseCaseProvider, updateSubscriptionUseCaseProvider
        │
UI State         tunnelStateProvider, nodeListProvider, trafficChartProvider
        │
Widget           ref.watch(...)
```

Всё, что приходит из ядра, живёт в `StreamProvider`. Всё, что пользователь меняет
— в `NotifierProvider`. Асинхронные состояния в UI обрабатываются через
`AsyncValue.when` с обязательными ветками загрузки и ошибки: в сетевом приложении
«ошибка» — это нормальный, а не исключительный сценарий.

---

## Адаптивность

Один граф маршрутов `go_router`, две оболочки.

| Ширина | Оболочка | Навигация |
|---|---|---|
| < 600 dp | `MobileShell` | Нижняя панель, 4 вкладки, модальные bottom sheet |
| 600–1000 dp | `TabletShell` | `NavigationRail`, детали в правой панели |
| > 1000 dp | `DesktopShell` | Боковое меню + двухпанельный layout, диалоги вместо sheet |

Точки перелома — **токены** в `commy_ui`, а не числа в коде экранов (правило R4).

Десктоп получает то, чего нет на мобайле: трей с быстрым переключением, глобальные
горячие клавиши, окно логов отдельно, запуск при входе в систему.

---

## Обработка ошибок

Домен возвращает `Result<T, CommyFailure>` — не бросает исключения через слои.
Исключения ловятся **на границе** (I/O, FFI, каналы, HTTP) и превращаются в
типизированный `Failure`.

```dart
sealed class CommyFailure {
  // сеть
  const factory CommyFailure.subscriptionUnreachable(Uri url, Object cause);
  const factory CommyFailure.subscriptionMalformed(String detail);
  // конфиг
  const factory CommyFailure.unsupportedProtocol(String scheme);
  const factory CommyFailure.configInvalid(String detail);
  // туннель
  const factory CommyFailure.permissionDenied();     // юзер отклонил VPN-запрос
  const factory CommyFailure.helperUnavailable();    // служба не поднята
  const factory CommyFailure.coreCrashed(String log);
  // прочее
  const factory CommyFailure.storage(Object cause);
  const factory CommyFailure.unknown(Object cause, StackTrace st);
}
```

Каждый `Failure` обязан иметь: человеческий текст (через `slang`), понятное
**действие** для пользователя («Проверить ссылку», «Разрешить VPN», «Открыть
логи») и признак «можно ли повторить». Сообщение об ошибке без действия — это
недоделанная ошибка.
