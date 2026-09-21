import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/subscription_fakes.dart';

/// A panel routinely lists one server in several of its groups — "Streaming",
/// "Games", "All" — and every entry is the same endpoint under a different
/// name. A node's identity leaves the display name out on purpose, so those
/// entries arrive under one id and the store holds one row for them.
///
/// That collapse is correct. What is not is telling the user the subscription
/// brought in two servers: the import panel is shown once and there is no
/// history to correct the number afterwards.
void main() {
  group('AddSubscriptionUseCase', () {
    test('reports the servers the store gained, not the entries listed',
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

      final result = await useCase(url: _url);

      expect(result.valueOrNull?.importedCount, 1);
      expect(nodes.stored, hasLength(1));
      // The store is handed one row too: the second would only overwrite the
      // row the first one made.
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

      await useCase(url: _url);

      expect(nodes.stored.single.name, 'Games · Frankfurt 07');
    });

    test('a panel with no repeats reports every server it listed', () async {
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[
              buildNode(id: 'de', name: 'Frankfurt 07'),
              buildNode(id: 'nl', name: 'Amsterdam 03', sortIndex: 1),
              buildNode(id: 'pl', name: 'Warsaw 10', sortIndex: 2),
            ],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(url: _url);

      expect(result.valueOrNull?.importedCount, 3);
      expect(
        result.valueOrNull?.outcome.nodes.map((node) => node.name),
        <String>['Frankfurt 07', 'Amsterdam 03', 'Warsaw 10'],
      );
    });

    test('every stored node belongs to the new subscription', () async {
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

      final result = await useCase(url: _url);

      expect(nodes.stored.single.subscriptionId, 'sub-new');
      expect(
        result.valueOrNull?.outcome.nodes.single.subscriptionId,
        'sub-new',
      );
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

      final result = await useCase(url: _url);

      expect(result.valueOrNull?.skippedCount, 1);
      expect(result.valueOrNull?.outcome.failures, <ImportFailure>[skipped]);
    });

    group('a URL the user already has', () {
      test('updates the card they have instead of making a second one',
          () async {
        // Node ids come from the server, so the same server under a new
        // subscription id takes its row with it: a second card would fill up
        // and the first would quietly empty.
        final subscriptions = FakeSubscriptionRepository()
          ..seed(
            Subscription(
              id: 'sub-old',
              name: 'My panel',
              url: Uri.parse('https://panel.example.com/sub/token?f=v2ray'),
              lastUpdatedAt: DateTime.utc(2026, 8),
            ),
          );
        final nodes = RecordingNodeRepository();
        final useCase = _useCase(
          parser: StubLinkParser(
            ParseOutcome(
              nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
            ),
          ),
          nodes: nodes,
          subscriptions: subscriptions,
        );

        // The same account, written the way a share sheet would: a trailing
        // slash, the parameters swapped, a fragment left on the end.
        final result = await useCase(
          url: Uri.parse('https://panel.example.com/sub/token/?f=v2ray#main'),
        );

        expect(result.valueOrNull?.updatedExisting, isTrue);
        expect(subscriptions.stored, hasLength(1));
        expect(subscriptions.stored.single.id, 'sub-old');
        expect(nodes.stored.single.subscriptionId, 'sub-old');
      });

      test('keeps the name the user gave that card', () async {
        final subscriptions = FakeSubscriptionRepository()
          ..seed(
            Subscription(
              id: 'sub-old',
              name: 'Work',
              url: _url,
              lastUpdatedAt: DateTime.utc(2026, 8),
            ),
          );
        final useCase = _useCase(
          parser: StubLinkParser(
            ParseOutcome(
              nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
            ),
          ),
          nodes: RecordingNodeRepository(),
          subscriptions: subscriptions,
        );

        await useCase(url: _url);

        expect(subscriptions.stored.single.name, 'Work');
      });

      test('a second account on the same panel is still its own card',
          () async {
        final subscriptions = FakeSubscriptionRepository()
          ..seed(
            Subscription(
              id: 'sub-old',
              name: 'Alice',
              url: Uri.parse('https://alice@panel.example.com/sub/t'),
              lastUpdatedAt: DateTime.utc(2026, 8),
            ),
          );
        final useCase = _useCase(
          parser: StubLinkParser(
            ParseOutcome(
              nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
            ),
          ),
          nodes: RecordingNodeRepository(),
          subscriptions: subscriptions,
        );

        final result = await useCase(
          url: Uri.parse('https://bob@panel.example.com/sub/t'),
        );

        expect(result.valueOrNull?.updatedExisting, isFalse);
        expect(subscriptions.stored, hasLength(2));
      });

      test('the interval the user picked is applied, not silently dropped',
          () async {
        // The defect this closes: `applyTo` keeps the stored interval, and the
        // caller only wrote the picked one when the stored one was null — so
        // on a second add the switch beside it worked and it did not.
        final subscriptions = FakeSubscriptionRepository()
          ..seed(
            Subscription(
              id: 'sub-old',
              name: 'My panel',
              url: _url,
              updateIntervalHours: 24,
              lastUpdatedAt: DateTime.utc(2026, 8),
            ),
          );
        final useCase = _useCase(
          parser: StubLinkParser(
            ParseOutcome(
              nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
            ),
          ),
          nodes: RecordingNodeRepository(),
          subscriptions: subscriptions,
        );

        await useCase(url: _url, intervalHours: 6, autoUpdate: true);

        expect(subscriptions.stored.single.updateIntervalHours, 6);
        expect(subscriptions.stored.single.autoUpdate, isTrue);
      });

      test('the panel still wins when it declares one in this response',
          () async {
        final subscriptions = FakeSubscriptionRepository();
        final useCase = _useCase(
          parser: StubLinkParser(
            ParseOutcome(
              nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
            ),
          ),
          nodes: RecordingNodeRepository(),
          subscriptions: subscriptions,
          fetcher: StubSubscriptionFetcher(
            const SubscriptionPayload(
              body: 'vless://...',
              updateIntervalHours: 12,
            ),
          ),
        );

        await useCase(url: _url, intervalHours: 6);

        expect(subscriptions.stored.single.updateIntervalHours, 12);
      });
    });

    test('a stored URL the keystore lost stops the add rather than guessing',
        () async {
      // The placeholder a row falls back to could be this very subscription.
      // Guessing "new" would re-parent its servers onto a second card, and
      // the user would find the one they had gone empty.
      final subscriptions = FakeSubscriptionRepository()
        ..seed(
          Subscription(
            id: 'sub-old',
            name: 'My panel',
            url: Uri.parse('https://panel.example.com/redacted'),
            lastUpdatedAt: DateTime.utc(2026, 8),
          ),
        );
      final nodes = RecordingNodeRepository();
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
          ),
        ),
        nodes: nodes,
        subscriptions: subscriptions,
      );

      final result = await useCase(url: _url);

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(subscriptions.stored, hasLength(1));
      expect(nodes.stored, isEmpty);
    });

    test('a write the store refused is not reported as an import', () async {
      final nodes = RecordingNodeRepository()
        ..failure = const StorageFailure('database is locked');
      final useCase = _useCase(
        parser: StubLinkParser(
          ParseOutcome(
            nodes: <ProxyNode>[buildNode(id: 'de', name: 'Frankfurt 07')],
          ),
        ),
        nodes: nodes,
      );

      final result = await useCase(url: _url);

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(result.valueOrNull, isNull);
    });
  });
}

final Uri _url = Uri.parse('https://panel.example.com/sub/token?f=v2ray');

AddSubscriptionUseCase _useCase({
  required StubLinkParser parser,
  required RecordingNodeRepository nodes,
  FakeSubscriptionRepository? subscriptions,
  StubSubscriptionFetcher? fetcher,
}) {
  return AddSubscriptionUseCase(
    fetcher: fetcher ?? StubSubscriptionFetcher(),
    parser: parser,
    subscriptions: subscriptions ?? FakeSubscriptionRepository(),
    nodes: nodes,
    ids: FixedIdGenerator('sub-new'),
  );
}
