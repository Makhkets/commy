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
}) {
  return AddSubscriptionUseCase(
    fetcher: StubSubscriptionFetcher(),
    parser: parser,
    subscriptions: FakeSubscriptionRepository(),
    nodes: nodes,
    ids: FixedIdGenerator('sub-new'),
  );
}
