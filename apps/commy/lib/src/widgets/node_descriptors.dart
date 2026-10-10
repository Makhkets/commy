import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';

/// The `VLESS · Reality · TCP` line under a server name.
///
/// It answers the one question a list of near-identical names cannot: what is
/// this connection actually made of. The parts are read from the node's own
/// parameters. A link that names no transport gets the one its protocol runs
/// over — TCP for the V2Ray family, QUIC for Hysteria2 and TUIC, UDP for
/// WireGuard — and never a default that belongs to some other protocol.
///
/// Each part carries a hue (docs/04-design-system.md, "Метки сервера"): the
/// protocol its family's, TLS green, Reality violet, the Vision flow yellow,
/// and the transport none — it is the plumbing, and a grey word between two
/// coloured ones is what makes the line scan, the way INCY draws it.
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

  /// What every XTLS flow name starts with, and what the line leaves out:
  /// `xtls-rprx-vision` is drawn as `Vision`, the name it goes by.
  static const String _flowPrefix = 'xtls-rprx-';

  /// Builds the descriptor list for [node].
  static List<NodeTag> of(ProxyNode node) {
    final parts = <NodeTag>[
      NodeTag(
        node.protocol.wireName.toUpperCase(),
        hue: _protocolHue(node.protocol),
      ),
    ];

    final security = node.param(securityKey)?.trim() ?? '';
    if (security.isNotEmpty && security != 'none') {
      parts.add(NodeTag(_titleCase(security), hue: _securityHue(security)));
    }

    final transport = node.param(transportKey)?.trim() ?? '';
    parts.add(
      NodeTag(
        transport.isEmpty
            ? _carriedOver(node.protocol)
            : transport.toUpperCase(),
      ),
    );

    final flow = node.param(flowKey)?.trim() ?? '';
    // `none` is how some panels write "no flow", like `security=none`.
    if (flow.isNotEmpty && flow.toLowerCase() != 'none') {
      parts.add(NodeTag(_flowName(flow), hue: CommyTagHue.gold));
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

  /// The hue of [protocol]: one per family, so a mixed list shows its
  /// families apart. Exhaustive for the same reason as [_carriedOver].
  static CommyTagHue _protocolHue(Protocol protocol) => switch (protocol) {
        Protocol.vless => CommyTagHue.azure,
        Protocol.vmess => CommyTagHue.sky,
        Protocol.trojan => CommyTagHue.orchid,
        Protocol.shadowsocks || Protocol.shadowtls => CommyTagHue.teal,
        Protocol.hysteria2 || Protocol.tuic => CommyTagHue.tangerine,
        Protocol.wireguard => CommyTagHue.coral,
        // Local debugging proxies: plumbing, like a transport.
        Protocol.socks || Protocol.http => CommyTagHue.neutral,
      };

  static CommyTagHue _securityHue(String security) =>
      switch (security.toLowerCase()) {
        'tls' => CommyTagHue.mint,
        'reality' => CommyTagHue.iris,
        _ => CommyTagHue.neutral,
      };

  static String _flowName(String flow) {
    final lower = flow.toLowerCase();
    if (lower.startsWith(_flowPrefix) && lower.length > _flowPrefix.length) {
      return _titleCase(flow.substring(_flowPrefix.length));
    }
    return flow;
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
