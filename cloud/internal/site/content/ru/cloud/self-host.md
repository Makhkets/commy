---
title: Своя точка встречи
summary: Как поднять сервер Commy Cloud у себя — один контейнер, один файл состояния.
---

Сервер Commy Cloud — открытый (GPL-3.0), каталог
[`cloud/`](https://github.com/Makhkets/Commy/tree/main/cloud) репозитория.
Один бинарник без внешних зависимостей, состояние — один JSON-файл.

```bash
git clone https://github.com/Makhkets/Commy && cd Commy/cloud
docker build -t commy-cloud .
docker run -d --name commy-cloud -p 8080:8080 \
  -v commy-cloud-data:/data \
  -e COMMY_CLOUD_BASE_URL=https://cloud.example.org \
  -e COMMY_CLOUD_TRUST_PROXY=1 \
  commy-cloud
```

| Переменная | Смысл |
|---|---|
| `COMMY_CLOUD_BASE_URL` | Публичный адрес — из него строятся ссылки точки встречи |
| `COMMY_CLOUD_DATA` | Файл состояния (`/data/cloud.json` в контейнере) |
| `COMMY_CLOUD_OPEN_SIGNUP` | `1` — регистрация открыта всем. Первый аккаунт создаётся всегда и становится админом |
| `COMMY_CLOUD_TRUST_PROXY` | `1` — брать адрес клиента из `X-Forwarded-For` (за Caddy/nginx) |

TLS — на обратном прокси. Пример для Caddy:

```text
cloud.example.org {
    reverse_proxy commy-cloud:8080
}
```

Резервная копия — копия файла `cloud.json`. Ключей операторов в нём нет: их
приватные половины никогда не попадают на сервер.
