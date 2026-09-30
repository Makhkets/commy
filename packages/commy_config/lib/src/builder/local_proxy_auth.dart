/// The credentials the loopback proxy asks of whoever connects to it.
///
/// The loopback mixed inbound exists for the IP check (exception E-1): the
/// app's own package is outside the TUN, and aiming its request at this port
/// is how it goes through the tunnel. Unauthenticated, it was a proxy any app
/// on the phone could find by scanning localhost — and one that answers with
/// the tunnel's exit address, which is exactly what an app that wants to know
/// whether, and through what, the user is tunnelled would scan for.
class LocalProxyAuth {
  /// Creates the credentials.
  const LocalProxyAuth({
    required this.password,
    this.username = defaultUsername,
  });

  /// The user name; the password is what is secret.
  static const String defaultUsername = 'commy';

  /// The user name the inbound accepts.
  final String username;

  /// The password the inbound accepts. Hex, so it needs no escaping in a
  /// proxy directive.
  final String password;

  @override
  bool operator ==(Object other) =>
      other is LocalProxyAuth &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(username, password);

  @override
  String toString() => 'LocalProxyAuth($username)';
}
