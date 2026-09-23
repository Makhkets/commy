# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are cut from tags matching `v*`; the release workflow reads the section
matching the tag out of this file and uses it as the release notes.

## [Unreleased]

## [0.1.0-alpha.7]

- An unlimited plan draws a full traffic bar, in the calm colour — not red.
- Release notes carry only the release they describe; each earlier one
  carried the whole changelog.

## [0.1.0-alpha.6]

The earlier alphas are withdrawn: none of them connected to REALITY servers on
Xray 26.7.

- **Connects to REALITY servers on Xray 26.7.** They refuse clients that call
  themselves older than 26.3.27, and sing-box calls itself 1.8.1.
- **The server you pick is the one traffic goes through.** A choice made while
  disconnected used to lose to the server used last time.
- **"Check" and "Measure all" work with the tunnel up.** They used to report
  every server down.
- Servers that did not answer are grey; Auto wears the EU flag; the list keeps
  a margin from the screen edges.
- A toast after a subscription refresh, whether it worked or not.
- Settings → Reset: network settings and app settings.

## [0.1.0-alpha.5]

The release that met a live stand: servers of every protocol on the list, a
panel with a device limit, and an emulator that loses its Wi-Fi on purpose.
Three things matter more than the rest of this list: a tunnel that dies now
says so instead of showing "Connected"; the core's log reaches the log screen
at all; and REALITY keeps working against Xray 26.9.8 and later.

**If alpha.4 is installed, uninstall it first.** Neither build is signed with
a release key, so Android will not install one over the other.

### Added

- **Ad blocking works, and it works in DNS.** The switch had been in settings
  since the silence panel existed, and nothing behind it could ever apply: it
  asked for a list called `geosite-ads`, which no mirror publishes, so the
  download answered 404 and every configuration was built with the rule left
  out. The list is now `geosite-category-ads-all` — the file the default source
  actually serves — and a query for an advertising name is refused at the
  resolver (`action: reject`) rather than answered and then dialled into a
  rejected connection. The route-level rejection stays for names that never
  reach DNS. Nothing new goes on the wire: the list is exception E-2's file,
  downloaded by the same button from the same configurable address, and the
  settings row now says when the switch is on but the list is not on disk
  instead of reporting "on".

- **XHTTP servers connect.** XHTTP is Xray's transport — the proxied connection
  rides ordinary HTTP requests, which is what survives a CDN — and sing-box does
  not have it, so until now a server of this kind was refused at import with
  "transport is not supported by the core" while the same link worked in Happ.
  The client is ours (`core/xhttp`): `packet-up`, `stream-up`, `stream-one` and
  `auto`; HTTP/1.1, HTTP/2 and HTTP/3; REALITY; XMUX; padding and every
  placement a link's `extra` can name. It reaches the pinned sing-box through a
  build overlay — eleven added lines in two upstream files, checked by hash —
  so the core in `go.mod` is still the published v1.13.16 and no new module was
  added; the AAR grew by 177 KB across three ABIs. Links (VLESS, VMess, Trojan),
  Clash.Meta `xhttp-opts`, sing-box and Xray JSON all import and export without
  loss. Verified against real Xray binaries — the 26.3.27 release and 26.9.9 —
  in every mode over every HTTP version, 24 MiB down and 16 MiB up with
  checksums, and on an Android emulator. `downloadSettings` (a second route for
  the download) is not implemented. Reasoning in
  docs/adr/0010-xhttp-transport.md.

- **A QR code for a server and for a subscription.** Reading one has worked
  since the import sheet existed; drawing one did not, so moving a server to a
  second phone meant pasting a credential into a messenger. Both menus now
  offer it, over `qr_flutter` (BSD-3-Clause, pure Dart, nothing measurable in
  the APK). The subscription code says what it hands over before it is on
  screen — it is the access token, not a server. A protocol with no link
  format, and a payload too long to scan, are both said out loud rather than
  shown as a blank square.

### Changed

- **A panel's refusal reads as a refusal, not as a server.** A panel that will
  not serve this client answers with one entry addressed at `0.0.0.0` and the
  reason where a server's name goes — "App not supported", "Device limit
  reached", "Subscription expired". The app imported it, drew it in the list
  with a flag and a ping button, offered to connect through it, and reported
  "imported 1 server"; the one thing it never did was show what the panel had
  said. The rule is the address, not the wording (an admin writes that in their
  own language): such an entry is kept out of the server list, out of the Auto
  group, out of the generated document and out of the count, and its text is
  shown in the subscription card and in the import sheet, untranslated.
- **Adding a subscription you already have refreshes it instead of making a
  second card** (owner's decision, 2026-09-17). It was never only a duplicate
  in the list: a node's id comes from the server, so the same server fetched
  under a new subscription id takes its row with it — the second card filled up
  and the first quietly emptied. What counts as the same URL is now one answer
  in one place: the fragment, a trailing slash, the order of query parameters
  and a default port are ignored; the path (case included), the userinfo and
  every parameter value are not, so two accounts on one panel stay two cards.
  It fails closed — a stored subscription whose URL the keystore can no longer
  give back stops the add rather than guessing. Rules and reasoning in
  docs/adr/0008-subscription-identity.md. An existing pair of duplicates is not
  merged; that is a decision for a screen, not for an import.
- **`x-ver-os` and `x-device-model` are sent with the subscription request**,
  completing the header set #21 asked for. They come from an eleventh channel
  method rather than from a new dependency: `dart:io` reports a kernel build
  string where a panel wants `16`, and has no notion of a model at all, and
  `device_info_plus` would bring native code along for three strings. A field
  the platform cannot answer is left out rather than guessed — the panel stores
  what it is sent and shows it back as the name of the user's device. Neither
  value identifies anybody; both are in every browser's user agent already.
  Reasoning in docs/adr/0009-device-identifier.md.
- **The tunnel notification stops flickering.** It hung off the traffic stream,
  which ticks once a second whether or not anything moved, so an idle tunnel
  re-posted an identical notification sixty times a minute — visible in the
  shade and, measured on a device, sixty notification-removed events. It is now
  posted only when what the user would read has changed: zero in twenty seconds
  where there were twenty.
- **The refresh interval picked on the import sheet is applied on a repeat
  add.** The panel's own `profile-update-interval` still wins, but only when it
  sends one in that response — the rule used to be "when nothing is stored
  yet", which on a second add is never, so the switch beside it worked and the
  interval silently did not.

### Security

- **Known, measured, not ours to fix: under Android's own kill switch, names
  are still looked up in the clear while the tunnel is down.** With "Always-on
  VPN" and "Block connections without VPN" set and the tunnel down — after
  Disconnect, or in the seconds after the core crashed — connections are
  blocked as they should be, but a DNS query an app makes still reaches the
  network's resolver unencrypted: Android sends it from netd as uid 0, which
  its lockdown exempts. Every VPN client on Android shares this; it was
  reported publicly in 2024. Google Play services also keeps its own
  connection outside the lockdown by platform privilege. Measurements and the
  one mitigation an app could try — keeping a blocking TUN up while
  disconnected, an owner's decision — are in docs/09-security-privacy.md.

### Fixed

Found by running the app on an Android emulator against live servers of every
protocol on the list (session 15). Each one was invisible to the unit tests,
and most of them to anyone who does not unplug things on purpose.

- **After a crash the notification no longer says "Connected".** The core
  lives in the app's process, so when that process dies — a Go panic, the
  low-memory killer — the tunnel dies with it and every app goes back to the
  open network. Android kept the last notification up regardless: "Connected",
  a speed and a Disconnect button, over a device that was not protected, for as
  long as nothing started the app again. The service is sticky now, so the
  system restarts it to report the loss ("The tunnel stopped — apps are using
  the network without the proxy", or, under the system kill switch, "nothing
  reaches the network until it is back"); and where Android 16 skips that
  restart — its VPN code unbinds from the service at the instant the process
  dies, which leaves the service record behind — the next start of the app
  clears the stale notification and opens on "The core stopped unexpectedly"
  instead of a quiet "Disconnected".
- **The core's log reaches the log screen.** Not one line of it ever arrived
  in a release build: the log stream was opened before the core started,
  libbox refuses that request until the service is up, and the stream ended
  there without a word — so the screen showed the app's own lines and none of
  the core's. It opens after the start now, and begins with everything the
  core kept from start-up.
- **A subscription link shared to the app, pasted or scanned is imported as a
  subscription.** Sharing the link from a panel's bot opened the paste sheet,
  and the import answered "the subscription response could not be read"
  without asking the panel anything: the text went to the proxy-link parser,
  which rightly refused it. A single http(s) line that is not a proxy is now
  fetched as the subscription it is.
- **"Check" reports a working tunnel as working.** The core measures a whole
  group at once and reports each server as it finishes; the app read the first
  report and looked for the server it had asked about, which was usually still
  in flight — so the check failed on every press, while traffic flowed. It now
  waits for that server's own fresh result. "Measure all" with the tunnel up
  asked for one full round per server — nine servers, eighty-one probes — and
  now shares one round.
- **The system Back button no longer closes the app.** Every screen was a
  sibling route, so Back — the gesture people use far more than the arrow on
  screen — had nothing to return to from Settings, Routing, DNS or Diagnostics
  and left the app. The routes are nested the way the paths always read.
- **A tap on "open the app to connect" connects.** The notification after a
  reboot, the one after a crash and the Quick Settings tile all open the app
  with a connect request, and that request arrived before the database had
  answered: no selection, no servers, nothing done. It waits for them now.
- **A connect is not repeated behind the user's back.** The last system intent
  was replayed to every new Flutter engine for the life of the process — and
  the process outlives the screen whenever a tunnel is up. Open the app from
  the notification, disconnect, press Back, open it again: the tunnel came back
  up on its own. A tapped `vless://` link reopened its import sheet the same
  way. Each intent is delivered once now.
- **The panel's announcement is shown.** The subscription card has had a place
  for the `announce` header since the card existed, and nothing ever filled
  it: the header was parsed and then dropped on the way to the database. It
  arrives now, and goes away when the panel stops sending it.
- **Ping without a tunnel measures the server, not the resolver.** The name
  was resolved inside the timed window, so the first batch of "measure all"
  paid for every cold lookup — 196 ms against 44 for identical servers on one
  host — and sorting by latency sorted by who went first.
- **Hysteria2 and TUIC are not labelled TCP.** Every server whose link names
  no transport was described as TCP, including the two that have no TCP port;
  they read QUIC now, and WireGuard UDP.
- **"App not supported" says why when the device identifier is off.** That is
  word for word what a panel with a device limit sends a client without
  `x-hwid`; with the switch off, the card and the import sheet now say so, and
  the card turns it back on and refreshes in one tap.
- **The IP check names its host.** docs/09 asks that the user see where an
  exception's request goes before it goes; the row in the silence panel said
  when and never where. It reads `ipinfo.io · only when you tap` now.
- **"Commy is not connected" does not outlive a connection.** The prompt posted
  at boot or by an always-on start stayed in the shade under "Connected" until
  it was tapped. It is taken down when a tunnel comes up, and it is posted
  where it can be seen — no longer in the silent section of the shade.
- **Sizes and speeds read in the reader's language.** A Russian screen said
  `6.0 GB из 100 GB` and `37.1 KB/s`: Latin symbols and a decimal point, the
  one line nobody had translated. It is `6,0 ГБ из 100 ГБ` and `37,1 КБ/с` now,
  in the app and in the notification alike; English keeps `GB` and `KB/s`.
- **Reconnecting no longer leaves a TUN interface behind.** Every stop or
  reload of the core left the old interface in the system and a thread asleep
  on its descriptor — five reconnects, five more interfaces. The fault is in
  sing-tun: closing the gVisor stack wrapped the "detach" signal so that the
  reader never saw it, and that reader kept the descriptor *number*, which the
  next core reuses — a woken one could read a live socket or the new tunnel.
  The same one-line fix upstream sing-tun carries is applied through the build
  overlay, since v1.13.16 pins a sing-tun without it; a test against the
  library fails without it. docs/adr/0012-gvisor-reader-stop.md.
- **The routing screen explains a dropped rule in the reader's language.** The
  banner above the rules had a Russian heading and, under it, the builder's own
  English — "Rule "geosite:ru" needs geosite-ru, which is not on disk; the
  rule was left out". The builder hands over what it dropped, not a sentence,
  and the screen words it: `geosite:ru — нужно загрузить: geosite-ru`.

- **REALITY keeps working against Xray 26.9.8 and later.** Found while testing
  XHTTP, and nothing to do with it: plain VLESS + REALITY stopped connecting to
  a current Xray. sing-box strips the `X25519MLKEM768` key share from its
  REALITY ClientHello, because servers older than Xray 25.5 cannot finish a
  handshake that offers it — and since 26.9.8 the server refuses a ClientHello
  that does *not* offer it, as one no browser sends. No released sing-box copes
  with both. The client now sends the hello Chrome sends, and falls back to the
  stripped one only after a server has answered with somebody else's
  certificate; a timeout switches nothing. Tested against eight Xray
  generations from 1.8.4 to 26.9.9: all connect, the old ones on the second
  attempt. In this uTLS only Chrome's hellos carry that share, and a REALITY
  server does not check the fingerprint, so a REALITY server is now always
  reached with `chrome`, whatever the link's `fp=` says; `firefox`, `safari`
  and the rest failed on 26.9.x with a stranger's certificate. The link itself
  — export, QR, copy — keeps what it had. docs/adr/0011-reality-client-hello.md,
  confirmed by the owner.
- **One malformed server no longer stops every other server connecting.** The
  document holds every stored server, so that switching does not mean
  reconnecting — and one entry the builder could not express (Reality with no
  public key, a port of 70000, a duplicate id) made the whole build fail, so
  the user who had picked a perfectly good server could connect to none. Such a
  server is now left out and named in the log; the build still fails, with the
  reason, when it is the server that was asked for.
- **A server that appeared while the tunnel was up can be switched to.** The
  running document is a snapshot taken at start; a server imported after that,
  or brought in by a subscription refresh, was in the list and not in the core,
  and tapping it answered "could not switch" until the user disconnected
  first. The core is asked, and the document is rebuilt around the new server
  when it has to be — `reload` keeps the TUN device. A rebuild that fails
  leaves the old server selected, because traffic still leaves through it.
- **A uTLS fingerprint never reaches a QUIC protocol.** The core answers a
  `utls` block under Hysteria 2 or TUIC with "unsupported usage for uTLS" on
  every connection, and Clash configs set the fingerprint globally.

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

[Unreleased]: https://github.com/Makhkets/commy/compare/v0.1.0-alpha.7...main
[0.1.0-alpha.7]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.7
[0.1.0-alpha.6]: https://github.com/Makhkets/commy/releases/tag/v0.1.0-alpha.6
