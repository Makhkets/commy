import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

import '../support/commy_test_host.dart';

/// One golden per molecule, in both themes.
void main() {
  useCommyGoldens();

  Widget column(List<Widget> children) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: CommySpacing.standard.s4,
        children: children,
      );

  goldenTest(
    'empty_state',
    size: const Size(360, 320),
    builder: (context) => EmptyState(
      icon: CommyIcons.empty,
      title: 'Добавьте свой сервер',
      message: 'Commy не предлагает готовых серверов и не держит своих. '
          'Это решение продукта, а не пробел.',
      actionLabel: 'Вставить ссылку',
      onAction: () {},
    ),
  );

  goldenTest(
    'error_banner',
    size: const Size(360, 420),
    builder: (context) => column(<Widget>[
      ErrorBanner(
        title: 'Не удалось подключиться',
        message: 'Сервер не ответил за 10 секунд. Проверьте адрес и порт.',
        actionLabel: 'Повторить',
        onAction: () {},
        onDismiss: () {},
        dismissSemanticLabel: 'Закрыть',
      ),
      const ErrorBanner(
        message: 'Подписка обновится через 42 минуты.',
        tone: CommyTone.info,
      ),
      const ErrorBanner(
        message: 'Осталось меньше 10 % квоты.',
        tone: CommyTone.connecting,
      ),
    ]),
  );

  goldenTest(
    'latency_badge',
    size: const Size(320, 160),
    builder: (context) => column(const <Widget>[
      LatencyBadge(latency: Duration(milliseconds: 41)),
      LatencyBadge(latency: Duration(milliseconds: 180)),
      LatencyBadge(latency: Duration(milliseconds: 640)),
      LatencyBadge(latency: null),
    ]),
  );

  goldenTest(
    'quota_bar',
    size: const Size(360, 220),
    builder: (context) => column(const <Widget>[
      QuotaBar(
        ratio: 0.32,
        leadingLabel: '0,64 ТБ из 2 ТБ',
        trailingLabel: 'осталось 18 дней',
      ),
      QuotaBar(
        ratio: 0.81,
        leadingLabel: '1,62 ТБ из 2 ТБ',
        trailingLabel: 'осталось 4 дня',
      ),
      QuotaBar(
        ratio: 0.97,
        leadingLabel: '1,94 ТБ из 2 ТБ',
        trailingLabel: 'истекает завтра',
      ),
    ]),
  );

  goldenTest(
    'search_field',
    size: const Size(360, 120),
    builder: (context) => SearchField(
      hintText: 'Поиск по узлам',
      clearSemanticLabel: 'Очистить',
      onClear: () {},
    ),
  );

  goldenTest(
    'segmented_control',
    size: const Size(360, 140),
    builder: (context) => column(<Widget>[
      SegmentedControl<String>(
        value: 'rules',
        onChanged: (_) {},
        segments: const <SegmentedControlItem<String>>[
          SegmentedControlItem<String>(value: 'global', label: 'Глобально'),
          SegmentedControlItem<String>(value: 'rules', label: 'Правила'),
          SegmentedControlItem<String>(value: 'direct', label: 'Прямо'),
        ],
      ),
    ]),
  );

  goldenTest(
    'status_pill',
    size: const Size(360, 200),
    builder: (context) => Wrap(
      spacing: CommySpacing.standard.s3,
      runSpacing: CommySpacing.standard.s3,
      children: const <Widget>[
        StatusPill(label: 'Подключено', tone: CommyTone.connected),
        StatusPill(label: 'Подключение', tone: CommyTone.connecting),
        StatusPill(label: 'Ошибка', tone: CommyTone.error),
        StatusPill(label: 'Отключено', tone: CommyTone.idle),
        StatusPill(
          label: 'Проверка',
          tone: CommyTone.info,
          icon: CommyIcons.refresh,
        ),
      ],
    ),
  );

  goldenTest(
    'toast',
    size: const Size(400, 220),
    builder: (context) => column(<Widget>[
      const Toast(message: 'Ссылка скопирована'),
      Toast(
        message: 'Импортировано 24 узла',
        tone: CommyTone.connected,
        icon: CommyIcons.success,
        actionLabel: 'Отменить',
        onAction: () {},
      ),
    ]),
  );

  goldenTest(
    'traffic_meter',
    size: const Size(360, 200),
    builder: (context) => column(const <Widget>[
      TrafficMeter(uplink: 25600, downlink: 1348576),
      TrafficMeter(uplink: 0, downlink: 0, isActive: false),
      TrafficMeter(uplink: 25600, downlink: 1348576, isVertical: true),
    ]),
  );
}
