import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/auto_refresh_notice.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/subscription_scheduler.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_data/commy_data.dart';
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

  void start(
    List<Subscription> subscriptions, {
    List<Override> extra = const <Override>[],
  }) {
    clock = CommyTestHarness.now;
    harness = CommyTestHarness(subscriptions: subscriptions);
    harness.subscriptionFetcher.body = link;
    container = ProviderContainer(
      overrides: harness.overrides(
        extra: <Override>[
          refreshClockProvider.overrideWithValue(() => clock),
          ...extra,
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

  // Nobody pressed anything, so nobody is waiting for an answer: the only way
  // the user learns that the list under them changed — or that the panel has
  // stopped answering — is what the scheduler publishes for `NoticeHost`.
  group('what it tells the user', () {
    /// Every notice published, in order.
    late List<AutoRefreshNotice> said;

    void listen() {
      said = <AutoRefreshNotice>[];
      final handle = container.listen<AutoRefreshNotice?>(
        autoRefreshNoticeProvider,
        (previous, next) {
          if (next != null) {
            said.add(next);
          }
        },
      );
      addTearDown(handle.close);
    }

    /// Takes the notice down the way `NoticeHost` does once it has shown it.
    ///
    /// Without this a second notice equal to the first would not be a change
    /// of state at all, and "said nothing" would pass for the wrong reason.
    void shown() => container.read(autoRefreshNoticeProvider.notifier).clear();

    void refuse() {
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse('https://panel.example.net/sub/token'),
        cause: 'the panel did not answer',
      );
    }

    /// A document of [count] distinct servers: the count in the toast is the
    /// one the store ended up with, so one server would not tell it apart
    /// from a constant.
    String servers(int count) => <String>[
          for (var index = 1; index <= count; index++)
            link.replaceFirst('nl-03.', 'nl-0$index.'),
        ].join('\n');

    SubscriptionController manual() =>
        container.read(subscriptionControllerProvider.notifier);

    test('a refresh that worked names the subscription and counts the servers',
        () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      harness.subscriptionFetcher.body = servers(3);
      listen();

      await sweep();

      expect(harness.nodeRepository.nodes, hasLength(3));
      expect(said, <AutoRefreshNotice>[
        const AutoRefreshNotice.refreshed(name: 'My panel', count: 3),
      ]);
    });

    test('the name is the stored one, a rename during the sweep included',
        () async {
      // Two due at once, refreshed one after the other: the user renames the
      // second while the first is still downloading. The sweep's own list is
      // older than that, and the toast must say what the card says.
      start(<Subscription>[
        aged(const Duration(hours: 3)).copyWith(id: 'sub-1', name: 'Home'),
        aged(const Duration(hours: 3)).copyWith(id: 'sub-2', name: 'Old'),
      ]);
      listen();
      var renamed = false;
      final watch = container.listen<SubscriptionActionState>(
        subscriptionControllerProvider,
        (previous, next) {
          if (next.refreshingId == 'sub-1' && !renamed) {
            renamed = true;
            final second = harness.subscriptionRepository.items
                .firstWhere((item) => item.id == 'sub-2');
            harness.subscriptionRepository
                .upsert(second.copyWith(name: 'Work'))
                .ignore();
          }
        },
      );
      addTearDown(watch.close);

      await sweep();

      expect(renamed, isTrue);
      expect(said, <AutoRefreshNotice>[
        const AutoRefreshNotice.refreshed(name: 'Home', count: 1),
        const AutoRefreshNotice.refreshed(name: 'Work', count: 1),
      ]);
    });

    test('the first failure is said, with the reason', () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();
      listen();

      await sweep();

      expect(said, hasLength(1));
      expect(said.single.name, 'My panel');
      expect(said.single.count, isNull);
      expect(said.single.failure, isA<SubscriptionUnreachableFailure>());
    });

    test('a retry that fails again after the backoff is not said again',
        () async {
      // A panel that is down for an afternoon would otherwise interrupt the
      // user every fifteen minutes with the same sentence.
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();
      listen();
      await sweep();
      shown();

      clock = clock.add(
        SubscriptionScheduler.retryAfterFailure + const Duration(minutes: 1),
      );
      await sweep();

      expect(fetches(), 2);
      expect(said, hasLength(1));
      expect(container.read(autoRefreshNoticeProvider), isNull);
    });

    test('a failure after a refresh from the card worked is news again',
        () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();
      listen();
      await sweep();
      shown();

      // The user's own refresh, from the card, which the scheduler never
      // sees — only its trace, the moved `lastUpdatedAt`.
      harness.subscriptionFetcher.failure = null;
      expect(await manual().refresh('sub-1'), isTrue);
      await pumpEventQueue();
      final refreshedAt = stored().lastUpdatedAt!;

      refuse();
      clock = refreshedAt.add(const Duration(minutes: 61));
      await sweep();

      expect(fetches(), 3);
      expect(said, hasLength(2));
      expect(said.last.failure, isA<SubscriptionUnreachableFailure>());
    });

    test('an automatic refresh that worked ends the streak too', () async {
      start(<Subscription>[aged(const Duration(hours: 3))]);
      refuse();
      listen();
      await sweep();
      shown();

      harness.subscriptionFetcher.failure = null;
      clock = clock.add(
        SubscriptionScheduler.retryAfterFailure + const Duration(minutes: 1),
      );
      await sweep();
      shown();
      final refreshedAt = stored().lastUpdatedAt!;

      refuse();
      clock = refreshedAt.add(const Duration(minutes: 61));
      await sweep();

      expect(fetches(), 3);
      expect(said.map((notice) => notice.failure == null), <bool>[
        false,
        true,
        false,
      ]);
    });

    group('two due in one sweep', () {
      /// Fails the fetch of every subscription in [refused] and serves the
      /// rest, decided per fetch — the fake's one switch is read when the
      /// download starts.
      void refuseOnly(Set<String> refused) {
        final watch = container.listen<SubscriptionActionState>(
          subscriptionControllerProvider,
          (previous, next) {
            final id = next.refreshingId;
            if (id == null) {
              return;
            }
            if (refused.contains(id)) {
              refuse();
            } else {
              harness.subscriptionFetcher.failure = null;
            }
          },
        );
        addTearDown(watch.close);
      }

      void startTwo() => start(<Subscription>[
            aged(const Duration(hours: 3)).copyWith(id: 'sub-1', name: 'Home'),
            aged(const Duration(hours: 3)).copyWith(id: 'sub-2', name: 'Work'),
          ]);

      test('a failure is not covered by the next one that worked', () async {
        // Toasts replace each other: "Work refreshed" a second after "Home
        // was not refreshed" took the failure down, and the streak rule kept
        // it quiet on every retry after.
        startTwo();
        refuseOnly(<String>{'sub-1'});
        listen();

        await sweep();

        expect(fetches(), 2);
        expect(said, hasLength(1));
        expect(said.single.name, 'Home');
        expect(said.single.failure, isA<SubscriptionUnreachableFailure>());
      });

      test('one that worked before the failure is said, then the failure',
          () async {
        startTwo();
        refuseOnly(<String>{'sub-2'});
        listen();

        await sweep();

        expect(said.map((notice) => (notice.name, notice.failure == null)), <(
          String,
          bool,
        )>[
          ('Home', true),
          ('Work', false),
        ]);
      });

      test('a second failure waits for its own retry, and is said then',
          () async {
        startTwo();
        refuseOnly(<String>{'sub-1', 'sub-2'});
        listen();
        await sweep();
        shown();

        expect(said.map((notice) => notice.name), <String>['Home']);

        clock = clock.add(
          SubscriptionScheduler.retryAfterFailure + const Duration(minutes: 1),
        );
        await sweep();

        expect(fetches(), 4);
        expect(said.map((notice) => notice.name), <String>['Home', 'Work']);
      });
    });

    test('the log line says what the panel answered, without the link',
        () async {
      // The toast is a headline that sends the user to the logs, so the
      // reason — a Remnawave panel's 403 over its device limit — is there.
      final logger = AppLogger(
        sink: (_) {},
        clock: () => CommyTestHarness.now,
      );
      addTearDown(logger.dispose);
      start(
        <Subscription>[aged(const Duration(hours: 3))],
        extra: <Override>[appLoggerProvider.overrideWithValue(logger)],
      );
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse('https://panel.example.net/sub/secret-token'),
        cause: const HttpTransportError(
          kind: HttpTransportError.kindStatus,
          statusCode: 403,
        ),
      );

      await sweep();

      final line = logger.buffer
          .map((line) => line.message)
          .firstWhere((message) => message.startsWith('automatic refresh'));
      expect(line, contains('subscription_unreachable (status 403)'));
      expect(line, isNot(contains('secret-token')));
      expect(line, isNot(contains('panel.example.net')));
    });

    test('a refresh from the card is answered by the card, not from here',
        () async {
      // Not due, so the scheduler has no business of its own here; it is
      // alive all the same, as it is in the app, watched from the root.
      start(<Subscription>[aged(const Duration(minutes: 20), hours: 6)]);
      container.read(subscriptionRefreshProvider);
      listen();

      expect(await manual().refresh('sub-1'), isTrue);
      refuse();
      expect(await manual().refresh('sub-1'), isFalse);
      await pumpEventQueue();

      expect(fetches(), 2);
      expect(said, isEmpty);
    });
  });
}
