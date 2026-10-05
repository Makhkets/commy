---
title: Routing
summary: Global / Rules / Direct, geoip and geosite rules, apps outside the tunnel, ad blocking.
---

**Settings → Routing.** Changes reach a running tunnel at once, without
reconnecting.

## Modes

| Mode | What happens |
|---|---|
| **Global** | All traffic goes through the server |
| **Rules** | Your rules decide; the rest goes through the server |
| **Direct** | Nothing goes through the server; the tunnel stays up |

## Profiles

Above the mode sits the profile row. **+ New** saves the current rules under a
name (“Home”, “Travel”); a tap on a profile switches the rules at once,
without reconnecting, and edits of the profile being left stay in it. A long
press renames, deletes or **copies a link** like `commy://routing/…`: whoever
opens it sees the rules and decides whether to switch. The app list never
goes into a link. Profiles are part of backups.

## Rules

A rule is a condition and an action (**Proxy**, **Direct**, **Block**). Order
is priority; drag to sort. The last rule, “Everything else”, cannot be
removed: routing always needs a final outcome.

Conditions use sing-box syntax:

```text
geosite:ru              domains in the geosite "ru" set
geoip:private           private addresses
domain:example.com      exact name
domain_suffix:example.com
ip_cidr:10.0.0.0/8
```

## Rule sets (geoip, geosite)

`geosite:` and `geoip:` rules need a compiled list on the device. Commy
**downloads nothing on its own**: the **Rule sets** screen shows the source
address up front, and downloads happen on a button. Auto refresh — daily,
weekly or monthly — is optional and only refreshes sets that are already
downloaded and in use.

## Apps

**Routing → Apps**: everything through the tunnel, only the chosen apps, or
everything except them (Android).

## Ad blocking

**Block ads** applies `geosite-category-ads-all`: a DNS query for an ad name is
refused, and a connection to such an address is blocked. Until the list is
downloaded, the switch says it blocks nothing.

## Local network

**Local network outside the proxy** keeps your router, printer and NAS
reachable.

## Kill switch

On Android the kill switch is the system's: **Settings → Connection → Kill
switch** opens “Always-on VPN” and “Block connections without VPN”. While the
tunnel is down, Commy holds a blocking TUN so apps' DNS queries do not leave
in the clear.
