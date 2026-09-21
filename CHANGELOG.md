# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are cut from tags matching `v*`; the release workflow reads the section
matching the tag out of this file and uses it as the release notes.

## [Unreleased]

### Fixed

- **The tunnel carries traffic.** Up to this release a connection came up, the
  key appeared in the status bar, and nothing worked — and the log did not say
  why. Two faults, both on the Android side of the core, both now verified
  against a live VLESS server with an emulator in between:
  - **The core was told our own tunnel was the default network.**
    `registerDefaultNetworkCallback` answers "the default network for this
    app", and once a VPN is up that answer is the VPN — for the app that built
    it as much as for anyone else. sing-box drops its own interface from the
    candidate list and then looks for one matching the index it was handed,
    finds none, and every dial fails with *no available network interface*.
    The watch is now a request for a network carrying
    `NET_CAPABILITY_NOT_VPN`, which is also what keeps a Wi-Fi ↔ mobile
    handover visible while the tunnel is up.
  - **`{"type": "local"}` DNS had nothing to ask.** libbox lets the platform
    supply the system resolver, and we supplied none, so the core used its own
    implementation — which reads `/etc/resolv.conf`. **Android has no
    `/etc/resolv.conf`**, so Go fell back to its compiled-in `127.0.0.1:53`
    and every direct lookup was refused. That resolver is what
    `route.default_domain_resolver` points at, which makes it the one that
    turns a node's hostname into an address, so a node written as a name —
    which is every node any panel hands out — could never be dialled.
    `AndroidDnsTransport` now answers through `DnsResolver`, on the underlying
    network rather than through the tunnel.
- **The log says something.** On Android the core colours its output
  (`DisableColors()` answers `GOOS != "android"`), and the escapes were being
  drawn literally: the severity — the first thing anyone looks for — read as
  `[31mERROR[0m`. They are stripped now, and the level is recovered from the
  text underneath. A debug build also sent every line a second time through
  `writeDebugMessage` with the level hardcoded to `debug`; that copy goes to
  logcat (`adb logcat -s CommyCore`) instead of onto the screen.
- **A failed connect says what failed.** The log carried `connect failed:
  config_invalid` — the code the screen was about to translate, and nothing
  else. It now carries the failure with its detail, and the line before it
  names the server the tunnel was pointed at: name, protocol and address, no
  credentials. A reachability probe that finds no way out of a live tunnel now
  says so in the log as well as in a toast.

## [0.1.0-alpha.4]

The first release that has met a real Android runtime, and the first to be
held to a size budget. Two things matter more than the rest of this list.
**Every earlier build crashed on connect** — two Go panics inside our own
process — so this is the first version that can bring a tunnel up at all. And
the file to download is **51 MB instead of 202** — and it is the only file
there is, so there is nothing to choose between.

### Added

- **A size budget, and rule R11.** The app is to be fast and light, and that is
  now measured rather than hoped for: `scripts/check_apk_size.sh` fails a
  release whose APK is over 56 MB, and the release workflow runs it
  before collecting anything. The number moves only in a commit that says what
  the bytes bought. CLAUDE.md R11; docs/08-build-release.md has the table of
  where 202 MB went.
- **A server picker under the connect button.** The chosen-server chip draws
  a chevron, and on a device it opened nothing: on a phone it scrolled the
  page, beside a list pane it had no callback at all. It now opens a sheet
  with the servers of the chosen subscription — or the hand-added ones, or all
  of them when nothing is chosen yet — plus Auto, using the same rows as the
  list, so a tap is the same in-core switch. The search typed over the list
  is deliberately not applied to it. One server is not a choice and gets no
  chevron.
- **Latency with the tunnel down.** The ping button failed on every press
  until the user had already connected — the only way to measure was to ask a
  core that was not running. With the tunnel down the app now times the
  server's TCP handshake itself (`LatencyProbe`, `SocketLatencyProbe`): one
  connection to the host the user entered, nothing sent, closed. Which method
  a run uses is decided once, so numbers inside one run stay comparable.
  Hysteria2, TUIC, WireGuard and QUIC/KCP transports listen on UDP; they are
  left unmeasured and the run says how many, instead of marking a healthy
  server offline.
- **46 more country flags**, described as data (`_FlagSpec`: bands plus marks)
  rather than painted by hand, and a fallback for the rest: a country with no
  drawing gets its two letters on the neutral chip instead of a globe.
- **HWID on subscription requests** (queue #21, owner decision 2026-09-18,
  "like Happ / INCY"). Subscription fetches now carry `x-hwid` and
  `x-device-os`. Panels that limit devices per subscription answer a client
  without an identifier with a single "App not supported" placeholder — which
  is what the owner's own panel had been doing, and why trying nineteen
  User-Agents never helped. The identifier is a random UUID of this install,
  not a hardware serial; it lives in the encrypted store, is made on first
  need, goes to the subscription host and nowhere else, and Settings → Device
  identifier turns it off (nothing is sent, nothing is even created) or resets
  it. On by default. `x-ver-os` and `x-device-model` wait for a channel
  method: `dart:io` has no honest value for either. Described in
  docs/09-security-privacy.md and the README, because "no telemetry" stays
  true only if this is said out loud.

- **Navigation on tablets and desktops.** Every screen already built an
  `AdaptiveScaffold` and every one of them handed it an empty list of
  sections, so above 600 dp the app was a stretched phone with the rail and
  the sidebar that `commy_ui` ships never drawn. There are now four sections —
  Home, Routing, Diagnostics, Settings — declared once (`AppSection`) and used
  by all nine screens; a screen inside a section lights its parent, so the DNS
  screen shows Routing. From roughly 810 dp, where two panes actually fit, the
  home screen splits the way docs/05-ux-flows.md asks: servers on the left,
  the connection — disc, status, chosen server — in the pane beside them.
  Below 600 dp nothing changed: one root screen, sections from the header.
  Queue #19.
- **Widget tests for the screens that had none.** Nine of the ten screens were
  rendered by no test at all. Settings, routing, appearance, about, the import
  and subscription sheets, the import result panel, the diagnostics frame and
  the shared widgets (`FailureView`, `AsyncSection`, `SettingsTile`,
  `ToastMessenger`) are now covered, and the switches are asserted through
  what *reads* them rather than through the field they write. The app went
  from 135 tests to 353; the monorepo from 925 to 1187. Queue #16.
- **Search and order on the home list.** Above the servers, once there is
  more than one: a search field that narrows every card and the manual group
  by name, address or whole country code, and a chip that orders the servers
  inside each list — as the panel listed them, by latency (measured fastest
  first, unmeasured next, timed out last) or by name. The order is a setting
  and survives a restart; the search is not. A search that matches nothing
  says so and offers to clear itself. Subscriptions keep their own order and
  are never interleaved (docs/05-ux-flows.md). Queue #15.
- **Traffic by day.** The statistics tab keeps the last week as two numbers
  a day — sent and received — under the live chart and the session totals,
  and shows them with the tunnel down too. Nothing finer is recorded: a table
  of connections would be a browsing history. The store had been written and
  never wired (queue #18); it now sits behind a domain port, and a pump
  watched from the root feeds it whether or not the tab is ever opened.

### Changed

- **A release is one APK.** Three per-ABI files on the releases page left
  people guessing which to take, so there is one again — but not the old one.
  That carried a copy of the core, the engine and the Dart snapshot for three
  ABIs, x86_64 included, which only emulators run: 202 MB. This one is built
  for the two ABIs phones have, and the Gradle build now packages native
  libraries only for the platforms it was asked for — before, the 13 MB
  x86_64 core rode along even in an APK with no x86_64 engine to load it.
  51 MB. The `.aab` and `libbox.aar` are no longer release assets either;
  they stay on the workflow run. Per-ABI APKs can still be built locally with
  `--split-per-abi`.
- **Native libraries are compressed inside the APK.** 66 of the 69 MB of an
  arm64 APK were libraries stored as-is; `libbox.so` alone is 39 MB that
  deflates to 13. An APK from the releases page is downloaded exactly as built,
  so that was 40 MB of download for nothing visible. The price is on the
  device — the installer unpacks them, so the installed size grows by about
  what the download shrank — and it is paid once, at install. Bundles keep
  them stored: Play compresses the transfer itself.
- **The icon font is vendored, not depended on.** `lucide_icons_flutter`
  declares seven font families, one per stroke weight, and Flutter bundles
  every font a dependency declares, used or not: six unused weights, 2.6 MB,
  in every APK. `commy_ui` now ships the one font, which tree-shaking cuts to
  11 KB, and names its 35 glyphs by code point. A second gain came free: the
  package resolved to a different version in each workspace member, so the
  goldens were drawn with one set of glyphs while the app shipped another. A
  file in the repository cannot drift. The goldens are pixel-identical.
- **Start-up waits run together.** The locale, the keystore-and-database open
  and the package info were awaited one after another before the first frame;
  they have nothing to do with each other and now cost the slowest of the
  three rather than their sum.
- **One home for the rule that folds a server listed twice.** It had four,
  and the four agreed — but a rule living in four houses is a rule that can
  drift apart without anyone noticing, and these four were already explaining
  themselves differently: three were reasoning about reporting an honest
  count, the fourth about not failing an insert on a primary key.
  `NodeDuplicates.folded` states it once, in `commy_domain` beside the entity
  it is about — the last entry wins the fields, the first keeps its place in
  the list. The paste import, the subscription add, the subscription refresh
  and the node store all call it, and each keeps the one line saying why the
  fold belongs at that particular boundary. The store's copy returned a
  growable list where the other three returned an unmodifiable one; nothing
  ever mutated it, and the shared rule is unmodifiable for all four.
- **The cog on the home screen stops duplicating the navigation.**
  docs/05-ux-flows.md gives the header the sections below 600 dp and the
  navigation everything from 600 up, but the cog was drawn at every width — so
  from the first breakpoint it stood beside a Settings entry in the rail, two
  doors into the same room in the same frame. It now appears only where there
  is no rail to carry it. The `+` is unchanged and stays at every width: the
  navigation has no twin for it, and outside the first-run view it is the only
  way into import.

### Fixed

- **The connect button did nothing until a row had been tapped.** One link
  imported, nothing selected, and the only large control on the screen was
  dead: `connect()` had no target and returned quietly. It now starts on the
  first server there is and makes it the selection, which is what the press
  meant. With no server at all it still reports that, so the screen can offer
  the import sheet.
- **Every connect crashed the app on a real device.** Two Go panics inside
  our own process, found the first time the build met an Android runtime.
  `startOrReloadService(config, null)`: libbox 1.13 reads
  `options.AutoRedirect` with no nil check, so `null` is a nil-pointer panic;
  an empty `OverrideOptions()` is passed now, on start and on reload. Then
  `netip.MustParsePrefix("fe80::…%wlan0/64")`: Java prints a link-local IPv6
  address with its scope, every live interface has one, and Go refuses a zone
  inside a prefix; the scope is dropped before the address reaches libbox.
  docs/03, docs/13 and the wire protocol all prescribed the `null`.
- **A failed ping painted the connect button red.** The single-server probe
  wrote its failure into the tunnel's state, so "measure" on a server while
  disconnected produced a red disc and "something went wrong" on a tunnel
  nobody had asked for anything. Measuring moved to `MeasurementController`;
  its failures are a toast about a measurement.
- **Typed failures reached the screen as "something went wrong".** All eleven
  use cases ended in `UnknownFailure(error, stackTrace)`, which buried the
  `CoreClientException` a core client throws — so declining the VPN dialog,
  the named M1 acceptance case, told the user nothing. `FailureCarrier` and
  `CommyFailure.fromCaught` keep a failure that arrives typed, typed.
- **The flag a panel types into a server name is drawn as a flag.** Nothing
  ever filled `ProxyNode.countryCode`, so every row showed the neutral globe
  with the emoji flag next to it. `NodeLabel` reads the regional-indicator
  pair out of the name, the slot draws the country, and the label drops the
  emoji; search by country code and sort by name follow the label. The stored
  name is untouched.
- **Sheets opened under the keyboard.** `CommySheet` left the keyboard insets
  to nobody, so the field being typed into — a link, a subscription address —
  was the part the keyboard covered. The sheet now rides above it and scrolls
  what does not fit.
- **An unlimited plan's card said only "unlimited".** It now shows what was
  used next to the word.

Everything in this list was found by the tests above, and each is the same
defect the project has been chasing since docs/15-handoff.md §0: a screen
stating something the rest of the app does not do.

- **A subscription listing one server twice could not refresh at all.**
  `replaceForSubscription` deleted the subscription's rows and re-inserted
  with a plain insert, so two entries carrying one node id — an ordinary panel
  layout, the same endpoint in two groups — hit a UNIQUE constraint and the
  whole refresh failed with a storage error. Duplicates now fold into the row
  they become, by the same last-wins rule the import path uses.
- **The routing screen promised the tunnel in Direct mode.** The final row was
  hardcoded to `PROXY` while `RouteSectionBuilder.finalOutbound` answers
  `direct` for that mode — the screen said everything unmatched goes through
  the tunnel while the generated document sent it outside. The row now reads
  the builder.
- **Rules edited outside Rules mode did nothing, silently.** The builder walks
  the rule list only in Rules mode; the screen offered the same list, the same
  Add button and the same reordering in all three. The rules are still kept
  and still editable — a mode change must not throw a user's work away — and
  the screen now says they are not in force, with one tap to make them so.
- **Imports reported the parser's count, not the library's.** Two links naming
  the same server are one stored row, and the panel said two. It now reports
  what the store gained, on the paste path and the subscription path both.
- **A dismissed import sheet left its result behind.** Dropping the sheet by
  the scrim, the drag handle or the back gesture never cleared the import
  state, so the next sheet opened on the previous import's result panel — and
  while a modal showed a result, the sheet underneath had already replaced its
  four choices with a second copy of it. Sheets now clear on route end, and an
  import that finishes after its sheet is gone drops the report instead of
  parking it for whatever opens next.
- **Every failure offered the wrong button.** The import panel derived its
  action from `retryable` alone and always added a link to the logs, throwing
  away the action each failure declares — so a storage failure was offered
  "Close" instead of "Retry" and an invalid config was sent to the logs rather
  than to the config. All nine action strings in both languages were dead.
- **First-run imports had nowhere to report.** The file tile and the clipboard
  offer on the empty home screen called the importer directly and rendered no
  result, so a failed import said nothing at all and its result sat waiting
  for the next sheet to open on it.
- **"Imported 1 servers".** Four counted strings interpolated a number next to
  a noun with no plural form; Russian was also wrong for 2–4. They are CLDR
  plurals now, in both languages.
- **Node names came out escaped.** The redactor keeps a link's fragment on
  purpose — it holds the display name that makes an import error readable —
  and then printed it percent-encoded: `#Amsterdam%2003`, in the clipboard
  card, the skipped-lines list, the log screen and the log export.
- **The selected-server chip never scrolled.** It asked for the scrollable
  from a context above the list, got null, and did nothing on every phone.

### Security

- **The kept fragment is scrubbed before it is shown.** A display name is
  whatever the user or the panel put after the `#`: control characters that
  would forge a second log line are dropped, and credential-shaped text that
  landed on the wrong side of the separator is redacted (R3). Log redaction
  became idempotent with it — a second pass over an exported line used to add
  a bracket to every placeholder.

## [0.1.0-alpha.3]

`alpha.2` built every artifact and then failed its own verification step: the
pattern that checks each APK carries `libbox.so` used a character class with no
underscore, so `lib/x86_64/libbox.so` could never match. The two ABIs that
passed are the two whose directory names contain no underscore. Fixed.

### Fixed

- **Release verification.** See above. The APKs were always fine.

## [0.1.0-alpha.2]

`v0.1.0-alpha.1` never produced a downloadable file: every APK built and then
`bundleRelease` failed, because ABI splits and an app bundle cannot both be on
while resource shrinking is. Fixed, and the bundle now builds first so the two
cannot interact at all.

### Added

- **Deep links work.** The manifest has always registered Commy as a handler
  for `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`,
  for JSON and YAML config files and for shared text — and nothing on the Dart
  side listened, so tapping such a link opened the app to no effect. A link now
  opens the import sheet with the text already in it, and a Quick Settings tap
  connects. The contract checker no longer excuses that channel.

### Fixed

- **Release artifacts.** See above.

## [0.1.0-alpha.1]

First build anyone can install. **The tunnel has never carried live traffic** —
no subscription has yet returned a real server to point it at — so treat this as
something to look at, not something to rely on. The APK is signed with the debug
key and named accordingly; it installs, and it is not fit for distribution.

What is actually verified: the core builds for three ABIs on a clean machine,
the APK carries `libbox.so` inside it, 649 tests pass with a clean analysis
across the workspace, the Dart↔Kotlin channel contract matches on both sides,
and subscription headers from a real Remnawave panel parse exactly as specified.

### Fixed

- **Four settings did nothing.** The kill switch, "hide unreachable", "auto
  connect" and the `checking` state each wrote or declared a value that no layer
  read. The kill switch is no longer a switch at all: the guarantee belongs to
  Android's "Always-on VPN" with "Block connections without VPN", so the row
  names it and opens the system screen instead of implying Commy provides it.
- **Routing rules were dropped in silence.** Every rule naming `geosite:` or a
  `geoip:` country is removed at build time while no rule set is on disk — which
  keeps the tunnel working, but the warnings explaining it were thrown away.
  They now reach the log and a banner on the routing screen.
- **The reachability probe said nothing.** Its result was stored and read by no
  widget, so «Проверить» ran a real probe and reported nothing at all.

### Added

- **Monorepo skeleton.** Melos workspace with five Dart packages
  (`commy_domain`, `commy_config`, `commy_core`, `commy_data`, `commy_ui`), the
  Flutter application under `apps/commy`, and the Go core under `core/`.
- **Domain layer.** Entities, `Result<T, CommyFailure>`, repository ports and use
  cases, in pure Dart with no dependencies at all — not even on Flutter (rule R5).
- **Link and subscription parsers.** `vless://` including Reality, `vmess://` in
  both the base64-JSON and query forms, `trojan://`, `ss://` including SIP002,
  `hysteria2://`, `tuic://`, `wireguard://`, `socks://` and `http://`.
  Subscription bodies are decoded as plain lists, base64, sing-box JSON or
  Clash YAML, and `subscription-userinfo`, `profile-title`,
  `profile-update-interval` and `announce` headers are read.
- **sing-box config generation.** Full configuration rebuilt from scratch on
  every start rather than patched, so the core's state always follows from the
  app's.
- **Design system.** Tokens, both themes, typography with Inter and JetBrains
  Mono vendored under the OFL, and the component library.
- **Network core.** sing-box v1.13.16 bound with gomobile into `libbox.aar`,
  built by `scripts/build_core.sh`.
- **CI.** Analyze, tests, golden tests, a debug APK, and a release pipeline that
  publishes signed artifacts with SHA-256 sums.

### Notes for anyone reading the history

Two decisions in this window deviate from the specification and are recorded as
ADRs rather than buried in commits:

- [ADR-0006](docs/adr/0006-codegen-and-native-layout.md) — code generation is
  cut down to `drift` and `slang` only; Dart 3 sealed classes replace freezed,
  and Riverpod is used without its generator.
- [ADR-0007](docs/adr/0007-database-encryption.md) — full database encryption is
  deferred. `sqlcipher_flutter_libs` and `sqlite3_flutter_libs` are both
  end-of-life; credentials now live in Keystore/Keychain through secure storage
  and the database holds metadata only.

[Unreleased]: https://github.com/Makhkets/commy/compare/v0.1.0-alpha.4...main
[0.1.0-alpha.4]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.4
[0.1.0-alpha.3]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.1
