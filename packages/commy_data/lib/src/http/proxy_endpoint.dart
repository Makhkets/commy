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
  const ProxyEndpoint({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  /// The loopback mixed inbound at [port], which is where the core puts it.
  const ProxyEndpoint.loopback(int port, {String? username, String? password})
      : this(
          host: '127.0.0.1',
          port: port,
          username: username,
          password: password,
        );

  /// Address of the local inbound.
  final String host;

  /// Port of the local inbound.
  final int port;

  /// The user name the inbound asks for, if it asks.
  final String? username;

  /// The password the inbound asks for, if it asks. Never printed.
  final String? password;

  /// The value `HttpClient.findProxy` expects.
  ///
  /// `HttpClient` sends credentials written into the directive as
  /// `Proxy-Authorization`, on the CONNECT of an https request too.
  String get proxyDirective {
    final user = username;
    final secret = password;
    final credentials = user == null || secret == null
        ? ''
        : '${Uri.encodeComponent(user)}:${Uri.encodeComponent(secret)}@';
    return 'PROXY $credentials$host:$port';
  }

  @override
  String toString() => 'ProxyEndpoint($host:$port)';
}
