import 'dart:async';
import 'dart:io';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/failure_view.dart';
import 'package:commy/src/widgets/notice_host.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The five widgets every screen leans on and nothing tested.
///
/// They are shared, so a regression in any of them is a regression in a dozen
/// screens at once, and each of them owns a promise docs/05-ux-flows.md makes:
///
/// * `FailureView` is the only place the shape that document asks for — a
///   cause in plain language, an action, and a way to the logs — is spelled
///   out, and `FailureText` is the only place a failure turns into words. A
///   variant that fell out of that mapping would ship as a blank screen with
///   a button on it, or as a button that goes somewhere else.
/// * `AsyncSection` owns three of the four mandatory states, including the
///   rule that a refresh keeps the content instead of flashing a skeleton.
/// * `SettingsTile` without a handler has to look inert — a row that drew a
///   chevron and swallowed the tap was a real bug — and `SettingsSection`
///   draws the seams between rows that every settings screen is made of.
/// * `ToastMessenger` and `NoticeHost` are what turned a pile of results
///   written to state and read by nobody into something the user sees.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  setUp(() => harness = CommyTestHarness());
  tearDown(() => harness.dispose());

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget child, {
    List<Override> extra = const <Override>[],
  }) async {
    await tester.pumpWidget(harness.wrap(child, extra: extra));
    await settle(tester);
  }

  /// Lets the snack bar's own three-second timer run out.
  ///
  /// Without it the toast is still up when the tree is torn down, and the
  /// pending timer fails the test rather than the widget.
  Future<void> expireToast(WidgetTester tester) async {
    await tester.pump(ToastMessenger.duration);
    await tester.pumpAndSettle();
  }

  group('FailureView', () {
    final failures = <({
      String code,
      CommyFailure failure,
      String message,
      String actionLabel,
      FailureAction action,
      bool hasLogLink,
    })>[
      (
        code: 'subscription_unreachable',
        failure: CommyFailure.subscriptionUnreachable(
          url: Uri.parse('https://panel.example.net/sub/token'),
          cause: 'connection refused',
        ),
        message: t.error.subscriptionUnreachable.message,
        actionLabel: t.error.subscriptionUnreachable.action,
        action: FailureAction.retry,
        hasLogLink: true,
      ),
      (
        code: 'subscription_malformed',
        failure: const CommyFailure.subscriptionMalformed('not base64'),
        message: t.error.subscriptionMalformed.message,
        actionLabel: t.error.subscriptionMalformed.action,
        action: FailureAction.openLogs,
        hasLogLink: false,
      ),
      (
        code: 'unsupported_protocol',
        failure: const CommyFailure.unsupportedProtocol('sstp'),
        message: t.error.unsupportedProtocol.message(scheme: 'sstp'),
        actionLabel: t.error.unsupportedProtocol.action,
        action: FailureAction.openLogs,
        hasLogLink: false,
      ),
      (
        code: 'config_invalid',
        failure: const CommyFailure.configInvalid('no outbound'),
        message: t.error.configInvalid.message,
        actionLabel: t.error.configInvalid.action,
        action: FailureAction.openConfig,
        hasLogLink: true,
      ),
      (
        code: 'permission_denied',
        failure: const CommyFailure.permissionDenied(),
        message: t.error.permissionDenied.message,
        actionLabel: t.error.permissionDenied.action,
        action: FailureAction.retry,
        hasLogLink: true,
      ),
      (
        code: 'helper_unavailable',
        failure: const CommyFailure.helperUnavailable(),
        message: t.error.helperUnavailable.message,
        actionLabel: t.error.helperUnavailable.action,
        action: FailureAction.retry,
        hasLogLink: true,
      ),
      (
        code: 'core_crashed',
        failure: const CommyFailure.coreCrashed('panic: nil map'),
        message: t.error.coreCrashed.message,
        actionLabel: t.error.coreCrashed.action,
        action: FailureAction.openLogs,
        hasLogLink: false,
      ),
      (
        code: 'storage',
        failure: const CommyFailure.storage('disk full'),
        message: t.error.storage.message,
        actionLabel: t.error.storage.action,
        action: FailureAction.retry,
        hasLogLink: true,
      ),
      (
        code: 'unknown',
        failure: const CommyFailure.unknown('boom', StackTrace.empty),
        message: t.error.unknown.message,
        actionLabel: t.error.unknown.action,
        action: FailureAction.openLogs,
        hasLogLink: false,
      ),
    ];

    for (final entry in failures) {
      testWidgets('${entry.code} gets a cause, an action and the logs',
          (tester) async {
        await pumpScreen(tester, FailureView(failure: entry.failure));

        // The failure's own stable code is what the translation is keyed to;
        // asserting it here ties the row of this table to the variant.
        expect(entry.failure.code, entry.code);

        final empty = tester.widget<EmptyState>(find.byType(EmptyState));
        expect(empty.title, t.error.title);
        // Read off the widget rather than through `find.text`: the unknown
        // failure's sentence is the same string as the headline, and a
        // finder would happily pass on the headline alone.
        expect(empty.message, entry.message);
        expect(empty.message?.trim(), isNotEmpty);

        final buttons =
            tester.widgetList<CommyButton>(find.byType(CommyButton)).toList();
        expect(buttons.first.label, entry.actionLabel);
        expect(buttons.first.label.trim(), isNotEmpty);
        // Two buttons when the primary action retries or opens the config,
        // one when it already lands in the logs — the same screen twice is
        // noise, the logs missing entirely is an unfinished error.
        expect(buttons, hasLength(entry.hasLogLink ? 2 : 1));
        if (entry.hasLogLink) {
          expect(buttons.last.label, t.error.openLogs);
          expect(buttons.last.variant, CommyButtonVariant.ghost);
        }
      });
    }

    testWidgets('a file that could not be read says so, and offers a re-pick',
        (tester) async {
      // The pick worked and the read threw, which the import path wraps in an
      // `unknown` failure. Rendered as "something went wrong" it sent the one
      // user who could have fixed it on the spot to the log tab; the sentence
      // for it had been sitting in both locales, used nowhere.
      await pumpScreen(
        tester,
        const FailureView(
          failure: CommyFailure.unknown(
            FileSystemException('no such file'),
            StackTrace.empty,
          ),
        ),
      );

      final empty = tester.widget<EmptyState>(find.byType(EmptyState));
      expect(empty.message, t.import.file.unreadable);
      expect(
        tester
            .widgetList<CommyButton>(find.byType(CommyButton))
            .map((button) => button.label),
        <String>[t.common.retry, t.error.openLogs],
      );
    });

    test('the unreadable-file sentence is a sentence in both languages',
        () async {
      // Same guard as the table's own both-languages loop: a key that only
      // exists in `ru` renders as an empty banner in `en`.
      const failure = CommyFailure.unknown(
        FileSystemException('no such file'),
        StackTrace.empty,
      );
      for (final locale in AppLocale.values) {
        final strings = await locale.build();
        final text = FailureText.of(failure, strings);
        expect(
          text.message.trim(),
          isNotEmpty,
          reason: 'unreadable file has no sentence in ${locale.languageCode}',
        );
        expect(
          text.message,
          isNot(strings.error.unknown.message),
          reason: 'unreadable file fell back to the generic sentence',
        );
        expect(text.actionLabel.trim(), isNotEmpty);
      }
    });

    testWidgets('the primary action retries in place when it has no route',
        (tester) async {
      var retries = 0;
      await pumpScreen(
        tester,
        FailureView(
          failure: const CommyFailure.permissionDenied(),
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text(t.error.permissionDenied.action));
      await settle(tester);

      expect(retries, 1);
    });

    testWidgets('a primary action with a route goes there instead of retrying',
        (tester) async {
      // `configInvalid` is the one failure whose button lands on the
      // generated config rather than on the logs. An `_act` that lost the
      // route branch would quietly call `onRetry` here — rebuilding the same
      // broken configuration — and every other test in this group would
      // still pass.
      var retries = 0;
      await pumpScreen(
        tester,
        FailureView(
          failure: const CommyFailure.configInvalid('no outbound'),
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text(t.error.configInvalid.action));
      await settle(tester);

      expect(retries, 0);
      // The harness stands no router up, so the attempt is what is visible.
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('GoRouter'),
        ),
        reason: '${AppRoutes.diagnosticsConfig} has to be handed over',
      );
    });

    test('every failure says something in both languages', () async {
      // A missing key renders as an empty string rather than as a crash, so
      // the only thing standing between a forgotten translation and a blank
      // error screen is this loop. `build` rather than `buildSync`: the
      // English bundle is a deferred library, exactly as the app loads it.
      for (final locale in AppLocale.values) {
        final strings = await locale.build();
        for (final entry in failures) {
          final text = FailureText.of(entry.failure, strings);
          expect(
            text.message.trim(),
            isNotEmpty,
            reason: '${entry.code} has no message in ${locale.languageCode}',
          );
          expect(
            text.actionLabel.trim(),
            isNotEmpty,
            reason: '${entry.code} has no action in ${locale.languageCode}',
          );
        }
      }
    });

    test('every failure points its button at the right place', () {
      // The button count above separates "opens the logs" from the other
      // two, and nothing else does: a mapping that turned the VPN permission
      // prompt into a jump to the config tab would keep the same label, the
      // same sentence and the same two buttons, and simply stop asking for
      // the permission.
      for (final entry in failures) {
        expect(
          FailureText.of(entry.failure, t).action,
          entry.action,
          reason: '${entry.code} sends its button somewhere else',
        );
      }
    });

    test('the routes an error action offers are real tabs', () {
      // A button that navigates to a path the router does not serve leaves
      // the user exactly where they were, which is worse than no button.
      expect(FailureAction.retry.route, isNull);
      expect(FailureAction.openLogs.route, AppRoutes.diagnosticsLogs);
      expect(FailureAction.openConfig.route, AppRoutes.diagnosticsConfig);
      expect(
        <String?>[
          FailureAction.openLogs.route,
          FailureAction.openConfig.route,
        ],
        everyElement(isIn(AppRoutes.diagnosticsTabs)),
      );
    });
  });

  group('FailureBanner', () {
    testWidgets('keeps the cause, the action and the way to the logs',
        (tester) async {
      var retries = 0;
      await pumpScreen(
        tester,
        FailureBanner(
          failure: const CommyFailure.helperUnavailable(),
          onRetry: () => retries++,
        ),
      );

      final banner = tester.widget<ErrorBanner>(find.byType(ErrorBanner));
      expect(banner.message, t.error.helperUnavailable.message);
      expect(banner.actionLabel, t.error.helperUnavailable.action);
      // The banner sits over content that is still usable, so the quiet link
      // to the logs is the only route out of it.
      expect(find.text(t.error.openLogs), findsOneWidget);

      await tester.tap(find.text(t.error.helperUnavailable.action));
      await settle(tester);

      expect(retries, 1);
    });

    testWidgets('can be dismissed only when someone is listening',
        (tester) async {
      await pumpScreen(
        tester,
        const FailureBanner(failure: CommyFailure.permissionDenied()),
      );
      expect(find.byIcon(CommyIcons.close), findsNothing);

      var dismissals = 0;
      await pumpScreen(
        tester,
        FailureBanner(
          failure: const CommyFailure.permissionDenied(),
          onDismiss: () => dismissals++,
        ),
      );

      await tester.tap(find.byIcon(CommyIcons.close));
      await settle(tester);

      expect(dismissals, 1);
    });

    testWidgets('an action that is already a route does not offer the logs',
        (tester) async {
      // `_act` is a second copy of the same three lines the full-screen view
      // has, so it can rot on its own. A crashed core is the case where the
      // action is the log route: one button, and it has to navigate rather
      // than retry a core that just died.
      var retries = 0;
      await pumpScreen(
        tester,
        FailureBanner(
          failure: const CommyFailure.coreCrashed('panic: nil map'),
          onRetry: () => retries++,
        ),
      );

      // The ghost link is the only `CommyButton` this banner ever adds, so
      // its absence is the assertion — the primary action here is worded
      // "open the logs" itself, and a second one saying the same words is
      // exactly what `needsLogRoute` exists to prevent.
      expect(find.byType(CommyButton), findsNothing);
      expect(find.text(t.error.coreCrashed.action), findsOneWidget);

      await tester.tap(find.text(t.error.coreCrashed.action));
      await settle(tester);

      expect(retries, 0);
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('GoRouter'),
        ),
        reason: '${AppRoutes.diagnosticsLogs} has to be handed over',
      );
    });
  });

  group('AsyncSection', () {
    Widget section(
      AsyncValue<String> value, {
      VoidCallback? onRetry,
    }) {
      return AsyncSection<String>(
        value: value,
        skeleton: const Text(_skeletonMarker),
        onRetry: onRetry,
        builder: (context, data) => Text(data),
      );
    }

    testWidgets('shows the shape of the answer while it loads', (tester) async {
      await pumpScreen(tester, section(const AsyncLoading<String>()));

      expect(find.text(_skeletonMarker), findsOneWidget);
      expect(find.text(_contentMarker), findsNothing);
    });

    testWidgets('shows the content once there is some', (tester) async {
      await pumpScreen(
        tester,
        section(const AsyncData<String>(_contentMarker)),
      );

      expect(find.text(_contentMarker), findsOneWidget);
      expect(find.text(_skeletonMarker), findsNothing);
    });

    testWidgets('a refresh keeps the content instead of flashing a skeleton',
        (tester) async {
      // Through a real provider rather than a hand-built `AsyncValue`: the
      // refreshing state is Riverpod's to produce, and the point is that this
      // section reads it the way Riverpod hands it over.
      final answers = <Completer<String>>[];
      final source = FutureProvider<String>((ref) {
        final answer = Completer<String>();
        answers.add(answer);
        return answer.future;
      });
      late WidgetRef sectionRef;

      await pumpScreen(
        tester,
        Consumer(
          builder: (context, ref, child) {
            sectionRef = ref;
            return section(ref.watch(source));
          },
        ),
      );
      expect(find.text(_skeletonMarker), findsOneWidget);

      answers.single.complete(_contentMarker);
      await settle(tester);
      expect(find.text(_contentMarker), findsOneWidget);

      sectionRef.invalidate(source);
      await settle(tester);

      // Every one of these sections sits on a stream that re-emits: a
      // skeleton on each refresh would make the connections tab strobe.
      expect(find.text(_contentMarker), findsOneWidget);
      expect(find.text(_skeletonMarker), findsNothing);

      answers.last.complete(_contentMarker);
      await settle(tester);
    });

    testWidgets('an error keeps the typed failure rather than flattening it',
        (tester) async {
      // The core throws `CoreClientException`, Riverpod hands the section
      // whatever was thrown, and only `failureOf` knows how to get the
      // classified failure back out. Without it every failure on every
      // screen would read as the catch-all "something went wrong".
      await pumpScreen(
        tester,
        section(
          const AsyncError<String>(
            CoreClientException(CommyFailure.permissionDenied()),
            StackTrace.empty,
          ),
        ),
      );

      final empty = tester.widget<EmptyState>(find.byType(EmptyState));
      expect(empty.message, t.error.permissionDenied.message);
      expect(find.text(_skeletonMarker), findsNothing);
    });

    testWidgets('the error state retries what produced it', (tester) async {
      var retries = 0;
      await pumpScreen(
        tester,
        section(
          const AsyncError<String>(
            CoreClientException(CommyFailure.helperUnavailable()),
            StackTrace.empty,
          ),
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text(t.error.helperUnavailable.action));
      await settle(tester);

      expect(retries, 1);
    });

    testWidgets('the list skeleton clips instead of overflowing',
        (tester) async {
      // A placeholder that throws a layout error on a short screen is worse
      // than the blank it stands in for.
      await pumpScreen(
        tester,
        const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(height: 60, child: ListSkeleton(rows: 12)),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CommySkeleton), findsWidgets);
    });
  });

  group('SettingsTile', () {
    testWidgets('a row with no handler is inert and draws no chevron',
        (tester) async {
      await pumpScreen(
        tester,
        const SettingsTile(title: _tileTitle, subtitle: '1.4.0'),
      );

      // The chevron is the promise that something happens; an inert row that
      // draws one is a row the user taps and taps.
      expect(find.byIcon(CommyIcons.chevronRight), findsNothing);
      expect(find.byType(InkWell), findsNothing);

      await tester.tap(find.text(_tileTitle));
      await settle(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('a row with a handler draws the chevron and fires it',
        (tester) async {
      var taps = 0;
      await pumpScreen(
        tester,
        SettingsTile(title: _tileTitle, value: '7', onTap: () => taps++),
      );

      expect(find.byIcon(CommyIcons.chevronRight), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      await tester.tap(find.text(_tileTitle));
      await settle(tester);

      expect(taps, 1);
    });

    testWidgets('a row that ends in a control keeps the chevron off',
        (tester) async {
      await pumpScreen(
        tester,
        SettingsTile(
          title: _tileTitle,
          trailing: CommySwitch(value: true, onChanged: (_) {}),
          onTap: () {},
        ),
      );

      // Two trailing things at once is what the designs never do: the switch
      // is the control, and a chevron beside it points nowhere.
      expect(find.byType(CommySwitch), findsOneWidget);
      expect(find.byIcon(CommyIcons.chevronRight), findsNothing);
    });
  });

  group('SettingsSection', () {
    testWidgets('names the group in caps and rules only between the rows',
        (tester) async {
      await pumpScreen(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SectionLabel(_groupLabel),
            SettingsSection(
              children: <Widget>[
                SettingsTile(title: _tileTitle),
                SettingsTile(title: _secondTileTitle),
                SettingsTile(title: _thirdTileTitle),
              ],
            ),
          ],
        ),
      );

      // Every caller passes the heading in sentence case; the uppercase run
      // in docs/design-refs/08-settings.png is this widget's doing, and a
      // screen that had to shout its own headings would drift within a
      // release.
      expect(find.text(_groupLabel.toUpperCase()), findsOneWidget);
      expect(find.text(_groupLabel), findsNothing);
      // One rule between each pair and none at either end: a seam under the
      // last row is what makes a card look unfinished.
      expect(find.byType(CommyDivider), findsNWidgets(2));
    });
  });

  group('ToastMessenger', () {
    testWidgets('a result posted from a screen reaches the user',
        (tester) async {
      await pumpScreen(
        tester,
        AdaptiveScaffold(
          body: Builder(
            builder: (context) => CommyButton(
              label: _tileTitle,
              onPressed: () => ToastMessenger.show(
                context,
                message: t.diagnostics.copied,
                tone: CommyTone.connected,
                icon: CommyIcons.success,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text(_tileTitle));
      await tester.pumpAndSettle();

      final toast = tester.widget<Toast>(find.byType(Toast));
      expect(toast.message, t.diagnostics.copied);
      expect(toast.tone, CommyTone.connected);
      expect(toast.icon, CommyIcons.success);

      await expireToast(tester);
    });

    testWidgets('a second result replaces the first instead of queueing',
        (tester) async {
      late BuildContext hostContext;
      await pumpScreen(
        tester,
        AdaptiveScaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      void show(String message) => ToastMessenger.show(
            hostContext,
            message: message,
            tone: CommyTone.info,
            icon: CommyIcons.info,
          );

      show(t.diagnostics.copied);
      await tester.pumpAndSettle();
      show(t.common.done);
      await tester.pumpAndSettle();

      // Queued, the second result would wait three seconds behind the first
      // and land after the user had moved on.
      expect(find.byType(Toast), findsOneWidget);
      expect(
        tester.widget<Toast>(find.byType(Toast)).message,
        t.common.done,
      );

      await expireToast(tester);
    });

    testWidgets('a widget with no messenger above it is not a crash',
        (tester) async {
      // Deliberately outside the harness: the documented contract is that a
      // bare widget tree may call this and must survive it.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ToastMessenger.show(
                context,
                message: t.diagnostics.copied,
                tone: CommyTone.info,
                icon: CommyIcons.info,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Toast), findsNothing);
    });
  });

  group('NoticeHost', () {
    late _NoticeStub tunnel;
    late _MeasurementStub measurement;

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        harness.wrap(
          NoticeHost(
            child: AdaptiveScaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  tunnel = ref.read(tunnelControllerProvider.notifier)
                      as _NoticeStub;
                  measurement = ref.read(measurementProvider.notifier)
                      as _MeasurementStub;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          extra: <Override>[
            tunnelControllerProvider.overrideWith(_NoticeStub.new),
            measurementProvider.overrideWith(_MeasurementStub.new),
          ],
        ),
      );
      await settle(tester);
    }

    final notices = <({
      String name,
      TunnelNotice notice,
      String message,
      CommyTone tone,
      IconData icon,
    })>[
      (
        name: 'a passed check',
        notice: const TunnelNotice(
          TunnelNoticeKind.checkPassed,
          milliseconds: 48,
        ),
        message: t.home.checkOk(ms: 48),
        tone: CommyTone.connected,
        icon: CommyIcons.success,
      ),
      (
        name: 'a passed check that also found the exit address',
        notice: const TunnelNotice(
          TunnelNoticeKind.checkPassed,
          milliseconds: 48,
          name: '203.0.113.7',
        ),
        message: t.home.checkOkWithIp(ms: 48, ip: '203.0.113.7'),
        tone: CommyTone.connected,
        icon: CommyIcons.success,
      ),
      (
        name: 'a failed check',
        notice: const TunnelNotice(TunnelNoticeKind.checkFailed),
        message: t.home.checkFailed,
        tone: CommyTone.error,
        icon: CommyIcons.warning,
      ),
      (
        name: 'a check whose address lookup went unanswered',
        notice: const TunnelNotice(
          TunnelNoticeKind.ipCheckFailed,
          milliseconds: 48,
        ),
        message: t.home.ipCheckFailed(ms: 48),
        tone: CommyTone.error,
        icon: CommyIcons.warning,
      ),
      (
        name: 'a switch to another server',
        notice: const TunnelNotice(
          TunnelNoticeKind.switched,
          name: 'Amsterdam 03',
        ),
        message: t.home.switched(name: 'Amsterdam 03'),
        tone: CommyTone.info,
        icon: CommyIcons.proxy,
      ),
      (
        name: 'a switch back to Auto',
        notice: const TunnelNotice(TunnelNoticeKind.switchedToAuto),
        message: t.home.switchedToAuto,
        tone: CommyTone.info,
        icon: CommyIcons.proxy,
      ),
      (
        name: 'a configuration applied to the running core',
        notice: const TunnelNotice(TunnelNoticeKind.reloaded),
        message: t.home.settingsApplied,
        tone: CommyTone.info,
        icon: CommyIcons.refresh,
      ),
    ];

    for (final entry in notices) {
      testWidgets('${entry.name} reaches the user in words', (tester) async {
        await pumpHost(tester);

        tunnel.post(entry.notice);
        await tester.pumpAndSettle();

        final toast = tester.widget<Toast>(find.byType(Toast));
        expect(toast.message, entry.message);
        expect(toast.tone, entry.tone);
        // Tone alone does not separate a switch from a reload: both are
        // `info`, and the glyph is what says which of the two just happened.
        expect(toast.icon, entry.icon);

        await expireToast(tester);
      });
    }

    testWidgets('a notice is shown once and then dropped', (tester) async {
      await pumpHost(tester);

      tunnel.post(const TunnelNotice(TunnelNoticeKind.reloaded));
      await tester.pumpAndSettle();
      expect(find.byType(Toast), findsOneWidget);
      await expireToast(tester);

      // Cleared by the host, so the next unrelated rebuild does not put the
      // same sentence back on screen.
      expect(tunnel.state.notice, isNull);

      tunnel.state = tunnel.state.copyWith(isBusy: true);
      await tester.pumpAndSettle();

      expect(find.byType(Toast), findsNothing);
    });

    testWidgets('a latency run that failed says so', (tester) async {
      // A run of probes has no screen of its own to fail on: the progress row
      // is gone by the time the last one comes back.
      await pumpHost(tester);

      measurement.post(const CommyFailure.configInvalid('no probe url'));
      await tester.pumpAndSettle();

      final toast = tester.widget<Toast>(find.byType(Toast));
      expect(toast.message, t.error.configInvalid.message);
      expect(toast.tone, CommyTone.error);
      expect(toast.icon, CommyIcons.warning);
      // Cleared, or the next unrelated rebuild says it again.
      expect(measurement.state.failure, isNull);

      await expireToast(tester);
    });
  });
}

/// Stands in for a skeleton, so the state can be told apart from the content.
const String _skeletonMarker = 'skeleton';

/// Stands in for the content an `AsyncSection` builds.
const String _contentMarker = 'content';

/// A row title, short enough to tap by its text.
const String _tileTitle = 'Version';

/// A second row, so a section has a seam to draw.
const String _secondTileTitle = 'Core';

/// A third row, so "one rule per row" and "one rule between rows" differ.
const String _thirdTileTitle = 'Licences';

/// A group heading, given the way every screen gives one: in sentence case.
const String _groupLabel = 'Connection';

/// A tunnel controller a test can write a notice to.
///
/// The real one only ever produces notices at the end of a long flow — a
/// connect, a switch, a probe — and this widget's job is what happens after
/// that, for all seven of them.
class _NoticeStub extends TunnelController {
  /// Writes [notice] the way a finished action would.
  void post(TunnelNotice notice) => state = state.copyWith(notice: notice);
}

/// A measurement controller a test can fail on demand.
class _MeasurementStub extends MeasurementController {
  /// Writes [failure] the way a finished run would.
  void post(CommyFailure failure) => state = MeasurementState(failure: failure);
}
