import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/failure_log.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What the log says about a failed fetch.
///
/// The certificate and redirect messages send the user to the log. It used
/// to hold only `subscription refresh failed: subscription_unreachable`.
void main() {
  final url = Uri.parse('https://panel.example.net/sub/secret-token');
  const reason = 'CERTIFICATE_VERIFY_FAILED: certificate has expired';

  test('a refused certificate is logged with the reason', () {
    final line = FailureLog.describe(
      SubscriptionUnreachableFailure(
        url: url,
        cause: const HttpTransportError(
          kind: HttpTransportError.kindCertificate,
          detail: reason,
        ),
      ),
    );

    expect(line, 'subscription_unreachable (certificate: $reason)');
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('panel.example.net')));
  });

  test('a status is logged without a detail it does not have', () {
    final line = FailureLog.describe(
      SubscriptionUnreachableFailure(
        url: url,
        cause: const HttpTransportError(
          kind: HttpTransportError.kindStatus,
          statusCode: 403,
        ),
      ),
    );

    expect(line, 'subscription_unreachable (status 403)');
  });

  test('any other failure is its code', () {
    expect(
      FailureLog.describe(
        const CommyFailure.subscriptionMalformed('no proxies'),
      ),
      'subscription_malformed',
    );
  });

  test('a refresh from the card logs why it failed', () async {
    final logger = AppLogger(
      sink: (_) {},
      clock: () => CommyTestHarness.now,
    );
    addTearDown(logger.dispose);
    final harness =
        CommyTestHarness(subscriptions: <Subscription>[testSubscription()]);
    final container = ProviderContainer(
      overrides: harness.overrides(
        extra: <Override>[appLoggerProvider.overrideWithValue(logger)],
      ),
    );
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
      url: url,
      cause: const HttpTransportError(
        kind: HttpTransportError.kindCertificate,
        detail: reason,
      ),
    );

    await container.read(subscriptionControllerProvider.notifier).refresh(
          'sub-1',
        );

    final line = logger.buffer
        .map((line) => line.message)
        .firstWhere((message) => message.startsWith('subscription refresh'));
    expect(line, contains(reason));
  });
}
