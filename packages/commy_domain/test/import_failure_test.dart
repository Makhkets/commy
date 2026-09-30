import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// What the app words a skipped line from has to survive every copy of it.
void main() {
  const failure = ImportFailure(
    rawLine: 'vless://8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88@a.example:443',
    reason: 'Transport "kcp" is not supported by the core',
    kind: ImportFailureKind.unsupported,
    subject: 'kcp',
  );

  test('a redacted copy keeps the kind and the subject', () {
    final redacted = failure.redacted();

    expect(redacted.rawLine, isNot(contains('8f3c1e6a')));
    expect(redacted.kind, ImportFailureKind.unsupported);
    expect(redacted.subject, 'kcp');
  });

  test('the kind and the subject go through JSON and back', () {
    expect(ImportFailure.fromJson(failure.toJson()), failure);
  });

  test('a map from before the kind existed reads as a broken line', () {
    final older = ImportFailure.fromJson(<String, Object?>{
      'rawLine': 'x',
      'reason': 'Line is not a proxy link',
    });

    expect(older.kind, ImportFailureKind.malformed);
    expect(older.subject, isNull);
    expect(
      ImportFailure.fromJson(<String, Object?>{
        'rawLine': 'x',
        'reason': 'y',
        'kind': 'somethingNewer',
      }).kind,
      ImportFailureKind.malformed,
    );
  });

  test('an unnamed failure is a broken line', () {
    expect(
      const ImportFailure(rawLine: 'x', reason: 'y').kind,
      ImportFailureKind.malformed,
    );
  });
}
