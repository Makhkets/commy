import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  final registry = LinkParserRegistry();

  group('LinkParserRegistry.canParse', () {
    test('recognises every scheme we ship', () {
      const links = <String>[
        'vless://u@a.example:443',
        'vmess://u@a.example:443',
        'trojan://p@a.example:443',
        'ss://YWVzLTI1Ni1nY206cHc@a.example:8388',
        'hysteria2://p@a.example:443',
        'hy2://p@a.example:443',
        'tuic://u:p@a.example:443',
        'wireguard://k@a.example:51820',
        'wg://k@a.example:51820',
        'shadowtls://p@a.example:443',
        'socks5://a.example:1080',
        'http://a.example:8080',
      ];

      for (final link in links) {
        expect(registry.canParse(link), isTrue, reason: link);
      }
    });

    test('does not mistake a subscription URL for a proxy', () {
      expect(registry.canParse('https://panel.example/sub/token'), isFalse);
    });

    test('says no to a scheme we do not implement', () {
      expect(registry.canParse('ssr://whatever'), isFalse);
      expect(registry.canParse('not a link at all'), isFalse);
    });
  });

  group('LinkParserRegistry.parseLines', () {
    test('imports the good lines and explains the bad ones', () {
      final outcome = registry.parseLines('''
# a comment
vless://uuid@a.example:443#One

// another comment
trojan://pw@b.example:443#Two
vless://@broken.example:443#Broken
this is not a link
''');

      expect(outcome.nodes, hasLength(2));
      expect(outcome.nodes.first.name, 'One');
      expect(outcome.nodes.last.name, 'Two');
      expect(outcome.failures, hasLength(2));
      expect(outcome.failures.last.reason, 'Line is not a proxy link');
    });

    test('numbers the nodes in the order the panel wrote them', () {
      final outcome = registry.parseLines(
        'vless://uuid@a.example:443#One\nvless://uuid@b.example:443#Two',
        startIndex: 5,
      );

      expect(outcome.nodes.map((node) => node.sortIndex), <int>[5, 6]);
    });

    test('stamps the subscription and the group on every node', () {
      final outcome = registry.parseLines(
        'vless://uuid@a.example:443#One',
        subscriptionId: 'sub-1',
        groupId: 'group-1',
      );

      expect(outcome.nodes.single.subscriptionId, 'sub-1');
      expect(outcome.nodes.single.groupId, 'group-1');
    });

    test('survives a leading byte order mark and CRLF endings', () {
      final outcome = registry.parseLines(
        '\u{FEFF}vless://uuid@a.example:443#One\r\n'
        'trojan://pw@b.example:443#Two\r\n',
      );

      expect(outcome.nodes, hasLength(2));
      expect(outcome.failures, isEmpty);
    });

    test('a broken line never throws', () {
      final outcome = registry.parseLines('vless://uuid@a.example:70000#x');

      expect(outcome.nodes, isEmpty);
      expect(outcome.failures, hasLength(1));
    });
  });

  group('LinkParserRegistry.toLink', () {
    test('finds the parser that owns a protocol', () {
      final node = registry.parse('vless://uuid@a.example:443#One');

      expect(registry.toLink(node), startsWith('vless://'));
    });

    test('reports a protocol with no share format', () {
      const node = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.vless,
        host: 'a.example',
        port: 443,
      );
      final other = LinkParserRegistry(parsers: const <NodeLinkParser>[]);

      expect(
        () => other.toLink(node),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
