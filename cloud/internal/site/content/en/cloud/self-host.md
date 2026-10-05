---
title: Your own meeting point
summary: Run a Commy Cloud server yourself — one container, one state file.
---

The Commy Cloud server is open source (GPL-3.0), in the
[`cloud/`](https://github.com/Makhkets/Commy/tree/main/cloud) directory. One
binary, no external services; its state is one JSON file.

```bash
git clone https://github.com/Makhkets/Commy && cd Commy/cloud
docker build -t commy-cloud .
docker run -d --name commy-cloud -p 8080:8080 \
  -v commy-cloud-data:/data \
  -e COMMY_CLOUD_BASE_URL=https://cloud.example.org \
  -e COMMY_CLOUD_TRUST_PROXY=1 \
  commy-cloud
```

| Variable | Meaning |
|---|---|
| `COMMY_CLOUD_BASE_URL` | Public address — meeting-point links are built from it |
| `COMMY_CLOUD_DATA` | State file (`/data/cloud.json` in the container) |
| `COMMY_CLOUD_OPEN_SIGNUP` | `1` — anyone may register. The first account is always allowed and becomes the admin |
| `COMMY_CLOUD_TRUST_PROXY` | `1` — take the client address from `X-Forwarded-For` (behind Caddy/nginx) |

TLS belongs to the reverse proxy. For Caddy:

```text
cloud.example.org {
    reverse_proxy commy-cloud:8080
}
```

Back up by copying `cloud.json`. It holds no operator's private key: those
never reach the server.
