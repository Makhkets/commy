/// Thrown inside the configuration builder when a node cannot be expressed.
///
/// It never escapes the package: [reason] becomes the detail of a
/// `ConfigInvalidFailure`, so it is written as a sentence a person can act on.
class ConfigBuildException implements Exception {
  /// Creates the exception with a human readable [reason].
  const ConfigBuildException(this.reason);

  /// Why the configuration could not be assembled.
  final String reason;

  @override
  String toString() => 'ConfigBuildException($reason)';
}
