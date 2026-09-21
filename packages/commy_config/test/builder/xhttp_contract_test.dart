import 'dart:convert';
import 'dart:io';

import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

/// The Dart half of a two-sided check. See the `_comment` in the fixture.
void main() {
  // `dart test` runs from the package directory.
  final fixture = File('../../core/xhttp/config/testdata/dart_blocks.json');
  final document =
      jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
  final cases = (document['cases']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList(growable: false);

  test('the fixture is not empty', () {
    expect(cases, isNotEmpty);
  });

  final parser = CommyLinkParser();
  for (final entry in cases) {
    test('the core is handed what the fixture promises: ${entry['name']}', () {
      final outcome = parser.parse('${entry['link']}').valueOrNull;
      expect(outcome?.failures, isEmpty, reason: 'the link did not parse');
      expect(outcome?.nodes, hasLength(1));

      final outbound =
          OutboundBuilder.build(node: outcome!.nodes.single, tag: 'out');
      expect(outbound['transport'], entry['transport']);
    });
  }
}
