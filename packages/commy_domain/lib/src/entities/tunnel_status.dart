import 'package:commy_domain/src/core/failure.dart';

/// State of the tunnel, as a closed set of six.
///
/// These are exactly the six states of docs/05-ux-flows.md, scenario 2. Each
/// one has to be distinguishable in the UI, and the compiler is what makes
/// sure none is forgotten — there is no `bool isConnected` anywhere.
///
/// [TunnelChecking] is not decoration: a raised tunnel does not mean working
/// internet. The server may be dead, the quota spent, the ISP in the way. The
/// user has to see the difference between "tunnel up" and "traffic flows".
sealed class TunnelStatus {
  /// Base constructor. Construct one of the six variants instead.
  const TunnelStatus();

  /// Nothing is running.
  const factory TunnelStatus.idle() = TunnelIdle;

  /// The core was asked to start and has not reported readiness yet.
  const factory TunnelStatus.starting() = TunnelStarting;

  /// The tunnel is up.
  const factory TunnelStatus.connected({
    required DateTime since,
    String? nodeId,
  }) = TunnelConnected;

  /// The tunnel is up and reachability is being probed.
  const factory TunnelStatus.checking({
    required DateTime since,
    String? nodeId,
  }) = TunnelChecking;

  /// The core was asked to stop and has not finished yet.
  const factory TunnelStatus.stopping() = TunnelStopping;

  /// The tunnel is down because something went wrong.
  const factory TunnelStatus.error(CommyFailure failure) = TunnelError;
}

/// Nothing is running. The button says "connect".
final class TunnelIdle extends TunnelStatus {
  /// Creates the state.
  const TunnelIdle();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TunnelIdle;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'TunnelIdle()';
}

/// The core is coming up. Cancelling is the only available action.
final class TunnelStarting extends TunnelStatus {
  /// Creates the state.
  const TunnelStarting();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TunnelStarting;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'TunnelStarting()';
}

/// The tunnel is up and reachability has been confirmed.
final class TunnelConnected extends TunnelStatus {
  /// Creates the state, connected [since] through node [nodeId].
  const TunnelConnected({required this.since, this.nodeId});

  /// When the tunnel came up. Drives the on-screen timer.
  final DateTime since;

  /// Node currently selected as the outbound, when known.
  final String? nodeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunnelConnected &&
          other.since == since &&
          other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(runtimeType, since, nodeId);

  @override
  String toString() => 'TunnelConnected($since, $nodeId)';
}

/// The tunnel is up; the first reachability probe has not answered yet.
final class TunnelChecking extends TunnelStatus {
  /// Creates the state, connected [since] through node [nodeId].
  const TunnelChecking({required this.since, this.nodeId});

  /// When the tunnel came up. The timer keeps running during the check.
  final DateTime since;

  /// Node currently selected as the outbound, when known.
  final String? nodeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunnelChecking &&
          other.since == since &&
          other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(runtimeType, since, nodeId);

  @override
  String toString() => 'TunnelChecking($since, $nodeId)';
}

/// The core is shutting down.
final class TunnelStopping extends TunnelStatus {
  /// Creates the state.
  const TunnelStopping();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TunnelStopping;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'TunnelStopping()';
}

/// The tunnel is down because of [failure].
final class TunnelError extends TunnelStatus {
  /// Creates the state carrying [failure].
  const TunnelError(this.failure);

  /// Why the tunnel is not running. Always paired with an action in the UI.
  final CommyFailure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TunnelError && other.failure == failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'TunnelError($failure)';
}
