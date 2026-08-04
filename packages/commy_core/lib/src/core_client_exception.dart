import 'package:commy_domain/commy_domain.dart';

/// What every `CoreClient` throws, carrying an already typed failure.
///
/// The domain port is the one place that is allowed to throw: it sits directly
/// on a channel or an FFI call, and use cases wrap it. The classification,
/// though, only exists here — the platform side knows whether the user
/// declined the VPN prompt, the layers above do not. So the failure travels
/// inside the exception rather than being reconstructed from a string later.
///
/// Callers that want the typed failure back out of a caught object use
/// [failureOf].
class CoreClientException implements Exception {
  /// Wraps [failure], optionally keeping the [cause] it came from.
  const CoreClientException(this.failure, {this.cause, this.stackTrace});

  /// The typed failure, ready for the UI.
  final CommyFailure failure;

  /// The platform error this was built from, when there was one.
  final Object? cause;

  /// Where the platform error came from.
  final StackTrace? stackTrace;

  /// Digs a [CommyFailure] out of anything that was caught.
  ///
  /// Returns the carried failure for a [CoreClientException], unwraps the one
  /// hiding inside an `UnknownFailure` produced by a use case, and falls back
  /// to `UnknownFailure` for everything else. This is what lets a use case
  /// keep its blanket `catch` without flattening `permissionDenied` into
  /// `unknown` by the time it reaches a screen.
  static CommyFailure failureOf(Object error, [StackTrace? stackTrace]) {
    if (error is CoreClientException) {
      return error.failure;
    }
    if (error is UnknownFailure) {
      return failureOf(error.cause, error.stackTrace);
    }
    if (error is CommyFailure) {
      return error;
    }
    return UnknownFailure(error, stackTrace ?? StackTrace.empty);
  }

  @override
  String toString() => 'CoreClientException($failure)';
}
