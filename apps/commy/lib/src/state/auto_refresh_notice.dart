import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the automatic subscription refresh has to say, until it is said.
///
/// The scheduler runs from the root with no screen and no `BuildContext`, so
/// it cannot put a toast up itself. It writes here instead, and `NoticeHost`
/// shows the notice and clears it — the pattern `TunnelNotice` set.
///
/// A refresh from the card's own button never comes through here: that one
/// is answered by the card, and saying it twice would be one toast
/// overwriting its twin.
final autoRefreshNoticeProvider =
    NotifierProvider<AutoRefreshNotices, AutoRefreshNotice?>(
  AutoRefreshNotices.new,
);

/// One automatic refresh, finished.
@immutable
class AutoRefreshNotice {
  /// The subscription called [name] was refreshed and holds [count] servers.
  const AutoRefreshNotice.refreshed({
    required this.name,
    required int this.count,
  }) : failure = null;

  /// The subscription called [name] could not be refreshed.
  const AutoRefreshNotice.failed({
    required this.name,
    required CommyFailure this.failure,
  }) : count = null;

  /// The subscription's name, as its card shows it.
  ///
  /// Never its URL: that carries the access token (rule R3).
  final String name;

  /// How many servers the refresh left, when it worked.
  final int? count;

  /// What stopped it, when it did not.
  final CommyFailure? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoRefreshNotice &&
          other.name == name &&
          other.count == count &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(name, count, failure);

  @override
  String toString() => failure == null
      ? 'AutoRefreshNotice.refreshed($count)'
      : 'AutoRefreshNotice.failed(${failure?.code})';
}

/// Holds the latest [AutoRefreshNotice] until it has been shown.
class AutoRefreshNotices extends Notifier<AutoRefreshNotice?> {
  @override
  AutoRefreshNotice? build() => null;

  /// Says the subscription called [name] now holds [count] servers.
  void refreshed({required String name, required int count}) =>
      state = AutoRefreshNotice.refreshed(name: name, count: count);

  /// Says the subscription called [name] could not be refreshed.
  void failed({required String name, required CommyFailure failure}) =>
      state = AutoRefreshNotice.failed(name: name, failure: failure);

  /// Drops the notice once it has been shown.
  void clear() => state = null;
}
