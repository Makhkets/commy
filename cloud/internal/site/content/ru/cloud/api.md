---
title: API Commy Cloud
summary: Публикация манифестов и статистика по токену — для автоматизации и интеграции с биллингом.
---

Токен создаётся на странице проекта (**API-токены**) и показывается один раз.
Он действует только для своего проекта.

```http
Authorization: Bearer cct_…
```

## Проект

```http
GET {{BASE}}/api/v1/projects/{id}
```

```json
{
  "id": "axm",
  "name": "AXM VPN",
  "key": "…",
  "next_key": "",
  "rendezvous": "{{BASE}}/r/axm",
  "page": "{{BASE}}/s/axm",
  "latest": {"seq": 3, "origin": "https://sub.example.ru", "mirrors": [], "manifest": "v1.…", "published": "2026-10-05T12:00:00Z"}
}
```

## Опубликовать манифест

Манифест подписывается **у вас** (`commy-cloud sign` или своя реализация
протокола); сервер проверяет подпись, ключ проекта и рост `seq`.

```http
POST {{BASE}}/api/v1/projects/{id}/manifests
Content-Type: application/json

{"manifest": "v1.…"}
```

`201` — опубликован; `422` с `{"error": "…"}` — отказ (неверный ключ, `seq` не
больше опубликованного, нарушен формат).

## История

```http
GET {{BASE}}/api/v1/projects/{id}/manifests
```

## Статистика

```http
GET {{BASE}}/api/v1/projects/{id}/stats?days=30
```

```json
[{"date": "2026-10-05", "visits": 1520, "unique": 1307, "versions": {"0.1.0": 1307}}]
```

`unique` — установки Commy, спросившие точку встречи за сутки (по хешу IP с
суточной солью; IP не хранятся).

Лимит — 120 запросов в минуту с одного адреса.
