import 'package:commy_domain/src/entities/proxy_node.dart';

/// A line in a subscription that is a message from the panel, not a server.
///
/// Panels answer a client they will not serve by sending exactly one entry
/// with an address that goes nowhere — `vless://…@0.0.0.0:1` — and putting the
/// explanation in the name where a server's label would be: *App not
/// supported*, *Device limit reached*, *Subscription expired*. Remnawave even
/// has a setting for the wording (`hwidNotSupportedRemarks`).
///
/// It parses as a perfectly good node, and that was the problem: the app
/// imported it, drew it in the list with a flag and a ping button, offered to
/// connect through it, and reported "imported 1 server". The one thing it
/// never did was tell the user what the panel had actually said — which is the
/// only useful thing in the whole response.
///
/// The test is the address, not the port and not the wording. `0.0.0.0` and
/// `::` are "no address" in every stack there is; a panel that means a server
/// never sends one, and a name is free text in whatever language the admin
/// chose, so matching on it would work for English and for nobody else.
abstract final class PanelNotice {
  /// Addresses that mean "nowhere", written the way a panel writes them.
  static const Set<String> unspecifiedHosts = <String>{
    '0.0.0.0',
    '::',
    '0:0:0:0:0:0:0:0',
    '[::]',
  };

  /// Whether [node] is a message rather than somewhere to connect.
  static bool isNotice(ProxyNode node) => isUnspecified(node.host);

  /// Whether [host] addresses nothing.
  ///
  /// Trimmed and lowercased first: the value comes out of a link somebody
  /// else generated, and `[::]` and `::` are the same nothing.
  static bool isUnspecified(String host) =>
      unspecifiedHosts.contains(host.trim().toLowerCase());

  /// What the panel said, or `null` when [node] is an ordinary server.
  ///
  /// The name as the panel wrote it, with nothing added: a translation of it
  /// would be this app inventing an explanation on a panel's behalf, and a
  /// prefix would push the part the user needs off the end of the line. An
  /// entry with no name at all yields `null` — there is no message to show,
  /// and the absence of servers says the same thing more quietly.
  static String? messageOf(ProxyNode node) {
    if (!isNotice(node)) {
      return null;
    }
    final message = node.name.trim();
    return message.isEmpty ? null : message;
  }

  /// [nodes] without the notices among them.
  static List<ProxyNode> servers(Iterable<ProxyNode> nodes) =>
      List<ProxyNode>.unmodifiable(nodes.where((node) => !isNotice(node)));

  /// The messages among [nodes], in the order the panel listed them.
  static List<String> messages(Iterable<ProxyNode> nodes) =>
      List<String>.unmodifiable(nodes.map(messageOf).whereType<String>());
}
