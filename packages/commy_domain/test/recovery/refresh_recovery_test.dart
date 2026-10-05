import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/recovery_fakes.dart';
import '../support/subscription_fakes.dart';

/// A refresh of a subscription whose provider signs recovery manifests
/// (docs/adr/0019-subscription-domain-recovery.md): mirrors when the address
/// fails, meeting points when everything fails or once a day, and a move of
/// the address stored as a question, never taken.
void main() {
  final primaryUrl = Uri.parse('https://sub.example.com/sub/TOKEN');
  final mirrorUrl = Uri.parse('https://mirror.example.org/sub/TOKEN');
  final meetingPoint = Uri.parse('https://meet.example.net/r/axm');
  final now = DateTime.utc(2026, 10, 5, 12);

  late FakeSubscriptionRepository subscriptions;
  late RecordingNodeRepository nodes;
  late _RoutedFetcher fetcher;
  late FakeRendezvous rendezvous;

  final servers = ParseOutcome(
    nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
  );

  UpdateSubscriptionUseCase useCase({
    ParseOutcome? outcome,
    DateTime? at,
  }) =>
      UpdateSubscriptionUseCase(
        fetcher: fetcher,
        parser: _BodyParser(outcome ?? servers),
        subscriptions: subscriptions,
        nodes: nodes,
        recovery: RecoveryEngine(
          reader: ManifestReader(verifier: FakeVerifier()),
          rendezvous: rendezvous,
          clock: () => at ?? now,
        ),
      );

  SubscriptionRecovery pinned({int seq = 1, DateTime? visited}) =>
      SubscriptionRecovery.pinned(
        SignedManifest.parse(compactOf(manifestJson(seq: seq)))!.manifest,
      ).copyWith(lastRendezvousAt: visited ?? now);

  void seed({SubscriptionRecovery? recovery}) => subscriptions.seed(
        Subscription(
          id: 'sub-1',
          name: 'Panel',
          url: primaryUrl,
          autoUpdate: true,
          recovery: recovery,
        ),
      );

  setUp(() {
    subscriptions = FakeSubscriptionRepository();
    nodes = RecordingNodeRepository();
    fetcher = _RoutedFetcher();
    rendezvous = FakeRendezvous();
  });

  test('the first manifest from the address pins its key', () async {
    seed();
    fetcher.answers[primaryUrl] = SubscriptionPayload(
      body: 'servers',
      manifest: compactOf(manifestJson()),
    );

    final result = await useCase()(subscriptionId: 'sub-1');

    expect(result.valueOrNull?.servedBy, RecoverySource.primary);
    final recovery = subscriptions.stored.single.recovery;
    expect(recovery?.key, testKey());
    expect(recovery?.mirrors, <Uri>[Uri.parse('https://mirror.example.org')]);
    // Pinned on an answer: no meeting point is asked in the same breath.
    expect(rendezvous.visits, isEmpty);
    expect(recovery?.lastRendezvousAt, now);
  });

  test('a forged manifest is not pinned', () async {
    seed();
    fetcher.answers[primaryUrl] = SubscriptionPayload(
      body: 'servers',
      manifest: compactOf(manifestJson(), signature: 2),
    );

    await useCase()(subscriptionId: 'sub-1');

    expect(subscriptions.stored.single.recovery, isNull);
  });

  test('a subscription without a manifest never reaches out', () async {
    seed();
    fetcher.failures[primaryUrl] = SubscriptionUnreachableFailure(
      url: primaryUrl,
      cause: 'blocked',
    );

    final result = await useCase()(subscriptionId: 'sub-1');

    expect(result.failureOrNull, isA<SubscriptionUnreachableFailure>());
    expect(fetcher.requests, <Uri>[primaryUrl]);
    expect(rendezvous.visits, isEmpty);
  });

  test('a blocked address is served by the mirror, token and all', () async {
    seed(recovery: pinned());
    fetcher
      ..failures[primaryUrl] = SubscriptionUnreachableFailure(
        url: primaryUrl,
        cause: 'blocked',
      )
      ..answers[mirrorUrl] = const SubscriptionPayload(body: 'servers');

    final result = await useCase()(subscriptionId: 'sub-1');

    expect(fetcher.requests, <Uri>[primaryUrl, mirrorUrl]);
    expect(result.valueOrNull?.servedBy, RecoverySource.mirror);
    expect(nodes.stored.single.name, 'Frankfurt 07');
    // The address is not changed by a mirror answering.
    expect(subscriptions.stored.single.url, primaryUrl);
  });

  test(
      'when every address fails, the meeting point is asked, and a move '
      'waits for the user', () async {
    seed(recovery: pinned(visited: now.subtract(const Duration(hours: 1))));
    fetcher
      ..failures[primaryUrl] = SubscriptionUnreachableFailure(
        url: primaryUrl,
        cause: 'blocked',
      )
      ..failures[mirrorUrl] = SubscriptionUnreachableFailure(
        url: mirrorUrl,
        cause: 'blocked',
      );
    rendezvous.served[meetingPoint] = compactOf(
      manifestJson(seq: 2, origin: 'https://sub.example.online'),
    );

    final result = await useCase()(subscriptionId: 'sub-1');

    expect(result.failureOrNull, isNotNull);
    expect(rendezvous.visits, <Uri>[meetingPoint]);
    final stored = subscriptions.stored.single;
    expect(stored.url, primaryUrl, reason: 'Never moved without the user.');
    expect(
      stored.recovery?.pending?.manifest.origin,
      Uri.parse('https://sub.example.online'),
    );
    expect(stored.recovery?.lastRendezvousAt, now);
  });

  test('a meeting point is not asked again within the quarter hour', () async {
    seed(recovery: pinned(visited: now.subtract(const Duration(minutes: 5))));
    fetcher
      ..failures[primaryUrl] = SubscriptionUnreachableFailure(
        url: primaryUrl,
        cause: 'blocked',
      )
      ..failures[mirrorUrl] = SubscriptionUnreachableFailure(
        url: mirrorUrl,
        cause: 'blocked',
      );

    await useCase()(subscriptionId: 'sub-1');

    expect(rendezvous.visits, isEmpty);
  });

  test(
      'once a day, a working address does not stop the visit — a taken-over '
      'domain answers too', () async {
    seed(recovery: pinned(visited: now.subtract(const Duration(hours: 25))));
    fetcher.answers[primaryUrl] = const SubscriptionPayload(body: 'servers');
    rendezvous.served[meetingPoint] = compactOf(
      manifestJson(seq: 2, origin: 'https://sub.example.online'),
    );

    final result = await useCase()(subscriptionId: 'sub-1');

    expect(result.valueOrNull, isNotNull);
    expect(rendezvous.visits, <Uri>[meetingPoint]);
    expect(subscriptions.stored.single.recovery?.pending, isNotNull);
  });

  test('switched off, nothing but the address is asked', () async {
    seed(
      recovery: pinned(visited: now.subtract(const Duration(days: 3)))
          .copyWith(enabled: false),
    );
    fetcher.failures[primaryUrl] = SubscriptionUnreachableFailure(
      url: primaryUrl,
      cause: 'blocked',
    );

    await useCase()(subscriptionId: 'sub-1');

    expect(fetcher.requests, <Uri>[primaryUrl]);
    expect(rendezvous.visits, isEmpty);
  });

  test('an answer with no servers keeps the ones there were', () async {
    seed(recovery: pinned());
    fetcher
      ..answers[primaryUrl] = const SubscriptionPayload(body: '<html>parked')
      ..failures[mirrorUrl] = SubscriptionUnreachableFailure(
        url: mirrorUrl,
        cause: 'blocked',
      );

    final result = await useCase(
      outcome: ParseOutcome.empty,
    )(subscriptionId: 'sub-1');

    expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    expect(nodes.replaceCalls, isEmpty);
    expect(fetcher.requests, <Uri>[primaryUrl, mirrorUrl]);
  });

  test('a switch flipped during the download is kept', () async {
    seed(recovery: pinned());
    fetcher
      ..answers[primaryUrl] = SubscriptionPayload(
        body: 'servers',
        manifest: compactOf(manifestJson(seq: 2)),
      )
      ..meanwhile = () {
        final row = subscriptions.stored.single;
        subscriptions.seed(
          row.copyWith(recovery: row.recovery!.copyWith(enabled: false)),
        );
      };

    await useCase()(subscriptionId: 'sub-1');

    final recovery = subscriptions.stored.single.recovery;
    expect(recovery?.seq, 2);
    expect(recovery?.enabled, isFalse);
  });

  test('adding a subscription pins its key too', () async {
    fetcher.answers[primaryUrl] = SubscriptionPayload(
      body: 'servers',
      manifest: compactOf(manifestJson()),
    );
    final add = AddSubscriptionUseCase(
      fetcher: fetcher,
      parser: _BodyParser(servers),
      subscriptions: subscriptions,
      nodes: nodes,
      ids: FixedIdGenerator('sub-new'),
      recovery: RecoveryEngine(
        reader: ManifestReader(verifier: FakeVerifier()),
        rendezvous: rendezvous,
        clock: () => now,
      ),
    );

    await add(url: primaryUrl);

    expect(subscriptions.stored.single.recovery?.id, 'axm');
    expect(rendezvous.visits, isEmpty);
  });
}

/// Answers per address; an address it does not know is unreachable.
class _RoutedFetcher implements SubscriptionFetcher {
  final Map<Uri, SubscriptionPayload> answers = <Uri, SubscriptionPayload>{};
  final Map<Uri, CommyFailure> failures = <Uri, CommyFailure>{};
  final List<Uri> requests = <Uri>[];

  /// Runs once, during the first download.
  void Function()? meanwhile;

  @override
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  }) async {
    requests.add(url);
    final hook = meanwhile;
    meanwhile = null;
    hook?.call();
    final failure = failures[url];
    if (failure != null) {
      return Err<SubscriptionPayload, CommyFailure>(failure);
    }
    final answer = answers[url];
    if (answer == null) {
      return Err<SubscriptionPayload, CommyFailure>(
        SubscriptionUnreachableFailure(url: url, cause: 'unknown host'),
      );
    }
    return Ok<SubscriptionPayload, CommyFailure>(answer);
  }
}

/// Parses every body into [outcome].
class _BodyParser implements LinkParser {
  _BodyParser(this.outcome);

  final ParseOutcome outcome;

  @override
  bool canParse(String input) => true;

  @override
  Result<ParseOutcome, CommyFailure> parse(String input) =>
      Ok<ParseOutcome, CommyFailure>(outcome);

  @override
  Result<String, CommyFailure> toLink(ProxyNode node) =>
      const Err<String, CommyFailure>(ConfigInvalidFailure('no link form'));
}
