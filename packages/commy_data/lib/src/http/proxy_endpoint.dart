/// The local inbound the core exposes, used to send a request *into* the
/// tunnel on purpose.
///
/// Refreshing a subscription normally goes around the tunnel: routing it
/// through a tunnel that is not up yet makes the first refresh after a
/// reinstall impossible, and that is an invariant of the config generator
/// ("собственный трафик приложения исключён из туннеля",
/// docs/06-data-model.md). The opposite case is real too — a panel reachable
/// only from inside — so `UpdateSubscriptionUseCase` takes a `throughTunnel`
/// flag, and this is what makes the `true` branch mean something.
class ProxyEndpoint {
  /// Creates an endpoint.
  const ProxyEndpoint({required this.host, required this.port});

  /// The loopback mixed inbound at [port], which is where the core puts it.
  const ProxyEndpoint.loopback(int port) : this(host: '127.0.0.1', port: port);

  /// Address of the local inbound.
  final String host;

  /// Port of the local inbound.
  final int port;

  /// The value `HttpClient.findProxy` expects.
  String get proxyDirective => 'PROXY $host:$port';

  @override
  String toString() => 'ProxyEndpoint($host:$port)';
}
