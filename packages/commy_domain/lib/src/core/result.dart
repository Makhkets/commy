/// Outcome of an operation that either produced a value or failed.
///
/// The domain never throws across a layer boundary. Adapters catch their own
/// exceptions at the edge (I/O, FFI, channels, HTTP) and hand back an `Err`
/// carrying a typed failure. Use cases return `Result` and nothing else.
///
/// ```dart
/// final result = await connectUseCase(nodeId: id);
/// final label = result.fold(
///   (_) => 'connected',
///   (failure) => failure.code,
/// );
/// ```
sealed class Result<T, F> {
  /// Base constructor. Construct [Ok] or [Err] instead.
  const Result();

  /// Whether this result carries a value.
  bool get isOk => this is Ok<T, F>;

  /// Whether this result carries a failure.
  bool get isErr => this is Err<T, F>;

  /// The value, or `null` when this result is an [Err].
  T? get valueOrNull => switch (this) {
        Ok<T, F>(:final value) => value,
        Err<T, F>() => null,
      };

  /// The failure, or `null` when this result is an [Ok].
  F? get failureOrNull => switch (this) {
        Ok<T, F>() => null,
        Err<T, F>(:final failure) => failure,
      };

  /// Collapses both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok<T, F>(:final value) => onOk(value),
        Err<T, F>(:final failure) => onErr(failure),
      };

  /// Transforms the value, leaving a failure untouched.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T, F>(:final value) => Ok<R, F>(transform(value)),
        Err<T, F>(:final failure) => Err<R, F>(failure),
      };

  /// Transforms the failure, leaving a value untouched.
  Result<T, G> mapErr<G>(G Function(F failure) transform) => switch (this) {
        Ok<T, F>(:final value) => Ok<T, G>(value),
        Err<T, F>(:final failure) => Err<T, G>(transform(failure)),
      };

  /// Chains another fallible step onto a successful result.
  Result<R, F> flatMap<R>(Result<R, F> Function(T value) transform) =>
      switch (this) {
        Ok<T, F>(:final value) => transform(value),
        Err<T, F>(:final failure) => Err<R, F>(failure),
      };

  /// Returns the value, or what [orElse] makes out of the failure.
  T getOrElse(T Function(F failure) orElse) => switch (this) {
        Ok<T, F>(:final value) => value,
        Err<T, F>(:final failure) => orElse(failure),
      };
}

/// A [Result] that succeeded.
final class Ok<T, F> extends Result<T, F> {
  /// Wraps [value] as a success.
  const Ok(this.value);

  /// The produced value.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Ok($value)';
}

/// A [Result] that failed.
final class Err<T, F> extends Result<T, F> {
  /// Wraps [failure] as an error.
  const Err(this.failure);

  /// The reason the operation did not produce a value.
  final F failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'Err($failure)';
}
