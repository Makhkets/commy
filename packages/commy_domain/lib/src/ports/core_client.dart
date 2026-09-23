import 'package:commy_domain/src/entities/connection_info.dart';
import 'package:commy_domain/src/entities/core_config.dart';
import 'package:commy_domain/src/entities/log_line.dart';
import 'package:commy_domain/src/entities/proxy_group.dart';
import 'package:commy_domain/src/entities/traffic_sample.dart';
import 'package:commy_domain/src/entities/tunnel_status.dart';

/// The one and only door to the sing-box core.
///
/// Features never touch platform channels or FFI directly — always this
/// interface. That is what makes a connection test possible without a real
/// tunnel (`FakeCoreClient`). Signature fixed by docs/02-architecture.md.
///
/// Unlike the repository ports, the methods here return bare futures and may
/// throw: they sit directly on top of a channel or an FFI call. Use cases wrap
/// them and turn whatever comes out into a typed failure, so nothing escapes
/// past the domain boundary.
abstract interface class CoreClient {
  /// Starts the core with a freshly built configuration.
  Future<void> start(CoreConfig config);

  /// Stops the core and tears the tunnel down.
  Future<void> stop();

  /// Restarts the core with a new configuration.
  ///
  /// Switching the active node does *not* go through here: that would drop
  /// every open connection. Use [select] instead.
  Future<void> reload(CoreConfig config);

  /// Tunnel state, from `idle` to `error`.
  Stream<TunnelStatus> get status;

  /// Throughput ticks while the tunnel is up.
  Stream<TrafficSample> get traffic;

  /// Core log, unredacted. Redaction happens on the output layer.
  Stream<LogLine> get logs;

  /// Snapshots of the currently open connections.
  Stream<List<ConnectionInfo>> get connections;

  /// Outbound groups the running core knows about.
  Future<List<ProxyGroup>> proxies();

  /// Points the group tagged [group] at the member tagged [tag].
  ///
  /// This is how the node changes on the fly, without a restart.
  Future<void> select(String group, String tag);

  /// Measures the round trip of the outbound tagged [tag] against [probe].
  ///
  /// Returns `null` when the probe did not come back.
  Future<Duration?> urlTest(String tag, Uri probe);

  /// Measures every outbound of [config] by a GET to [probe] through it, in a
  /// core instance of its own, whether or not the tunnel is up.
  ///
  /// [config] carries nothing but the outbounds to measure (see
  /// `ConfigGenerator.buildProbe`); the instance has no inbound and no TUN,
  /// and goes away once the numbers are in. Each server gets [timeout].
  ///
  /// The answer maps each outbound tag to its delay, `null` for a server that
  /// did not answer. Throws only when the core refuses [config] as a whole.
  Future<Map<String, Duration?>> probeOutbounds(
    CoreConfig config, {
    required Uri probe,
    required Duration timeout,
  });

  /// Releases what the client holds: subscriptions, timers, sockets.
  ///
  /// It does **not** take the tunnel down, and must never be mistaken for
  /// [stop]. On every platform the core outlives the process that talks to it
  /// — a foreground service on Android, an extension on Apple, a privileged
  /// helper on the desktops — and closing the client while traffic flows is
  /// exactly what happens when the user swipes the app away. The tunnel is
  /// stopped when the user says so, not when a window closes.
  ///
  /// Idempotent: a client disposed twice is not an error.
  Future<void> dispose();
}
