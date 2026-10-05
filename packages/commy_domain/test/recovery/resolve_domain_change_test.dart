import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/recovery_fakes.dart';
import '../support/subscription_fakes.dart';

void main() {
  final url = Uri.parse('https://sub.example.com/sub/TOKEN?f=1');

  SubscriptionRecovery asked() {
    final pinned = SubscriptionRecovery.pinned(
      SignedManifest.parse(compactOf(manifestJson()))!.manifest,
    );
    return RecoveryPolicy.consider(
      state: pinned,
      manifest: SignedManifest.parse(
        compactOf(manifestJson(seq: 2, origin: 'https://sub.example.online')),
      )!
          .manifest,
      source: RecoverySource.rendezvous,
      subscriptionUrl: url,
    ).state!;
  }

  late FakeSubscriptionRepository subscriptions;
  setUp(() {
    final card = Subscription(
      id: 's1',
      name: 'Panel',
      url: url,
      recovery: asked(),
    );
    subscriptions = FakeSubscriptionRepository()..seed(card);
  });

  test('accepting moves the address, keeps the card and the token', () async {
    final result = await ResolveDomainChangeUseCase(
      subscriptions: subscriptions,
    )(subscriptionId: 's1', accept: true);

    final stored = subscriptions.stored.single;
    expect(result.valueOrNull, stored);
    expect(stored.id, 's1');
    expect(stored.url, Uri.parse('https://sub.example.online/sub/TOKEN?f=1'));
    expect(stored.recovery?.pending, isNull);
    expect(stored.recovery?.seq, 2);
  });

  test('declining keeps the address and remembers the release', () async {
    await ResolveDomainChangeUseCase(
      subscriptions: subscriptions,
    )(subscriptionId: 's1', accept: false);

    final stored = subscriptions.stored.single;
    expect(stored.url, url);
    expect(stored.recovery?.pending, isNull);
    expect(stored.recovery?.declinedSeq, 2);
  });

  test('a second answer is not an error', () async {
    final useCase = ResolveDomainChangeUseCase(subscriptions: subscriptions);
    await useCase(subscriptionId: 's1', accept: true);

    final again = await useCase(subscriptionId: 's1', accept: false);

    expect(again.valueOrNull?.url.host, 'sub.example.online');
  });
}
