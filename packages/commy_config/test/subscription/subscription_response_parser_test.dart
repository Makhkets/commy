import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _body = '''
vless://uuid@nl.example.com:443?security=tls&sni=nl.example.com#NL
trojan://pw@de.example.com:443#DE
''';

void main() {
  final parser = SubscriptionResponseParser();

  group('SubscriptionResponseParser', () {
    test('reads a Remnawave shaped response whole', () {
      final result = parser.parse(
        body: LenientBase64.encode(_body),
        headers: <String, Object?>{
          'subscription-userinfo':
              'upload=1024; download=2048; total=10737418240; '
                  'expire=1767225600',
          'profile-title': 'base64:0JzQvtC5INC/0YDQvtGE0LjQu9GM',
          'profile-update-interval': '12',
          'profile-web-page-url': 'https://panel.example.com/',
          'support-url': 'https://t.me/example',
        },
        subscriptionId: 'sub-1',
      );

      expect(result.nodes, hasLength(2));
      expect(result.nodes.first.subscriptionId, 'sub-1');
      expect(result.userInfo!.upload, 1024);
      expect(result.userInfo!.total, 10737418240);
      expect(result.payload.profileTitle, 'Мой профиль');
      expect(result.payload.updateIntervalHours, 12);
      expect(
        result.payload.profileWebPageUrl,
        Uri.parse('https://panel.example.com/'),
      );
      expect(result.failures, isEmpty);
    });

    test('invents nothing when the panel sent no headers', () {
      final result = parser.parse(body: _body);

      expect(result.nodes, hasLength(2));
      expect(result.userInfo, isNull);
      expect(result.payload.profileTitle, isNull);
      expect(result.announcement, isNull);
    });

    test('carries an announcement through without acting on it', () {
      final result = parser.parse(
        body: _body,
        headers: <String, Object?>{'announce': 'Maintenance on Sunday'},
      );

      expect(result.announcement, 'Maintenance on Sunday');
    });

    test('applies the reported metadata onto a subscription', () {
      final result = parser.parse(
        body: _body,
        headers: <String, Object?>{
          'profile-title': 'Personal',
          'profile-update-interval': '6',
        },
      );
      final updated = result.applyTo(
        Subscription(
          id: 'sub-1',
          name: 'Old name',
          url: Uri.parse('https://panel.example.com/sub/token'),
        ),
      );

      expect(updated.profileTitle, 'Personal');
      expect(updated.updateIntervalHours, 6);
      expect(updated.name, 'Old name');
    });

    test('parses a payload some other layer already fetched', () {
      final result = parser.parsePayload(
        const SubscriptionPayload(
          body: _body,
          userInfo: SubscriptionUserInfo(total: 100, download: 10),
        ),
        subscriptionId: 'sub-2',
      );

      expect(result.nodes, hasLength(2));
      expect(result.userInfo!.total, 100);
      expect(result.nodes.first.subscriptionId, 'sub-2');
    });

    test('a body that makes no sense still returns headers', () {
      final result = parser.parse(
        body: 'the quick brown fox',
        headers: <String, Object?>{'profile-title': 'Personal'},
      );

      expect(result.hasNodes, isFalse);
      expect(result.failures, isNotEmpty);
      expect(result.payload.profileTitle, 'Personal');
    });
  });
}
