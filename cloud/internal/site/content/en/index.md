---
title: What is Commy
summary: An open-source proxy client for your own servers — VLESS/Reality, Hysteria2, TUIC, WireGuard and more, with no telemetry and no accounts.
---

**Commy** is an open-source, cross-platform proxy client. It connects you to
**your own** servers, or to a subscription your provider issued (Remnawave,
Marzban, 3x-ui and other panels). The network core is
[sing-box](https://sing-box.sagernet.org/); the interface is Flutter.

## What makes it different

- **Open source (GPL-3.0).** All your traffic goes through this tool — you
  have a right to know what it does. Every generated config can be opened and
  read inside the app.
- **Quiet on the network.** No analytics, no crash reports, no update checks.
  Commy talks to your servers and your subscriptions; the few exceptions are
  listed on one screen and in [Privacy](/en/docs/privacy/).
- **Not a VPN service.** We run no servers, ship no free configs and have no
  accounts. The app is empty until your first import.
- **As convenient as Happ.** Subscriptions with quota and expiry, an Auto
  server, one-tap pings, a quick-settings tile, and import from the “Add to…”
  buttons of a subscription page.

## Protocols

VLESS (including Reality, XTLS Vision and XHTTP), VMess, Trojan,
Shadowsocks (including 2022), Hysteria2, TUIC, WireGuard, ShadowTLS, SOCKS and
HTTP. Transports: TCP, WebSocket, gRPC, HTTP/2, HTTPUpgrade, XHTTP.

## Platforms

| Platform | Status |
|---|---|
| Android 7+ | Released — APK on [GitHub](https://github.com/Makhkets/Commy/releases/latest) |
| iOS | In progress — next |
| Windows | Version 1.1 |
| macOS, Linux | Version 1.2 |

Next: [Install](/en/docs/install/) · [First connection](/en/docs/quick-start/).
