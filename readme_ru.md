# Commy

**Open-source прокси-клиент для ваших собственных серверов.** Android · iOS · Windows · macOS · Linux

[![CI](https://github.com/Makhkets/commy/actions/workflows/ci.yml/badge.svg)](https://github.com/Makhkets/commy/actions/workflows/ci.yml) [![Core](https://github.com/Makhkets/commy/actions/workflows/core.yml/badge.svg)](https://github.com/Makhkets/commy/actions/workflows/core.yml) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/Makhkets/commy/blob/main/LICENSE) [![Status](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/Makhkets/commy/blob/main/docs/07-roadmap.md) [![sing-box](https://img.shields.io/badge/sing--box-v1.13.16-2FD98A.svg)](https://github.com/SagerNet/sing-box) [![Flutter](https://img.shields.io/badge/Flutter-3.44.8-0468D7.svg)](https://flutter.dev)

Собрано из тех же экранов, что и в приложении. Интерфейс локализован: доступны русский и английский языки.

---

## Что такое Commy

Клиент, который подключает вас к **вашим собственным** серверам по VLESS/Reality, VMess,
Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard и ShadowTLS — с интерфейсом, который не
похож на заполнение JSON-формы.

Построен на ядре [sing-box](https://github.com/SagerNet/sing-box) с интерфейсом на [Flutter](https://flutter.dev), поэтому на всех платформах работает
один и тот же код и одинаковое поведение.

## Чем Commy не является

**Commy — не VPN-сервис.** Это принципиальное ограничение продукта, а не маркетинг:

- мы не держим серверов и не продаём доступ;
- в приложении нет встроенных бесплатных конфигов и каталога публичных серверов —
  приложение пустое, пока вы сами не импортируете что-то;
- нет аккаунтов, нет бэкенда, нет телеметрии.

## Статус

**Альфа.** Пре-релизные APK собираются из тегов и публикуются в разделе [Releases](https://github.com/Makhkets/commy/releases); в магазинах приложений пока не размещён.

| Платформа             | Состояние                                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------- |
| **Android**             | Приложение и туннель написаны, APK собирается с ядром внутри. Ещё не проверено на реальном сервере  |
| **iOS**                 | Не начато — [этап M4](https://github.com/Makhkets/commy/blob/main/docs/07-roadmap.md), главный риск проекта |
| **Windows**             | Не начато — запланировано на версию 1.1                                                              |
| **macOS**, **Linux**   | Не начато — запланировано на версию 1.2                                                              |

Что уже есть: шесть Dart-пакетов, покрытых 699 тестами, ядро sing-box, собранное под три
Android ABI, туннель для Android (`VpnService`, все 15 методов `PlatformInterface`, boot
receiver, плитка быстрых настроек, обработка Doze), все экраны приложения, диплинки для
шести URL-схем, русская и английская локализация.

Чего честно не хватает: туннель ни разу не пропускал трафик через реальный сервер, поэтому
ни один из четырёх критериев приёмки этапа M1 пока не может быть отмечен выполненным.
Подэкраны роутинга (DNS, per-app, наборы правил) смоделированы и сгенерированы, но не имеют
UI. Прогресс отслеживается в [roadmap](https://github.com/Makhkets/commy/blob/main/docs/07-roadmap.md).

## Зачем ещё один клиент

| Клиент             | В чём пробел                            |
| ------------------- | ---------------------------------------- |
| v2rayNG, NekoBox    | Только Android                          |
| sing-box official   | Отличное ядро, минималистичный интерфейс |
| Hiddify             | Все платформы, но перегруженный интерфейс |
| Happ, INCY          | Отличный UX — но **закрытый исходный код** |

Сегодня ничто не сочетает хороший UX, все пять платформ **и** открытый код одновременно.
Для софта, через который проходит весь ваш трафик, возможность аудита — это не приятный
бонус, а необходимость.

## Принципы

1. **Только ваши серверы и ничего больше.** Никаких встроенных конфигов, никаких партнёрских интеграций.
2. **Тишина в сети.** Ноль исходящих запросов, которые вы не инициировали сами. Ровно три
   опциональных исключения, все инициируются пользователем и перечислены на одном экране настроек.
3. **Прозрачность важнее удобства.** Любой сгенерированный конфиг можно открыть и прочитать.
4. **Одинаковое поведение везде.** Правило маршрутизации, написанное на телефоне, работает
   точно так же на ноутбуке.
5. **Без рекламы, без платных тарифов, без аккаунтов.**

## Протоколы

VLESS (включая Reality) · VMess · Trojan · Shadowsocks · Hysteria2 · TUIC ·
WireGuard · ShadowTLS · SOCKS · HTTP

Транспорты для VLESS, VMess и Trojan: TCP · WebSocket · gRPC · HTTP/2 ·
HTTPUpgrade · QUIC · **XHTTP** (`packet-up`, `stream-up`, `stream-one`; поверх
HTTP/1.1, HTTP/2 и HTTP/3, с Reality). В самом sing-box XHTTP нет — клиент наш,
лежит в [`core/xhttp`](core/xhttp), и сборка добавляет его в закреплённое ядро
без форка ([как и почему](docs/adr/0010-xhttp-transport.md)).

Импорт по ссылке-подписке, из share-ссылки, QR-кода, файла, диплинка или буфера обмена.
Ответы подписок читаются как обычный список, base64, Clash YAML или sing-box JSON, а
заголовки `subscription-userinfo` превращаются в отображаемые на карточке квоту и срок действия.

## Запланированные функции

Подключение к собственным серверам со статистикой трафика в реальном времени · импорт
подписок с отслеживанием квоты и срока действия · импорт через QR, диплинк и файл ·
тестирование задержки и автоматический выбор лучшего узла · маршрутизация на основе правил
с geoip/geosite · раздельное туннелирование по приложениям · управление DNS с защитой от
утечек · kill switch · живые логи и просмотр активных соединений · тёмная и светлая темы ·
русский и английский языки.

Полный каталог с этапами: [docs/07-roadmap.md](https://github.com/Makhkets/commy/blob/main/docs/07-roadmap.md)

## Документация

|                                                                               |                                          |
| ------------------------------------------------------------------------------ | ------------------------------------------ |
| [Видение](https://github.com/Makhkets/commy/blob/main/docs/00-vision.md)                          | Продукт, аудитория, явные не-цели          |
| [Стек](https://github.com/Makhkets/commy/blob/main/docs/01-stack.md)                              | Все зависимости и почему они выбраны       |
| [Архитектура](https://github.com/Makhkets/commy/blob/main/docs/02-architecture.md)                | Слои, поток данных, `CoreClient`           |
| [Платформенные туннели](https://github.com/Makhkets/commy/blob/main/docs/03-platform-tunnel.md)   | Как туннель работает на каждой ОС          |
| [Roadmap](https://github.com/Makhkets/commy/blob/main/docs/07-roadmap.md)                         | Этапы с критериями приёмки                 |
| [Безопасность и приватность](https://github.com/Makhkets/commy/blob/main/docs/09-security-privacy.md) | Модель угроз, чек-лист утечек          |
| [Решения (ADR)](https://github.com/Makhkets/commy/blob/main/docs/adr)                             | Architecture Decision Records              |

Документы спецификаций написаны на русском языке; код, идентификаторы и сообщения коммитов — на английском.

## Сборка

**Требования**

|                | |
| -------------- | ------------------------------------------------------- |
| Flutter        | 3.44.8 (поставляется с Dart 3.12.2)                      |
| Go             | 1.24+                                                    |
| JDK            | 17 — Android Gradle Plugin не примет 21                  |
| Android SDK    | platform 36, build-tools 36.0.0                          |
| Android NDK    | **28.0.13004108** — версия, с которой собирается sing-box |

**Сборка**

```
# 1. ядро sing-box -> apps/commy/android/app/libs/libbox.aar
#    gomobile пересобирает всё ядро заново под каждый ABI, поэтому начните с одного
COMMY_ANDROID_ABIS=android/arm64 scripts/build_core.sh android

# 2. Dart-часть. melos должен быть в PATH, а не просто в dev_dependency: его
#    скрипты вызывают `melos exec`, и `dart run melos run <script>` не может
#    разрешить это изнутри себя самого. Активируйте версию, закреплённую в pubspec.yaml.
dart pub get
dart pub global activate melos 6.3.3   # затем добавьте ~/.pub-cache/bin в PATH
melos bootstrap
melos run gen --no-select              # генерация кода drift + slang

# 3. запуск
cd apps/commy && flutter run -d <device>
```

`--no-select` нужен только в неинтерактивном терминале: любой `melos run`, чей
скрипт использует фильтры по пакетам, иначе останавливается с запросом выбора.
На Windows запускайте melos из PowerShell, а не из Git Bash — там он падает при
декодировании вывода дочернего процесса в не-UTF-8 локали.

APK не соберётся без шага 1: ядро — это нативная библиотека, а не pub-пакет.
`scripts/build_core.sh` сам устанавливает `gomobile` и завершится с понятным
сообщением об ошибке, если отсутствует NDK.

**Если сборка ядра падает**, сначала посмотрите
[docs/13-libbox-reference.md](https://github.com/Makhkets/commy/blob/main/docs/13-libbox-reference.md).
Там описаны четыре ловушки, из-за которых происходит почти всё большинство здешних
ошибок — в том числе то, что `golang.org/x/mobile` из апстрима — это *не тот*
gomobile (sing-box нужен форк от SagerNet), и что `go mod tidy` молча
игнорирует `-tags`, из-за чего получается `go.sum`, который ломается позже,
уже на этапе компиляции.

**Проверки**

```
melos run analyze --no-select          # статический анализ; предупреждения = ошибки
melos run test --no-select             # unit- и widget-тесты
python scripts/check_wire_contract.py  # контракт канала Dart <-> Kotlin
```

## Контрибьютинг

Контрибьюции приветствуются — см. [CONTRIBUTING.md](https://github.com/Makhkets/commy/blob/main/CONTRIBUTING.md).
CLA нет: контрибьюции принимаются на условиях GPL-3.0-or-later — той же лицензии,
что и у проекта, а значит его нельзя будет тихо перелицензировать или закрыть.

Нашли уязвимость безопасности? Пожалуйста, сначала прочитайте
[SECURITY.md](https://github.com/Makhkets/commy/blob/main/SECURITY.md) — не создавайте публичный issue.

## Лицензия

[GPL-3.0-or-later](https://github.com/Makhkets/commy/blob/main/LICENSE). Унаследована от sing-box,
и хорошо подходит: клиент, через который проходит весь ваш трафик, должен оставаться
открытым, в том числе и в форках.

Сторонние компоненты и совместимость лицензий: [docs/11-licensing.md](https://github.com/Makhkets/commy/blob/main/docs/11-licensing.md).

## Благодарности

[sing-box](https://github.com/SagerNet/sing-box) от SagerNet, без которого этот проект был бы
многолетним трудом, а не клиентом. [Hiddify](https://github.com/hiddify/hiddify-app) и [Karing](https://github.com/KaringX/karing)
доказали жизнеспособность связки Flutter + sing-box на всех пяти платформах.
