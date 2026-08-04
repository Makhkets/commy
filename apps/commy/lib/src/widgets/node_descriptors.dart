import 'package:commy_domain/commy_domain.dart';

/// The `VLESS · Reality · TCP` line under a server name.
///
/// It answers the one question a list of near-identical names cannot: what is
/// this connection actually made of. The parts are read from the node's own
/// parameters, so a server that carries no transport information gets a
/// shorter line rather than an invented one.
///
/// Nothing secret is ever read here. The keys touched — `security`, `type`,
/// `flow` — are transport shape, not credentials, and none of them appear in
/// [ProxyNode.secretParamKeys].
abstract final class NodeDescriptors {
  /// Parameter naming the TLS flavour: none, tls or reality.
  static const String securityKey = 'security';

  /// Parameter naming the stream transport: tcp, ws, grpc, http.
  static const String transportKey = 'type';

  /// Parameter naming the XTLS flow, e.g. `xtls-rprx-vision`.
  static const String flowKey = 'flow';

  /// Builds the descriptor list for [node].
  static List<String> of(ProxyNode node) {
    final parts = <String>[node.protocol.wireName.toUpperCase()];

    final security = node.param(securityKey)?.trim() ?? '';
    if (security.isNotEmpty && security != 'none') {
      parts.add(_titleCase(security));
    }

    final transport = node.param(transportKey)?.trim() ?? '';
    parts.add(transport.isEmpty ? 'TCP' : transport.toUpperCase());

    final flow = node.param(flowKey)?.trim() ?? '';
    if (flow.isNotEmpty) {
      parts.add(flow);
    }
    return parts;
  }

  static String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    if (value.toLowerCase() == 'tls') {
      return 'TLS';
    }
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }
}
