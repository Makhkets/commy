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
