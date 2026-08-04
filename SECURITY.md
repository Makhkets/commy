# Security Policy

Commy carries all of a user's traffic. A vulnerability here is worse than a
vulnerability almost anywhere else, and reports are taken seriously.

## Reporting a vulnerability

**Do not open a public issue.**

Use GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on
[github.com/Makhkets/commy](https://github.com/Makhkets/commy/security/advisories/new).

This creates a private thread visible only to the maintainers.

> **Maintainer note:** private reporting must be enabled in
> *Settings → Code security and analysis* before this link works. If you prefer a
> direct contact address instead, add it here.

### What to include

- what the issue is and what an attacker gains;
- steps to reproduce, or a proof of concept;
- affected version, platform and OS;
- anything you already know about mitigation.

### What to expect

| | |
|---|---|
| First response | Within 7 days |
| Assessment and plan | Within 14 days |
| Fix for a critical issue | As fast as possible, ahead of any other work |
| Credit | Yes, unless you prefer otherwise |

Please give us a reasonable window to ship a fix before public disclosure. If the
issue is being actively exploited, tell us — that changes the timeline.

## Scope

### In scope

- Traffic leaking outside the tunnel: DNS, IPv6, during network transitions, on
  crash, when the kill switch is on.
- Credential exposure: in logs, in exports, in the database, in backups.
- Attacks on the desktop control channel (the privileged service or helper).
- Parser vulnerabilities — a malicious subscription or link that causes a crash,
  code execution, or traffic being redirected somewhere the user did not choose.
- Weaknesses in secret storage or database encryption.
- Anything that causes the app to make network requests the user did not authorise.

### Out of scope

- Vulnerabilities in **sing-box** itself — report those to
  [SagerNet/sing-box](https://github.com/SagerNet/sing-box). We will pull in the fix.
- Compromise of the user's device (root, malware with system privileges).
- Attacks against the user's own servers.
- Traffic analysis and fingerprinting of proxy protocols — a property of the
  protocols, not of this client.
- Physical access to an unlocked device.

The full threat model is in
[docs/09-security-privacy.md](docs/09-security-privacy.md#модель-угроз).

## Supported versions

There is no release yet — the only thing to report against today is `main`, and a
report against it is very welcome. Once releases start, only the latest one is
supported until 1.0, after which this section will list versions properly.

## No automatic update check

Commy deliberately does **not** phone home to check for new versions — this follows
from the project's "quiet on the network" principle.

**This means you will not be notified about a security fix** if you installed the APK
directly or use the Windows portable build. Google Play, F-Droid and the App Store
update their users automatically; everyone else should
[watch releases](https://github.com/Makhkets/commy/releases) on GitHub.

This trade-off is documented as an accepted risk in
[docs/09-security-privacy.md](docs/09-security-privacy.md#проверка-обновлений--сознательно-не-реализуем).
