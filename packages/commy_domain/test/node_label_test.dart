import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('NodeLabel.parse', () {
    test('a leading flag becomes the country and leaves the words', () {
      final label = NodeLabel.parse('🇨🇿 AXM VPN - Czech');

      expect(label.countryCode, 'CZ');
      expect(label.text, 'AXM VPN - Czech');
    });

    test('a name without a flag is left exactly as it was', () {
      final label = NodeLabel.parse('  Amsterdam 03 ');

      expect(label.countryCode, isNull);
      expect(label.text, '  Amsterdam 03 ');
    });

    test('a trailing flag is read the same way', () {
      final label = NodeLabel.parse('Frankfurt 🇩🇪');

      expect(label.countryCode, 'DE');
      expect(label.text, 'Frankfurt');
    });

    test('a flag in the middle closes the gap it leaves', () {
      final label = NodeLabel.parse('Warsaw 🇵🇱 01');

      expect(label.countryCode, 'PL');
      expect(label.text, 'Warsaw 01');
    });

    test('the separator a panel put next to the flag goes with it', () {
      expect(NodeLabel.parse('🇳🇱 | Amsterdam').text, 'Amsterdam');
      expect(NodeLabel.parse('🇳🇱 - Amsterdam').text, 'Amsterdam');
      expect(NodeLabel.parse('Amsterdam · 🇳🇱').text, 'Amsterdam');
      expect(NodeLabel.parse('🇳🇱Amsterdam').text, 'Amsterdam');
    });

    test('a dash inside the words is not a separator to tidy', () {
      expect(NodeLabel.parse('🇮🇹 AXM VPN - Italy').text, 'AXM VPN - Italy');
    });

    test('the European flag is passed through for the auto entry', () {
      final label = NodeLabel.parse('🇪🇺 Авто-Выбор');

      expect(label.countryCode, 'EU');
      expect(label.text, 'Авто-Выбор');
    });

    test('a route with two flags is shown whole, under the first country', () {
      final label = NodeLabel.parse('🇩🇪→🇳🇱 relay');

      expect(label.countryCode, 'DE');
      expect(label.text, '🇩🇪→🇳🇱 relay');
    });

    test('two flags back to back are two flags, not three', () {
      final label = NodeLabel.parse('🇩🇪🇳🇱 relay');

      expect(label.countryCode, 'DE');
      expect(label.text, '🇩🇪🇳🇱 relay');
    });

    test('a name that is nothing but a flag keeps it', () {
      final label = NodeLabel.parse('🇯🇵');

      expect(label.countryCode, 'JP');
      expect(label.text, '🇯🇵');
    });

    test('a lone regional indicator is not a flag', () {
      final label = NodeLabel.parse('🇩 node');

      expect(label.countryCode, isNull);
      expect(label.text, '🇩 node');
    });

    test('other emoji are none of its business', () {
      final label = NodeLabel.parse('🚀 Fast 🏴‍☠️');

      expect(label.countryCode, isNull);
      expect(label.text, '🚀 Fast 🏴‍☠️');
    });

    test('a code known from elsewhere wins, and the flag still goes', () {
      final label = NodeLabel.parse('🇩🇪 Frankfurt', countryCode: ' nl ');

      expect(label.countryCode, 'NL');
      expect(label.text, 'Frankfurt');
    });

    test('a blank known code counts as none', () {
      expect(NodeLabel.parse('Oslo', countryCode: '  ').countryCode, isNull);
      expect(NodeLabel.parse('🇳🇴 Oslo', countryCode: '').countryCode, 'NO');
    });
  });

  group('NodeLabel.of', () {
    test('reads the stored name and the stored code together', () {
      const node = ProxyNode(
        id: 'node-1',
        name: '🇫🇮 Helsinki',
        protocol: Protocol.vless,
        host: 'fi.example.net',
        port: 443,
      );

      expect(
        NodeLabel.of(node),
        const NodeLabel(text: 'Helsinki', countryCode: 'FI'),
      );
      expect(
        NodeLabel.of(node.copyWith(countryCode: 'SE')).countryCode,
        'SE',
      );
    });
  });

  group('NodeSort.name', () {
    test('orders by the words, not by the flag in front of them', () {
      ProxyNode named(String id, String name) => ProxyNode(
            id: id,
            name: name,
            protocol: Protocol.vless,
            host: '$id.example.net',
            port: 443,
          );

      final sorted = NodeSort.name.apply(<ProxyNode>[
        named('a', '🇳🇱 Zwolle'),
        named('b', 'Berlin'),
        named('c', '🇺🇸 Austin'),
      ]);

      expect(sorted.map((node) => node.id), <String>['c', 'b', 'a']);
    });
  });
}
