---
title: Servers and subscriptions
summary: The server list, the Auto group, latency checks, the subscription menu and HWID.
---

## The list

Servers are grouped by subscription: the subscription card shows quota,
expiry, the panel's announcement and links to the provider's support and
site, with its servers under it. Above the list: search (name, address,
country code) and order — as in the panel, by latency, or by name.

## Auto

The **Auto** row is a group that keeps the fastest of all servers and
switches when it stops answering. The flag and name on the right show where
it stands now. Picking a server turns Auto off; switching never drops the
tunnel.

## Widget and tile

The notification shade has a Commy tile, the home screen a widget: the
tunnel's state and a Connect / Disconnect button. Disconnecting is
immediate; connecting opens the app — the configuration with your keys is
stored encrypted and never leaves it.

## Failover

**Settings → Connection → Switch when the server fails** (off by default).
While the tunnel is up and a server was picked by hand, Commy checks it
through the core every 30 seconds. Two misses in a row, and it measures up to
six other servers (its own subscription first) and moves to the fastest live
one without dropping the tunnel, with a notice. If nothing answers, that is
the network, and Commy stays put. Not needed with Auto: the group keeps a live
server anyway.

## Ping

The chart icon on a subscription card measures all its servers (in batches of
4, cancellable). The method is in **Settings → Ping**:

| Method | Measures |
|---|---|
| **GET through the server** (default) | A real request through the server: does it actually work. Works without connecting |
| **TCP** | Time to open the server's port. Fast, but says nothing about the protocol |
| **ICMP** | Plain ping. Many servers do not answer it |

All three go to your server only.

## Subscription menu (⋯)

Rename, copy the link, show a QR code, auto refresh and its interval,
**User-Agent** (for panels that serve different formats per client),
**Address recovery** (when the provider supports it — see
[Commy Cloud](/en/docs/cloud/)) and delete.

## HWID

Panels that limit devices (Remnawave) answer a client without a device id
with an “App not supported” placeholder. So, like Happ and INCY, Commy sends
`x-hwid`, `x-device-os`, `x-ver-os` and `x-device-model` — **to the
subscription's host only**. `x-hwid` is a random UUID of the install, not a
serial number. Turn it off or reset it in **Settings → Device identifier**.

## When the panel refuses

When a panel sends a message instead of servers (“App not supported”,
“Subscription expired”), Commy shows it on the card in the panel's words and
never tries to connect to the `0.0.0.0` “server”.
