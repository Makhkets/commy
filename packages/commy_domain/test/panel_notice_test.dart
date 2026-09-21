import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// A panel that will not serve this client sends one entry addressed at
/// nowhere, with the reason where a server's name goes. The app used to draw
/// it as a server — flag, ping button, "connect" — and never showed the one
/// part of the answer that meant anything.
void main() {
  ProxyNode node({required String host, String name = 'App not supported'}) =>
      ProxyNode(
        id: 'n-1',
        name: name,
        protocol: Protocol.vless,
        host: host,
        port: 1,
      );

  group('a message rather than a server', () {
    test('every way a panel writes "nowhere"', () {
      for (final host in <String>['0.0.0.0', '::', '[::]', ' 0.0.0.0 ']) {
        expect(
          PanelNotice.isNotice(node(host: host)),
          isTrue,
          reason: '$host addresses nothing',
        );
      }
    });

    test('hands back exactly what the panel wrote', () {
      expect(
        PanelNotice.messageOf(
          node(host: '0.0.0.0', name: 'Лимит устройств исчерпан'),
        ),
        'Лимит устройств исчерпан',
      );
    });

    test('an entry with no message has none to show', () {
      // The absence of servers already says something; a blank warning row
      // says it less clearly.
      expect(PanelNotice.messageOf(node(host: '0.0.0.0', name: '  ')), isNull);
    });
  });

  group('an ordinary server', () {
    test('is not a notice, whatever it is called', () {
      final server = node(host: 'nl-03.example.net');

      expect(PanelNotice.isNotice(server), isFalse);
      // The wording is free text in the admin's language. Matching on it
      // would work for English and for nobody else — and would hide a real
      // server from a user who named it as a joke.
      expect(PanelNotice.messageOf(server), isNull);
    });

    test('a port of 1 on a real address is still a server', () {
      expect(PanelNotice.isNotice(node(host: '10.0.0.1')), isFalse);
    });
  });

  group('splitting a list', () {
    final servers = <ProxyNode>[
      node(host: 'nl-03.example.net', name: 'Amsterdam 03'),
      node(host: 'de-01.example.net', name: 'Frankfurt 01'),
    ];
    final notice = node(host: '0.0.0.0');

    test('keeps the servers and drops the message', () {
      expect(
        PanelNotice.servers(<ProxyNode>[notice, ...servers]).map((n) => n.name),
        <String>['Amsterdam 03', 'Frankfurt 01'],
      );
    });

    test('keeps the message in the order the panel listed it', () {
      expect(
        PanelNotice.messages(<ProxyNode>[...servers, notice]),
        <String>['App not supported'],
      );
    });
  });
}
