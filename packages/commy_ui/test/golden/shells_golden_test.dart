import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

import '../support/commy_test_host.dart';

/// Goldens of the shells, at the widths that actually pick them.
///
/// The three sizes below are not decoration: 390 is the phone the mockups were
/// drawn at, 820 sits between the breakpoints, and 1280 is past the second
/// one. If `AdaptiveScaffold` ever stops switching at 600 and 1000, one of
/// these three frames changes shape and the diff says so immediately.
void main() {
  useCommyGoldens();

  const destinations = <CommyDestination>[
    CommyDestination(icon: CommyIcons.server, label: 'Серверы'),
    CommyDestination(icon: CommyIcons.routing, label: 'Маршрутизация'),
    CommyDestination(icon: CommyIcons.diagnostics, label: 'Диагностика'),
    CommyDestination(icon: CommyIcons.settings, label: 'Настройки'),
  ];

  Widget pane(BuildContext context, String title) => ColoredBox(
        color: context.colors.bgSurface,
        child: Center(
          child: Text(
            title,
            style: context.typography.title3.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );

  goldenTest(
    'app_bar_wordmark',
    size: const Size(390, 88),
    padding: EdgeInsets.zero,
    builder: (context) => CommyAppBar(
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
          semanticLabel: 'Добавить сервер',
        ),
      ],
    ),
  );

  goldenTest(
    'app_bar_section',
    size: const Size(390, 88),
    padding: EdgeInsets.zero,
    builder: (context) => CommyAppBar.section(
      title: 'Настройки',
      onBack: () {},
      backSemanticLabel: 'Назад',
      actions: <Widget>[
        CommyIconButton(
          icon: CommyIcons.more,
          onPressed: () {},
          semanticLabel: 'Ещё',
        ),
      ],
    ),
  );

  goldenTest(
    'sheet_surface',
    size: const Size(390, 280),
    padding: EdgeInsets.zero,
    builder: (context) => Align(
      alignment: Alignment.bottomCenter,
      child: CommySheetSurface(
        title: 'Добавить сервер',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: context.spacing.s3,
            children: <Widget>[
              CommyButton(
                label: 'Вставить',
                onPressed: () {},
                isFullWidth: true,
              ),
              CommyButton(
                label: 'Подписка по URL',
                onPressed: () {},
                variant: CommyButtonVariant.secondary,
                icon: CommyIcons.link,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  goldenTest(
    'sheet_surface_dialog',
    size: const Size(640, 260),
    padding: EdgeInsets.zero,
    builder: (context) => CommySheetSurface(
      title: 'Удалить подписку?',
      isDialog: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: context.spacing.s3,
          children: <Widget>[
            Text(
              'Её узлы исчезнут из списка. Саму ссылку можно будет '
              'добавить снова.',
              style: context.typography.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            CommyButton(
              label: 'Удалить',
              onPressed: () {},
              variant: CommyButtonVariant.danger,
            ),
          ],
        ),
      ),
    ),
  );

  goldenTest(
    'shell_mobile',
    size: const Size(390, 300),
    padding: EdgeInsets.zero,
    builder: (context) => MobileShell(
      appBar: CommyAppBar(
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
            semanticLabel: 'Добавить сервер',
          ),
        ],
      ),
      body: pane(context, 'Одна колонка, нижнего меню нет'),
    ),
  );

  goldenTest(
    'shell_tablet',
    size: const Size(820, 360),
    padding: EdgeInsets.zero,
    builder: (context) => TabletShell(
      destinations: destinations,
      selectedIndex: 1,
      onDestinationSelected: (_) {},
      appBar: const CommyAppBar.section(
        title: 'Маршрутизация',
        onBack: null,
      ),
      detail: pane(context, 'Деталь'),
      body: pane(context, 'Список'),
    ),
  );

  goldenTest(
    'shell_desktop',
    size: const Size(1280, 400),
    padding: EdgeInsets.zero,
    builder: (context) => DesktopShell(
      destinations: destinations,
      selectedIndex: 2,
      onDestinationSelected: (_) {},
      appBar: const CommyAppBar.section(
        title: 'Диагностика',
        onBack: null,
      ),
      detail: pane(context, 'Деталь'),
      body: pane(context, 'Список'),
    ),
  );
}
