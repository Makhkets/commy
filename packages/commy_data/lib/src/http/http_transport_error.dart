import 'package:flutter/foundation.dart' show immutable;

/// Why an HTTP request did not produce a usable answer.
///
/// `CommyFailure.subscriptionUnreachable` carries an opaque `cause`; this is
/// what goes in there. A typed cause beats a raw `DioException` for two
/// reasons: the UI can key an explanation off [kind] instead of parsing a
/// message, and `toString` is guaranteed never to print the URL — a
/// `DioException` prints it in full, token and all, the moment anything logs
/// the failure (rule R3).
@immutable
class HttpTransportError {
  /// Creates a transport error.
  const HttpTransportError({
    required this.kind,
    this.statusCode,
    this.detail,
  });

  /// The request never reached the server.
  static const String kindTimeout = 'timeout';

  /// DNS, TCP or TLS failed before any HTTP happened.
  static const String kindConnection = 'connection';

  /// The certificate did not validate.
  static const String kindCertificate = 'certificate';

  /// The server answered, but not with a success status.
  static const String kindStatus = 'status';

  /// The request was cancelled from our side.
  static const String kindCancelled = 'cancelled';

  /// Anything the client could not classify.
  static const String kindUnknown = 'unknown';

  /// The body was larger than we are willing to hold in memory.
  static const String kindTooLarge = 'too_large';

  /// One of the `kind*` constants.
  final String kind;

  /// HTTP status, when there was one.
  final int? statusCode;

  /// Short technical detail. Never a URL, never a credential.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpTransportError &&
          other.kind == kind &&
          other.statusCode == statusCode &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, statusCode, detail);

  @override
  String toString() {
    final status = statusCode == null ? '' : ' $statusCode';
    final extra = detail == null || detail!.isEmpty ? '' : ': $detail';
    return 'HttpTransportError($kind$status$extra)';
  }
}
