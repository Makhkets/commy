import 'dart:async';
import 'dart:io';

import 'package:commy_domain/commy_domain.dart';

/// Resolves a host name; [InternetAddress.lookup] outside tests.
typedef AddressLookup = Future<List<InternetAddress>> Function(String host);

/// Sends one ICMP echo, or answers `null` where it cannot.
typedef EchoSender = Future<Duration?> Function(
  String host, {
  required Duration timeout,
});

/// [LatencyProbe] over a plain `dart:io` socket.
///
/// Opens a TCP connection to the server, notes how long the handshake took,
/// and closes it without sending a byte. No TLS, no protocol greeting: the
/// number wanted is the distance to the server, and anything written after the
/// handshake would be a malformed request in the server's log.
///
/// The name is resolved first and the clock starts after. A cold lookup is a
/// one-off cost of the resolver, not a property of the server, and timing it
/// in skewed a whole run: "measure all" goes in batches of four, so the first
/// batch paid for every lookup and the rest found the answers cached. On the
/// emulator that was 196 ms against 44 ms for four servers on one host. The
/// connect itself resolves the name again, from the cache, which keeps
/// `Socket.connect`'s way of trying each address in turn.
///
/// The connection leaves outside the tunnel by construction — the app's own
/// traffic is always excluded from it — and goes to the host the user entered
/// and nowhere else (rule R1).
///
/// An echo is not something `dart:io` can send, so [echoTime] hands it to
/// the platform through the `echo` it was built with; without one it answers
/// `null`.
class SocketLatencyProbe implements LatencyProbe {
  /// Creates the probe.
  const SocketLatencyProbe({
    AddressLookup lookup = InternetAddress.lookup,
    EchoSender? echo,
    this.onDiagnostic,
  })  : _lookup = lookup,
        _echo = echo;

  final AddressLookup _lookup;
  final EchoSender? _echo;

  /// Local diagnostics, routed through the application's redacting logger.
  final void Function(String message)? onDiagnostic;

  @override
  Future<Duration?> echoTime(String host, {required Duration timeout}) async {
    final echo = _echo;
    if (echo == null) {
      onDiagnostic?.call('ICMP unavailable on this platform');
      return null;
    }
    try {
      final delay = await echo(host, timeout: timeout);
      final outcome = delay == null
          ? 'no echo; ICMP may be unavailable or blocked'
          : '${delay.inMilliseconds} ms';
      onDiagnostic?.call('ICMP $host: $outcome');
      return delay;
    } on Object catch (error) {
      onDiagnostic?.call('ICMP $host failed: $error');
      return null;
    }
  }

  @override
  Future<Duration?> connectTime(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    final budget = Stopwatch()..start();
    Socket? socket;
    var stage = 'DNS';
    try {
      final addresses = await _lookup(host).timeout(timeout);
      if (addresses.isEmpty) {
        onDiagnostic?.call('DNS $host: no addresses');
        return null;
      }
      onDiagnostic?.call(
        'DNS $host: ${addresses.length} addresses '
        'in ${budget.elapsedMilliseconds} ms',
      );
      final left = timeout - budget.elapsed;
      if (left <= Duration.zero) {
        onDiagnostic?.call(
          'DNS $host: exhausted ${timeout.inMilliseconds} ms deadline',
        );
        return null;
      }
      stage = 'TCP';
      final watch = Stopwatch()..start();
      socket = await Socket.connect(host, port, timeout: left);
      watch.stop();
      onDiagnostic?.call(
        'TCP $host:$port: connected in ${watch.elapsedMilliseconds} ms '
        '(no proxy handshake tested)',
      );
      return watch.elapsed;
    } on Object catch (error) {
      onDiagnostic?.call(
        '$stage $host:$port failed after ${budget.elapsedMilliseconds} ms: '
        '$error',
      );
      // Refused, unreachable, timed out, a name that does not resolve: all of
      // them are "this server did not answer", which is a measurement and not
      // a fault of the app.
      return null;
    } finally {
      socket?.destroy();
    }
  }
}
