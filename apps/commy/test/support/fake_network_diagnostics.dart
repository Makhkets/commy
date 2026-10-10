import 'package:commy_domain/commy_domain.dart';

/// Name resolution and TLS answered from fields, never from a socket.
class FakeNetworkDiagnostics implements NetworkDiagnostics {
  /// What [resolve] answers; `null` is a name that does not resolve.
  List<String>? addresses = <String>['198.51.100.7'];

  /// What [tlsHandshake] answers.
  TlsOutcome tls = TlsOutcome.completed;

  @override
  Future<List<String>?> resolve(
    String host, {
    required Duration timeout,
  }) async =>
      addresses;

  @override
  Future<TlsOutcome> tlsHandshake(
    String host,
    int port, {
    required String serverName,
    required Duration timeout,
  }) async =>
      tls;
}
