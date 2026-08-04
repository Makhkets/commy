# Contributing to Commy

Thanks for considering it. This document is short on purpose — the details live in
[docs/](docs/README.md).

> **Project status: M0 → M1.** The monorepo, the domain layer, the link and
> subscription parsers, the data layer and the Go core all exist and are tested. The
> Android tunnel is written against a real `libbox.aar`. What is *not* done is the
> app itself — `apps/commy/lib` is still a single `main.dart`, and there is no
> release yet.
>
> That makes parser fixtures, review of the [architecture decisions](docs/adr/) and
> anything in [docs/07-roadmap.md](docs/07-roadmap.md) under M1 the most useful
> places to start.

---

## Before you write code

**Open an issue first** for anything beyond a typo. A rejected pull request wastes
your time more than a five-minute discussion does.

Two things worth reading before you start:

- [CLAUDE.md](CLAUDE.md) — the working contract: hard rules, repo map, conventions.
- [docs/02-architecture.md](docs/02-architecture.md) — layers and dependency boundaries.

---

## Hard rules

These are not style preferences. A change that breaks one of them will not be merged
even if it works.

| | |
|---|---|
| **No network of our own** | No analytics, no crash reporting, no update checks. Only the user's subscriptions and servers, plus three documented exceptions |
| **Secrets never touch the plaintext database** | See [docs/06-data-model.md](docs/06-data-model.md) |
| **Logs are redacted** | Credentials and subscription tokens are stripped before display and export |
| **No hardcoded colours, spacing or durations** | Design tokens only |
| **The domain layer does not import Flutter** | Enforced by lint |
| **No leaks** | Any change to the tunnel, routing or DNS must pass the [leak checklist](docs/09-security-privacy.md#чек-лист-утечек) |
| **sing-box is never bumped in passing** | A core bump is its own pull request, with its own matrix run |
| **Generated files are not hand-edited** | `*.g.dart` and friends come from `melos run gen`, never from a text editor |
| **Licence compatibility** | Every new dependency must be compatible with GPL-3.0 |

---

## Setting up

Full requirements and the core build are in the
[README](README.md#building); the short version:

```bash
dart pub get
dart pub global activate melos 6.3.3   # then add ~/.pub-cache/bin to PATH
melos bootstrap
melos run gen --no-select              # drift + slang codegen
```

Three things that cost people an afternoon:

- **melos has to be on PATH**, not merely a `dev_dependency`. Its scripts shell out
  to `melos exec`, so `dart run melos run <script>` fails from inside itself with
  `"melos" is not recognised`. `dart run melos bootstrap` works, because bootstrap
  is a built-in command rather than a script — which is exactly what makes the
  failure confusing.
- **Flutter is pinned** to the version in [`.fvmrc`](.fvmrc). If you use
  [FVM](https://fvm.app), run `fvm flutter` rather than a global `flutter`.
- **On Windows, run melos from PowerShell**, not Git Bash — under Git Bash it dies
  with `FormatException: Unexpected extension byte` decoding a child process's
  output on a non-UTF-8 system locale.

Building the Android app additionally needs `scripts/build_core.sh android` first.
The APK cannot link without it: the sing-box core is a native library, not a pub
package.

---

## Workflow

1. Fork, branch from `main`.
2. Set up as above.
3. Write the change **and its test**.
4. `melos run analyze && melos run test` — both must be clean. Analysis runs with
   `--fatal-infos`, so an info-level lint fails the build too.
5. Commit using [Conventional Commits](https://www.conventionalcommits.org):
   `feat(android): ...`, `fix(config): ...`, `docs: ...`.
   Scopes: `core`, `android`, `apple`, `windows`, `linux`, `ui`, `domain`, `data`,
   `config`, `ci`, `docs`.
6. Sign off your commits: `git commit -s` (see DCO below).
7. Open a pull request describing **what** and **why**. The what is in the diff; the
   why is not.

### Definition of Done

- [ ] `melos run analyze` clean;
- [ ] `melos run test` green, new logic covered;
- [ ] UI changes have golden tests in **both** themes;
- [ ] new strings added to `slang` for `ru` and `en`;
- [ ] tunnel, routing or DNS changes passed the leak checklist;
- [ ] architectural changes recorded as an ADR in [docs/adr/](docs/adr/);
- [ ] verified by hand on at least one real platform, not only in tests.

---

## Language

Code, identifiers, comments, commit messages and error strings: **English**.
Specification documents in `docs/`: **Russian**. UI strings: `slang` only — never
hardcoded in widgets.

If you are more comfortable writing an issue in Russian, do that. Being understood
matters more than the language it happens in.

---

## Developer Certificate of Origin

There is no CLA. Instead, sign off your commits to confirm you have the right to
submit the code:

```bash
git commit -s -m "feat(config): add tuic link parser"
```

This appends `Signed-off-by: Your Name <your@email>` and means you agree to the
[DCO](https://developercertificate.org).

You keep the copyright to your contribution. Because there is no CLA, the project
cannot be relicensed or closed without every contributor's agreement — that is
deliberate.

---

## Reporting bugs

Include:

- platform and OS version, app version;
- what you expected and what happened;
- **redacted** logs (use the app's export — it strips credentials automatically);
- steps to reproduce.

**Never paste a real subscription URL or config into an issue.** They contain access
tokens. Redact them, or the first person to read your issue owns your servers.

## Reporting security issues

Do not open a public issue. See [SECURITY.md](SECURITY.md).

---

## Good first contributions

- **Link and subscription parser fixtures.** Real-world subscriptions are full of
  edge cases. Anonymised broken samples that we mis-parse are genuinely valuable —
  see [docs/10-testing.md](docs/10-testing.md).
- **Translations**, once `slang` is wired up.
- **Specification review.** If an ADR is wrong, say so now — it is far cheaper than
  after the code exists.
