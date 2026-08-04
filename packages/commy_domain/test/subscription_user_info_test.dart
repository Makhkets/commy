import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const gigabyte = 1024 * 1024 * 1024;

  group('SubscriptionUserInfo quota maths', () {
    test('usedBytes sums what the panel reported', () {
      const info = SubscriptionUserInfo(upload: 100, download: 400);

      expect(info.usedBytes, 500);
    });

    test('usedBytes tolerates a half-filled header', () {
      const uploadOnly = SubscriptionUserInfo(upload: 100);
      const downloadOnly = SubscriptionUserInfo(download: 400);

      expect(uploadOnly.usedBytes, 100);
      expect(downloadOnly.usedBytes, 400);
    });

    test('usedBytes is null when the panel reported nothing', () {
      const info = SubscriptionUserInfo(total: 10);

      expect(info.usedBytes, isNull);
    });

    test('remainingBytes subtracts and never goes negative', () {
      const normal = SubscriptionUserInfo(
        upload: gigabyte,
        download: gigabyte,
        total: 10 * gigabyte,
      );
      const overspent = SubscriptionUserInfo(
        upload: 9 * gigabyte,
        download: 9 * gigabyte,
        total: 10 * gigabyte,
      );

      expect(normal.remainingBytes, 8 * gigabyte);
      expect(overspent.remainingBytes, 0);
    });

    test('an unlimited or unknown quota has no remainder and no ratio', () {
      const unlimited = SubscriptionUserInfo(upload: 1, download: 1);
      const zeroTotal = SubscriptionUserInfo(
        upload: 1,
        download: 1,
        total: 0,
      );

      expect(unlimited.hasQuota, isFalse);
      expect(unlimited.remainingBytes, isNull);
      expect(unlimited.ratio, isNull);
      expect(zeroTotal.hasQuota, isFalse);
      expect(zeroTotal.ratio, isNull);
    });

    test('ratio is the spent share, clamped to 0..1', () {
      const half = SubscriptionUserInfo(
        upload: 3 * gigabyte,
        download: 2 * gigabyte,
        total: 10 * gigabyte,
      );
      const overspent = SubscriptionUserInfo(
        upload: 20 * gigabyte,
        download: 0,
        total: 10 * gigabyte,
      );

      expect(half.ratio, closeTo(0.5, 1e-9));
      expect(overspent.ratio, 1);
    });

    test('isNearQuota trips at ninety per cent', () {
      const comfortable = SubscriptionUserInfo(
        upload: 5 * gigabyte,
        download: 0,
        total: 10 * gigabyte,
      );
      const tight = SubscriptionUserInfo(
        upload: 9 * gigabyte,
        download: 0,
        total: 10 * gigabyte,
      );

      expect(comfortable.isNearQuota, isFalse);
      expect(tight.isNearQuota, isTrue);
    });
  });

  group('SubscriptionUserInfo expiry maths', () {
    final now = DateTime.utc(2026, 8, 4, 12);

    test('daysLeftAt counts whole days and goes negative once past', () {
      final future = SubscriptionUserInfo(
        expire: now.add(const Duration(days: 18, hours: 5)),
      );
      final past = SubscriptionUserInfo(
        expire: now.subtract(const Duration(days: 2)),
      );

      expect(future.daysLeftAt(now), 18);
      expect(past.daysLeftAt(now), -2);
    });

    test('no expiry header means no numbers at all', () {
      const info = SubscriptionUserInfo(total: 10);

      expect(info.daysLeftAt(now), isNull);
      expect(info.isExpiringAt(now), isFalse);
      expect(info.isExpiredAt(now), isFalse);
    });

    test('isExpiringAt warns three days out and keeps warning after', () {
      final far = SubscriptionUserInfo(
        expire: now.add(const Duration(days: 10)),
      );
      final close = SubscriptionUserInfo(
        expire: now.add(const Duration(days: 2)),
      );
      final gone = SubscriptionUserInfo(
        expire: now.subtract(const Duration(days: 1)),
      );

      expect(far.isExpiringAt(now), isFalse);
      expect(close.isExpiringAt(now), isTrue);
      expect(gone.isExpiringAt(now), isTrue);
    });

    test('isExpiredAt flips exactly on the deadline', () {
      final info = SubscriptionUserInfo(expire: now);

      expect(info.isExpiredAt(now), isTrue);
      expect(
        info.isExpiredAt(now.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });

  group('Subscription refresh schedule', () {
    final now = DateTime.utc(2026, 8, 4, 12);
    final url = Uri.parse('https://panel.example.com/sub/token');

    test('auto update off means never due', () {
      final subscription = Subscription(
        id: 'a',
        name: 'Panel',
        url: url,
        lastUpdatedAt: now.subtract(const Duration(days: 30)),
      );

      expect(subscription.isRefreshDueAt(now), isFalse);
    });

    test('never fetched and auto update on means due right away', () {
      final subscription = Subscription(
        id: 'a',
        name: 'Panel',
        url: url,
        autoUpdate: true,
      );

      expect(subscription.isRefreshDueAt(now), isTrue);
    });

    test('the panel interval wins over the default', () {
      final subscription = Subscription(
        id: 'a',
        name: 'Panel',
        url: url,
        autoUpdate: true,
        updateIntervalHours: 1,
        lastUpdatedAt: now.subtract(const Duration(hours: 2)),
      );

      expect(subscription.updateInterval, const Duration(hours: 1));
      expect(subscription.isRefreshDueAt(now), isTrue);
    });

    test('with no panel interval the default is a day', () {
      final subscription = Subscription(
        id: 'a',
        name: 'Panel',
        url: url,
        autoUpdate: true,
        lastUpdatedAt: now.subtract(const Duration(hours: 2)),
      );

      expect(subscription.updateInterval, const Duration(hours: 24));
      expect(subscription.isRefreshDueAt(now), isFalse);
    });
  });

  group('Subscription redaction (rule R3)', () {
    test('redacted drops the token and toString never prints it', () {
      final subscription = Subscription(
        id: 'a',
        name: 'Panel',
        url: Uri.parse('https://panel.example.com/sub/s3cr3t?key=v'),
      );

      final safe = subscription.redacted();

      expect(safe.url.toString(), isNot(contains('s3cr3t')));
      expect(safe.url.toString(), contains('panel.example.com'));
      expect(subscription.toString(), isNot(contains('s3cr3t')));
    });
  });
}
