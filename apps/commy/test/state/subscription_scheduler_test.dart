import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/subscription_scheduler.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #8: the card said «авто 1 ч» and nothing ever ran.
///
/// The `Timer.periodic` in the provider is not what these tests exercise — a
/// test that waited a minute is a test nobody runs. What is exercised is the
/// decision a tick makes: which subscriptions a sweep picks up, which it
/// leaves alone, and what it does after a panel refuses to answer.
void main() {
  const link = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Amsterdam%2003';

  late CommyTestHarness harness;
  late ProviderContainer container;

  /// The wall clock the scheduler reads. Moved by the tests that need time to
  /// pass; the real `DateTime.now()` never comes into the decision.
  late DateTime clock;

  /// A subscription last refreshed [ago] before the starting [clock].
  Subscription aged(Duration ago, {bool autoUpdate = true, int hours = 1}) {
    return testSubscription(
      autoUpdate: autoUpdate,
      updateIntervalHours: hours,
      updatedAgo: ago,
    );
  }

  void start(List<Subscription> subscriptions) {
    clock = CommyTestHarness.now;
    harness = CommyTestHarness(subscriptions: subscriptions);
    harness.subscriptionFetcher.body = link;
    container = ProviderContainer(
      overrides: harness.overrides(
        extra: <Override>[
          refreshClockProvider.overrideWithValue(() => clock),
        ],
      ),
    );
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handle = container.listen(subscriptionsProvider, (_, __) {});
    addTearDown(handle.close);
  }

  /// Runs one sweep against the settled stored list.
  Future<void> sweep() async {
    await container.read(subscriptionsProvider.future);
    await container.read(subscriptionRefreshProvider).sweep();
  }

  int fetches() => harness.subscriptionFetcher.callCount;

  Subscription stored() => harness.subscriptionRepository.items.single;

  test('an overdue subscription is refreshed', () async {
    start(<Subscription>[aged(const Duration(hours: 3))]);

    await sweep();

    expect(fetches(), 1);
    expect(harness.nodeRepository.nodes, hasLength(1));
    expect(stored().lastUpdatedAt, isNotNull);
  });

  test('one still inside its interval is left alone', () async {
    start(<Subscription>[aged(const Duration(minutes: 20), hours: 6)]);

    await sweep();

    expect(fetches(), 0);
  });

  test('auto refresh off means never, however overdue', () async {
    start(<Subscription>[aged(const Duration(days: 30), autoUpdate: false)]);

    await sweep();

    expect(fetches(), 0);
  });

  test('one never refreshed is due immediately', () async {
    start(<Subscription>[testSubscription(updatedAgo: null)]);

    await sweep();

    expect(fetches(), 1);
  });

  test('every due subscription is picked up, not just the first', () async {
    start(<Subscription>[
      aged(const Duration(hours: 3)).copyWith(id: 'sub-1'),
      aged(const Duration(hours: 3)).copyWith(id: 'sub-2'),
    ]);

    await sweep();

    expect(fetches(), 2);
  });

  test('the interval starts again from the refresh that just happened',
      () async {
    start(<Subscription>[aged(const Duration(hours: 3))]);

    await sweep();
    expect(fetches(), 1);

    // Half an hour after that refresh, against an interval of one hour. The
    // use case stamps `lastUpdatedAt` itself, so the clock is moved to sit
    // relative to what it wrote rather than to a guess.
    final refreshedAt = stored().lastUpdatedAt!;
    clock = refreshedAt.add(const Duration(minutes: 30));
    await sweep();
    expect(fetches(), 1);

    clock = refreshedAt.add(const Duration(minutes: 61));
    await sweep();
    expect(fetches(), 2);
  });

  group('after a failure', () {
    void refuse() {
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse('https://panel.example.net/sub/token'),
        cause: 'the panel did not answer',
      );
    }

    test('the panel is left alone rather than asked every tick', () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();

      await sweep();
      expect(fetches(), 1);
      expect(
        container.read(subscriptionControllerProvider).failure,
        isA<SubscriptionUnreachableFailure>(),
      );

      // Still overdue, and a whole tick later — but inside the backoff.
      clock = clock.add(SubscriptionScheduler.tick);
      await sweep();
      expect(fetches(), 1);
    });

    test('it is tried again once the backoff has run out', () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();
      await sweep();

      harness.subscriptionFetcher.failure = null;
      clock = clock.add(
        SubscriptionScheduler.retryAfterFailure + const Duration(minutes: 1),
      );
      await sweep();

      expect(fetches(), 2);
      expect(harness.nodeRepository.nodes, hasLength(1));
    });
  });
}
