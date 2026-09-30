import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

ProxyNode node(String id, {required String name, int sortIndex = 0}) =>
    ProxyNode(
      id: id,
      name: name,
      protocol: Protocol.vless,
      host: 'example.net',
      port: 443,
      sortIndex: sortIndex,
    );

List<String> names(List<ProxyNode> nodes) =>
    nodes.map((node) => node.name).toList();

void main() {
  test('a server listed twice becomes one entry', () {
    final folded = NodeDuplicates.folded(<ProxyNode>[
      node('same', name: 'Amsterdam 03'),
      node('same', name: 'Games · Amsterdam 03'),
    ]);

    expect(folded, hasLength(1));
  });

  test('the last entry wins the fields', () {
    final folded = NodeDuplicates.folded(<ProxyNode>[
      node('same', name: 'Amsterdam 03'),
      node('same', name: 'Amsterdam 03 (backup)', sortIndex: 7),
    ]);

    expect(folded.single.name, 'Amsterdam 03 (backup)');
    expect(folded.single.sortIndex, 7);
  });

  test('the first entry keeps its place in the list', () {
    final folded = NodeDuplicates.folded(<ProxyNode>[
      node('repeat', name: 'Warsaw 01'),
      node('other', name: 'Oslo 05'),
      node('repeat', name: 'Warsaw 01 (games)'),
    ]);

    expect(names(folded), <String>['Warsaw 01 (games)', 'Oslo 05']);
  });

  test('a list with no repeats comes back in the order it arrived', () {
    final distinct = <ProxyNode>[
      node('a', name: 'Amsterdam 03'),
      node('b', name: 'Warsaw 10'),
      node('c', name: 'Oslo 01'),
    ];

    expect(
      names(NodeDuplicates.folded(distinct)),
      <String>['Amsterdam 03', 'Warsaw 10', 'Oslo 01'],
    );
  });

  test('an empty list folds to an empty list', () {
    expect(NodeDuplicates.folded(const <ProxyNode>[]), isEmpty);
  });

  test('leaves the input untouched', () {
    final panel = <ProxyNode>[
      node('same', name: 'Amsterdam 03'),
      node('same', name: 'Amsterdam 03 (backup)'),
      node('other', name: 'Oslo 05'),
    ];
    final before = names(panel);

    NodeDuplicates.folded(panel);

    expect(names(panel), before);
  });

  group('panel notices', () {
    // A panel with more than one line to say sends one entry per line, all
    // at the same nowhere address under the same placeholder credential, so
    // every line arrives under one id and only the text tells them apart.
    ProxyNode line(String text) => ProxyNode(
          id: 'stub',
          name: text,
          protocol: Protocol.vless,
          host: '0.0.0.0',
          port: 1,
        );

    test('every line of a notice is kept, in the order it was sent', () {
      final folded = NodeDuplicates.folded(<ProxyNode>[
        line('Subscription expired'),
        line('Contact support'),
      ]);

      expect(
        PanelNotice.messages(folded),
        <String>['Subscription expired', 'Contact support'],
      );
      expect(folded.map((node) => node.id).toSet(), hasLength(2));
    });

    test('a single line keeps the id it came with', () {
      final folded = NodeDuplicates.folded(<ProxyNode>[
        line('App not supported'),
      ]);

      expect(folded.single.id, 'stub');
    });

    test('the same line twice is still one row', () {
      final folded = NodeDuplicates.folded(<ProxyNode>[
        line('App not supported'),
        line('App not supported'),
      ]);

      expect(folded, hasLength(1));
    });

    test('folding again changes nothing', () {
      final once = NodeDuplicates.folded(<ProxyNode>[
        line('Subscription expired'),
        line('Contact support'),
        node('server', name: 'Amsterdam 03'),
      ]);

      final twice = NodeDuplicates.folded(once);

      expect(twice.map((node) => node.id), once.map((node) => node.id));
      expect(names(twice), names(once));
    });

    test('servers are folded as before, notices or not', () {
      final folded = NodeDuplicates.folded(<ProxyNode>[
        line('Subscription expired'),
        node('same', name: 'Amsterdam 03'),
        node('same', name: 'Games · Amsterdam 03'),
      ]);

      expect(folded, hasLength(2));
    });
  });

  test('the result refuses to be changed', () {
    final folded = NodeDuplicates.folded(<ProxyNode>[
      node('a', name: 'Amsterdam 03'),
    ]);

    expect(
      () => folded.add(node('b', name: 'Oslo 05')),
      throwsUnsupportedError,
    );
  });
}
