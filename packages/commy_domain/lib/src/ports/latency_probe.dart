/// Times a server directly, without the core: the TCP and ICMP methods of the
/// "Ping" setting (`PingMethod`).
///
/// Both measure the distance to the server and nothing about its protocol —
/// a server that accepts the connection and then refuses the client looks
/// just as healthy. That is what `PingMethod.get` is for; these are the quick
/// numbers for people who want them.
///
/// Both go to the server the user entered and nowhere else, so rule R1 has
/// nothing to say about them: a TCP handshake is the first packet a connect
/// would send, and an echo goes to the same address. And both leave outside
/// the tunnel even while it is up: the app's own traffic is always excluded
/// from it.
abstract interface class LatencyProbe {
  /// How long [host]:[port] took to accept a TCP connection.
  ///
  /// `null` when it did not within [timeout] — refused, unreachable, or a name
  /// that does not resolve. Never throws: "did not answer" is a measurement.
  Future<Duration?> connectTime(
    String host,
    int port, {
    required Duration timeout,
  });

  /// The round trip of one ICMP echo to [host].
  ///
  /// `null` when nothing came back within [timeout], and also where the
  /// platform cannot send one. Never throws, for the same reason.
  Future<Duration?> echoTime(
    String host, {
    required Duration timeout,
  });
}
