---
title: Manifest protocol
summary: The open specification of the address-recovery manifest — for clients and for your own meeting points.
---

The protocol is open: any client may support it, any operator may run their
own meeting point. The canonical description and its reasoning:
[ADR-0019](https://github.com/Makhkets/Commy/blob/main/docs/adr/0019-subscription-domain-recovery.md).

## Format

```text
v1.<base64url(JSON)>.<base64url(signature)>
```

base64url without `=`. The signature is **Ed25519** (RFC 8032) over the ASCII
bytes of `v1.<base64url(JSON)>`. At most 4096 characters.

```json
{
  "v": 1,
  "id": "axm",
  "seq": 3,
  "iat": 1791160000,
  "origin": "https://sub.example.online",
  "mirrors": ["https://sub2.example.site"],
  "rendezvous": ["https://commy.makhkets.ru/r/axm"],
  "key": "<32-byte public key, base64url>",
  "next_key": "<optional>",
  "name": "AXM VPN"
}
```

| Field | Rule |
|---|---|
| `v` | exactly `1` |
| `id` | 1–64 characters of `[A-Za-z0-9_-]` |
| `seq` | integer ≥ 1, strictly increasing |
| `iat` | Unix seconds |
| `origin` | `http(s)://host[:port]` — no path, query, fragment or user info |
| `mirrors` | up to 8 origins of the same form |
| `rendezvous` | up to 4 full `https` URLs, no user info or fragment |
| `key` | the key that signed this manifest |
| `next_key` | an announced key rotation |
| `name` | up to 64 characters |

## Delivery

- Subscription response header: `commy-manifest: <string>`.
- Meeting point: `GET <rendezvous>` → `200 text/plain`, the body is the string.

## Client rules

1. Always check the signature; the key must equal the pinned one or the
   announced `next_key`, and `id` the pinned one.
2. Pin a key (TOFU) only from a manifest in the **main address's** answer.
3. A smaller `seq` is refused; an equal one is no news.
4. Silently accept only a manifest from the main address that does not change
   `origin`. A changed `origin`, and new hosts from a mirror or a meeting
   point, need the user's consent. Remember a refusal by its `seq`.
5. An accepted move changes the scheme, host and port of the subscription URL;
   the path and query stay.
6. Mirrors: when the main address did not answer with a subscription. The
   meeting point: after such a failure no more than every 15 minutes, and once
   a day on successful refreshes. The meeting-point request carries no
   identifier.

## Sign without a browser

```bash
commy-cloud keygen -project axm -o axm-key.json
commy-cloud sign -key axm-key.json -seq 1 \
  -origin https://sub.example.ru \
  -mirror https://sub2.example.org \
  -rendezvous {{BASE}}/r/axm \
  -name "AXM VPN"
commy-cloud verify v1.…
```

The key file is the same JSON the dashboard downloads (`private_key` is
PKCS#8 in base64url).
