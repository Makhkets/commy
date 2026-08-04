/// Names of the platform channels shared with the native tunnel.
///
/// These strings are the contract with `native/android`. They live here and
/// nowhere else: a typo in a channel name is invisible to the compiler and
/// shows up as a button that does nothing.
///
/// Full protocol: `packages/commy_core/docs/wire-protocol.md`.
abstract final class WireChannels {
  /// Prefix every channel shares. Matches the Android application id.
  static const String namespace = 'dev.commy.app';

  /// Control channel: start, stop, reload, select, urlTest, proxies, version.
  static const String method = '$namespace/core';

  /// Tunnel state events.
  static const String status = '$namespace/status';

  /// Throughput ticks.
  static const String traffic = '$namespace/traffic';

  /// Core log lines, raw and unredacted.
  static const String logs = '$namespace/logs';

  /// Snapshots of the open connections.
  static const String connections = '$namespace/connections';
}
