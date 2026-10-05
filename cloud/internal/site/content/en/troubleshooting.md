---
title: If it won't connect
summary: Common reasons a subscription will not load or the tunnel will not pass traffic, and what to do.
---

## Connection diagnosis

Long-press a server → **Connection diagnosis** (or “Why?” on a failed-check
notice). Commy checks in turn whether the server name resolves, the port is
open, the TLS handshake completes and a request gets through the protocol
itself — and names the first layer that broke, with what to do: a closed
port, blocking by name (SNI), a refused certificate, or a key the server no
longer accepts. Every check goes to your server only.

## The subscription does not load

| What you see | What it means |
|---|---|
| “The panel refused: HTTP 403” | Expired, revoked, or over the device limit |
| “App not supported” on the card | The panel wants an HWID — check **Send HWID** is on |
| “Certificate refused” | The panel's certificate expired, or the phone's clock is wrong |
| “The subscription server is not answering” | The domain is unreachable from your network. If your provider set up [address recovery](/en/docs/cloud/), Commy tries its mirrors by itself |
| “An encrypted Happ link” | Only Happ opens `happ://crypt…` — ask for the plain link |

**Subscription menu → User-Agent** lets Commy introduce itself as another
client when a panel serves it the wrong format.

## The tunnel is up but sites do not open

1. Ping the server: if **GET through the server** gets no answer, the server
   passes no traffic (expired key, server down, protocol blocked).
2. Try the **Auto** row — it picks a live server.
3. Open **Diagnostics → Logs**: `ERROR` lines name the cause.
4. **Diagnostics → Config** shows exactly what went into the core (without
   secrets).

## The tunnel drops

Turn off battery optimisation for Commy, and check that Always-on VPN is not
set to another app.

## Report a problem

[GitHub issues](https://github.com/Makhkets/Commy/issues). Attach a log copied
with the app's button — secrets are already stripped.
