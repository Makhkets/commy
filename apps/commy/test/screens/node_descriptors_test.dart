import 'package:commy/src/widgets/node_descriptors.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _labels(List<NodeTag> tags) =>
    <String>[for (final tag in tags) tag.label];

ProxyNode _node(Protocol protocol, [Map<String, Object?> params = const {}]) =>
    ProxyNode(
      id: 'n-${protocol.name}',
      name: protocol.name,
      protocol: protocol,
      host: 'server.example.com',
      port: 443,
      params: params,
    );

void main() {
  group('NodeDescriptors', () {
    test('a V2Ray link that names no transport is TCP', () {
      expect(
        NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{
            'security': 'reality',
            'flow': 'xtls-rprx-vision',
          }),
        ),
        const <NodeTag>[
          NodeTag('VLESS', hue: CommyTagHue.azure),
          NodeTag('Reality', hue: CommyTagHue.iris),
          NodeTag('TCP'),
          NodeTag('Vision', hue: CommyTagHue.gold),
        ],
      );
    });

    test('a named transport is shown as named', () {
      expect(
        NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{
            'security': 'tls',
            'type': 'xhttp',
          }),
        ),
        const <NodeTag>[
          NodeTag('VLESS', hue: CommyTagHue.azure),
          NodeTag('TLS', hue: CommyTagHue.mint),
          NodeTag('XHTTP'),
        ],
      );
    });

    // Seen on the emulator: `HYSTERIA2 · TCP` and `TUIC · TCP` under servers
    // that have no TCP port at all.
    test('QUIC protocols are not called TCP', () {
      expect(
        _labels(NodeDescriptors.of(_node(Protocol.hysteria2))),
        <String>['HYSTERIA2', 'QUIC'],
      );
      expect(
        _labels(NodeDescriptors.of(_node(Protocol.tuic))),
        <String>['TUIC', 'QUIC'],
      );
    });

    test('WireGuard is UDP', () {
      expect(
        _labels(NodeDescriptors.of(_node(Protocol.wireguard))),
        <String>['WIREGUARD', 'UDP'],
      );
    });

    // The owner's ask (2026-10-10, after INCY): the protocol, the security
    // and the flow each in a colour of their own, the transport left grey.
    test('every protocol family wears its own hue', () {
      CommyTagHue hueOf(Protocol protocol) =>
          NodeDescriptors.of(_node(protocol)).first.hue;

      expect(hueOf(Protocol.vless), CommyTagHue.azure);
      expect(hueOf(Protocol.vmess), CommyTagHue.sky);
      expect(hueOf(Protocol.trojan), CommyTagHue.orchid);
      expect(hueOf(Protocol.shadowsocks), CommyTagHue.teal);
      expect(hueOf(Protocol.shadowtls), CommyTagHue.teal);
      expect(hueOf(Protocol.hysteria2), CommyTagHue.tangerine);
      expect(hueOf(Protocol.tuic), CommyTagHue.tangerine);
      expect(hueOf(Protocol.wireguard), CommyTagHue.coral);
      expect(hueOf(Protocol.socks), CommyTagHue.neutral);
      expect(hueOf(Protocol.http), CommyTagHue.neutral);
    });

    test('the transport is never coloured', () {
      for (final type in <String>['tcp', 'ws', 'grpc', 'xhttp', '']) {
        final tags = NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{
            'security': 'tls',
            'type': type,
          }),
        );
        expect(tags.last.hue, CommyTagHue.neutral, reason: type);
      }
    });

    test('an unknown security word is shown, but without a hue', () {
      expect(
        NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{'security': 'xtls'}),
        )[1],
        const NodeTag('Xtls'),
      );
    });

    test('a flow written as none is no flow at all', () {
      for (final flow in <String>['none', 'NONE', ' none ']) {
        expect(
          NodeDescriptors.of(
            _node(Protocol.vless, <String, Object?>{'flow': flow}),
          ),
          const <NodeTag>[
            NodeTag('VLESS', hue: CommyTagHue.azure),
            NodeTag('TCP'),
          ],
          reason: flow,
        );
      }
    });

    test('a flow outside the XTLS family is kept as written', () {
      expect(
        NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{'flow': 'custom-flow'}),
        ).last,
        const NodeTag('custom-flow', hue: CommyTagHue.gold),
      );
      expect(
        NodeDescriptors.of(
          _node(Protocol.vless, <String, Object?>{
            'flow': 'xtls-rprx-vision-udp443',
          }),
        ).last.label,
        'Vision-udp443',
      );
    });
  });
}
