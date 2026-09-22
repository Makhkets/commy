import 'dart:io';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy_data/commy_data.dart';
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
      // A panel that answered with 403 or 404 is not "not answering": it
      // answered, and it said no. The old single sentence sent the user to
      // check their connection when the thing to check is the subscription —
      // expired, revoked, or over its device limit, which is what a Remnawave
      // panel returns a 403 for. The status is already in the failure; only
      // the sentence was throwing it away.
      SubscriptionUnreachableFailure(
        cause: HttpTransportError(
          kind: HttpTransportError.kindStatus,
          statusCode: final int status,
        ),
      ) =>
        FailureText(
          message: errors.subscriptionRefused.message(status: status),
          actionLabel: errors.subscriptionRefused.action,
          action: FailureAction.retry,
          retryable: failure.retryable,
        ),
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
      // A file that could not be read is not a mystery, and it is the one
      // failure the user can fix without leaving the sheet: the pick worked,
      // the read threw. "Something went wrong" plus a trip to the logs was
      // hiding a sentence the app already had -- and hiding the obvious next
      // step, which is to choose another file.
      UnknownFailure(cause: FileSystemException()) => FailureText(
          message: t.import.file.unreadable,
          actionLabel: t.common.retry,
          action: FailureAction.retry,
          // Not [failure.retryable]: that answers "can the same call work
          // again", and the call this offers is a new pick, not the same one.
          retryable: true,
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
