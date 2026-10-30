import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the last access check said about the tunnel that is up now.
///
/// The check's own result is a notice: a toast that is shown once and then
/// cleared. The route on the main screen needs the answer for as long as it
/// stays true — "Online, 52 ms" under its internet stop, or the cross where
/// nothing came back — so it is kept here, and dropped the moment it stops
/// describing the tunnel on screen: a disconnect, a new connect, a switch of
/// server.
@immutable
class AccessCheck {
  /// Creates a result.
  const AccessCheck({required this.passed, this.milliseconds});

  /// Whether the probe came back through the tunnel.
  final bool passed;

  /// Its round trip, when it did.
  final int? milliseconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessCheck &&
          other.passed == passed &&
          other.milliseconds == milliseconds;

  @override
  int get hashCode => Object.hash(passed, milliseconds);

  @override
  String toString() => 'AccessCheck(passed: $passed, $milliseconds ms)';
}

/// The last access check of the live tunnel, or `null` when there is none.
final NotifierProvider<AccessCheckNotifier, AccessCheck?> accessCheckProvider =
    NotifierProvider<AccessCheckNotifier, AccessCheck?>(
  AccessCheckNotifier.new,
);

/// Keeps [AccessCheck] in step with the tunnel.
///
/// It mirrors `TunnelActionState.lastCheck`, which the controller sets with
/// every check's result and clears when a check starts, the server changes
/// or the tunnel goes. It used to listen for the check's *notice* instead,
/// and on a device the toast host cleared that notice before this notifier
/// was told about it — the route's internet stop stayed blank after every
/// check that the toast had just reported.
class AccessCheckNotifier extends Notifier<AccessCheck?> {
  @override
  AccessCheck? build() {
    ref
      ..listen<TunnelNotice?>(
        tunnelControllerProvider.select((state) => state.lastCheck),
        (previous, next) => state = _answerOf(next),
      )
      ..listen<TunnelStatus>(tunnelStatusProvider, (previous, next) {
        final wasUp = previous is TunnelConnected || previous is TunnelChecking;
        final isUp = next is TunnelConnected || next is TunnelChecking;
        if (!isUp || !wasUp) {
          state = null;
        }
      });
    return _answerOf(ref.read(tunnelControllerProvider).lastCheck);
  }

  static AccessCheck? _answerOf(TunnelNotice? notice) => switch (notice?.kind) {
        TunnelNoticeKind.checkPassed ||
        TunnelNoticeKind.ipCheckFailed =>
          // The IP half is exception E-1 and optional; the access half
          // passed either way.
          AccessCheck(passed: true, milliseconds: notice!.milliseconds),
        TunnelNoticeKind.checkFailed => const AccessCheck(passed: false),
        _ => null,
      };
}
