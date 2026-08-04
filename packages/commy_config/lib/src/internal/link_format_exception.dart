/// Thrown inside the parsers when one link cannot be understood.
///
/// It never escapes the package: [reason] is what ends up in the
/// `ImportFailure` the user reads, so it is written as a sentence a person
/// can act on, not as a stack trace.
class LinkFormatException implements Exception {
  /// Creates the exception with a human readable [reason].
  const LinkFormatException(this.reason);

  /// Why the link could not be turned into a node.
  final String reason;

  @override
  String toString() => 'LinkFormatException($reason)';
}
