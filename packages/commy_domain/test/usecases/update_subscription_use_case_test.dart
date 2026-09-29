import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/subscription_fakes.dart';

/// A refresh reports the same number a first import does, and for the same
/// reason: the entries a panel lists are not the rows the store keeps. One
/// endpoint in two of the panel's groups is one server, because a node's
/// identity leaves the display name out, and the refresh toast is shown once.
void main() {
  group('UpdateSubscriptionUseCase', () {
    test('reports the servers the store holds, not the entries listed',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.importedCount, 1);
      expect(nodes.stored, hasLength(1));
      expect(nodes.replaceCalls.single, hasLength(1));
    });

    test('the entry that survives is the one a write would have left',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      await useCase(subscriptionId: 'sub-1');

      expect(nodes.stored.single.name, 'Games · Frankfurt 07');
    });

    test('a refresh with no repeats reports every server', () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'de', name: 'Frankfurt 07'),
              buildNode(id: 'nl', name: 'Amsterdam 03', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.importedCount, 2);
      expect(nodes.replaceCalls.single, hasLength(2));
    });

    test('the refreshed nodes stay with the subscription they came from',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(nodes.stored.single.subscriptionId, 'sub-1');
      expect(result.valueOrNull?.outcome.nodes.single.subscriptionId, 'sub-1');
    });

    test('collapsing repeats leaves the skipped entries alone', () async {
      const skipped = ImportFailure(
        rawLine: 'ss://truncated-line',
        reason: 'not a link',
      );
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'same', name: 'Frankfurt 07'),
              buildNode(id: 'same', name: 'Games · Frankfurt 07', sortIndex: 1),
            ],
            failures: const <ImportFailure>[skipped],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.valueOrNull?.skippedCount, 1);
      expect(result.valueOrNull?.outcome.failures, <ImportFailure>[skipped]);
    });

    test('an unknown subscription is refused before anything is written',
        () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'no-such-id');

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
      expect(nodes.replaceCalls, isEmpty);
    });
  });

  group('a refresh that outlives its subscription', () {
    Subscription subscription({String token = 'token'}) => Subscription(
          id: 'sub-1',
          name: 'Example panel',
          url: Uri.parse('https://panel.example.com/sub/$token'),
          autoUpdate: true,
        );

    test('deleted while the panel was answering: nothing comes back', () async {
      final subscriptions = FakeSubscriptionRepository()..seed(subscription());
      final nodes = RecordingNodeRepository();
      final useCase = UpdateSubscriptionUseCase(
        fetcher: MeanwhileFetcher(() => subscriptions.deleteById('sub-1')),
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt')],
          ),
        ),
        subscriptions: subscriptions,
        nodes: nodes,
      );

      final result = await useCase(subscriptionId: 'sub-1');

      expect(result.isErr, isTrue);
      expect(subscriptions.stored, isEmpty);
      expect(nodes.stored, isEmpty);
    });

    test(
        'replaced from a backup while the panel was answering: the '
        'restored one stays', () async {
      final subscriptions = FakeSubscriptionRepository()..seed(subscription());
      final restored = subscription(token: 'restored');
      final nodes = RecordingNodeRepository();
      final useCase = UpdateSubscriptionUseCase(
        fetcher: MeanwhileFetcher(() => subscriptions.upsert(restored)),
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt')],
          ),
        ),
        subscriptions: subscriptions,
        nodes: nodes,
      );

      await useCase(subscriptionId: 'sub-1');

      expect(subscriptions.stored.single.url, restored.url);
      expect(nodes.replaceCalls, isEmpty);
    });
  });

  group('a refresh that outlives an edit', () {
    // The card's menu stays usable while its spinner turns, and on a slow
    // link that is seconds. Whatever the user changed in them is the user's;
    // the refresh brings the panel's half of the row, not the whole row as it
    // was before it set off.
    final original = Subscription(
      id: 'sub-1',
      name: 'Example panel',
      url: Uri.parse('https://panel.example.com/sub/token'),
      autoUpdate: true,
    );
    const answer = SubscriptionPayload(
      body: 'vless://...',
      profileTitle: 'Example VPN',
      userInfo: SubscriptionUserInfo(upload: 1, download: 2, total: 100),
    );

    UpdateSubscriptionUseCase useCase(
      FakeSubscriptionRepository subscriptions,
      Future<void> Function() meanwhile,
    ) {
      return UpdateSubscriptionUseCase(
        fetcher: MeanwhileFetcher(meanwhile, payload: answer),
        parser: StubLinkParser(ParseOutcome.empty),
        subscriptions: subscriptions,
        nodes: RecordingNodeRepository(),
      );
    }

    test('auto-update switched off stays off', () async {
      final subscriptions = FakeSubscriptionRepository()..seed(original);
      final refresh = useCase(
        subscriptions,
        () => subscriptions.upsert(original.copyWith(autoUpdate: false)),
      );

      final result = await refresh(subscriptionId: 'sub-1');

      expect(result.isOk, isTrue);
      expect(subscriptions.stored.single.autoUpdate, isFalse);
      expect(result.valueOrNull?.subscription.autoUpdate, isFalse);
    });

    test('a rename, a collapse and a move all survive', () async {
      final subscriptions = FakeSubscriptionRepository()..seed(original);
      final refresh = useCase(subscriptions, () async {
        await subscriptions.upsert(original.copyWith(name: 'Work'));
        await subscriptions.setCollapsed(id: 'sub-1', isCollapsed: true);
        await subscriptions.reorder(<String>['other', 'sub-1']);
      });

      await refresh(subscriptionId: 'sub-1');

      final stored = subscriptions.stored.single;
      expect(stored.name, 'Work');
      expect(stored.isCollapsed, isTrue);
      expect(stored.sortIndex, 1);
    });

    test("the panel's half of the row is still the panel's", () async {
      final subscriptions = FakeSubscriptionRepository()..seed(original);
      final refresh = useCase(
        subscriptions,
        () => subscriptions.upsert(original.copyWith(name: 'Work')),
      );

      await refresh(subscriptionId: 'sub-1');

      final stored = subscriptions.stored.single;
      expect(stored.profileTitle, 'Example VPN');
      expect(stored.userInfo?.total, 100);
      expect(stored.lastUpdatedAt, isNotNull);
    });
  });
}

UpdateSubscriptionUseCase _useCase({
  required StubLinkParser parser,
  required RecordingNodeRepository nodes,
}) {
  final subscriptions = FakeSubscriptionRepository()
    ..seed(
      Subscription(
        id: 'sub-1',
        name: 'Example panel',
        url: Uri.parse('https://panel.example.com/sub/token?f=v2ray'),
        autoUpdate: true,
      ),
    );
  return UpdateSubscriptionUseCase(
    fetcher: StubSubscriptionFetcher(),
    parser: parser,
    subscriptions: subscriptions,
    nodes: nodes,
  );
}
