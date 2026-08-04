import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = CoreConfig(<String, Object?>{'log': <String, Object?>{}});

  /// A fake whose whole machine runs inside a few milliseconds.
  FakeCoreClient build() => FakeCoreClient(
        startDelay: const Duration(milliseconds: 5),
        checkDelay: const Duration(milliseconds: 5),
        stopDelay: const Duration(milliseconds: 5),
        tick: const Duration(milliseconds: 5),
      );

  /// Collects states until [count] have arrived or [timeout] runs out.
  Future<List<TunnelStatus>> collect(
    Stream<TunnelStatus> stream,
    int count, {
    Duration timeout = const Duration(seconds: 2),
  }) =>
      stream.take(count).toList().timeout(timeout);

  /// Waits for the machine to *settle* on connected.
  ///
  /// `connected` is passed through twice — once when the tunnel comes up and
  /// again once the first reachability probe answers — so waiting for the first
  /// one leaves the client in `checking` and makes every assertion after it a
  /// race.
  Future<void> settled(FakeCoreClient client) async {
    await client.status.firstWhere((state) => state is TunnelChecking);
    await client.status.firstWhere((state) => state is TunnelConnected);
  }

  group('FakeCoreClient state machine', () {
    test('walks idle, starting, connected, checking and back', () async {
      final client = build();
      addTearDown(client.dispose);
      final states = collect(client.status, 5);

      await client.start(config);

      expect(await states, <Matcher>[
        isA<TunnelIdle>(),
        isA<TunnelStarting>(),
        isA<TunnelConnected>(),
        isA<TunnelChecking>(),
        isA<TunnelConnected>(),
      ]);
    });

    test('answers a new subscriber with the current state, like the '
        'native side does on onListen', () async {
      final client = build();
      addTearDown(client.dispose);

      await client.start(config);
      await settled(client);

      // A second screen attaching later must not be told the tunnel is idle.
      expect(await client.status.first, isA<TunnelConnected>());
    });

    test('keeps `since` fixed across the checking round trip', () async {
      final client = build();
      addTearDown(client.dispose);
      final states = collect(client.status, 5);

      await client.start(config);
      final seen = await states;

      final since = <DateTime>[
        for (final state in seen)
          if (state is TunnelConnected)
            state.since
          else if (state is TunnelChecking)
            state.since,
      ];
      expect(since.toSet(), hasLength(1));
    });

    test('walks stopping then idle on the way down', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      final states = collect(client.status, 3);
      await client.stop();

      expect(await states, <Matcher>[
        isA<TunnelConnected>(),
        isA<TunnelStopping>(),
        isA<TunnelIdle>(),
      ]);
    });

    test('a second start does not raise a second tunnel', () async {
      final client = build();
      addTearDown(client.dispose);

      await client.start(config);
      await client.start(config);
      await settled(client);

      expect(client.startCalls, 2);
      expect(client.isRunning, isTrue);
    });

    test('stopping a stopped tunnel is a success, not an error', () async {
      final client = build();
      addTearDown(client.dispose);

      await expectLater(client.stop(), completes);
      expect(client.currentStatus, isA<TunnelIdle>());
    });

    test('a dead core lands in error rather than sitting in connected',
        () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      client.crash(const CoreCrashedFailure('panic: nil map'));

      expect(client.currentStatus, isA<TunnelError>());
      expect(client.isRunning, isFalse);
    });
  });

  group('FakeCoreClient failure injection', () {
    test('a declined VPN prompt survives as a typed failure', () async {
      final client = build()
        ..failOn(FakeCoreStep.start, const PermissionDeniedFailure());
      addTearDown(client.dispose);

      await expectLater(
        client.start(config),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const PermissionDeniedFailure(),
          ),
        ),
      );
      // And it is visible on the stream too, because "the app said nothing"
      // is the named acceptance failure.
      expect(client.currentStatus, isA<TunnelError>());
    });

    test('failOn can be undone', () async {
      final client = build()
        ..failOn(FakeCoreStep.start, const PermissionDeniedFailure())
        ..succeedOn(FakeCoreStep.start);
      addTearDown(client.dispose);

      await expectLater(client.start(config), completes);
    });

    test('every step can be made to fail', () async {
      for (final step in FakeCoreStep.values) {
        final client = build()
          ..failOn(step, const CoreCrashedFailure('injected'));
        addTearDown(client.dispose);
        if (step != FakeCoreStep.start) {
          await client.start(config);
          await settled(client);
        }

        Future<void> call() => switch (step) {
              FakeCoreStep.start => client.start(config),
              FakeCoreStep.stop => client.stop(),
              FakeCoreStep.reload => client.reload(config),
              FakeCoreStep.select => client.select('proxy', 'node-alpha'),
              FakeCoreStep.urlTest =>
                client.urlTest('node-alpha', Uri.parse('http://x/')),
              FakeCoreStep.proxies => client.proxies(),
            };

        await expectLater(
          call(),
          throwsA(isA<CoreClientException>()),
          reason: '$step did not fail',
        );
      }
    });

    test('calls that need a tunnel fail without one', () async {
      final client = build();
      addTearDown(client.dispose);

      await expectLater(
        client.select('proxy', 'node-alpha'),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const HelperUnavailableFailure(),
          ),
        ),
      );
    });
  });

  group('FakeCoreClient proxies and select', () {
    test('a stopped core reports no groups instead of failing', () async {
      final client = build();
      addTearDown(client.dispose);

      expect(await client.proxies(), isEmpty);
    });

    test('select moves the group and the reported node', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      await client.select('proxy', 'node-beta');

      final groups = await client.proxies();
      expect(groups.single.now, 'node-beta');
      expect(
        (client.currentStatus as TunnelConnected).nodeId,
        'node-beta',
      );
    });

    test('select refuses a tag the group does not have', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      await expectLater(
        client.select('proxy', 'node-nowhere'),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            isA<ConfigInvalidFailure>(),
          ),
        ),
      );
    });
  });

  group('FakeCoreClient urlTest', () {
    test('answers the configured latency', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      expect(
        await client.urlTest('node-alpha', Uri.parse('http://x/')),
        const Duration(milliseconds: 137),
      );
    });

    test('a node told to time out answers null, which is not a failure',
        () async {
      final client = build()..setLatency('node-beta', null);
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      expect(await client.urlTest('node-beta', Uri.parse('http://x/')), isNull);
    });
  });

  group('FakeCoreClient synthetic data', () {
    test('emits traffic with monotonic totals while connected', () async {
      final client = build();
      addTearDown(client.dispose);
      final samples = client.traffic.take(3).toList().timeout(
            const Duration(seconds: 2),
          );

      await client.start(config);
      final seen = await samples;

      expect(seen, hasLength(3));
      expect(seen[0].uplinkTotal, lessThan(seen[1].uplinkTotal));
      expect(seen[1].downlinkTotal, lessThan(seen[2].downlinkTotal));
      expect(seen.every((sample) => sample.rate > 0), isTrue);
    });

    test('the traffic series is reproducible for a given seed', () async {
      Future<List<int>> run() async {
        final client = FakeCoreClient(
          startDelay: const Duration(milliseconds: 5),
          checkDelay: const Duration(milliseconds: 5),
          tick: const Duration(milliseconds: 5),
        );
        addTearDown(client.dispose);
        final samples = client.traffic.take(3).toList().timeout(
              const Duration(seconds: 2),
            );
        await client.start(config);
        return (await samples).map((sample) => sample.uplink).toList();
      }

      expect(await run(), await run());
    });

    test('emits log lines while connected', () async {
      final client = build();
      addTearDown(client.dispose);
      final lines = client.logs.take(2).toList().timeout(
            const Duration(seconds: 2),
          );

      await client.start(config);

      expect(await lines, hasLength(2));
    });

    test('emits connection snapshots that always carry a rule', () async {
      final client = build();
      addTearDown(client.dispose);
      final snapshots = client.connections.take(1).toList().timeout(
            const Duration(seconds: 2),
          );

      await client.start(config);
      final snapshot = (await snapshots).single;

      expect(snapshot, isNotEmpty);
      expect(snapshot.every((row) => row.rule.isNotEmpty), isTrue);
      expect(snapshot.map((row) => row.id).toSet(), hasLength(snapshot.length));
    });

    test('stops emitting once the tunnel is down', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await client.traffic.first.timeout(const Duration(seconds: 2));
      await client.stop();

      var ticks = 0;
      final subscription = client.traffic.listen((_) => ticks++);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(ticks, 0);
    });
  });

  group('FakeCoreClient lifecycle', () {
    test('reset rewinds to idle', () async {
      final client = build();
      addTearDown(client.dispose);
      await client.start(config);
      await settled(client);

      client.reset();

      expect(client.currentStatus, isA<TunnelIdle>());
      expect(client.isRunning, isFalse);
      expect(client.startCalls, 0);
    });

    test('dispose is idempotent', () async {
      final client = build();
      await client.dispose();

      await expectLater(client.dispose(), completes);
    });
  });
}
