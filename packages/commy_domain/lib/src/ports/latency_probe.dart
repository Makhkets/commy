/// Times a server without a running core.
///
/// The core measures the honest number — a request through the outbound and
/// back — and it can only do that while it is up. But the moment a user most
/// wants a number is *before* connecting: which of these ten servers do I
/// pick? Answering "connect first" to that is how the header's ping button
/// came to fail on every press while the tunnel was down.
///
/// So with the tunnel down the app times the one thing it can reach on its
/// own: how long the server takes to accept a TCP connection. It is a smaller
/// number than the core's — one round trip against several — and the two are
/// never mixed inside one run, so a list measured in one go still orders
/// correctly.
///
/// This goes to the server the user entered and nowhere else, so rule R1 has
/// nothing to say about it: it is the first packet a connect would send.
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
}
