import 'package:commy_domain/commy_domain.dart';

/// Turns a throwing storage operation into a [Result].
///
/// Everything below this package throws: sqlite, the platform keystore, JSON
/// decoding of a row that got corrupted. Nothing above it may
/// (docs/02-architecture.md, "Обработка ошибок"), so every repository method
/// funnels through here and hands back a typed failure instead.
abstract final class StorageGuard {
  /// Runs [body] and wraps whatever it throws into a [StorageFailure].
  ///
  /// A [StorageFailure] is the honest classification for this layer: the
  /// caller cannot tell a locked keychain from a corrupted row, and both mean
  /// the same thing to the user — the data did not survive.
  static Future<Result<T, CommyFailure>> run<T>(
    Future<T> Function() body,
  ) async {
    try {
      return Ok<T, CommyFailure>(await body());
    } on Object catch (error) {
      return Err<T, CommyFailure>(CommyFailure.storage(error));
    }
  }

  /// Synchronous twin of [run].
  static Result<T, CommyFailure> runSync<T>(T Function() body) {
    try {
      return Ok<T, CommyFailure>(body());
    } on Object catch (error) {
      return Err<T, CommyFailure>(CommyFailure.storage(error));
    }
  }

  /// [run] for an operation that produces nothing.
  ///
  /// Spelled out rather than inferred as `run<void>`: the domain writes a void
  /// success as `const Ok<void, CommyFailure>(null)`, and building that from a
  /// generic makes the analyser reason about a void expression for no gain.
  static Future<Result<void, CommyFailure>> runVoid(
    Future<void> Function() body,
  ) async {
    try {
      await body();
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error) {
      return Err<void, CommyFailure>(CommyFailure.storage(error));
    }
  }

  /// Synchronous twin of [runVoid].
  static Result<void, CommyFailure> runVoidSync(void Function() body) {
    try {
      body();
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error) {
      return Err<void, CommyFailure>(CommyFailure.storage(error));
    }
  }

  /// Runs [body], falling back to [orElse] when it throws.
  ///
  /// Used on the stream side, where there is no [Result] to return: a single
  /// unreadable row must not tear down a `watch()` that the whole UI hangs
  /// off. The row is replaced by the fallback and the stream keeps going.
  static T orElse<T>(T Function() body, T Function() orElse) {
    try {
      return body();
    } on Object catch (_) {
      return orElse();
    }
  }
}
