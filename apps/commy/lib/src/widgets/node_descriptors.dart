import 'package:commy_domain/commy_domain.dart';

/// The `VLESS · Reality · TCP` line under a server name.
///
/// It answers the one question a list of near-identical names cannot: what is
/// this connection actually made of. The parts are read from the node's own
/// parameters. A link that names no transport gets the one its protocol runs
/// over — TCP for the V2Ray family, QUIC for Hysteria2 and TUIC, UDP for
/// WireGuard — and never a default that belongs to some other protocol.
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
    parts.add(
      transport.isEmpty ? _carriedOver(node.protocol) : transport.toUpperCase(),
    );

    final flow = node.param(flowKey)?.trim() ?? '';
    if (flow.isNotEmpty) {
      parts.add(flow);
    }
    return parts;
  }

  /// What [protocol] carries traffic over when the link says nothing.
  ///
  /// Every row used to fall back to "TCP", which put `HYSTERIA2 · TCP` under
  /// a server that has no TCP port at all. Exhaustive on purpose, like
  /// `MeasureLatencyUseCase.acceptsTcp`: a protocol added later has
  /// to be placed by whoever adds it.
  static String _carriedOver(Protocol protocol) => switch (protocol) {
        Protocol.hysteria2 || Protocol.tuic => 'QUIC',
        Protocol.wireguard => 'UDP',
        Protocol.vless ||
        Protocol.vmess ||
        Protocol.trojan ||
        Protocol.shadowsocks ||
        Protocol.shadowtls ||
        Protocol.socks ||
        Protocol.http =>
          'TCP',
      };

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
