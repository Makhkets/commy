# Протокол между Dart и нативным туннелем

> Контракт двух сторон. Kotlin реализует ровно это, `AndroidCoreClient` вызывает
> ровно это. Расхождение здесь не ловится ни линтером, ни компилятором — оно
> проявляется как «кнопка нажимается, ничего не происходит».
>
> Точный API libbox, поверх которого всё это построено, —
> [../../../docs/13-libbox-reference.md](../../../docs/13-libbox-reference.md),
> полный дамп сигнатур — [../../../docs/libbox-java-api.txt](../../../docs/libbox-java-api.txt).
>
> Доменный порт, под который протокол обязан ложиться без зазора, —
> `CoreClient` в `packages/commy_domain/lib/src/ports/core_client.dart`.
> Если протокол и порт разошлись — прав порт.

---

## Каналы

| Канал | Имя | Направление |
|---|---|---|
| `MethodChannel` | `dev.commy.app/core` | Dart → Kotlin |
| `EventChannel` | `dev.commy.app/status` | Kotlin → Dart |
| `EventChannel` | `dev.commy.app/traffic` | Kotlin → Dart |
| `EventChannel` | `dev.commy.app/logs` | Kotlin → Dart |
| `EventChannel` | `dev.commy.app/connections` | Kotlin → Dart |

Имена лежат в `WireChannels` (`lib/src/wire/wire_channels.dart`) и больше нигде.

**Все полезные нагрузки — JSON-строки**, а не `Map`. Причина не в эстетике:
кодек `StandardMessageCodec` по-разному округляет целые больше 2^31 на разных
платформах, а счётчики трафика их превышают на первой же гигабайтной сессии.
Та же строка едет дальше в libbox, который через gomobile умеет только строки, —
один формат на всю цепочку вместо двух.

Общие правила:

| Правило | Значение |
|---|---|
| Кодек канала | `StandardMethodCodec` (дефолт Flutter) |
| Аргумент метода | `String?` — JSON, либо `null` |
| Результат метода | `String?` — JSON, либо `null` |
| Событие `EventChannel` | `String` — JSON |
| Аргумент `listen` | всегда `null`; фильтрация — на стороне Dart |
| Время | целое, миллисекунды от Unix-эпохи, **UTC** |
| Байтовые счётчики | целое JSON-число до 2^63−1 |
| Незнакомое поле | игнорируется обеими сторонами; добавление поля не ломающее |
| Отсутствующее необязательное поле | эквивалентно `null` |

**Всё, что уходит в `Result` и в `EventSink`, отправляется с главного потока**
(`Handler(Looper.getMainLooper())`). Вызов из потока libbox роняет движок Flutter
без внятного стека — это самая дорогая ошибка в этом файле.

---

## Методы

Ровно семь. Больше методов на этом канале нет.

### `start(config: String) → null`

`config` — полный JSON конфига sing-box, собранный `SingBoxConfigBuilder`
(результат `CoreConfig.encode()`), передаётся как **строка целиком**, без
обёртки. Конфиг **всегда собирается целиком**, а не патчится: состояние ядра
обязано однозначно выводиться из состояния приложения.

Kotlin:
1. `VpnService.prepare()` — если разрешение не выдано, бросить
   `permission_denied` (см. коды ошибок);
2. `Libbox.setup(SetupOptions)` — один раз за процесс;
3. поднять foreground-сервис;
4. `CommandServer(handler, platformInterface).start()`;
5. `commandServer.startOrReloadService(config, null)`.

Успех метода означает **«ядро запускается»**, а не «туннель работает».
Фактическое состояние приходит потоком в `/status`.

**Идемпотентность обязательна.** Повторный `start` при уже поднятом туннеле не
создаёт второй туннель — это критерий приёмки из
[docs/10-testing.md](../../../docs/10-testing.md). Допустимо либо перезапустить
с новым конфигом, либо ответить `already_running`; Dart трактует
`already_running` как успех и ничего не показывает пользователю.

### `stop() → null`

`commandServer.closeService()`, затем остановка foreground-сервиса.
Идемпотентен: остановка уже остановленного — **успех**, не ошибка.

### `reload(config: String) → null`

`commandServer.startOrReloadService(config, null)` без пересоздания TUN.
Аргумент — та же строка конфига, что у `start`.
Для смены узла **не использовать** — есть `select`.

### `select(args: String) → null`

```json
{"group": "proxy", "tag": "node-7f3c1a"}
```

`commandClient.selectOutbound(group, tag)`.

Это и есть «смена узла на лету». Перезапуск туннеля рвёт все открытые
соединения, и пользователь видит это как отвалившийся звонок и оборванную
загрузку.

- `group` — всегда приходит явно; на практике это `proxy`
  (`SingBoxTags.proxyGroup` = `SwitchNodeUseCase.defaultGroupTag`).
- `tag` — тег исходящего вида `node-<id>` (`SingBoxTags.forNode`).
- ядро не запущено → `not_running`;
- тега нет в группе → `config_invalid` с текстом.

### `urlTest(args: String) → String`

```json
{"tag": "node-7f3c1a", "url": "http://cp.cloudflare.com/generate_204",
 "timeoutMs": 5000, "group": "proxy"}
```

```json
{"delayMs": 137}      // измерено
{"delayMs": null}     // проба не вернулась — это НЕ ошибка
```

`group` необязателен, по умолчанию `proxy`. `timeoutMs` необязателен, по
умолчанию `5000`.

⚠️ **Ловушка libbox, из-за которой этот метод переписан.**
`CommandClient.urlTest(groupTag)` замеряет **группу целиком**, а не один
исходящий, и результат приходит асинхронно в `writeGroups(...)`, а не возвратом.
Доменный порт при этом требует `Future<Duration?> urlTest(String tag, Uri probe)`
— задержку одного узла. Поэтому асинхронность прячется в Kotlin:

1. вызвать `commandClient.urlTest(group)` на клиенте с подпиской `CommandGroup`;
2. дождаться следующего `writeGroups` — но не дольше `timeoutMs`;
3. найти в группе элемент с тегом `tag`, взять его `urlTestDelay`;
4. задержка `0`, элемент не найден или таймаут → `{"delayMs": null}`.

`null` — честный ответ «не достучались», а не ошибка: `MeasureLatencyUseCase`
возвращает на нём `Ok(null)` и рисует прочерк. Ошибку кидать нельзя, иначе
недоступный узел неотличим от сломанного приложения.

`url` — то, что пользователь задал в `AppSettings.latencyProbeUrl`. Проба идёт
**через туннель**, поэтому исключением из правила R1 не является.

### `proxies() → String`

JSON-массив групп из последнего `writeGroups`:

```json
[{"tag":"auto","type":"urltest","selected":"nl-03","selectable":true,
  "items":[{"tag":"nl-03","type":"vless","urlTestDelay":48}]}]
```

| Поле | Обяз. | Описание |
|---|---|---|
| `tag` | да | тег группы |
| `type` | да | тип, как его отдаёт libbox: `selector`, `urltest`, `fallback`, … Регистр не важен |
| `selected` | нет | тег текущего участника |
| `items` | нет | участники в порядке ядра; по умолчанию `[]` |
| `items[].tag` | да | тег участника |
| `items[].type` | нет | тип исходящего, для отображения |
| `items[].urlTestDelay` | нет | последняя задержка, мс |
| `selectable` | нет | информационное; Dart выводит переключаемость из `type` |

`urlTestDelay` в миллисекундах; `0` означает **не измерено**, а не «мгновенно» —
это различие обязано доехать до UI, иначе неизмеренный узел выглядит лучшим.

Нормализация в Dart: `ProxyGroup(tag: tag, type: type, now: selected,
all: items.map((i) => i.tag))`. Всё остальное — `urlTestDelay`, `selectable`,
`items[].type` — на этой границе отбрасывается: доменный `ProxyGroup` их не
несёт. Поля остаются в протоколе потому, что они бесплатны для Kotlin и
понадобятся, когда появится массовый замер.

Ядро не запущено → **пустой массив** `[]`, а не ошибка.

### `version() → String`

`Libbox.version()`. Нужен экрану «О программе». Частью доменного `CoreClient`
не является — это дополнительный метод `AndroidCoreClient`.

---

## События

### `/status`

```json
{"state":"connected","since":1754280000000,"nodeId":null,"reason":null,"code":null}
```

| Поле | Обяз. | Описание |
|---|---|---|
| `state` | да | `idle`, `starting`, `connected`, `checking`, `stopping`, `error` |
| `since` | для `connected` / `checking` | когда туннель поднялся, мс epoch UTC |
| `nodeId` | нет | идентификатор доменного `ProxyNode`, если нативная сторона его знает |
| `reason` | для `error` | человекочитаемый текст |
| `code` | для `error` | код из таблицы ошибок |

Ровно шесть состояний машины из
[docs/05-ux-flows.md](../../../docs/05-ux-flows.md).

**Обязательства нативной стороны:**

1. **Сразу после `onListen` отдать текущее состояние.** Ничего не запущено —
   `{"state":"idle"}`. Это единственный способ пережить hot restart и
   пересоздание Flutter-движка: Dart подписывается заново на живой туннель и
   иначе покажет `idle` поверх работающего соединения.
2. `starting` — до `startOrReloadService`, `connected` — после того, как сервис
   реально поднялся.
3. `stopping` → `idle` при штатной остановке.
4. Смерть ядра — внешнее убийство, паника Go, `serviceStop()` не по нашей
   команде — обязана доехать как `{"state":"error","code":"core_crashed"}`.
   Зависание в `connected` при мёртвом ядре — баг (ручной сценарий №9).
5. `since` берётся из `commandClient.getStartedAt()`, если доступен, иначе из
   `System.currentTimeMillis()` в момент подъёма, и **не пересчитывается** на
   последующих событиях: на нём висит таймер в UI.

**`connected` не означает, что трафик идёт.** Переход в `checking` и обратно
делает Dart-сторона по результату первого `urlTest`; Kotlin сам `checking` не
выставляет. Декодер его принимает — ради `FakeCoreClient` и на будущее.

### `/traffic`

```json
{"up":25600,"down":37888,"upTotal":1073741824,"downTotal":5368709120,"at":1754280000000}
```

Прямо из `StatusMessage`: `getUplink`, `getDownlink`, `getUplinkTotal`,
`getDownlinkTotal`. Интервал задаётся `CommandClientOptions.statusInterval`
(1 с). `up` и `down` — байты в секунду, `upTotal` и `downTotal` — нарастающим
итогом от подъёма туннеля. Монотонность внутри сессии обязательна: на ней стоит
дневной агрегат в `commy_data`.

⚠️ Если `getTrafficAvailable()` вернул `false`, событие **не отправляется вовсе**.
Иначе нули «статистика не собирается» неотличимы от нулей «трафика нет», и UI
показывает работающему туннелю прочерк.

`at` необязателен: без него Dart проставит своё время. Но лучше слать — тогда
все отметки на графике из одних часов.

### `/logs`

```json
{"level":"info","message":"…","at":1754280000000,"tag":"router"}
```

`level`: `trace` `debug` `info` `warn` (`warning`) `error` `fatal` (`panic`).
Неизвестный или отсутствующий уровень → `info`.
`tag` необязателен — компонент, если его удалось выделить.

**Массив тоже принимается**, и это основной путь:
`CommandClientHandler.writeLogs(LogIterator)` отдаёт пачку, разбивать её на
отдельные события бессмысленно.

```json
[{"level":"info","message":"…","at":1754280000000},
 {"level":"error","message":"…","at":1754280000010}]
```

**Логи уходят наверх сырыми.** Редакция по правилу R3 — на стороне Dart, в
`AppLogger`, перед показом и перед экспортом. Резать в Kotlin нельзя: там нет
знания о том, какие строки являются кредами, и попытка угадать регулярками
вырежет половину полезного и оставит половину секретов.

Если выделить уровень не удалось — шли всю строку в `message` и не ставь
`level`: Dart умеет вытащить ведущий токен сам (`INFO[0001] …`, `[warn] …`,
`level=error …`).

### `/connections`

```json
[{"id":"…","host":"example.com:443","rule":"geosite:ru → direct","outbound":"direct",
  "up":1024,"down":8192,"start":1754280000000,"network":"tcp"}]
```

Снимок целиком, а не дельта. Отвечает на вопрос «почему этот сайт идёт мимо
прокси» — поэтому поле `rule` обязательно, без него экран бесполезен.

| Поле | Обяз. | По умолчанию |
|---|---|---|
| `id` | да | — |
| `host` | нет | `""` |
| `rule` | нет | `""` |
| `outbound` | нет | `""` |
| `up` | нет | `0` |
| `down` | нет | `0` |
| `start` | нет | время события |
| `network` | нет | `"tcp"` |

`ConnectionEvents` в libbox инкрементален (`getCreated` / `getClosed`).
**Накопление в снимок — задача Kotlin**: у Dart нет способа отличить «соединение
закрылось» от «событие потерялось». Частота — не чаще 1 Гц, иначе на активном
туннеле канал забивается и UI начинает тормозить на ровном месте.

Соединения нигде не сохраняются (docs/06-data-model.md), поэтому пропущенный
снимок некритичен — важен только последний.

---

## Ошибки

`MethodChannel` отдаёт `FlutterError(code, message, details)`; то же самое для
`EventSink.error(code, message, details)`. Коды закрытые:

| Код | Когда | Доменный `CommyFailure` |
|---|---|---|
| `permission_denied` | пользователь отклонил системный диалог VPN | `PermissionDeniedFailure()` |
| `config_invalid` | `Libbox.checkConfig` не принял конфиг, нет тега в группе | `ConfigInvalidFailure(message)` |
| `core_crashed` | ядро упало после старта | `CoreCrashedFailure(message)` |
| `already_running` | `start` при поднятом туннеле | **не ошибка** — Dart трактует как успех |
| `not_running` | `select` / `urlTest` без туннеля | `HelperUnavailableFailure()` |
| `helper_unavailable` | сервис не поднялся | `HelperUnavailableFailure()` |
| `storage` | не прочитали/не записали файл конфига или лога | `StorageFailure(message)` |
| `unknown` | всё остальное | `UnknownFailure(...)` |

Отображение полное: незнакомый код превращается в `UnknownFailure` и не роняет
приложение. `MissingPluginException` — плагин не зарегистрирован, платформа не
поддержана — Dart сам превращает в `HelperUnavailableFailure`, отдельного кода
для этого не нужно.

Критерий приёмки M1 №4 — отказ в системном диалоге даёт **понятную ошибку, а не
тишину**. `permission_denied` обязан долетать до UI.

`message` попадает в `CoreCrashedFailure.log` и `ConfigInvalidFailure.detail`,
то есть **виден пользователю**. Креды туда не кладём.
`details` необязателен; Dart его логирует и не разбирает.

---

## Что нативная сторона делать не должна

Четыре вещи и всё, по [docs/02-architecture.md](../../../docs/02-architecture.md):
получить дескриптор TUN, реализовать `PlatformInterface`, управлять жизненным
циклом сервиса, показать системный UI.

Если в Kotlin появился разбор подписки, сборка конфига, выбор приложений для
раздельного туннелирования или расчёт маршрутов — это ошибка слоя. Маршруты и
списки пакетов приходят готовыми в `TunOptions`, их надо только переложить в
`VpnService.Builder`.

Отдельно: **Clash API на Android не поднимается.** Обратный поток идёт через
`CommandClient`; HTTP-сервер внутри процесса туннеля — лишняя память и лишняя
поверхность атаки. Clash API живёт только на десктопе
([ADR-0005](../../../docs/adr/0005-core-ipc.md)).

---

## Чек-лист для Kotlin-стороны

- [ ] пять каналов с именами ровно из первой таблицы;
- [ ] семь методов, каждый **всегда** отвечает `success` или `error`, без тихих
      веток;
- [ ] `start` и `stop` идемпотентны;
- [ ] `urlTest` ждёт `writeGroups` и возвращает `{"delayMs": …}`, а не `null`
      сразу;
- [ ] `/status` отдаёт текущее состояние сразу при `onListen`;
- [ ] `/traffic` молчит, когда `getTrafficAvailable() == false`;
- [ ] `/logs` умеет и одиночный объект, и массив;
- [ ] `/connections` шлёт полный снимок, накапливая дельты сам, не чаще 1 Гц;
- [ ] коды ошибок — только из таблицы выше;
- [ ] `Result` и `EventSink` — только с главного потока;
- [ ] `onCancel` отцепляет соответствующий `CommandClient`;
- [ ] смерть ядра доезжает до `state: "error"`, а не оставляет `connected`.

---

## Версионирование

Протокол не версионируется отдельно: Dart и Kotlin едут в одном APK. Ломающее
изменение — это одновременная правка `commy_core` и `native/android` в одном PR
плюс правка этого файла. Файл — часть diff'а, а не документация «потом».
