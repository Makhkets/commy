import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
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
  Future<void> refresh(String id) async {
    if (state.refreshingId != null) {
      return;
    }
    state = SubscriptionActionState(refreshingId: id);
    final result = await ref.read(updateSubscriptionUseCaseProvider)(
      subscriptionId: id,
    );
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'subscription refresh failed: ${failure.code}',
            tag: logTag,
          );
      state = SubscriptionActionState(failure: failure);
      return;
    }
    state = SubscriptionActionState(
      importedCount: result.valueOrNull?.importedCount ?? 0,
    );
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
    return _run(
      () => ref
          .read(subscriptionRepositoryProvider)
          .upsert(subscription.copyWith(autoUpdate: value)),
    );
  }

  /// Renames the subscription.
  Future<void> rename(Subscription subscription, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future<void>.value();
    }
    return _run(
      () => ref
          .read(subscriptionRepositoryProvider)
          .upsert(subscription.copyWith(name: trimmed)),
    );
  }

  /// Deletes the subscription, its servers and their credentials.
  Future<void> delete(String id) {
    return _run(() => ref.read(subscriptionRepositoryProvider).deleteById(id));
  }

  /// Copies the subscription URL to the clipboard.
  ///
  /// The URL carries an access token, so this is a deliberate, user-initiated
  /// move of a secret out of the keystore and nothing does it implicitly.
  Future<void> copyLink(Subscription subscription) {
    return _run(
      () => ref.read(clipboardProvider).write(subscription.url.toString()),
    );
  }

  /// Clears the last outcome once it has been shown.
  void clear() => state = SubscriptionActionState.idle;

  Future<void> _run(
    Future<Result<void, CommyFailure>> Function() action,
  ) async {
    final result = await action();
    final failure = result.failureOrNull;
    state = failure == null
        ? SubscriptionActionState.idle
        : SubscriptionActionState(failure: failure);
  }
}
