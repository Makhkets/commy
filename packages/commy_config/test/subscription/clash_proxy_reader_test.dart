import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ClashProxyReader', () {
    test('reads a vless Reality entry', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'NL Reality',
        'type': 'vless',
        'server': 'nl.example.com',
        'port': 443,
        'uuid': 'the-uuid',
        'flow': 'xtls-rprx-vision',
        'tls': true,
        'servername': 'www.microsoft.com',
        'client-fingerprint': 'chrome',
        'reality-opts': <String, Object?>{
          'public-key': 'PUBKEY',
          'short-id': 'ab12',
        },
        'network': 'tcp',
      });

      expect(node.protocol, Protocol.vless);
      expect(node.name, 'NL Reality');
      expect(node.host, 'nl.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.security), 'reality');
      expect(node.param(ParamKeys.publicKey), 'PUBKEY');
      expect(node.param(ParamKeys.shortId), 'ab12');
      expect(node.param(ParamKeys.fingerprint), 'chrome');
      expect(node.param(ParamKeys.sni), 'www.microsoft.com');
      expect(node.param(ParamKeys.flow), 'xtls-rprx-vision');
    });

    test('reads a vmess websocket entry with its host header', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'WS',
        'type': 'vmess',
        'server': 'ws.example.com',
        'port': 443,
        'uuid': 'the-uuid',
        'alterId': 0,
        'cipher': 'auto',
        'tls': true,
        'network': 'ws',
        'ws-opts': <String, Object?>{
          'path': '/ray',
          'headers': <String, Object?>{'Host': 'cdn.example.com'},
        },
      });

      expect(node.protocol, Protocol.vmess);
      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/ray');
      expect(node.param(ParamKeys.host), 'cdn.example.com');
      expect(node.param(ParamKeys.security), 'tls');
    });

    test('reads a grpc service name', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'G',
        'type': 'trojan',
        'server': 'g.example.com',
        'port': 443,
        'password': 'pw',
        'network': 'grpc',
        'grpc-opts': <String, Object?>{'grpc-service-name': 'svc'},
      });

      expect(node.param(ParamKeys.serviceName), 'svc');
      expect(node.param(ParamKeys.security), 'tls');
    });

    test('turns a clash obfs plugin into the SIP003 spelling', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'SS',
        'type': 'ss',
        'server': 'ss.example.com',
        'port': 8388,
        'cipher': 'aes-256-gcm',
        'password': 'pw',
        'plugin': 'obfs',
        'plugin-opts': <String, Object?>{
          'mode': 'tls',
          'host': 'bing.com',
        },
      });

      expect(node.param(ParamKeys.plugin), 'obfs-local');
      expect(node.param(ParamKeys.pluginOpts), 'obfs=tls;obfs-host=bing.com');
    });

    test('reads a hysteria2 entry', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'HY',
        'type': 'hysteria2',
        'server': 'hy.example.com',
        'port': 8443,
        'password': 'pw',
        'sni': 'hy.example.com',
        'obfs': 'salamander',
        'obfs-password': 'o',
        'skip-cert-verify': true,
        'up': 100,
        'down': 500,
      });

      expect(node.protocol, Protocol.hysteria2);
      expect(node.param(ParamKeys.obfs), 'salamander');
      expect(node.param(ParamKeys.obfsPassword), 'o');
      expect(node.params[ParamKeys.allowInsecure], isTrue);
      expect(node.params[ParamKeys.upMbps], 100);
    });

    test('reads a wireguard entry and adds the missing masks', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'WG',
        'type': 'wireguard',
        'server': 'wg.example.com',
        'port': 51820,
        'private-key': 'PK',
        'public-key': 'PEER',
        'ip': '10.0.0.2',
        'ipv6': 'fd00::2',
        'mtu': 1420,
        'reserved': <int>[0, 0, 0],
      });

      expect(node.protocol, Protocol.wireguard);
      expect(node.param(ParamKeys.localAddress), '10.0.0.2/32,fd00::2/128');
      expect(node.param(ParamKeys.reserved), '0,0,0');
      expect(node.params[ParamKeys.mtu], 1420);
    });

    test('names an unsupported clash type instead of guessing', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'old',
          'type': 'ssr',
          'server': 'a.example',
          'port': 443,
        }),
        throwsA(
          isA<LinkFormatException>().having(
            (error) => error.reason,
            'reason',
            contains('ssr'),
          ),
        ),
      );
    });

    test('rejects an entry with no port', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'uuid': 'u',
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a transport the core cannot carry', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'port': 443,
          'uuid': 'u',
          'network': 'xhttp',
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
