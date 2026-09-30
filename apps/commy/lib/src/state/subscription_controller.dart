import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/failure_log.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Refreshing, editing and deleting subscriptions.
///
/// The busy flag is per subscription id rather than a single boolean: two
/// panels refreshing at once must spin two spinners, not one.
final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, SubscriptionActionState>(
  SubscriptionController.new,
);

/// What the subscription list is currently doing.
@immutable
class SubscriptionActionState {
  /// Creates the state.
  const SubscriptionActionState({
    this.refreshingId,
    this.failure,
    this.importedCount,
  });

  /// Nothing in flight.
  static const SubscriptionActionState idle = SubscriptionActionState();

  /// The subscription being refreshed right now, if any.
  final String? refreshingId;

  /// What the last action failed with.
  final CommyFailure? failure;

  /// How many servers the last refresh brought in, for the toast.
  final int? importedCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionActionState &&
          other.refreshingId == refreshingId &&
          other.failure == failure &&
          other.importedCount == importedCount;

  @override
  int get hashCode => Object.hash(refreshingId, failure, importedCount);

  @override
  String toString() => 'SubscriptionActionState($refreshingId, $failure)';
}

/// Actions on a stored subscription.
class SubscriptionController extends Notifier<SubscriptionActionState> {
  /// Tag on the log lines this controller writes.
  static const String logTag = 'subscription';

  @override
  SubscriptionActionState build() => SubscriptionActionState.idle;

  /// Re-downloads [id] and replaces its servers.
  ///
  /// Goes **around** the tunnel by default: a refresh that needed the tunnel
  /// would be impossible right after a reinstall, which is when it is needed
  /// most (docs/05-ux-flows.md, scenario 3).
  ///
  /// Returns whether the download ran and succeeded. A refresh declined
  /// because another one is already in flight returns false without touching
  /// state, so a caller cannot mistake "not now" for "done".
  Future<bool> refresh(String id) async {
    if (state.refreshingId != null) {
      return false;
    }
    state = SubscriptionActionState(refreshingId: id);
    final result = await ref.read(updateSubscriptionUseCaseProvider)(
      subscriptionId: id,
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'subscription refresh failed: ${FailureLog.describe(failure)}',
            tag: logTag,
          );
      state = SubscriptionActionState(failure: failure);
      return false;
    }
    state = SubscriptionActionState(
      importedCount: result.valueOrNull?.importedCount ?? 0,
    );
    return true;
  }

  /// Folds or unfolds the card.
  Future<void> setCollapsed({required String id, required bool isCollapsed}) {
    return _run(
      () => ref.read(subscriptionRepositoryProvider).setCollapsed(
            id: id,
            isCollapsed: isCollapsed,
          ),
    );
  }

  /// Turns automatic refreshing on or off.
  Future<void> setAutoUpdate(Subscription subscription, {required bool value}) {
    return _edit(
      subscription.id,
      (current) => current.copyWith(autoUpdate: value),
    );
  }

  /// Sets how often the subscription is re-downloaded, in whole hours.
  ///
  /// Writes the figure even while [Subscription.autoUpdate] is off, so that
  /// turning auto refresh back on keeps the interval the user picked instead
  /// of quietly falling back to the panel's suggestion.
  Future<void> setUpdateIntervalHours(Subscription subscription, int hours) {
    if (hours <= 0) {
      return Future<void>.value();
    }
    return _edit(
      subscription.id,
      (current) => current.copyWith(updateIntervalHours: hours),
    );
  }

  /// Sets the User-Agent the subscription is fetched with; `null` or an
  /// empty string goes back to the default.
  ///
  /// The next refresh uses it, and so does adding the same URL again.
  Future<void> setUserAgent(Subscription subscription, String? userAgent) {
    final trimmed = userAgent?.trim() ?? '';
    return _edit(
      subscription.id,
      (current) => current.copyWith(
        userAgentOverride: trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  /// Renames the subscription.
  Future<void> rename(Subscription subscription, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future<void>.value();
    }
    return _edit(
      subscription.id,
      (current) => current.copyWith(name: trimmed),
    );
  }

  /// Deletes the subscription, its servers and their credentials.
  ///
  /// When the selected server is one of them, the tunnel goes down first and
  /// the selection is cleared, as deleting that one server does
  /// (`NodeController.delete`). Otherwise the core went on running through a
  /// server the list no longer had, and the next connect failed on a
  /// selection that pointed at nothing.
  Future<void> delete(String id) async {
    // Listened to while awaited: a provider nobody listens to is paused, and
    // its `future` would never arrive.
    final selection = ref.listen(selectedNodeIdProvider, (_, __) {});
    final servers = ref.listen(nodesProvider, (_, __) {});
    try {
      final selectedId = await ref.read(selectedNodeIdProvider.future);
      final nodes = await ref.read(nodesProvider.future);
      final owned = selectedId != null &&
          nodes.any(
            (node) => node.id == selectedId && node.subscriptionId == id,
          );
      if (owned) {
        if (_isTunnelUp()) {
          await ref.read(tunnelControllerProvider.notifier).disconnect();
        }
        await ref.read(selectedNodeIdProvider.notifier).select(null);
      }
    } on Object {
      // A selection that cannot be read is left to the connect, which checks
      // it against the servers there are.
    } finally {
      selection.close();
      servers.close();
    }
    await _run(
      () => ref.read(subscriptionRepositoryProvider).deleteById(id),
    );
  }

  bool _isTunnelUp() => switch (ref.read(coreStatusProvider).value) {
        TunnelConnected() || TunnelChecking() || TunnelStarting() => true,
        _ => false,
      };

  /// Copies the subscription URL to the clipboard.
  ///
  /// The URL carries an access token, so this is a deliberate, user-initiated
  /// move of a secret out of the keystore and nothing does it implicitly.
  ///
  /// Returns whether it landed, so the caller can say so: a clipboard write
  /// that failed looks exactly like one that worked until the user pastes.
  Future<bool> copyLink(Subscription subscription) async {
    final result =
        await ref.read(clipboardProvider).write(subscription.url.toString());
    final failure = result.failureOrNull;
    _settle(failure);
    return failure == null;
  }

  /// Clears the last outcome once it has been shown.
  void clear() => _settle(null);

  /// Writes [change] over the subscription as it is stored now.
  ///
  /// Not over the copy the card or its menu was built from: a menu opened
  /// before a refresh landed holds the old quota, title and announcement,
  /// and writing that copy back with a new name undid the refresh. The
  /// refresh itself reads the fresh row before it writes, for the same
  /// reason the other way round. A subscription deleted in the meantime is
  /// left deleted.
  Future<void> _edit(
    String id,
    Subscription Function(Subscription current) change,
  ) {
    return _run(() async {
      final repository = ref.read(subscriptionRepositoryProvider);
      switch (await repository.findById(id)) {
        case Ok(value: final Subscription current):
          return repository.upsert(change(current));
        case Ok():
          return const Ok<void, CommyFailure>(null);
        case Err(:final failure):
          return Err<void, CommyFailure>(failure);
      }
    });
  }

  Future<void> _run(
    Future<Result<void, CommyFailure>> Function() action,
  ) async {
    final result = await action();
    _settle(result.failureOrNull);
  }

  /// Records how a menu action ended — unless a refresh is still running.
  ///
  /// A refresh owns the state until it ends. The card's spinner and the
  /// one-at-a-time guard in [refresh] both read `refreshingId`, and a caller
  /// tells a declined refresh from a failed one by a null `failure`. Writing
  /// here used to clear the id, so collapsing a card mid-download stopped its
  /// spinner and let a second refresh of the same panel start beside the
  /// first. The refresh writes its own outcome the moment it ends.
  void _settle(CommyFailure? failure) {
    if (state.refreshingId != null) {
      return;
    }
    state = failure == null
        ? SubscriptionActionState.idle
        : SubscriptionActionState(failure: failure);
  }
}
