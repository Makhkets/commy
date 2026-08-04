<!--
Thank you for contributing.

Contributions are accepted under GPL-3.0-or-later, the same licence as the
project. There is no CLA — which is the point: the project cannot be quietly
relicensed or closed later, not even by its maintainer.
-->

## What this changes

<!-- One or two sentences. If it fixes an issue, write "Fixes #123". -->

## Why

<!-- The problem, not the patch. A reviewer who disagrees with the reasoning will
     disagree with the code no matter how it is written. -->

## Definition of Done

From [CLAUDE.md](../CLAUDE.md) section 6. Tick what applies; strike out what does
not with a one-line reason.

- [ ] `melos run analyze` is clean
- [ ] `melos run test` is green, and new logic has a test
- [ ] UI changes have a golden test in **both** themes
- [ ] New strings are in `slang` for **both** `ru` and `en`
- [ ] If the tunnel, routing or DNS was touched — the
      [leak checklist](../docs/09-security-privacy.md#чек-лист-утечек) was run
- [ ] If the public API of `core/` changed — artifacts rebuilt for every affected
      platform
- [ ] If an architectural decision changed — an ADR was added or updated in
      [docs/adr/](../docs/adr/)
- [ ] Checked by hand on at least one real platform, not only in tests

## The rules that are easy to break by accident

- [ ] **R1** — no outbound request to any host the user did not enter. The three
      documented exceptions are all user-triggered.
- [ ] **R2** — no credential, subscription URL or generated core config written to
      the plain database
- [ ] **R3** — nothing secret reaches a log line, including on the export path
- [ ] **R4** — no colour, spacing, radius or duration literal outside
      `packages/commy_ui/lib/src/tokens/`
- [ ] **R5** — `commy_domain` still imports nothing from Flutter

## How you tested it

<!-- Device, OS version, protocol. "It builds" is not a test.
     If you could not test something, say so — that is useful, hiding it is not. -->

## Screenshots

<!-- For UI changes: before and after, in both themes. -->
