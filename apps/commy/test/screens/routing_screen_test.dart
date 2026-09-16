import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #16. This screen owns the policy that decides what leaves
/// through the tunnel, so every control on it is a rule R6 surface: a mode
/// that does not store, a rule that does not round-trip, or a row that leads
/// nowhere all send traffic somewhere the user did not ask for.
///
/// The assertions that matter read the value back out of
/// `harness.routingRepository` — the same place `BuildConfigUseCase` reads it
/// from — plus the banner, which is the only thing that ever tells a user
/// their `geosite:` rule was dropped by the builder instead of applied.
void main() {
  final t = Translations();

  RoutingRule rule(
    String matcher, {
    int sortIndex = 0,
    RuleAction action = RuleAction.direct,
  }) =>
      RoutingRule(
        id: matcher,
        matcher: matcher,
        action: action,
        sortIndex: sortIndex,
      );

  RoutingPolicy policyWith(List<RoutingRule> rules) =>
      RoutingPolicy.defaults.copyWith(mode: RoutingMode.rules, rules: rules);

  late CommyTestHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    RoutingPolicy? policy,
    DnsSettings? dns,
    List<String> ruleSetsOnDisk = const <String>[],
    List<Override> extra = const <Override>[],
    bool settleFully = true,
  }) async {
    // Taller than the 800x600 default because the mode control, the rules,
    // the final outcome and four more rows are not one screen; and wider than
    // a phone because the test font draws every glyph as a square em, which
    // makes `tls://1.1.1.1 · prefer_ipv4` about three times the width it has
    // on a device. Still under `CommyBreakpoints.compact`, so this is the
    // phone shell with the phone's bottom sheet.
    tester.view
      ..physicalSize = const Size(560, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);
    if (policy != null) {
      await harness.routingRepository.write(policy);
    }
    if (dns != null) {
      await harness.routingRepository.writeDns(dns);
    }
    for (final tag in ruleSetsOnDisk) {
      await harness.ruleSetRepository.download(
        tag: tag,
        from: Uri.parse('https://seeded.example/$tag'),
      );
    }

    await tester.pumpWidget(harness.wrap(const RoutingScreen(), extra: extra));
    // The skeleton shimmers forever, so a screen parked on it can only be
    // pumped, never settled.
    if (settleFully) {
      await tester.pumpAndSettle();
    } else {
      await settle(tester);
    }
  }

  RoutingPolicy stored() => harness.routingRepository.policy;

  List<String> storedMatchers() =>
      <String>[for (final item in stored().rules) item.matcher];

  /// The row that renders [matcher]; the final outcome renders its own words.
  RuleRow rowFor(WidgetTester tester, String matcher) =>
      tester.widget<RuleRow>(find.widgetWithText(RuleRow, matcher));

  /// Builds a document the way the tunnel controller would.
  ///
  /// The banner reports what the *last build* threw away, so a test that wants
  /// to see it has to make a build happen rather than hand the screen a list
  /// of strings the test invented.
  Result<CoreConfig, CommyFailure> buildConfig(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RoutingScreen)),
      listen: false,
    );
    return container.read(configGeneratorProvider).build(
          node: testNode(),
          routing: harness.routingRepository.policy,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          includeClashApi: false,
        );
  }

  /// The outbound tag the built document sends unmatched traffic to.
  String finalOutboundOf(WidgetTester tester) => buildConfig(tester).fold(
        (config) => (config.document['route']! as JsonMap)['final']! as String,
        (failure) => fail('the document did not build: ${failure.code}'),
      );

  testWidgets('the three modes are offered and the pick is stored',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.routing.mode.global), findsOneWidget);
    expect(find.text(t.routing.mode.rules), findsOneWidget);
    expect(find.text(t.routing.mode.direct), findsOneWidget);

    await tester.tap(find.text(t.routing.mode.direct));
    await tester.pumpAndSettle();
    expect(stored().mode, RoutingMode.direct);

    await tester.tap(find.text(t.routing.mode.global));
    await tester.pumpAndSettle();
    expect(stored().mode, RoutingMode.global);
  });

  testWidgets('with no rules of its own it offers the way to write one',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.routing.emptyRules), findsOneWidget);
    expect(find.text(t.routing.emptyRulesBody), findsOneWidget);

    // An empty state without a next step is half a state, so the way out has
    // to be the control and not a label beside the real one.
    await tester.tap(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.text(t.routing.addRule),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.routing.newRule.title), findsOneWidget);
  });

  testWidgets('a rule typed into the sheet reaches storage', (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('domain:example.com')]),
    );

    await tester.tap(find.text(t.routing.addRule));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CommyTextField), '  geosite:netflix  ');
    await tester.tap(find.text(t.routing.action.block));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.routing.newRule.save));
    await tester.pumpAndSettle();

    final rules = stored().rules;
    expect(rules, hasLength(2));
    // Trimmed: a matcher with a space around it is not one the core parses,
    // and the sheet is where that gets fixed.
    expect(rules.last.matcher, 'geosite:netflix');
    expect(rules.last.action, RuleAction.block);
    // Order is priority, and a new rule goes below what is already there.
    expect(rules.last.sortIndex, 1);
    expect(find.text('geosite:netflix'), findsOneWidget);
  });

  testWidgets('each rule wears the badge of the action it stores',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[
        rule('domain:proxied.example', action: RuleAction.proxy),
        rule('domain:direct.example', sortIndex: 1),
        rule('domain:blocked.example', sortIndex: 2, action: RuleAction.block),
      ]),
    );

    // The badge is the only place a stored action is ever shown. A mapping
    // off by one would read the same to the eye and tell the user a blocked
    // domain goes through the tunnel, which is the rule R6 failure the screen
    // is supposed to prevent rather than cause.
    final expected = <String, RuleAction>{
      'domain:proxied.example': RuleAction.proxy,
      'domain:direct.example': RuleAction.direct,
      'domain:blocked.example': RuleAction.block,
    };
    final words = <RuleAction, String>{
      RuleAction.proxy: t.routing.action.proxy,
      RuleAction.direct: t.routing.action.direct,
      RuleAction.block: t.routing.action.block,
    };
    for (final entry in expected.entries) {
      final row = rowFor(tester, entry.key);
      expect(row.action, entry.value, reason: entry.key);
      expect(row.actionLabel, words[entry.value], reason: entry.key);
    }
  });

  testWidgets('a match that is only whitespace is refused where it is typed',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.text(t.routing.addRule),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CommyTextField), '   ');
    await tester.tap(find.text(t.routing.newRule.save));
    await tester.pumpAndSettle();

    expect(find.text(t.routing.newRule.empty), findsOneWidget);
    // The sheet stays open and nothing was written: a rule the core could not
    // build never becomes one.
    expect(find.text(t.routing.newRule.title), findsOneWidget);
    expect(stored().rules, isEmpty);
  });

  testWidgets('swiping a rule away removes exactly that rule', (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[
        rule('domain:example.com'),
        rule('geoip:private', sortIndex: 1),
      ]),
    );

    await tester.drag(find.text('domain:example.com'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(storedMatchers(), <String>['geoip:private']);
    expect(find.text('domain:example.com'), findsNothing);
  });

  testWidgets('dragging a rule over another rewrites priority', (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[
        rule('domain:example.com'),
        rule('geoip:private', sortIndex: 1),
      ]),
    );

    // The second row's handle. The third `drag` glyph belongs to the final
    // outcome, which is inert by design.
    final handle = tester.getCenter(find.byIcon(CommyIcons.drag).at(1));
    final gesture = await tester.startGesture(handle);
    await tester.pump(const Duration(milliseconds: 100));
    // Step by step, not one jump: the list picks the drop slot on each
    // pointer update, so a single long move lands the row back where it was.
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(storedMatchers(), <String>['geoip:private', 'domain:example.com']);
    // The core reads `sortIndex`, not the position in the list, so a drag
    // that moved the row without renumbering would change nothing at all.
    expect(
      <int>[for (final item in stored().rules) item.sortIndex],
      <int>[0, 1],
    );
  });

  testWidgets('the final outcome is out of reach of the drag and the swipe',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('domain:example.com')]),
    );

    final last = rowFor(tester, t.routing.finalRule);
    // Routing has to end somewhere: a last rule that can be dragged above
    // another, or swiped away, leaves traffic that matched nothing with no
    // answer at all. Neither gesture reaches it, and the row knows it.
    expect(last.isFinal, isTrue);
    expect(last.dragIndex, isNull);
    expect(
      find.ancestor(
        of: find.text(t.routing.finalRule),
        matching: find.byType(Dismissible),
      ),
      findsNothing,
    );
    expect(rowFor(tester, 'domain:example.com').dragIndex, 0);

    await tester.drag(find.text(t.routing.finalRule), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text(t.routing.finalRule), findsOneWidget);
    expect(storedMatchers(), <String>['domain:example.com']);
    // In Rules mode the badge says Proxy because the document says `proxy`.
    // Which mode it follows is pinned below; here it only has to be true.
    expect(last.action, RuleAction.proxy);
    expect(last.actionLabel, t.routing.action.proxy);
  });

  testWidgets('the final outcome names the outbound the document sends it to',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('domain:example.com')]),
    );

    // This row is a statement about where *all* unmatched traffic goes, which
    // makes a wrong word here a rule R6 failure rather than a typo: in Direct
    // mode every unmatched packet leaves outside the tunnel while the screen
    // used to promise the proxy. The assertion is against the built document,
    // not against a second copy of the mapping, so the screen and
    // `RouteSectionBuilder.finalOutbound` cannot drift apart unnoticed.
    final expected = <RoutingMode, (String, RuleAction, String)>{
      RoutingMode.rules: (
        t.routing.mode.rules,
        RuleAction.proxy,
        SingBoxTags.proxyGroup,
      ),
      RoutingMode.global: (
        t.routing.mode.global,
        RuleAction.proxy,
        SingBoxTags.proxyGroup,
      ),
      RoutingMode.direct: (
        t.routing.mode.direct,
        RuleAction.direct,
        SingBoxTags.direct,
      ),
    };
    final words = <RuleAction, String>{
      RuleAction.proxy: t.routing.action.proxy,
      RuleAction.direct: t.routing.action.direct,
    };

    for (final entry in expected.entries) {
      final (segment, action, tag) = entry.value;
      await tester.tap(find.text(segment));
      await tester.pumpAndSettle();

      expect(stored().mode, entry.key);
      expect(finalOutboundOf(tester), tag, reason: segment);
      await tester.pumpAndSettle();

      final last = rowFor(tester, t.routing.finalRule);
      expect(last.action, action, reason: segment);
      expect(last.actionLabel, words[action], reason: segment);
    }
  });

  testWidgets('outside Rules mode the rules say they are not in force',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('domain:example.com')]),
    );

    // Rules mode is the only one that walks them, so this is the only mode
    // with nothing to disclose.
    expect(find.text(t.routing.inactive.body), findsNothing);

    await tester.tap(find.text(t.routing.mode.global));
    await tester.pumpAndSettle();

    // The builder skips `activeRules` entirely outside Rules mode: the rule
    // below is stored, editable and completely absent from the document. Even
    // the dropped-rules banner cannot speak for it, because the loop that
    // emits those warnings is the one being skipped.
    expect(find.text(t.routing.inactive.body), findsOneWidget);
    expect(find.text('domain:example.com'), findsOneWidget);
    buildConfig(tester);
    await tester.pumpAndSettle();
    expect(find.text(t.routing.dropped.title), findsNothing);

    await tester.tap(find.text(t.routing.mode.direct));
    await tester.pumpAndSettle();
    expect(find.text(t.routing.inactive.body), findsOneWidget);
  });

  testWidgets('the way back into force is one tap, and the rules survive it',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        mode: RoutingMode.direct,
        rules: <RoutingRule>[rule('domain:example.com')],
      ),
    );

    await tester.tap(find.text(t.routing.inactive.action));
    await tester.pumpAndSettle();

    expect(stored().mode, RoutingMode.rules);
    expect(find.text(t.routing.inactive.body), findsNothing);
    // Deleting a user's rules because a mode changed would be worse than the
    // defect, so the notice only ever changes the mode.
    expect(storedMatchers(), <String>['domain:example.com']);
  });

  testWidgets('rules stay editable while they are out of force',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(mode: RoutingMode.global),
    );

    // The notice is a disclosure, not a lock: a user setting up Rules mode
    // writes the rules first and switches after.
    await tester.tap(
      find.descendant(
        of: find.byType(EmptyState),
        matching: find.text(t.routing.addRule),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CommyTextField), 'domain:example.com');
    await tester.tap(find.text(t.routing.newRule.save));
    await tester.pumpAndSettle();

    expect(storedMatchers(), <String>['domain:example.com']);
    expect(find.text(t.routing.inactive.body), findsOneWidget);
  });

  testWidgets('a rule the builder throws away is said out loud, then not',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('geosite:ru')]),
    );

    // Nothing has been built yet, so there is nothing to warn about.
    expect(find.text(t.routing.dropped.title), findsNothing);

    buildConfig(tester);
    await tester.pumpAndSettle();

    expect(find.text(t.routing.dropped.title), findsOneWidget);
    expect(find.text(t.routing.dropped.body), findsOneWidget);
    // Which rule, not merely that there was one: the rule stays on screen
    // looking applied, and the tag is the only clue to which file fixes it.
    // The row itself reads `geosite:ru`, so the hyphenated tag can only have
    // come from the builder.
    expect(find.textContaining('geosite-ru'), findsOneWidget);

    await harness.ruleSetRepository.download(
      tag: 'geosite-ru',
      from: Uri.parse('https://mirror.example/geosite-ru.srs'),
    );
    await tester.pumpAndSettle();
    buildConfig(tester);
    await tester.pumpAndSettle();

    // A banner that never clears is a banner nobody reads.
    expect(find.text(t.routing.dropped.title), findsNothing);
  });

  testWidgets('the rows that lead deeper are live, not dead strings',
      (tester) async {
    await pumpScreen(tester);

    for (final title in <String>[
      t.routing.apps,
      t.routing.ruleSets,
      t.routing.dns,
    ]) {
      final tile = tester.widget<SettingsTile>(
        find.widgetWithText(SettingsTile, title),
      );
      expect(tile.onTap, isNotNull, reason: '"$title" leads nowhere');
    }
  });

  testWidgets('the rule sets row counts what the rules need against the disk',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[
        rule('geosite:ru'),
        rule('geoip:ru', sortIndex: 1),
        // Needs no file: `geoip:private` becomes `ip_is_private`, so counting
        // it would send the user after a set that does not exist.
        rule('geoip:private', sortIndex: 2),
      ]),
      ruleSetsOnDisk: <String>['geosite-ru'],
    );

    expect(
      find.text(t.routing.ruleSetsValue(have: 1, need: 2)),
      findsOneWidget,
    );
  });

  testWidgets('that count follows the mode, not the rules left lying around',
      (tester) async {
    await pumpScreen(
      tester,
      policy: policyWith(<RoutingRule>[rule('geosite:ru')]),
    );

    expect(
      find.text(t.routing.ruleSetsValue(have: 0, need: 1)),
      findsOneWidget,
    );

    await tester.tap(find.text(t.routing.mode.global));
    await tester.pumpAndSettle();

    // Global routing consults no rule, so nothing is missing. A row that kept
    // counting would send the user off to download a file that would change
    // nothing about where their traffic goes.
    expect(
      find.text(t.routing.ruleSetsValue(have: 0, need: 0)),
      findsOneWidget,
    );
  });

  testWidgets('the Apps and DNS rows report what is stored', (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        perAppMode: PerAppMode.include,
        perAppPackages: const <String>[
          'org.mozilla.firefox',
          'org.telegram.messenger',
        ],
      ),
      dns: const DnsSettings(
        remote: 'tls://9.9.9.9',
        strategy: DnsStrategy.ipv4Only,
      ),
    );

    expect(find.text(t.routing.appsValue(count: 2)), findsOneWidget);
    expect(
      find.text(
        t.routing.dnsValue(
          remote: 'tls://9.9.9.9',
          strategy: DnsStrategy.ipv4Only.wireName,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Apps row says everything while per-app routing is off',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        perAppPackages: const <String>['org.mozilla.firefox'],
      ),
    );

    // The packages outlive the switch that selected them, by design — turning
    // per-app routing off must not throw the list away. The row still has to
    // report the tunnel as it is: every app in it, nothing chosen.
    expect(stored().perAppMode, PerAppMode.disabled);
    expect(find.text(t.routing.appsOff), findsOneWidget);
    expect(find.text(t.routing.appsValue(count: 1)), findsNothing);
  });

  testWidgets('the LAN switch writes through to the policy', (tester) async {
    await pumpScreen(tester);
    expect(stored().bypassLan, isTrue);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CommySwitch &&
            widget.semanticLabel == t.routing.bypassLan,
      ),
    );
    await tester.pumpAndSettle();

    // Rule R6 lives on this value: local traffic either leaves the tunnel or
    // it does not, and this switch is the only thing that says which.
    expect(stored().bypassLan, isFalse);
  });

  group('the states it owes the user', () {
    testWidgets('a policy on its way shows the shape of the answer',
        (tester) async {
      await pumpScreen(
        tester,
        settleFully: false,
        extra: <Override>[
          routingPolicyProvider.overrideWith(
            (ref) => const Stream<RoutingPolicy>.empty(),
          ),
        ],
      );

      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(SegmentedControl<RoutingMode>), findsNothing);
    });

    testWidgets(
        'a policy that cannot be read gives a cause, an action and the logs',
        (tester) async {
      await pumpScreen(
        tester,
        extra: <Override>[
          routingPolicyProvider.overrideWith(
            (ref) => Stream<RoutingPolicy>.error(
              const StorageFailure('the keystore refused'),
            ),
          ),
        ],
      );

      expect(find.text(t.error.storage.message), findsOneWidget);
      expect(
        find.widgetWithText(CommyButton, t.error.storage.action),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CommyButton, t.error.openLogs),
        findsOneWidget,
      );
      // Not the content: a screen that drew a policy it could not read as an
      // empty one would have the user editing rules that are not there.
      expect(find.byType(SegmentedControl<RoutingMode>), findsNothing);
    });
  });
}
