/// Thrown when a payload from the core cannot be read as the protocol says.
///
/// It never escapes `commy_core`. A malformed event is logged and dropped —
/// one bad log line must not tear down the stream that carries the tunnel
/// state. A malformed *method result*, on the other hand, is turned into a
/// failure, because the caller is waiting for an answer.
class WireFormatException implements Exception {
  /// Creates the exception for [what], caused by [cause].
  const WireFormatException(this.what, [this.cause]);

  /// Which payload could not be read, in words: `'/traffic event'`.
  final String what;

  /// The underlying decoding error, when there was one.
  final Object? cause;

  @override
  String toString() {
    final tail = cause == null ? '' : ': $cause';
    return 'WireFormatException($what$tail)';
  }
}
