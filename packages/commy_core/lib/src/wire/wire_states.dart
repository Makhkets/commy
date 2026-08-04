/// The six values the `state` field of a `/status` event can take.
///
/// They line up one for one with the variants of the domain `TunnelStatus`.
abstract final class WireStates {
  /// Nothing is running.
  static const String idle = 'idle';

  /// The core was asked to start and has not reported readiness.
  static const String starting = 'starting';

  /// The tunnel is up.
  static const String connected = 'connected';

  /// The tunnel is up and reachability is being probed.
  ///
  /// The native side never sends this one: it is derived in Dart on top of
  /// [connected]. The decoder accepts it for `FakeCoreClient` and for whoever
  /// implements a platform that does know the difference.
  static const String checking = 'checking';

  /// The core was asked to stop and has not finished.
  static const String stopping = 'stopping';

  /// The tunnel is down because something went wrong.
  static const String error = 'error';
}
