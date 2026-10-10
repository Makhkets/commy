---
title: DNS
summary: Two resolvers — through the tunnel and direct — address strategy, FakeIP.
---

**Routing → DNS.**

There are always two resolvers, and that is the point:

- **Through the tunnel** answers for names that go through the proxy, and is
  asked through it;
- **Direct** answers for names that go around the proxy.

One resolver for both is the classic leak: the DNS query would tell, outside
the tunnel, where you are going.

Schemes: plain UDP (`1.1.1.1`), `tcp://`, `tls://` (DoT), `https://` (DoH),
`quic://`, `h3://`, `dhcp://`, and `local` (direct only: ask the system). A
typo is caught in the field, not at connect time.

**Addresses** chooses which records to ask for: both (IPv4 or IPv6 first) or
one kind only. **FakeIP** speeds up connections through the proxy; it turns
on separate resolver caches with it.
