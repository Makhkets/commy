import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Ok reports isOk and carries its value', () {
      const result = Ok<int, CommyFailure>(42);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('Err reports isErr and carries its failure', () {
      const failure = ConfigInvalidFailure('bad');
      const result = Err<int, CommyFailure>(failure);

      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('map transforms the value and leaves a failure alone', () {
      const ok = Ok<int, CommyFailure>(2);
      const err = Err<int, CommyFailure>(ConfigInvalidFailure('bad'));

      expect(ok.map((value) => value * 2), const Ok<int, CommyFailure>(4));
      expect(
        err.map((value) => value * 2),
        const Err<int, CommyFailure>(ConfigInvalidFailure('bad')),
      );
    });

    test('mapErr transforms the failure and leaves the value alone', () {
      const ok = Ok<int, CommyFailure>(2);
      const err = Err<int, CommyFailure>(ConfigInvalidFailure('bad'));

      expect(ok.mapErr((failure) => failure.code), const Ok<int, String>(2));
      expect(
        err.mapErr((failure) => failure.code),
        const Err<int, String>('config_invalid'),
      );
    });

    test('flatMap chains only on success', () {
      const ok = Ok<int, CommyFailure>(2);
      const err = Err<int, CommyFailure>(ConfigInvalidFailure('bad'));
      Result<String, CommyFailure> stringify(int value) =>
          Ok<String, CommyFailure>('$value');

      expect(ok.flatMap(stringify), const Ok<String, CommyFailure>('2'));
      expect(
        err.flatMap(stringify),
        const Err<String, CommyFailure>(ConfigInvalidFailure('bad')),
      );
    });

    test('fold collapses both branches', () {
      const ok = Ok<int, CommyFailure>(2);
      const err = Err<int, CommyFailure>(ConfigInvalidFailure('bad'));

      expect(ok.fold((value) => 'v$value', (failure) => failure.code), 'v2');
      expect(
        err.fold((value) => 'v$value', (failure) => failure.code),
        'config_invalid',
      );
    });

    test('getOrElse falls back only on failure', () {
      const ok = Ok<int, CommyFailure>(2);
      const err = Err<int, CommyFailure>(ConfigInvalidFailure('bad'));

      expect(ok.getOrElse((_) => -1), 2);
      expect(err.getOrElse((_) => -1), -1);
    });

    test('equality is structural', () {
      expect(
        const Ok<int, CommyFailure>(1),
        equals(const Ok<int, CommyFailure>(1)),
      );
      expect(
        const Ok<int, CommyFailure>(1),
        isNot(equals(const Ok<int, CommyFailure>(2))),
      );
      expect(
        const Err<int, CommyFailure>(PermissionDeniedFailure()),
        equals(const Err<int, CommyFailure>(PermissionDeniedFailure())),
      );
      expect(
        const Ok<int, CommyFailure>(1).hashCode,
        const Ok<int, CommyFailure>(1).hashCode,
      );
    });

    test('a void result is expressible and compares equal', () {
      const first = Ok<void, CommyFailure>(null);
      const second = Ok<void, CommyFailure>(null);

      expect(first, equals(second));
      expect(first.isOk, isTrue);
    });
  });
}
