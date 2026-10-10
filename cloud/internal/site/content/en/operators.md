---
title: Supporting Commy in your panel
summary: Which subscription headers Commy reads, which deep links it accepts, and how to add an “Add to Commy” button.
---

If you run a panel (Remnawave, Marzban, 3x-ui, your own backend), your
subscription already works in Commy. Here is exactly what it reads.

## Subscription formats

A link list (plain or base64), Clash/Mihomo YAML, sing-box JSON, and a JSON
array of Xray configs (what Remnawave serves Happ).

## Response headers

| Header | What Commy does |
|---|---|
| `subscription-userinfo` | Quota and expiry on the card (`upload=…; download=…; total=…; expire=…`) |
| `profile-title` | The subscription's name (`base64:…` allowed) |
| `profile-update-interval` | Auto-refresh interval, in hours |
| `profile-web-page-url` | A “Website” button on the card |
| `support-url` | A “Support” button |
| `announce` | An announcement under the quota, as is (`base64:…` allowed) |
| `commy-manifest` | A signed address-recovery manifest — [Commy Cloud](/en/docs/cloud/) |

## Request headers

Commy identifies as `Commy/<version>` (users can change the User-Agent in the
subscription menu) and, unless switched off, sends `x-hwid`, `x-device-os`,
`x-ver-os` and `x-device-model` **to the subscription host only** — like Happ
and INCY. They are not sent on to another host after a redirect.

## An “Add to Commy” button

```text
commy://import/https://sub.example.com/sub/<token>
```

Commy also opens other clients' links — so the buttons of your subscription
page already work:

```text
happ://add/<url>            incy://import/<url>        v2raytun://import/<url>
hiddify://import/<url>      streisand://import/<url>   sub://<base64(url)>
v2rayng://install-config?url=<url>    clash://install-config?url=<url>
clashmeta://install-config?url=<url>  stash://install-config?url=<url>
sing-box://import-remote-profile?url=<url>   sn://subscription?url=<url>
```

A name in such a link (`name=`, the `#fragment`) is a hint: if the panel sends
`profile-title`, that wins.

## Panel placeholders

When a panel answers with one entry at `0.0.0.0` and the reason in its name
(“App not supported”, “Device limit reached”), Commy shows the text on the
card and never treats it as a server.
