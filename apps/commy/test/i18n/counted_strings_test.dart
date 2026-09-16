import 'package:commy/gen/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// The strings that put a number next to a noun.
///
/// English read "Imported 1 servers" after a one-server import, because the
/// English bundle held a single sentence with the plural noun baked in.
/// Russian sidestepped the question with "Импортировано узлов: $count", which
/// is grammatical but is not the sentence anyone would write by hand.
///
/// Both are now CLDR plurals. Russian is the base locale, so it is the base
/// that declares the plural and the parameter name (`param=count`, the name
/// every call site already passes); English follows with the two forms its
/// own CLDR categories use. The count is never spelled out in these
/// assertions where a shape comparison will do: what matters is that the
/// noun changes with the number, not which wording won.
void main() {
  // Every counted string, addressed exactly as its call site addresses it.
  // The named argument here is half the test: `param=count` is what keeps
  // `t.import.result.imported(count: …)` compiling.
  final counted = <String, String Function(Translations, int)>{
    'import.result.imported': (Translations t, int n) =>
        t.import.result.imported(count: n),
    'import.clipboard.many': (Translations t, int n) =>
        t.import.clipboard.many(count: n),
    'subscription.nodes': (Translations t, int n) =>
        t.subscription.nodes(count: n),
    'subscription.refreshed': (Translations t, int n) =>
        t.subscription.refreshed(count: n),
  };

  late Translations ru;
  late Translations en;

  setUpAll(() async {
    // `build` rather than `buildSync`: the English bundle is a deferred
    // library, exactly as the app loads it.
    ru = await AppLocale.ru.build();
    en = await AppLocale.en.build();
  });

  group('English counted strings', () {
    test('one reads differently from two', () {
      for (final entry in counted.entries) {
        expect(
          _shape(entry.value(en, 1), 1),
          isNot(_shape(entry.value(en, 2), 2)),
          reason: '${entry.key} reads "${entry.value(en, 1)}" for one',
        );
      }
    });

    test('zero takes the plural form', () {
      for (final entry in counted.entries) {
        expect(
          _shape(entry.value(en, 0), 0),
          _shape(entry.value(en, 2), 2),
          reason: '${entry.key} reads "${entry.value(en, 0)}" for none',
        );
      }
    });

    test('the import result says "1 server", not "1 servers"', () {
      // The defect this file exists for, pinned word for word: the panel is
      // the only report an import produces and a single server is the most
      // common import there is.
      expect(en.import.result.imported(count: 1), 'Imported 1 server');
      expect(en.import.result.imported(count: 2), 'Imported 2 servers');
    });
  });

  group('Russian counted strings', () {
    test('one, two and five are three different forms', () {
      for (final entry in counted.entries) {
        final one = _shape(entry.value(ru, 1), 1);
        final few = _shape(entry.value(ru, 2), 2);
        final many = _shape(entry.value(ru, 5), 5);

        expect(one, isNot(few), reason: '${entry.key}: 1 and 2 agree');
        expect(few, isNot(many), reason: '${entry.key}: 2 and 5 agree');
        expect(one, isNot(many), reason: '${entry.key}: 1 and 5 agree');
      }
    });

    test('the twenties and the teens follow the same rule as the units', () {
      for (final entry in counted.entries) {
        expect(
          _shape(entry.value(ru, 21), 21),
          _shape(entry.value(ru, 1), 1),
          reason: '${entry.key}: 21 is not read as 1',
        );
        expect(
          _shape(entry.value(ru, 22), 22),
          _shape(entry.value(ru, 2), 2),
          reason: '${entry.key}: 22 is not read as 2',
        );
        // The teens are the trap: 11 is "узлов", not "узел".
        expect(
          _shape(entry.value(ru, 11), 11),
          _shape(entry.value(ru, 5), 5),
          reason: '${entry.key}: 11 is not read as 5',
        );
      }
    });

    test('zero does not fall off the end of the resolver', () {
      // slang's Russian resolver answers zero with `zero ?? other`, so a
      // plural written with one/few/many and no `other` throws on an empty
      // import — and an empty import is exactly what a bad paste produces.
      for (final entry in counted.entries) {
        expect(
          _shape(entry.value(ru, 0), 0),
          _shape(entry.value(ru, 5), 5),
          reason: '${entry.key} does not read none as many',
        );
      }
    });

    test('the import result declines the noun', () {
      expect(ru.import.result.imported(count: 1), 'Импортирован 1 узел');
      expect(ru.import.result.imported(count: 2), 'Импортировано 2 узла');
      expect(ru.import.result.imported(count: 5), 'Импортировано 5 узлов');
    });
  });
}

/// [text] with the number blanked out, so two counts can be compared on their
/// grammar alone rather than on the digits they carry.
String _shape(String text, int count) => text.replaceAll('$count', '#');
