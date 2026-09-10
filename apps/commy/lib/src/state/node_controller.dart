import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Actions on a single stored server: share it, or throw it away.
///
/// Selecting and measuring live in `TunnelController` because both talk to
/// the running core. These two never do, which is why they are not there.
final nodeControllerProvider =
    NotifierProvider<NodeController, NodeActionState>(NodeController.new);

/// What the last node action produced.
@immutable
class NodeActionState {
  /// Creates the state.
  const NodeActionState({this.failure});

  /// Nothing has failed.
  static const NodeActionState idle = NodeActionState();

  /// What the last action failed with, if it did.
  final CommyFailure? failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeActionState && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'NodeActionState($failure)';
}

/// Copying and deleting a server.
class NodeController extends Notifier<NodeActionState> {
  /// Tag on the log lines this controller writes.
  static const String logTag = 'node';

  @override
  NodeActionState build() => NodeActionState.idle;

  /// Renders [node] back into a share link and puts it on the clipboard.
  ///
  /// Returns whether the link made it there. Not every protocol has a link
  /// format, and a copy that silently put nothing on the clipboard would be
  /// indistinguishable from one that worked until the user pasted it.
  Future<bool> copyLink(ProxyNode node) async {
    final rendered = ref.read(nodeLinkExporterProvider).toLink(node);
    final link = rendered.valueOrNull;
    if (link == null) {
      state = NodeActionState(failure: rendered.failureOrNull);
      return false;
    }
    final written = await ref.read(clipboardProvider).write(link);
    final failure = written.failureOrNull;
    if (failure != null) {
      state = NodeActionState(failure: failure);
      return false;
    }
    state = NodeActionState.idle;
    return true;
  }

  /// Deletes [node], taking the tunnel down first when it is the live one.
  ///
  /// The order matters. Stopping after the row is gone would leave the core
  /// running on an outbound nothing on screen can name, and clearing the
  /// selection after the delete would leave one frame pointing at a server
  /// that no longer exists.
  Future<void> delete(ProxyNode node) async {
    // Awaited, not read: `selectedNodeIdProvider` reads storage on first
    // build, and its synchronous value is null until that lands. Reading it
    // instead would silently skip both steps below on a cold start and leave
    // the settings pointing at a row that no longer exists.
    final selectedId = await ref.read(selectedNodeIdProvider.future);
    if (selectedId == node.id) {
      if (_isTunnelUp()) {
        await ref.read(tunnelControllerProvider.notifier).disconnect();
      }
      await ref.read(selectedNodeIdProvider.notifier).select(null);
    }
    final result = await ref.read(nodeRepositoryProvider).deleteById(node.id);
    final failure = result.failureOrNull;
    if (failure != null) {
      ref.read(appLoggerProvider).warn(
            'node delete failed: ${failure.code}',
            tag: logTag,
          );
    }
    state = failure == null
        ? NodeActionState.idle
        : NodeActionState(failure: failure);
  }

  /// Whether traffic is going through [node] right now.
  ///
  /// Synchronous because the confirmation sheet needs an answer while it is
  /// being built. By then the selection has long since been read — the list
  /// the menu was opened from watches it — so the loading case cannot be the
  /// one on screen.
  bool isLive(ProxyNode node) {
    if (ref.read(selectedNodeIdProvider).value != node.id) {
      return false;
    }
    return _isTunnelUp();
  }

  bool _isTunnelUp() {
    return switch (ref.read(coreStatusProvider).value) {
      TunnelConnected() || TunnelChecking() || TunnelStarting() => true,
      _ => false,
    };
  }

  /// Clears the last failure once it has been shown.
  void clear() => state = NodeActionState.idle;
}
