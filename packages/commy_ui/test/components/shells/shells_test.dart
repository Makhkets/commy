import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

void main() {
  useCommyGoldens();

  const destinations = <CommyDestination>[
    CommyDestination(icon: CommyIcons.server, label: 'Серверы'),
    CommyDestination(icon: CommyIcons.routing, label: 'Маршрутизация'),
    CommyDestination(icon: CommyIcons.diagnostics, label: 'Диагностика'),
  ];

  Widget scaffold({
    Widget? detail,
    ValueChanged<int>? onSelected,
  }) =>
      AdaptiveScaffold(
        destinations: destinations,
        selectedIndex: 1,
        onDestinationSelected: onSelected ?? (_) {},
        detail: detail,
        appBar: const CommyAppBar(title: 'Commy'),
        body: const SizedBox.expand(),
      );

  group('AdaptiveScaffold', () {
    testWidgets('picks the shell the width asks for', (tester) async {
      // Just under the first breakpoint.
      await pumpCommy(
        tester,
        size: const Size(599, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(TabletShell), findsNothing);

      // Exactly on it.
      await pumpCommy(
        tester,
        size: const Size(600, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.byType(TabletShell), findsOneWidget);

      // Just under the second one.
      await pumpCommy(
        tester,
        size: const Size(999, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.byType(TabletShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);

      // Exactly on it.
      await pumpCommy(
        tester,
        size: const Size(1000, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.byType(DesktopShell), findsOneWidget);
    });

    testWidgets('never puts a navigation bar at the bottom on mobile', (
      tester,
    ) async {
      // docs/04-design-system.md, "Навигация: нижнего меню нет". This is the
      // guard against somebody helpfully adding one back.
      await pumpCommy(
        tester,
        size: const Size(390, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      // Destinations exist, and the mobile shell still shows none of them.
      expect(find.text('Маршрутизация'), findsNothing);
    });

    testWidgets('names every section on desktop, none on the tablet rail', (
      tester,
    ) async {
      await pumpCommy(
        tester,
        size: const Size(1280, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.text('Маршрутизация'), findsOneWidget);

      await pumpCommy(
        tester,
        size: const Size(820, 800),
        padding: EdgeInsets.zero,
        child: scaffold(),
      );
      expect(find.text('Маршрутизация'), findsNothing);
      // The name is still carried, as the accessible label of the icon.
      expect(find.bySemanticsLabel('Маршрутизация'), findsOneWidget);
    });

    testWidgets('reports the section that was chosen', (tester) async {
      final chosen = <int>[];
      await pumpCommy(
        tester,
        size: const Size(1280, 800),
        padding: EdgeInsets.zero,
        child: scaffold(onSelected: chosen.add),
      );
      await tester.tap(find.text('Диагностика'));
      await tester.pump();
      expect(chosen, <int>[2]);
    });

    testWidgets('drops the detail pane rather than squeezing it', (
      tester,
    ) async {
      const detail = Key('detail');

      // 820 − 88 of rail leaves 732, comfortably two panes of 360.
      await pumpCommy(
        tester,
        size: const Size(820, 800),
        padding: EdgeInsets.zero,
        child: scaffold(detail: const SizedBox.expand(key: detail)),
      );
      expect(find.byKey(detail), findsOneWidget);

      // 640 − 88 leaves 552, which cannot hold two.
      await pumpCommy(
        tester,
        size: const Size(640, 800),
        padding: EdgeInsets.zero,
        child: scaffold(detail: const SizedBox.expand(key: detail)),
      );
      expect(find.byKey(detail), findsNothing);
    });
  });

  group('CommyAppBar', () {
    testWidgets('upper-cases the wordmark and centres it', (tester) async {
      await pumpCommy(
        tester,
        size: const Size(390, 120),
        padding: EdgeInsets.zero,
        child: CommyAppBar(
          title: 'Commy',
          leading: <Widget>[
            CommyIconButton(
              icon: CommyIcons.settings,
              onPressed: () {},
              semanticLabel: 'Настройки',
            ),
          ],
          actions: <Widget>[
            CommyIconButton(
              icon: CommyIcons.add,
              onPressed: () {},
              semanticLabel: 'Добавить',
            ),
          ],
        ),
      );
      expect(find.text('COMMY'), findsOneWidget);
      expect(
        tester.getCenter(find.text('COMMY')).dx,
        moreOrLessEquals(195, epsilon: 1),
      );
      expect(
        tester.getSize(find.byType(CommyAppBar)).height,
        CommySizes.appBarHeight,
      );
    });

    testWidgets('leads the section shape with a back arrow', (tester) async {
      var backs = 0;
      await pumpCommy(
        tester,
        size: const Size(390, 120),
        padding: EdgeInsets.zero,
        child: CommyAppBar.section(
          title: 'Настройки',
          onBack: () => backs++,
          backSemanticLabel: 'Назад',
        ),
      );
      expect(find.text('Настройки'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Назад'));
      await tester.pump();
      expect(backs, 1);
    });

    testWidgets('refuses a third control on either side', (tester) async {
      const filler = SizedBox.shrink();
      await pumpCommy(
        tester,
        size: const Size(390, 120),
        padding: EdgeInsets.zero,
        child: const CommyAppBar(
          title: 'Commy',
          actions: <Widget>[filler, filler, filler],
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());

      await pumpCommy(
        tester,
        size: const Size(390, 120),
        padding: EdgeInsets.zero,
        child: const CommyAppBar(
          title: 'Commy',
          leading: <Widget>[filler, filler, filler],
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    test('refuses a back arrow with nothing to announce', () {
      expect(
        () => CommyAppBar.section(title: 'Настройки', onBack: () {}),
        throwsAssertionError,
      );
    });
  });

  group('CommySheet', () {
    Widget opener() => Builder(
          builder: (context) => Center(
            child: CommyButton(
              label: 'Открыть',
              onPressed: () => CommySheet.show<void>(
                context: context,
                title: 'Добавить сервер',
                builder: (context) => const Text('содержимое'),
              ),
            ),
          ),
        );

    testWidgets('is a bottom sheet below the second breakpoint', (
      tester,
    ) async {
      await pumpCommy(
        tester,
        size: const Size(390, 800),
        padding: EdgeInsets.zero,
        child: opener(),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Добавить сервер'), findsOneWidget);
      expect(find.text('содержимое'), findsOneWidget);
      final surface = tester.widget<CommySheetSurface>(
        find.byType(CommySheetSurface),
      );
      expect(surface.isDialog, isFalse);
      // It is anchored to the bottom edge, not floating in the middle.
      expect(
        tester.getRect(find.byType(CommySheetSurface)).bottom,
        moreOrLessEquals(800, epsilon: 1),
      );
    });

    testWidgets('is a dialog above it, without the caller asking', (
      tester,
    ) async {
      await pumpCommy(
        tester,
        size: const Size(1280, 800),
        padding: EdgeInsets.zero,
        child: opener(),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Добавить сервер'), findsOneWidget);
      final surface = tester.widget<CommySheetSurface>(
        find.byType(CommySheetSurface),
      );
      expect(surface.isDialog, isTrue);
      final box = tester.getRect(find.byType(CommySheetSurface));
      expect(box.width, lessThanOrEqualTo(CommySizes.dialogMaxWidth));
      expect(box.center.dx, moreOrLessEquals(640, epsilon: 1));
    });
  });
}
