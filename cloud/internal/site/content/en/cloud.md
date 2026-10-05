---
title: Commy Cloud — protect your subscription from domain blocking
summary: If your subscription's domain is blocked or seized, Commy clients move to the new address with no reinstall. Free.
---

You have hundreds or thousands of links like
`https://sub.example.ru/sub/<token>` out there. The domain gets blocked,
seized or expires — and every client stops getting updates. Today the only
cure is a new link for everyone.

**Commy Cloud fixes this without you in the middle:** Commy clients learn the
new address themselves and, after one confirmation from the user, move to it.
The tokens in the links stay the same.

## How it works

1. You create a project in the [dashboard]({{BASE}}/cloud/). Your browser
   makes a **signing key** (Ed25519) — the file stays with you; only its
   public half reaches the server.
2. You sign a **manifest**: the subscription's main address, its mirrors, and a
   **meeting point** — an address on Commy Cloud that always holds the latest
   manifest.
3. You add the manifest as a `commy-manifest` **header** to your subscription's
   answers (one setting in Remnawave). Clients pin your key on the first answer.
4. The domain is blocked. A client that cannot reach it tries the **mirrors**
   with the same path and token, then asks the **meeting point**.
5. You publish a new manifest with the new address. The client checks the
   signature against your key and asks the user: “Your provider moved this
   subscription: old → new. The signature checks out. Move?”

## Why it is safe

- **Commy Cloud is only a courier.** A manifest cannot be forged without your
  key, and Cloud does not have it. Even a full breach of Cloud moves nobody.
- **A move always needs the user's consent.** If your key is stolen too, the
  user sees an unexpected “move” and can refuse it.
- **No rollback.** The release number only grows: an old signed manifest
  cannot be brought back.
- **We do not see your users.** The meeting point gets a bare `GET` with no
  token and no HWID. We count daily visits only; no IP is stored — uniqueness
  is a hash with a salt that changes every day.

## Set up in five minutes

1. Sign up: [{{BASE}}/cloud/signup]({{BASE}}/cloud/signup).
2. **New project** → an identifier (say, `axm`) and a name. Your browser
   downloads the key file — **keep it safe**: without it no move is possible.
3. On the project page, fill in the main address (`https://sub.example.ru`)
   and mirrors (if any), then **Sign and publish**, choosing the key file.
4. Copy the header line and add it to your subscription's answer:
   - **Remnawave:** Subscription settings → Custom response headers →
     `commy-manifest` = the string;
   - **Caddy:** `header Commy-Manifest "v1.…"`;
   - **nginx:** `add_header Commy-Manifest "v1.…" always;`
5. Done. Clients that refreshed are protected; the dashboard shows how many
   Commy installs ask the meeting point.

## When the domain is blocked

Publish a new manifest: the new main address and, if you like, new mirrors.
Clients see the move on their next meeting-point visit — at once if the old
address is silent, and within a day if the domain was seized and answers
with someone else's content.

## Also in Cloud

- **A subscription page** `{{BASE}}/s/<project>#<subscription address>` with
  your name, colour, “Add to Commy / Happ / INCY / v2RayTun…” buttons and a QR
  code. Browsers never send the part after `#` to the server.
- **History and audit log**: who published what, and when.
- **Address availability**, as seen from the Cloud server.
- **An [API](/en/docs/cloud/api/)** for automation.

Commy Cloud is **free** for now. The protocol is open
([specification](/en/docs/cloud/protocol/)), and the server is in the
[Commy repository](https://github.com/Makhkets/Commy/tree/main/cloud): you
can [run your own meeting point](/en/docs/cloud/self-host/).
