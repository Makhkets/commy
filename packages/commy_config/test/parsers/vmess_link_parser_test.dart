import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

String _legacy(Map<String, Object?> document) =>
    'vmess://${LenientBase64.encode(jsonEncode(document))}';

void main() {
  const parser = VmessLinkParser();

  group('VmessLinkParser.parse', () {
    test('reads the v2rayN base64 JSON form', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'v': '2',
          'ps': 'Tokyo 01',
          'add': 'jp.example.com',
          'port': '443',
          'id': 'a0b1c2d3-e4f5-6789-abcd-ef0123456789',
          'aid': '0',
          'scy': 'auto',
          'net': 'ws',
          'type': 'none',
          'host': 'cdn.example.com',
          'path': '/ws',
          'tls': 'tls',
          'sni': 'jp.example.com',
          'alpn': 'h2',
          'fp': 'chrome',
        }),
      );

      expect(node.protocol, Protocol.vmess);
      expect(node.name, 'Tokyo 01');
      expect(node.host, 'jp.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.security), 'tls');
      expect(node.param(ParamKeys.path), '/ws');
      expect(node.param(ParamKeys.host), 'cdn.example.com');
      expect(node.param(ParamKeys.fingerprint), 'chrome');
      expect(node.param(ParamKeys.headerType), isNull);
    });

    test('accepts numeric port and alterId', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'ps': 'n',
          'add': 'example.com',
          'port': 8080,
          'id': 'uuid',
          'aid': 64,
          'net': 'tcp',
        }),
      );

      expect(node.port, 8080);
      expect(node.param(ParamKeys.alterId), '64');
    });

    test('maps net=h2 onto the http transport', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'ps': 'n',
          'add': 'example.com',
          'port': 443,
          'id': 'uuid',
          'net': 'h2',
          'tls': 'tls',
        }),
      );

      expect(node.param(ParamKeys.transport), 'http');
    });

    test('moves the grpc path into serviceName', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'ps': 'n',
          'add': 'example.com',
          'port': 443,
          'id': 'uuid',
          'net': 'grpc',
          'path': 'svc',
        }),
      );

      expect(node.param(ParamKeys.serviceName), 'svc');
      expect(node.param(ParamKeys.path), isNull);
    });

    test('reads the modern query form', () {
      final node = parser.parse(
        'vmess://uuid@example.com:443?type=ws&security=tls&path=%2Fx'
        '&aid=0&scy=aes-128-gcm#Modern',
      );

      expect(node.name, 'Modern');
      expect(node.param(ParamKeys.uuid), 'uuid');
      expect(node.param(ParamKeys.vmessSecurity), 'aes-128-gcm');
      expect(node.param(ParamKeys.transport), 'ws');
    });

    test('falls back to the fragment when the payload has no ps', () {
      final base = LenientBase64.encode(
        jsonEncode(<String, Object?>{
          'add': 'example.com',
          'port': 443,
          'id': 'uuid',
        }),
      );

      expect(parser.parse('vmess://$base#FromFragment').name, 'FromFragment');
    });

    test('rejects a payload without an address', () {
      expect(
        () => parser.parse(
          _legacy(<String, Object?>{'ps': 'n', 'port': 443, 'id': 'uuid'}),
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a payload without a valid port', () {
      expect(
        () => parser.parse(
          _legacy(<String, Object?>{
            'add': 'example.com',
            'port': 'ninety',
            'id': 'uuid',
          }),
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a payload without a user id', () {
      expect(
        () => parser.parse(
          _legacy(<String, Object?>{'add': 'example.com', 'port': 443}),
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a base64 body that is not JSON', () {
      final body = LenientBase64.encode('not json at all');

      expect(
        () => parser.parse('vmess://$body'),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('VmessLinkParser.toLink', () {
    test('round trips through the base64 form', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'ps': 'Round Trip',
          'add': 'example.com',
          'port': 443,
          'id': 'uuid',
          'aid': '0',
          'scy': 'auto',
          'net': 'ws',
          'path': '/w',
          'host': 'h.example',
          'tls': 'tls',
          'sni': 's.example',
        }),
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.name, node.name);
      expect(again.host, node.host);
      expect(again.port, node.port);
      expect(again.params, node.params);
    });

    test('writes a link every other client can read', () {
      final node = parser.parse(
        _legacy(<String, Object?>{
          'ps': 'n',
          'add': 'example.com',
          'port': 443,
          'id': 'uuid',
          'net': 'tcp',
        }),
      );
      final link = parser.toLink(node);
      final decoded = LenientBase64.decodeToString(link.substring(8));

      expect(link, startsWith('vmess://'));
      expect(jsonDecode(decoded!), isA<Map<String, Object?>>());
    });
  });
}
