---
title: Commy Cloud API
summary: Publish manifests and read stats with a token — for automation and billing integrations.
---

Create a token on the project page (**API tokens**); it is shown once and
works for its own project only.

```http
Authorization: Bearer cct_…
```

## Project

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

## Publish a manifest

The manifest is signed **on your side** (`commy-cloud sign` or your own
implementation of the protocol); the server checks the signature, the
project's key and that `seq` grows.

```http
POST {{BASE}}/api/v1/projects/{id}/manifests
Content-Type: application/json

{"manifest": "v1.…"}
```

`201` — published; `422` with `{"error": "…"}` — refused (wrong key, `seq` not
above the published one, malformed).

## History

```http
GET {{BASE}}/api/v1/projects/{id}/manifests
```

## Stats

```http
GET {{BASE}}/api/v1/projects/{id}/stats?days=30
```

```json
[{"date": "2026-10-05", "visits": 1520, "unique": 1307, "versions": {"0.1.0": 1307}}]
```

`unique` is the number of Commy installs that asked the meeting point that
day (a hash of the IP with a daily salt; no IP is stored).

Limit: 120 requests a minute per address.
