import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The card's menu stays usable while its refresh spinner turns, and on a
/// slow link that is seconds. What the menu does in them must leave the
/// refresh alone: its spinner, and the guard that keeps a second refresh of
/// the same panel from starting beside it.
void main() {
  const link = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k'
      '&sid=ab12cd34#Amsterdam%2003';

  late CommyTestHarness harness;
  late ProviderContainer container;
  late Completer<void> panel;
  late _SlowPanel fetcher;

  setUp(() {
    panel = Completer<void>();
    fetcher = _SlowPanel(panel.future, body: link);
    harness =
        CommyTestHarness(subscriptions: <Subscription>[testSubscription()]);
    container = ProviderContainer(
      overrides: harness.overrides(
        extra: <Override>[
          updateSubscriptionUseCaseProvider.overrideWith(
            (ref) => UpdateSubscriptionUseCase(
              fetcher: fetcher,
              parser: ref.watch(linkParserProvider),
              subscriptions: ref.watch(subscriptionRepositoryProvider),
              nodes: ref.watch(nodeRepositoryProvider),
            ),
          ),
        ],
      ),
    );
    addTearDown(() async {
      if (!panel.isCompleted) {
        panel.complete();
      }
      container.dispose();
      await harness.dispose();
    });
  });

  SubscriptionController controller() =>
      container.read(subscriptionControllerProvider.notifier);

  String? refreshingId() =>
      container.read(subscriptionControllerProvider).refreshingId;

  test('collapsing the card mid-refresh keeps its spinner', () async {
    final refreshing = controller().refresh('sub-1');
    await pumpEventQueue();

    await controller().setCollapsed(id: 'sub-1', isCollapsed: true);

    expect(refreshingId(), 'sub-1');
    panel.complete();
    expect(await refreshing, isTrue);
    expect(refreshingId(), isNull);
  });

  test('a menu action mid-refresh does not open the door to a second one',
      () async {
    final refreshing = controller().refresh('sub-1');
    await pumpEventQueue();

    await controller().rename(testSubscription(), 'Work');
    final second = await controller().refresh('sub-1');

    expect(second, isFalse);
    expect(fetcher.calls, 1);
    panel.complete();
    await refreshing;
  });

  test('auto refresh switched off mid-refresh stays off', () async {
    final refreshing = controller().refresh('sub-1');
    await pumpEventQueue();

    await controller().setAutoUpdate(testSubscription(), value: false);
    panel.complete();
    await refreshing;

    final stored = harness.subscriptionRepository.items.single;
    expect(stored.autoUpdate, isFalse);
    expect(stored.lastUpdatedAt, isNot(testSubscription().lastUpdatedAt));
  });
}

/// A panel that answers once [answer] completes.
class _SlowPanel implements SubscriptionFetcher {
  _SlowPanel(this.answer, {required this.body});

  final Future<void> answer;

  final String body;

  int calls = 0;

  @override
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  }) async {
    calls++;
    await answer;
    return Ok<SubscriptionPayload, CommyFailure>(
      SubscriptionPayload(body: body),
    );
  }
}
