import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

ProxyNode node(
  String name, {
  Duration? latency,
  DateTime? checkedAt,
}) =>
    ProxyNode(
      id: name,
      name: name,
      protocol: Protocol.vless,
      host: 'example.net',
      port: 443,
      latency: latency,
      lastCheckedAt: checkedAt,
    );

List<String> names(List<ProxyNode> nodes) =>
    nodes.map((node) => node.name).toList();

void main() {
  final probed = DateTime.utc(2026, 9, 14);
  final panel = <ProxyNode>[
    node('Warsaw 01'),
    node('amsterdam 03', latency: const Duration(milliseconds: 48)),
    node('Berlin 02', checkedAt: probed),
    node('Zurich 04', latency: const Duration(milliseconds: 12)),
    node('Oslo 05'),
  ];

  test('panel keeps the list exactly as given', () {
    expect(NodeSort.panel.apply(panel), same(panel));
  });

  test('latency: measured fastest first, then never asked, then timed out', () {
    expect(
      names(NodeSort.latency.apply(panel)),
      <String>[
        'Zurich 04',
        'amsterdam 03',
        'Warsaw 01',
        'Oslo 05',
        'Berlin 02',
      ],
    );
  });

  test('name ignores case', () {
    expect(
      names(NodeSort.name.apply(panel)),
      <String>[
        'amsterdam 03',
        'Berlin 02',
        'Oslo 05',
        'Warsaw 01',
        'Zurich 04',
      ],
    );
  });

  test('servers the order cannot tell apart keep their panel order', () {
    final tied = <ProxyNode>[
      node('Zeta', latency: const Duration(milliseconds: 30)),
      node('Alpha', latency: const Duration(milliseconds: 30)),
      node('Mid'),
      node('Early'),
    ];

    expect(
      names(NodeSort.latency.apply(tied)),
      <String>['Zeta', 'Alpha', 'Mid', 'Early'],
    );
  });

  test('leaves the input untouched', () {
    final before = names(panel);
    NodeSort.name.apply(panel);
    NodeSort.latency.apply(panel);

    expect(names(panel), before);
  });
}
