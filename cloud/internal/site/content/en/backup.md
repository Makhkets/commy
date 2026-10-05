---
title: Backup
summary: Move subscriptions, servers and rules to a new phone — one file under a password.
---

**Settings → Backup → Save a backup.** The file holds your subscriptions with
their links, every server with its keys, routing with rules, DNS, settings
and the selected server. It is encrypted with your password (Argon2id +
ChaCha20-Poly1305); from the outside it only says it is a Commy backup.

Left out: the device identifier (a new phone is a new device to your panel),
traffic history, logs and rule-set files — those download again.

**Restore from a backup** replaces everything you have, after a question that
says how many subscriptions, servers and rules the file holds.

> The password cannot be recovered. The file holds the keys to your servers:
> choose a long one.
