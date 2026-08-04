import 'package:commy_domain/src/core/redaction.dart';

/// Everything that can go wrong, as a closed set.
///
/// Each variant carries the data needed to explain itself. The UI turns [code]
/// into a localised sentence through slang and pairs it with an action; a
/// message without an action is an unfinished error. [retryable] says whether
/// repeating the very same call can plausibly work.
///
/// The variant set mirrors docs/02-architecture.md, "Обработка ошибок".
sealed class CommyFailure {
  /// Base constructor. Construct one of the variants instead.
  const CommyFailure();

  /// The subscription server could not be reached at all.
  const factory CommyFailure.subscriptionUnreachable({
    required Uri url,
    required Object cause,
  }) = SubscriptionUnreachableFailure;

  /// The subscription answered, but the body made no sense.
  const factory CommyFailure.subscriptionMalformed(String detail) =
      SubscriptionMalformedFailure;

  /// A link used a scheme we do not implement.
  const factory CommyFailure.unsupportedProtocol(String scheme) =
      UnsupportedProtocolFailure;

  /// The generated core configuration did not pass validation.
  const factory CommyFailure.configInvalid(String detail) =
      ConfigInvalidFailure;

  /// The user declined the system VPN prompt.
  const factory CommyFailure.permissionDenied() = PermissionDeniedFailure;

  /// The privileged desktop helper or the tunnel service is not running.
  const factory CommyFailure.helperUnavailable() = HelperUnavailableFailure;

  /// The core died; the tail of its log is attached.
  const factory CommyFailure.coreCrashed(String log) = CoreCrashedFailure;

  /// The database or the secure storage refused to cooperate.
  const factory CommyFailure.storage(Object cause) = StorageFailure;

  /// Anything we failed to classify. Always a bug worth reading.
  const factory CommyFailure.unknown(Object cause, StackTrace stackTrace) =
      UnknownFailure;

  /// Stable machine key for the i18n lookup.
  ///
  /// Never change an existing value: translations key off it.
  String get code;

  /// Whether repeating the same operation can plausibly succeed.
  bool get retryable;
}

/// The subscription host did not answer.
final class SubscriptionUnreachableFailure extends CommyFailure {
  /// Creates the failure for [url], caused by [cause].
  const SubscriptionUnreachableFailure({
    required this.url,
    required this.cause,
  });

  /// The subscription URL that was requested.
  ///
  /// Holds an access token. Never print it raw — use [Redact.uri].
  final Uri url;

  /// The underlying transport error.
  final Object cause;

  @override
  String get code => 'subscription_unreachable';

  @override
  bool get retryable => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionUnreachableFailure &&
          other.url == url &&
          other.cause == cause;

  @override
  int get hashCode => Object.hash(runtimeType, url, cause);

  @override
  String toString() =>
      'SubscriptionUnreachableFailure(${Redact.uri(url)}, $cause)';
}

/// The subscription body could not be understood.
final class SubscriptionMalformedFailure extends CommyFailure {
  /// Creates the failure with a human readable [detail].
  const SubscriptionMalformedFailure(this.detail);

  /// What exactly was wrong with the body.
  final String detail;

  @override
  String get code => 'subscription_malformed';

  @override
  bool get retryable => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionMalformedFailure && other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, detail);

  @override
  String toString() => 'SubscriptionMalformedFailure($detail)';
}

/// A link scheme we do not support.
final class UnsupportedProtocolFailure extends CommyFailure {
  /// Creates the failure for [scheme], without the `://` part.
  const UnsupportedProtocolFailure(this.scheme);

  /// The scheme as it appeared in the input.
  final String scheme;

  @override
  String get code => 'unsupported_protocol';

  @override
  bool get retryable => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnsupportedProtocolFailure && other.scheme == scheme;

  @override
  int get hashCode => Object.hash(runtimeType, scheme);

  @override
  String toString() => 'UnsupportedProtocolFailure($scheme)';
}

/// The configuration we built is not valid.
final class ConfigInvalidFailure extends CommyFailure {
  /// Creates the failure with a human readable [detail].
  const ConfigInvalidFailure(this.detail);

  /// What exactly is wrong with the configuration.
  final String detail;

  @override
  String get code => 'config_invalid';

  @override
  bool get retryable => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigInvalidFailure && other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, detail);

  @override
  String toString() => 'ConfigInvalidFailure($detail)';
}

/// The user declined the system VPN permission prompt.
final class PermissionDeniedFailure extends CommyFailure {
  /// Creates the failure.
  const PermissionDeniedFailure();

  @override
  String get code => 'permission_denied';

  /// Retryable: the prompt can be shown again, and usually should be.
  @override
  bool get retryable => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PermissionDeniedFailure;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'PermissionDeniedFailure()';
}

/// The privileged helper or tunnel service is not available.
final class HelperUnavailableFailure extends CommyFailure {
  /// Creates the failure.
  const HelperUnavailableFailure();

  @override
  String get code => 'helper_unavailable';

  /// Retryable: installing or starting the helper fixes it in place.
  @override
  bool get retryable => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is HelperUnavailableFailure;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'HelperUnavailableFailure()';
}

/// The core process died.
final class CoreCrashedFailure extends CommyFailure {
  /// Creates the failure with the tail of the core [log].
  const CoreCrashedFailure(this.log);

  /// Tail of the core log. Redact before showing it outside the app.
  final String log;

  @override
  String get code => 'core_crashed';

  @override
  bool get retryable => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoreCrashedFailure && other.log == log;

  @override
  int get hashCode => Object.hash(runtimeType, log);

  /// Deliberately omits the log body: it can contain server addresses.
  @override
  String toString() => 'CoreCrashedFailure(${log.length} chars)';
}

/// The database or the secure storage failed.
final class StorageFailure extends CommyFailure {
  /// Creates the failure caused by [cause].
  const StorageFailure(this.cause);

  /// The underlying storage error.
  final Object cause;

  @override
  String get code => 'storage';

  @override
  bool get retryable => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageFailure && other.cause == cause;

  @override
  int get hashCode => Object.hash(runtimeType, cause);

  @override
  String toString() => 'StorageFailure($cause)';
}

/// Something we did not classify. Every occurrence is worth investigating.
final class UnknownFailure extends CommyFailure {
  /// Creates the failure from [cause] and its [stackTrace].
  const UnknownFailure(this.cause, this.stackTrace);

  /// Whatever was caught.
  final Object cause;

  /// Where it was caught.
  final StackTrace stackTrace;

  @override
  String get code => 'unknown';

  @override
  bool get retryable => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownFailure &&
          other.cause == cause &&
          other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(runtimeType, cause, stackTrace);

  @override
  String toString() => 'UnknownFailure($cause)';
}
