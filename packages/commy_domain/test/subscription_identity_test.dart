import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// One question, asked of every shape a person copies a subscription link in.
///
/// Getting it wrong is expensive in both directions. Too loose and two
/// accounts on one panel become one card; too strict and a trailing slash
/// makes a second card that quietly takes the first one's servers with it.
void main() {
  final canonical = Uri.parse('https://panel.example.com/sub/TOKEN?f=v2ray');

  group('the same subscription', () {
    test('a trailing slash is not a different endpoint', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com/sub/TOKEN/?f=v2ray'),
          canonical,
        ),
        isTrue,
      );
    });

    test('a fragment never reached the server to begin with', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com/sub/TOKEN?f=v2ray#main'),
          canonical,
        ),
        isTrue,
      );
    });

    test('query parameters in another order are the same request', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com/sub/TOKEN?b=2&a=1'),
          Uri.parse('https://panel.example.com/sub/TOKEN?a=1&b=2'),
        ),
        isTrue,
      );
    });

    test('the default port written out is still the default port', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com:443/sub/TOKEN?f=v2ray'),
          canonical,
        ),
        isTrue,
      );
    });

    test('the host is a name, and names have no case', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('HTTPS://Panel.Example.COM/sub/TOKEN?f=v2ray'),
          canonical,
        ),
        isTrue,
      );
    });
  });

  group('a different subscription', () {
    test('a token differing only in case is a different token', () {
      // The path is where most panels keep it, and tokens are case
      // sensitive. Folding this would hand one account's servers to another.
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com/sub/token?f=v2ray'),
          canonical,
        ),
        isFalse,
      );
    });

    test('two accounts on one panel stay two subscriptions', () {
      // The case an index on the host would have broken, which is why there
      // is no index.
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://alice@panel.example.com/sub/TOKEN?f=v2ray'),
          Uri.parse('https://bob@panel.example.com/sub/TOKEN?f=v2ray'),
        ),
        isFalse,
      );
    });

    test('a parameter with another value asks for something else', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com/sub/TOKEN?f=clash'),
          canonical,
        ),
        isFalse,
      );
    });

    test('a non-default port is part of the address', () {
      expect(
        SubscriptionIdentity.same(
          Uri.parse('https://panel.example.com:8443/sub/TOKEN?f=v2ray'),
          canonical,
        ),
        isFalse,
      );
    });
  });

  group('a URL the keystore could not give back', () {
    final unknown = Uri.parse('https://panel.example.com/redacted');

    test('is recognised as the placeholder it is', () {
      expect(SubscriptionIdentity.isUnknown(unknown), isTrue);
      expect(SubscriptionIdentity.isUnknown(canonical), isFalse);
    });

    test('never matches, not even another placeholder', () {
      // Two subscriptions whose URLs are both unreadable are not thereby the
      // same subscription — and answering otherwise would merge them.
      expect(SubscriptionIdentity.same(unknown, unknown), isFalse);
      expect(SubscriptionIdentity.same(unknown, canonical), isFalse);
    });
  });
}
