---
title: Install
summary: Where to get Commy for Android, and how to check the APK was built from the open source.
---

## Android

1. Open the [releases page](https://github.com/Makhkets/Commy/releases/latest)
   and download `commy-…-android.apk`. One file fits every modern phone
   (arm64 and arm).
2. Allow installs from that source when Android asks.
3. Open Commy. It is empty — that is expected: we have no servers of our own.

Android 7.0 or newer is required.

> Commy does not check for updates by itself — that is the “quiet on the
> network” rule. To hear about new versions, use **Watch → Custom → Releases**
> on the GitHub project page. Releases are signed with one project key and
> install over each other without losing data.

### Check the signature

The SHA-256 fingerprint of the release certificate is published in
[docs/08-build-release.md](https://github.com/Makhkets/Commy/blob/main/docs/08-build-release.md):

```bash
apksigner verify --print-certs commy-android.apk | grep SHA-256
```

## iOS

In progress. The iOS network extension is limited to 50 MB of memory, and the
build is being prepared for that limit.

## Windows, macOS, Linux

Planned as versions 1.1 and 1.2.
