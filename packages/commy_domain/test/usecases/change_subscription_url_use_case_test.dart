import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/subscription_fakes.dart';

/// Panels re-issue a link when the user resets it. The card follows it here
/// instead of being deleted and added again, which lost its interval, its
/// User-Agent, its recovery state and the chosen server.
void main() {
  late FakeSubscriptionRepository repository;
  late ChangeSubscriptionUrlUseCase change;

  final old = Uri.parse('https://panel.example.net/sub/old-token');
  final fresh = Uri.parse('https://panel.example.net/sub/new-token');

  Subscription card({
    String id = 'sub-1',
    Uri? url,
    String name = 'My panel',
  }) =>
      Subscription(
        id: id,
        name: name,
        url: url ?? old,
        updateIntervalHours: 6,
        userAgentOverride: 'Happ/3.0',
        autoUpdate: true,
      );

  setUp(() {
    repository = FakeSubscriptionRepository();
    change = ChangeSubscriptionUrlUseCase(subscriptions: repository);
  });

  test('the card keeps everything but its address', () async {
    repository.seed(card());

    final result = await change(subscriptionId: 'sub-1', url: fresh);

    expect(result.valueOrNull?.change, SubscriptionUrlChange.changed);
    final stored = (await repository.findById('sub-1')).valueOrNull!;
    expect(stored.url, fresh);
    expect(stored.name, 'My panel');
    expect(stored.updateIntervalHours, 6);
    expect(stored.userAgentOverride, 'Happ/3.0');
    expect(stored.autoUpdate, isTrue);
  });

  test('the same address in another spelling changes nothing', () async {
    repository.seed(card());

    final result = await change(
      subscriptionId: 'sub-1',
      url: Uri.parse('https://PANEL.example.net:443/sub/old-token#main'),
    );

    expect(result.valueOrNull?.change, SubscriptionUrlChange.unchanged);
    expect((await repository.findById('sub-1')).valueOrNull!.url, old);
  });

  // ADR-0008: two cards of one identity trade servers on every refresh.
  test('an address another card already has is refused, naming it', () async {
    repository
      ..seed(card())
      ..seed(card(id: 'sub-2', url: fresh, name: 'Other panel'));

    final result = await change(subscriptionId: 'sub-1', url: fresh);

    expect(result.valueOrNull?.change, SubscriptionUrlChange.taken);
    expect(result.valueOrNull?.subscription.name, 'Other panel');
    expect((await repository.findById('sub-1')).valueOrNull!.url, old);
  });

  test('something that is not an http(s) address is refused', () async {
    repository.seed(card());

    for (final raw in <String>[
      'vless://uuid@host:443',
      'panel.example.net/sub',
      'https://',
      'ftp://panel.example.net/sub',
    ]) {
      final result = await change(subscriptionId: 'sub-1', url: Uri.parse(raw));
      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    }
    expect((await repository.findById('sub-1')).valueOrNull!.url, old);
  });

  // The keystore lost the address: the card shows its redacted form, and a
  // new address is how it is repaired.
  test('a card whose address could not be read can be given one', () async {
    const path = Redact.pathPlaceholder;
    repository.seed(card(url: Uri.parse('https://panel.example.net/$path')));

    final result = await change(subscriptionId: 'sub-1', url: fresh);

    expect(result.valueOrNull?.change, SubscriptionUrlChange.changed);
    expect((await repository.findById('sub-1')).valueOrNull!.url, fresh);
  });

  test('a card that is not there is a failure, not a new card', () async {
    final result = await change(subscriptionId: 'missing', url: fresh);

    expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    expect((await repository.getAll()).valueOrNull, isEmpty);
  });

  // Review of session 25: a link of another provider kept the old one's
  // recovery state, and a failed refresh then handed the new token to the
  // old provider's mirrors.
  group('recovery state', () {
    final mirror = Uri.parse('https://mirror.panel.example.net');
    final moveTo = Uri.parse('https://new-panel.example.net');

    SubscriptionRecovery state({PendingDomainChange? pending}) =>
        SubscriptionRecovery(
          id: 'axm',
          key: 'k',
          seq: 3,
          mirrors: <Uri>[mirror],
          rendezvous: <Uri>[Uri.parse('https://meet.example.org/r/axm')],
          pending: pending,
        );

    Future<Subscription> changeTo(
      Uri url, {
      SubscriptionRecovery? recovery,
    }) async {
      repository.seed(card().copyWith(recovery: recovery ?? state()));
      await change(subscriptionId: 'sub-1', url: url);
      return (await repository.findById('sub-1')).valueOrNull!;
    }

    test('another provider drops it', () async {
      final stored = await changeTo(
        Uri.parse('https://sub.other-provider.org/api/sub/t2'),
      );
      expect(stored.recovery, isNull);
    });

    test('the same panel with a new token keeps it', () async {
      final stored = await changeTo(fresh);
      expect(stored.recovery?.mirrors, <Uri>[mirror]);
    });

    test('a mirror the provider signed keeps it', () async {
      final stored = await changeTo(
        Uri.parse('https://mirror.panel.example.net/sub/new-token'),
      );
      expect(stored.recovery?.seq, 3);
    });

    test('the address of a pending signed move takes the move', () async {
      final manifest = RecoveryManifest(
        id: 'axm',
        seq: 4,
        issuedAt: DateTime.utc(2026, 10),
        origin: moveTo,
        key: 'k',
        mirrors: <Uri>[Uri.parse('https://mirror2.example.net')],
      );
      final stored = await changeTo(
        Uri.parse('https://new-panel.example.net/sub/new-token'),
        recovery: state(
          pending: PendingDomainChange(
            manifest: manifest,
            source: RecoverySource.rendezvous,
          ),
        ),
      );
      expect(stored.recovery?.pending, isNull);
      expect(stored.recovery?.seq, 4);
      expect(
        stored.recovery?.mirrors,
        <Uri>[Uri.parse('https://mirror2.example.net')],
      );
    });
  });
}
