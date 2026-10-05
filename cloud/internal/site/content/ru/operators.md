---
title: Поддержка Commy в вашей панели
summary: Какие заголовки подписки Commy понимает, какие deep links принимает и как добавить кнопку «Добавить в Commy».
---

Если вы держите панель (Remnawave, Marzban, 3x-ui, свой бэкенд), ваша
подписка уже работает в Commy. Ниже — что именно он читает.

## Форматы подписки

Список ссылок (обычный или в base64), Clash/Mihomo YAML, sing-box JSON и
JSON-массив конфигов Xray (как отдаёт Remnawave для Happ).

## Заголовки ответа

| Заголовок | Что делает Commy |
|---|---|
| `subscription-userinfo` | Квота и срок на карточке (`upload=…; download=…; total=…; expire=…`) |
| `profile-title` | Название подписки (можно `base64:…`) |
| `profile-update-interval` | Интервал автообновления, в часах |
| `profile-web-page-url` | Кнопка «Сайт» на карточке |
| `support-url` | Кнопка «Поддержка» |
| `announce` | Объявление под квотой, как есть (можно `base64:…`) |
| `commy-manifest` | Подписанный манифест восстановления адреса — [Commy Cloud](/docs/cloud/) |

## Заголовки запроса

Commy представляется как `Commy/<версия>` (пользователь может сменить
User-Agent в меню подписки) и, если не выключено, присылает **только хосту
подписки** `x-hwid`, `x-device-os`, `x-ver-os`, `x-device-model` — как Happ и
INCY. При редиректе на другой хост эти заголовки не уходят.

## Кнопка «Добавить в Commy»

```text
commy://import/https://sub.example.com/sub/<token>
```

Commy также открывается по ссылкам других клиентов — значит, кнопки вашей
страницы подписки уже работают:

```text
happ://add/<url>            incy://import/<url>        v2raytun://import/<url>
hiddify://import/<url>      streisand://import/<url>   sub://<base64(url)>
v2rayng://install-config?url=<url>    clash://install-config?url=<url>
clashmeta://install-config?url=<url>  stash://install-config?url=<url>
sing-box://import-remote-profile?url=<url>   sn://subscription?url=<url>
```

Имя из такой ссылки (`name=`, `#фрагмент`) — подсказка: если панель прислала
`profile-title`, побеждает он.

## Заглушки панели

Если панель отвечает одной строкой с адресом `0.0.0.0` и причиной в имени
(«App not supported», «Device limit reached»), Commy покажет текст на
карточке и не будет считать это сервером.
