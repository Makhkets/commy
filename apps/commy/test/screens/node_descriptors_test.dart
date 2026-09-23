import 'package:commy/src/widgets/node_descriptors.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

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
        <String>['VLESS', 'Reality', 'TCP', 'xtls-rprx-vision'],
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
        <String>['VLESS', 'TLS', 'XHTTP'],
      );
    });

    // Seen on the emulator: `HYSTERIA2 · TCP` and `TUIC · TCP` under servers
    // that have no TCP port at all.
    test('QUIC protocols are not called TCP', () {
      expect(
        NodeDescriptors.of(_node(Protocol.hysteria2)),
        <String>['HYSTERIA2', 'QUIC'],
      );
      expect(
        NodeDescriptors.of(_node(Protocol.tuic)),
        <String>['TUIC', 'QUIC'],
      );
    });

    test('WireGuard is UDP', () {
      expect(
        NodeDescriptors.of(_node(Protocol.wireguard)),
        <String>['WIREGUARD', 'UDP'],
      );
    });
  });
}
