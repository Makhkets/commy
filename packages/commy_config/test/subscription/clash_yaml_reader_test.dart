import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

void main() {
  group('ClashYamlReader.tryParseDocument', () {
    test('reads a block mapping with nested blocks', () {
      final document = ClashYamlReader.tryParseDocument('''
port: 7890
allow-lan: false
dns:
  enable: true
  nameserver:
    - 1.1.1.1
    - 8.8.8.8
''');

      expect(document, isNotNull);
      expect(document!['port'], 7890);
      expect(document['allow-lan'], isFalse);
      final dns = document['dns']! as Map<String, Object?>;
      expect(dns['enable'], isTrue);
      expect(dns['nameserver'], <Object?>['1.1.1.1', '8.8.8.8']);
    });

    test('reads a sequence of mappings started on the dash line', () {
      final document = ClashYamlReader.tryParseDocument('''
proxies:
  - name: A
    port: 443
  - name: B
    port: 8443
''');
      final proxies = document!['proxies']! as List<Object?>;

      expect(proxies, hasLength(2));
      expect((proxies.first! as Map<String, Object?>)['name'], 'A');
      expect((proxies.last! as Map<String, Object?>)['port'], 8443);
    });

    test('reads flow mappings and flow sequences', () {
      final document = ClashYamlReader.tryParseDocument('''
ws-opts: { path: /ray, headers: { Host: cdn.example.com } }
alpn: [ h2, http/1.1 ]
''');
      final wsOpts = document!['ws-opts']! as Map<String, Object?>;
      final headers = wsOpts['headers']! as Map<String, Object?>;

      expect(wsOpts['path'], '/ray');
      expect(headers['Host'], 'cdn.example.com');
      expect(document['alpn'], <Object?>['h2', 'http/1.1']);
    });

    test('keeps a leading zero, because a short id needs it', () {
      final document = ClashYamlReader.tryParseDocument('''
reality-opts:
  short-id: 01ab
  other: 7
''');
      final reality = document!['reality-opts']! as Map<String, Object?>;

      expect(reality['short-id'], '01ab');
      expect(reality['other'], 7);
    });

    test('drops a comment that is not inside quotes', () {
      final document = ClashYamlReader.tryParseDocument('''
# a whole line
name: value # trailing
quoted: "a # b"
''');

      expect(document!['name'], 'value');
      expect(document['quoted'], 'a # b');
    });

    test('reads quoted scalars', () {
      final document = ClashYamlReader.tryParseDocument('''
double: "a: b"
single: 'it''s'
''');

      expect(document!['double'], 'a: b');
      expect(document['single'], "it's");
    });

    test('refuses a document with anchors rather than half reading it', () {
      final document = ClashYamlReader.tryParseDocument('''
defaults: &base
  type: vless
proxies:
  - <<: *base
    name: A
''');

      expect(document, isNull);
    });

    test('refuses a document with a block scalar', () {
      final document = ClashYamlReader.tryParseDocument('''
script: |
  some code
''');

      expect(document, isNull);
    });

    test('refuses an empty document', () {
      expect(ClashYamlReader.tryParseDocument('   '), isNull);
    });

    test('looksLikeClash keys off the proxies list', () {
      expect(ClashYamlReader.looksLikeClash('proxies:\n  - name: A'), isTrue);
      expect(ClashYamlReader.looksLikeClash('port: 7890'), isFalse);
    });
  });
}
