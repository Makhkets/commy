import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

HttpTransportError? causeOf(CommyFailure failure) =>
    (failure as SubscriptionUnreachableFailure).cause as HttpTransportError?;

/// What dio hands over when `dart:io` threw [error] under it.
///
/// Our client sets no `validateCertificate`, so dio never raises
/// `badCertificate` itself: the platform's exception is wrapped as `unknown`,
/// the way `DioMixin.assureDioException` does it.
DioException wrapped(Object error) => DioException(
      requestOptions: RequestOptions(path: Fixtures.subscriptionUrl.toString()),
      error: error,
    );

void main() {
  group('NetworkFailureMapper and certificates', () {
    const expired = HandshakeException(
      'Handshake error in client',
      OSError(
        'CERTIFICATE_VERIFY_FAILED: certificate has expired(handshake.cc:393)',
        1,
      ),
    );

    test('a certificate the platform refused is a certificate failure', () {
      // It used to read `unknown: HandshakeException` and reach the user as
      // "the subscription server is not answering", with a retry that gives
      // the same answer every time.
      final cause = causeOf(
        NetworkFailureMapper.fromDio(
          wrapped(expired),
          Fixtures.subscriptionUrl,
        ),
      );

      expect(cause?.kind, HttpTransportError.kindCertificate);
      expect(cause?.detail, contains('certificate has expired'));
    });

    test('the same exception outside dio is read the same way', () {
      expect(
        causeOf(
          NetworkFailureMapper.fromError(expired, Fixtures.subscriptionUrl),
        )?.kind,
        HttpTransportError.kindCertificate,
      );
      expect(
        causeOf(
          NetworkFailureMapper.fromError(
            const CertificateException('self-signed'),
            Fixtures.subscriptionUrl,
          ),
        )?.kind,
        HttpTransportError.kindCertificate,
      );
    });

    test('a handshake that failed for another reason is not blamed on it', () {
      // An https URL aimed at a port that speaks plain HTTP fails the
      // handshake too, and the certificate has nothing to do with it.
      const notTls = HandshakeException(
        'Handshake error in client',
        OSError('WRONG_VERSION_NUMBER(tls_record.cc:231)', 1),
      );

      expect(
        causeOf(
          NetworkFailureMapper.fromDio(
            wrapped(notTls),
            Fixtures.subscriptionUrl,
          ),
        )?.kind,
        isNot(HttpTransportError.kindCertificate),
      );
    });

    test('the cause never carries the address', () {
      final failure = NetworkFailureMapper.fromDio(
        wrapped(expired),
        Fixtures.subscriptionUrl,
      );

      expect(
        causeOf(failure).toString(),
        isNot(contains(Fixtures.subscriptionUrl.host)),
      );
    });
  });
}
