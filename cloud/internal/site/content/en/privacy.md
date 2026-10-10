---
title: Privacy
summary: Which requests Commy makes by itself, where, when, and how to turn them off. The list is closed.
---

The rule: **Commy makes no outgoing request you did not ask for.** No
analytics, no crash reports, no licence checks, no auto-update. It talks to
your servers and your subscriptions' hosts — and nowhere else, except the
four exceptions below. All four are on **Settings → Network silence**, with
the address each request would go to.

| # | Exception | When | Where |
|---|---|---|---|
| E-1 | Check my IP | Only when you press “Check” | The service you chose (ipinfo.io by default), **through the tunnel** |
| E-2 | geoip/geosite sets | On a button, or on the interval you enabled | The source you set (a SagerNet mirror by default) |
| E-3 | Ad-blocking lists | Only while ad blocking is on | The same source |
| E-4 | Subscription address recovery | Only for a subscription whose provider **signed** a manifest: when its address is silent, and once a day | Mirrors and the meeting point named in the manifest — see [Commy Cloud](/en/docs/cloud/) |

None is required: with all of them off, the client works fully. Requests of
E-1–E-3 and the meeting-point request of E-4 carry no device identifier.

## Device identifier (HWID)

Not an exception: it goes where the request went anyway — your
subscription's host. It is a random UUID of the install (not a serial number,
not `ANDROID_ID`), needed by panels that limit devices. Turn it off or reset
it in settings.

## Secrets

Subscription links (they hold your token), server UUIDs and passwords, and the
generated core config live in the system keystore (Android Keystore), not in
the database.

## Logs

Core logs are in **Diagnostics → Logs**. Copying or exporting strips UUIDs,
passwords, tokens and full subscription addresses automatically — a log is
safe to attach to a support request.
