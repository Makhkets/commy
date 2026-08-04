import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// Turns a [CommyFailure] into the three things an error screen owes the user.
///
/// docs/05-ux-flows.md is blunt about it: "Ошибка без пути к диагностике —
/// недоделанная ошибка". So every variant here carries a sentence in plain
/// language, a labelled action, and — unless the action already goes there —
/// a route to the logs.
///
/// The mapping keys off [CommyFailure.code], which is documented as stable, so
/// a translation never breaks because a class was renamed.
@immutable
class FailureText {
  /// Creates the description.
  const FailureText({
    required this.message,
    required this.actionLabel,
    required this.action,
    required this.retryable,
  });

  /// Describes [failure] in the currently selected language.
  factory FailureText.of(CommyFailure failure, Translations t) {
    final errors = t.error;
    return switch (failure) {
      SubscriptionUnreachableFailure() => FailureText(
          message: errors.subscriptionUnreachable.message,
          actionLabel: errors.subscriptionUnreachable.action,
          action: FailureAction.retry,
          retryable: failure.retryable,
        ),
      SubscriptionMalformedFailure() => FailureText(
          message: errors.subscriptionMalformed.message,
          actionLabel: errors.subscriptionMalformed.action,
          action: FailureAction.openLogs,
          retryable: failure.retryable,
        ),
      UnsupportedProtocolFailure(:final scheme) => FailureText(
          message: errors.unsupportedProtocol.message(scheme: scheme),
          actionLabel: errors.unsupportedProtocol.action,
          action: FailureAction.openLogs,
          retryable: failure.retryable,
        ),
      ConfigInvalidFailure() => FailureText(
          message: errors.configInvalid.message,
          actionLabel: errors.configInvalid.action,
          action: FailureAction.openConfig,
          retryable: failure.retryable,
        ),
      PermissionDeniedFailure() => FailureText(
          message: errors.permissionDenied.message,
          actionLabel: errors.permissionDenied.action,
          action: FailureAction.retry,
          retryable: failure.retryable,
        ),
      HelperUnavailableFailure() => FailureText(
          message: errors.helperUnavailable.message,
          actionLabel: errors.helperUnavailable.action,
          action: FailureAction.retry,
          retryable: failure.retryable,
        ),
      CoreCrashedFailure() => FailureText(
          message: errors.coreCrashed.message,
          actionLabel: errors.coreCrashed.action,
          action: FailureAction.openLogs,
          retryable: failure.retryable,
        ),
      StorageFailure() => FailureText(
          message: errors.storage.message,
          actionLabel: errors.storage.action,
          action: FailureAction.retry,
          retryable: failure.retryable,
        ),
      UnknownFailure() => FailureText(
          message: errors.unknown.message,
          actionLabel: errors.unknown.action,
          action: FailureAction.openLogs,
          retryable: failure.retryable,
        ),
    };
  }

  /// One sentence, in the user's language, with no jargon and no stack trace.
  final String message;

  /// What the button next to [message] says.
  final String actionLabel;

  /// What the button next to [message] does.
  final FailureAction action;

  /// Whether repeating the same call can plausibly work.
  final bool retryable;

  /// Whether a second, quieter "open the logs" link is still needed.
  ///
  /// False only when the primary action already lands in diagnostics — two
  /// buttons to the same screen is noise.
  bool get needsLogRoute => action != FailureAction.openLogs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FailureText &&
          other.message == message &&
          other.actionLabel == actionLabel &&
          other.action == action &&
          other.retryable == retryable;

  @override
  int get hashCode => Object.hash(message, actionLabel, action, retryable);

  @override
  String toString() => 'FailureText($message, ${action.name})';
}

/// What the button on an error banner does.
enum FailureAction {
  /// Call the same thing again.
  retry,

  /// Go to the log tab.
  openLogs,

  /// Go to the generated-config tab.
  openConfig;

  /// The route this action navigates to, or `null` when it retries in place.
  String? get route => switch (this) {
        FailureAction.retry => null,
        FailureAction.openLogs => AppRoutes.diagnosticsLogs,
        FailureAction.openConfig => AppRoutes.diagnosticsConfig,
      };
}
