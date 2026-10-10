import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/recovery_fakes.dart';

/// The trust rules of docs/adr/0019-subscription-domain-recovery.md.
void main() {
  final subscriptionUrl =
      Uri.parse('https://sub.example.com/api/sub/TOKEN?f=raw');

  RecoveryManifest manifest({
    int seq = 1,
    String origin = 'https://sub.example.com',
    List<String> mirrors = const <String>['https://mirror.example.org'],
    String? key,
    String? nextKey,
  }) =>
      SignedManifest.parse(
        compactOf(
          manifestJson(
            seq: seq,
            origin: origin,
            mirrors: mirrors,
            key: key,
            nextKey: nextKey,
          ),
        ),
      )!
          .manifest;

  RecoveryUpdate consider(
    SubscriptionRecovery? state,
    RecoveryManifest manifest, {
    RecoverySource source = RecoverySource.primary,
  }) =>
      RecoveryPolicy.consider(
        state: state,
        manifest: manifest,
        source: source,
        subscriptionUrl: subscriptionUrl,
      );

  group('a subscription with no key yet', () {
    test('pins the first manifest from its own address', () {
      final update = consider(null, manifest());

      expect(update.verdict, RecoveryVerdict.pinned);
      expect(update.state?.key, testKey());
      expect(update.state?.seq, 1);
      expect(update.state?.mirrors, hasLength(1));
      expect(update.state?.pending, isNull);
    });

    test('never pins from a mirror or a meeting point', () {
      for (final source in <RecoverySource>[
        RecoverySource.mirror,
        RecoverySource.rendezvous,
      ]) {
        final update = consider(null, manifest(), source: source);
        expect(update.verdict, RecoveryVerdict.refused, reason: '$source');
        expect(update.state, isNull);
      }
    });

    test('a manifest naming another main address pins, and asks', () {
      final moved = manifest(origin: 'https://sub.example.online');

      final update = consider(null, moved);

      expect(update.verdict, RecoveryVerdict.pending);
      expect(update.state?.key, testKey());
      expect(update.state?.pending?.manifest, moved);
      // Nothing of the release is taken until it is answered: no mirrors to
      // fetch from, and the accepted release is none.
      expect(update.state?.mirrors, isEmpty);
      expect(update.state?.seq, 0);
    });
  });

  group('a subscription with a pinned key', () {
    final pinned = SubscriptionRecovery.pinned(manifest(seq: 3));

    test('an older release is a replay', () {
      expect(consider(pinned, manifest()).verdict, RecoveryVerdict.stale);
    });

    test('the same release is no news', () {
      final update = consider(pinned, manifest(seq: 3));

      expect(update.verdict, RecoveryVerdict.unchanged);
      expect(update.state, pinned);
    });

    test('its own address changes mirrors silently', () {
      final update = consider(
        pinned,
        manifest(seq: 4, mirrors: <String>['https://new-mirror.example']),
      );

      expect(update.verdict, RecoveryVerdict.adopted);
      expect(update.state?.seq, 4);
      expect(
        update.state?.mirrors,
        <Uri>[Uri.parse('https://new-mirror.example')],
      );
    });

    test('a move of the main address is always a question', () {
      for (final source in RecoverySource.values) {
        final update = consider(
          pinned,
          manifest(seq: 4, origin: 'https://sub.example.online'),
          source: source,
        );
        expect(update.verdict, RecoveryVerdict.pending, reason: '$source');
        expect(update.state?.seq, 3, reason: 'Not taken before the answer.');
        expect(update.state?.pending?.source, source);
      }
    });

    test('new hosts from a meeting point are a question too', () {
      final update = consider(
        pinned,
        manifest(seq: 4, mirrors: <String>['https://attacker.example']),
        source: RecoverySource.rendezvous,
      );

      expect(update.verdict, RecoveryVerdict.pending);
      expect(update.state?.mirrors, pinned.mirrors);
    });

    test('a meeting point may confirm what is already trusted, silently', () {
      final update = consider(
        pinned,
        manifest(seq: 4, mirrors: const <String>[]),
        source: RecoverySource.rendezvous,
      );

      expect(update.verdict, RecoveryVerdict.adopted);
      expect(update.state?.seq, 4);
      expect(update.state?.mirrors, isEmpty);
    });

    test('a pending question is not asked twice, a newer one replaces it', () {
      final asked = consider(
        pinned,
        manifest(seq: 4, origin: 'https://sub.example.online'),
      ).state!;

      expect(
        consider(
          asked,
          manifest(seq: 4, origin: 'https://sub.example.online'),
        ).verdict,
        RecoveryVerdict.pending,
      );
      final newer = consider(
        asked,
        manifest(seq: 5, origin: 'https://sub.example.site'),
      );
      expect(newer.state?.pending?.manifest.seq, 5);
    });
  });

  group('the answer', () {
    final pinned = SubscriptionRecovery.pinned(manifest(seq: 3));
    final asked = RecoveryPolicy.consider(
      state: pinned,
      manifest: manifest(
        seq: 4,
        origin: 'https://sub.example.online:8443',
        mirrors: <String>['https://m2.example'],
      ),
      source: RecoverySource.rendezvous,
      subscriptionUrl: subscriptionUrl,
    ).state!;

    test('accepting moves the address and keeps the token', () {
      final accepted = RecoveryPolicy.accept(asked, subscriptionUrl)!;

      expect(
        accepted.url,
        Uri.parse('https://sub.example.online:8443/api/sub/TOKEN?f=raw'),
      );
      expect(accepted.state.seq, 4);
      expect(accepted.state.mirrors, <Uri>[Uri.parse('https://m2.example')]);
      expect(accepted.state.pending, isNull);
    });

    test('declining forgets the move and does not offer it again', () {
      final declined = RecoveryPolicy.decline(asked);

      expect(declined.pending, isNull);
      expect(declined.declinedSeq, 4);
      expect(declined.seq, 3);
      expect(declined.mirrors, pinned.mirrors);
      expect(
        RecoveryPolicy.consider(
          state: declined,
          manifest: manifest(seq: 4, origin: 'https://sub.example.online'),
          source: RecoverySource.rendezvous,
          subscriptionUrl: subscriptionUrl,
        ).verdict,
        RecoveryVerdict.declined,
      );
    });

    test('nothing pending, nothing to accept', () {
      expect(RecoveryPolicy.accept(pinned, subscriptionUrl), isNull);
      expect(RecoveryPolicy.decline(pinned), pinned);
    });
  });

  group('key rotation', () {
    test('a release signed by the announced key takes it over', () {
      final pinned = SubscriptionRecovery.pinned(
        manifest(seq: 3, nextKey: testKey(9)),
      );

      final update = consider(pinned, manifest(seq: 4, key: testKey(9)));

      expect(update.verdict, RecoveryVerdict.adopted);
      expect(update.state?.key, testKey(9));
      expect(update.state?.nextKey, isNull);
    });
  });

  group('meeting points are due', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    final state = SubscriptionRecovery.pinned(manifest())
        .copyWith(lastRendezvousAt: now.subtract(const Duration(hours: 2)));

    test('once a day while the address works', () {
      expect(
        RecoveryPolicy.rendezvousDue(state, now, primaryFailed: false),
        isFalse,
      );
      expect(
        RecoveryPolicy.rendezvousDue(
          state,
          now.add(const Duration(hours: 22)),
          primaryFailed: false,
        ),
        isTrue,
      );
    });

    test('every quarter of an hour while it fails', () {
      expect(
        RecoveryPolicy.rendezvousDue(state, now, primaryFailed: true),
        isTrue,
      );
      expect(
        RecoveryPolicy.rendezvousDue(
          state.copyWith(lastRendezvousAt: now),
          now.add(const Duration(minutes: 10)),
          primaryFailed: true,
        ),
        isFalse,
      );
    });

    test('never when switched off or with nowhere to go', () {
      expect(
        RecoveryPolicy.rendezvousDue(
          state.copyWith(enabled: false),
          now,
          primaryFailed: true,
        ),
        isFalse,
      );
      expect(
        RecoveryPolicy.rendezvousDue(
          state.copyWith(rendezvous: const <Uri>[]),
          now,
          primaryFailed: true,
        ),
        isFalse,
      );
    });
  });

  group('ManifestReader', () {
    test('believes a valid signature and nothing else', () async {
      final reader = ManifestReader(verifier: FakeVerifier());

      expect(await reader.read(compactOf(manifestJson())), isNotNull);
      expect(
        await reader.read(compactOf(manifestJson(), signature: 2)),
        isNull,
      );
      expect(await reader.read(null), isNull);
      expect(await reader.read('garbage'), isNull);
    });

    test('a stranger is refused before a verification is spent on it',
        () async {
      final verifier = FakeVerifier();
      final reader = ManifestReader(verifier: verifier);
      final pinned = SubscriptionRecovery.pinned(
        SignedManifest.parse(compactOf(manifestJson()))!.manifest,
      );

      expect(
        await reader.read(
          compactOf(manifestJson(seq: 2, key: testKey(3))),
          pinned: pinned,
        ),
        isNull,
      );
      expect(
        await reader.read(
          compactOf(manifestJson(seq: 2, id: 'other')),
          pinned: pinned,
        ),
        isNull,
      );
      expect(verifier.asked, isEmpty);
      expect(
        await reader.read(compactOf(manifestJson(seq: 2)), pinned: pinned),
        isNotNull,
      );
    });
  });

  test('a subscription carries its recovery state through JSON', () {
    final state = SubscriptionRecovery.pinned(manifest()).copyWith(
      lastRendezvousAt: DateTime.utc(2026, 10, 5),
      pending: PendingDomainChange(
        manifest: manifest(seq: 2, origin: 'https://sub.example.online'),
        source: RecoverySource.rendezvous,
      ),
      declinedSeq: 1,
      enabled: false,
    );
    final subscription = Subscription(
      id: 's1',
      name: 'Panel',
      url: subscriptionUrl,
      recovery: state,
    );

    final back = Subscription.fromJson(subscription.toJson());

    expect(back.recovery, state);
    expect(back, subscription);
  });

  test('a recovery state that does not read costs the state, not the card', () {
    final json = Subscription(id: 's1', name: 'Panel', url: subscriptionUrl)
        .toJson()
      ..['recovery'] = <String, Object?>{'id': 'x'};

    final back = Subscription.fromJson(json);

    expect(back.recovery, isNull);
    expect(back.name, 'Panel');
  });
}
