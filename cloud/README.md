# Commy Cloud

The server side of [subscription domain recovery](../docs/adr/0019-subscription-domain-recovery.md):
meeting points (`/r/{id}`), the operators' dashboard (`/cloud/`), white-label
subscription pages (`/s/{id}`), an API (`/api/v1/`) and the public site with
the documentation (`/`, `/docs/`, `/en/docs/`).

One Go binary, standard library plus `goldmark`, state in one JSON file.

```bash
go test ./...
go run ./cmd/commy-cloud serve          # http://localhost:8080
go run ./cmd/commy-cloud keygen -project demo -o demo-key.json
go run ./cmd/commy-cloud sign -key demo-key.json -seq 1 -origin https://sub.example.com \
  -rendezvous https://commy.makhkets.ru/r/demo
```

Deploy: `deploy/docker-compose.yml` (joins an existing Caddy network) and
`deploy/Caddyfile.snippet`. Production: https://commy.makhkets.ru —
see docs/19-commy-cloud.md, «Инфраструктура».

Licence: GPL-3.0-or-later, like the rest of Commy. `internal/web/static/qr.js`
is Kazuhiko Arase's QR Code Generator, MIT.
