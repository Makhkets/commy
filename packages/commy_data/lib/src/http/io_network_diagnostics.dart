import 'dart:async';
import 'dart:io';

import 'package:commy_domain/commy_domain.dart';

/// Name resolution and a TLS handshake for `DiagnoseNodeUseCase`, on
/// `dart:io`.
///
/// Both leave around the tunnel: on Android the app's own traffic is
/// excluded from it, so this is the path a connect takes to the server — and
/// the path a diagnosis has to look at.
class IoNetworkDiagnostics implements NetworkDiagnostics {
  /// Creates the diagnostics.
  const IoNetworkDiagnostics();

  @override
  Future<List<String>?> resolve(
    String host, {
    required Duration timeout,
  }) async {
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      return <String>[for (final address in addresses) address.address];
    } on Object {
      return null;
    }
  }

  @override
  Future<TlsOutcome> tlsHandshake(
    String host,
    int port, {
    required String serverName,
    required Duration timeout,
  }) async {
    final started = DateTime.now();
    Socket? plain;
    SecureSocket? secure;
    var badCertificate = false;
    try {
      plain = await Socket.connect(host, port, timeout: timeout);
      final left = timeout - DateTime.now().difference(started);
      if (left <= Duration.zero) {
        return TlsOutcome.failed;
      }
      secure = await SecureSocket.secure(
        plain,
        host: serverName,
        supportedProtocols: const <String>['h2', 'http/1.1'],
        onBadCertificate: (_) {
          // Accepted only so the handshake can finish and the answer can be
          // "the certificate", not "the handshake". Nothing is sent on it.
          badCertificate = true;
          return true;
        },
      ).timeout(left);
      return badCertificate ? TlsOutcome.badCertificate : TlsOutcome.completed;
    } on Object {
      return TlsOutcome.failed;
    } finally {
      secure?.destroy();
      plain?.destroy();
    }
  }
}
