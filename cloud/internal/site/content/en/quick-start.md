---
title: First connection
summary: Add a subscription or a server — by link, QR code, file, or an “Add to…” button.
---

Commy is empty until the first import. There are five ways in, all leading to
the same “Add a server” sheet (the **+** button on the home screen).

## 1. A subscription link

Your provider gives you a link like `https://sub.example.com/sub/…`.

- Copy it — Commy offers it when you open the app (the clipboard is read only
  then, never in the background).
- Or **+ → Subscription by URL**, paste it, optionally name it and choose the
  refresh interval.

Commy loads the servers, the quota, the expiry and the panel's announcement.
The subscription refreshes itself on the interval the panel sent or you chose.

## 2. “Add to…” buttons on a subscription page

Subscription pages of Remnawave, Marzban and other panels carry a button per
client. Commy opens from any of them: **Happ, INCY, v2RayTun, Hiddify,
Streisand, Shadowrocket, v2rayNG, Clash Meta, FlClashX, Stash, sing-box,
Exclave** — and `commy://import/<address>`, of course.

If Android asks which app should open the link, choose Commy.

> **Encrypted links** `happ://crypt…` and `incy://crypt…` can only be opened
> by the app they were made for. Commy says so plainly — ask your provider
> for the plain subscription link (`https://…`).

## 3. Server links

`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`,
`wireguard://` and more: paste one or many lines through **+ → Paste**, or
open the link from a messenger.

## 4. QR code

**+ → QR code.** The camera runs only while scanning. Got a stack of codes (a
leaflet, stickers)? Switch on **“Several codes in a row”**: codes are collected
as you point at them and added with one button.

## 5. A file

**+ → File**: a sing-box config (JSON), Clash YAML, or a base64 link list.

## Connecting

Pick a server (or the **Auto** row — Commy keeps the fastest) and press the
big button. Android asks once for VPN permission; the tunnel cannot start
without it. After connecting, Commy checks that the internet really works
through the server before it turns green.
