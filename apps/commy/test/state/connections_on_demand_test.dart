import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod's default export set.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// On Android the core streams connections only while the event channel has
/// a listener. The app has to stop listening when the screen goes, or the
/// core keeps streaming for nobody.
void main() {
  late _ListenedCore core;
  late ProviderContainer container;

  setUp(() {
    core = _ListenedCore();
    container = ProviderContainer(
      overrides: <Override>[coreClientProvider.overrideWithValue(core)],
    );
  });

  tearDown(() async {
    container.dispose();
    await core.close();
  });

  test('the core is listened to while the screen watches', () async {
    container.listen(connectionsProvider, (_, __) {});
    await pumpEventQueue();

    expect(core.isListened, isTrue);
  });

  test('leaving the screen stops listening to the core', () async {
    final screen = container.listen(connectionsProvider, (_, __) {});
    await pumpEventQueue();

    screen.close();
    await pumpEventQueue();

    expect(core.isListened, isFalse);
  });
}

/// A fake core that can say whether its connections stream has a listener.
class _ListenedCore extends FakeCoreClient {
  final StreamController<List<ConnectionInfo>> _rows =
      StreamController<List<ConnectionInfo>>.broadcast();

  bool get isListened => _rows.hasListener;

  @override
  Stream<List<ConnectionInfo>> get connections => _rows.stream;

  Future<void> close() async {
    await _rows.close();
    await dispose();
  }
}
