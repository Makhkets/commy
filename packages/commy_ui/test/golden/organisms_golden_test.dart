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
            borderRadius: context.radii.cardAll,
          ),
          child: child,
        ),
      );

  // The signature in every state (docs/04-design-system.md §8, «Маршрут»).
  // Motion is reduced in goldens, so a leg being built is the still,
  // half-drawn one.
  for (final state in ConnectState.values) {
    goldenTest(
      'connect_button_${state.name}',
      size: const Size(390, 300),
      builder: (context) => ConnectButton(
        state: state,
        label: switch (state) {
          ConnectState.idle || ConnectState.error => 'Подключиться',
          ConnectState.starting => 'Отменить',
          ConnectState.stopping => 'Отключение…',
          _ => 'Отключиться',
        },
        onPressed: () {},
      ),
    );
    goldenTest(
      'connection_route_${state.name}',
      size: const Size(390, 260),
      builder: (context) => Padding(
        padding: EdgeInsets.all(context.spacing.s4),
        child: ConnectionRoute(
          state: state,
          deviceLabel: 'Это устройство',
          serverName: 'Amsterdam 03',
          internetLabel: 'Интернет',
          flag: const CountryFlag(countryCode: 'NL'),
          tags: const <NodeTag>[
            NodeTag('VLESS', hue: CommyTagHue.azure),
            NodeTag('Reality', hue: CommyTagHue.iris),
            NodeTag('TCP'),
          ],
          latency: const Duration(milliseconds: 48),
          onServerTap: () {},
          checkLabel: 'Проверить доступ',
          onCheck: state.isTunnelUp ? () {} : null,
          internetStatus:
              state == ConnectState.connected ? 'Доступ есть, 52 мс' : null,
          internetTone: CommyTone.connected,
          breakAt: state == ConnectState.error ? RouteBreak.server : null,
        ),
      ),
    );
  }

  goldenTest(
    'connect_button_focused',
    size: const Size(390, 300),
    tabs: 1,
    builder: (context) => ConnectButton(
      state: ConnectState.idle,
      label: 'Подключиться',
      onPressed: () {},
    ),
  );

  goldenTest(
    'connection_route_no_answer',
    size: const Size(390, 260),
    builder: (context) => Padding(
      padding: EdgeInsets.all(context.spacing.s4),
      child: ConnectionRoute(
        state: ConnectState.connected,
        deviceLabel: 'Это устройство',
        serverName: 'Amsterdam 03',
        internetLabel: 'Интернет',
        flag: const CountryFlag(countryCode: 'NL'),
        checkLabel: 'Проверить доступ',
        onCheck: () {},
        internetStatus: 'Через сервер нет ответа',
        internetTone: CommyTone.connecting,
        breakAt: RouteBreak.internet,
      ),
    ),
  );

  goldenTest(
    'route_steps',
    size: const Size(390, 220),
    builder: (context) => Padding(
      padding: EdgeInsets.all(context.spacing.s4),
      child: const RouteSteps(
        steps: <RouteStep>[
          RouteStep(
            label: 'Имя сервера',
            state: RouteStepState.passed,
            detail: '198.51.100.7',
          ),
          RouteStep(
            label: 'Порт открыт',
            state: RouteStepState.passed,
            detail: '37 мс',
          ),
          RouteStep(
            label: 'TLS-рукопожатие',
            state: RouteStepState.passed,
            detail: 'nl-03.example.net',
          ),
          RouteStep(
            label: 'Запрос через сервер',
            state: RouteStepState.failed,
          ),
        ],
      ),
    ),
  );

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
    'node_tile',
    size: const Size(390, 370),
    builder: (context) => card(
      Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.s1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NodeTile(
              name: 'Авто-Выбор',
              countryCode: 'EU',
              descriptors: const <NodeTag>[
                NodeTag('VLESS', hue: CommyTagHue.azure),
                NodeTag('Reality', hue: CommyTagHue.iris),
                NodeTag('TCP'),
                NodeTag('Vision', hue: CommyTagHue.gold),
              ],
              latency: const Duration(milliseconds: 41),
              isActive: true,
              onTap: () {},
            ),
            NodeTile(
              name: 'Amsterdam 03',
              countryCode: 'NL',
              descriptors: const <NodeTag>[
                NodeTag('VLESS', hue: CommyTagHue.azure),
                NodeTag('Reality', hue: CommyTagHue.iris),
                NodeTag('TCP'),
              ],
              latency: const Duration(milliseconds: 148),
              onTap: () {},
            ),
            NodeTile(
              name: 'Tokyo 01',
              countryCode: 'JP',
              descriptors: const <NodeTag>[
                NodeTag('TROJAN', hue: CommyTagHue.orchid),
                NodeTag('TLS', hue: CommyTagHue.mint),
                NodeTag('WS'),
              ],
              latency: const Duration(milliseconds: 620),
              onTap: () {},
            ),
            NodeTile(
              name: 'Node without a country',
              descriptors: const <NodeTag>[
                NodeTag('HYSTERIA2', hue: CommyTagHue.tangerine),
                NodeTag('QUIC'),
              ],
              isReachable: false,
              offlineSemanticLabel: 'Недоступен',
              onTap: () {},
            ),
            // A server with a flag that failed its ping: the flag goes grey
            // with the name, so the row reads as down before it is read.
            NodeTile(
              name: 'Frankfurt 02',
              countryCode: 'DE',
              descriptors: const <NodeTag>[
                NodeTag('VLESS', hue: CommyTagHue.azure),
                NodeTag('Reality', hue: CommyTagHue.iris),
                NodeTag('TCP'),
              ],
              isReachable: false,
              offlineSemanticLabel: 'Недоступен',
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );

  // Every hue the server line can wear, one protocol family per row, so the
  // palette is reviewed as a whole and not one row at a time.
  goldenTest(
    'node_tags',
    size: const Size(390, 460),
    builder: (context) => card(
      Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.s1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (name, code, tags) in <(String, String, List<NodeTag>)>[
              (
                'Helsinki',
                'FI',
                const <NodeTag>[
                  NodeTag('VLESS', hue: CommyTagHue.azure),
                  NodeTag('TLS', hue: CommyTagHue.mint),
                  NodeTag('XHTTP'),
                ]
              ),
              (
                'Warsaw',
                'PL',
                const <NodeTag>[
                  NodeTag('VMESS', hue: CommyTagHue.sky),
                  NodeTag('TLS', hue: CommyTagHue.mint),
                  NodeTag('WS'),
                ]
              ),
              (
                'Riga',
                'LV',
                const <NodeTag>[
                  NodeTag('SHADOWSOCKS', hue: CommyTagHue.teal),
                  NodeTag('TCP'),
                ]
              ),
              (
                'Vilnius',
                'LT',
                const <NodeTag>[
                  NodeTag('TUIC', hue: CommyTagHue.tangerine),
                  NodeTag('QUIC'),
                ]
              ),
              (
                'Tallinn',
                'EE',
                const <NodeTag>[
                  NodeTag('WIREGUARD', hue: CommyTagHue.coral),
                  NodeTag('UDP'),
                ]
              ),
              (
                'Oslo',
                'NO',
                const <NodeTag>[
                  NodeTag('TROJAN', hue: CommyTagHue.orchid),
                  NodeTag('Reality', hue: CommyTagHue.iris),
                  NodeTag('GRPC'),
                ]
              ),
            ])
              NodeTile(
                name: name,
                countryCode: code,
                descriptors: tags,
                latency: const Duration(milliseconds: 87),
                isActive: name == 'Riga',
                onTap: () {},
              ),
          ],
        ),
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
          descriptors: const <NodeTag>[
            NodeTag('VLESS', hue: CommyTagHue.azure),
            NodeTag('Reality', hue: CommyTagHue.iris),
            NodeTag('TCP'),
          ],
          latency: const Duration(milliseconds: 41),
          isActive: true,
          onTap: () {},
        ),
        NodeTile(
          name: 'Amsterdam 03',
          countryCode: 'NL',
          descriptors: const <NodeTag>[
            NodeTag('VLESS', hue: CommyTagHue.azure),
            NodeTag('Reality', hue: CommyTagHue.iris),
            NodeTag('TCP'),
          ],
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

  // Folded away with a run of "measure all" going: the server is gone, and
  // the progress with its way out is not.
  goldenTest(
    'subscription_card_collapsed_status',
    size: const Size(390, 168),
    builder: (context) => SubscriptionCard(
      name: 'MAKHKETS VPN',
      subtitle: '2 ч назад · авто 1 ч',
      refreshLabel: 'Обновить',
      pingAllLabel: 'Измерить все',
      moreLabel: 'Ещё',
      isCollapsed: true,
      onRefresh: () {},
      onPingAll: () {},
      onMore: () {},
      status: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.s4,
            vertical: context.spacing.s2,
          ),
          child: Row(
            children: <Widget>[
              const CommySpinner(),
              SizedBox(width: context.spacing.s3),
              Expanded(
                child: Text(
                  'Замер: 8 из 24',
                  style: context.typography.caption.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              CommyButton(
                label: 'Отмена',
                variant: CommyButtonVariant.ghost,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
      nodes: <Widget>[
        NodeTile(name: 'Amsterdam 03', countryCode: 'NL', onTap: () {}),
      ],
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
