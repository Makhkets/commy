import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

void main() {
  group('SubscriptionHeaders', () {
    test('reads the quota block a panel sends', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'Subscription-Userinfo':
            'upload=1234; download=5678; total=107374182400; '
                'expire=1735689600',
      });
      final info = headers.userInfo;

      expect(info, isNotNull);
      expect(info!.upload, 1234);
      expect(info.download, 5678);
      expect(info.total, 107374182400);
      expect(info.expire, DateTime.utc(2025));
    });

    test('treats expire=0 as no expiry rather than 1970', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'subscription-userinfo': 'upload=0; download=0; total=0; expire=0',
      });

      expect(headers.userInfo!.expire, isNull);
      expect(headers.userInfo!.total, 0);
    });

    test('matches header names whatever the casing', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'PROFILE-UPDATE-INTERVAL': '12',
      });

      expect(headers.updateIntervalHours, 12);
    });

    test('takes the first value when a client hands back a list', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-title': <String>['First', 'Second'],
      });

      expect(headers.profileTitle, 'First');
    });

    test('decodes a base64 prefixed title', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-title': 'base64:0JzQvtC5INC/0YDQvtGE0LjQu9GM',
      });

      expect(headers.profileTitle, 'Мой профиль');
    });

    test('decodes an unprefixed title that is unambiguously base64', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-title': '0JzQvtC5INC/0YDQvtGE0LjQu9GM',
      });

      expect(headers.profileTitle, 'Мой профиль');
    });

    test('leaves a plain title alone', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-title': 'Personal servers',
      });

      expect(headers.profileTitle, 'Personal servers');
    });

    test('reads the provider and support URLs', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-web-page-url': 'https://panel.example.com/',
        'support-url': 'https://t.me/example',
      });

      expect(
        headers.profileWebPageUrl,
        Uri.parse('https://panel.example.com/'),
      );
      expect(headers.supportUrl, Uri.parse('https://t.me/example'));
    });

    test('ignores a web page URL that is not a URL', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-web-page-url': 'not a url',
      });

      expect(headers.profileWebPageUrl, isNull);
    });

    test('refuses a non-positive update interval', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-update-interval': '0',
      });

      expect(headers.updateIntervalHours, isNull);
    });

    test('invents nothing when the panel sent no headers', () {
      const headers = SubscriptionHeaders.empty;

      expect(headers.userInfo, isNull);
      expect(headers.profileTitle, isNull);
      expect(headers.updateIntervalHours, isNull);
      expect(headers.profileWebPageUrl, isNull);
    });

    test('wraps a body into a payload', () {
      final headers = SubscriptionHeaders.from(<String, Object?>{
        'profile-title': 'Personal servers',
        'profile-update-interval': '6',
      });
      final payload = headers.toPayload('vless://uuid@a.example:443#One');

      expect(payload.profileTitle, 'Personal servers');
      expect(payload.updateIntervalHours, 6);
      expect(payload.body, 'vless://uuid@a.example:443#One');
    });
  });
}
