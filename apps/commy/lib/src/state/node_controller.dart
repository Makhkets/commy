import 'dart:async';

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
  ///
  /// On Auto the live one is the server the core picked, not the stored
  /// selection — see [_leaveAuto].
  Future<void> delete(ProxyNode node) async {
    // Awaited, not read: `selectedNodeIdProvider` reads storage on first
    // build, and its synchronous value is null until that lands. Reading it
    // instead would silently skip both steps below on a cold start and leave
    // the settings pointing at a row that no longer exists.
    final selectedId = await ref.read(selectedNodeIdProvider.future);
    final onAuto = ref.read(autoSelectedProvider);
    if (onAuto) {
      await _leaveAuto(node, selectedId);
    } else if (selectedId == node.id) {
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
    if (failure == null && onAuto && _isTunnelUp()) {
      await _reloadWithout(node.id);
    }
  }

  /// Takes a deleted server out of the running Auto group.
  ///
  /// Only the server Auto is on takes the tunnel down with it; any other
  /// stays a member of the core's urltest group, which keeps testing it and
  /// may well switch to it — traffic through a server the user deleted, that
  /// no row on screen can name. A reload builds the group afresh and keeps
  /// the TUN device up (R6). It waits for the list to lose the row first:
  /// read before that, the reload would build from the list it is fixing.
  Future<void> _reloadWithout(String id) async {
    final gone = Completer<void>();
    final watch = ref.listen<AsyncValue<List<ProxyNode>>>(
      nodesProvider,
      (_, next) {
        final nodes = next.value;
        if (nodes != null &&
            nodes.every((node) => node.id != id) &&
            !gone.isCompleted) {
          gone.complete();
        }
      },
      fireImmediately: true,
    );
    try {
      await gone.future.timeout(_listSettle);
    } on TimeoutException {
      ref.read(appLoggerProvider).warn(
            'deleted server still listed; Auto group not rebuilt',
            tag: logTag,
          );
      return;
    } finally {
      watch.close();
    }
    await ref.read(tunnelControllerProvider.notifier).reload();
  }

  /// How long [_reloadWithout] waits for the list to drop the deleted row.
  static const Duration _listSettle = Duration(seconds: 5);

  /// Auto's half of [delete].
  ///
  /// On Auto the core chooses, and the stored selection is only the server
  /// the list leads with. Both used to be treated as the manual choice: the
  /// stored server got the "the tunnel runs through this server" warning and
  /// its delete took down a tunnel that was running through another one,
  /// while deleting the server Auto was actually using left the core sending
  /// traffic through a row that no longer existed.
  ///
  /// So the tunnel goes down only for the server the core picked, as the
  /// warning says. And the stored selection, when it is the one going, moves
  /// on rather than going empty: a reload builds from it and does nothing
  /// without one, so a routing edit on the running tunnel would silently not
  /// apply, and neither would "connect on launch" at the next start.
  Future<void> _leaveAuto(ProxyNode node, String? selectedId) async {
    final picked = _autoPick(selectedId);
    if (picked == node.id && _isTunnelUp()) {
      await ref.read(tunnelControllerProvider.notifier).disconnect();
    }
    if (selectedId == node.id) {
      await ref
          .read(selectedNodeIdProvider.notifier)
          .select(_successorOf(node, picked));
    }
  }

  /// The server the stored selection moves to when [leaving] is deleted on
  /// Auto: the one the core picked, or the first other one there is.
  String? _successorOf(ProxyNode leaving, String? picked) {
    if (picked != null && picked != leaving.id) {
      return picked;
    }
    for (final other in ref.read(nodesProvider).value ?? const <ProxyNode>[]) {
      if (other.id != leaving.id) {
        return other.id;
      }
    }
    return null;
  }

  /// Whether traffic is going through [node] right now.
  ///
  /// On Auto that is the server the core picked, not the stored selection.
  ///
  /// Synchronous because the confirmation sheet needs an answer while it is
  /// being built. By then the selection has long since been read — the list
  /// the menu was opened from watches it, and on Auto the core's pick — so the
  /// loading case cannot be the one on screen.
  bool isLive(ProxyNode node) {
    final selectedId = ref.read(selectedNodeIdProvider).value;
    final live =
        ref.read(autoSelectedProvider) ? _autoPick(selectedId) : selectedId;
    if (live != node.id) {
      return false;
    }
    return _isTunnelUp();
  }

  /// The server Auto is on, as far as anybody knows.
  ///
  /// The core's answer is not there while the tunnel is starting, nor until
  /// the first question after a connect or a resume comes back. Read as
  /// "none", that window gave no server the warning, and deleting the one
  /// the start was being built from let the core come up with it in its
  /// group. Until the core has said, the stored selection — the server the
  /// tunnel was started from — is the one treated as live.
  String? _autoPick(String? selectedId) =>
      ref.read(autoNodeProvider)?.id ?? selectedId;

  bool _isTunnelUp() {
    return switch (ref.read(coreStatusProvider).value) {
      TunnelConnected() || TunnelChecking() || TunnelStarting() => true,
      _ => false,
    };
  }

  /// Clears the last failure once it has been shown.
  void clear() => state = NodeActionState.idle;
}
