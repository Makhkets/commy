/// How a TLS handshake with a server ended.
enum TlsOutcome {
  /// It completed with a certificate the platform trusts for the name.
  completed,

  /// It completed, but the certificate is not one the platform trusts for
  /// the name — expired, self-signed, for another host, or the clock is off.
  badCertificate,

  /// It did not complete: refused, reset, timed out.
  failed,
}

/// The two network checks of a diagnosis the latency probe does not cover
/// (`DiagnoseNodeUseCase`): name resolution and a TLS handshake.
///
/// Both go to the user's server and nowhere else, around the tunnel, exactly
/// as a connect would (rule R1).
abstract interface class NetworkDiagnostics {
  /// The addresses [host] resolves to, or `null` when it does not within
  /// [timeout]. Never throws.
  Future<List<String>?> resolve(String host, {required Duration timeout});

  /// A TLS handshake with [host]:[port] presenting [serverName] as SNI.
  /// Never throws.
  Future<TlsOutcome> tlsHandshake(
    String host,
    int port, {
    required String serverName,
    required Duration timeout,
  });
}
