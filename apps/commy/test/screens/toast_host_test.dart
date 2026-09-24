import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/widgets/toast_host.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Toasts at the top of the window (the owner, 2026-09-24).
///
/// They were floating `SnackBar`s at the bottom, over the connect button and
/// the list the thumb is on. What moved is a promise about geometry and
/// touch as much as about looks, so these tests measure the toast rather
/// than photograph it: where it lands against the status bar, how long it
/// stays, how it leaves, and that the layer never takes a tap meant for the
/// screen underneath.
void main() {
  final t = Translations();

  late CommyTestHarness harness;
  setUp(() => harness = CommyTestHarness());
  tearDown(() => harness.dispose());

  /// How far down the system draws its status bar in these tests.
  const statusBar = 24.0;

  /// Stands a phone up — 390 × 844 with a status bar — and a screen that
  /// counts the taps that reach it.
  Future<({BuildContext context, List<Offset> taps})> pumpPhone(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);

    late BuildContext screen;
    final taps = <Offset>[];
    await tester.pumpWidget(
      harness.wrap(
        Builder(
          builder: (context) {
            screen = context;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => taps.add(details.globalPosition),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    await settle(tester);
    return (context: screen, taps: taps);
  }

  void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ToastMessenger.show(
      context,
      message: message,
      tone: CommyTone.info,
      icon: CommyIcons.info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// The toast's own surface — the decorated box, not the full-width `Align`
  /// around it.
  Rect surface(WidgetTester tester) => tester.getRect(
        find
            .descendant(
              of: find.byType(Toast),
              matching: find.byType(Container),
            )
            .first,
      );

  // 360 is the narrowest phone the layout is held to; 390 the common one.
  for (final width in <double>[360, 390]) {
    testWidgets(
        'lands at the top, under the status bar, not at the bottom · '
        '${width.toInt()} dp', (tester) async {
      final phone = await pumpPhone(tester, size: Size(width, 800));

      show(phone.context, t.diagnostics.copied);
      await tester.pumpAndSettle();

      final rect = surface(tester);
      expect(rect.top, greaterThanOrEqualTo(statusBar));
      expect(rect.bottom, lessThan(800 / 4));
      // Centred, inside the screen's own gutters.
      expect(rect.left, greaterThanOrEqualTo(CommySpacing.standard.s4));
      expect(rect.right, lessThanOrEqualTo(width - CommySpacing.standard.s4));
      expect(rect.center.dx, closeTo(width / 2, 1));
    });
  }

  testWidgets('is capped and centred on a wide window', (tester) async {
    final desktop = await pumpPhone(tester, size: const Size(1280, 800));

    show(desktop.context, t.diagnostics.copied);
    await tester.pumpAndSettle();

    final rect = surface(tester);
    expect(rect.width, lessThanOrEqualTo(CommySizes.toastMaxWidth));
    expect(rect.center.dx, closeTo(640, 1));
    expect(rect.top, greaterThanOrEqualTo(statusBar));
  });

  testWidgets('touches around the toast reach the screen underneath',
      (tester) async {
    final desktop = await pumpPhone(tester, size: const Size(1280, 800));
    show(desktop.context, t.diagnostics.copied);
    await tester.pumpAndSettle();
    final rect = surface(tester);

    // Beside the toast, level with it: inside the layer's box, outside the
    // toast's surface.
    await tester.tapAt(Offset(rect.left - 40, rect.center.dy));
    // Under the status bar, above the toast.
    await tester.tapAt(Offset(rect.center.dx, statusBar / 2));
    // Anywhere below.
    await tester.tapAt(const Offset(640, 600));
    expect(desktop.taps, hasLength(3));

    // The toast itself is the one thing the layer keeps.
    await tester.tapAt(rect.center);
    expect(desktop.taps, hasLength(3));
  });

  testWidgets('with nothing up, the layer takes no touch at all',
      (tester) async {
    final phone = await pumpPhone(tester);

    await tester.tapAt(const Offset(195, 50));

    expect(find.byType(Toast), findsNothing);
    expect(phone.taps, hasLength(1));
  });

  testWidgets('goes away on its own once its time is up', (tester) async {
    final phone = await pumpPhone(tester);

    show(phone.context, t.diagnostics.copied);
    await tester.pumpAndSettle();
    await tester.pump(ToastMessenger.duration - const Duration(seconds: 1));
    expect(find.byType(Toast), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Toast), findsNothing);
  });

  testWidgets('a replacement starts its own time, not the rest of the old one',
      (tester) async {
    final phone = await pumpPhone(tester);

    show(phone.context, t.diagnostics.copied);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    show(phone.context, t.common.done);
    await tester.pumpAndSettle();

    // Two seconds into the second toast: the first one's timer, had it been
    // left running, would have taken the second one down a second ago.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Toast), findsOneWidget);
    expect(tester.widget<Toast>(find.byType(Toast)).message, t.common.done);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Toast), findsNothing);
  });

  testWidgets('a swipe up puts it away early', (tester) async {
    final phone = await pumpPhone(tester);
    show(phone.context, t.diagnostics.copied);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Toast), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(find.byType(Toast), findsNothing);
    // And its timer went with it: nothing fires later into an empty layer.
    await tester.pump(ToastMessenger.duration);
    expect(find.byType(Toast), findsNothing);
  });

  testWidgets('a swipe down does not', (tester) async {
    final phone = await pumpPhone(tester);
    show(phone.context, t.diagnostics.copied);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Toast), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(find.byType(Toast), findsOneWidget);
  });

  testWidgets('the action takes the toast down, then runs, and waits longer',
      (tester) async {
    final phone = await pumpPhone(tester);
    var undone = 0;
    show(
      phone.context,
      t.diagnostics.copied,
      actionLabel: t.common.done,
      onAction: () => undone++,
    );
    await tester.pumpAndSettle();

    // Past a plain toast's time, inside an actionable one's.
    await tester.pump(ToastMessenger.duration);
    expect(find.byType(Toast), findsOneWidget);

    await tester.tap(find.text(t.common.done));
    await tester.pumpAndSettle();

    expect(undone, 1);
    expect(find.byType(Toast), findsNothing);
  });

  group('with a screen reader driving the device', () {
    /// The phone, with the reader switched on before the app reads its
    /// first `MediaQuery`.
    Future<({BuildContext context, List<Offset> taps})> pumpReader(
      WidgetTester tester,
    ) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      return pumpPhone(tester);
    }

    testWidgets('a toast with an action waits to be answered', (tester) async {
      // Six seconds is not long enough to find the action by exploring the
      // screen, which is why Material keeps a snack bar with an action up
      // under a screen reader.
      final phone = await pumpReader(tester);
      show(
        phone.context,
        t.diagnostics.copied,
        actionLabel: t.common.done,
        onAction: () {},
      );
      await tester.pumpAndSettle();

      await tester.pump(ToastMessenger.actionDuration * 3);
      await tester.pumpAndSettle();
      expect(find.byType(Toast), findsOneWidget);

      // Still dismissible the way a reader dismisses things.
      final dismissible = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byType(Toast),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.onDismiss != null,
              ),
            )
            .first,
      );
      dismissible.properties.onDismiss?.call();
      await tester.pumpAndSettle();
      expect(find.byType(Toast), findsNothing);
    });

    testWidgets('a toast with nothing to answer goes on its own',
        (tester) async {
      final phone = await pumpReader(tester);
      show(phone.context, t.diagnostics.copied);
      await tester.pumpAndSettle();

      await tester.pump(ToastMessenger.duration);
      await tester.pumpAndSettle();
      expect(find.byType(Toast), findsNothing);
    });
  });

  testWidgets('is announced the way a snack bar was', (tester) async {
    final phone = await pumpPhone(tester);
    show(phone.context, t.diagnostics.copied);
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byType(Toast),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.liveRegion ?? false) &&
              widget.properties.onDismiss != null,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('with reduced motion it is simply there, in one frame',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final phone = await pumpPhone(tester);

    show(phone.context, t.diagnostics.copied);
    await tester.pump();

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(Toast),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a toast raised from a sheet outlives the sheet', (tester) async {
    // Copying a link closes the menu that asked; the confirmation must not
    // close with it.
    final phone = await pumpPhone(tester);
    late BuildContext sheet;
    unawaited(
      Navigator.of(phone.context).push(
        MaterialPageRoute<void>(
          builder: (context) {
            sheet = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    show(sheet, t.subscription.linkCopied);
    Navigator.of(sheet).pop();
    await tester.pumpAndSettle();

    expect(find.text(t.subscription.linkCopied), findsOneWidget);
  });

  testWidgets('with no host above it, showing a toast is not a crash',
      (tester) async {
    // The documented contract: a bare widget tree may call this and must
    // survive it.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            expect(ToastHost.maybeOf(context), isNull);
            show(context, t.diagnostics.copied);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Toast), findsNothing);
  });
}
