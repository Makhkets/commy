/// How the servers in the list are timed — the "Ping" setting.
///
/// Three answers to three different questions, and the owner's choice of
/// default (2026-09-23): [get], the one Happ and INCY default to, because it
/// is the only one that says whether a server actually carries traffic.
enum PingMethod {
  /// A GET to the probe URL through the server itself.
  ///
  /// The whole handshake with the server plus one round trip through it: the
  /// delay a user feels, and the only method a REALITY server that refuses
  /// this client fails. It works with the tunnel down too — the app brings the
  /// server's outbound up in a core instance of its own.
  get,

  /// How long the server takes to accept a TCP connection, measured directly.
  ///
  /// Quick and says nothing about the protocol: a server that accepts the
  /// connection and then refuses the client looks healthy. Servers on UDP
  /// (Hysteria2, TUIC, WireGuard, QUIC and KCP transports) have nothing to
  /// accept a TCP connection with and are left out.
  tcp,

  /// An ICMP echo to the server's address, like `ping`.
  ///
  /// Many servers do not answer it, and they show as unreachable while they
  /// work — which is the reason it is not the default.
  icmp;

  /// The stored name of [name], or [get] for a value this build does not know.
  static PingMethod fromName(String? name) {
    for (final method in values) {
      if (method.name == name) {
        return method;
      }
    }
    return get;
  }
}
