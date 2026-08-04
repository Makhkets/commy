# 06 · Модель данных, парсеры и генератор конфига

## Доменные сущности

Всё во `freezed`, всё иммутабельно. Живут в `commy_domain`, ничего не знают ни
о БД, ни о sing-box.

```dart
/// Источник узлов: подписка или ручной ввод.
class Profile {
  String        id;
  String        name;
  ProfileSource source;          // remote(Uri) | local | manual
  DateTime?     lastUpdatedAt;
  Duration?     autoUpdateEvery; // null = не обновлять автоматически
  SubscriptionInfo? info;        // квота и срок, если сервер их отдал
  bool          isActive;
}

/// Один сервер. Креды внутри `credentials`, не в открытых полях.
class Node {
  String      id;
  String      profileId;
  String      tag;               // отображаемое имя
  Protocol    protocol;          // vless | vmess | trojan | shadowsocks
                                 // hysteria2 | tuic | wireguard | ssh | socks | http
  String      host;
  int         port;
  String?     group;             // группа из подписки, если есть
  NodeSecrets credentials;       // ← в зашифрованном хранилище
  Map<String, dynamic> transport;// tls, reality, ws, grpc, mux…
  Duration?   lastLatency;
  DateTime?   lastTestedAt;
}

/// Квота и срок из заголовка подписки.
class SubscriptionInfo {
  int?      uploadBytes;
  int?      downloadBytes;
  int?      totalBytes;
  DateTime? expiresAt;
  String?   title;              // profile-title
  Duration? updateInterval;     // profile-update-interval
}

/// Политика маршрутизации.
class RoutingPolicy {
  String      id;
  String      name;
  RoutingMode mode;             // global | rules | direct
  List<RoutingRule> rules;
  AppRuleSet? appRules;         // split tunneling, где поддерживается
  DnsPolicy   dns;
}

sealed class TunnelStatus {
  // idle | starting | connected(since, node) | stopping | error(failure)
}
```

---

## Хранилище

Два физически разных места. Разделение — не стилистическое, а следствие
правила **R2**.

### Открытая часть · SQLite через Drift

Сюда попадает только то, чья утечка не даёт доступа к серверу пользователя.

| Таблица | Поля | Заметки |
|---|---|---|
| `profiles` | id, name, source_type, secret_ref, last_updated_at, auto_update_every, info_json, is_active | `secret_ref` — **ключ** в secure storage, а не сам URL |
| `nodes` | id, profile_id, tag, protocol, host, port, group_name, transport_json, secret_ref, latency_ms, tested_at | То же: креды по ссылке |
| `routing_policies` | id, name, mode, rules_json, dns_json, is_active | |
| `app_rules` | policy_id, identifier, mode | `identifier` = package (Android) / путь exe (Windows) |
| `traffic_daily` | day, profile_id, up_bytes, down_bytes | Агрегат для графика; сырые соединения не храним |
| `settings` | key, value_json | Ключ-значение для настроек приложения |
| `import_failures` | id, raw_snippet, reason, created_at | Что не распарсилось — показываем пользователю |

### Секретная часть · `flutter_secure_storage`

- URL подписок (в них токен доступа);
- `NodeSecrets`: UUID, пароли, приватные ключи, Reality short-id;
- ключ шифрования БД;
- токен доступа к десктопному хелперу.

Бэкенды: Keychain (Apple), Keystore/EncryptedSharedPreferences (Android),
DPAPI (Windows), libsecret (Linux).

> **Linux — известная слабость.** Если в системе нет keyring, `libsecret`
> недоступен. Тогда приложение обязано **честно сказать** пользователю, что
> секреты будут лежать в файле с правами `0600`, и дать выбор, а не тихо
> деградировать. Молчаливое понижение защиты — это баг.

### Шифрование

> ⚠️ **Этот раздел устарел. Действующее решение —
> [ADR-0007](adr/0007-database-encryption.md).**
>
> `sqlcipher_flutter_libs` и `sqlite3_flutter_libs` в августе 2026 объявлены EOL
> («update to version 3.x of package:sqlite3»), шифрование в `sqlite3` 3.x
> переехало на Dart build hooks. В 1.0 **вся база не шифруется**: креды, ссылки
> подписок целиком и сгенерированный конфиг ядра уходят в secure storage поверх
> Keystore/Keychain, в SQLite остаются только метаданные. Аргументация, что мы
> при этом теряем и почему это не ослабление R2, — в ADR.
>
> Текст ниже сохранён как исходное намерение.

БД открывается через **SQLCipher** (`sqlcipher_flutter_libs`). Ключ генерируется
при первом запуске (32 байта из CSPRNG) и кладётся в secure storage.

Зачем шифровать и секреты, и БД, если секреты и так в secure storage: сгенерированный
конфиг sing-box содержит **все креды в открытом виде**, и он кешируется. Плюс
`transport_json` может содержать чувствительные параметры. Дешевле зашифровать
всё, чем каждый раз решать, что чувствительно.

Именно из-за этого абзаца конфиг ядра в ADR-0007 отправлен целиком в secure
storage, а не в колонку: наблюдение верное, вывод из него теперь другой.

### Миграции

Drift-миграции нумерованные, вперёд-только. На каждую — тест, который открывает
БД предыдущей версии и проверяет, что данные пережили переезд. Пользователь VPN-
клиента, потерявший все профили после обновления, — потерянный пользователь.

---

## Парсеры импорта

Пакет `commy_config`. Вход — произвольная строка от пользователя. Выход —
`(List<Node>, List<ImportFailure>)`.

### Определение формата

```
строка
  ├─ начинается с известной схемы?  → протокольная ссылка (одна или список)
  ├─ валидный JSON?                 → sing-box / Xray / v2rayN конфиг
  ├─ валидный YAML с ключом proxies?→ Clash / Clash.Meta
  ├─ декодируется из base64?        → развернуть и распарсить рекурсивно
  └─ иначе                          → ImportFailure с внятной причиной
```

### Поддерживаемые схемы ссылок

| Схема | Комментарий |
|---|---|
| `vless://` | Включая Reality: `pbk`, `sid`, `fp`, `spx` |
| `vmess://` | Base64-JSON, историческая каша форматов — нужен снисходительный парсер |
| `trojan://` | |
| `ss://` | Два формата: legacy base64 и SIP002 |
| `hysteria2://` / `hy2://` | |
| `tuic://` | |
| `wireguard://` | |
| `socks://`, `http://` | Для локальной отладки |

### Источники подписок

| Формат | Как узнаём |
|---|---|
| Список ссылок, по одной на строку | Самый частый случай |
| То же в base64 | Оборачивается почти всеми панелями |
| Clash / Clash.Meta YAML | Ключ `proxies:` |
| sing-box JSON | Ключ `outbounds:` |
| Xray / v2rayN JSON | Ключ `outbounds:` с иной структурой |

### Заголовки ответа подписки

Панели (Marzban, Remnawave, x-ui и прочие) отдают метаданные заголовками:

```
subscription-userinfo: upload=1234; download=5678; total=107374182400; expire=1735689600
profile-update-interval: 24
profile-title: base64:0JzQvtC5INC/0YDQvtGE0LjQu9GM
profile-web-page-url: https://panel.example.com/
```

Разбираем все четыре, показываем в карточке профиля: полоса квоты, срок, имя.
Заголовков нет — просто не показываем блок, не выдумываем данные.

**User-Agent имеет значение.** Панели отдают разный формат в зависимости от него.
Ходим с честным `Commy/<version>`; если пользователю нужен другой — даём
переопределить в настройках профиля. Маскироваться под чужой клиент по умолчанию
не будем.

### Импорт из других клиентов

Отдельная задача, дающая рост: человек уже пользуется Happ или v2rayNG и не хочет
вбивать всё заново.

- deep links `happ://`, `sing-box://`, `clash://install-config?url=…`;
- вставка экспортированного JSON из v2rayN / NekoBox;
- QR-код через `mobile_scanner`;
- файл конфига через системный пикер.

### Правила парсера

1. **Снисходителен ко входу, строг к выходу.** Реальные подписки полны мусора.
2. **Частичный успех — это успех.** 40 узлов из 50 импортированы, 10 в
   `import_failures` с причиной. Не «ошибка импорта».
3. **Ноль доверия входу.** Ссылка приходит из интернета: длины, диапазоны портов,
   допустимые значения — всё проверяется. Битый ввод не должен уронить приложение
   и тем более не должен утечь в конфиг ядра как есть.
4. **Каждый парсер имеет корпус тестов** из реальных примеров, включая заведомо
   кривые. См. [10-testing.md](10-testing.md).

---

## Генератор конфига sing-box

Обратная сторона: домен → JSON для ядра.

```
Node(выбранный) ─┐
RoutingPolicy   ─┼─► ConfigBuilder ─► полный sing-box config
Settings        ─┤
DnsPolicy       ─┘
```

### Структура генерируемого конфига

```jsonc
{
  "log":       { "level": "info", "timestamp": true },

  "dns": {
    // раздельные резолверы: локальный для direct, удалённый через прокси
    "servers": [ /* remote, local, block */ ],
    "rules":   [ /* по geosite, по домену */ ],
    "strategy": "prefer_ipv4",
    "independent_cache": true
  },

  "inbounds": [
    {
      "type": "tun",
      "stack": "gvisor",           // на iOS — обязательно, см. правило R7
      "mtu": 9000,
      "auto_route": true,
      "strict_route": true,        // защита от утечек
      "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      "sniff": true
    }
  ],

  "outbounds": [
    { /* выбранный узел */ },
    { "type": "direct", "tag": "direct" },
    { "type": "block",  "tag": "block"  }
  ],

  "route": {
    "rules":     [ /* из RoutingPolicy */ ],
    "rule_set":  [ /* geoip / geosite, подгружаются с диска */ ],
    "auto_detect_interface": true,
    "final": "proxy"
  },

  "experimental": {
    "clash_api": { "external_controller": "127.0.0.1:0" },  // только десктоп
    "cache_file": { "enabled": true }
  }
}
```

### Инварианты генератора

| Инвариант | Почему |
|---|---|
| Конфиг собирается **целиком** на каждый старт, не патчится | Состояние ядра однозначно выводится из состояния приложения |
| Валидируется **до** отправки в ядро | Ошибка на нашей стороне читаемее, чем краш ядра |
| Детерминирован | Одинаковый вход → байт-в-байт одинаковый выход. Иначе не написать golden-тесты |
| `clash_api` **только на десктопе** | На мобайле данные идут через `libbox`; лишний HTTP-сервер в расширении с лимитом 50 MiB не нужен |
| Собственный трафик приложения исключён из туннеля | Иначе обновление подписки уйдёт в ещё не работающий туннель |
| DNS-запросы **не покидают туннель** мимо политики | Классическая утечка. См. [чек-лист](09-security-privacy.md#чек-лист-утечек) |

### Наборы правил

`geoip` и `geosite` — большие файлы. Правила:

- скачиваются **по явному запросу** пользователя, не автоматически (правило R1);
- кешируются на диске с версией и датой;
- загружаются ядром **по мере надобности**, а не целиком в RAM (критично для iOS);
- источник настраивается — пользователь вправе указать своё зеркало.

---

## Экспорт

Пользователь должен уметь забрать свои данные:

| Что | Формат | Заметки |
|---|---|---|
| Один узел | Протокольная ссылка + QR | Как в других клиентах |
| Профиль | Список ссылок / base64 | Совместимо с чужими клиентами |
| Полный бэкап | Зашифрованный архив | Пароль задаёт пользователь; без пароля не экспортируем |
| Сгенерированный конфиг | sing-box JSON | Для отладки. **С редакцией кредов** по умолчанию и явным предупреждением при экспорте без неё |

Бэкап в облако не делаем никогда — см. [00-vision.md](00-vision.md#явные-non-goals).
