# `core/` — сетевое ядро

Go-модуль, который **пинит версию sing-box, выбирает build-теги и добавляет в
ядро то, чего в нём нет**. Своей обёртки над ядром здесь почти нет, и это
осознанно.

sing-box уже поставляет `experimental/libbox` — пакет, спроектированный ровно под
`gomobile bind`, на котором построен официальный Android-клиент sing-box. Писать
поверх него свой слой значило бы переизобретать и потом сопровождать чужой
движущийся API без единой выгоды.

Поэтому модуль делает четыре вещи:

1. фиксирует версию ядра в `go.mod` — бамп это отдельный PR со своим прогоном
   матрицы (правило R8);
2. держит `libbox` в графе модулей, чтобы `gomobile bind` до него дотянулся;
3. хранит немногое, чего в libbox нет: `internal/safe` и `cshared/`;
4. несёт **две правки закреплённого sing-box**, которые применяются только на
   время сборки — см. ниже.

---

## Оверлей: что мы меняем в sing-box и как

`go.mod` называет опубликованный `sing-box v1.13.16`, без `replace` и без форка.
Всё, чем наше ядро отличается от апстрима, — это список точных замен в
[`cmd/overlaygen/main.go`](cmd/overlaygen/main.go), который скрипт сборки
превращает в `go build -overlay`:

| Правка | Зачем | Где код | ADR |
|---|---|---|---|
| Транспорт **XHTTP** | в sing-box его нет, а серверов на нём всё больше | [`xhttp/`](xhttp) — обычный Go-пакет; в двух файлах апстрима добавлено 11 строк, чтобы имя `xhttp` до него дошло | [0010](../docs/adr/0010-xhttp-transport.md) |
| **ClientHello REALITY** | sing-box вырезает `X25519MLKEM768`, а Xray ≥ 26.9.8 без него клиента отвергает | девять замен в `common/tls/reality_client.go` | [0011](../docs/adr/0011-reality-client-hello.md) |

Каждый файл апстрима сверяется по SHA-256. Бамп sing-box, который задел любой
из них, останавливает сборку сообщением «перебазируй оверлей» — вкомпилировать
в ядро устаревшую копию чужого кода молча не получится.

```bash
cd core
go test -race ./...                       # транспорт и опции — без всякого оверлея

# сквозной тест через настоящий sing-box: VLESS поверх XHTTP, все режимы
TAGS=$(grep -oP '(?<=^readonly TAGS=")[^"]+' ../scripts/build_core.sh)
GODEBUG=goindex=0 go test -overlay="$(go run ./cmd/overlaygen)" \
  -tags "$TAGS,commy_overlay" -ldflags "-checklinkname=0" ./xhttp/
```

`GODEBUG=goindex=0` обязателен: без него `go` берёт список импортов пакета из
индекса модуля, про оверлей не знает, и сборка падает на `could not import`.
Собирать ядро руками, мимо `scripts/build_core.sh`, не надо: он передаёт всё это
сам и **проверяет готовую библиотеку**, потому что оверлей, который молча не
применился, даёт рабочее ядро, отказывающее каждому XHTTP-серверу.

Проверка против настоящего Xray (десять минут, без панели) — рецепт в
[../docs/17-agent-handoff.md](../docs/17-agent-handoff.md), «Сессия 13».

Точный API, который обязаны реализовать Kotlin и Swift, вычитан из исходников
закреплённого тега и лежит в [../docs/13-libbox-reference.md](../docs/13-libbox-reference.md).
Не по памяти — по коду.

---

## Сборка

```bash
scripts/build_core.sh android    # → core/build/libbox.aar → apps/commy/android/app/libs/
scripts/build_core.sh apple      # → core/build/Libbox.xcframework   (нужен macOS)
```

| Что | Значение |
|---|---|
| sing-box | `v1.13.16` |
| Java-пакет AAR | `io.nekohasekai.libbox` |
| NDK | `28.0.13004108` |
| `-androidapi` | 24 |

### Требования

- Go 1.24+
- `ANDROID_HOME`
- NDK. Если `ANDROID_NDK_HOME` не задан, скрипт берёт самый свежий из
  `$ANDROID_HOME/ndk`. Поставить: `sdkmanager --install 'ndk;28.0.13004108'`

Скрипт сам доставит `gomobile`, если его нет.

### Про время сборки

`gomobile bind` компилирует **всё ядро заново на каждую ABI**. На слабой машине
три ABI — это часы. Для локальной проверки хватает одной:

```bash
COMMY_ANDROID_ABIS=android/arm64 scripts/build_core.sh android
```

Полный набор `arm64 + arm + amd64` — работа CI, а не ноутбука.

---

## Теги

```
with_gvisor  with_quic  with_wireguard  with_utls  with_clash_api
badlinkname  tfogo_checklinkname0
```

Короче апстримного набора: выброшены `with_naive_outbound` (тянет `cronet-go` —
целый сетевой стек Chromium) и `with_tailscale` (весь клиент Tailscale). Ни NAIVE,
ни Tailscale не входят в список протоколов продукта, а вес критичен для правила R7.

Проверено по `include/registry.go` закреплённого тега, что **ничего заявленного не
потерялось**: VLESS, VMess, Trojan, Shadowsocks, ShadowTLS и AnyTLS
регистрируются безусловно; Hysteria2 и TUIC закрыты `with_quic`; WireGuard —
`with_wireguard`. Вернуть тег можно только вместе с внесением протокола в
[00-vision.md](../docs/00-vision.md).

### Три грабли, каждая стоит часа

**`badlinkname`, `tfogo_checklinkname0` и `-checklinkname=0` не опциональны.**
sing-box использует `go:linkname` на внутренние символы рантайма, Go 1.23+ это
запрещает по умолчанию, и линковка падает с невнятной ошибкой.

**`go mod tidy` не принимает `-tags`.** Он пишет `go.sum` только для конфигурации
по умолчанию, а `with_clash_api` и `with_quic` тянут модули, которых в ней нет.
Падает не резолв, а компиляция — и выглядит как сломанная версия sing-box:

```
missing go.sum entry for module providing package github.com/go-chi/render
```

Правильно — через переменную окружения, и ровно это делает `sync_modules` в
скрипте сборки:

```bash
GOFLAGS="-tags=$TAGS" go mod tidy
```

**`CGO_ENABLED=0` не проверяет полный набор тегов.** Годится как дешёвый
смоук-тест типов, но настоящая проверка — только `gomobile bind` с NDK.

---

## Что внутри

```
libbox.go            блank-импорт libbox + константа версии
xhttp/               клиент транспорта XHTTP (наш код; в sing-box его нет)
xhttp/config/        опции блока `transport` для xhttp; sing-box не импортирует
cmd/overlaygen/      генератор оверлея сборки: правки sing-box точной заменой
internal/safe/       превращение паники в строку ошибки на границе языка
cshared/             C ABI под dart:ffi для десктопа (M5–M7, не входит в 1.0)
build/               артефакты и `_overlay/` — не в гите
```

`internal/safe` — не перестраховка. Паника, пересёкшая cgo или JNI, не становится
ловимым исключением на той стороне: она роняет процесс, а в отчёте о падении
виден хостовый поток, а не Go-стек, который к этому привёл. Разобраться в таком с
устройства пользователя практически невозможно, поэтому каждая экспортируемая
точка входа оборачивается здесь.
