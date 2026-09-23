import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #16. The settings screen is the densest control surface in the
/// app, and almost every row on it is a claim about what the process does.
///
/// The assertions that matter are therefore about storage, not about pixels:
/// each switch writes the one field the rest of the app reads, the silence
/// panel holds exactly the three exceptions rule R1 allows, and the row that
/// hands the kill-switch guarantee to the operating system stores nothing at
/// all — a flag written there and read by nobody is the defect
/// `AppSettings` documents having removed.
///
/// The write that did **not** land is covered too, because half of what the
/// controller promises only happens then: a boot receiver armed behind a
/// setting that failed to save outlives the setting, and nothing afterwards
/// puts the two back together.
void main() {
  final t = Translations();

  late CommyTestHarness harness;
  late _RecordingSystemSettings system;

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppSettings settings = AppSettings.defaults,
    RoutingPolicy? policy,
    bool hasVpnSettings = true,
    // `FakeSettingsRepository` cannot be told to refuse a write, and half of
    // what `SettingsController` promises is about the write that did not
    // land. This swaps in a store that reads normally and saves nothing.
    bool settingsWritable = true,
    // The skeleton shimmers forever by design, so the loading state is the
    // one case that cannot be waited out.
    bool animationsEnd = true,
    List<Override> extra = const <Override>[],
  }) async {
    // Taller than the 800x600 default: four sections, a panel and a footer,
    // and a surface that cut the connection rows off would be testing the
    // window rather than the screen.
    tester.view
      ..physicalSize = const Size(420, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(settings: settings);
    addTearDown(harness.dispose);
    system = _RecordingSystemSettings(hasVpnSettings: hasVpnSettings);
    if (policy != null) {
      await harness.routingRepository.write(policy);
    }

    const screen = SettingsScreen();
    await tester.pumpWidget(
      harness.wrap(
        // Riverpod refuses the same provider overridden twice in one
        // container, and the harness already names this one, so the store
        // that saves nothing goes in a child scope underneath rather than
        // beside it. The controller is re-declared with its own constructor
        // for the same reason: an override pins a provider to the container
        // it is named in, and a controller left in the root one would read
        // the root's store and save after all.
        settingsWritable
            ? screen
            : ProviderScope(
                overrides: <Override>[
                  settingsRepositoryProvider.overrideWithValue(
                    _ReadOnlySettingsRepository(harness.settingsRepository),
                  ),
                  settingsControllerProvider.overrideWith(
                    SettingsController.new,
                  ),
                ],
                child: screen,
              ),
        extra: <Override>[
          systemSettingsProvider.overrideWithValue(system),
          ...extra,
        ],
      ),
    );
    if (animationsEnd) {
      await tester.pumpAndSettle();
    } else {
      await settle(tester);
    }
  }

  /// The live provider graph behind the screen.
  ///
  /// Used to ask the *readers* of a setting what they now see, which is the
  /// only way to tell a stored field from a consumed one.
  ProviderContainer scope(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );

  /// What the rest of the app would read back, not what the widget shows.
  Future<AppSettings> stored() async {
    final result = await harness.settingsRepository.read();
    return result.getOrElse(
      (failure) => throw StateError('settings unreadable: $failure'),
    );
  }

  Finder switchFor(String label) => find.byWidgetPredicate(
        (widget) => widget is CommySwitch && widget.semanticLabel == label,
      );

  bool switchValue(WidgetTester tester, String label) =>
      tester.widget<CommySwitch>(switchFor(label)).value;

  RoutingRule rule(String matcher) => RoutingRule(
        id: matcher,
        matcher: matcher,
        action: RuleAction.direct,
      );

  testWidgets('the silence panel holds three exceptions and no more',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.settings.silence.title), findsOneWidget);
    expect(find.text(t.settings.silence.body), findsOneWidget);
    expect(switchFor(t.settings.silence.ipCheck), findsOneWidget);
    expect(switchFor(t.settings.silence.ruleSets), findsOneWidget);
    expect(switchFor(t.settings.silence.blockLists), findsOneWidget);
    expect(find.text(t.settings.silence.footer), findsOneWidget);

    // Rule R1 made countable. Three exceptions, the four connection
    // switches, and — since the owner's decision of 2026-09-18 — the device
    // identifier; a fourth outgoing request cannot appear here without this
    // number moving, which is exactly what the footer promises. The kill
    // switch is deliberately not among them — it is a row, not a switch.
    //
    // The identifier moved the number on purpose and is *not* a fourth
    // exception: it adds a header to requests that already go to the host the
    // user entered, and no new host. That is why it sits in a section of its
    // own under the panel rather than as a fourth row inside it, and why the
    // panel's three are still counted separately below.
    expect(find.byType(CommySwitch), findsNWidgets(8));
    expect(switchFor(t.settings.identity.send), findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: find.text(t.settings.silence.footer),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(CommySwitch),
      ),
      findsNWidgets(3),
      reason: 'The closed list of R1 exceptions is still three.',
    );
  });

  testWidgets('every section row leads somewhere', (tester) async {
    await pumpScreen(tester);

    for (final title in <String>[
      t.settings.routing,
      t.settings.diagnostics,
      t.settings.appearance,
      t.settings.about,
    ]) {
      final tile = tester.widget<SettingsTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(SettingsTile),
        ),
      );
      // The harness stands no router up, so where each row goes is not
      // checkable here — but whether it goes anywhere is, and a row in an
      // index that swallows the tap is indistinguishable from a working one
      // until somebody presses it.
      expect(tile.onTap, isNotNull, reason: title);
    }
  });

  testWidgets('the routing row reads the stored policy, not a fixed blurb',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        mode: RoutingMode.direct,
        rules: <RoutingRule>[rule('geosite:ru'), rule('domain:example.com')],
      ),
    );

    final subtitle = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .firstWhere(
          (text) => text.startsWith(t.routing.mode.direct),
          orElse: () => '',
        );

    expect(subtitle, contains(t.routing.rules));
    expect(subtitle, contains('2'));
    // The static description is the fallback for a policy that has not
    // loaded; showing it over a loaded one would hide the live state.
    expect(find.text(t.settings.routingSubtitle), findsNothing);
  });

  testWidgets('a policy still in flight does not fake an answer',
      (tester) async {
    // Settings and routing are two independent streams, and the second one
    // being slower is an ordinary frame, not an error state.
    await pumpScreen(
      tester,
      extra: <Override>[
        routingPolicyProvider.overrideWith(
          (ref) => Stream<RoutingPolicy>.fromFuture(
            Completer<RoutingPolicy>().future,
          ),
        ),
      ],
    );

    expect(find.text(t.settings.routingSubtitle), findsOneWidget);
    // Off, not the defaults. Rule sets drawn on before the policy arrives
    // would claim the app is willing to fetch files it has not been told to,
    // and the user reading the panel has no way to tell the guess from the
    // stored answer.
    expect(switchValue(tester, t.settings.silence.ruleSets), isFalse);
    expect(switchValue(tester, t.settings.silence.blockLists), isFalse);
  });

  testWidgets('the connection switches each write their own field',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(switchFor(t.settings.connection.autoConnect));
    await tester.pumpAndSettle();

    var settings = await stored();
    expect(settings.autoConnect, isTrue);
    expect(settings.hideUnavailable, isFalse);

    await tester.tap(switchFor(t.settings.connection.hideUnavailable));
    await tester.pumpAndSettle();

    settings = await stored();
    // The second write must not lose the first. Every row here saves the
    // whole envelope, so a row holding a copy taken before the previous tap
    // is how two switches end up undoing each other.
    expect(settings.autoConnect, isTrue);
    expect(settings.hideUnavailable, isTrue);

    // A stored field nobody consults is the defect docs/15-handoff.md §0 is
    // about, so the assertion is made of the reader: every list in the app
    // narrows itself through this filter.
    expect(scope(tester).read(nodeFilterProvider).hideUnavailable, isTrue);
  });

  /// Queue #21. The switch is asserted through its reader — the headers a
  /// subscription request would carry — not through the field it writes.
  testWidgets('the HWID switch decides what a subscription request carries',
      (tester) async {
    await pumpScreen(tester);
    final identity = scope(tester).read(deviceIdentityProvider);

    // On by default: the owner's decision, and what Happ and INCY do.
    expect(switchValue(tester, t.settings.identity.send), isTrue);
    final sent = await identity.subscriptionHeaders();
    expect(sent[DeviceIdentity.hwidHeader], isNotEmpty);
    expect(sent[DeviceIdentity.osHeader], isNotEmpty);

    await tester.ensureVisible(switchFor(t.settings.identity.send));
    await tester.tap(switchFor(t.settings.identity.send));
    await tester.pumpAndSettle();

    expect((await stored()).sendDeviceId, isFalse);
    expect(
      await identity.subscriptionHeaders(),
      isEmpty,
      reason: 'Off means nothing is sent, not "a little less".',
    );
  });

  testWidgets('resetting the identifier gives the panel a new device',
      (tester) async {
    await pumpScreen(tester);
    final identity = scope(tester).read(deviceIdentityProvider);
    final before =
        (await identity.subscriptionHeaders())[DeviceIdentity.hwidHeader];

    await tester.ensureVisible(find.text(t.settings.identity.reset));
    await tester.tap(find.text(t.settings.identity.reset));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(t.settings.identity.resetDone), findsOneWidget);
    final after =
        (await identity.subscriptionHeaders())[DeviceIdentity.hwidHeader];
    expect(after, isNotEmpty);
    expect(after, isNot(before));
    // Let the toast run out, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('start on boot moves the setting and the receiver together',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(switchFor(t.settings.connection.startOnBoot));
    await tester.pumpAndSettle();

    expect((await stored()).startOnBoot, isTrue);
    expect(system.startOnBootCalls, <bool>[true]);

    await tester.tap(switchFor(t.settings.connection.startOnBoot));
    await tester.pumpAndSettle();

    // A boot receiver that stayed enabled behind a switch that reads off is
    // the one defect `setStartOnBoot` exists to close.
    expect((await stored()).startOnBoot, isFalse);
    expect(system.startOnBootCalls, <bool>[true, false]);
  });

  testWidgets('a save that never landed does not arm the boot receiver',
      (tester) async {
    await pumpScreen(tester, settingsWritable: false);

    await tester.tap(switchFor(t.settings.connection.startOnBoot));
    await tester.pumpAndSettle();

    // The order inside `setStartOnBoot` is the whole method: setting first,
    // platform second, second only if the first went through. A receiver
    // armed for a setting that failed to save survives the restart the
    // setting does not, and nothing afterwards reconciles the two.
    expect((await stored()).startOnBoot, isFalse);
    expect(system.startOnBootCalls, isEmpty);
    expect(switchValue(tester, t.settings.connection.startOnBoot), isFalse);
  });

  testWidgets('allow LAN moves the local inbound off loopback', (tester) async {
    // The IP check keeps the mixed inbound in the configuration at all, so
    // the assertion below is about its listen address and nothing else.
    await pumpScreen(
      tester,
      settings: const AppSettings(ipCheckUrl: 'https://ip.example/json'),
    );

    final before = InboundSectionBuilder.mixed(settings: await stored());
    expect(
      before[SingBoxKeys.listen],
      InboundSectionBuilder.loopbackListenAddress,
    );

    await tester.tap(switchFor(t.settings.connection.allowLan));
    await tester.pumpAndSettle();

    final after = InboundSectionBuilder.mixed(settings: await stored());
    expect((await stored()).allowLan, isTrue);
    expect(after[SingBoxKeys.listen], InboundSectionBuilder.lanListenAddress);
  });

  testWidgets('the IP check stores a probe URL and then clears it',
      (tester) async {
    await pumpScreen(tester);
    expect(switchValue(tester, t.settings.silence.ipCheck), isFalse);

    await tester.tap(switchFor(t.settings.silence.ipCheck));
    await tester.pumpAndSettle();

    expect((await stored()).ipCheckUrl, SettingsController.defaultIpCheckUrl);

    await tester.tap(switchFor(t.settings.silence.ipCheck));
    await tester.pumpAndSettle();

    // Exception E-1 off has to mean "there is no host left to call", not a
    // boolean sitting next to a URL that is still there: `isIpCheckEnabled`
    // is the emptiness of this string and nothing else.
    expect((await stored()).ipCheckUrl, isEmpty);
    expect((await stored()).isIpCheckEnabled, isFalse);
  });

  // docs/09: the user sees where an exception's request goes before it goes.
  // The row used to say when ("only when you tap") and never where.
  testWidgets('the IP check names its host before and after it is on',
      (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('ipinfo.io'), findsOneWidget);

    await tester.tap(switchFor(t.settings.silence.ipCheck));
    await tester.pumpAndSettle();
    expect(find.textContaining('ipinfo.io'), findsOneWidget);
  });

  testWidgets('a custom IP check host is the one shown', (tester) async {
    await pumpScreen(
      tester,
      settings: const AppSettings(ipCheckUrl: 'https://ip.example/json'),
    );

    expect(find.textContaining('ip.example'), findsOneWidget);
    expect(find.textContaining('ipinfo.io'), findsNothing);
  });

  testWidgets('the rule-set switch is the routing mode itself', (tester) async {
    await pumpScreen(tester);
    expect(switchValue(tester, t.settings.silence.ruleSets), isTrue);

    await tester.tap(switchFor(t.settings.silence.ruleSets));
    await tester.pumpAndSettle();

    // Exception E-2 is only reachable from rule mode, so switching it off
    // is switching the mode, and the mode it lands on is what decides
    // whether traffic is still proxied.
    expect(harness.routingRepository.policy.mode, RoutingMode.global);

    await tester.tap(switchFor(t.settings.silence.ruleSets));
    await tester.pumpAndSettle();

    expect(harness.routingRepository.policy.mode, RoutingMode.rules);
  });

  testWidgets('the block-list switch writes the policy the builder reads',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(switchFor(t.settings.silence.blockLists));
    await tester.pumpAndSettle();

    expect(harness.routingRepository.policy.blockAds, isTrue);
    // Exception E-3 lives in the routing policy and only there: a second
    // copy in the settings envelope would be two truths about one request.
    expect(await stored(), AppSettings.defaults);
  });

  testWidgets('the block-list row says when the list is not on disk',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(blockAds: true),
    );

    // The switch is on and the core has nothing to apply: the list is a file,
    // and until it is downloaded the feature is a promise. The row is the one
    // place that knows both halves, so it is the one place that can say it.
    expect(find.text(t.settings.silence.blockListsMissing), findsOneWidget);
    expect(find.text(t.settings.silence.blockListsHint), findsNothing);
  });

  testWidgets('the block-list row goes quiet once the list is downloaded',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(blockAds: true),
    );
    await harness.ruleSetRepository.download(
      tag: RouteSectionBuilder.adsRuleSetTag,
      from: Uri.parse(
        'https://mirror.example/${RouteSectionBuilder.adsRuleSetTag}.srs',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.settings.silence.blockListsMissing), findsNothing);
    expect(find.text(t.settings.silence.blockListsHint), findsOneWidget);
  });

  testWidgets('a list nobody asked for does not make the row complain',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.settings.silence.blockListsMissing), findsNothing);
    expect(find.text(t.settings.silence.blockListsHint), findsOneWidget);
  });

  testWidgets('the kill-switch row opens the system screen and stores nothing',
      (tester) async {
    await pumpScreen(tester);
    final before = await stored();

    await tester.tap(find.text(t.settings.connection.killSwitch));
    await tester.pumpAndSettle();

    expect(system.vpnSettingsOpened, 1);
    // The guarantee belongs to Android. A row that also wrote a flag would
    // be a claim about blocked traffic that nothing in the app enforces.
    expect(await stored(), before);
    expect((await stored()).toJson().containsKey('killSwitch'), isFalse);
    expect(
      find.text(t.settings.connection.killSwitchUnavailable),
      findsNothing,
    );
  });

  testWidgets('a system with no VPN screen says so instead of swallowing it',
      (tester) async {
    await pumpScreen(tester, hasVpnSettings: false);

    await tester.tap(find.text(t.settings.connection.killSwitch));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.connection.killSwitchUnavailable),
      findsOneWidget,
    );

    // Let the toast time out so its timer does not outlive the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('every switch shows the stored value, not a default',
      (tester) async {
    await pumpScreen(
      tester,
      settings: const AppSettings(
        autoConnect: true,
        startOnBoot: true,
        hideUnavailable: true,
        allowLan: true,
        ipCheckUrl: 'https://ip.example/json',
      ),
      policy: RoutingPolicy.defaults.copyWith(
        mode: RoutingMode.global,
        blockAds: true,
      ),
    );

    expect(switchValue(tester, t.settings.connection.autoConnect), isTrue);
    expect(switchValue(tester, t.settings.connection.startOnBoot), isTrue);
    expect(switchValue(tester, t.settings.connection.hideUnavailable), isTrue);
    expect(switchValue(tester, t.settings.connection.allowLan), isTrue);
    expect(switchValue(tester, t.settings.silence.ipCheck), isTrue);
    expect(switchValue(tester, t.settings.silence.blockLists), isTrue);
    // Rule sets are the mode, and this policy is global: a switch reading
    // `true` here would be offering to download files nothing consults.
    expect(switchValue(tester, t.settings.silence.ruleSets), isFalse);
  });

  testWidgets('draws the shape of the answer before the first value arrives',
      (tester) async {
    await pumpScreen(
      tester,
      animationsEnd: false,
      extra: <Override>[
        settingsProvider.overrideWith(
          (ref) => Stream<AppSettings>.fromFuture(
            Completer<AppSettings>().future,
          ),
        ),
      ],
    );

    expect(find.byType(ListSkeleton), findsOneWidget);
    // Not the rows with a guessed default underneath them: a switch drawn
    // off before the stored value lands is a lie for as long as it is drawn.
    expect(switchFor(t.settings.connection.autoConnect), findsNothing);
  });

  testWidgets('a failure carries a cause, an action and a route to the logs',
      (tester) async {
    var reads = 0;
    await pumpScreen(
      tester,
      extra: <Override>[
        settingsProvider.overrideWith((ref) {
          reads++;
          return Stream<AppSettings>.error(const StorageFailure('disk'));
        }),
      ],
    );

    expect(find.text(t.error.title), findsOneWidget);
    expect(find.text(t.error.storage.message), findsOneWidget);
    expect(find.text(t.error.storage.action), findsOneWidget);
    expect(find.text(t.error.openLogs), findsOneWidget);

    final before = reads;
    await tester.tap(find.text(t.error.storage.action));
    await tester.pumpAndSettle();

    // The button has to do the thing it is labelled with. `FailureView`
    // swallows a null `onRetry` without complaint, so a screen that forgot
    // to pass one renders exactly these three widgets and answers a tap with
    // nothing — an error state that cannot be left, and a green test.
    expect(reads, greaterThan(before));
  });
}

/// A [SystemSettings] that records instead of calling a platform channel.
///
/// The harness does not override `systemSettingsProvider`, and the real one
/// would answer `false` to everything in a test because there is no plugin
/// behind the channel — which would make "the platform refused" and "the app
/// never asked" the same observation.
class _RecordingSystemSettings extends SystemSettings {
  _RecordingSystemSettings({this.hasVpnSettings = true});

  final bool hasVpnSettings;

  int vpnSettingsOpened = 0;

  final List<bool> startOnBootCalls = <bool>[];

  @override
  Future<bool> openVpnSettings() async {
    vpnSettingsOpened++;
    return hasVpnSettings;
  }

  @override
  Future<bool> setStartOnBoot({required bool enabled}) async {
    startOnBootCalls.add(enabled);
    return true;
  }

  /// Answers what a device would, without a channel.
  ///
  /// Overridden for a reason worth naming: the real one invokes a method
  /// channel, and awaiting that inside `testWidgets` never completes — the
  /// reply arrives on a queue the test's fake clock does not drive. A test
  /// that touches the device identity would hang rather than fail, which is
  /// the worst way for a test to be wrong.
  @override
  Future<DeviceDescription?> deviceInfo() async => const DeviceDescription(
        os: 'Android',
        osVersion: '16',
        model: 'Pixel Test',
      );
}

/// A [SettingsRepository] that reads like the harness's one and saves nothing.
///
/// `FakeSettingsRepository` accepts every write, which makes the half of
/// `SettingsController` that only runs when a write *failed* invisible. The
/// reads delegate, so the screen renders the same content either way and the
/// only difference is the outcome of the save.
class _ReadOnlySettingsRepository implements SettingsRepository {
  _ReadOnlySettingsRepository(this._inner);

  final SettingsRepository _inner;

  @override
  Stream<AppSettings> watch() => _inner.watch();

  @override
  Future<Result<AppSettings, CommyFailure>> read() => _inner.read();

  @override
  Future<Result<void, CommyFailure>> write(AppSettings settings) async =>
      const Err<void, CommyFailure>(StorageFailure('read-only'));

  @override
  Future<Result<String?, CommyFailure>> readSelectedNodeId() =>
      _inner.readSelectedNodeId();

  @override
  Future<Result<void, CommyFailure>> writeSelectedNodeId(String? nodeId) =>
      _inner.writeSelectedNodeId(nodeId);
}
