import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a subscription that could not be fetched is called, by cause.
///
/// The failure is one variant, `subscriptionUnreachable`; what went wrong
/// lives in its `HttpTransportError`, and the sentence has to follow it. A
/// sentence that fits one cause and is shown for another sends the user to fix
/// the wrong thing.
void main() {
  late Translations ru;
  late Translations en;

  setUpAll(() async {
    // `build` rather than `buildSync`: the English bundle is a deferred
    // library, exactly as the app loads it.
    ru = await AppLocale.ru.build();
    en = await AppLocale.en.build();
  });

  CommyFailure unreachable(HttpTransportError cause) =>
      CommyFailure.subscriptionUnreachable(
        url: Uri.parse('https://panel.example.net/sub/secret-token'),
        cause: cause,
      );

  CommyFailure status(int code) => unreachable(
        HttpTransportError(
          kind: HttpTransportError.kindStatus,
          statusCode: code,
        ),
      );

  group('a panel that answered with a status', () {
    test('a 4xx says the panel refused, with the status', () {
      for (final t in <Translations>[ru, en]) {
        for (final code in <int>[403, 404, 429]) {
          final text = FailureText.of(status(code), t);
          expect(
            text.message,
            t.error.subscriptionRefused.message(status: code),
          );
          expect(text.action, FailureAction.retry);
        }
      }
    });

    test('a 5xx is the server in trouble, not a revoked subscription', () {
      // A panel being restarted, nginx in front of a backend that is down, a
      // Cloudflare 52x: "the subscription may be expired or revoked" sent the
      // user to support over an outage.
      for (final t in <Translations>[ru, en]) {
        for (final code in <int>[500, 502, 503, 522]) {
          final text = FailureText.of(status(code), t);
          expect(
            text.message,
            isNot(t.error.subscriptionRefused.message(status: code)),
            reason: 'HTTP $code read as a refusal',
          );
          expect(
            text.message,
            t.error.subscriptionServerError.message(status: code),
          );
          expect(text.message, contains('$code'));
          expect(text.action, FailureAction.retry);
          expect(text.retryable, isTrue);
        }
      }
    });
  });

  test('a refused https-to-http redirect says what was refused', () {
    const cause = HttpTransportError(
      kind: HttpTransportError.kindInsecureRedirect,
    );
    for (final t in <Translations>[ru, en]) {
      final text = FailureText.of(unreachable(cause), t);
      expect(text.message, t.error.subscriptionInsecureRedirect.message);
      expect(text.message, isNot(t.error.subscriptionUnreachable.message));
      expect(text.action, FailureAction.openLogs);
    }
  });

  test('a redirect that could not be followed is not a silent server', () {
    for (final detail in <String>[
      'more than 5 redirects',
      'no Location',
      'unusable Location (ftp)',
    ]) {
      final cause = HttpTransportError(
        kind: HttpTransportError.kindRedirect,
        detail: detail,
      );
      for (final t in <Translations>[ru, en]) {
        final text = FailureText.of(unreachable(cause), t);
        expect(text.message, t.error.subscriptionRedirect.message);
        expect(text.message, isNot(t.error.subscriptionUnreachable.message));
        expect(text.action, FailureAction.openLogs);
      }
    }
  });

  test('a refused certificate is named, not called a silent server', () {
    // A self-signed panel or an expired certificate: "the server is not
    // answering" with a retry that gives the same answer every time.
    const cause = HttpTransportError(
      kind: HttpTransportError.kindCertificate,
      detail: 'CERTIFICATE_VERIFY_FAILED: certificate has expired',
    );
    for (final t in <Translations>[ru, en]) {
      final text = FailureText.of(unreachable(cause), t);
      expect(text.message, isNot(t.error.subscriptionUnreachable.message));
      expect(text.message, t.error.subscriptionCertificate.message);
      expect(text.actionLabel, t.error.subscriptionCertificate.action);
      // The platform's own reason is in the log line, and it is the one
      // thing that tells an expired certificate from a wrong device clock.
      expect(text.action, FailureAction.openLogs);
    }
  });
}
