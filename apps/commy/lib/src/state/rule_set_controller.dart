import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Downloading and deleting the geoip and geosite files. Exception E-2.
///
/// The whole of the exception is one method with one caller: `download`, from
/// a button. Nothing in this file runs on a timer, on a schedule, or on the
/// app coming up — a rule set that refreshed itself would turn a sanctioned
/// exception into traffic the user never asked for, which is rule R1.
final ruleSetControllerProvider =
    NotifierProvider<RuleSetController, RuleSetActionState>(
  RuleSetController.new,
);

/// What the rule sets screen is doing.
@immutable
class RuleSetActionState {
  /// Creates the state.
  const RuleSetActionState({this.downloadingTag, this.failure});

  /// Nothing in flight.
  static const RuleSetActionState idle = RuleSetActionState();

  /// The tag being downloaded right now, if any.
  final String? downloadingTag;

  /// What the last action failed with.
  final CommyFailure? failure;

  /// Whether a download is running.
  bool get isBusy => downloadingTag != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleSetActionState &&
          other.downloadingTag == downloadingTag &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(downloadingTag, failure);

  @override
  String toString() => 'RuleSetActionState($downloadingTag, $failure)';
}

/// Actions on the rule set files.
class RuleSetController extends Notifier<RuleSetActionState> {
  @override
  RuleSetActionState build() => RuleSetActionState.idle;

  /// Fetches [tag] from the configured source.
  ///
  /// Returns `false` when there was nothing to ask — no source configured, or
  /// a template that does not produce a URL — so the caller can tell "the
  /// user has switched this off" from "the mirror is down".
  Future<bool> download(String tag) async {
    if (state.isBusy) {
      return false;
    }
    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final url = settings.ruleSetUrl(tag);
    if (url == null) {
      return false;
    }

    state = RuleSetActionState(downloadingTag: tag);
    final result = await ref.read(ruleSetRepositoryProvider).download(
          tag: tag,
          from: url,
        );
    final failure = result.failureOrNull;
    state = RuleSetActionState(failure: failure);
    return failure == null;
  }

  /// Removes [tag] from disk.
  ///
  /// The rules that named it stay where they are and start being dropped
  /// again, with the warning on the routing screen saying why. Deleting the
  /// file is not the same as deleting the rule, and conflating the two would
  /// lose something the user wrote.
  Future<void> delete(String tag) async {
    final result = await ref.read(ruleSetRepositoryProvider).delete(tag);
    state = RuleSetActionState(failure: result.failureOrNull);
  }

  /// Clears the last failure once it has been shown.
  void clear() => state = RuleSetActionState.idle;
}
