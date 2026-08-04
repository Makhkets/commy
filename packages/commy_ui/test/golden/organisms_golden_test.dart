import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

import '../support/commy_test_host.dart';

/// One golden per organism, in both themes.
///
/// Every date and duration here is a literal. Nothing in this file may read
/// the wall clock: a golden that depends on `DateTime.now()` starts failing
/// on its own after the first minute.
void main() {
  useCommyGoldens();

  final at = DateTime.utc(2026, 8, 4, 4, 36, 12);

  Widget card(Widget child) => Builder(
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.bgSurface,
            borderRadius: context.radii.mdAll,
            border: Border.all(color: context.colors.borderSubtle),
          ),
          child: child,
        ),
      );

  for (final state in ConnectState.values) {
    goldenTest(
      'connect_button_${state.name}',
      size: const Size(280, 280),
      builder: (context) => ConnectButton(
        state: state,
        onPressed: () {},
        semanticLabel: 'Подключиться',
        semanticValue: state.name,
      ),
    );
  }

  goldenTest(
    'metrics_strip',
    size: const Size(360, 120),
    builder: (context) => const MetricsStrip(
      uplink: 25600,
      downlink: 1348576,
      session: Duration(hours: 1, minutes: 12, seconds: 47),
      isActive: true,
      uplinkLabel: 'Отдача',
      sessionLabel: 'Сессия',
      downlinkLabel: 'Загрузка',
    ),
  );

  goldenTest(
    'metrics_strip_idle',
    size: const Size(360, 120),
    builder: (context) => const MetricsStrip(
      uplink: 25600,
      downlink: 1348576,
      session: Duration(hours: 1),
      uplinkLabel: 'Отдача',
      sessionLabel: 'Сессия',
      downlinkLabel: 'Загрузка',
    ),
  );

  goldenTest(
    'selected_node',
    size: const Size(360, 120),
    builder: (context) => SelectedNode(
      name: 'Авто-Выбор',
      onTap: () {},
      flag: const CountryFlag(countryCode: 'EU'),
    ),
  );

  goldenTest(
    'check_button',
    size: const Size(320, 120),
    builder: (context) => CheckButton(label: 'Проверить', onPressed: () {}),
  );

  goldenTest(
    'check_button_running',
    size: const Size(320, 120),
    builder: (context) => CheckButton(
      label: 'Проверить',
      onPressed: () {},
      isChecking: true,
    ),
  );

  goldenTest(
    'node_tile',
    size: const Size(390, 300),
    builder: (context) => card(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NodeTile(
            name: 'Авто-Выбор',
            countryCode: 'EU',
            descriptors: const <String>['VLESS', 'Reality', 'TCP'],
            latency: const Duration(milliseconds: 41),
            isActive: true,
            onTap: () {},
          ),
          const CommyDivider(),
          NodeTile(
            name: 'Amsterdam 03',
            countryCode: 'NL',
            descriptors: const <String>['VLESS', 'Reality', 'TCP'],
            latency: const Duration(milliseconds: 148),
            onTap: () {},
          ),
          const CommyDivider(),
          NodeTile(
            name: 'Tokyo 01',
            countryCode: 'JP',
            descriptors: const <String>['Trojan', 'TLS', 'WS'],
            latency: const Duration(milliseconds: 620),
            onTap: () {},
          ),
          const CommyDivider(),
          NodeTile(
            name: 'Node without a country',
            descriptors: const <String>['Hysteria2', 'QUIC'],
            isReachable: false,
            offlineSemanticLabel: 'Недоступен',
            onTap: () {},
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'group_header',
    size: const Size(390, 140),
    builder: (context) => card(
      GroupHeader(
        title: 'Мои серверы',
        subtitle: 'добавлены вручную · 1 узел',
        collapseLabel: 'Свернуть',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        onToggleCollapse: () {},
        onPingAll: () {},
        onMore: () {},
      ),
    ),
  );

  goldenTest(
    'subscription_card',
    size: const Size(390, 520),
    builder: (context) => SubscriptionCard(
      name: 'MAKHKETS VPN',
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
          isActive: true,
          onTap: () {},
        ),
        NodeTile(
          name: 'Amsterdam 03',
          countryCode: 'NL',
          descriptors: const <String>['VLESS', 'Reality', 'TCP'],
          latency: const Duration(milliseconds: 148),
          onTap: () {},
        ),
      ],
    ),
  );

  goldenTest(
    'subscription_card_error',
    size: const Size(390, 260),
    builder: (context) => SubscriptionCard(
      name: 'Старая подписка',
      subtitle: 'обновление не удалось',
      health: SubscriptionHealth.error,
      healthSemanticLabel: 'Подписка недоступна',
      refreshLabel: 'Обновить',
      pingAllLabel: 'Измерить все',
      moreLabel: 'Ещё',
      isRefreshing: true,
      onRefresh: () {},
      onPingAll: () {},
      onMore: () {},
    ),
  );

  goldenTest(
    'rule_row',
    size: const Size(390, 260),
    builder: (context) => card(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RuleRow(
            matcher: 'geosite:ru',
            actionLabel: 'Прямо',
            action: RuleAction.direct,
            dragIndex: 0,
            dragHandleLabel: 'Переместить',
            onTap: () {},
          ),
          const CommyDivider(),
          RuleRow(
            matcher: 'domain_suffix:ads.example.com',
            actionLabel: 'Блок',
            action: RuleAction.block,
            dragIndex: 1,
            dragHandleLabel: 'Переместить',
            onTap: () {},
          ),
          const CommyDivider(),
          const RuleRow(
            matcher: 'Всё остальное',
            actionLabel: 'Прокси',
            action: RuleAction.proxy,
            isFinal: true,
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'log_line',
    size: const Size(390, 220),
    builder: (context) => Builder(
      builder: (context) => ColoredBox(
        color: context.colors.bgInset,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LogLineView(
              isSelectable: false,
              line: LogLine(
                level: LogLevel.info,
                tag: 'router',
                message: 'started at 127.0.0.1:2080',
                at: at,
              ),
            ),
            LogLineView(
              isSelectable: false,
              line: LogLine(
                level: LogLevel.warn,
                tag: 'dns',
                message: 'fallback to system resolver',
                at: at,
              ),
            ),
            LogLineView(
              isSelectable: false,
              line: LogLine(
                level: LogLevel.error,
                message: 'outbound/vless: connection reset by peer',
                at: at,
              ),
            ),
            LogLineView(
              isSelectable: false,
              line: LogLine(
                level: LogLevel.debug,
                tag: 'inbound',
                message: 'tun opened, mtu 9000',
                at: at,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  goldenTest(
    'connection_row',
    size: const Size(390, 260),
    builder: (context) => card(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConnectionRow(
            age: const Duration(minutes: 3, seconds: 12),
            connection: ConnectionInfo(
              id: '1',
              host: 'api.telegram.org',
              rule: 'geosite:telegram',
              outbound: 'proxy',
              uploadTotal: 24576,
              downloadTotal: 1348576,
              start: at,
              network: 'tcp',
            ),
            onTap: () {},
          ),
          const CommyDivider(),
          ConnectionRow(
            age: const Duration(seconds: 9),
            connection: ConnectionInfo(
              id: '2',
              host: 'mail.ru',
              rule: 'geosite:ru',
              outbound: 'direct',
              uploadTotal: 512,
              downloadTotal: 8192,
              start: at,
              network: 'udp',
            ),
            onTap: () {},
          ),
        ],
      ),
    ),
  );

  goldenTest(
    'traffic_chart',
    size: const Size(390, 140),
    builder: (context) => TrafficChart(
      semanticLabel: 'Трафик за 60 секунд, пик 1,2 МБ/с',
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

  goldenTest(
    'traffic_chart_empty',
    size: const Size(390, 140),
    builder: (context) => const TrafficChart(
      samples: <TrafficSample>[],
      semanticLabel: 'Нет данных о трафике',
    ),
  );
}
