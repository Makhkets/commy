import 'dart:async';
import 'dart:io';

import 'package:commy_domain/commy_domain.dart';

/// [LatencyProbe] over a plain `dart:io` socket.
///
/// Opens a TCP connection to the server, notes how long the handshake took,
/// and closes it without sending a byte. No TLS, no protocol greeting: the
/// number wanted is the distance to the server, and anything written after the
/// handshake would be a malformed request in the server's log.
///
/// The connection leaves outside the tunnel by construction — the use case
/// only comes here while the tunnel is down — and goes to the host the user
/// entered and nowhere else (rule R1).
class SocketLatencyProbe implements LatencyProbe {
  /// Creates the probe.
  const SocketLatencyProbe();

  @override
  Future<Duration?> connectTime(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      watch.stop();
      return watch.elapsed;
    } on Object {
      // Refused, unreachable, timed out, a name that does not resolve: all of
      // them are "this server did not answer", which is a measurement and not
      // a fault of the app.
      return null;
    } finally {
      socket?.destroy();
    }
  }
}
