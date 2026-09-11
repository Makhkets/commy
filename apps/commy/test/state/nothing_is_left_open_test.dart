import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod's default export set.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Queue item #17: what the app opens, the app closes.
///
/// Everything the composition root builds used to outlive it. The core client
/// kept its timers, the HTTP client kept its connection pool, the database
/// stayed open and the logger kept its stream — not because anybody decided
/// that, but because the only place a disposal could have been registered is a
/// provider body, and `overrideWithValue` replaces the body.
///
/// These tests pin the two halves of the fix: providers that build a resource
/// close it, and a resource built before the graph is *handed* to the graph
/// rather than pushed past it.
void main() {
  group('providers close what they build', () {
    // `flutter test` reports Android, where the factory hands back the real
    // client — and that one has nothing to release, so there is nothing to
    // watch. A platform with no tunnel yet gets the fake, which says out loud
    // when it has been closed.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('the core client is disposed with the scope', () async {
      final container = ProviderContainer();
      final core = container.read(coreClientProvider);
      expect(core, isA<FakeCoreClient>(), reason: 'no tunnel on this platform');

      container.dispose();
      await pumpEventQueue();

      expect((core as FakeCoreClient).isDisposed, isTrue);
    });

    test('disposing the client does not stop the tunnel', () async {
      // The distinction the port insists on: a client that goes away is a
      // window closing, not a user tapping disconnect. On Android the tunnel
      // is a foreground service and outlives this process on purpose.
      final container = ProviderContainer();
      final core = container.read(coreClientProvider) as FakeCoreClient;
      await core.start(const CoreConfig(<String, Object?>{}));

      container.dispose();
      await pumpEventQueue();

      expect(core.isRunning, isTrue);
      expect(core.stopCalls, 0);
    });

    test('the logger is disposed with the scope', () async {
      final container = ProviderContainer();
      final logger = container.read(appLoggerProvider);

      container.dispose();
      await pumpEventQueue();

      expect(logger.isDisposed, isTrue);
    });
  });

  group('ownedOverride', () {
    test('closes a value the graph was handed', () async {
      var closed = 0;
      ProviderContainer(
        overrides: <Override>[
          ownedOverride(_thing, const _Thing(), (_) async => closed++),
        ],
      )
        ..read(_thing)
        ..dispose();
      await pumpEventQueue();

      expect(closed, 1);
    });

    test('a value nobody read is never built, so never closed', () async {
      // Riverpod builds lazily, and that is the right behaviour here: a
      // resource the app never asked for was never opened either.
      var closed = 0;
      ProviderContainer(
        overrides: <Override>[
          ownedOverride(_thing, const _Thing(), (_) async => closed++),
        ],
      ).dispose();
      await pumpEventQueue();

      expect(closed, 0);
    });

    test('overrideWithValue, the thing it replaces, closes nothing', () async {
      // The defect itself, kept as a test so nobody quietly goes back to it:
      // an override that replaces the body leaves no place for `onDispose`.
      var disposals = 0;
      final counted = Provider<_Thing>((ref) {
        ref.onDispose(() => disposals++);
        return const _Thing();
      });
      ProviderContainer(
        overrides: <Override>[counted.overrideWithValue(const _Thing())],
      )
        ..read(counted)
        ..dispose();
      await pumpEventQueue();

      expect(disposals, 0);
    });
  });
}

/// A stand-in for anything with a `close()`.
class _Thing {
  const _Thing();
}

final _thing = Provider<_Thing>(
  (ref) => throw UnimplementedError('overridden in every test here'),
);
