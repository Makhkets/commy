import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/app_visibility.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// A fake core whose connection stream the test holds, so it can see who is
/// still listening.
class _WatchedCore extends FakeCoreClient {
  final StreamController<List<ConnectionInfo>> source =
      StreamController<List<ConnectionInfo>>.broadcast();

  @override
  Stream<List<ConnectionInfo>> get connections => source.stream;
}

/// What a diagnostics screen costs once the user has left it.
///
/// Riverpod does not cancel a kept provider's stream when its last listener
/// goes; it pauses it, and a paused subscription queues whatever still
/// arrives. A screen visited once used to keep its stream going for the rest
/// of the process, into a queue nobody read.
void main() {
  test('a log screen left behind queues nothing', () async {
    final harness = CommyTestHarness();
    final container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });

    // The screen opens, and is left.
    final screen = container.listen(logLinesProvider, (_, __) {});
    await container.read(logLinesProvider.future);
    screen.close();
    await pumpEventQueue();

    // A connected core goes on writing while the user is elsewhere.
    for (var i = 0; i < 50; i++) {
      await harness.logRepository.append(
        LogLine(
          level: LogLevel.info,
          message: 'outbound connection $i',
          at: CommyTestHarness.now,
        ),
      );
    }
    await pumpEventQueue();

    // Back on the screen: the log as it is now, not fifty views replayed.
    final views = <int>[];
    final again = container.listen<AsyncValue<List<LogLine>>>(
      logLinesProvider,
      (_, next) => views.add(next.value?.length ?? -1),
    );
    addTearDown(again.close);
    await pumpEventQueue();

    expect(views, hasLength(lessThanOrEqualTo(2)));
    expect(container.read(logLinesProvider).value, hasLength(50));
  });

  test('leaving the connections tab lets go of the stream', () async {
    final core = _WatchedCore();
    final container = ProviderContainer(
      overrides: <Override>[coreClientProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await core.source.close();
      await core.dispose();
    });

    final screen = container.listen(connectionsProvider, (_, __) {});
    await pumpEventQueue();
    expect(core.source.hasListener, isTrue);

    screen.close();
    await pumpEventQueue();

    // Cancelled, not paused: on Android the channel's cancel is what stops
    // the native side sending the table once a second.
    expect(core.source.hasListener, isFalse);
  });

  test('the connections tab lets go while the app is hidden', () async {
    // The tab on top of the stack is not left when the app goes into the
    // background, so nothing paused it, and the table went on arriving once
    // a second for a screen nobody could see.
    final core = _WatchedCore();
    final container = ProviderContainer(
      overrides: <Override>[coreClientProvider.overrideWithValue(core)],
    );
    addTearDown(() async {
      container.dispose();
      await core.source.close();
      await core.dispose();
    });
    final screen = container.listen(connectionsProvider, (_, __) {});
    addTearDown(screen.close);
    await pumpEventQueue();
    core.source.add(const <ConnectionInfo>[]);
    await pumpEventQueue();

    container.read(appVisibleProvider.notifier).hide();
    await pumpEventQueue();
    expect(core.source.hasListener, isFalse);

    container.read(appVisibleProvider.notifier).show();
    await pumpEventQueue();
    expect(core.source.hasListener, isTrue);
    // What was on screen stays there until the table comes back.
    expect(container.read(connectionsProvider).value, isEmpty);
  });

  test('the log screen lets go while the app is hidden', () async {
    final harness = CommyTestHarness();
    final container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final views = <int>[];
    final screen = container.listen<AsyncValue<List<LogLine>>>(
      logLinesProvider,
      (_, next) {
        if (next.hasValue && !next.isLoading) {
          views.add(next.value!.length);
        }
      },
    );
    addTearDown(screen.close);
    await container.read(logLinesProvider.future);
    views.clear();

    container.read(appVisibleProvider.notifier).hide();
    await pumpEventQueue();
    for (var i = 0; i < 20; i++) {
      await harness.logRepository.append(
        LogLine(
          level: LogLevel.info,
          message: 'outbound connection $i',
          at: CommyTestHarness.now,
        ),
      );
    }
    await pumpEventQueue();
    expect(views, isEmpty);

    container.read(appVisibleProvider.notifier).show();
    await pumpEventQueue();
    expect(views, equals(<int>[20]));
  });
}
