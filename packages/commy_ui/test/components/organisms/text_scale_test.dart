import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// Every organism at 200 % system font on the narrowest phone we support.
///
/// This is not a nicety. The people most likely to raise the system font are
/// the ones least able to work around a row that runs off the edge, and an
/// organism that overflows is unusable for them while looking perfect in the
/// mockups. The failure mode is silent in a golden and loud here: Flutter
/// reports overflow as an exception, which `tester.takeException()` returns.
///
/// Vertical growth is fine — screens scroll — so each subject is placed in a
/// scroll view. What is being asserted is that nothing runs off the side and
/// nothing asks for infinite space.
void main() {
  useCommyGoldens();

  final at = DateTime.utc(2026, 8, 4, 4, 36, 12);

  Future<void> expectSurvives(
    WidgetTester tester,
    String description,
    Widget subject,
  ) async {
    await pumpAtTextScale(
      tester,
      child: SingleChildScrollView(
        child: SizedBox(width: 320, child: subject),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.takeException(),
      isNull,
      reason: '$description overflows at 200 % text',
    );
  }

  testWidgets('MetricsStrip survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'MetricsStrip',
      const MetricsStrip(
        uplink: 25600,
        downlink: 1348576,
        session: Duration(hours: 1, minutes: 12, seconds: 47),
        isActive: true,
        uplinkLabel: 'Отдача',
        sessionLabel: 'Сессия',
        downlinkLabel: 'Загрузка',
      ),
    );
  });

  testWidgets('SelectedNode survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'SelectedNode',
      SelectedNode(
        name: 'Amsterdam 03 — очень длинное имя узла',
        onTap: () {},
        flag: const CountryFlag(countryCode: 'NL'),
      ),
    );
  });

  testWidgets('CheckButton survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'CheckButton',
      CheckButton(label: 'Проверить соединение', onPressed: () {}),
    );
  });

  testWidgets('ConnectButton survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'ConnectButton',
      ConnectButton(
        state: ConnectState.connected,
        onPressed: () {},
        semanticLabel: 'Отключиться',
      ),
    );
  });

  testWidgets('NodeTile survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'NodeTile',
      NodeTile(
        name: 'Amsterdam 03 — очень длинное имя узла',
        countryCode: 'NL',
        descriptors: const <String>['VLESS', 'Reality', 'TCP'],
        latency: const Duration(milliseconds: 148),
        isActive: true,
        onTap: () {},
      ),
    );
  });

  testWidgets('GroupHeader survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'GroupHeader',
      GroupHeader(
        title: 'Мои серверы, добавленные вручную',
        subtitle: 'добавлены вручную · 1 узел',
        collapseLabel: 'Свернуть',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        onToggleCollapse: () {},
        onPingAll: () {},
        onMore: () {},
      ),
    );
  });

  testWidgets('SubscriptionCard survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'SubscriptionCard',
      SubscriptionCard(
        name: 'MAKHKETS VPN — очень длинное имя подписки',
        subtitle: '2 ч назад · авто 1 ч',
        refreshLabel: 'Обновить',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        quotaRatio: 0.56,
        quotaLabel: '1,12 ТБ из 2 ТБ',
        expiryLabel: 'осталось 18 дней',
        announcement: 'id: Makhkets · связь в телеграм @tmaac',
        links: <SubscriptionCardLink>[
          SubscriptionCardLink(
            label: 'Поддержка',
            icon: CommyIcons.externalLink,
            onPressed: () {},
          ),
          SubscriptionCardLink(
            label: 'Сайт',
            icon: CommyIcons.globe,
            onPressed: () {},
          ),
        ],
        onRefresh: () {},
        onPingAll: () {},
        onMore: () {},
        nodes: <Widget>[
          NodeTile(
            name: 'Авто-Выбор',
            countryCode: 'EU',
            descriptors: const <String>['VLESS', 'Reality', 'TCP'],
            latency: const Duration(milliseconds: 41),
            onTap: () {},
          ),
        ],
      ),
    );
  });

  testWidgets('RuleRow survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'RuleRow',
      RuleRow(
        matcher: 'domain_suffix:very.long.example.com',
        actionLabel: 'Прокси',
        action: RuleAction.proxy,
        dragIndex: 0,
        dragHandleLabel: 'Переместить',
        onTap: () {},
      ),
    );
  });

  testWidgets('LogLineView survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'LogLineView',
      LogLineView(
        isSelectable: false,
        line: LogLine(
          level: LogLevel.error,
          tag: 'outbound/vless',
          message: 'connection reset by peer while dialing nl-03.example.net',
          at: at,
        ),
      ),
    );
  });

  testWidgets('ConnectionRow survives 200 %', (tester) async {
    // The one that used to run 87 dp off the edge, before its metadata line
    // became a Wrap. It stays in this file for exactly that reason.
    await expectSurvives(
      tester,
      'ConnectionRow',
      ConnectionRow(
        age: const Duration(minutes: 3, seconds: 12),
        connection: ConnectionInfo(
          id: '1',
          host: 'very-long-hostname.api.telegram.org',
          rule: 'geosite:telegram',
          outbound: 'proxy',
          uploadTotal: 24576,
          downloadTotal: 1348576,
          start: at,
          network: 'tcp',
        ),
        onTap: () {},
      ),
    );
  });

  testWidgets('TrafficChart survives 200 %', (tester) async {
    await expectSurvives(
      tester,
      'TrafficChart',
      TrafficChart(
        semanticLabel: 'Трафик за 60 секунд',
        samples: <TrafficSample>[
          for (var index = 0; index < 30; index++)
            TrafficSample(
              uplink: 4096 * (index % 5 + 1),
              downlink: 32768 * ((index * 7) % 11 + 1),
              uplinkTotal: 4096 * index,
              downlinkTotal: 32768 * index,
              at: at.add(Duration(seconds: index * 2)),
            ),
        ],
      ),
    );
  });
}
