import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/settings/rule_sets_screen.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #13, exception E-2.
///
/// The assertions that matter are about *when a request happens*: opening the
/// screen must not make one, pressing Download must, and clearing the source
/// must take the ability away. Everything else here is presentation.
void main() {
  final t = Translations();

  RoutingRule rule(String matcher) => RoutingRule(
        id: matcher,
        matcher: matcher,
        action: RuleAction.direct,
      );

  late CommyTestHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<RoutingRule> rules = const <RoutingRule>[],
    List<RuleSet> onDisk = const <RuleSet>[],
    String? source,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(
      settings: source == null
          ? AppSettings.defaults
          : AppSettings.defaults.copyWith(ruleSetSource: source),
    );
    await harness.routingRepository.write(
      RoutingPolicy.defaults.copyWith(mode: RoutingMode.rules, rules: rules),
    );
    for (final set in onDisk) {
      await harness.ruleSetRepository.download(
        tag: set.tag,
        from: Uri.parse('https://seeded.example/${set.tag}'),
      );
    }
    harness.ruleSetRepository.requests.clear();

    await tester.pumpWidget(harness.wrap(const RuleSetsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('opening the screen asks nobody for anything', (tester) async {
    await pumpScreen(tester, rules: <RoutingRule>[rule('geosite:ru')]);

    // The whole of E-2: the request happens on a press and at no other time.
    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  testWidgets('the address that will be asked is shown before it is',
      (tester) async {
    await pumpScreen(tester, rules: <RoutingRule>[rule('geosite:ru')]);

    expect(find.text(AppSettings.defaultRuleSetSource), findsOneWidget);
    expect(find.text(t.ruleSets.intro), findsOneWidget);
  });

  testWidgets('it offers the tags the rules name, not a catalogue',
      (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[
        rule('geosite:ru'),
        rule('geoip:ru'),
        // Needs no file: `geoip:private` is the one value the matcher turns
        // into `ip_is_private` rather than a downloadable set.
        rule('geoip:private'),
        rule('domain:example.com'),
      ],
    );

    expect(find.text('geosite-ru'), findsOneWidget);
    expect(find.text('geoip-ru'), findsOneWidget);
    expect(find.text('geoip-private'), findsNothing);
    expect(find.text(t.ruleSets.missing), findsNWidgets(2));
  });

  testWidgets('rules that need no list say so', (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[rule('domain:example.com')],
    );

    expect(find.text(t.ruleSets.noneNeeded), findsOneWidget);
    expect(find.text(t.ruleSets.noneNeededBody), findsOneWidget);
  });

  testWidgets('Download fetches from the configured source and says so',
      (tester) async {
    await pumpScreen(tester, rules: <RoutingRule>[rule('geosite:ru')]);

    await tester.tap(find.text(t.ruleSets.download));
    await tester.pumpAndSettle();

    expect(
      harness.ruleSetRepository.requests.single.toString(),
      AppSettings.defaultRuleSetSource.replaceAll('{tag}', 'geosite-ru'),
    );
    expect(harness.ruleSetRepository.sets.single.tag, 'geosite-ru');
    expect(find.text(t.ruleSets.downloaded(tag: 'geosite-ru')), findsOneWidget);
  });

  testWidgets('a set already here offers an update instead', (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[rule('geosite:ru')],
      onDisk: <RuleSet>[
        RuleSet(
          tag: 'geosite-ru',
          sizeBytes: 1024,
          updatedAt: CommyTestHarness.now,
        ),
      ],
    );

    expect(find.text(t.ruleSets.update), findsOneWidget);
    expect(find.text(t.ruleSets.download), findsNothing);
    expect(find.text(t.ruleSets.missing), findsNothing);
  });

  testWidgets('clearing the source takes the ability to ask away',
      (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[rule('geosite:ru')],
      source: '',
    );

    expect(find.text(t.ruleSets.sourceOff), findsOneWidget);
    final button = tester.widget<CommyButton>(
      find.widgetWithText(CommyButton, t.ruleSets.download),
    );
    // Disabled, not merely unused: a user who wants the request to be
    // impossible gets that, not a promise that we will not make it.
    expect(button.onPressed, isNull);
  });

  testWidgets('a failed download stores nothing and says nothing succeeded',
      (tester) async {
    await pumpScreen(tester, rules: <RoutingRule>[rule('geosite:ru')]);
    harness.ruleSetRepository.failure = SubscriptionUnreachableFailure(
      url: Uri.parse('https://mirror.example/geosite-ru.srs'),
      cause: 'the mirror did not answer',
    );

    await tester.tap(find.text(t.ruleSets.download));
    await tester.pumpAndSettle();

    expect(harness.ruleSetRepository.sets, isEmpty);
    expect(find.text(t.ruleSets.downloaded(tag: 'geosite-ru')), findsNothing);
  });

  testWidgets('a set nothing references is listed apart, with a way out',
      (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[rule('geosite:ru')],
      onDisk: <RuleSet>[
        RuleSet(
          tag: 'geosite-netflix',
          sizeBytes: 2048,
          updatedAt: CommyTestHarness.now,
        ),
      ],
    );

    expect(find.text('geosite-netflix'), findsOneWidget);
    expect(find.textContaining(t.ruleSets.unused), findsOneWidget);
  });

  testWidgets('deleting asks first, and keeps the rule that named it',
      (tester) async {
    await pumpScreen(
      tester,
      rules: <RoutingRule>[rule('geosite:ru')],
      onDisk: <RuleSet>[
        RuleSet(
          tag: 'geosite-ru',
          sizeBytes: 1024,
          updatedAt: CommyTestHarness.now,
        ),
      ],
    );

    await tester.tap(find.byIcon(CommyIcons.delete).first);
    await tester.pumpAndSettle();
    expect(find.text(t.ruleSets.deleteConfirm.title), findsOneWidget);

    await tester.tap(find.text(t.ruleSets.deleteConfirm.confirm));
    await tester.pumpAndSettle();

    expect(harness.ruleSetRepository.sets, isEmpty);
    // The rule stays: deleting a file is not deleting what the user wrote.
    expect(harness.routingRepository.policy.rules, hasLength(1));
    expect(find.text(t.ruleSets.missing), findsOneWidget);
  });
}
