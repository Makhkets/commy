import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

ProxyNode _node(Protocol protocol, Map<String, Object?> params) => ProxyNode(
      id: 'n',
      name: 'N',
      protocol: protocol,
      host: 'a.example',
      port: 443,
      params: params,
    );

/// With the tunnel down a server is measured by a TCP handshake to its port.
/// That is only an answer for a server that listens on TCP.
void main() {
  group('MeasureLatencyUseCase.acceptsTcp', () {
    test('a TCP protocol over a TCP transport is', () {
      for (final transport in <String?>[null, 'tcp', 'ws', 'grpc', 'xhttp']) {
        expect(
          MeasureLatencyUseCase.acceptsTcp(
            _node(Protocol.vless, <String, Object?>{'type': transport}),
          ),
          isTrue,
          reason: '$transport',
        );
      }
    });

    test('a QUIC protocol is not', () {
      for (final protocol in <Protocol>[
        Protocol.hysteria2,
        Protocol.tuic,
        Protocol.wireguard,
      ]) {
        expect(
          MeasureLatencyUseCase.acceptsTcp(
            _node(protocol, const <String, Object?>{}),
          ),
          isFalse,
          reason: protocol.name,
        );
      }
    });

    test('a UDP transport under a TCP protocol is not', () {
      expect(
        MeasureLatencyUseCase.acceptsTcp(
          _node(Protocol.vmess, <String, Object?>{'type': 'quic'}),
        ),
        isFalse,
      );
    });

    test('xhttp is HTTP, and HTTP/3 is QUIC', () {
      final http3 = _node(Protocol.vless, <String, Object?>{
        'type': 'xhttp',
        'security': 'tls',
        'alpn': 'h3',
      });
      final http2 = _node(Protocol.vless, <String, Object?>{
        'type': 'xhttp',
        'security': 'tls',
        'alpn': 'h2,http/1.1',
      });
      // Several entries mean HTTP/2 even with h3 among them: the transport
      // picks HTTP/3 only when it is the single one offered.
      final both = _node(Protocol.vless, <String, Object?>{
        'type': 'xhttp',
        'security': 'tls',
        'alpn': 'h3,h2',
      });
      // Reality is HTTP/2 whatever the link says about ALPN.
      final reality = _node(Protocol.vless, <String, Object?>{
        'type': 'xhttp',
        'security': 'reality',
        'alpn': 'h3',
      });

      expect(MeasureLatencyUseCase.acceptsTcp(http3), isFalse);
      expect(MeasureLatencyUseCase.acceptsTcp(http2), isTrue);
      expect(MeasureLatencyUseCase.acceptsTcp(both), isTrue);
      expect(MeasureLatencyUseCase.acceptsTcp(reality), isTrue);
    });
  });

  group('ProxyNode.redacted', () {
    test('blanks the extra of an xhttp node', () {
      final node = _node(Protocol.vless, <String, Object?>{
        'type': 'xhttp',
        'path': '/xh',
        'extra': '{"headers":{"Authorization":"Bearer secret-token"}}',
      });

      expect('${node.redacted().params}', isNot(contains('secret-token')));
      expect(node.redacted().param('path'), '/xh');
    });
  });
}
