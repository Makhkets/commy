import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

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
}
