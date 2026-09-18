import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('CommyFailure.retryable', () {
    test('transport and tunnel problems are worth retrying', () {
      final unreachable = CommyFailure.subscriptionUnreachable(
        url: Uri.parse('https://panel.example.com/sub/token'),
        cause: 'timeout',
      );

      expect(unreachable.retryable, isTrue);
      expect(const PermissionDeniedFailure().retryable, isTrue);
      expect(const HelperUnavailableFailure().retryable, isTrue);
      expect(const CoreCrashedFailure('boom').retryable, isTrue);
    });

    test('bad input and bad state are not worth retrying', () {
      expect(const SubscriptionMalformedFailure('junk').retryable, isFalse);
      expect(const UnsupportedProtocolFailure('ftp').retryable, isFalse);
      expect(const ConfigInvalidFailure('no outbound').retryable, isFalse);
      expect(const StorageFailure('disk full').retryable, isFalse);
      expect(
        UnknownFailure('x', StackTrace.current).retryable,
        isFalse,
      );
    });
  });

  group('CommyFailure.code', () {
    test('every variant has a distinct, stable code', () {
      final failures = <CommyFailure>[
        CommyFailure.subscriptionUnreachable(
          url: Uri.parse('https://panel.example.com/sub'),
          cause: 'timeout',
        ),
        const SubscriptionMalformedFailure('junk'),
        const UnsupportedProtocolFailure('ftp'),
        const ConfigInvalidFailure('no outbound'),
        const PermissionDeniedFailure(),
        const HelperUnavailableFailure(),
        const CoreCrashedFailure('boom'),
        const StorageFailure('disk full'),
        UnknownFailure('x', StackTrace.current),
      ];

      final codes = failures.map((failure) => failure.code).toList();

      expect(codes.toSet().length, codes.length);
      expect(
        codes,
        <String>[
          'subscription_unreachable',
          'subscription_malformed',
          'unsupported_protocol',
          'config_invalid',
          'permission_denied',
          'helper_unavailable',
          'core_crashed',
          'storage',
          'unknown',
        ],
      );
    });
  });

  group('CommyFailure redaction (rule R3)', () {
    test('toString never leaks the subscription token', () {
      final failure = CommyFailure.subscriptionUnreachable(
        url: Uri.parse('https://panel.example.com/sub/s3cr3t-token?k=v'),
        cause: 'timeout',
      );

      final text = failure.toString();

      expect(text, contains('panel.example.com'));
      expect(text, contains('[redacted]'));
      expect(text, isNot(contains('s3cr3t-token')));
      expect(text, isNot(contains('k=v')));
    });

    test('toString of a core crash omits the log body', () {
      const failure = CoreCrashedFailure('outbound 10.1.2.3:443 died');

      expect(failure.toString(), isNot(contains('10.1.2.3')));
    });
  });

  group('CommyFailure factories', () {
    test('factory constructors build the matching variant', () {
      expect(
        const CommyFailure.configInvalid('x'),
        isA<ConfigInvalidFailure>(),
      );
      expect(
        const CommyFailure.permissionDenied(),
        isA<PermissionDeniedFailure>(),
      );
      expect(
        const CommyFailure.unsupportedProtocol('ftp'),
        equals(const UnsupportedProtocolFailure('ftp')),
      );
    });
  });
  group('CommyFailure.fromCaught', () {
    test('a failure that was thrown as itself stays what it was', () {
      const thrown = CommyFailure.permissionDenied();

      expect(CommyFailure.fromCaught(thrown, StackTrace.empty), same(thrown));
    });

    test('a carrier hands back the failure it was thrown for', () {
      final caught = CommyFailure.fromCaught(
        const _Carrier(CommyFailure.helperUnavailable()),
        StackTrace.empty,
      );

      expect(caught, const CommyFailure.helperUnavailable());
    });

    test('only what nobody classified becomes unknown', () {
      final error = StateError('boom');
      final caught = CommyFailure.fromCaught(error, StackTrace.empty);

      expect(caught, isA<UnknownFailure>());
      expect((caught as UnknownFailure).cause, same(error));
    });
  });
}

class _Carrier implements Exception, FailureCarrier {
  const _Carrier(this.failure);

  @override
  final CommyFailure failure;
}
