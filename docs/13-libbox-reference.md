# 13 · Справочник по libbox (sing-box v1.13.16)

> Выдержка из исходников `github.com/sagernet/sing-box@v1.13.16`, раздел
> `experimental/libbox`. Это **факт, а не пересказ** — всё ниже прочитано из кода,
> а не из документации и не по памяти.
>
> Зачем документ: Kotlin-сторона обязана реализовать `PlatformInterface` **точно** —
> gomobile генерирует Java-интерфейс по этой сигнатуре, и любое расхождение
> ломает сборку на этапе линковки, а не в рантайме.
>
> Обновляется только вместе с бампом версии ядра (правило R8).

---

## Пин версии

| Что | Значение |
|---|---|
| sing-box | **v1.13.16** (релиз от 2026-08-03, не пре-релиз) |
| Java-пакет AAR | `io.nekohasekai.libbox` |
| Имя библиотеки | `box` → артефакт `libbox.aar` |
| minSdk сборки `android-main` | **23** |
| NDK, на котором собирает апстрим | **28.0.13004108** |

Ветка `v1.14.0` существует, но только в alpha/beta — не берём.

`io.nekohasekai` как имя пакета оставлено **намеренно**: все примеры и исходники
официального Android-клиента sing-box используют именно его, и совпадение имён
экономит часы при сверке. Своё имя через `-javapkg` технически работает, но
лишает возможности копировать код апстрима один в один.

---

## Build-теги

Взяты из `experimental/libbox/ffi.json`, сборка `android-main`:

```
with_gvisor          with_quic            with_wireguard       with_utls
with_naive_outbound  with_clash_api       badlinkname          tfogo_checklinkname0
with_tailscale       ts_omit_logtail      ts_omit_ssh          ts_omit_drive
ts_omit_taildrop     ts_omit_webclient    ts_omit_doctor       ts_omit_capture
ts_omit_kube         ts_omit_aws          ts_omit_synology     ts_omit_bird
```

```
ldflags: -X github.com/sagernet/sing-box/constant.Version=<version>
         -X internal/godebug.defaultGODEBUG=multipathtcp=0
         -s -w -buildid= -checklinkname=0
trimpath: true
```

⚠️ **`badlinkname`, `tfogo_checklinkname0` и `-checklinkname=0` обязательны.**
Без них сборка падает на современных Go: sing-box использует `go:linkname` на
внутренние символы рантайма, а Go 1.23+ это запрещает по умолчанию. Это первое,
что стоит проверить, если `gomobile bind` упал с ошибкой линковки.

`with_dhcp` и `with_ech` в андроид-сборку апстрима **не входят** — не добавляем
их «на всякий случай», каждый тег тянет зависимости и вес.

### Наш набор тегов короче апстримного

Мы берём **не весь** список апстрима:

```
with_gvisor  with_quic  with_wireguard  with_utls  with_clash_api
badlinkname  tfogo_checklinkname0
```

Выброшены `with_naive_outbound` и `with_tailscale` (вместе со всей гроздью
`ts_omit_*`). Причина: **мы не обещаем ни NAIVE, ни Tailscale** — список
протоколов продукта закрыт и лежит в [00-vision.md](00-vision.md). Каждый из этих
двух тегов тянет тяжёлую зависимость: `with_naive_outbound` — `cronet-go`
(целый Chromium-сетевой стек), `with_tailscale` — весь клиент Tailscale.
Это прямо работает на правило R7 (расширение iOS живёт в 50 MiB).

Проверено по `include/registry.go` тега v1.13.16, что от урезания **не страдает
ни один заявленный протокол**:

| Протокол | Чем закрыт |
|---|---|
| VLESS, VMess, Trojan, Shadowsocks, ShadowTLS, AnyTLS | регистрируются **безусловно**, тег не нужен |
| Hysteria2, TUIC, Hysteria | `with_quic` ✅ |
| WireGuard | `with_wireguard` ✅ |
| Reality / отпечатки TLS | `with_utls` ✅ |
| gVisor-стек для TUN | `with_gvisor` ✅ |
| Clash API (десктоп, статистика) | `with_clash_api` ✅ |
| NAIVE | `with_naive_outbound` ❌ не обещаем |
| Tailscale | `with_tailscale` ❌ не обещаем |

Урезанный набор проверен сборкой: `GOOS=android GOARCH=arm64 go build` проходит
чисто. Возвращать тег обратно — значит сначала внести протокол в список продукта.

### gomobile нужен **форк SagerNet**, а не апстримный

`go install golang.org/x/mobile/cmd/gomobile@latest` даёт инструмент, который
**не знает флага `-libname`** и в ответ на него печатает справку и выходит с
нулевым кодом — то есть выглядит как успешная сборка, после которой просто нет
файла. sing-box v1.13.16 в своём `Makefile` ставит другое:

```bash
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.12
```

Плюс `gobind` резолвит пакет `github.com/sagernet/gomobile/bind` **из того модуля,
который биндит**, а не из своей установки. Без явной зависимости получаем:

```
"github.com/sagernet/gomobile/bind" is not found; run go get github.com/sagernet/gomobile/bind
```

что читается как сломанная установка gomobile, а не как отсутствующая зависимость.
Поэтому в `core/internal/tools/gomobile.go` лежит файл под тегом `tools` с
blank-импортом этого пакета — только чтобы удержать его в графе модулей.

### `javac` ищется мимо шелла

gomobile вызывает `javac` для компиляции сгенерированных Java-биндингов и ищет
его средствами ОС, а не шелла. Под Git Bash запись PATH в Unix-виде
(`C:/dev/jdk17/bin`) для этого поиска **невидима**, и сборка доходит до
`aar: classes.jar` — то есть компилирует всё ядро целиком — и только там падает:

```
exec: "javac": executable file not found in %PATH%
```

`scripts/build_core.sh` решает это в `need_javac`: резолвит JDK из `JAVA_HOME`,
прогоняет путь через `cygpath -u` и добавляет в PATH до вызова gomobile.

### `go mod tidy` не принимает `-tags`

Отдельные грабли, на которых теряется время. `go mod tidy` записывает `go.sum`
только для конфигурации по умолчанию, а `with_clash_api`, `with_quic` и
`with_naive_outbound` подтягивают модули, которых в ней нет. Падает при этом не
резолв, а компиляция — и выглядит так, будто сломана версия sing-box:

```
missing go.sum entry for module providing package github.com/go-chi/render
missing go.sum entry for module providing package github.com/sagernet/quic-go
```

Правильно — прогонять tidy с теми же тегами через переменную окружения:

```bash
GOFLAGS="-tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0" \
  go mod tidy
```

Это же обязано быть в `scripts/build_core.sh` и в CI, иначе на чистом клоне
сборка упадёт на первом же прогоне.

---

## Жизненный цикл: `CommandServer` + `CommandClient`

Первое, что стоит знать: **функции `NewService` не существует**. Туннель
поднимается через `CommandServer`, и это же единственная точка, куда отдаётся
JSON конфига.

```
VpnService (наш процесс туннеля)
└─ CommandServer(CommandServerHandler, PlatformInterface)
     .start()
     .startOrReloadService(configJSON, OverrideOptions)   ← туннель поднимается ЗДЕСЬ
     .closeService()
     .pause() / .wake()          ← Doze: усыпить и разбудить ядро
     .resetNetwork()             ← дёргается при смене сети
     .updateWIFIState()
     .setError(String)

UI (Flutter-сторона через каналы)
└─ Libbox.newCommandClient(CommandClientHandler, CommandClientOptions)
     .connect()
     .selectOutbound(groupTag, outboundTag)   ← смена узла без разрыва
     .urlTest(groupTag)
     .closeConnection(id) / .closeConnections()
     .serviceReload() / .serviceClose()
     .getStartedAt()
```

Под каждую подписку поднимается **свой** `CommandClient` со своим
`options.addCommand(...)`: `Libbox.CommandStatus`, `CommandLog`, `CommandGroup`,
`CommandConnections`, `CommandClashMode`.

`CommandServerHandler` — то, что сервер спрашивает у платформы:
`serviceReload()`, `serviceStop()`, `getSystemProxyStatus()`,
`setSystemProxyEnabled(boolean)`, `writeDebugMessage(String)`.

Статические функции `Libbox`, которые действительно понадобятся:

| Метод | Зачем |
|---|---|
| `setup(SetupOptions)` | вызывается **до всего остального**, один раз |
| `newCommandServer(handler, platform)` | сервис туннеля |
| `newCommandClient(handler, options)` | подписка на статус/логи/группы/соединения |
| `checkConfig(String)` / `formatConfig(String)` | валидация и красивый вывод конфига на экране «Конфиг» |
| `randomHex(int)` | секрет command server — свой CSPRNG не нужен |
| `availablePort(int)` | подобрать свободный порт под command server |
| `setMemoryLimit(boolean)` | режим экономии памяти, пригодится для R7 |
| `redirectStderr(String)` | сохранить нативный краш в файл |
| `version()`, `formatBytes()`, `formatDuration()` | экран «О программе», метрики |
| `setLocale(String)` | локализация сообщений ядра |

---

## `PlatformInterface` — точная сигнатура для Kotlin

Ниже **не пересказ исходников Go, а вывод `javap` по собранному нами
`libbox.aar`** — ровно то, что увидит компилятор Kotlin. gomobile переводит имена
в camelCase, и расхождение здесь ломает сборку на линковке, а не в рантайме.

```java
interface io.nekohasekai.libbox.PlatformInterface {
  boolean              usePlatformAutoDetectInterfaceControl();
  void                 autoDetectInterfaceControl(int fd) throws Exception;
  int                  openTun(TunOptions options) throws Exception;
  boolean              useProcFS();
  ConnectionOwner      findConnectionOwner(int ipProtocol,
                                           String sourceAddress, int sourcePort,
                                           String destinationAddress, int destinationPort)
                                           throws Exception;
  void                 startDefaultInterfaceMonitor(InterfaceUpdateListener l) throws Exception;
  void                 closeDefaultInterfaceMonitor(InterfaceUpdateListener l) throws Exception;
  NetworkInterfaceIterator getInterfaces() throws Exception;
  boolean              underNetworkExtension();
  boolean              includeAllNetworks();
  WIFIState            readWIFIState();
  StringIterator       systemCertificates();
  LocalDNSTransport    localDNSTransport();
  void                 clearDNSCache();
  void                 sendNotification(Notification n) throws Exception;
}
```

Что возвращать на Android:

| Метод | Реализация |
|---|---|
| `usePlatformAutoDetectInterfaceControl` | `true` |
| `autoDetectInterfaceControl(fd)` | `VpnService.protect(fd)`; при `false` — бросить |
| `openTun(options)` | собрать `VpnService.Builder` из `options`, вернуть **fd** |
| `useProcFS` | `false` — на Android 10+ `/proc/net` закрыт |
| `findConnectionOwner` | `connectivityManager.getConnectionOwnerUid(...)`, затем `setUserId` и `setAndroidPackageNames` |
| `startDefaultInterfaceMonitor` | зарегистрировать `NetworkCallback`, звать `listener.updateDefaultInterface(...)` |
| `getInterfaces` | `NetworkInterface.getNetworkInterfaces()` → итератор |
| `underNetworkExtension` | `false` — это про iOS |
| `includeAllNetworks` | `false` |
| `readWIFIState` | `Libbox.newWIFIState(ssid, bssid)` или `null` без разрешения на локацию |
| `systemCertificates` | пустой итератор — Android отдаёт их сам |
| `localDNSTransport` | `null`, пока не делаем свой DNS-транспорт |
| `clearDNSCache` | no-op |
| `sendNotification` | системное уведомление |

Что писать в реализации на Android:

| Метод | Что возвращаем |
|---|---|
| `UsePlatformAutoDetectInterfaceControl` | `true` |
| `AutoDetectInterfaceControl(fd)` | `VpnService.protect(fd)`; при `false` — бросить ошибку |
| `OpenTun(options)` | строим `VpnService.Builder` из `options`, возвращаем **fd** |
| `UseProcFS` | `false` — на Android 10+ `/proc/net` недоступен, владельца ищем через `ConnectivityManager` |
| `FindConnectionOwner` | `connectivityManager.getConnectionOwnerUid(...)` → `ConnectionOwner` с `UserId` и `SetAndroidPackageNames` |
| `StartDefaultInterfaceMonitor` | регистрируем `NetworkCallback`, на каждое изменение зовём `listener.UpdateDefaultInterface(...)` |
| `GetInterfaces` | `NetworkInterface.getNetworkInterfaces()` → итератор |
| `UnderNetworkExtension` | `false` (это про iOS) |
| `IncludeAllNetworks` | `false` |
| `ReadWIFIState` | SSID/BSSID или `null` без разрешения на локацию |
| `SystemCertificates` | пустой итератор — Android отдаёт их сам |
| `ClearDNSCache` | no-op |
| `SendNotification` | системное уведомление |

### `InterfaceUpdateListener` — это и есть выживание при смене сети

```java
interface InterfaceUpdateListener {
  void updateDefaultInterface(String interfaceName, int interfaceIndex,
                              boolean isExpensive, boolean isConstrained);
}
```

Критерий приёмки M1 №2 («туннель переживает Wi-Fi ↔ мобильную сеть») закрывается
**именно этим вызовом плюс `CommandServer.resetNetwork()`**, а не пересозданием
TUN. Пришёл `onAvailable` / `onLinkPropertiesChanged` → зовём
`updateDefaultInterface`. Всё.

Аналогично Doze: `CommandServer.pause()` при уходе в сон и `wake()` при выходе —
не рестарт сервиса.

### `ConnectionOwner`

```java
class ConnectionOwner {
  int    getUserId();      void setUserId(int);
  String getUserName();    void setUserName(String);
  String getProcessPath(); void setProcessPath(String);
  StringIterator androidPackageNames();
  void setAndroidPackageNames(StringIterator);
}
```

### `StatusMessage` — что приходит в `writeStatus`

```java
long getMemory();        int  getGoroutines();
int  getConnectionsIn(); int  getConnectionsOut();
boolean getTrafficAvailable();
long getUplink();        long getDownlink();
long getUplinkTotal();   long getDownlinkTotal();
```

Ложится в доменный `TrafficSample` один в один. `getTrafficAvailable()` — это
признак того, что статистика вообще собирается; без него нули из `getUplink()`
не отличить от «трафика нет».

### `RoutePrefix`

```java
String address();  int prefix();  String mask();  String string();
```

Заметь: методы **без** префикса `get`. `RoutePrefixIterator` даёт `hasNext()`,
`next()`, `len()`.

---

## `TunOptions` — из чего собирается `VpnService.Builder`

`experimental/libbox/tun.go`. **Маршруты считает sing-box, не Kotlin.**

```go
type TunOptions interface {
    GetInet4Address() RoutePrefixIterator
    GetInet6Address() RoutePrefixIterator
    GetDNSServerAddress() (*StringBox, error)
    GetMTU() int32
    GetAutoRoute() bool
    GetStrictRoute() bool
    GetInet4RouteAddress() RoutePrefixIterator
    GetInet6RouteAddress() RoutePrefixIterator
    GetInet4RouteExcludeAddress() RoutePrefixIterator
    GetInet6RouteExcludeAddress() RoutePrefixIterator
    GetInet4RouteRange() RoutePrefixIterator
    GetInet6RouteRange() RoutePrefixIterator
    GetIncludePackage() StringIterator
    GetExcludePackage() StringIterator
    IsHTTPProxyEnabled() bool
    GetHTTPProxyServer() string
    GetHTTPProxyServerPort() int32
    GetHTTPProxyBypassDomain() StringIterator
    GetHTTPProxyMatchDomain() StringIterator
}
```

`RoutePrefix` отдаёт `Address()`, `Prefix()`, `Mask()`.

**Следствие, которое легко упустить:** раздельное туннелирование по приложениям
задаётся в JSON-конфиге (`inbounds[tun].include_package` / `exclude_package`),
а Kotlin просто перекладывает `GetIncludePackage()` / `GetExcludePackage()` в
`addAllowedApplication` / `addDisallowedApplication`. Своей логики выбора
приложений в Kotlin быть не должно — это нарушение слоя.

При `GetAutoRoute() == true` маршруты берутся из `GetInet4RouteRange()` /
`GetInet6RouteRange()`, а не выдумываются как `0.0.0.0/0`.

---

## Обратный поток: `CommandClient`, а не Clash API

На мобайле статус, логи, группы и соединения приходят через **command server**
внутри libbox — Clash API там не нужен.

```go
const (
    CommandLog int32 = iota   // 0
    CommandStatus             // 1
    CommandGroup              // 2
    CommandClashMode          // 3
    CommandConnections        // 4
)

type CommandClientHandler interface {
    Connected()
    Disconnected(message string)
    SetDefaultLogLevel(level int32)
    ClearLogs()
    WriteLogs(messageList LogIterator)
    WriteStatus(message *StatusMessage)
    WriteGroups(message OutboundGroupIterator)
    InitializeClashMode(modeList StringIterator, currentMode string)
    UpdateClashMode(newMode string)
    WriteConnectionEvents(events *ConnectionEvents)
}

type CommandClientOptions struct { StatusInterval int64 }
func (o *CommandClientOptions) AddCommand(command int32)
```

Методы клиента:

```
Connect / ConnectWithFD / Disconnect
SelectOutbound(groupTag, outboundTag)     ← смена узла без разрыва туннеля
URLTest(groupTag)                          ← замер задержки
SetClashMode(newMode)
CloseConnection(connId) / CloseConnections()
ServiceReload() / ServiceClose()
ClearLogs()
GetSystemProxyStatus / SetSystemProxyEnabled
GetDeprecatedNotes / GetStartedAt / SetGroupExpand
```

**`SelectOutbound` — это и есть «смена узла на лету»** из сценария 2
[05-ux-flows.md](05-ux-flows.md#сценарий-2--подключение). Один клиент на команду:
под каждую подписку (`CommandStatus`, `CommandLog`, …) поднимается свой
`CommandClient` со своим `AddCommand`.

---

## `Setup` — вызывается до всего остального

`experimental/libbox/setup.go`:

```go
type SetupOptions struct {
    BasePath                string
    WorkingPath             string
    TempPath                string
    FixAndroidStack         bool
    CommandServerListenPort int32
    CommandServerSecret     string
    LogMaxLines             int
    Debug                   bool
}
func Setup(options *SetupOptions) error
func SetLocale(localeId string)
func Version() string
```

Плюс полезное: `FormatBytes`, `FormatMemoryBytes`, `FormatDuration`,
`ProxyDisplayType`, `AvailablePort(startPort)`, `RandomHex(length)`.

`RandomHex` — то, чем генерируется `CommandServerSecret`. Своего CSPRNG для этого
писать не надо.

---

## Схема конфига: что проверять в `SingBoxConfigBuilder`

Прочитано из `option/*.go` того же тега. Неверное имя поля здесь — это **молча
не поднявшийся туннель**, поэтому сверяем буквально.

### VLESS + Reality — основной случай

`option/vless.go` + `option/tls.go`:

```json
{
  "type": "vless",
  "tag": "proxy",
  "server": "nl-03.example.net",
  "server_port": 443,
  "uuid": "…",
  "flow": "xtls-rprx-vision",
  "packet_encoding": "xudp",
  "tls": {
    "enabled": true,
    "server_name": "…",
    "insecure": false,
    "alpn": ["h2", "http/1.1"],
    "utls":    { "enabled": true, "fingerprint": "chrome" },
    "reality": { "enabled": true, "public_key": "…", "short_id": "…" }
  },
  "transport": { "type": "ws", "path": "/", "headers": {} }
}
```

⚠️ **У Reality в outbound ровно три поля:** `enabled`, `public_key`, `short_id`.
Поля `spider_x` **нет** — параметр `spx` из ссылки sing-box игнорирует. Парсер
его читает (чтобы не терять при экспорте обратно в ссылку), но в конфиг не кладёт.

Транспорты (`option/v2ray_transport.go`), поля только те, что перечислены:

| `type` | Поля |
|---|---|
| `ws` | `path`, `headers`, `max_early_data`, `early_data_header_name` |
| `grpc` | `service_name`, `idle_timeout`, `ping_timeout`, `permit_without_stream` |
| `http` | `host` (список), `path`, `method`, `headers`, `idle_timeout`, `ping_timeout` |
| `httpupgrade` | `host` (строка, **не список**), `path`, `headers` |

`server` / `server_port` приходят из общего `ServerOptions`, `detour` и прочее —
из `DialerOptions`.

### TUN inbound — половина полей переименована в 1.12+

`option/tun.go`. Актуальные имена:

```json
{
  "type": "tun",
  "tag": "tun-in",
  "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
  "mtu": 9000,
  "auto_route": true,
  "strict_route": true,
  "stack": "mixed",
  "route_address": [],
  "route_exclude_address": [],
  "include_package": [],
  "exclude_package": ["dev.commy.app"]
}
```

⚠️ **Помечены `Deprecated` и использоваться не должны:**
`inet4_address`, `inet6_address` → слиты в **`address`**;
`inet4_route_address`, `inet6_route_address` → **`route_address`**;
`inet4_route_exclude_address`, `inet6_route_exclude_address` → **`route_exclude_address`**;
`endpoint_independent_nat` и `gso` — удалены совсем.

Это самая частая ошибка при переносе конфигов из статей и из старых клиентов:
поля со старыми именами не вызывают ошибку валидации, они просто не применяются.

Раздельное туннелирование задаётся здесь — `include_package` / `exclude_package`,
и **собственный пакет всегда в исключениях**, иначе трафик приложения уйдёт в петлю.

---

## Что это меняет в наших планах

1. **Clash API на мобайле не нужен.** `commy_core` использует Clash API только
   на десктопе; на Android обратный поток идёт через `CommandClient`.
2. **Kotlin не считает маршруты и не выбирает приложения** — только перекладывает
   то, что дал `TunOptions`.
3. **Смена узла** — это `SelectOutbound`, а не пересборка конфига и рестарт.
4. **NDK 28.0.13004108**, не 27.x.
5. **Секрет command server** — `libbox.RandomHex(16)`.
